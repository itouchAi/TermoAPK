import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/thermostat_state.dart';
import 'ambient_audio_service.dart';
import 'hardware_service.dart';

enum AlertSeverity { info, warning, critical }

class SafetyGuardStatus {
  final bool lowPressure;
  final bool freezeRisk;
  final bool overheat;
  final bool flameHealthy;
  final double waterPressureBar;
  final double roomTemp;
  final double outsideTemp;

  const SafetyGuardStatus({
    required this.lowPressure,
    required this.freezeRisk,
    required this.overheat,
    required this.flameHealthy,
    required this.waterPressureBar,
    required this.roomTemp,
    required this.outsideTemp,
  });

  bool get hasCriticalAlert => lowPressure || freezeRisk || overheat || !flameHealthy;

  String headline(LangCode lang) {
    final tr = lang == LangCode.tr;
    if (lowPressure) {
      return tr ? 'Kritik Basınç Düşüşü (< 1.0 Bar)' : 'Critical Low Pressure (< 1.0 Bar)';
    }
    if (freezeRisk) {
      return tr ? 'Donma Riski Algılandı (< 5.0°C)' : 'Freeze Risk Detected (< 5.0°C)';
    }
    if (overheat) {
      return tr ? 'Aşırı Isınma Eşiği Aşıldı' : 'Overheat Threshold Exceeded';
    }
    if (!flameHealthy) {
      return tr ? 'Brülör Alev Kesintisi Uyarısı' : 'Boiler Flame Loss Warning';
    }
    return tr
        ? 'Basınç & Donma Koruma İzleyicisi Devrede'
        : 'Pressure & Freeze Protection Guard Active';
  }
}

class NotificationDispatchResult {
  final String title;
  final String body;
  final AlertSeverity severity;
  final bool telegramAttempted;
  final bool telegramDelivered;
  final String statusTextTr;
  final String statusTextEn;
  final String timestampLabel;

  const NotificationDispatchResult({
    required this.title,
    required this.body,
    required this.severity,
    required this.telegramAttempted,
    required this.telegramDelivered,
    required this.statusTextTr,
    required this.statusTextEn,
    required this.timestampLabel,
  });
}

class NotificationService {
  NotificationService._();

  static OverlayEntry? _activeOverlay;
  static Timer? _dismissTimer;

  static SafetyGuardStatus evaluateSafetyThresholds({
    required double roomTemp,
    double? outsideTemp,
    required BoilerTelemetry boiler,
    BoilerHardwareSensors? sensors,
  }) {
    final effectivePressure = sensors != null
        ? (sensors.isConnected ? sensors.waterPressureBar : null)
        : boiler.waterPressureBar;
    final lowPressure = effectivePressure != null && effectivePressure < 1.0;
    final freezeRisk = roomTemp < 5.0 || (outsideTemp != null && outsideTemp < 5.0);
    final overheat = roomTemp >= 28.5;
    final flameHealthy = !boiler.isHeating || boiler.flamePercent > 0;
    return SafetyGuardStatus(
      lowPressure: lowPressure,
      freezeRisk: freezeRisk,
      overheat: overheat,
      flameHealthy: flameHealthy,
      waterPressureBar: effectivePressure ?? boiler.waterPressureBar,
      roomTemp: roomTemp,
      outsideTemp: outsideTemp ?? roomTemp,
    );
  }

