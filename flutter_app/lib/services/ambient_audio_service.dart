import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/thermostat_state.dart';

class AmbientAudioService {
  AmbientAudioService._();

  static final AudioPlayer _player = AudioPlayer();
  static final AudioPlayer _chimePlayer = AudioPlayer();
  static final AudioPlayer _ringPlayer = AudioPlayer();
  static bool _playing = false;
  static bool _ringing = false;
  static Uint8List? _customAudioBytes;

  static bool get isPlaying => _playing;
  static bool get isRinging => _ringing;

  static void setCustomAudioBytes(Uint8List? bytes) {
    _customAudioBytes = bytes;
  }

  /// Synthesizes a seamless 3-second 16-bit mono 22050Hz PCM WAV loop
  /// for each built-in ambient soundtrack so sound works 100% offline.
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
          lowPass = lowPass * 0.96 + white * 0.04;
          final pop = (i % 3400 < 18 && rng.nextDouble() > 0.7) ? white * 0.55 : 0.0;
          final warmth = math.sin(2 * math.pi * 110 * t) * 0.08;
          sample = (lowPass * 2.6 + pop + warmth);
          break;
        case AmbientSoundtrack.nightRain:
          lowPass = lowPass * 0.84 + white * 0.16;
          sample = lowPass * 1.45 * (0.85 + 0.15 * math.sin(2 * math.pi * 0.33 * t));
          break;
        case AmbientSoundtrack.cozyJazzLofi:
          final chord = math.sin(2 * math.pi * 174.61 * t) * 0.32 +
              math.sin(2 * math.pi * 220.00 * t) * 0.25 +
              math.sin(2 * math.pi * 261.63 * t) * 0.22 +
              math.sin(2 * math.pi * 329.63 * t) * 0.16;
          lowPass = lowPass * 0.90 + white * 0.10;
          sample = chord * (0.55 + 0.45 * loopEnv) + lowPass * 0.14;
          break;
        case AmbientSoundtrack.relaxPiano:
          const notes = [261.63, 329.63, 392.00, 493.88];
          final segLen = durationSeconds / notes.length;
          final segIdx = (t / segLen).floor().clamp(0, notes.length - 1);
          final localT = t - segIdx * segLen;
          final decay = math.exp(-localT * 2.6);
          final f = notes[segIdx];
          final bell = math.sin(2 * math.pi * f * t) * 0.55 +
              math.sin(4 * math.pi * f * t) * 0.18 +
              math.sin(2 * math.pi * (f * 0.5) * t) * 0.22;
          sample = bell * decay * 0.55;
          break;
        case AmbientSoundtrack.deepSpace:
          final drone = math.sin(2 * math.pi * 108.0 * t) * 0.45 +
              math.sin(2 * math.pi * 216.0 * t) * 0.25 +
              math.sin(2 * math.pi * 432.0 * t) * 0.14;
          sample = drone * (0.65 + 0.35 * math.sin(2 * math.pi * (t / durationSeconds)));
          break;
        case AmbientSoundtrack.forestBreeze:
          lowPass = lowPass * 0.93 + white * 0.07;
          final swell = 0.5 + 0.5 * math.sin(2 * math.pi * (t / durationSeconds));
          final birdShimmer = math.sin(2 * math.pi * 528.0 * t) * 0.05 * swell;
          sample = lowPass * (1.2 + 0.9 * swell) + birdShimmer;
          break;
        case AmbientSoundtrack.customMp3:
          sample = (math.sin(2 * math.pi * 220.0 * t) + math.sin(2 * math.pi * 330.0 * t) * 0.5) * 0.28;
          break;
      }

      final edgeFade = i < 400
          ? i / 400.0
          : (i > numSamples - 400 ? (numSamples - i) / 400.0 : 1.0);
      final pcm = (sample * edgeFade * 16000).round().clamp(-32767, 32767);
      buffer.setInt16(44 + i * 2, pcm, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  static Future<void> start({
    required AmbientSoundtrack track,
    required String customSource,
    required double volume,
  }) async {
    try {
      await _player.stop();
      if (track == AmbientSoundtrack.silent || volume <= 0.005) {
        _playing = false;
        return;
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(volume.clamp(0.0, 1.0));

      final trimmed = customSource.trim();
      if (track == AmbientSoundtrack.customMp3) {
        if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
          await _player.play(UrlSource(trimmed));
        } else if (kIsWeb && _customAudioBytes != null) {
          await _player.play(BytesSource(_customAudioBytes!));
        } else if (!kIsWeb && trimmed.isNotEmpty) {
          await _player.play(DeviceFileSource(trimmed));
        } else {
          await _player.play(BytesSource(generateAmbientWavBytes(track)));
        }
      } else {
        final wavBytes = generateAmbientWavBytes(track);
        await _player.play(BytesSource(wavBytes));
      }
      _playing = true;
    } catch (_) {
      _playing = false;
    }
  }

  static Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume.clamp(0.0, 1.0));
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    _playing = false;
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
        // Brisk triple alert ring: 0-0.22s, 0.30-0.52s, 0.60-0.86s
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
        // Warm smartphone dual-pulse marimba ring: 0-0.28s, 0.36-0.74s
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
