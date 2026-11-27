import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/house_plan_model.dart';
import '../models/thermostat_state.dart';

class HomeWidgetBridge {
  HomeWidgetBridge._();

  static const MethodChannel _channel = MethodChannel('termostat_flow/widget');

  static bool get _isAndroidNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> syncFromApp({
    required double targetTemp,
    required LangCode lang,
    required HouseFloorPlan floorPlan,
    required Map<String, RoomEspTelemetry> roomTelemetries,
    required double? mainRoomTemp,
    required bool espOnline,
    required String mainEspDeviceId,
  }) async {
    if (!_isAndroidNative) return;
    try {
      final roomsPayload = <Map<String, dynamic>>[];
      for (final room in floorPlan.rooms) {
        final tel = HouseFloorPlan.resolveRoomTelemetry(
          room: room,
          roomTelemetries: roomTelemetries,
          mainRoomTemp: mainRoomTemp,
          mainEspOnline: espOnline,
          mainEspDeviceId: mainEspDeviceId,
        );
        roomsPayload.add({
          'id': room.id,
          'name': room.name,
          'tempC': tel.online ? tel.roomTempC : null,
          'radiatorTempC': tel.online ? tel.radiatorTempC : null,
          'online': tel.online,
          'isBoilerHub': room.isBoilerHub,
        });
      }

      final payload = jsonEncode({
        'targetTemp': ThermostatMath.snapTemperature(targetTemp),
        'lang': lang == LangCode.en ? 'en' : 'tr',
        'espOnline': espOnline,
        'rooms': roomsPayload,
      });
      await _channel.invokeMethod<bool>('updateWidget', {'payload': payload});
    } catch (_) {
      // Ignore on unsupported hosts / unit tests
    }
  }

  static Future<double?> consumePendingTarget() async {
    if (!_isAndroidNative) return null;
    try {
      final raw = await _channel.invokeMethod<dynamic>('consumePendingTarget');
      if (raw is num) {
        return ThermostatMath.snapTemperature(raw.toDouble());
      }
    } catch (_) {}
    return null;
  }
}
