import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/thermostat_state.dart';
import 'voice_gender_classifier.dart';
import 'web_speech_bridge.dart';

/// Unified Text-to-Speech (TTS) and Speech-to-Text (STT) service
/// supporting character gender voices (female: Ela/Mirnav/Puki, male: TermoBot/Mert),
/// natural Turkish temperature readout, and reliable Web/Android mic permission prompts.
class VoiceSpeechService {
  VoiceSpeechService._();

  static final FlutterTts _tts = FlutterTts();
  static final stt.SpeechToText _stt = stt.SpeechToText();

  static bool _ttsInitialized = false;
  static bool _sttAvailable = false;
  static bool _isListening = false;
  static bool _isSpeaking = false;
  static List<Map<String, String>>? _cachedVoices;

  static bool get isListening => _isListening;
  static bool get isSpeaking => _isSpeaking;
  static String preferredFemaleVoice = '';
  static String preferredMaleVoice = '';
  static String lastSpokenVoiceName = '';
  static bool lastSpokenMatchedGender = true;

  static Future<List<VoiceOptionInfo>> listTurkishVoicesDetailed() async {
    if (kIsWeb && WebSpeechBridge.isSupported) {
      return WebSpeechBridge.listTurkishVoicesDetailed();
    }
    await _ensureVoicesLoaded();
    final voices = _cachedVoices ?? const [];
    final out = <VoiceOptionInfo>[];
    final seen = <String>{};
    for (final v in voices) {
      final locale = (v['locale'] ?? '').trim();
      final name = (v['name'] ?? '').trim();
      if (locale.toLowerCase().startsWith('tr') && name.isNotEmpty && seen.add(name)) {
        out.add(
          VoiceOptionInfo(
            name: name,
            locale: locale,
            gender: VoiceGenderClassifier.classify(name),
          ),
        );
      }
    }
    return out;
  }

  static Future<List<String>> listTurkishVoices() async {
    final detailed = await listTurkishVoicesDetailed();
    return [for (final v in detailed) v.name];
  }

  static void warmup() {
    if (kIsWeb && WebSpeechBridge.isSupported) {
      WebSpeechBridge.warmup();
    } else {
      _ensureVoicesLoaded();
    }
  }

  /// Requests microphone permission upfront inside a user tap (`Cevapla` / mic open)
  /// so hands-free listening can start automatically right after assistant finishes speaking.
  static Future<String?> ensureMicPermission(LangCode lang) async {
    if (kIsWeb && WebSpeechBridge.isSupported) {
      return WebSpeechBridge.ensureMicPermission(lang);
    }
    try {
      final ok = await _stt.initialize();
      _sttAvailable = ok;
      if (!ok) {
        return lang == LangCode.tr
            ? 'Mikrofon veya ses tanıma servisi kullanılamıyor.'
            : 'Microphone speech recognition is unavailable.';
      }
      return null;
    } catch (_) {
      return lang == LangCode.tr
          ? 'Mikrofon izni alınamadı.'
          : 'Could not obtain microphone permission.';
    }
  }

  /// Female characters: Ela, Mırnav (kedi), Puki (tavşan).
  /// Male characters: TermoBot (robot), Mert (erkek asistan).
  static bool isFemaleCharacter(MascotCharacter character) {
    switch (character) {
      case MascotCharacter.ela:
      case MascotCharacter.mirnav:
      case MascotCharacter.puki:
        return true;
      case MascotCharacter.termoBot:
      case MascotCharacter.mert:
        return false;
    }
  }

