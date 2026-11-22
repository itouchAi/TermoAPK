import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import '../models/thermostat_state.dart';
import 'voice_gender_classifier.dart';

/// Direct browser Web Speech API (`speechSynthesis`, `getUserMedia`, `SpeechRecognition`)
/// bridge using Dart 3 `dart:js_interop`:
/// - Uses `onvoiceschanged` + up to 1.8s async wait so cloud female Turkish voices
///   (`Google Türkçe`, `Microsoft Emel Online`) load instead of returning early on local `Microsoft Tolga`.
/// - Uses word-boundary VoiceGenderClassifier so `female` is never blocked by `male`.
/// - Pre-requests `getUserMedia({audio: true})` inside the `Cevapla` tap gesture for hands-free listening.
class WebSpeechBridge {
  WebSpeechBridge._();

  static bool get isSupported => true;
  static String lastSpokenVoiceName = '';
  static bool lastSpokenMatchedGender = true;

  static JSObject? _activeUtterance;
  static JSObject? _activeRecognition;
  static int _speakToken = 0;
  static bool _warmedUp = false;
  static bool _micGranted = false;

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

  static void warmup() {
    if (_warmedUp) return;
    _warmedUp = true;
    try {
      final synth = _getSynthesis();
      if (synth == null) return;
      synth.callMethod<JSAny?>('getVoices'.toJS);
      synth.setProperty(
        'onvoiceschanged'.toJS,
        ((JSAny? _) {
          synth.callMethod<JSAny?>('getVoices'.toJS);
        }).toJS,
      );
    } catch (_) {}
  }

  static List<JSObject> _readVoicesNow(JSObject synth) {
    final raw = synth.callMethod<JSAny?>('getVoices'.toJS);
    if (raw == null || !raw.isA<JSArray>()) return const [];
    return [
      for (final item in (raw as JSArray).toDart)
        if (item != null && item.isA<JSObject>()) item as JSObject,
    ];
  }

  static List<VoiceOptionInfo> _toOptions(List<JSObject> rawVoices) {
    return [
      for (final v in rawVoices)
        VoiceOptionInfo(
          name: _strProp(v, 'name').trim(),
          locale: _strProp(v, 'lang').trim(),
          voiceUri: _strProp(v, 'voiceURI').trim(),
          gender: VoiceGenderClassifier.classify(
            _strProp(v, 'name'),
            voiceUri: _strProp(v, 'voiceURI'),
          ),
        ),
    ];
  }

  static bool _hasTargetGenderVoice(
    List<JSObject> rawVoices, {
    required LangCode lang,
    required bool female,
  }) {
    final prefix = lang == LangCode.tr ? 'tr' : 'en';
    final target = female ? VoiceGenderHint.female : VoiceGenderHint.male;
    for (final opt in _toOptions(rawVoices)) {
      if (opt.locale.toLowerCase().startsWith(prefix) && opt.gender == target) {
        return true;
      }
    }
    return false;
  }

  static Future<List<JSObject>> _waitForVoices(
    JSObject synth, {
    required LangCode lang,
    required bool female,
  }) async {
    warmup();
    var voices = _readVoicesNow(synth);
    if (_hasTargetGenderVoice(voices, lang: lang, female: female)) {
      return voices;
    }

    // Local SAPI5 voices (`Microsoft Tolga`) appear at t=0ms before cloud female voices
    // (`Google Türkçe` / `Microsoft Emel Online`) finish loading via `voiceschanged`.
    final done = Completer<List<JSObject>>();
    void finishIfReady() {
      final latest = _readVoicesNow(synth);
      if (!done.isCompleted && _hasTargetGenderVoice(latest, lang: lang, female: female)) {
        done.complete(latest);
      }
    }

    synth.setProperty(
      'onvoiceschanged'.toJS,
      ((JSAny? _) {
        finishIfReady();
      }).toJS,
    );

    for (int i = 0; i < 18 && !done.isCompleted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      voices = _readVoicesNow(synth);
      if (_hasTargetGenderVoice(voices, lang: lang, female: female)) {
        if (!done.isCompleted) done.complete(voices);
        break;
      }
    }

    return done.isCompleted ? await done.future : _readVoicesNow(synth);
  }

