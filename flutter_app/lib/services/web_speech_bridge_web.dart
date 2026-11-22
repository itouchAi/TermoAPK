import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import '../models/thermostat_state.dart';

/// Direct browser Web Speech API (`speechSynthesis`, `getUserMedia`, `SpeechRecognition`)
/// bridge using Dart 3 `dart:js_interop` so:
/// 1) Voice list is awaited until populated (`voiceschanged`), preventing stale `Microsoft Tolga` fallback.
/// 2) Clicking mic synchronously invokes `navigator.mediaDevices.getUserMedia({audio: true})`
///    so Chrome/Edge/Android Web reliably prompts for microphone permission.
class WebSpeechBridge {
  WebSpeechBridge._();

  static bool get isSupported => true;

  static JSObject? _activeUtterance;
  static JSObject? _activeRecognition;
  static int _speakToken = 0;

  static String _norm(String raw) => raw
      .replaceAll('İ', 'i')
      .toLowerCase()
      .replaceAll('\u0307', '')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i');

  static String _strProp(JSObject obj, String key) {
    final val = obj.getProperty<JSAny?>(key.toJS);
    if (val != null && val.isA<JSString>()) {
      return (val as JSString).toDart;
    }
    return '';
  }

  static bool _boolProp(JSObject obj, String key) {
    final val = obj.getProperty<JSAny?>(key.toJS);
    if (val != null && val.isA<JSBoolean>()) {
      return (val as JSBoolean).toDart;
    }
    return false;
  }

  static int _intProp(JSObject obj, String key) {
    final val = obj.getProperty<JSAny?>(key.toJS);
    if (val != null && val.isA<JSNumber>()) {
      return (val as JSNumber).toDartInt;
    }
    return 0;
  }

  static JSObject? _getSynthesis() {
    final s = globalContext.getProperty<JSAny?>('speechSynthesis'.toJS);
    if (s != null && s.isA<JSObject>()) return s as JSObject;
    return null;
  }

  static Future<List<JSObject>> _waitForVoices(JSObject synth) async {
    List<JSObject> readNow() {
      final raw = synth.callMethod<JSAny?>('getVoices'.toJS);
      if (raw == null || !raw.isA<JSArray>()) return const [];
      return [
        for (final item in (raw as JSArray).toDart)
          if (item != null && item.isA<JSObject>()) item as JSObject,
      ];
    }

    var voices = readNow();
    if (voices.isNotEmpty) return voices;

    for (int i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      voices = readNow();
      if (voices.isNotEmpty) return voices;
    }
    return voices;
  }

  static JSObject? _pickVoice(
    List<JSObject> voices, {
    required LangCode lang,
    required bool female,
  }) {
    if (voices.isEmpty) return null;
    final prefix = lang == LangCode.tr ? 'tr' : 'en';
    final langVoices = voices.where((v) {
      final vLang = _strProp(v, 'lang').toLowerCase();
      return vLang.startsWith(prefix);
    }).toList();
    final pool = langVoices.isNotEmpty ? langVoices : voices;

    const femaleKeys = [
      'emel',
      'google turkce',
      'yelda',
      'filiz',
      'seda',
      'defne',
      'ayla',
      'zeynep',
      'ipek',
      'esra',
      'female',
      'woman',
      '#trf',
      '-efu-',
      '-ama-',
      'zira',
      'jenny',
      'aria',
      'samantha',
      'google us english',
      'google uk english female',
    ];
    const maleKeys = [
      'ahmet',
      'tolga',
      'mehmet',
      'cem',
      'can',
      'murat',
      'kerem',
      'male',
      'man',
      '#trm',
      '-tmc-',
      'david',
      'mark',
      'daniel',
      'guy',
      'google uk english male',
    ];

    final targetKeys = female ? femaleKeys : maleKeys;
    final oppositeKeys = female ? maleKeys : femaleKeys;

    // 1. Exact target gender voice match
    for (final v in pool) {
      final label = _norm('${_strProp(v, 'name')} ${_strProp(v, 'voiceURI')}');
      final isTarget = targetKeys.any(label.contains);
      final isOpposite = oppositeKeys.any(label.contains);
      if (isTarget && !isOpposite) {
        return v;
      }
    }

    // 2. Exclude opposite gender voices (crucial when e.g. Tolga + unmarked female voice exist)
    for (final v in pool) {
      final label = _norm('${_strProp(v, 'name')} ${_strProp(v, 'voiceURI')}');
      final isOpposite = oppositeKeys.any(label.contains);
      if (!isOpposite) {
        return v;
      }
    }

    // 3. Fallback within same language pool
    return pool.isNotEmpty ? pool.first : null;
  }

