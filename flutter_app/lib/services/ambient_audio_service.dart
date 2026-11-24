import 'dart:async';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/thermostat_state.dart';
import 'audio_tempo_analyzer.dart';
import 'media_storage_service.dart';
import 'web_audio_decode_bridge.dart';

class AmbientAudioService {
  AmbientAudioService._();

  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _chimePlayer = AudioPlayer();
  static final AudioPlayer _ringPlayer = AudioPlayer();

  static bool _playing = false;
  static bool _paused = false;
  static bool _ringing = false;
  static double _activeVolume = 0.5;
  static Uint8List? _customAudioBytes;
  static bool _listenersAttached = false;

  static Duration _lastKnownPosition = Duration.zero;
  static final Stopwatch _posStopwatch = Stopwatch();
  static AudioSpectrumProfile? _activeProfile;
  static int _sessionToken = 0;
  static final Map<String, AudioSpectrumProfile> _profileCache = {};

  static bool get isPlaying => _playing && !_paused;
  static bool get isPaused => _paused;
  static bool get isRinging => _ringing;
  static AudioSpectrumProfile? get activeProfile => _activeProfile;

  static void _ensureListeners() {
    if (_listenersAttached) return;
    _listenersAttached = true;
    _player.onPositionChanged.listen((pos) {
      _lastKnownPosition = pos;
      if (_playing && !_paused) {
        _posStopwatch
          ..reset()
          ..start();
      }
    });
    _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.stopped || state == PlayerState.completed) {
        if (!_paused) {
          _posStopwatch.stop();
        }
      } else if (state == PlayerState.paused) {
        _paused = true;
        _posStopwatch.stop();
      } else if (state == PlayerState.playing) {
        _paused = false;
        _playing = true;
        _posStopwatch.start();
      }
    });
  }

  static List<double> _smoothedBands = const [];
  static double _smoothedPulse = 0.0;

  static Duration get currentPlaybackPosition {
    if (!_playing) return _lastKnownPosition;
    if (_paused || !_posStopwatch.isRunning) return _lastKnownPosition;
    return _lastKnownPosition + _posStopwatch.elapsed;
  }

  static List<double> currentSpectrumBands({int bandCount = 18}) {
    if (!_playing || _paused || _activeVolume <= 0.005) {
      _smoothedBands = List<double>.filled(bandCount, 0.0);
      return _smoothedBands;
    }
    final target = AudioTempoAnalyzer.sampleBandsAtPosition(
      _activeProfile,
      currentPlaybackPosition,
      playing: true,
      bandCount: bandCount,
      masterGain: (0.62 + _activeVolume * 0.50).clamp(0.45, 1.12),
    );
    if (_smoothedBands.length != target.length) {
      _smoothedBands = List<double>.from(target);
      return _smoothedBands;
    }
    final next = List<double>.filled(target.length, 0.0);
    for (int i = 0; i < target.length; i++) {
      final prev = _smoothedBands[i];
      final cur = target[i];
      final alpha = cur >= prev ? 0.68 : 0.24; // Fast attack on kick/note, smooth decay
      next[i] = (prev + (cur - prev) * alpha).clamp(0.0, 1.0);
    }
    _smoothedBands = next;
    return _smoothedBands;
  }

  static double currentBeatPulse() {
    if (!_playing || _paused || _activeVolume <= 0.005) {
      _smoothedPulse = 0.0;
      return 0.0;
    }
    final target = AudioTempoAnalyzer.beatPulseAtPosition(
      _activeProfile,
      currentPlaybackPosition,
      playing: true,
      masterGain: (0.65 + _activeVolume * 0.45).clamp(0.45, 1.10),
    );
    final alpha = target >= _smoothedPulse ? 0.72 : 0.22;
    _smoothedPulse = (_smoothedPulse + (target - _smoothedPulse) * alpha).clamp(0.0, 1.0);
    return _smoothedPulse;
  }

  static double currentDetectedBpm() {
    if (!_playing || _paused) return 0.0;
    return _activeProfile?.bpm ?? 0.0;
  }

  static void setCustomAudioBytes(Uint8List? bytes) {
    _customAudioBytes = bytes;
    _profileCache.removeWhere((k, _) => k.startsWith('custom_'));
  }

  static AmbientSoundtrack stepPlaylistTrack(
    AmbientSoundtrack current,
    int delta, {
    bool hasCustomAudio = false,
    bool shuffle = false,
  }) {
    final pool = <AmbientSoundtrack>[
      AmbientSoundtrack.fireplaceCrackling,
      AmbientSoundtrack.nightRain,
      AmbientSoundtrack.cozyJazzLofi,
      AmbientSoundtrack.relaxPiano,
      AmbientSoundtrack.deepSpace,
      AmbientSoundtrack.forestBreeze,
      if (hasCustomAudio) AmbientSoundtrack.customMp3,
    ];
    final idx = pool.indexOf(current);
    if (shuffle && pool.length > 1) {
      final seed = DateTime.now().microsecondsSinceEpoch % (pool.length - 1);
      final base = idx < 0 ? 0 : idx;
      return pool[(base + 1 + seed) % pool.length];
    }
    if (idx < 0) return pool.first;
    final nextIdx = ((idx + delta) % pool.length + pool.length) % pool.length;
    return pool[nextIdx];
  }

  /// Synthesizes a seamless 3-second 16-bit mono 22050Hz PCM WAV loop
  /// for each built-in ambient soundtrack so sound & tempo-locked spectrum analysis work 100% offline.
  static Uint8List generateAmbientWavBytes(AmbientSoundtrack track) {
    const sampleRate = 22050;
    const durationSeconds = 3;
    const numSamples = sampleRate * durationSeconds;
    const dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    // Standard RIFF/WAVE header
    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // PCM chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM format
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    buffer.setUint16(32, 2, Endian.little); // Block align
    buffer.setUint16(34, 16, Endian.little); // Bits per sample
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    final rng = math.Random(42 + track.index * 17);
    double lowPass = 0.0;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final loopEnv = 0.5 - 0.5 * math.cos((i / numSamples) * math.pi * 2);
      final white = rng.nextDouble() * 2.0 - 1.0;
      double sample = 0.0;

      switch (track) {
        case AmbientSoundtrack.silent:
          sample = 0.0;
          break;
        case AmbientSoundtrack.fireplaceCrackling:
          lowPass = lowPass * 0.955 + white * 0.045;
          // Rhythmic ember swells + crisp crackling transients
          final crackWindow = (t * 2.666) % 1.0;
          final crackleBurst = crackWindow < 0.045 ? math.exp(-crackWindow * 85.0) * white * 0.72 : 0.0;
          final subtlePop = (i % 4100 < 22 && rng.nextDouble() > 0.62) ? white * 0.48 : 0.0;
          final warmth = math.sin(2 * math.pi * 110 * t) * (0.06 + 0.05 * math.sin(2 * math.pi * 1.333 * t));
          sample = lowPass * 2.5 + crackleBurst + subtlePop + warmth;
          break;
        case AmbientSoundtrack.nightRain:
          lowPass = lowPass * 0.84 + white * 0.16;
          final rainPulse = 0.72 + 0.28 * math.sin(2 * math.pi * (t / 1.5));
          final dropStep = (t * 2.0) % 1.0;
          final dropPlink = math.exp(-dropStep * 14.0) * math.sin(2 * math.pi * 1480.0 * t) * 0.10;
          sample = lowPass * 1.48 * rainPulse + dropPlink;
          break;
        case AmbientSoundtrack.cozyJazzLofi:
          // 80 BPM exact 4-beat bar in 3.0s (beatPeriod = 0.75s)
          const beatLen = 0.75;
          final beatPhase = t % beatLen;
          final barIdx = (t / beatLen).floor().clamp(0, 3);
          // Warm sub kick on beats 0 & 2
          final kickActive = (barIdx == 0 || barIdx == 2);
          final kickPitch = 52.0 + 68.0 * math.exp(-beatPhase * 28.0);
          final kick = kickActive ? math.sin(2 * math.pi * kickPitch * beatPhase) * math.exp(-beatPhase * 9.5) * 0.48 : 0.0;
          // Soft brush transient on beats 1 & 3
          final snareActive = (barIdx == 1 || barIdx == 3);
          final snare = snareActive ? white * math.exp(-beatPhase * 24.0) * 0.22 : 0.0;
          // Rhodes chord progression cycling warmly per beat
          const roots = [174.61, 220.00, 196.00, 164.81];
          final root = roots[barIdx];
          final chord = math.sin(2 * math.pi * root * t) * 0.26 +
              math.sin(2 * math.pi * (root * 1.25) * t) * 0.20 +
              math.sin(2 * math.pi * (root * 1.5) * t) * 0.17;
          final chordEnv = 0.45 + 0.55 * math.exp(-beatPhase * 2.2);
          lowPass = lowPass * 0.90 + white * 0.10;
          sample = kick + snare + chord * chordEnv + lowPass * 0.09;
          break;
        case AmbientSoundtrack.relaxPiano:
          // 80 BPM crisp piano arpeggio: C4 -> E4 -> G4 -> B4 -> C5 -> G4
          const notes = [261.63, 329.63, 392.00, 493.88, 523.25, 392.00];
          final segLen = durationSeconds / notes.length; // 0.50s each (120 BPM eighth feel)
          final segIdx = (t / segLen).floor().clamp(0, notes.length - 1);
          final localT = t - segIdx * segLen;
          final attack = (localT / 0.015).clamp(0.0, 1.0);
          final decay = math.exp(-localT * 4.2);
          final f = notes[segIdx];
          final bell = math.sin(2 * math.pi * f * t) * 0.55 +
              math.sin(4 * math.pi * f * t) * 0.20 +
              math.sin(2 * math.pi * (f * 0.5) * t) * 0.24;
          sample = bell * attack * decay * 0.62;
          break;
        case AmbientSoundtrack.deepSpace:
          final pulse = 0.45 + 0.55 * math.pow(0.5 - 0.5 * math.cos(2 * math.pi * t), 1.5);
          final drone = math.sin(2 * math.pi * 108.0 * t) * 0.46 +
              math.sin(2 * math.pi * 216.0 * t) * 0.26 +
              math.sin(2 * math.pi * 432.0 * t) * 0.14;
          sample = drone * pulse;
          break;
        case AmbientSoundtrack.forestBreeze:
          lowPass = lowPass * 0.93 + white * 0.07;
          final swell = 0.35 + 0.65 * loopEnv;
          final chirpSlot = (t / 0.75) % 1.0;
          final birdGate = chirpSlot < 0.18 ? math.sin((chirpSlot / 0.18) * math.pi) : 0.0;
          final birdFreq = 1850.0 + chirpSlot * 2400.0;
          final birdShimmer = math.sin(2 * math.pi * birdFreq * t) * 0.20 * birdGate;
          sample = lowPass * (1.05 + 0.95 * swell) + birdShimmer;
          break;
        case AmbientSoundtrack.customMp3:
          final pulse = 0.5 + 0.5 * math.exp(-((t * 1.5) % 1.0) * 5.0);
          sample = (math.sin(2 * math.pi * 220.0 * t) + math.sin(2 * math.pi * 330.0 * t) * 0.5) * 0.32 * pulse;
          break;
      }

      final edgeFade = i < 400
          ? i / 400.0
          : (i > numSamples - 400 ? (numSamples - i) / 400.0 : 1.0);
      final pcm = (sample * edgeFade * 16500).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  static bool canPlayCustomAudio(String customSource) {
    final trimmed = customSource.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return true;
    if (MediaStorageService.isPersistedKey(trimmed)) {
      return _customAudioBytes != null || MediaStorageService.getCachedBytes(trimmed) != null;
    }
    if (kIsWeb) return _customAudioBytes != null;
    return trimmed.isNotEmpty;
  }

  static Future<void> _loadCustomAudioSpectrum({
    required int token,
    required AmbientSoundtrack track,
    required String source,
    required Uint8List? customBytes,
  }) async {
    final cacheKey = 'custom_${source}_${customBytes?.length ?? 0}';
    final cached = _profileCache[cacheKey];
    if (cached != null) {
      if (_sessionToken == token) _activeProfile = cached;
      return;
    }

    // Immediate beat-locked placeholder until offline Web Audio / WAV decode completes
    _activeProfile = AudioTempoAnalyzer.buildFallbackBeatProfile(
      track: track,
      customLabel: source,
    );

    final decoded = await WebAudioDecodeBridge.decodeAndAnalyze(
      bytes: customBytes,
      source: source,
    );
    if (decoded != null && !decoded.isEmpty) {
      _profileCache[cacheKey] = decoded;
      if (_sessionToken == token) {
        _activeProfile = decoded;
      }
    }
  }

  static Future<void> start({
    required AmbientSoundtrack track,
    required String customSource,
    required double volume,
  }) async {
    _ensureListeners();
    final token = ++_sessionToken;
    _activeVolume = volume.clamp(0.0, 1.0);
    _lastKnownPosition = Duration.zero;
    _posStopwatch
      ..reset()
      ..stop();

    try {
      await _player.stop();
      if (track != AmbientSoundtrack.customMp3 || volume <= 0.005) {
        _playing = false;
        _paused = false;
        _activeProfile = null;
        return;
      }

      final trimmed = customSource.trim();
      final isHttpUrl = trimmed.startsWith('http://') || trimmed.startsWith('https://');
      if (!isHttpUrl && _customAudioBytes == null && MediaStorageService.isPersistedKey(trimmed)) {
        final loaded = await MediaStorageService.loadBytes(trimmed);
        if (loaded != null && loaded.isNotEmpty) {
          _customAudioBytes = loaded;
        }
      } else if (!isHttpUrl && !kIsWeb && _customAudioBytes == null && trimmed.isNotEmpty) {
        final loaded = MediaStorageService.getCachedBytes(trimmed);
        if (loaded != null && loaded.isNotEmpty) {
          _customAudioBytes = loaded;
        }
      }
      if (_sessionToken != token) return;

      final hasWebBytes = kIsWeb && _customAudioBytes != null;
      final hasNativeFile = !kIsWeb && trimmed.isNotEmpty && !MediaStorageService.isPersistedKey(trimmed);

      if (!isHttpUrl && !hasWebBytes && !hasNativeFile) {
        _playing = false;
        _paused = false;
        _activeProfile = null;
        return;
      }

      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(_activeVolume);

      if (isHttpUrl) {
        unawaited(_loadCustomAudioSpectrum(
          token: token,
          track: track,
          source: trimmed,
          customBytes: null,
        ));
        await _player.play(UrlSource(trimmed));
      } else if (hasWebBytes) {
        final bytes = _customAudioBytes!;
        unawaited(_loadCustomAudioSpectrum(
          token: token,
          track: track,
          source: trimmed,
          customBytes: bytes,
        ));
        await _player.play(BytesSource(bytes));
      } else {
        unawaited(_loadCustomAudioSpectrum(
          token: token,
          track: track,
          source: trimmed,
          customBytes: null,
        ));
        await _player.play(DeviceFileSource(trimmed));
      }

      if (_sessionToken == token) {
        _playing = true;
        _paused = false;
        _posStopwatch
          ..reset()
          ..start();
      }
    } catch (_) {
      _playing = false;
      _paused = false;
      _posStopwatch.stop();
    }
  }

  static Future<void> pause() async {
    if (!_playing || _paused) return;
    _lastKnownPosition = currentPlaybackPosition;
    _posStopwatch.stop();
    _paused = true;
    try {
      await _player.pause();
    } catch (_) {}
  }

  static Future<void> resume() async {
    if (!_playing || !_paused) return;
    _paused = false;
    _posStopwatch
      ..reset()
      ..start();
    try {
      await _player.resume();
    } catch (_) {}
  }

  static Future<void> setVolume(double volume) async {
    _activeVolume = volume.clamp(0.0, 1.0);
    try {
      await _player.setVolume(_activeVolume);
    } catch (_) {}
  }

  static Future<void> stop() async {
    _sessionToken++;
    _playing = false;
    _paused = false;
    _lastKnownPosition = Duration.zero;
    _posStopwatch
      ..reset()
      ..stop();
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Generates a clean two-note PCM WAV notification chime (22050Hz 16-bit mono).
  static Uint8List generateChimeWavBytes({bool urgent = false}) {
    const sampleRate = 22050;
    const totalMs = 420;
    const numSamples = (sampleRate * totalMs) ~/ 1000;
    const dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    final f1 = urgent ? 784.0 : 587.33;
    final f2 = urgent ? 1046.5 : 880.0;
    final split = numSamples ~/ 2;

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final isSecond = i >= split;
      final localIdx = isSecond ? i - split : i;
      final localLen = isSecond ? (numSamples - split) : split;
      final env = math.sin((localIdx / localLen) * math.pi);
      final freq = isSecond ? f2 : f1;
      final sample = (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t)) * env * 0.42;
      final pcm = (sample * 18000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  static Future<void> playNotificationChime({bool urgent = false}) async {
    try {
      await _chimePlayer.stop();
      await _chimePlayer.setReleaseMode(ReleaseMode.release);
      await _chimePlayer.setVolume(0.75);
      await _chimePlayer.play(BytesSource(generateChimeWavBytes(urgent: urgent)));
    } catch (_) {}
  }

  /// Generates a character-specific offline 16-bit PCM WAV chirp/purr/chime
  /// for each virtual assistant mascot (works 100% offline on Android & Web).
  static Uint8List generateMascotSoundWavBytes(
    MascotCharacter character, {
    bool sleepy = false,
  }) {
    const sampleRate = 22050;
    const totalMs = 360;
    const numSamples = (sampleRate * totalMs) ~/ 1000;
    const dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);

    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < numSamples; i++) {
      final p = i / numSamples;
      final t = i / sampleRate;
      final env = math.sin(p * math.pi);
      double sample = 0.0;

      if (sleepy) {
        final f = 360.0 - p * 140.0;
        sample = math.sin(2 * math.pi * f * t) * env * 0.30;
      } else {
        switch (character) {
          case MascotCharacter.termoBot:
            // Retro dual-step robot bleep
            final f = p < 0.45 ? 660.0 : 990.0;
            sample = (math.sin(2 * math.pi * f * t) + 0.25 * math.sin(6 * math.pi * f * t)) * env * 0.34;
            break;
          case MascotCharacter.mirnav:
            // Soft rising cat chirp + gentle 26Hz purr LFO
            final purr = 0.7 + 0.3 * math.sin(2 * math.pi * 26.0 * t);
            final f = 440.0 + math.sin(p * math.pi) * 260.0;
            sample = math.sin(2 * math.pi * f * t) * env * purr * 0.38;
            break;
          case MascotCharacter.puki:
            // Playful quick double-hop bunny boing
            final hopEnv = math.sin((p * 2.0 % 1.0) * math.pi);
            final f = 580.0 + p * 380.0;
            sample = math.sin(2 * math.pi * f * t) * hopEnv * 0.38;
            break;
          case MascotCharacter.mert:
            // Warm friendly male assistant two-tone fifth
            final f = p < 0.5 ? 392.0 : 523.25;
            sample = (math.sin(2 * math.pi * f * t) * 0.75 + math.sin(4 * math.pi * f * t) * 0.20) * env * 0.36;
            break;
          case MascotCharacter.ela:
            // Bright soft bell harmonic chord
            final f = p < 0.5 ? 659.25 : 880.0;
            sample = (math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * 1318.5 * t)) * env * 0.32;
            break;
        }
      }

      final pcm = (sample * 18000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  static Future<void> playMascotSound(
    MascotCharacter character, {
    bool sleepy = false,
  }) async {
    try {
      await _chimePlayer.stop();
      await _chimePlayer.setReleaseMode(ReleaseMode.release);
      await _chimePlayer.setVolume(0.65);
      await _chimePlayer.play(BytesSource(generateMascotSoundWavBytes(character, sleepy: sleepy)));
    } catch (_) {}
  }

  static ByteData _createWavBuffer(int numSamples, {int sampleRate = 22050}) {
    final dataSize = numSamples * 2;
    final buffer = ByteData(44 + dataSize);
    void writeAscii(int offset, String text) {
      for (int i = 0; i < text.length; i++) {
        buffer.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1, Endian.little);
    buffer.setUint16(22, 1, Endian.little);
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2, Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);
    return buffer;
  }

  /// Synthesizes a 2.0-second smartphone incoming ringtone WAV loop (harmonic cadence + pause).
  static Uint8List generateRingtoneWavBytes({bool urgent = false}) {
    const sampleRate = 22050;
    const durationMs = 2000;
    const numSamples = (sampleRate * durationMs) ~/ 1000;
    final buffer = _createWavBuffer(numSamples, sampleRate: sampleRate);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      double env = 0.0;
      double baseFreq = 659.25;
      double harmonyFreq = 987.77;

      if (urgent) {
        if (t < 0.22) {
          env = math.sin((t / 0.22) * math.pi);
          baseFreq = 783.99;
          harmonyFreq = 1174.66;
        } else if (t >= 0.30 && t < 0.52) {
          env = math.sin(((t - 0.30) / 0.22) * math.pi);
          baseFreq = 880.0;
          harmonyFreq = 1318.51;
        } else if (t >= 0.60 && t < 0.86) {
          env = math.sin(((t - 0.60) / 0.26) * math.pi);
          baseFreq = 1046.50;
          harmonyFreq = 1567.98;
        }
      } else {
        if (t < 0.28) {
          env = math.sin((t / 0.28) * math.pi);
          baseFreq = 587.33;
          harmonyFreq = 880.0;
        } else if (t >= 0.36 && t < 0.74) {
          env = math.sin(((t - 0.36) / 0.38) * math.pi);
          baseFreq = 783.99;
          harmonyFreq = 1174.66;
        }
      }

      final shimmer = 0.85 + 0.15 * math.sin(2 * math.pi * 14.0 * t);
      final tone = (math.sin(2 * math.pi * baseFreq * t) * 0.62 +
              math.sin(2 * math.pi * harmonyFreq * t) * 0.28 +
              math.sin(2 * math.pi * baseFreq * 2.0 * t) * 0.10) *
          env *
          shimmer *
          0.50;
      final pcm = (tone * 20000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  /// Generates a crisp call-connect (answered) or call-end (hangup) tone WAV.
  static Uint8List generateCallChimeWavBytes({required bool answered}) {
    const sampleRate = 22050;
    const totalMs = 340;
    const numSamples = (sampleRate * totalMs) ~/ 1000;
    final buffer = _createWavBuffer(numSamples, sampleRate: sampleRate);

    for (int i = 0; i < numSamples; i++) {
      final p = i / numSamples;
      final t = i / sampleRate;
      final env = math.sin(p * math.pi);
      final freq = answered
          ? (p < 0.45 ? 523.25 : 783.99)
          : (p < 0.45 ? 587.33 : 392.00);
      final tone = (math.sin(2 * math.pi * freq * t) + 0.25 * math.sin(4 * math.pi * freq * t)) * env * 0.38;
      final pcm = (tone * 18000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  /// Generates a soft 3-syllable assistant briefing acoustic cue WAV when call is answered.
  static Uint8List generateVoiceBriefCueWavBytes() {
    const sampleRate = 22050;
    const totalMs = 720;
    const numSamples = (sampleRate * totalMs) ~/ 1000;
    final buffer = _createWavBuffer(numSamples, sampleRate: sampleRate);

    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final p = i / numSamples;
      double freq = 440.0;
      double localEnv = 0.0;
      if (p < 0.30) {
        freq = 440.0;
        localEnv = math.sin((p / 0.30) * math.pi);
      } else if (p < 0.62) {
        freq = 554.37;
        localEnv = math.sin(((p - 0.30) / 0.32) * math.pi);
      } else {
        freq = 659.25;
        localEnv = math.sin(((p - 0.62) / 0.38) * math.pi);
      }
      final tone = (math.sin(2 * math.pi * freq * t) * 0.72 +
              math.sin(2 * math.pi * freq * 1.5 * t) * 0.20) *
          localEnv *
          0.34;
      final pcm = (tone * 18000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  static Future<void> startRingtone({bool urgent = false, double volume = 0.85}) async {
    try {
      await _ringPlayer.stop();
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.setVolume(volume.clamp(0.1, 1.0));
      await _ringPlayer.play(BytesSource(generateRingtoneWavBytes(urgent: urgent)));
      _ringing = true;
    } catch (_) {
      _ringing = false;
    }
  }

  static Future<void> stopRingtone() async {
    try {
      await _ringPlayer.stop();
    } catch (_) {}
    _ringing = false;
  }

  static Future<void> playCallChime({required bool answered}) async {
    try {
      await _chimePlayer.stop();
      await _chimePlayer.setReleaseMode(ReleaseMode.release);
      await _chimePlayer.setVolume(0.75);
      await _chimePlayer.play(BytesSource(generateCallChimeWavBytes(answered: answered)));
    } catch (_) {}
  }

  static Future<void> playVoiceBriefCue() async {
    try {
      await _chimePlayer.stop();
      await _chimePlayer.setReleaseMode(ReleaseMode.release);
      await _chimePlayer.setVolume(0.68);
      await _chimePlayer.play(BytesSource(generateVoiceBriefCueWavBytes()));
    } catch (_) {}
  }
}
