import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'audio_tempo_analyzer.dart';

/// Browser Web Audio API (`AudioContext.decodeAudioData`) bridge so custom
/// MP3 / M4A / OGG / WAV files uploaded in Chrome/Edge are decoded offline
/// into PCM samples and analyzed for exact tempo, beats, and 18-band spectrum.
class WebAudioDecodeBridge {
  WebAudioDecodeBridge._();

  static Future<AudioSpectrumProfile?> decodeAndAnalyze({
    Uint8List? bytes,
    String source = '',
    int bandCount = 18,
    int framesPerSecond = 25,
  }) async {
    try {
      JSAny? arrayBuffer;
      if (bytes != null && bytes.isNotEmpty) {
        final wavFast = AudioTempoAnalyzer.analyzeWavBytes(
          bytes,
          bandCount: bandCount,
          framesPerSecond: framesPerSecond,
        );
        if (wavFast != null) return wavFast;
        // Slice exact byte view copy into a clean ArrayBuffer for decodeAudioData
        final copied = Uint8List.fromList(bytes);
        arrayBuffer = copied.toJS.getProperty<JSAny?>('buffer'.toJS);
      } else {
        final trimmed = source.trim();
        if (trimmed.startsWith('http://') ||
            trimmed.startsWith('https://') ||
            trimmed.startsWith('blob:')) {
          final fetchPromise = globalContext.callMethod<JSPromise<JSAny?>>('fetch'.toJS, trimmed.toJS);
          final respAny = await fetchPromise.toDart;
          if (respAny != null && respAny.isA<JSObject>()) {
            final resp = respAny as JSObject;
            final okVal = resp.getProperty<JSAny?>('ok'.toJS);
            if (okVal != null && okVal.isA<JSBoolean>() && (okVal as JSBoolean).toDart) {
              final bufPromise = resp.callMethod<JSPromise<JSAny?>>('arrayBuffer'.toJS);
              arrayBuffer = await bufPromise.toDart;
            }
          }
        }
      }

      if (arrayBuffer == null) return null;

      final ctor = globalContext.getProperty<JSFunction?>('AudioContext'.toJS) ??
          globalContext.getProperty<JSFunction?>('webkitAudioContext'.toJS);
      if (ctor == null) return null;

      final audioCtx = ctor.callAsConstructor<JSObject>();
      try {
        final decodePromise = audioCtx.callMethod<JSPromise<JSAny?>>('decodeAudioData'.toJS, arrayBuffer);
        final decodedAny = await decodePromise.toDart;
        if (decodedAny == null || !decodedAny.isA<JSObject>()) return null;

        final audioBuf = decodedAny as JSObject;
        final srAny = audioBuf.getProperty<JSAny?>('sampleRate'.toJS);
        final lenAny = audioBuf.getProperty<JSAny?>('length'.toJS);
        final chAny = audioBuf.getProperty<JSAny?>('numberOfChannels'.toJS);
        final rawRate = (srAny != null && srAny.isA<JSNumber>()) ? (srAny as JSNumber).toDartInt : 44100;
        final totalLen = (lenAny != null && lenAny.isA<JSNumber>()) ? (lenAny as JSNumber).toDartInt : 0;
        final numCh = (chAny != null && chAny.isA<JSNumber>()) ? (chAny as JSNumber).toDartInt : 1;
        if (totalLen <= 0 || rawRate <= 0) return null;

        final ch0Any = audioBuf.callMethod<JSAny?>('getChannelData'.toJS, 0.toJS);
        if (ch0Any == null || !ch0Any.isA<JSFloat32Array>()) return null;
        final ch0 = (ch0Any as JSFloat32Array).toDart;
        Float32List? ch1;
        if (numCh > 1) {
          final ch1Any = audioBuf.callMethod<JSAny?>('getChannelData'.toJS, 1.toJS);
          if (ch1Any != null && ch1Any.isA<JSFloat32Array>()) {
            ch1 = (ch1Any as JSFloat32Array).toDart;
          }
        }

        // Downsample to ~11025 Hz and cap at 45s so DSP analysis stays ultra fast (<25ms)
        final step = math.max(1, (rawRate / 11025).round());
        final effectiveRate = (rawRate / step).round();
        final maxSamples = math.min(ch0.length, rawRate * 45);
        final downCount = math.max(1, maxSamples ~/ step);
        final mono = Float64List(downCount);
        for (int i = 0; i < downCount; i++) {
          final idx = i * step;
          final s0 = ch0[idx];
          final s1 = ch1 != null && idx < ch1.length ? ch1[idx] : s0;
          mono[i] = ((s0 + s1) * 0.5).clamp(-1.0, 1.0);
        }

        return AudioTempoAnalyzer.analyzePcmSamples(
          mono,
          sampleRate: effectiveRate,
          bandCount: bandCount,
          framesPerSecond: framesPerSecond,
        );
      } finally {
        try {
          audioCtx.callMethod<JSAny?>('close'.toJS);
        } catch (_) {}
      }
    } catch (_) {
      return null;
    }
  }
}
