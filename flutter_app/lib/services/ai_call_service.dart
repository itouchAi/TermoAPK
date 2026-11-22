import '../models/thermostat_state.dart';
import 'notification_service.dart';

class AiCallTriggerDecision {
  final bool shouldCall;
  final AiCallReason? reason;
  final bool urgent;

  const AiCallTriggerDecision({
    required this.shouldCall,
    this.reason,
    this.urgent = false,
  });
}

class AiCallService {
  AiCallService._();

  static const Duration defaultCooldown = Duration(seconds: 60);
  static const double coldRoomThresholdC = 17.5;
  static const double hotRoomThresholdC = 26.5;

  /// Formats `20.0` -> `20` and `21.8` -> `21.8` for natural speech readout.
  static String formatSpokenNumber(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  /// Evaluates whether the AI phone call assistant should ring on boiler state
  /// changes (ignition / shutoff) or room temperature / safety thresholds.
  static AiCallTriggerDecision evaluateTrigger({
    required bool enabled,
    required AiCallTriggerMode triggerMode,
    required bool wasHeating,
    required BoilerTelemetry nextBoiler,
    required SafetyGuardStatus safety,
    double roomTemp = 21.8,
    DateTime? lastCallAt,
    DateTime? now,
    Duration cooldown = defaultCooldown,
  }) {
    if (!enabled) {
      return const AiCallTriggerDecision(shouldCall: false);
    }

    final checkNow = now ?? DateTime.now();
    if (lastCallAt != null && checkNow.difference(lastCallAt) < cooldown) {
      return const AiCallTriggerDecision(shouldCall: false);
    }

    final ignitionDetected = !wasHeating && nextBoiler.isHeating;
    final shutdownDetected = wasHeating && !nextBoiler.isHeating;
    final isCold = safety.freezeRisk || roomTemp <= coldRoomThresholdC;
    final isHot = safety.overheat || roomTemp >= hotRoomThresholdC;

    switch (triggerMode) {
      case AiCallTriggerMode.onIgnition:
        if (ignitionDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.ignition,
            urgent: false,
          );
        }
        if (shutdownDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.boilerOff,
            urgent: false,
          );
        }
        return const AiCallTriggerDecision(shouldCall: false);

      case AiCallTriggerMode.ignitionAndSafety:
        if (safety.lowPressure) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.safetyAlert,
            urgent: true,
          );
        }
        if (isCold && !nextBoiler.isHeating) {
          return AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.coldRoom,
            urgent: safety.freezeRisk,
          );
        }
        if (isHot && nextBoiler.isHeating) {
          return AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.hotRoom,
            urgent: safety.overheat,
          );
        }
        if (ignitionDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.ignition,
            urgent: false,
          );
        }
        if (shutdownDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.boilerOff,
            urgent: false,
          );
        }
        return const AiCallTriggerDecision(shouldCall: false);

      case AiCallTriggerMode.criticalOnly:
        if (safety.lowPressure) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.safetyAlert,
            urgent: true,
          );
        }
        if (isCold && !nextBoiler.isHeating) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.coldRoom,
            urgent: true,
          );
        }
        if (isHot && nextBoiler.isHeating) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.hotRoom,
            urgent: true,
          );
        }
        return const AiCallTriggerDecision(shouldCall: false);
    }
  }

  static String triggerModeLabel(AiCallTriggerMode mode, LangCode lang) {
    final tr = lang == LangCode.tr;
    switch (mode) {
      case AiCallTriggerMode.onIgnition:
        return tr ? 'Ateşleme & Kapanma' : 'Ignition & Shutdown';
      case AiCallTriggerMode.ignitionAndSafety:
        return tr ? 'Durum + Sıcaklık Eşiği' : 'Status + Temp Thresholds';
      case AiCallTriggerMode.criticalOnly:
        return tr ? 'Yalnızca Kritik Eşik' : 'Critical Thresholds Only';
    }
  }

  static String reasonBadge(
    AiCallReason reason,
    BoilerTelemetry boiler,
    SafetyGuardStatus safety,
    LangCode lang,
  ) {
    final tr = lang == LangCode.tr;
    switch (reason) {
      case AiCallReason.ignition:
        return tr ? '🔥 Kombi Ateşlendi' : '🔥 Boiler Ignited';
      case AiCallReason.boilerOff:
        return tr ? '⏸ Kombi Kapatıldı' : '⏸ Boiler Turned Off';
      case AiCallReason.coldRoom:
        return tr ? '❄️ Ev Sıcaklığı Düştü · Açalım mı?' : '❄️ Room Is Cold · Turn On?';
      case AiCallReason.hotRoom:
        return tr ? '☀️ Ev Sıcaklığı Yükseldi · Kapatalım mı?' : '☀️ Room Is Warm · Turn Off?';
      case AiCallReason.safetyAlert:
        return '⚠️ ${safety.headline(lang)}';
      case AiCallReason.manualTest:
        return boiler.isHeating
            ? (tr ? '📞 Kombi Aktif · Asistan Görüşmesi' : '📞 Boiler Active · Assistant Call')
            : (tr ? '📞 Kombi Kapalı · Asistan Görüşmesi' : '📞 Boiler Idle · Assistant Call');
    }
  }

  /// Concise, natural spoken briefing with full word units (`derece` / `degrees`),
  /// avoiding unnecessary technical figures.
  static String buildVoiceScript({
    required AiCallReason reason,
    required String assistantName,
    required String locationName,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
    required SafetyGuardStatus safety,
    required LangCode lang,
  }) {
    final room = formatSpokenNumber(roomTemp);
    final target = formatSpokenNumber(targetTemp);
    final tr = lang == LangCode.tr;

    switch (reason) {
      case AiCallReason.ignition:
        return tr
            ? 'Merhaba, ben $assistantName. Kombi ateşlendi ve sıcaklık $target dereceye ayarlandı.'
            : 'Hello, this is $assistantName. The boiler has ignited and target temperature is set to $target degrees.';
      case AiCallReason.boilerOff:
        return tr
            ? 'Merhaba, ben $assistantName. Kombi kapatıldı ve ısıtma bekleme moduna alındı.'
            : 'Hello, this is $assistantName. The boiler has been turned off and placed in standby.';
      case AiCallReason.coldRoom:
        return tr
            ? 'Merhaba, ben $assistantName. Ev sıcaklığı $room dereceye düştü. Kombiyi açalım mı?'
            : 'Hello, this is $assistantName. Room temperature dropped to $room degrees. Should I turn on the boiler?';
      case AiCallReason.hotRoom:
        return tr
            ? 'Merhaba, ben $assistantName. Ev sıcaklığı $room dereceye yükseldi. Kombiyi kapatalım mı?'
            : 'Hello, this is $assistantName. Room temperature rose to $room degrees. Should I turn off the boiler?';
      case AiCallReason.safetyAlert:
        return tr
            ? 'Dikkat, ben $assistantName. Kombi su basıncı kritik seviyeye düştü, lütfen kontrol edin.'
            : 'Attention, this is $assistantName. Boiler water pressure dropped critically, please inspect the system.';
      case AiCallReason.manualTest:
        if (boiler.isHeating) {
          return tr
              ? 'Merhaba, ben $assistantName. Kombi şu an çalışıyor ve sıcaklık $target dereceye ayarlı. İstediğiniz bir değişiklik var mı?'
              : 'Hello, this is $assistantName. The boiler is active and set to $target degrees. Would you like to adjust anything?';
        }
        return tr
            ? 'Merhaba, ben $assistantName. Kombi şu an kapalı, ev sıcaklığı $room derece. Kombiyi açalım mı?'
            : 'Hello, this is $assistantName. The boiler is currently off and room temperature is $room degrees. Should I turn it on?';
    }
  }

  /// Evaluates conversational yes/no or direct thermostat commands during an active call,
  /// returning a concise confirmation + thank-you closing line.
  static VoiceCommandResult evaluateCallResponse({
    required String rawInput,
    required AiCallReason callReason,
    required BoilerTelemetry boiler,
    required double currentTargetTemp,
    required LangCode lang,
  }) {
    final text = rawInput.trim().toLowerCase();
    final tr = lang == LangCode.tr;

    // 1) Explicit open/close affirmative phrases
    if (text == 'evet kapat' ||
        text == 'evet kapatalım' ||
        text == 'tamam kapat' ||
        text == 'kapatalım' ||
        text == 'kapat') {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: ThermostatMath.minTemp,
        replyTr: 'Kombi kapatılıyor. Teşekkürler.',
        replyEn: 'Turning off the boiler. Thank you.',
      );
    }
    if (text == 'evet aç' ||
        text == 'evet açalım' ||
        text == 'tamam aç' ||
        text == 'açalım' ||
        text == 'aç') {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 22.5,
        newPreset: PresetId.konfor,
        replyTr: 'Kombi açılıyor ve sıcaklık 22.5 dereceye ayarlanıyor. Teşekkürler.',
        replyEn: 'Turning on the boiler at 22.5 degrees. Thank you.',
      );
    }

    // 2) Contextual affirmative ("evet", "olur", "tamam", "tabii", "peki", "yes", "sure")
    final isAffirmative = text == 'evet' ||
        text.startsWith('evet ') ||
        text == 'olur' ||
        text == 'tamam' ||
        text == 'tabii' ||
        text == 'tabi' ||
        text == 'peki' ||
        text == 'onay' ||
        text == 'onaylıyorum' ||
        text == 'yes' ||
        text == 'sure' ||
        text == 'ok';
    final isNegative = text == 'hayır' ||
        text.startsWith('hayır ') ||
        text == 'gerek yok' ||
        text == 'kalsın' ||
        text == 'kapatma' ||
        text == 'açma' ||
        text == 'istemiyorum' ||
        text == 'vazgeç' ||
        text == 'no';

    if (isAffirmative) {
      if (callReason == AiCallReason.hotRoom ||
          (callReason == AiCallReason.ignition && boiler.isHeating)) {
        return const VoiceCommandResult(
          handled: true,
          newTargetTemp: ThermostatMath.minTemp,
          replyTr: 'Kombi kapatılıyor. Teşekkürler.',
          replyEn: 'Turning off the boiler. Thank you.',
        );
      }
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 22.5,
        newPreset: PresetId.konfor,
        replyTr: 'Kombi açılıyor ve sıcaklık 22.5 dereceye ayarlanıyor. Teşekkürler.',
        replyEn: 'Turning on the boiler at 22.5 degrees. Thank you.',
      );
    }

    if (isNegative) {
      return const VoiceCommandResult(
        handled: true,
        replyTr: 'Anlaşıldı, mevcut ayar korunuyor. Teşekkürler.',
        replyEn: 'Understood, keeping current settings. Thank you.',
      );
    }

    // 2) Full thermostat voice command parsing
    final parsed = ThermostatMath.parseVoiceCommand(
      rawInput,
      currentTargetTemp: currentTargetTemp,
    );
    if (!parsed.handled) {
      return parsed;
    }

    if (parsed.newTargetTemp == ThermostatMath.minTemp) {
      return VoiceCommandResult(
        handled: true,
        newTargetTemp: parsed.newTargetTemp,
        newPreset: parsed.newPreset,
        replyTr: tr ? 'Kombi kapatılıyor. Teşekkürler.' : 'Turning off the boiler. Thank you.',
        replyEn: 'Turning off the boiler. Thank you.',
      );
    }

    final spokenTemp = parsed.newTargetTemp != null
        ? formatSpokenNumber(parsed.newTargetTemp!)
        : '';
    if (spokenTemp.isNotEmpty) {
      return VoiceCommandResult(
        handled: true,
        newTargetTemp: parsed.newTargetTemp,
        newPreset: parsed.newPreset,
        replyTr: 'Sıcaklık $spokenTemp dereceye ayarlanıyor. Teşekkürler.',
        replyEn: 'Setting temperature to $spokenTemp degrees. Thank you.',
      );
    }

    return VoiceCommandResult(
      handled: true,
      newTargetTemp: parsed.newTargetTemp,
      newPreset: parsed.newPreset,
      navigateTab: parsed.navigateTab,
      replyTr: '${parsed.replyTr} Teşekkürler.',
      replyEn: '${parsed.replyEn} Thank you.',
    );
  }

  static String formatCallDuration(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