  static Future<void> speak(
    String text, {
    required LangCode lang,
    required bool female,
    VoidCallback? onComplete,
  }) async {
    final synth = _getSynthesis();
    if (synth == null) {
      onComplete?.call();
      return;
    }

    final myToken = ++_speakToken;
    synth.callMethod<JSAny?>('cancel'.toJS);

    final ctorAny = globalContext.getProperty<JSAny?>('SpeechSynthesisUtterance'.toJS);
    if (ctorAny == null || !ctorAny.isA<JSFunction>()) {
      onComplete?.call();
      return;
    }

    final voices = await _waitForVoices(synth);
    if (myToken != _speakToken) return;

    final chosen = _pickVoice(voices, lang: lang, female: female);
    final chosenLabel = chosen != null
        ? _norm('${_strProp(chosen, 'name')} ${_strProp(chosen, 'voiceURI')}')
        : '';

    const maleOnlyMarkers = ['ahmet', 'tolga', 'mehmet', 'cem', 'can', '#trm', 'david', 'mark', 'daniel'];
    const femaleOnlyMarkers = ['emel', 'google turkce', 'yelda', 'filiz', 'seda', 'defne', 'ayla', 'zira', 'jenny', 'aria', 'samantha'];
    final matchedExpectedGender = female
        ? !maleOnlyMarkers.any(chosenLabel.contains)
        : !femaleOnlyMarkers.any(chosenLabel.contains);

    final utter = (ctorAny as JSFunction).callAsConstructor<JSObject>(text.toJS);
    utter.setProperty('lang'.toJS, (lang == LangCode.tr ? 'tr-TR' : 'en-US').toJS);
    if (chosen != null) {
      utter.setProperty('voice'.toJS, chosen);
    }
    utter.setProperty(
      'pitch'.toJS,
      (female
              ? (matchedExpectedGender ? 1.08 : 1.46)
              : (matchedExpectedGender ? 0.88 : 0.66))
          .toJS,
    );
    utter.setProperty('rate'.toJS, (female ? 1.0 : 0.94).toJS);
    utter.setProperty('volume'.toJS, 1.0.toJS);

    var finished = false;
    Timer? guardTimer;

    void finishNow() {
      if (finished) return;
      finished = true;
      guardTimer?.cancel();
      _activeUtterance = null;
      if (myToken == _speakToken) {
        onComplete?.call();
      }
    }

    utter.setProperty(
      'onend'.toJS,
      ((JSAny? _) {
        finishNow();
      }).toJS,
    );
    utter.setProperty(
      'onerror'.toJS,
      ((JSAny? _) {
        finishNow();
      }).toJS,
    );

    // Prevent Chrome GC from dropping utterance before `onend` fires
    _activeUtterance = utter;

    // Fallback safety guard in case browser pauses synthesis on background tab
    final fallbackMs = (text.length * 95 + 1800).clamp(2400, 12000);
    guardTimer = Timer(Duration(milliseconds: fallbackMs), finishNow);

    synth.callMethod<JSAny?>('speak'.toJS, utter);
  }

  static void stopSpeaking() {
    _speakToken++;
    _activeUtterance = null;
    try {
      _getSynthesis()?.callMethod<JSAny?>('cancel'.toJS);
    } catch (_) {}
  }

  static Future<String?> _ensureMicPermission(LangCode lang) async {
    final tr = lang == LangCode.tr;
    try {
      final nav = globalContext.getProperty<JSAny?>('navigator'.toJS);
      if (nav == null || !nav.isA<JSObject>()) return null;
      final mediaDevices = (nav as JSObject).getProperty<JSAny?>('mediaDevices'.toJS);
      if (mediaDevices == null || !mediaDevices.isA<JSObject>()) return null;

      final constraints = JSObject();
      constraints.setProperty('audio'.toJS, true.toJS);

      final promiseAny = (mediaDevices as JSObject).callMethod<JSAny?>(
        'getUserMedia'.toJS,
        constraints,
      );
      if (promiseAny != null && promiseAny.isA<JSPromise>()) {
        final streamAny = await (promiseAny as JSPromise<JSAny?>).toDart;
        if (streamAny != null && streamAny.isA<JSObject>()) {
          final tracksAny = (streamAny as JSObject).callMethod<JSAny?>('getTracks'.toJS);
          if (tracksAny != null && tracksAny.isA<JSArray>()) {
            for (final track in (tracksAny as JSArray).toDart) {
              if (track != null && track.isA<JSObject>()) {
                (track as JSObject).callMethod<JSAny?>('stop'.toJS);
              }
            }
          }
        }
      }
      return null;
    } catch (e) {
      final raw = e.toString().toLowerCase();
      if (raw.contains('notallowed') || raw.contains('permission') || raw.contains('denied')) {
        return tr
            ? 'Mikrofon izni reddedildi. Tarayıcı adres çubuğundaki kilit/mikrofon simgesinden izin verin.'
            : 'Microphone permission denied. Please allow mic access in your browser bar.';
      }
      if (raw.contains('notfound') || raw.contains('device')) {
        return tr
            ? 'Bağlı mikrofon bulunamadı. Cihaz mikrofonunu kontrol edin.'
            : 'No microphone hardware found.';
      }
      return tr
          ? 'Mikrofon erişimi açılamadı. HTTPS üzerinden Chrome veya Edge kullanın.'
          : 'Could not open microphone access. Use Chrome or Edge over HTTPS.';
    }
  }

