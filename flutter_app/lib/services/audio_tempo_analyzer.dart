import 'dart:math' as math;
import 'dart:typed_data';
import '../models/thermostat_state.dart';

class AudioSpectrumProfile {
  final double bpm;
  final int framesPerSecond;
  final double durationSeconds;
  final int bandCount;
  final List<List<double>> frames;
  final List<double> beatEnvelope;
  final bool fromRealAudioPcm;

  const AudioSpectrumProfile({
    required this.bpm,
    required this.framesPerSecond,
    required this.durationSeconds,
    required this.bandCount,
    required this.frames,
    required this.beatEnvelope,
    required this.fromRealAudioPcm,
  });

  bool get isEmpty => frames.isEmpty || durationSeconds <= 0.0;
}

class ParsedWavPcm {
  final int sampleRate;
  final Float64List monoSamples;

  const ParsedWavPcm({
    required this.sampleRate,
    required this.monoSamples,
  });
}

/// Pure-Dart DSP spectrum & tempo analyzer.
/// Extracts 18 log-spaced frequency bands + rhythmic beat transients + BPM
/// directly from decoded PCM samples or WAV bytes so the Smart Display
/// equalizer moves strictly in sync with actual music playback.
class AudioTempoAnalyzer {
  AudioTempoAnalyzer._();

  static const List<double> _defaultCentersHz = [
    60.0,
    82.0,
    110.0,
    148.0,
    196.0,
    262.0,
    349.0,
    466.0,
    622.0,
    830.0,
    1108.0,
    1480.0,
    1975.0,
    2637.0,
    3520.0,
    4186.0,
    4978.0,
    5920.0,
  ];

  static ParsedWavPcm? parseWavBytes(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (bytes[0] != 0x52 || bytes[1] != 0x49 || bytes[2] != 0x46 || bytes[3] != 0x46) {
      return null; // Not 'RIFF'
    }
    if (bytes[8] != 0x57 || bytes[9] != 0x41 || bytes[10] != 0x56 || bytes[11] != 0x45) {
      return null; // Not 'WAVE'
    }

    final bd = ByteData.sublistView(bytes);
    int offset = 12;
    int audioFormat = 1;
    int channels = 1;
    int sampleRate = 22050;
    int bitsPerSample = 16;
    int? dataStart;
    int dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final c0 = bytes[offset];
      final c1 = bytes[offset + 1];
      final c2 = bytes[offset + 2];
      final c3 = bytes[offset + 3];
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;

      if (c0 == 0x66 && c1 == 0x6D && c2 == 0x74 && c3 == 0x20) {
        // 'fmt '
        if (chunkDataOffset + 16 <= bytes.length) {
          audioFormat = bd.getUint16(chunkDataOffset, Endian.little);
          channels = bd.getUint16(chunkDataOffset + 2, Endian.little).clamp(1, 8);
          sampleRate = bd.getUint32(chunkDataOffset + 4, Endian.little).clamp(4000, 192000);
          bitsPerSample = bd.getUint16(chunkDataOffset + 14, Endian.little);
        }
      } else if (c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61) {
        // 'data'
        dataStart = chunkDataOffset;
        dataSize = math.min(chunkSize, bytes.length - chunkDataOffset);
        break;
      }

      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      offset = chunkDataOffset + paddedSize;
    }

    if (dataStart == null || dataSize <= 0 || (audioFormat != 1 && audioFormat != 3)) {
      return null;
    }

    final bytesPerSample = (bitsPerSample ~/ 8).clamp(1, 4);
    final frameBytes = bytesPerSample * channels;
    if (frameBytes <= 0) return null;
    final sampleCount = dataSize ~/ frameBytes;
    if (sampleCount <= 0) return null;

    final mono = Float64List(sampleCount);
    for (int i = 0; i < sampleCount; i++) {
      double acc = 0.0;
      final base = dataStart + i * frameBytes;
      for (int ch = 0; ch < channels; ch++) {
        final sOff = base + ch * bytesPerSample;
        if (sOff + bytesPerSample > bytes.length) break;
        if (audioFormat == 3 && bitsPerSample == 32) {
          acc += bd.getFloat32(sOff, Endian.little).clamp(-1.0, 1.0);
        } else if (bitsPerSample == 16) {
          acc += bd.getInt16(sOff, Endian.little) / 32768.0;
        } else if (bitsPerSample == 8) {
          acc += (bytes[sOff] - 128) / 128.0;
        } else if (bitsPerSample == 24) {
          int v = bytes[sOff] | (bytes[sOff + 1] << 8) | (bytes[sOff + 2] << 16);
          if ((v & 0x800000) != 0) v |= ~0xFFFFFF;
          acc += v / 8388608.0;
        } else if (bitsPerSample == 32) {
          acc += bd.getInt32(sOff, Endian.little) / 2147483648.0;
        }
      }
      mono[i] = (acc / channels).clamp(-1.0, 1.0);
    }

