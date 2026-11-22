import '../models/thermostat_state.dart';
import 'firebase_sync_service.dart';
import 'notification_service.dart';

class EspPingResult {
  final bool ok;
  final int latencyMs;
  final String timestampLabel;
  final String messageTr;
  final String messageEn;
  final EspLogEntry logEntry;

  const EspPingResult({
    required this.ok,
    required this.latencyMs,
    required this.timestampLabel,
    required this.messageTr,
    required this.messageEn,
    required this.logEntry,
  });
}

class EspLogService {
  EspLogService._();

  static List<EspLogEntry> appendLog(
    List<EspLogEntry> existing,
    EspLogEntry entry, {
    int maxEntries = 40,
  }) {
    final limit = maxEntries < 1 ? 1 : maxEntries;
    return [entry, ...existing].take(limit).toList(growable: false);
  }

  static List<EspLogEntry> filterLogs(
    List<EspLogEntry> logs, {
    EspLogCategory? category,
    bool warningsOnly = false,
  }) {
    return logs.where((entry) {
      if (warningsOnly && !entry.isWarning) return false;
      if (category != null && entry.category != category) return false;
      return true;
    }).toList(growable: false);
  }

  static int countWatchdogEvents(List<EspLogEntry> logs) {
    return logs.where((e) => e.isWarning || e.category == EspLogCategory.watchdog).length;
  }

  static int computeBurnMinutes(
    List<EspLogEntry> logs, {
    int baseMinutes = 0,
  }) {
    int seconds = 0;
    for (final entry in logs) {
      if (entry.category == EspLogCategory.burner && entry.durationSeconds > 0) {
        seconds += entry.durationSeconds;
      }
    }
    final fromLogs = seconds > 0 ? (seconds / 60).round() : 0;
    return baseMinutes > fromLogs ? baseMinutes : fromLogs;
  }

  static String formatDurationBadge(int seconds, LangCode lang) {
    final tr = lang == LangCode.tr;
    if (seconds <= 0) return '';
    if (seconds < 60) {
      return tr ? '$seconds sn' : '${seconds}s';
    }
    final totalMinutes = seconds ~/ 60;
    if (totalMinutes < 60) {
      return tr ? '$totalMinutes dk' : '${totalMinutes}m';
    }
    final hours = totalMinutes ~/ 60;
    final remMin = totalMinutes % 60;
    if (remMin == 0) {
      return tr ? '$hours sa' : '${hours}h';
    }
    return tr ? '$hours sa $remMin dk' : '${hours}h ${remMin}m';
  }

  static String categoryLabel(EspLogCategory category, LangCode lang) {
    final tr = lang == LangCode.tr;
    switch (category) {
      case EspLogCategory.burner:
        return tr ? 'Yanma' : 'Burner';
      case EspLogCategory.watchdog:
        return tr ? 'WDT / Uyarı' : 'WDT / Alert';
      case EspLogCategory.sync:
        return tr ? 'Bulut' : 'Cloud';
      case EspLogCategory.system:
        return tr ? 'Sistem' : 'System';
    }
  }

