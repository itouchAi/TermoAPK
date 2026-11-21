import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/thermostat_state.dart';

/// Unified Text-to-Speech (TTS) and Speech-to-Text (STT) service
/// supporting both Android native speech engines and Web Speech APIs.
class VoiceSpeechService {
  VoiceSpeechService._();

  static final FlutterTts _tts = FlutterTts();
  static final stt.SpeechToText _stt = stt.SpeechToText();

  static bool _ttsInitialized = false;
  static bool _sttAvailable = false;
  static bool _isListening = false;
  static bool _isSpeaking = false;

  static bool get isListening => _isListening;
  static bool get isSpeaking => _isSpeaking;

  static Future<void> _ensureTtsReady(LangCode lang) async {
    try {
      if (!_ttsInitialized) {
        _ttsInitialized = true;
        _tts.setCompletionHandler(() => _isSpeaking = false);
        _tts.setCancelHandler(() => _isSpeaking = false);
        _tts.setErrorHandler((_) => _isSpeaking = false);
        await _tts.awaitSpeakCompletion(false);
        await _tts.setVolume(1.0);
        await _tts.setPitch(1.0);
        await _tts.setSpeechRate(kIsWeb ? 0.96 : 0.50);
      }
      await _tts.setLanguage(lang == LangCode.tr ? 'tr-TR' : 'en-US');
    } catch (_) {
      // Ignore in headless unit tests or unsupported environments
    }
  }

  /// Speaks [text] aloud using native Android TTS or browser Web SpeechSynthesis.
  static Future<void> speak(
    String text, {
    required LangCode lang,
    VoidCallback? onComplete,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    try {
      await _ensureTtsReady(lang);
      await _tts.stop();
      _isSpeaking = true;
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        onComplete?.call();
      });
      await _tts.speak(clean);
    } catch (_) {
      _isSpeaking = false;
    }
  }

  static Future<void> stopSpeaking() async {
    _isSpeaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Starts live microphone speech recognition in Turkish (`tr_TR`) or English (`en_US`).
  static Future<bool> startListening({
    required LangCode lang,
    required ValueChanged<String> onResultText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<String> onStatusError,
    VoidCallback? onDone,
  }) async {
    try {
      await stopSpeaking();
      if (_isListening) {
        await stopListening();
      }
      final available = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            onDone?.call();
          }
        },
        onError: (err) {
          _isListening = false;
          onStatusError(err.errorMsg);
          onDone?.call();
        },
      );
      _sttAvailable = available;
      if (!_sttAvailable) {
        _isListening = false;
        onStatusError(
          lang == LangCode.tr
              ? 'Mikrofon veya tarayıcı ses tanıma kullanılamıyor.'
              : 'Microphone or speech recognition is unavailable.',
        );
        return false;
      }

      _isListening = true;
      await _stt.listen(
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            onResultText(words);
            if (result.finalResult) {
              _isListening = false;
              onFinalResult(words);
              onDone?.call();
            }
          }
        },
        localeId: lang == LangCode.tr ? 'tr_TR' : 'en_US',
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.dictation,
        ),
      );
      return true;
    } catch (_) {
      _isListening = false;
      onStatusError(
        lang == LangCode.tr
            ? 'Ses dinleme başlatılamadı (mikrofon iznini kontrol edin).'
            : 'Could not start speech listener (check mic permission).',
      );
      return false;
    }
  }

  static Future<void> stopListening() async {
    _isListening = false;
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
