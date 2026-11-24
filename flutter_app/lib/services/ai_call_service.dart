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

enum BoilerEventAlertKind {
  ignition,
  boilerLowered,
  boilerOff,
  highTarget,
  coldRoom,
  hotRoom,
  safetyAlert,
}

class BoilerEventAlertDecision {
  final bool shouldNotify;
  final BoilerEventAlertKind? kind;
  final AlertSeverity severity;
  final String titleTr;
  final String titleEn;
  final String bodyTr;
  final String bodyEn;

  const BoilerEventAlertDecision({
    required this.shouldNotify,
    this.kind,
    this.severity = AlertSeverity.info,
    this.titleTr = '',
    this.titleEn = '',
    this.bodyTr = '',
    this.bodyEn = '',
  });
}

class AiCallQuickAction {
  final String labelTr;
  final String labelEn;
  final double targetTemp;
  final String logActionTr;
  final String logActionEn;
  final bool isDanger;

  const AiCallQuickAction({
    required this.labelTr,
    required this.labelEn,
    required this.targetTemp,
    required this.logActionTr,
    required this.logActionEn,
    this.isDanger = false,
  });
}

class AiCallService {
  AiCallService._();

  static const Duration defaultCooldown = Duration(seconds: 60);
  static const Duration userActionCooldown = Duration(seconds: 4);
  static const double coldRoomThresholdC = 17.5;
  static const double hotRoomThresholdC = 26.5;
  static const double highTargetTempThresholdC = 28.0;
  static const double lowTargetTempThresholdC = 14.5;

