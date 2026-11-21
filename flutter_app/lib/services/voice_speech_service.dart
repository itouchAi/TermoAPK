import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/thermostat_state.dart';

/// Unified Text-to-Speech (TTS) and Speech-to-Text (STT) service
/// supporting character gender voices (female: Ela/Mirnav/Puki, male: TermoBot/Mert),
/// natural Turkish temperature readout, and Web/Android mic permission handling.
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
    if (_cachedVoices != null) return;
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        _cachedVoices = [
          for (final item in raw)
            if (item is Map)
              {
                'name': (item['name'] ?? '').toString(),
                'locale': (item['locale'] ?? '').toString(),
              },
        ];
      }
    } catch (_) {
      _cachedVoices = const [];
    }
  }

  static Map<String, String>? _pickGenderedVoice({
    required LangCode lang,
    required bool female,
  }) {
    final voices = _cachedVoices;
    if (voices == null || voices.isEmpty) return null;

    final langPrefix = lang == LangCode.tr ? 'tr' : 'en';
    final langVoices = voices
        .where((v) => (v['locale'] ?? '').toLowerCase().startsWith(langPrefix))
        .toList();
    final pool = langVoices.isNotEmpty ? langVoices : voices;

    const femaleKeys = [
      'emel',
      'seda',
      'yelda',
      'defne',
      'filiz',
      'ayla',
      'female',
      'woman',
      '#trf',
      '#female',
      'tff',
      'sfg',
      'zira',
      'samantha',
      'jenny',
      'aria',
      'google türkçe',
      'google us english',
    ];
    const maleKeys = [
      'ahmet',
      'tolga',
      'mehmet',
      'cem',
      'can',
      'male',
      'man',
      '#trm',
      '#male',
      'david',
      'mark',
      'daniel',
      'guy',
    ];

    final targetKeys = female ? femaleKeys : maleKeys;
    final oppositeKeys = female ? maleKeys : femaleKeys;

    for (final v in pool) {
      final nameLower = (v['name'] ?? '').toLowerCase();
      final matchesTarget = targetKeys.any((k) => nameLower.contains(k));
      final matchesOpposite = oppositeKeys.any((k) => nameLower.contains(k));
      if (matchesTarget && !matchesOpposite) {
        return v;
      }
    }
    return null;
  }

  static Future<void> _configureTts({
    required LangCode lang,
    required MascotCharacter character,
  }) async {
    try {
      if (!_ttsInitialized) {
        _ttsInitialized = true;
        _tts.setCompletionHandler(() => _isSpeaking = false);
        _tts.setCancelHandler(() => _isSpeaking = false);
        _tts.setErrorHandler((_) => _isSpeaking = false);
        await _tts.awaitSpeakCompletion(false);
        await _tts.setVolume(1.0);
        await _tts.setSpeechRate(kIsWeb ? 0.98 : 0.50);
      }

      await _tts.setLanguage(lang == LangCode.tr ? 'tr-TR' : 'en-US');
      await _ensureVoicesLoaded();

      final female = isFemaleCharacter(character);
      final chosen = _pickGenderedVoice(lang: lang, female: female);
      if (chosen != null) {
        await _tts.setVoice({
          'name': chosen['name'] ?? '',
          'locale': chosen['locale'] ?? (lang == LangCode.tr ? 'tr-TR' : 'en-US'),
        });
        await _tts.setPitch(female ? 1.06 : 0.88);
      } else {
        await _tts.setPitch(female ? 1.24 : 0.78);
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
    try {
      await _configureTts(lang: lang, character: character);
      await _tts.stop();
      _isSpeaking = true;
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        onComplete?.call();
      });
      final res = await _tts.speak(spoken);
      if (res != 1 && onComplete != null) {
        // Fallback auto-complete timer if platform engine returns immediately
        Timer(
          Duration(milliseconds: (spoken.length * 65).clamp(1200, 4200)),
          () {
            if (_isSpeaking) {
              _isSpeaking = false;
              onComplete();
            }
          },
        );
      }
    } catch (_) {
      _isSpeaking = false;
      onComplete?.call();
    }
  }

  static Future<void> stopSpeaking() async {
    _isSpeaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static Future<String> _resolveSpeechLocale(LangCode lang) async {
    final preferred = lang == LangCode.tr
        ? (kIsWeb ? 'tr-TR' : 'tr_TR')
        : (kIsWeb ? 'en-US' : 'en_US');
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

  /// Starts live microphone speech recognition directly within a user tap gesture.
  static Future<bool> startListening({
    required LangCode lang,
    required ValueChanged<String> onResultText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<String> onStatusError,
    VoidCallback? onDone,
  }) async {
    try {
      // Stop TTS without awaiting so browser user-activation chain stays intact for mic permission
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
                  ? 'Mikrofon izni reddedildi. Tarayıcı/telefon ayarlarından mikrofona izin verin.'
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
              ? 'Mikrofon veya tarayıcı ses tanıma desteklenmiyor (Chrome/Edge veya Android APK kullanın).'
              : 'Microphone speech recognition is not supported on this browser.',
        );
        return false;
      }

      final localeId = await _resolveSpeechLocale(lang);
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
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