  /// Replaces symbol units like `20.0°C` with natural spoken words (`20 derece`).
  static String formatForSpeech(String raw, {required LangCode lang}) {
    final unit = lang == LangCode.tr ? ' derece' : ' degrees';
    var out = raw.replaceAllMapped(
      RegExp(r'(\d+)\.0(?=\s*(?:°C|°|derece|degrees))', caseSensitive: false),
      (m) => m.group(1)!,
    );
    out = out.replaceAll(RegExp(r'\s*°C\b', caseSensitive: false), unit);
    out = out.replaceAll(RegExp(r'\s*°'), unit);
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static Future<void> _ensureVoicesLoaded() async {
    if (_cachedVoices != null && _cachedVoices!.isNotEmpty) return;
    try {
      for (int attempt = 0; attempt < 4; attempt++) {
        final raw = await _tts.getVoices;
        if (raw is List && raw.isNotEmpty) {
          _cachedVoices = [
            for (final item in raw)
              if (item is Map)
                {
                  'name': (item['name'] ?? '').toString(),
                  'locale': (item['locale'] ?? '').toString(),
                },
          ];
          if (_cachedVoices!.isNotEmpty) return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
    } catch (_) {}
  }

  static Future<void> _configureNativeTts({
    required LangCode lang,
    required MascotCharacter character,
  }) async {
    try {
      if (!_ttsInitialized) {
        _ttsInitialized = true;
        _tts.setCompletionHandler(() => _isSpeaking = false);
        _tts.setCancelHandler(() => _isSpeaking = false);
        _tts.setErrorHandler((_) => _isSpeaking = false);
        await _tts.awaitSpeakCompletion(true);
        await _tts.setVolume(1.0);
        await _tts.setSpeechRate(0.50);
      }

      await _tts.setLanguage(lang == LangCode.tr ? 'tr-TR' : 'en-US');
      await _ensureVoicesLoaded();

      final female = isFemaleCharacter(character);
      final preferredName = female ? preferredFemaleVoice : preferredMaleVoice;
      final rawVoices = _cachedVoices ?? const [];
      final options = [
        for (final v in rawVoices)
          VoiceOptionInfo(
            name: (v['name'] ?? '').trim(),
            locale: (v['locale'] ?? '').trim(),
            gender: VoiceGenderClassifier.classify(v['name'] ?? ''),
          ),
      ];

      final pick = VoiceGenderClassifier.pickBestIndex(
        options,
        lang: lang,
        female: female,
        preferredVoiceName: preferredName,
      );

      if (pick != null && pick.index >= 0 && pick.index < rawVoices.length) {
        final chosen = rawVoices[pick.index];
        lastSpokenVoiceName = chosen['name'] ?? '';
        lastSpokenMatchedGender = pick.matchedExpectedGender;
        await _tts.setVoice({
          'name': chosen['name'] ?? '',
          'locale': chosen['locale'] ?? (lang == LangCode.tr ? 'tr-TR' : 'en-US'),
        });
        await _tts.setPitch(
          female
              ? (pick.matchedExpectedGender ? 1.06 : 1.38)
              : (pick.matchedExpectedGender ? 0.88 : 0.72),
        );
      } else {
        lastSpokenVoiceName = '';
        lastSpokenMatchedGender = false;
        await _tts.setPitch(female ? 1.35 : 0.72);
      }
    } catch (_) {
      // Safe fallback in headless unit tests
    }
  }

  /// Speaks [text] aloud using character-appropriate female/male voice and natural Turkish units.
  static Future<void> speak(
    String text, {
    required LangCode lang,
    MascotCharacter character = MascotCharacter.ela,
    VoidCallback? onComplete,
  }) async {
    final spoken = formatForSpeech(text, lang: lang);
    if (spoken.isEmpty) {
      onComplete?.call();
      return;
    }

    final female = isFemaleCharacter(character);
    final preferredName = female ? preferredFemaleVoice : preferredMaleVoice;

    // Web uses direct WebSpeechBridge so voice list (`voiceschanged`) and gender selection work reliably
    if (kIsWeb && WebSpeechBridge.isSupported) {
      _isSpeaking = true;
      await WebSpeechBridge.speak(
        spoken,
        lang: lang,
        female: female,
        preferredVoiceName: preferredName,
        onComplete: () {
          _isSpeaking = false;
          lastSpokenVoiceName = WebSpeechBridge.lastSpokenVoiceName;
          lastSpokenMatchedGender = WebSpeechBridge.lastSpokenMatchedGender;
          onComplete?.call();
        },
      );
      lastSpokenVoiceName = WebSpeechBridge.lastSpokenVoiceName;
      lastSpokenMatchedGender = WebSpeechBridge.lastSpokenMatchedGender;
      return;
    }

    try {
      await _configureNativeTts(lang: lang, character: character);
      await _tts.stop();
      _isSpeaking = true;
      var completed = false;
      void finish() {
        if (completed) return;
        completed = true;
        _isSpeaking = false;
        onComplete?.call();
      }

      _tts.setCompletionHandler(finish);
      _tts.setErrorHandler((_) => finish());
      await _tts.speak(spoken);
      finish();
    } catch (_) {
      _isSpeaking = false;
      onComplete?.call();
    }
  }

  static Future<void> stopSpeaking() async {
    _isSpeaking = false;
    if (kIsWeb && WebSpeechBridge.isSupported) {
      WebSpeechBridge.stopSpeaking();
      return;
    }
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static Future<String> _resolveNativeSpeechLocale(LangCode lang) async {
    final preferred = lang == LangCode.tr ? 'tr_TR' : 'en_US';
    try {
      final locales = await _stt.locales();
      final prefix = lang == LangCode.tr ? 'tr' : 'en';
      for (final loc in locales) {
        if (loc.localeId.toLowerCase().startsWith(prefix)) {
          return loc.localeId;
        }
      }
    } catch (_) {}
    return preferred;
  }

  /// Starts live microphone speech recognition.
  static Future<bool> startListening({
    required LangCode lang,
    required ValueChanged<String> onResultText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<String> onStatusError,
    VoidCallback? onDone,
    bool skipPermissionPrompt = false,
  }) async {
    if (kIsWeb && WebSpeechBridge.isSupported) {
      _isSpeaking = false;
      _isListening = true;
      final started = await WebSpeechBridge.startListening(
        lang: lang,
        onResultText: onResultText,
        onFinalResult: (words) {
          _isListening = false;
          onFinalResult(words);
        },
        onStatusError: (err) {
          _isListening = false;
          onStatusError(err);
        },
        onDone: () {
          _isListening = false;
          onDone?.call();
        },
        skipPermissionPrompt: skipPermissionPrompt,
      );
      if (!started) _isListening = false;
      return started;
    }

    try {
      unawaited(stopSpeaking());
      if (_isListening) {
        unawaited(_stt.stop());
        _isListening = false;
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
          final msg = err.errorMsg.toLowerCase();
          if (msg.contains('not-allowed') || msg.contains('permission')) {
            onStatusError(
              lang == LangCode.tr
                  ? 'Mikrofon izni reddedildi. Telefon ayarlarından mikrofona izin verin.'
                  : 'Microphone permission denied. Please allow mic access.',
            );
          } else {
            onStatusError(
              lang == LangCode.tr
                  ? 'Ses algılanamadı (${err.errorMsg}). Tekrar deneyin.'
                  : 'Speech not captured (${err.errorMsg}). Try again.',
            );
          }
          onDone?.call();
        },
      );
      _sttAvailable = available;
      if (!_sttAvailable) {
        _isListening = false;
        onStatusError(
          lang == LangCode.tr
              ? 'Mikrofon veya ses tanıma servisi kullanılamıyor.'
              : 'Microphone speech recognition is unavailable.',
        );
        return false;
      }

      final localeId = await _resolveNativeSpeechLocale(lang);
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
        localeId: localeId,
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
            ? 'Mikrofon izni alınamadı veya ses tanıma başlatılamadı.'
            : 'Could not obtain microphone permission or start speech recognizer.',
      );
      return false;
    }
  }

  static Future<void> stopListening() async {
    _isListening = false;
    if (kIsWeb && WebSpeechBridge.isSupported) {
      WebSpeechBridge.stopListening();
      return;
    }
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
