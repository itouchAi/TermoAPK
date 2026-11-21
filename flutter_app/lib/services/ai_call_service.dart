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

  /// Evaluates whether the AI phone call assistant should ring on a boiler/safety transition.
  static AiCallTriggerDecision evaluateTrigger({
    required bool enabled,
    required AiCallTriggerMode triggerMode,
    required bool wasHeating,
    required BoilerTelemetry nextBoiler,
    required SafetyGuardStatus safety,
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
    final criticalDetected = safety.hasCriticalAlert;

    switch (triggerMode) {
      case AiCallTriggerMode.onIgnition:
        if (ignitionDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.ignition,
            urgent: false,
          );
        }
        return const AiCallTriggerDecision(shouldCall: false);

      case AiCallTriggerMode.ignitionAndSafety:
        if (criticalDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.safetyAlert,
            urgent: true,
          );
        }
        if (ignitionDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.ignition,
            urgent: false,
          );
        }
        return const AiCallTriggerDecision(shouldCall: false);

      case AiCallTriggerMode.criticalOnly:
        if (criticalDetected) {
          return const AiCallTriggerDecision(
            shouldCall: true,
            reason: AiCallReason.safetyAlert,
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
        return tr ? 'Kombi Ateşlenince' : 'On Boiler Ignition';
      case AiCallTriggerMode.ignitionAndSafety:
        return tr ? 'Ateşleme + Güvenlik' : 'Ignition + Safety';
      case AiCallTriggerMode.criticalOnly:
        return tr ? 'Yalnızca Kritik Uyarı' : 'Critical Alerts Only';
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
        return tr
            ? '🔥 Kombi Ateşlendi · Modülasyon %${boiler.flamePercent}'
            : '🔥 Boiler Ignited · Modulation ${boiler.flamePercent}%';
      case AiCallReason.safetyAlert:
        return '⚠️ ${safety.headline(lang)}';
      case AiCallReason.manualTest:
        return tr ? '📞 Canlı Asistan Test Araması' : '📞 Live Assistant Test Call';
    }
  }

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
    final room = roomTemp.toStringAsFixed(1);
    final target = targetTemp.toStringAsFixed(1);
    final bar = boiler.waterPressureBar.toStringAsFixed(1);
    final tr = lang == LangCode.tr;

    switch (reason) {
      case AiCallReason.safetyAlert:
        return tr
            ? 'Dikkat! Ben $assistantName. $locationName kombi sisteminde ${safety.headline(lang)} tespit edildi. Oda sıcaklığı $room°C, hedef $target°C ve tesisat su basıncı $bar Bar. Aşağıdaki hızlı kontrollerden sıcaklığı düşürebilir veya sistemi izleyebilirsiniz.'
            : 'Attention! This is $assistantName. ${safety.headline(lang)} detected at $locationName. Room is $room°C, target is $target°C, water pressure $bar Bar. You can adjust temperature below immediately.';
      case AiCallReason.ignition:
        return tr
            ? 'Merhaba, ben $assistantName. $locationName konumunda kombi brülörü az önce ateşlendi. Oda şu an $room°C, hedefiniz $target°C. Alev modülasyonu %${boiler.flamePercent} ve su basıncı $bar Bar ile sağlıklı çalışıyor.'
            : 'Hello, this is $assistantName. Boiler ignition started at $locationName. Room is currently $room°C, target is $target°C. Flame modulation is ${boiler.flamePercent}% and water pressure is $bar Bar.';
      case AiCallReason.manualTest:
        final burnerText = boiler.isHeating
            ? (tr
                ? 'kombi şu an %${boiler.flamePercent} modülasyonla ısınıyor'
                : 'the boiler is currently heating at ${boiler.flamePercent}% modulation')
            : (tr
                ? 'kombi şu an sessiz bekleme modunda'
                : 'the boiler is currently in standby');
        return tr
            ? 'Merhaba, ben $assistantName. Sesli telefon araması testi başarıyla bağlandı. $locationName için oda sıcaklığı $room°C, hedef $target°C, $burnerText ve tesisat basıncı $bar Bar.'
            : 'Hello, this is $assistantName. Voice call test connected cleanly for $locationName. Room is $room°C, target is $target°C, $burnerText, and pressure is $bar Bar.';
    }
  }

  static String formatCallDuration(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final m = (safe ~/ 60).toString().padLeft(2, '0');
    final s = (safe % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