  static Future<List<VoiceOptionInfo>> listTurkishVoicesDetailed() async {
    final synth = _getSynthesis();
    if (synth == null) return const [];
    final voices = await _waitForVoices(synth, lang: LangCode.tr, female: true);
    final result = <VoiceOptionInfo>[];
    final seen = <String>{};
    for (final opt in _toOptions(voices)) {
      if (opt.locale.toLowerCase().startsWith('tr') &&
          opt.name.isNotEmpty &&
          seen.add(opt.name)) {
        result.add(opt);
      }
    }
    return result;
  }

  static Future<List<String>> listTurkishVoices() async {
    final detailed = await listTurkishVoicesDetailed();
    return [for (final v in detailed) v.name];
  }

  static Future<void> speak(
    String text, {
    required LangCode lang,
    required bool female,
    String? preferredVoiceName,
    VoidCallback? onComplete,
  }) async {
    final synth = _getSynthesis();
    if (synth == null) {
      lastSpokenVoiceName = '';
      lastSpokenMatchedGender = false;
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

    final rawVoices = await _waitForVoices(synth, lang: lang, female: female);
    if (myToken != _speakToken) return;

    final options = _toOptions(rawVoices);
    final pick = VoiceGenderClassifier.pickBestIndex(
      options,
      lang: lang,
      female: female,
      preferredVoiceName: preferredVoiceName,
    );

    final chosen = (pick != null && pick.index >= 0 && pick.index < rawVoices.length)
        ? rawVoices[pick.index]
        : null;
    final chosenOpt = (pick != null && pick.index >= 0 && pick.index < options.length)
        ? options[pick.index]
        : null;
    final matchedExpectedGender = pick?.matchedExpectedGender ?? false;

    lastSpokenVoiceName = chosenOpt?.name ?? '';
    lastSpokenMatchedGender = matchedExpectedGender;

    final utter = (ctorAny as JSFunction).callAsConstructor<JSObject>(text.toJS);
    utter.setProperty('lang'.toJS, (lang == LangCode.tr ? 'tr-TR' : 'en-US').toJS);
    if (chosen != null) {
      utter.setProperty('voice'.toJS, chosen);
    }
    utter.setProperty(
      'pitch'.toJS,
      (female
              ? (matchedExpectedGender ? 1.04 : 1.55)
              : (matchedExpectedGender ? 0.90 : 0.65))
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

    _activeUtterance = utter;
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

  static Future<String?>? _pendingPermission;

  static Future<String?> ensureMicPermission(LangCode lang) {
    if (_micGranted) return Future.value(null);
    return _pendingPermission ??= _requestMicPermissionInternal(lang).whenComplete(() {
      _pendingPermission = null;
    });
  }

  static Future<String?> _requestMicPermissionInternal(LangCode lang) async {
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
      _micGranted = true;
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
    bool skipPermissionPrompt = false,
  }) async {
    final tr = lang == LangCode.tr;
    stopSpeaking();
    stopListening();

    if (!skipPermissionPrompt || !_micGranted) {
      final permError = await ensureMicPermission(lang);
      if (permError != null) {
        onStatusError(permError);
        onDone?.call();
        return false;
      }
    }

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
          _micGranted = false;
          onStatusError(
            tr
                ? 'Mikrofon izni engellendi. Adres çubuğundan mikrofona izin verin.'
                : 'Microphone permission blocked. Allow mic in browser settings.',
          );
        } else if (code == 'no-speech') {
          onStatusError(
            tr
                ? 'Ses duyulmadı. Tekrar dinlemek için mikrofona dokunun veya yazın.'
                : 'No speech detected. Tap mic to retry or type.',
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