  static String formatNowTime([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Dispatches an active alert: hardware double-haptic, synthesized chime,
  /// floating top UI notification banner, and live Telegram Bot API delivery if configured.
  static Future<NotificationDispatchResult> dispatchNotification({
    BuildContext? context,
    required LangCode lang,
    required String locationName,
    required double roomTemp,
    required double targetTemp,
    double? outsideTemp,
    required BoilerTelemetry boiler,
    BoilerHardwareSensors sensors = const BoilerHardwareSensors.disconnected(),
    required SystemSettingsState settings,
    String? customTitle,
    String? customBody,
    AlertSeverity? severityOverride,
    bool suppressChime = false,
    bool showOverlayBanner = true,
  }) async {
    final tr = lang == LangCode.tr;
    final guard = evaluateSafetyThresholds(
      roomTemp: roomTemp,
      outsideTemp: outsideTemp,
      boiler: boiler,
      sensors: sensors,
    );
    final severity = severityOverride ??
        (guard.hasCriticalAlert ? AlertSeverity.critical : AlertSeverity.info);
    final isCritical = severity == AlertSeverity.critical;

    final pressurePart = (sensors.isConnected && sensors.waterPressureBar != null)
        ? ' · ${sensors.waterPressureBar!.toStringAsFixed(1)} Bar'
        : '';
    final title = customTitle ??
        (isCritical
            ? (tr ? '⚠️ Kritik Kombi Emniyet Uyarısı' : '⚠️ Critical Boiler Safety Alert')
            : (tr ? '🔔 Termostat 3 Saatlik Durum & Test Bildirimi' : '🔔 Thermostat 3h Status & Test Alert'));
    final body = customBody ??
        (tr
            ? '$locationName · Oda ${roomTemp.toStringAsFixed(1)}°C / Hedef ${targetTemp.toStringAsFixed(1)}°C$pressurePart · ${boiler.statusTextTr}'
            : '$locationName · Room ${roomTemp.toStringAsFixed(1)}°C / Target ${targetTemp.toStringAsFixed(1)}°C$pressurePart · ${boiler.statusTextEn}');

    if (settings.hapticEnabled && !suppressChime) {
      HardwareService.vibrateMs(isCritical ? 140 : 55, amplitude: isCritical ? 230 : 150);
      if (isCritical) {
        Future.delayed(const Duration(milliseconds: 180), () {
          HardwareService.vibrateMs(140, amplitude: 230);
        });
      }
    }

    if (settings.notifyChimeEnabled && !suppressChime) {
      AmbientAudioService.playNotificationChime(urgent: isCritical);
    }

    if (showOverlayBanner && context != null && context.mounted) {
      showFloatingBanner(
        context: context,
        title: title,
        body: body,
        severity: severity,
      );
    }

    final tgToken = settings.telegramToken.trim();
    final tgChatId = settings.telegramChatId.trim();
    bool attempted = false;
    bool delivered = false;

    if (tgToken.isNotEmpty && tgChatId.isNotEmpty) {
      attempted = true;
      try {
        final resp = await http
            .post(
              Uri.parse('https://api.telegram.org/bot$tgToken/sendMessage'),
              headers: const {'Content-Type': 'application/json'},
              body: jsonEncode({'chat_id': tgChatId, 'text': '$title\n$body'}),
            )
            .timeout(const Duration(seconds: 6));
        delivered = resp.statusCode >= 200 && resp.statusCode < 300;
      } catch (_) {
        delivered = false;
      }
    }

    final ts = formatNowTime();
    final statusTr = attempted
        ? (delivered
            ? '✓ Uygulama içi bildirim ve Telegram botu ($ts) ile iletildi.'
            : '✓ Cihaz bildirimi tetiklendi; Telegram API yanıt vermedi.')
        : '✓ Uygulama içi bildirim ($ts) tetiklendi. Telegram için Kasa\'dan token girin.';
    final statusEn = attempted
        ? (delivered
            ? '✓ Delivered to device banner & Telegram bot ($ts).'
            : '✓ In-app alert triggered; Telegram API unreachable.')
        : '✓ In-app alert ($ts) triggered. Add Telegram keys in Vault for push.';

    return NotificationDispatchResult(
      title: title,
      body: body,
      severity: severity,
      telegramAttempted: attempted,
      telegramDelivered: delivered,
      statusTextTr: statusTr,
      statusTextEn: statusEn,
      timestampLabel: ts,
    );
  }

  static void showFloatingBanner({
    required BuildContext context,
    required String title,
    required String body,
    AlertSeverity severity = AlertSeverity.info,
  }) {
    try {
      final overlay = Overlay.of(context, rootOverlay: true);
      _dismissBanner();

      final Color accent;
      final IconData icon;
      switch (severity) {
        case AlertSeverity.critical:
          accent = const Color(0xFFEF4444);
          icon = Icons.warning_amber_rounded;
          break;
        case AlertSeverity.warning:
          accent = const Color(0xFFF59E0B);
          icon = Icons.notifications_active_rounded;
          break;
        case AlertSeverity.info:
          accent = const Color(0xFF10B981);
          icon = Icons.notifications_active_outlined;
          break;
      }

      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (ctx) {
          final topPad = MediaQuery.of(ctx).padding.top + 10;
          return Positioned(
            top: topPad,
            left: 14,
            right: 14,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF11131C).withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: accent.withValues(alpha: 0.65), width: 1.2),
                      boxShadow: [
                        BoxShadow(color: accent.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 6)),
                        BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 20),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: 0.18),
                          ),
                          child: Icon(icon, size: 18, color: accent),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                body,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.78),
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: _dismissBanner,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded, size: 16, color: Colors.white.withValues(alpha: 0.6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

      _activeOverlay = entry;
      overlay.insert(entry);
      _dismissTimer = Timer(const Duration(seconds: 4), _dismissBanner);
    } catch (_) {}
  }

  static void _dismissBanner() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    final entry = _activeOverlay;
    _activeOverlay = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}
