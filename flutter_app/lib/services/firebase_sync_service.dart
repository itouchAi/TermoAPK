import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/thermostat_state.dart';

class FirebaseSyncResult {
  final bool ok;
  final int? statusCode;
  final int? latencyMs;
  final String messageTr;
  final String messageEn;
  final double? remoteTargetTemp;
  final BoilerHardwareSensors? remoteSensors;

  const FirebaseSyncResult({
    required this.ok,
    this.statusCode,
    this.latencyMs,
    required this.messageTr,
    required this.messageEn,
    this.remoteTargetTemp,
    this.remoteSensors,
  });
}

class FirebaseSyncService {
  FirebaseSyncService._();

  static final Map<String, String> _anonymousIdTokens = <String, String>{};

  static bool isWebApiKey(String? raw) {
    final trimmed = raw?.trim() ?? '';
    return trimmed.startsWith('AIza') && trimmed.length >= 30;
  }

  static String sanitizeNodePath(String raw) {
    var cleaned = raw.trim().replaceAll(RegExp(r'\.json$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^/+|/+$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z0-9_\-/]'), '');
    return cleaned.isEmpty ? 'kombi' : cleaned;
  }

  static bool validateRtdbUrl(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  static Future<String?> _resolveRtdbAuthToken(String? apiKey) async {
    final key = apiKey?.trim() ?? '';
    if (key.isEmpty) return null;
    if (!isWebApiKey(key)) return key;

    final cached = _anonymousIdTokens[key];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final authUri = Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${Uri.encodeComponent(key)}',
      );
      final resp = await http
          .post(
            authUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'returnSecureToken': true}),
          )
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic> && decoded['idToken'] is String) {
          final idToken = decoded['idToken'] as String;
          if (idToken.isNotEmpty) {
            _anonymousIdTokens[key] = idToken;
            return idToken;
          }
        }
      }
    } catch (_) {
      // Anonymous auth may be disabled or offline; fall back cleanly.
    }
    return null;
  }

  static Uri? _buildEndpoint(
    String baseUrl,
    String? authToken, {
    String nodePath = 'kombi',
  }) {
    if (!validateRtdbUrl(baseUrl)) return null;
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final safeNode = sanitizeNodePath(nodePath);
    final token = authToken?.trim() ?? '';
    final suffix = token.isNotEmpty
        ? '/$safeNode.json?auth=${Uri.encodeComponent(token)}'
        : '/$safeNode.json';
    return Uri.tryParse('$trimmed$suffix');
  }

  static Map<String, dynamic> buildPayload({
    required String roomName,
    required String espDeviceId,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
    DateTime? timestamp,
  }) {
    return {
      'roomTemp': roomTemp,
      'targetTemp': targetTemp,
      'boilerActive': boiler.isHeating,
      'flamePercent': boiler.flamePercent,
      'pressureBar': boiler.waterPressureBar,
      'roomName': roomName,
      'espDeviceId': espDeviceId,
      'updatedAt': (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  static String buildPayloadPreviewJson({
    required String roomName,
    required String espDeviceId,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
    DateTime? timestamp,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      buildPayload(
        roomName: roomName,
        espDeviceId: espDeviceId,
        roomTemp: roomTemp,
        targetTemp: targetTemp,
        boiler: boiler,
        timestamp: timestamp,
      ),
    );
  }

  /// Pushes live thermostat & boiler telemetry to Firebase Realtime Database via HTTP PATCH.
  static Future<FirebaseSyncResult> pushState({
    required String baseUrl,
    String? apiKey,
    String nodePath = 'kombi',
    required String roomName,
    required String espDeviceId,
    required double roomTemp,
    required double targetTemp,
    required BoilerTelemetry boiler,
  }) async {
    if (!validateRtdbUrl(baseUrl)) {
      return const FirebaseSyncResult(
        ok: false,
        messageTr: 'Geçerli bir Firebase RTDB URL adresi (https://...) girin.',
        messageEn: 'Enter a valid Firebase RTDB URL (https://...).',
      );
    }

    final sw = Stopwatch()..start();
    try {
      final authToken = await _resolveRtdbAuthToken(apiKey);
      final uri = _buildEndpoint(baseUrl, authToken, nodePath: nodePath);
      if (uri == null) {
        return const FirebaseSyncResult(
          ok: false,
          messageTr: 'Geçerli bir Firebase RTDB URL adresi (https://...) girin.',
          messageEn: 'Enter a valid Firebase RTDB URL (https://...).',
        );
      }
      final resp = await http
          .patch(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
              buildPayload(
                roomName: roomName,
                espDeviceId: espDeviceId,
                roomTemp: roomTemp,
                targetTemp: targetTemp,
                boiler: boiler,
              ),
            ),
          )
          .timeout(const Duration(seconds: 7));
      sw.stop();
      final ms = sw.elapsedMilliseconds;

      if (resp.statusCode == 401 && isWebApiKey(apiKey)) {
        _anonymousIdTokens.remove(apiKey?.trim());
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final safeNode = sanitizeNodePath(nodePath);
        return FirebaseSyncResult(
          ok: true,
          statusCode: resp.statusCode,
          latencyMs: ms,
          messageTr: 'RTDB /$safeNode senkronize edildi (HTTP ${resp.statusCode} · ${ms}ms).',
          messageEn: 'RTDB /$safeNode synced (HTTP ${resp.statusCode} · ${ms}ms).',
        );
      }
      return FirebaseSyncResult(
        ok: false,
        statusCode: resp.statusCode,
        latencyMs: ms,
        messageTr: 'Firebase HTTP ${resp.statusCode}: ${resp.body.isEmpty ? 'Erişim reddedildi (Kuralları veya API anahtarını kontrol edin)' : resp.body}',
        messageEn: 'Firebase HTTP ${resp.statusCode}: ${resp.body.isEmpty ? 'Permission denied' : resp.body}',
      );
    } catch (e) {
      sw.stop();
      return FirebaseSyncResult(
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        messageTr: 'Bağlantı hatası: $e',
        messageEn: 'Connection error: $e',
      );
    }
  }

  /// Pulls remote targetTemp from Firebase Realtime Database via HTTP GET.
  static Future<FirebaseSyncResult> pullState({
    required String baseUrl,
    String? apiKey,
    String nodePath = 'kombi',
  }) async {
    if (!validateRtdbUrl(baseUrl)) {
      return const FirebaseSyncResult(
        ok: false,
        messageTr: 'Geçerli bir Firebase RTDB URL adresi girin.',
        messageEn: 'Enter a valid Firebase RTDB URL.',
      );
    }

    final sw = Stopwatch()..start();
    try {
      final authToken = await _resolveRtdbAuthToken(apiKey);
      final uri = _buildEndpoint(baseUrl, authToken, nodePath: nodePath);
      if (uri == null) {
        return const FirebaseSyncResult(
          ok: false,
          messageTr: 'Geçerli bir Firebase RTDB URL adresi girin.',
          messageEn: 'Enter a valid Firebase RTDB URL.',
        );
      }
      final resp = await http.get(uri).timeout(const Duration(seconds: 7));
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      final safeNode = sanitizeNodePath(nodePath);

      if (resp.statusCode == 401 && isWebApiKey(apiKey)) {
        _anonymousIdTokens.remove(apiKey?.trim());
      }

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final decoded = jsonDecode(resp.body);
        double? target;
        BoilerHardwareSensors? sensors;
        if (decoded is Map<String, dynamic>) {
          if (decoded['targetTemp'] is num) {
            target = ThermostatMath.snapTemperature((decoded['targetTemp'] as num).toDouble());
          }
          final hasHardwareBus = decoded['hardwareConnected'] == true ||
              decoded['supplyTemp'] is num ||
              decoded['returnTemp'] is num ||
              decoded['ionizationUa'] is num;
          if (hasHardwareBus) {
            sensors = BoilerHardwareSensors(
              isConnected: true,
              supplyTempC: (decoded['supplyTemp'] as num?)?.toDouble(),
              returnTempC: (decoded['returnTemp'] as num?)?.toDouble(),
              flamePercent: (decoded['flamePercent'] as num?)?.round(),
              pumpRpm: (decoded['pumpRpm'] as num?)?.round(),
              waterPressureBar: (decoded['pressureBar'] as num?)?.toDouble(),
              ionizationUa: (decoded['ionizationUa'] as num?)?.toDouble(),
              roomHumidityPercent: (decoded['humidity'] as num?)?.toDouble(),
              protocolLabel: (decoded['protocol'] as String?) ?? 'ESP32 / OpenTherm',
            );
          }
        }
        return FirebaseSyncResult(
          ok: true,
          statusCode: resp.statusCode,
          latencyMs: ms,
          remoteTargetTemp: target,
          remoteSensors: sensors,
          messageTr: target != null
              ? 'RTDB /$safeNode çekildi: Hedef ${target.toStringAsFixed(1)}°C (${ms}ms)'
              : 'Firebase bağlı (/$safeNode düğümü henüz boş · ${ms}ms).',
          messageEn: target != null
              ? 'Pulled from /$safeNode: Target ${target.toStringAsFixed(1)}°C (${ms}ms)'
              : 'Firebase connected (/$safeNode node empty · ${ms}ms).',
        );
      }
      return FirebaseSyncResult(
        ok: false,
        statusCode: resp.statusCode,
        latencyMs: ms,
        messageTr: 'Firebase okuma hatası (HTTP ${resp.statusCode}).',
        messageEn: 'Firebase read error (HTTP ${resp.statusCode}).',
      );
    } catch (e) {
      sw.stop();
      return FirebaseSyncResult(
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        messageTr: 'Bağlantı hatası: $e',
        messageEn: 'Connection error: $e',
      );
    }
  }
}
