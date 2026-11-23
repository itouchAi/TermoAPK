import 'dart:io';
import 'dart:typed_data';
import 'audio_tempo_analyzer.dart';

class WebAudioDecodeBridge {
  WebAudioDecodeBridge._();

  static Future<AudioSpectrumProfile?> decodeAndAnalyze({
    Uint8List? bytes,
    String source = '',
    int bandCount = 18,
    int framesPerSecond = 25,
  }) async {
    if (bytes != null && bytes.length >= 44) {
      final parsed = AudioTempoAnalyzer.analyzeWavBytes(
        bytes,
        bandCount: bandCount,
        framesPerSecond: framesPerSecond,
      );
      if (parsed != null) return parsed;
    }
    final trimmed = source.trim();
    if (trimmed.isNotEmpty &&
        !trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://')) {
      try {
        final file = File(trimmed);
        if (await file.exists()) {
          final fileBytes = await file.readAsBytes();
          return AudioTempoAnalyzer.analyzeWavBytes(
            fileBytes,
            bandCount: bandCount,
            framesPerSecond: framesPerSecond,
          );
        }
      } catch (_) {}
    }
    return null;
  }
}
