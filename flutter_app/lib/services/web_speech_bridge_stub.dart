import 'package:flutter/foundation.dart';
import '../models/thermostat_state.dart';
import 'voice_gender_classifier.dart';

class WebSpeechBridge {
  WebSpeechBridge._();

  static bool get isSupported => false;
  static String lastSpokenVoiceName = '';
  static bool lastSpokenMatchedGender = true;

  static void warmup() {}

  static Future<List<String>> listTurkishVoices() async => const [];

  static Future<List<VoiceOptionInfo>> listTurkishVoicesDetailed() async => const [];

  static Future<String?> ensureMicPermission(LangCode lang) async => null;

  static Future<void> speak(
    String text, {
    required LangCode lang,
    required bool female,
    String? preferredVoiceName,
    VoidCallback? onComplete,
  }) async {
    onComplete?.call();
  }

  static void stopSpeaking() {}

  static Future<bool> startListening({
    required LangCode lang,
    required ValueChanged<String> onResultText,
    required ValueChanged<String> onFinalResult,
    required ValueChanged<String> onStatusError,
    VoidCallback? onDone,
    bool skipPermissionPrompt = false,
  }) async {
    return false;
  }

  static void stopListening() {}
}
