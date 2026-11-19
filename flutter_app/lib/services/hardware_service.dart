import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:vibration/vibration.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HapticCapabilityInfo {
  final bool hasVibrator;
  final bool hasAmplitudeControl;

  const HapticCapabilityInfo({
    required this.hasVibrator,
    required this.hasAmplitudeControl,
  });
}

class HardwareService {
  HardwareService._();

  static int scaledAmplitude(int baseAmplitude, int strengthPercent) {
    final factor = strengthPercent.clamp(40, 100) / 100.0;
    return (baseAmplitude * factor).round().clamp(1, 255);
  }

  static Future<HapticCapabilityInfo> detectHapticCapability() async {
    try {
      final hasVib = await Vibration.hasVibrator();
      final hasAmp = hasVib == true ? await Vibration.hasAmplitudeControl() : false;
      return HapticCapabilityInfo(
        hasVibrator: hasVib == true,
        hasAmplitudeControl: hasAmp == true,
      );
    } catch (_) {
      return const HapticCapabilityInfo(
        hasVibrator: false,
        hasAmplitudeControl: false,
      );
    }
  }

  static Future<void> vibrateMs(int durationMs, {int amplitude = 180}) async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        final hasAmp = await Vibration.hasAmplitudeControl();
        if (hasAmp == true) {
          await Vibration.vibrate(duration: durationMs, amplitude: amplitude.clamp(1, 255));
        } else {
          await Vibration.vibrate(duration: durationMs);
        }
        return;
      }
    } catch (_) {}

    // Fallback to Flutter system haptics when running on devices/tests without Vibration plugin
    if (durationMs >= 110) {
      HapticFeedback.heavyImpact();
    } else if (durationMs >= 70) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  static Future<void> enterSmartDisplayHardware({
    required int brightnessPercent,
    required bool keepAwake,
  }) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(
        (brightnessPercent / 100.0).clamp(0.05, 1.0),
      );
    } catch (_) {}

    try {
      if (keepAwake) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  static Future<void> updateSmartDisplayBrightness(int brightnessPercent) async {
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(
        (brightnessPercent / 100.0).clamp(0.05, 1.0),
      );
    } catch (_) {}
  }

  static Future<void> exitSmartDisplayHardware() async {
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }
}