  static String exportLogsReport({
    required SystemSettingsState settings,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
    required LangCode lang,
  }) {
    final tr = lang == LangCode.tr;
    final buffer = StringBuffer();
    buffer.writeln(tr ? '=== ESP32 DONANIM & WDT RAPORU ===' : '=== ESP32 HARDWARE & WDT REPORT ===');
    buffer.writeln('${tr ? 'Cihaz Kimliği' : 'Device ID'}: ${settings.espDeviceId}');
    buffer.writeln(
      '${tr ? 'Durum' : 'Status'}: ${settings.espOnline ? (tr ? 'Çevrimiçi' : 'Online') : (tr ? 'Çevrimdışı' : 'Offline')}'
      '${settings.espLastPingAt.isNotEmpty ? ' (${settings.espLastPingAt})' : ''}',
    );
    buffer.writeln(
      '${tr ? 'WDT İzleme' : 'Watchdog'}: ${settings.espWdtEnabled ? (tr ? 'Açık' : 'On') : (tr ? 'Kapalı' : 'Off')} '
      '(${tr ? 'Sayaç' : 'Count'}: ${settings.espWdtResetCount})',
    );
    buffer.writeln(
      '${tr ? 'NVS Çevrimdışı Tampon' : 'NVS Offline Buffer'}: '
      '${settings.espOfflineBufferEnabled ? (tr ? 'Açık' : 'On') : (tr ? 'Kapalı' : 'Off')} '
      '(${settings.espOfflineBurnMinutes} ${tr ? 'dk yanma' : 'min burn'})',
    );
    buffer.writeln(
      '${tr ? 'Anlık Telemetri' : 'Live Telemetry'}: '
      '${roomTemp.toStringAsFixed(1)}°C → ${targetTemp.toStringAsFixed(1)}°C | '
      '${tr ? 'Alev' : 'Flame'} %${boiler.flamePercent} | '
      '${boiler.waterPressureBar.toStringAsFixed(1)} Bar',
    );
    buffer.writeln(tr ? '--- Son Kayıtlar (${settings.espLogs.length}) ---' : '--- Recent Logs (${settings.espLogs.length}) ---');
    if (settings.espLogs.isEmpty) {
      buffer.writeln(tr ? '(Kayıt yok)' : '(No entries)');
    } else {
      for (final log in settings.espLogs) {
        final dur = log.durationSeconds > 0 ? ' [${formatDurationBadge(log.durationSeconds, lang)}]' : '';
        final warn = log.isWarning ? ' [!]' : '';
        buffer.writeln('[${log.timestamp}] [${categoryLabel(log.category, lang)}] ${log.event}$dur$warn - ${log.detail}');
      }
    }
    return buffer.toString().trimRight();
  }

  static Future<EspPingResult> testDeviceConnection({
    required String baseUrl,
    required String espDeviceId,
    required String roomName,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
    required LangCode lang,
  }) async {
    final nowLabel = NotificationService.formatNowTime();
    final tr = lang == LangCode.tr;
    final sw = Stopwatch()..start();
    final pull = await FirebaseSyncService.pullState(baseUrl: baseUrl);
    FirebaseSyncResult push = pull;
    if (pull.ok) {
      push = await FirebaseSyncService.pushState(
        baseUrl: baseUrl,
        roomName: roomName,
        espDeviceId: espDeviceId,
        roomTemp: roomTemp,
        targetTemp: targetTemp,
        boiler: boiler,
      );
    }
    sw.stop();
    final ms = sw.elapsedMilliseconds;
    final ok = pull.ok && push.ok;

    if (ok) {
      final msgTr = 'ESP32 ($espDeviceId) RTDB bağlantısı doğrulandı · ${ms}ms';
      final msgEn = 'ESP32 ($espDeviceId) RTDB link verified · ${ms}ms';
      return EspPingResult(
        ok: true,
        latencyMs: ms,
        timestampLabel: nowLabel,
        messageTr: msgTr,
        messageEn: msgEn,
        logEntry: EspLogEntry(
          timestamp: nowLabel,
          event: tr ? 'RTDB Ping Başarılı (${ms}ms)' : 'RTDB Ping OK (${ms}ms)',
          detail: '$espDeviceId · ${roomTemp.toStringAsFixed(1)}°C / ${targetTemp.toStringAsFixed(1)}°C',
          category: EspLogCategory.sync,
        ),
      );
    }

    final reasonTr = !pull.ok ? pull.messageTr : push.messageTr;
    final reasonEn = !pull.ok ? pull.messageEn : push.messageEn;
    return EspPingResult(
      ok: false,
      latencyMs: ms,
      timestampLabel: nowLabel,
      messageTr: reasonTr,
      messageEn: reasonEn,
      logEntry: EspLogEntry(
        timestamp: nowLabel,
        event: tr ? 'WDT Bağlantı Uyarısı (${ms}ms)' : 'WDT Link Warning (${ms}ms)',
        detail: reasonTr,
        isWarning: true,
        category: EspLogCategory.watchdog,
      ),
    );
  }
}
