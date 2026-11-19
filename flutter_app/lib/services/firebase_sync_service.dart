import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/thermostat_state.dart';

class FirebaseSyncResult {
  final bool ok;
  final int? statusCode;
  final String messageTr;
  final String messageEn;
  final double? remoteTargetTemp;

  const FirebaseSyncResult({
    required this.ok,
    this.statusCode,
    required this.messageTr,
    required this.messageEn,
    this.remoteTargetTemp,
  });
}

class FirebaseSyncService {
  FirebaseSyncService._();

  static Uri? _buildEndpoint(String baseUrl, String? apiKey) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty || (!trimmed.startsWith('https://') && !trimmed.startsWith('http://'))) {
      return null;
    }
    final key = apiKey?.trim() ?? '';
    final suffix = key.isNotEmpty ? '/kombi.json?auth=${Uri.encodeComponent(key)}' : '/kombi.json';
    return Uri.tryParse('$trimmed$suffix');
  }

  /// Pushes live thermostat & boiler telemetry to Firebase Realtime Database via HTTP PATCH.
  static Future<FirebaseSyncResult> pushState({
    required String baseUrl,
    String? apiKey,
    required String roomName,
    required String espDeviceId,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
  }) async {
    final uri = _buildEndpoint(baseUrl, apiKey);
    if (uri == null) {
      return const FirebaseSyncResult(
        ok: false,
        messageTr: 'Geçerli bir Firebase RTDB URL adresi (https://...) girin.',
        messageEn: 'Enter a valid Firebase RTDB URL (https://...).',
      );
    }

    try {
      final resp = await http
          .patch(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'roomTemp': roomTemp,
              'targetTemp': targetTemp,
              'boilerActive': boiler.isHeating,
              'flamePercent': boiler.flamePercent,
              'pressureBar': boiler.waterPressureBar,
              'roomName': roomName,
              'espDeviceId': espDeviceId,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 7));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return FirebaseSyncResult(
          ok: true,
          statusCode: resp.statusCode,
          messageTr: 'Firebase RTDB senkronize edildi (HTTP ${resp.statusCode}).',
          messageEn: 'Firebase RTDB synced (HTTP ${resp.statusCode}).',
        );
      }
      return FirebaseSyncResult(
        ok: false,
        statusCode: resp.statusCode,
        messageTr: 'Firebase HTTP ${resp.statusCode}: ${resp.body.isEmpty ? 'Erişim reddedildi (Kuralları veya API anahtarını kontrol edin)' : resp.body}',
        messageEn: 'Firebase HTTP ${resp.statusCode}: ${resp.body.isEmpty ? 'Permission denied' : resp.body}',
      );
    } catch (e) {
      return FirebaseSyncResult(
        ok: false,
        messageTr: 'Bağlantı hatası: $e',
        messageEn: 'Connection error: $e',
      );
    }
  }

  /// Pulls remote targetTemp from Firebase Realtime Database via HTTP GET.
  static Future<FirebaseSyncResult> pullState({
    required String baseUrl,
    String? apiKey,
  }) async {
    final uri = _buildEndpoint(baseUrl, apiKey);
    if (uri == null) {
      return const FirebaseSyncResult(
        ok: false,
        messageTr: 'Geçerli bir Firebase RTDB URL adresi girin.',
        messageEn: 'Enter a valid Firebase RTDB URL.',
      );
    }

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 7));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        double? target;
        if (decoded is Map<String, dynamic> && decoded['targetTemp'] is num) {
          target = ThermostatMath.snapTemperature((decoded['targetTemp'] as num).toDouble());
        }
        return FirebaseSyncResult(
          ok: true,
          statusCode: resp.statusCode,
          remoteTargetTemp: target,
          messageTr: target != null
              ? 'Firebase\'den çekildi: Hedef ${target.toStringAsFixed(1)}°C'
              : 'Firebase bağlı (kombi düğümü henüz boş).',
          messageEn: target != null
              ? 'Pulled from Firebase: Target ${target.toStringAsFixed(1)}°C'
              : 'Firebase connected (kombi node empty).',
        );
      }
      return FirebaseSyncResult(
        ok: false,
        statusCode: resp.statusCode,
        messageTr: 'Firebase okuma hatası (HTTP ${resp.statusCode}).',
        messageEn: 'Firebase read error (HTTP ${resp.statusCode}).',
      );
    } catch (e) {
      return FirebaseSyncResult(
        ok: false,
        messageTr: 'Bağlantı hatası: $e',
        messageEn: 'Connection error: $e',
      );
    }
  }
}