    return ParsedWavPcm(sampleRate: sampleRate, monoSamples: mono);
  }

  static AudioSpectrumProfile? analyzeWavBytes(
    Uint8List wavBytes, {
    int bandCount = 18,
    int framesPerSecond = 25,
  }) {
    final parsed = parseWavBytes(wavBytes);
    if (parsed == null) return null;
    return analyzePcmSamples(
      parsed.monoSamples,
      sampleRate: parsed.sampleRate,
      bandCount: bandCount,
      framesPerSecond: framesPerSecond,
    );
  }

  static AudioSpectrumProfile analyzePcmSamples(
    List<double> samples, {
    required int sampleRate,
    int bandCount = 18,
    int framesPerSecond = 25,
  }) {
    final safeRate = sampleRate.clamp(4000, 192000);
    final safeFps = framesPerSecond.clamp(10, 60);
    final safeBands = bandCount.clamp(6, 32);

    if (samples.isEmpty) {
      return AudioSpectrumProfile(
        bpm: 90.0,
        framesPerSecond: safeFps,
        durationSeconds: 0.0,
        bandCount: safeBands,
        frames: const [],
        beatEnvelope: const [],
        fromRealAudioPcm: true,
      );
    }

    final durationSeconds = samples.length / safeRate;
    final hop = math.max(1, (safeRate / safeFps).round());
    final frameCount = math.max(1, (samples.length / hop).ceil());
    final windowSize = math.max(256, math.min(1024, (safeRate * 0.046).round()));
    final halfWin = windowSize ~/ 2;

    // Precompute Hann window + Goertzel coefficients for exact band center frequencies
    final hann = Float64List(windowSize);
    for (int n = 0; n < windowSize; n++) {
      hann[n] = 0.5 * (1.0 - math.cos((2.0 * math.pi * n) / (windowSize - 1)));
    }

    final nyquistSafe = safeRate * 0.44;
    final coeffs = Float64List(safeBands);
    for (int b = 0; b < safeBands; b++) {
      final targetHz = b < _defaultCentersHz.length
          ? _defaultCentersHz[b]
          : 60.0 * math.pow(nyquistSafe / 60.0, b / math.max(1, safeBands - 1));
      final clampedHz = targetHz.clamp(45.0, math.max(90.0, nyquistSafe));
      final omega = 2.0 * math.pi * clampedHz / safeRate;
      coeffs[b] = 2.0 * math.cos(omega);
    }

    final rawFrames = List<List<double>>.generate(
      frameCount,
      (_) => List<double>.filled(safeBands, 0.0),
    );
    final frameEnergy = Float64List(frameCount);
    double globalPeak = 1e-6;

    for (int f = 0; f < frameCount; f++) {
      final centerIdx = math.min(samples.length - 1, f * hop + hop ~/ 2);
      final startIdx = centerIdx - halfWin;

      // Local windowed signal RMS
      double sumSq = 0.0;
      final windowed = Float64List(windowSize);
      for (int n = 0; n < windowSize; n++) {
        final idx = startIdx + n;
        final s = (idx >= 0 && idx < samples.length) ? samples[idx] : 0.0;
        final ws = s * hann[n];
        windowed[n] = ws;
        sumSq += ws * ws;
      }
      frameEnergy[f] = math.sqrt(sumSq / windowSize);

      // Exact Goertzel magnitude across every frequency band
      double bandEnergyWeighted = 0.0;
      for (int b = 0; b < safeBands; b++) {
        final c = coeffs[b];
        double q1 = 0.0;
        double q2 = 0.0;
        for (int n = 0; n < windowSize; n++) {
          final q0 = c * q1 - q2 + windowed[n];
          q2 = q1;
          q1 = q0;
        }
        final power = (q1 * q1 + q2 * q2 - q1 * q2 * c).abs();
        final mag = math.sqrt(power) / (windowSize * 0.5);
        // Gentle treble boost so natural pink-noise / acoustic rolloff still sparkles cleanly
        final tilt = 1.0 + (b / safeBands) * 0.85;
        final val = mag * tilt;
        rawFrames[f][b] = val;
        if (val > globalPeak) globalPeak = val;
        if (b < 6) bandEnergyWeighted += val;
      }
      frameEnergy[f] = frameEnergy[f] * 0.55 + (bandEnergyWeighted / 6.0) * 0.45;
    }

    // Per-frame normalization mixed with global peak so dynamic beats & transients breathe clearly
    final normFrames = List<List<double>>.generate(frameCount, (f) {
      final row = rawFrames[f];
      return List<double>.generate(safeBands, (b) {
        final ratio = (row[b] / globalPeak).clamp(0.0, 1.0);
        // Gamma 0.58 emphasizes real note attacks while preventing noise floor from saturating
        final perceptual = math.pow(ratio, 0.58).toDouble();
        return (perceptual * 0.96).clamp(0.0, 1.0);
      });
    });

    // Spectral flux + sub-bass RMS onset detection for beat envelope
    final flux = Float64List(frameCount);
    double maxFlux = 1e-6;
    for (int f = 0; f < frameCount; f++) {
      final prev = f == 0 ? f : f - 1;
      double posDiff = math.max(0.0, frameEnergy[f] - frameEnergy[prev]) * 2.5;
      for (int b = 0; b < safeBands; b++) {
        final d = normFrames[f][b] - normFrames[prev][b];
        if (d > 0) posDiff += d * (b < 5 ? 1.5 : 0.7);
      }
      flux[f] = posDiff + frameEnergy[f] * 0.35;
      if (flux[f] > maxFlux) maxFlux = flux[f];
    }

    final beatEnvelope = List<double>.generate(frameCount, (f) {
      final raw = (flux[f] / maxFlux).clamp(0.0, 1.0);
      return math.pow(raw, 0.75).toDouble();
    });

    // Estimate BPM via autocorrelation on onset flux in [55..175] BPM
    final bpm = _estimateBpmFromFlux(flux, framesPerSecond: safeFps);

    return AudioSpectrumProfile(
      bpm: bpm,
      framesPerSecond: safeFps,
      durationSeconds: durationSeconds,
      bandCount: safeBands,
      frames: normFrames,
      beatEnvelope: beatEnvelope,
      fromRealAudioPcm: true,
    );
  }

  static double _estimateBpmFromFlux(Float64List flux, {required int framesPerSecond}) {
    if (flux.length < framesPerSecond) return 90.0;
    final minLag = math.max(2, (framesPerSecond * 60.0 / 175.0).round());
    final maxLag = math.min(flux.length - 1, (framesPerSecond * 60.0 / 55.0).round());
    if (maxLag <= minLag) return 90.0;

    double mean = 0.0;
    for (final v in flux) {
      mean += v;
    }
    mean /= flux.length;

    int bestLag = minLag;
    double bestCorr = -double.infinity;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double corr = 0.0;
      for (int i = 0; i < flux.length - lag; i++) {
        corr += (flux[i] - mean) * (flux[i + lag] - mean);
      }
      if (corr > bestCorr) {
        bestCorr = corr;
        bestLag = lag;
      }
    }
    final bpm = (framesPerSecond * 60.0 / bestLag).clamp(55.0, 175.0);
    return bpm;
  }

  /// Fallback tempo-locked envelope used ONLY when external cross-origin MP3s
  /// cannot be decoded client-side due to CORS restrictions. Still strictly synced
  /// to real playback position clock & track BPM, and drops cleanly to 0 when paused.
  static AudioSpectrumProfile buildFallbackBeatProfile({
    required AmbientSoundtrack track,
    String customLabel = '',
    int bandCount = 18,
    int framesPerSecond = 25,
  }) {
    final safeBands = bandCount.clamp(6, 32);
    final safeFps = framesPerSecond.clamp(10, 60);
    final double bpm = switch (track) {
      AmbientSoundtrack.silent => 0.0,
      AmbientSoundtrack.cozyJazzLofi => 90.0,
      AmbientSoundtrack.relaxPiano => 80.0,
      AmbientSoundtrack.fireplaceCrackling => 108.0,
      AmbientSoundtrack.nightRain => 96.0,
      AmbientSoundtrack.forestBreeze => 72.0,
      AmbientSoundtrack.deepSpace => 62.0,
      AmbientSoundtrack.customMp3 => customLabel.toLowerCase().contains('chill') ? 86.0 : 112.0,
    };
    if (bpm <= 0.0) {
      return AudioSpectrumProfile(
        bpm: 0.0,
        framesPerSecond: safeFps,
        durationSeconds: 4.0,
        bandCount: safeBands,
        frames: const [],
        beatEnvelope: const [],
        fromRealAudioPcm: false,
      );
    }

    const durationSec = 4.0;
    final frameCount = (durationSec * safeFps).round();
    final frames = <List<double>>[];
    final beats = <double>[];
    final beatsPerSec = bpm / 60.0;

    for (int f = 0; f < frameCount; f++) {
      final t = f / safeFps;
      final beatPos = (t * beatsPerSec) % 1.0;
      final kickDecay = math.exp(-beatPos * 5.2);
      final halfBeatPos = ((t * beatsPerSec) + 0.5) % 1.0;
      final snareDecay = math.exp(-halfBeatPos * 7.0) * 0.72;
      beats.add((kickDecay * 0.85 + snareDecay * 0.45).clamp(0.0, 1.0));

      final row = List<double>.generate(safeBands, (b) {
        final norm = b / math.max(1, safeBands - 1);
        final subWeight = math.max(0.0, 1.0 - norm * 2.2) * kickDecay;
        final midWeight = math.exp(-math.pow((norm - 0.48) * 3.2, 2)) * (0.28 + snareDecay * 0.65);
        final hiStep = ((t * beatsPerSec * 2.0 + norm * 3.0) % 1.0);
        final hiWeight = norm * math.exp(-hiStep * 6.5) * 0.55;
        return (subWeight * 0.92 + midWeight + hiWeight).clamp(0.06, 0.98);
      });
      frames.add(row);
    }

    return AudioSpectrumProfile(
      bpm: bpm,
      framesPerSecond: safeFps,
      durationSeconds: durationSec,
      bandCount: safeBands,
      frames: frames,
      beatEnvelope: beats,
      fromRealAudioPcm: false,
    );
  }

  /// Linearly interpolates the analyzed spectrum bands at exact playback [position].
  /// Always returns all zeros when [playing] is false.
  static List<double> sampleBandsAtPosition(
    AudioSpectrumProfile? profile,
    Duration position, {
    bool playing = true,
    int bandCount = 18,
    double masterGain = 1.0,
  }) {
    final safeBands = bandCount.clamp(6, 32);
    if (!playing || profile == null || profile.frames.isEmpty || profile.durationSeconds <= 0.0) {
      return List<double>.filled(safeBands, 0.0);
    }

    final gain = masterGain.clamp(0.15, 1.15);
    final posSec = (position.inMicroseconds / 1000000.0) % profile.durationSeconds;
    final exactFrame = posSec * profile.framesPerSecond;
    final idx0 = exactFrame.floor() % profile.frames.length;
    final idx1 = (idx0 + 1) % profile.frames.length;
    final frac = exactFrame - exactFrame.floor();

    final row0 = profile.frames[idx0];
    final row1 = profile.frames[idx1];
    return List<double>.generate(safeBands, (b) {
      final srcIdx = ((b / safeBands) * row0.length).floor().clamp(0, row0.length - 1);
      final interpolated = row0[srcIdx] * (1.0 - frac) + row1[srcIdx] * frac;
      return (interpolated * gain).clamp(0.0, 1.0);
    });
  }

  static double beatPulseAtPosition(
    AudioSpectrumProfile? profile,
    Duration position, {
    bool playing = true,
    double masterGain = 1.0,
  }) {
    if (!playing || profile == null || profile.beatEnvelope.isEmpty || profile.durationSeconds <= 0.0) {
      return 0.0;
    }
    final posSec = (position.inMicroseconds / 1000000.0) % profile.durationSeconds;
    final exactFrame = posSec * profile.framesPerSecond;
    final idx0 = exactFrame.floor() % profile.beatEnvelope.length;
    final idx1 = (idx0 + 1) % profile.beatEnvelope.length;
    final frac = exactFrame - exactFrame.floor();
    final v = profile.beatEnvelope[idx0] * (1.0 - frac) + profile.beatEnvelope[idx1] * frac;
    return (v * masterGain.clamp(0.2, 1.1)).clamp(0.0, 1.0);
  }
}