  static Future<bool> startListening({
    required LangCode lang,
    required ValueChanged<String> onResultText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<String> onStatusError,
    VoidCallback? onDone,
  }) async {
    final tr = lang == LangCode.tr;
    stopSpeaking();
    stopListening();

    // Step 1: Request microphone permission immediately inside user tap
    final permError = await _ensureMicPermission(lang);
    if (permError != null) {
      onStatusError(permError);
      onDone?.call();
      return false;
    }

    // Step 2: Obtain SpeechRecognition constructor
    JSAny? ctorAny = globalContext.getProperty<JSAny?>('SpeechRecognition'.toJS);
    if (ctorAny == null || !ctorAny.isA<JSFunction>()) {
      ctorAny = globalContext.getProperty<JSAny?>('webkitSpeechRecognition'.toJS);
    }
    if (ctorAny == null || !ctorAny.isA<JSFunction>()) {
      onStatusError(
        tr
            ? 'Bu tarayıcı sesli komut algılamayı desteklemiyor (Chrome, Edge veya Android APK kullanın).'
            : 'Speech recognition is not supported on this browser (use Chrome, Edge or Android APK).',
      );
      onDone?.call();
      return false;
    }

    final recog = (ctorAny as JSFunction).callAsConstructor<JSObject>();
    recog.setProperty('lang'.toJS, (tr ? 'tr-TR' : 'en-US').toJS);
    recog.setProperty('interimResults'.toJS, true.toJS);
    recog.setProperty('continuous'.toJS, false.toJS);
    recog.setProperty('maxAlternatives'.toJS, 3.toJS);

    var deliveredFinal = false;
    var latestTranscript = '';

    recog.setProperty(
      'onresult'.toJS,
      ((JSAny? evAny) {
        if (evAny == null || !evAny.isA<JSObject>()) return;
        final ev = evAny as JSObject;
        final resultsAny = ev.getProperty<JSAny?>('results'.toJS);
        if (resultsAny == null || !resultsAny.isA<JSObject>()) return;
        final results = resultsAny as JSObject;
        final len = _intProp(results, 'length');
        final buffer = StringBuffer();
        var isFinal = false;
        for (int i = 0; i < len; i++) {
          final resAny = results.getProperty<JSAny?>(i.toString().toJS);
          if (resAny == null || !resAny.isA<JSObject>()) continue;
          final res = resAny as JSObject;
          if (_boolProp(res, 'isFinal')) isFinal = true;
          final altAny = res.getProperty<JSAny?>('0'.toJS);
          if (altAny != null && altAny.isA<JSObject>()) {
            final t = _strProp(altAny as JSObject, 'transcript').trim();
            if (t.isNotEmpty) {
              if (buffer.isNotEmpty) buffer.write(' ');
              buffer.write(t);
            }
          }
        }
        final combined = buffer.toString().trim();
        if (combined.isNotEmpty) {
          latestTranscript = combined;
          onResultText(combined);
          if (isFinal && !deliveredFinal) {
            deliveredFinal = true;
            onFinalResult(combined);
          }
        }
      }).toJS,
    );

    recog.setProperty(
      'onerror'.toJS,
      ((JSAny? evAny) {
        String code = 'unknown';
        if (evAny != null && evAny.isA<JSObject>()) {
          code = _strProp(evAny as JSObject, 'error');
        }
        if (code == 'not-allowed' || code == 'service-not-allowed') {
          onStatusError(
            tr
                ? 'Mikrofon izni engellendi. Adres çubuğundan mikrofona izin verin.'
                : 'Microphone permission blocked. Allow mic in browser settings.',
          );
        } else if (code == 'no-speech') {
          onStatusError(
            tr ? 'Ses duyulmadı. Mikrofona yaklaşıp tekrar deneyin.' : 'No speech detected. Try again.',
          );
        } else if (code != 'aborted') {
          onStatusError(
            tr ? 'Ses tanıma hatası ($code). Tekrar deneyin.' : 'Speech recognition error ($code).',
          );
        }
      }).toJS,
    );

    recog.setProperty(
      'onend'.toJS,
      ((JSAny? _) {
        _activeRecognition = null;
        if (!deliveredFinal && latestTranscript.isNotEmpty) {
          deliveredFinal = true;
          onFinalResult(latestTranscript);
        }
        onDone?.call();
      }).toJS,
    );

    _activeRecognition = recog;
    try {
      recog.callMethod<JSAny?>('start'.toJS);
      return true;
    } catch (_) {
      _activeRecognition = null;
      onStatusError(
        tr ? 'Mikrofon dinlemesi başlatılamadı. Tekrar dokunun.' : 'Could not start microphone listener.',
      );
      onDone?.call();
      return false;
    }
  }

  static void stopListening() {
    final r = _activeRecognition;
    _activeRecognition = null;
    if (r != null) {
      try {
        r.callMethod<JSAny?>('stop'.toJS);
      } catch (_) {}
    }
  }
}