  /// Formats `20.0` -> `20` and `21.8` -> `21.8` for natural speech readout.
  static String formatSpokenNumber(double value) {
    final fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  /// Evaluates whether the AI phone call assistant should ring on boiler state
  /// changes (ignition / shutoff), high target extremes, or room temperature / safety thresholds.
  static AiCallTriggerDecision evaluateTrigger({
    required bool enabled,
    required AiCallTriggerMode triggerMode,
    required bool wasHeating,
    required BoilerTelemetry nextBoiler,
    required SafetyGuardStatus safety,
    double roomTemp = 21.8,
    double targetTemp = 22.5,
    double? prevTargetTemp,
    bool isUserChange = false,
    DateTime? lastCallAt,
    DateTime? now,
    Duration? cooldown,
  }) {
    if (!enabled) {
      return const AiCallTriggerDecision(shouldCall: false);
    }

    final checkNow = now ?? DateTime.now();
    final effectiveCooldown = cooldown ?? (isUserChange ? userActionCooldown : defaultCooldown);
    if (lastCallAt != null && checkNow.difference(lastCallAt) < effectiveCooldown) {
      return const AiCallTriggerDecision(shouldCall: false);
    }

    final ignitionDetected = !wasHeating && nextBoiler.isHeating;
    final shutdownDetected = wasHeating && !nextBoiler.isHeating;
    final isColdRoom = safety.freezeRisk || roomTemp <= coldRoomThresholdC;
    final isHotRoom = safety.overheat || roomTemp >= hotRoomThresholdC;
    final isHighTargetPush = isUserChange &&
        nextBoiler.isHeating &&
        targetTemp >= highTargetTempThresholdC &&
        (prevTargetTemp == null || prevTargetTemp < highTargetTempThresholdC || ignitionDetected);
    final isLowTargetDrop = isUserChange &&
        !nextBoiler.isHeating &&
        targetTemp <= lowTargetTempThresholdC &&
        (prevTargetTemp == null || prevTargetTemp > lowTargetTempThresholdC);

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
        if (isHighTargetPush) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.hotRoom,
            urgent: true,
          );
        }
        if (isHotRoom && nextBoiler.isHeating) {
          return AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.hotRoom,
            urgent: safety.overheat,
          );
        }
        if (isColdRoom && !nextBoiler.isHeating) {
          return AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.coldRoom,
            urgent: safety.freezeRisk,
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
        if (isLowTargetDrop) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.coldRoom,
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
        if (isHighTargetPush) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.hotRoom,
            urgent: true,
          );
        }
        if (isColdRoom && !nextBoiler.isHeating) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.coldRoom,
            urgent: true,
          );
        }
        if (isHotRoom && nextBoiler.isHeating) {
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
    LangCode lang, {
    double? targetTemp,
  }) {
    final tr = lang == LangCode.tr;
    switch (reason) {
      case AiCallReason.ignition:
        return tr ? '🔥 Kombi Ateşlendi' : '🔥 Boiler Ignited';
      case AiCallReason.boilerOff:
        return tr ? '⏸ Kombi Kapatıldı' : '⏸ Boiler Turned Off';
      case AiCallReason.coldRoom:
        return tr ? '❄️ Düşük Sıcaklık · Açalım mı?' : '❄️ Low Temperature · Turn On?';
      case AiCallReason.hotRoom:
        if (targetTemp != null && targetTemp >= highTargetTempThresholdC) {
          return tr ? '⚠️ Yüksek Hedef Sıcaklık · Kısalım mı?' : '⚠️ High Target Temp · Lower It?';
        }
        return tr ? '☀️ Ev Sıcaklığı Yükseldi · Kapatalım mı?' : '☀️ Room Is Warm · Turn Off?';
      case AiCallReason.safetyAlert:
        return '⚠️ ${safety.headline(lang)}';
      case AiCallReason.manualTest:
        return boiler.isHeating
            ? (tr ? '📞 Kombi Aktif · Asistan Görüşmesi' : '📞 Boiler Active · Assistant Call')
            : (tr ? '📞 Kombi Kapalı · Asistan Görüşmesi' : '📞 Boiler Idle · Assistant Call');
    }
  }

  /// Concise, natural spoken briefing with full word units (`derece` / `degrees`).
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
            ? 'Merhaba, ben $assistantName. Kombi kapatıldı, ev sıcaklığı $room derece.'
            : 'Hello, this is $assistantName. The boiler has been turned off; room temperature is $room degrees.';
      case AiCallReason.coldRoom:
        return tr
            ? 'Merhaba, ben $assistantName. Ev sıcaklığı $room derece, ortam soğuk. Kombiyi açalım mı?'
            : 'Hello, this is $assistantName. Room temperature is $room degrees. Should I turn on the boiler?';
      case AiCallReason.hotRoom:
        if (roomTemp < hotRoomThresholdC && targetTemp >= highTargetTempThresholdC) {
          return tr
              ? 'Dikkat, ben $assistantName. Kombi hedef sıcaklığı $target derece ile maksimum seviyeye getirildi. Oda şu an $room derece, kombiyi kapatalım mı yoksa 22.5 dereceye düşürelim mi?'
              : 'Attention, this is $assistantName. Target temperature is raised to $target degrees while the room is $room degrees. Should I turn off the boiler or lower it?';
        }
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

    // 1) Explicit open/close/lower affirmative phrases
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
    if (text.contains('düşür') || text.contains('kıs') || text.contains('lower')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 22.5,
        newPreset: PresetId.konfor,
        replyTr: 'Sıcaklık 22.5 dereceye düşürülüyor. Teşekkürler.',
        replyEn: 'Lowering target temperature to 22.5 degrees. Thank you.',
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

    // 3) Full thermostat voice command parsing
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

  /// Concise human-readable event message shown in call history and missed/declined alert dialogs.
  static String buildAlertHeadline(
    AiCallReason reason, {
    required double roomTemp,
    required double targetTemp,
    required bool boilerHeating,
    required LangCode lang,
  }) {
    final tr = lang == LangCode.tr;
    final room = formatSpokenNumber(roomTemp);
    final target = formatSpokenNumber(targetTemp);
    switch (reason) {
      case AiCallReason.ignition:
        return tr
            ? 'Kombi açıldı / ateşlendi. Hedef sıcaklık $target°C (Oda $room°C).'
            : 'Boiler turned on / ignited. Target set to $target°C (Room $room°C).';
      case AiCallReason.boilerOff:
        return tr
            ? 'Kombi kapatıldı ve ısıtma durduruldu (Oda $room°C, Hedef $target°C).'
            : 'Boiler turned off and heating paused (Room $room°C, Target $target°C).';
      case AiCallReason.coldRoom:
        return tr
            ? 'Ev sıcaklığı $room°C ile düşük seviyeye indi; kombi şu an kapalı.'
            : 'Room temperature dropped to $room°C while the boiler is off.';
      case AiCallReason.hotRoom:
        if (targetTemp >= highTargetTempThresholdC) {
          return tr
              ? 'Hedef sıcaklık $target°C ile maksimum seviyeye alındı (Oda $room°C).'
              : 'Target temperature was raised to maximum ($target°C) while room is $room°C.';
        }
        return tr
            ? 'Ev sıcaklığı $room°C ile yüksek seviyeye ulaştı (Hedef $target°C).'
            : 'Room temperature reached $room°C (Target $target°C).';
      case AiCallReason.safetyAlert:
        return tr
            ? 'Kritik kombi emniyet uyarısı algılandı! Lütfen cihazı ve basıncı kontrol edin.'
            : 'Critical boiler safety alert detected! Please inspect pressure and status.';
      case AiCallReason.manualTest:
        return boilerHeating
            ? (tr
                ? 'Asistan araması: Kombi aktif çalışıyor (Hedef $target°C, Oda $room°C).'
                : 'Assistant call: Boiler active (Target $target°C, Room $room°C).')
            : (tr
                ? 'Asistan araması: Kombi şu an kapalı (Oda $room°C, Hedef $target°C).'
                : 'Assistant call: Boiler idle (Room $room°C, Target $target°C).');
    }
  }

  /// Context-specific actions presented when tapping a missed/declined call banner or history item.
  static List<AiCallQuickAction> suggestedActionsForEntry(AiCallLogEntry entry) {
    switch (entry.reason) {
      case AiCallReason.hotRoom:
        if (entry.targetTemp >= highTargetTempThresholdC) {
          return const [
            AiCallQuickAction(
              labelTr: "22.5°C'ye Düşür (Konfor)",
              labelEn: 'Lower to 22.5°C (Comfort)',
              targetTemp: 22.5,
              logActionTr: "Bildirimden: 22.5°C Konfor'a düşürüldü",
              logActionEn: 'From alert: Lowered to 22.5°C Comfort',
            ),
            AiCallQuickAction(
              labelTr: 'Eko Moduna Al (20°C)',
              labelEn: 'Set Eco Mode (20°C)',
              targetTemp: 20.0,
              logActionTr: "Bildirimden: Eko (20°C)'ya alındı",
              logActionEn: 'From alert: Set Eco (20°C)',
            ),
            AiCallQuickAction(
              labelTr: 'Kombiyi Kapat',
              labelEn: 'Turn Off Boiler',
              targetTemp: ThermostatMath.minTemp,
              logActionTr: 'Bildirimden: Kombi kapatıldı',
              logActionEn: 'From alert: Boiler turned off',
              isDanger: true,
            ),
          ];
        }
        return const [
          AiCallQuickAction(
            labelTr: 'Kombiyi Kapat',
            labelEn: 'Turn Off Boiler',
            targetTemp: ThermostatMath.minTemp,
            logActionTr: 'Bildirimden: Kombi kapatıldı',
            logActionEn: 'From alert: Boiler turned off',
            isDanger: true,
          ),
          AiCallQuickAction(
            labelTr: 'Eko Moduna Al (20°C)',
            labelEn: 'Set Eco Mode (20°C)',
            targetTemp: 20.0,
            logActionTr: "Bildirimden: Eko (20°C)'ya alındı",
            logActionEn: 'From alert: Set Eco (20°C)',
          ),
        ];

      case AiCallReason.coldRoom:
      case AiCallReason.boilerOff:
        return const [
          AiCallQuickAction(
            labelTr: 'Kombiyi Aç (22.5°C)',
            labelEn: 'Turn On Boiler (22.5°C)',
            targetTemp: 22.5,
            logActionTr: 'Bildirimden: Kombi açıldı (22.5°C)',
            logActionEn: 'From alert: Boiler turned on (22.5°C)',
          ),
          AiCallQuickAction(
            labelTr: 'Eko Modunda Aç (20°C)',
            labelEn: 'Open in Eco (20°C)',
            targetTemp: 20.0,
            logActionTr: 'Bildirimden: Eko (20°C) ile açıldı',
            logActionEn: 'From alert: Opened in Eco (20°C)',
          ),
          AiCallQuickAction(
            labelTr: 'Hızlı Isıt / Boost (25°C)',
            labelEn: 'Boost Heat (25°C)',
            targetTemp: 25.0,
            logActionTr: 'Bildirimden: Boost (25°C) açıldı',
            logActionEn: 'From alert: Boost (25°C) activated',
          ),
        ];

      case AiCallReason.ignition:
        return const [
          AiCallQuickAction(
            labelTr: 'Eko Moduna Düşür (20°C)',
            labelEn: 'Lower to Eco (20°C)',
            targetTemp: 20.0,
            logActionTr: "Bildirimden: Eko (20°C)'ya düşürüldü",
            logActionEn: 'From alert: Lowered to Eco (20°C)',
          ),
          AiCallQuickAction(
            labelTr: 'Kombiyi Kapat',
            labelEn: 'Turn Off Boiler',
            targetTemp: ThermostatMath.minTemp,
            logActionTr: 'Bildirimden: Kombi kapatıldı',
            logActionEn: 'From alert: Boiler turned off',
            isDanger: true,
          ),
        ];

      case AiCallReason.safetyAlert:
        return const [
          AiCallQuickAction(
            labelTr: 'Güvenlik İçin Kombiyi Kapat',
            labelEn: 'Turn Off Boiler Safely',
            targetTemp: ThermostatMath.minTemp,
            logActionTr: 'Bildirimden: Emniyet için kombi kapatıldı',
            logActionEn: 'From alert: Boiler shut off for safety',
            isDanger: true,
          ),
          AiCallQuickAction(
            labelTr: 'Eko Düşük Güç (20°C)',
            labelEn: 'Eco Low Load (20°C)',
            targetTemp: 20.0,
            logActionTr: "Bildirimden: Eko (20°C)'ya alındı",
            logActionEn: 'From alert: Set Eco (20°C)',
          ),
        ];

      case AiCallReason.manualTest:
        if (entry.boilerHeating) {
          return const [
            AiCallQuickAction(
              labelTr: 'Eko Moduna Al (20°C)',
              labelEn: 'Set Eco Mode (20°C)',
              targetTemp: 20.0,
              logActionTr: "Bildirimden: Eko (20°C)'ya alındı",
              logActionEn: 'From alert: Set Eco (20°C)',
            ),
            AiCallQuickAction(
              labelTr: 'Kombiyi Kapat',
              labelEn: 'Turn Off Boiler',
              targetTemp: ThermostatMath.minTemp,
              logActionTr: 'Bildirimden: Kombi kapatıldı',
              logActionEn: 'From alert: Boiler turned off',
              isDanger: true,
            ),
          ];
        }
        return const [
          AiCallQuickAction(
            labelTr: 'Kombiyi Aç (22.5°C)',
            labelEn: 'Turn On Boiler (22.5°C)',
            targetTemp: 22.5,
            logActionTr: 'Bildirimden: Kombi açıldı (22.5°C)',
            logActionEn: 'From alert: Boiler turned on (22.5°C)',
          ),
          AiCallQuickAction(
            labelTr: 'Eko Modu (20°C)',
            labelEn: 'Eco Mode (20°C)',
            targetTemp: 20.0,
            logActionTr: "Bildirimden: Eko (20°C)'ya alındı",
            logActionEn: 'From alert: Set Eco (20°C)',
          ),
        ];
    }
  }

  /// Prepends [entry] and keeps at most [maxEntries] recent calls (default 10).
  static List<AiCallLogEntry> appendCallHistory(
    List<AiCallLogEntry> existing,
    AiCallLogEntry entry, {
    int maxEntries = 10,
  }) {
    final next = <AiCallLogEntry>[
      entry,
      ...existing.where((e) => e.id != entry.id),
    ];
    if (next.length <= maxEntries) return next;
    return next.sublist(0, maxEntries);
  }

  /// Updates the recorded action of a call log entry by [entryId].
  static List<AiCallLogEntry> updateCallHistoryAction(
    List<AiCallLogEntry> existing,
    String entryId, {
    required String actionTr,
    required String actionEn,
  }) {
    return [
      for (final item in existing)
        if (item.id == entryId)
          item.copyWith(actionTakenTr: actionTr, actionTakenEn: actionEn)
        else
          item,
    ];
  }

  /// Evaluates real-time boiler & temperature notification events
  /// (Kombi açıldı / kısıldı / kapandı, Derece en yüksekte, Ev sıcaklığı düşük, Emniyet)
  /// so users receive full status alerts even when AI Voice Calls are turned off,
  /// or in parallel alongside AI Voice Calls.
  static BoilerEventAlertDecision evaluateBoilerEventNotification({
    required bool enabled,
    required bool wasHeating,
    required BoilerTelemetry nextBoiler,
    required SafetyGuardStatus safety,
    required String locationName,
    double roomTemp = 21.8,
    double targetTemp = 22.5,
    double? prevTargetTemp,
    bool isUserChange = false,
    String? scheduleTitleTr,
    String? scheduleTitleEn,
    DateTime? lastPassiveNotifyAt,
    DateTime? now,
    Duration passiveCooldown = const Duration(minutes: 5),
  }) {
    if (!enabled) {
      return const BoilerEventAlertDecision(shouldNotify: false);
    }

    final checkNow = now ?? DateTime.now();
    final room = formatSpokenNumber(roomTemp);
    final target = formatSpokenNumber(targetTemp);
    final schedulePrefixTr = (scheduleTitleTr != null && scheduleTitleTr.isNotEmpty)
        ? '[$scheduleTitleTr] '
        : '';
    final schedulePrefixEn = (scheduleTitleEn != null && scheduleTitleEn.isNotEmpty)
        ? '[$scheduleTitleEn] '
        : '';

    final ignitionDetected = !wasHeating && nextBoiler.isHeating;
    final shutdownDetected = wasHeating && !nextBoiler.isHeating;
    final loweredDetected = isUserChange &&
        wasHeating &&
        nextBoiler.isHeating &&
        prevTargetTemp != null &&
        targetTemp <= prevTargetTemp - 1.5;
    final isHighTargetPush = isUserChange &&
        nextBoiler.isHeating &&
        targetTemp >= highTargetTempThresholdC &&
        (prevTargetTemp == null || prevTargetTemp < highTargetTempThresholdC || ignitionDetected);
    final isColdRoom = safety.freezeRisk || roomTemp <= coldRoomThresholdC;
    final isHotRoom = safety.overheat || roomTemp >= hotRoomThresholdC;

    if (safety.lowPressure) {
      if (!isUserChange &&
          lastPassiveNotifyAt != null &&
          checkNow.difference(lastPassiveNotifyAt) < passiveCooldown) {
        return const BoilerEventAlertDecision(shouldNotify: false);
      }
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.safetyAlert,
        severity: AlertSeverity.critical,
        titleTr: '🚨 Kritik Kombi Basınç Uyarısı',
        titleEn: '🚨 Critical Boiler Pressure Alert',
        bodyTr:
            '$locationName · Su basıncı ${nextBoiler.waterPressureBar.toStringAsFixed(1)} Bar seviyesine düştü! Oda $room°C.',
        bodyEn:
            '$locationName · Water pressure dropped to ${nextBoiler.waterPressureBar.toStringAsFixed(1)} Bar! Room $room°C.',
      );
    }

    if (isHighTargetPush) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.highTarget,
        severity: AlertSeverity.warning,
        titleTr: '⚠️ Derece En Yüksekte ($target°C)',
        titleEn: '⚠️ Target Temp at Maximum ($target°C)',
        bodyTr:
            '$schedulePrefixTr$locationName · Kombi $target°C maksimum hedefe alındı. Oda şu an $room°C (${nextBoiler.statusTextTr}).',
        bodyEn:
            '$schedulePrefixEn$locationName · Target raised to $target°C. Room is $room°C (${nextBoiler.statusTextEn}).',
      );
    }

    if (ignitionDetected) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.ignition,
        severity: AlertSeverity.info,
        titleTr: '🔥 Kombi Açıldı',
        titleEn: '🔥 Boiler Turned On',
        bodyTr:
            '$schedulePrefixTr$locationName · Kombi ateşlendi, hedef $target°C (Oda $room°C · %${nextBoiler.flamePercent} alev).',
        bodyEn:
            '$schedulePrefixEn$locationName · Boiler ignited, target $target°C (Room $room°C · ${nextBoiler.flamePercent}% flame).',
      );
    }

    if (shutdownDetected) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.boilerOff,
        severity: AlertSeverity.info,
        titleTr: '⏸ Kombi Kapandı',
        titleEn: '⏸ Boiler Turned Off',
        bodyTr:
            '$schedulePrefixTr$locationName · Kombi durduruldu (Oda $room°C, Hedef $target°C).',
        bodyEn:
            '$schedulePrefixEn$locationName · Boiler shut down (Room $room°C, Target $target°C).',
      );
    }

    if (loweredDetected) {
      final prevStr = formatSpokenNumber(prevTargetTemp);
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.boilerLowered,
        severity: AlertSeverity.info,
        titleTr: '📉 Kombi Kısıldı ($target°C)',
        titleEn: '📉 Boiler Lowered ($target°C)',
        bodyTr:
            '$schedulePrefixTr$locationName · Hedef sıcaklık $prevStr°C → $target°C seviyesine düşürüldü (Oda $room°C).',
        bodyEn:
            '$schedulePrefixEn$locationName · Target lowered $prevStr°C → $target°C (Room $room°C).',
      );
    }

    // Passive thermal drift / threshold notifications (cooldown guarded)
    if (lastPassiveNotifyAt != null &&
        checkNow.difference(lastPassiveNotifyAt) < passiveCooldown) {
      return const BoilerEventAlertDecision(shouldNotify: false);
    }

    if (isColdRoom && !nextBoiler.isHeating) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.coldRoom,
        severity: safety.freezeRisk ? AlertSeverity.critical : AlertSeverity.warning,
        titleTr: '❄️ Ev Sıcaklığı Düşük ($room°C)',
        titleEn: '❄️ Low Room Temperature ($room°C)',
        bodyTr:
            '$locationName · Ev sıcaklığı $room°C seviyesine düştü ve kombi şu an kapalı (Hedef $target°C).',
        bodyEn:
            '$locationName · Room temperature dropped to $room°C while boiler is off (Target $target°C).',
      );
    }

    if (isHotRoom && nextBoiler.isHeating) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.hotRoom,
        severity: AlertSeverity.warning,
        titleTr: '☀️ Ev Sıcaklığı Yükseldi ($room°C)',
        titleEn: '☀️ Room Temperature High ($room°C)',
        bodyTr:
            '$locationName · Oda $room°C oldu ve kombi hâlâ aktif (Hedef $target°C).',
        bodyEn:
            '$locationName · Room reached $room°C while boiler is still active (Target $target°C).',
      );
    }

    return const BoilerEventAlertDecision(shouldNotify: false);
  }
}
