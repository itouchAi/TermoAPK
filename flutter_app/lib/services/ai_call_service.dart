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
  final AiCallReason callReason;
  final AlertSeverity severity;
  final String titleTr;
  final String titleEn;
  final String bodyTr;
  final String bodyEn;
  final String badgeTr;
  final String badgeEn;
  final String scheduleInfoTr;
  final String scheduleInfoEn;

  const BoilerEventAlertDecision({
    required this.shouldNotify,
    this.kind,
    this.callReason = AiCallReason.manualTest,
    this.severity = AlertSeverity.info,
    this.titleTr = '',
    this.titleEn = '',
    this.bodyTr = '',
    this.bodyEn = '',
    this.badgeTr = '',
    this.badgeEn = '',
    this.scheduleInfoTr = '',
    this.scheduleInfoEn = '',
  });

  AiCallLogEntry toAlertEntry({
    required String id,
    required MascotCharacter character,
    required double roomTemp,
    required double targetTemp,
    required bool boilerHeating,
    required String timestamp,
  }) {
    final isUrgent = severity == AlertSeverity.critical ||
        kind == BoilerEventAlertKind.highTarget;
    return AiCallLogEntry(
      id: id,
      timestamp: timestamp,
      character: character,
      reason: callReason,
      status: AiCallStatus.missed,
      durationSeconds: 0,
      summaryTr: bodyTr,
      summaryEn: bodyEn,
      actionTakenTr: '',
      actionTakenEn: '',
      roomTemp: roomTemp,
      targetTemp: targetTemp,
      boilerHeating: boilerHeating,
      urgent: isUrgent,
      isSystemAlert: true,
      badgeLabelTr: badgeTr,
      badgeLabelEn: badgeEn,
      scheduleInfoTr: scheduleInfoTr,
      scheduleInfoEn: scheduleInfoEn,
    );
  }
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
      case AiCallReason.boilerLowered:
        return tr ? '📉 Kombi Kısıldı' : '📉 Boiler Lowered';
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
            ? 'Merhaba, ben $assistantName. Kombi ateşlendi ve sıcaklık $target dereceye ayarlandı. İsterseniz Eko moduna düşürebilir ya da kapatabilirim.'
            : 'Hello, this is $assistantName. The boiler has ignited and target temperature is set to $target degrees. Would you like Eco mode or shutoff?';
      case AiCallReason.boilerLowered:
        return tr
            ? 'Merhaba, ben $assistantName. Kombi hedef sıcaklığı $target dereceye kısıldı, oda $room derece. Konfor seviyesine yükseltelim mi?'
            : 'Hello, this is $assistantName. Boiler target was lowered to $target degrees while the room is $room degrees. Should I raise it to Comfort?';
      case AiCallReason.boilerOff:
        return tr
            ? 'Merhaba, ben $assistantName. Kombi kapatıldı, ev sıcaklığı $room derece. Tekrar açalım mı?'
            : 'Hello, this is $assistantName. The boiler has been turned off; room temperature is $room degrees. Should I turn it back on?';
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
            ? 'Dikkat, ben $assistantName. Kombi su basıncı kritik seviyeye düştü, güvenli kapatma yapalım mı?'
            : 'Attention, this is $assistantName. Boiler water pressure dropped critically, should I turn it off safely?';
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
    String? scheduleTitleTr,
    String? scheduleTitleEn,
  }) {
    final tr = lang == LangCode.tr;
    final room = formatSpokenNumber(roomTemp);
    final target = formatSpokenNumber(targetTemp);
    final hasSchedule = tr
        ? (scheduleTitleTr != null && scheduleTitleTr.trim().isNotEmpty)
        : (scheduleTitleEn != null && scheduleTitleEn.trim().isNotEmpty);
    final schedPrefix = hasSchedule
        ? (tr
            ? 'Takvim ayarına (${scheduleTitleTr!.trim()}) göre işlem yapıldı: '
            : 'Executed per schedule (${scheduleTitleEn!.trim()}): ')
        : '';

    switch (reason) {
      case AiCallReason.ignition:
        return tr
            ? '${schedPrefix}Kombi açıldı, hedef sıcaklık $target°C (Oda $room°C). Eko 20°C\'ye kısalım mı yoksa kapatalım mı?'
            : '${schedPrefix}Boiler turned on at $target°C (Room $room°C). Should I lower to Eco 20°C or turn it off?';
      case AiCallReason.boilerLowered:
        return tr
            ? '${schedPrefix}Kombi hedef sıcaklığı $target°C\'ye kısıldı (Oda $room°C). Konfora yükseltelim mi yoksa kapatalım mı?'
            : '${schedPrefix}Boiler target lowered to $target°C (Room $room°C). Raise to Comfort or turn off?';
      case AiCallReason.boilerOff:
        return tr
            ? '${schedPrefix}Kombi kapatıldı ve ısıtma durduruldu (Oda $room°C). Tekrar açalım mı?'
            : '${schedPrefix}Boiler turned off and heating paused (Room $room°C). Should I turn it back on?';
      case AiCallReason.coldRoom:
        return tr
            ? '${schedPrefix}Ev sıcaklığı $room°C ile düşük seviyeye indi; kombi şu an kapalı. Kombiyi açalım mı?'
            : '${schedPrefix}Room temperature dropped to $room°C while boiler is off. Should I turn it on?';
      case AiCallReason.hotRoom:
        if (targetTemp >= highTargetTempThresholdC) {
          return tr
              ? '${schedPrefix}Hedef sıcaklık $target°C ile maksimum seviyeye alındı (Oda $room°C). Kısalım mı yoksa kapatalım mı?'
              : '${schedPrefix}Target temperature raised to maximum ($target°C) while room is $room°C. Lower or turn off?';
        }
        return tr
            ? '${schedPrefix}Ev sıcaklığı $room°C ile yüksek seviyeye ulaştı (Hedef $target°C). Kombiyi kapatalım mı?'
            : '${schedPrefix}Room temperature reached $room°C (Target $target°C). Should I turn off the boiler?';
      case AiCallReason.safetyAlert:
        return tr
            ? 'Kritik kombi emniyet uyarısı algılandı! Güvenlik için kombiyi kapatalım mı?'
            : 'Critical boiler safety alert detected! Should I shut off the boiler safely?';
      case AiCallReason.manualTest:
        return boilerHeating
            ? (tr
                ? 'Kombi aktif çalışıyor (Hedef $target°C, Oda $room°C). Ayarı değiştirelim mi?'
                : 'Boiler active (Target $target°C, Room $room°C). Would you like to adjust it?')
            : (tr
                ? 'Kombi şu an kapalı (Oda $room°C). Kombiyi açalım mı?'
                : 'Boiler idle (Room $room°C). Should I turn it on?');
    }
  }

  /// Context-specific actions presented when tapping a notification capsule, missed call banner, or history item.
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

      case AiCallReason.boilerLowered:
        if (entry.targetTemp <= 20.5) {
          return const [
            AiCallQuickAction(
              labelTr: "22.5°C'ye Yükselt (Konfor)",
              labelEn: 'Raise to 22.5°C (Comfort)',
              targetTemp: 22.5,
              logActionTr: "Bildirimden: 22.5°C Konfor'a yükseltildi",
              logActionEn: 'From alert: Raised to 22.5°C Comfort',
            ),
            AiCallQuickAction(
              labelTr: 'Hızlı Isıt / Boost (25°C)',
              labelEn: 'Boost Heat (25°C)',
              targetTemp: 25.0,
              logActionTr: 'Bildirimden: Boost (25°C) açıldı',
              logActionEn: 'From alert: Boost (25°C) activated',
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
            labelTr: "22.5°C'ye Yükselt (Konfor)",
            labelEn: 'Raise to 22.5°C (Comfort)',
            targetTemp: 22.5,
            logActionTr: "Bildirimden: 22.5°C Konfor'a yükseltildi",
            logActionEn: 'From alert: Raised to 22.5°C Comfort',
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
        if (entry.targetTemp >= 24.5) {
          return const [
            AiCallQuickAction(
              labelTr: "22.5°C'ye Düşür (Konfor)",
              labelEn: 'Lower to 22.5°C (Comfort)',
              targetTemp: 22.5,
              logActionTr: "Bildirimden: 22.5°C Konfor'a düşürüldü",
              logActionEn: 'From alert: Lowered to 22.5°C Comfort',
            ),
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
        }
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

  /// Evaluates real-time boiler, schedule & temperature notification events
  /// (Kombi açıldı / kısıldı / kapandı, Derece en yüksekte, Ev sıcaklığı düşük, Takvim planı)
  /// with voice-assistant-style actionable question phrasing so users receive full interactive
  /// alerts even when AI Voice Calls are turned off, or in parallel alongside AI Voice Calls.
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
    final schedTr = (scheduleTitleTr ?? '').trim();
    final schedEn = (scheduleTitleEn ?? '').trim();
    final hasSchedule = schedTr.isNotEmpty;

    if (!enabled && !hasSchedule) {
      return const BoilerEventAlertDecision(shouldNotify: false);
    }

    final checkNow = now ?? DateTime.now();
    final room = formatSpokenNumber(roomTemp);
    final target = formatSpokenNumber(targetTemp);
    final scheduleInfoTr = hasSchedule
        ? 'Takvim ayarına ($schedTr) göre işlem yapıldı.'
        : '';
    final scheduleInfoEn = schedEn.isNotEmpty
        ? 'Executed per calendar schedule ($schedEn).'
        : '';
    final scheduleIntroTr = hasSchedule ? 'Takvim ayarına ($schedTr) göre: ' : '';
    final scheduleIntroEn = schedEn.isNotEmpty ? 'Per schedule ($schedEn): ' : '';

    final ignitionDetected = !wasHeating && nextBoiler.isHeating;
    final shutdownDetected = wasHeating && !nextBoiler.isHeating;
    final loweredDetected = isUserChange &&
        wasHeating &&
        nextBoiler.isHeating &&
        prevTargetTemp != null &&
        (targetTemp <= prevTargetTemp - 1.5 ||
            (hasSchedule && targetTemp < prevTargetTemp - 0.05));
    final scheduleRaisedWhileHeating = hasSchedule &&
        wasHeating &&
        nextBoiler.isHeating &&
        prevTargetTemp != null &&
        targetTemp > prevTargetTemp + 0.05;
    final isHighTargetPush = isUserChange &&
        nextBoiler.isHeating &&
        targetTemp >= highTargetTempThresholdC &&
        (prevTargetTemp == null || prevTargetTemp < highTargetTempThresholdC || ignitionDetected);
    final isColdRoom = safety.freezeRisk || roomTemp <= coldRoomThresholdC;
    final isHotRoom = safety.overheat || roomTemp >= hotRoomThresholdC;

    if (safety.lowPressure) {
      if (!isUserChange &&
          !hasSchedule &&
          lastPassiveNotifyAt != null &&
          checkNow.difference(lastPassiveNotifyAt) < passiveCooldown) {
        return const BoilerEventAlertDecision(shouldNotify: false);
      }
      final pressureStr = nextBoiler.waterPressureBar.toStringAsFixed(1);
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.safetyAlert,
        callReason: AiCallReason.safetyAlert,
        severity: AlertSeverity.critical,
        titleTr: '🚨 Kritik Basınç · Kapatalım mı?',
        titleEn: '🚨 Critical Pressure · Turn Off?',
        badgeTr: 'Emniyet Uyarısı',
        badgeEn: 'Safety Alert',
        bodyTr:
            'Kombi su basıncı $pressureStr Bar seviyesine düştü (Oda $room°C). Güvenlik için kombiyi kapatalım mı?',
        bodyEn:
            'Boiler water pressure dropped to $pressureStr Bar (Room $room°C). Should I shut off the boiler safely?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
      );
    }

    if (isHighTargetPush) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.highTarget,
        callReason: AiCallReason.hotRoom,
        severity: AlertSeverity.warning,
        titleTr: '⚠️ Derece En Yüksekte · Kısalım mı?',
        titleEn: '⚠️ High Target Temp · Lower It?',
        badgeTr: hasSchedule ? 'Takvim · Yüksek Hedef' : 'Yüksek Hedef',
        badgeEn: hasSchedule ? 'Schedule · High Target' : 'High Target',
        bodyTr:
            '${scheduleIntroTr}Hedef sıcaklık $target°C ile maksimum seviyeye alındı (Oda $room°C). Kombiyi kapatalım mı yoksa 22.5°C\'ye düşürelim mi?',
        bodyEn:
            '${scheduleIntroEn}Target temperature raised to maximum ($target°C) while room is $room°C. Lower to 22.5°C or turn off?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
      );
    }

    if (ignitionDetected || scheduleRaisedWhileHeating) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.ignition,
        callReason: AiCallReason.ignition,
        severity: AlertSeverity.info,
        titleTr: hasSchedule ? '📅 Takvim · Kombi Açıldı' : '🔥 Kombi Açıldı',
        titleEn: hasSchedule ? '📅 Schedule · Boiler On' : '🔥 Boiler Turned On',
        badgeTr: hasSchedule ? 'Takvim · Isıtma Aktif' : 'Kombi Açıldı',
        badgeEn: hasSchedule ? 'Schedule · Heating On' : 'Boiler On',
        bodyTr:
            '${scheduleIntroTr}Kombi ateşlendi ve hedef sıcaklık $target°C\'ye ayarlandı (Oda $room°C). Eko 20°C\'ye düşürelim mi veya kapatalım mı?',
        bodyEn:
            '${scheduleIntroEn}Boiler ignited and target set to $target°C (Room $room°C). Lower to Eco 20°C or turn off?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
      );
    }

    if (shutdownDetected) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.boilerOff,
        callReason: AiCallReason.boilerOff,
        severity: AlertSeverity.info,
        titleTr: hasSchedule ? '📅 Takvim · Kombi Kapandı' : '⏸ Kombi Kapandı',
        titleEn: hasSchedule ? '📅 Schedule · Boiler Off' : '⏸ Boiler Turned Off',
        badgeTr: hasSchedule ? 'Takvim · Kapatma' : 'Kombi Kapandı',
        badgeEn: hasSchedule ? 'Schedule · Shutoff' : 'Boiler Off',
        bodyTr:
            '${scheduleIntroTr}Kombi kapatıldı ve ısıtma durduruldu (Oda $room°C). İsterseniz tekrar 22.5°C ile açalım mı?',
        bodyEn:
            '${scheduleIntroEn}Boiler turned off and heating paused (Room $room°C). Should I turn it back on at 22.5°C?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
      );
    }

    if (loweredDetected) {
      final prevStr = formatSpokenNumber(prevTargetTemp);
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.boilerLowered,
        callReason: AiCallReason.boilerLowered,
        severity: AlertSeverity.info,
        titleTr: hasSchedule ? '📅 Takvim · Kombi Kısıldı' : '📉 Kombi Kısıldı ($target°C)',
        titleEn: hasSchedule ? '📅 Schedule · Boiler Lowered' : '📉 Boiler Lowered ($target°C)',
        badgeTr: hasSchedule ? 'Takvim · Sıcaklık Kısıldı' : 'Kombi Kısıldı',
        badgeEn: hasSchedule ? 'Schedule · Lowered' : 'Boiler Lowered',
        bodyTr:
            '${scheduleIntroTr}Kombi sıcaklığı $prevStr°C\'den $target°C\'ye kısıldı (Oda $room°C). Konfora yükseltelim mi yoksa kapatalım mı?',
        bodyEn:
            '${scheduleIntroEn}Boiler target lowered from $prevStr°C to $target°C (Room $room°C). Raise to Comfort or turn off?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
      );
    }

    // If a schedule ran and target remained effectively unchanged (e.g. already at that target)
    if (hasSchedule) {
      final isOff = !nextBoiler.isHeating && targetTemp <= ThermostatMath.minTemp + 0.05;
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: isOff ? BoilerEventAlertKind.boilerOff : BoilerEventAlertKind.ignition,
        callReason: isOff ? AiCallReason.boilerOff : AiCallReason.ignition,
        severity: AlertSeverity.info,
        titleTr: '📅 Takvim Planı Uygulandı',
        titleEn: '📅 Schedule Plan Applied',
        badgeTr: 'Takvim Planı',
        badgeEn: 'Schedule Plan',
        bodyTr: isOff
            ? '${scheduleIntroTr}Kombi kapalı konuma alındı (Oda $room°C). Tekrar 22.5°C açalım mı?'
            : '${scheduleIntroTr}Hedef sıcaklık $target°C olarak doğrulandı (Oda $room°C). Kısma veya kapatma yapalım mı?',
        bodyEn: isOff
            ? '${scheduleIntroEn}Boiler kept off (Room $room°C). Turn on at 22.5°C?'
            : '${scheduleIntroEn}Target temperature confirmed at $target°C (Room $room°C). Lower or turn off?',
        scheduleInfoTr: scheduleInfoTr,
        scheduleInfoEn: scheduleInfoEn,
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
        callReason: AiCallReason.coldRoom,
        severity: safety.freezeRisk ? AlertSeverity.critical : AlertSeverity.warning,
        titleTr: '❄️ Ev Sıcaklığı Düşük · Açalım mı?',
        titleEn: '❄️ Low Room Temp · Turn On?',
        badgeTr: 'Düşük Sıcaklık',
        badgeEn: 'Low Room Temp',
        bodyTr:
            'Ev sıcaklığı $room°C ile düşük seviyeye indi ve kombi şu an kapalı. Kombiyi 22.5°C ile açalım mı?',
        bodyEn:
            'Room temperature dropped to $room°C while the boiler is off. Should I turn on the boiler at 22.5°C?',
      );
    }

    if (isHotRoom && nextBoiler.isHeating) {
      return BoilerEventAlertDecision(
        shouldNotify: true,
        kind: BoilerEventAlertKind.hotRoom,
        callReason: AiCallReason.hotRoom,
        severity: AlertSeverity.warning,
        titleTr: '☀️ Ev Sıcaklığı Yükseldi · Kapatalım mı?',
        titleEn: '☀️ Room Temp High · Turn Off?',
        badgeTr: 'Yüksek Oda Sıcaklığı',
        badgeEn: 'High Room Temp',
        bodyTr:
            'Ev sıcaklığı $room°C\'ye yükseldi ve kombi hâlâ aktif (Hedef $target°C). Kombiyi kapatalım mı yoksa 20°C Eko\'ya düşürelim mi?',
        bodyEn:
            'Room temperature reached $room°C while the boiler is still active (Target $target°C). Turn off or lower to Eco 20°C?',
      );
    }

    return const BoilerEventAlertDecision(shouldNotify: false);
  }
}
