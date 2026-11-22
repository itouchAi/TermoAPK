import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum PresetId { eko, konfor, gece, boost }

enum TabId { termo, hava, rapor, prog }

enum LangCode { tr, en }

class RgbAccent {
  final double r;
  final double g;
  final double b;

  const RgbAccent(this.r, this.g, this.b);

  Color toColor([double opacity = 1.0]) => Color.fromRGBO(
        (r * 255).round().clamp(0, 255),
        (g * 255).round().clamp(0, 255),
        (b * 255).round().clamp(0, 255),
        opacity,
      );

  static RgbAccent lerp(RgbAccent a, RgbAccent b, double u) {
    return RgbAccent(
      a.r + (b.r - a.r) * u,
      a.g + (b.g - a.g) * u,
      a.b + (b.b - a.b) * u,
    );
  }
}

class ThermostatPreset {
  final PresetId id;
  final String labelTr;
  final String labelEn;
  final String modeNameTr;
  final String modeNameEn;
  final double temp;
  final RgbAccent accent;
  final Color color;

  const ThermostatPreset({
    required this.id,
    required this.labelTr,
    required this.labelEn,
    required this.modeNameTr,
    required this.modeNameEn,
    required this.temp,
    required this.accent,
    required this.color,
  });
}

class TabMeta {
  final TabId id;
  final String labelTr;
  final String labelEn;
  final RgbAccent accent;
  final Color color;

  const TabMeta({
    required this.id,
    required this.labelTr,
    required this.labelEn,
    required this.accent,
    required this.color,
  });
}

class BoilerTelemetry {
  final bool isHeating;
  final int flamePercent;
  final int pumpRpm;
  final double waterPressureBar;
  final bool modulationActive;
  final String statusTextTr;
  final String statusTextEn;

  const BoilerTelemetry({
    required this.isHeating,
    required this.flamePercent,
    required this.pumpRpm,
    required this.waterPressureBar,
    required this.modulationActive,
    required this.statusTextTr,
    required this.statusTextEn,
  });
}

class ScheduleSlot {
  final String id;
  final String labelTr;
  final String labelEn;
  final String time;
  final double targetTemp;
  final bool enabled;

  const ScheduleSlot({
    required this.id,
    required this.labelTr,
    required this.labelEn,
    required this.time,
    required this.targetTemp,
    required this.enabled,
  });

  ScheduleSlot copyWith({
    String? time,
    double? targetTemp,
    bool? enabled,
  }) {
    return ScheduleSlot(
      id: id,
      labelTr: labelTr,
      labelEn: labelEn,
      time: time ?? this.time,
      targetTemp: targetTemp ?? this.targetTemp,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time,
        'targetTemp': targetTemp,
        'enabled': enabled,
      };
}

class FlowMove {
  final double ts;
  final int a;
  final int b;
  final double d;
  final RgbAccent fromAcc;
  final RgbAccent toAcc;

  const FlowMove({
    required this.ts,
    required this.a,
    required this.b,
    required this.d,
    required this.fromAcc,
    required this.toAcc,
  });
}

class FlowTabState {
  final double x;
  final double rise;
  final double sx;
  final RgbAccent acc;
  final double tapX;
  final double tapAge;
  final double sw;
  final int cur;
  final double draw;

  const FlowTabState({
    required this.x,
    required this.rise,
    required this.sx,
    required this.acc,
    required this.tapX,
    required this.tapAge,
    required this.sw,
    required this.cur,
    required this.draw,
  });
}

class VoiceCommandResult {
  final bool handled;
  final double? newTargetTemp;
  final PresetId? newPreset;
  final TabId? navigateTab;
  final String replyTr;
  final String replyEn;

  const VoiceCommandResult({
    required this.handled,
    this.newTargetTemp,
    this.newPreset,
    this.navigateTab,
    required this.replyTr,
    required this.replyEn,
  });
}

abstract final class ThermostatMath {
  static const double minTemp = 10.0;
  static const double maxTemp = 30.0;
  static const double tempStep = 0.5;
  static const double dialStartDeg = -135.0;
  static const double dialEndDeg = 135.0;

  static const List<double> tabXs = [240.0, 440.0, 640.0, 840.0];

  static const List<ThermostatPreset> presets = [
    ThermostatPreset(
      id: PresetId.eko,
      labelTr: 'EKO',
      labelEn: 'ECO',
      modeNameTr: 'EKO MODU',
      modeNameEn: 'ECO MODE',
      temp: 20.0,
      accent: RgbAccent(0.22, 0.85, 0.58),
      color: Color(0xFF38D994),
    ),
    ThermostatPreset(
      id: PresetId.konfor,
      labelTr: 'KONFOR',
      labelEn: 'COMFORT',
      modeNameTr: 'KONFOR MODU',
      modeNameEn: 'COMFORT MODE',
      temp: 22.5,
      accent: RgbAccent(1.0, 0.48, 0.14),
      color: Color(0xFFFF7A24),
    ),
    ThermostatPreset(
      id: PresetId.gece,
      labelTr: 'GECE',
      labelEn: 'NIGHT',
      modeNameTr: 'GECE MODU',
      modeNameEn: 'NIGHT MODE',
      temp: 18.5,
      accent: RgbAccent(0.46, 0.48, 1.0),
      color: Color(0xFF757AFF),
    ),
    ThermostatPreset(
      id: PresetId.boost,
      labelTr: 'BOOST',
      labelEn: 'BOOST',
      modeNameTr: 'BOOST MODU',
      modeNameEn: 'BOOST MODE',
      temp: 25.0,
      accent: RgbAccent(1.0, 0.30, 0.28),
      color: Color(0xFFFF4D47),
    ),
  ];

  static const List<TabMeta> tabs = [
    TabMeta(
      id: TabId.termo,
      labelTr: 'Termo.',
      labelEn: 'Thermo',
      accent: RgbAccent(1.0, 0.48, 0.14),
      color: Color(0xFFFF7A24),
    ),
    TabMeta(
      id: TabId.hava,
      labelTr: 'Hava',
      labelEn: 'Weather',
      accent: RgbAccent(0.20, 0.72, 1.0),
      color: Color(0xFF33B8FF),
    ),
    TabMeta(
      id: TabId.rapor,
      labelTr: 'Rapor',
      labelEn: 'Report',
      accent: RgbAccent(0.55, 0.40, 1.0),
      color: Color(0xFF8C66FF),
    ),
    TabMeta(
      id: TabId.prog,
      labelTr: 'Prog.',
      labelEn: 'Sched.',
      accent: RgbAccent(0.25, 0.92, 0.65),
      color: Color(0xFF40EB9E),
    ),
  ];

  static const List<ScheduleSlot> defaultSchedule = [
    ScheduleSlot(id: 'night', labelTr: 'Gece Modu', labelEn: 'Night Mode', time: '23:00', targetTemp: 19.0, enabled: true),
    ScheduleSlot(id: 'morning', labelTr: 'Sabah Modu', labelEn: 'Morning Mode', time: '06:30', targetTemp: 23.0, enabled: true),
    ScheduleSlot(id: 'away', labelTr: 'Dışarıda Modu', labelEn: 'Away Mode', time: '08:00', targetTemp: 17.5, enabled: true),
    ScheduleSlot(id: 'evening', labelTr: 'Akşam Konforu', labelEn: 'Evening Comfort', time: '18:30', targetTemp: 22.5, enabled: true),
  ];

  static double clamp01(double v) => v.clamp(0.0, 1.0);

  static double lerp(double a, double b, double u) => a + (b - a) * u;

  static double snapTemperature(double temp) {
    final c = temp.clamp(minTemp, maxTemp);
    return (c * 2.0).round() / 2.0;
  }

  static double tempToAngleDeg(double temp) {
    final norm = ((temp - minTemp) / (maxTemp - minTemp)).clamp(0.0, 1.0);
    return lerp(dialStartDeg, dialEndDeg, norm);
  }

  static double pointerOffsetToTemp(double dx, double dy) {
    var deg = math.atan2(dx, -dy) * 180.0 / math.pi;
    if (deg > dialEndDeg) deg = dialEndDeg;
    if (deg < dialStartDeg) deg = dialStartDeg;
    final norm = (deg - dialStartDeg) / (dialEndDeg - dialStartDeg);
    return snapTemperature(lerp(minTemp, maxTemp, norm));
  }

  static ThermostatPreset? findMatchingPreset(double targetTemp) {
    for (final p in presets) {
      if ((p.temp - targetTemp).abs() < 0.05) return p;
    }
    return null;
  }

  static RgbAccent resolveThermostatAccent(double targetTemp, PresetId? activePreset) {
    if (activePreset != null) {
      for (final p in presets) {
        if (p.id == activePreset) return p.accent;
      }
    }
    if (targetTemp <= 19.0) return const RgbAccent(0.46, 0.48, 1.0);
    if (targetTemp <= 21.0) return const RgbAccent(0.22, 0.85, 0.58);
    if (targetTemp <= 23.5) return const RgbAccent(1.0, 0.48, 0.14);
    return const RgbAccent(1.0, 0.30, 0.28);
  }

  static Color resolveThermostatColor(double targetTemp, PresetId? activePreset) {
    return resolveThermostatAccent(targetTemp, activePreset).toColor();
  }

  static BoilerTelemetry computeBoilerTelemetry(double roomTemp, double targetTemp) {
    final delta = targetTemp - roomTemp;
    if (delta <= 0.1) {
      return const BoilerTelemetry(
        isHeating: false,
        flamePercent: 0,
        pumpRpm: 0,
        waterPressureBar: 1.6,
        modulationActive: false,
        statusTextTr: 'Beklemede',
        statusTextEn: 'Standby',
      );
    }
    final flamePercent = (20.0 + (delta / 3.5) * 80.0).clamp(20.0, 100.0).round();
    final pumpRpm = (1280.0 + (flamePercent / 100.0) * 1120.0).round();
    final modulationActive = flamePercent < 75;
    return BoilerTelemetry(
      isHeating: true,
      flamePercent: flamePercent,
      pumpRpm: pumpRpm,
      waterPressureBar: 1.6,
      modulationActive: modulationActive,
      statusTextTr: modulationActive ? 'Modülasyon · %$flamePercent' : 'Yüksek Alev · %$flamePercent',
      statusTextEn: modulationActive ? 'Modulating · $flamePercent%' : 'High Flame · $flamePercent%',
    );
  }

  static double _eOut(double u) => 1.0 - math.pow(1.0 - clamp01(u), 5).toDouble();

  static double _eIO(double u) {
    final c = clamp01(u);
    return c < 0.5 ? 4.0 * c * c * c : 1.0 - math.pow(-2.0 * c + 2.0, 3).toDouble() / 2.0;
  }

  static double moveLength(int deltaTabs) {
    final n = deltaTabs.abs();
    return n <= 1 ? 0.65 : n <= 2 ? 0.8 : 0.95;
  }

  static FlowTabState computeFlowState(
    double t,
    FlowMove? move,
    int activeIndex,
    RgbAccent liveAccent,
  ) {
    if (move == null || t < move.ts) {
      return FlowTabState(
        x: tabXs[activeIndex.clamp(0, 3)],
        rise: 1.0,
        sx: 1.0,
        acc: liveAccent,
        tapX: 0.0,
        tapAge: -1.0,
        sw: 0.0,
        cur: activeIndex,
        draw: 1.0,
      );
    }

    final rawK = (t - move.ts) / move.d;
    final u = _eIO(rawK);
    final k = clamp01(rawK);
    final x = lerp(tabXs[move.a], tabXs[move.b], u);
    final dive = math.sin(math.pi * math.min(1.0, k * 1.08));
    var rise = 1.0 - 0.9 * math.pow(dive, 0.7).toDouble();
    if (k >= 1.0) {
      rise = 1.0 + 0.06 * math.exp(-(t - move.ts - move.d) * 9.0) * math.sin((t - move.ts - move.d) * 22.0);
    }
    final sx = 1.0 + 0.55 * math.sin(math.pi * k) * ((move.b - move.a).abs() > 1 ? 1.25 : 1.0);
    var acc = RgbAccent.lerp(move.fromAcc, move.toAcc, u);
    if (t >= move.ts + move.d + 0.25) {
      acc = liveAccent;
    }
    final tapAge = t - move.ts;
    final sw = clamp01((t - move.ts - move.d * 0.9) / 0.9);
    final draw = k < 0.5 ? 1.0 - _eIO((k - 0.25) / 0.25) : _eOut((t - move.ts - move.d * 0.5) / 0.6);

    return FlowTabState(
      x: x,
      rise: rise,
      sx: sx,
      acc: acc,
      tapX: tabXs[move.b],
      tapAge: tapAge,
      sw: sw,
      cur: move.b,
      draw: draw,
    );
  }

  static double? _extractSignedOrUnsignedDeltaNumber(String text) {
    final numMatch = RegExp(r'(\d+(?:[.,]\d)?)').firstMatch(text);
    if (numMatch != null) {
      return double.tryParse(numMatch.group(1)!.replaceAll(',', '.'));
    }
    const wordMap = <String, double>{
      'yarım': 0.5,
      'half': 0.5,
      'bir': 1.0,
      'one': 1.0,
      'iki': 2.0,
      'two': 2.0,
      'üç': 3.0,
      'three': 3.0,
      'dört': 4.0,
      'four': 4.0,
      'beş': 5.0,
      'five': 5.0,
      'altı': 6.0,
      'six': 6.0,
      'yedi': 7.0,
      'seven': 7.0,
      'sekiz': 8.0,
      'eight': 8.0,
      'dokuz': 9.0,
      'nine': 9.0,
      'on': 10.0,
      'ten': 10.0,
    };
    final tokens = text.split(RegExp(r'[\s.,!?°]+'));
    for (final tok in tokens) {
      if (wordMap.containsKey(tok)) {
        return wordMap[tok];
      }
    }
    return null;
  }

  static VoiceCommandResult parseVoiceCommand(
    String raw, {
    double currentTargetTemp = 22.5,
  }) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) {
      return const VoiceCommandResult(
        handled: false,
        replyTr: 'Bir komut söyleyin, yazın veya aşağıdan seçin.',
        replyEn: 'Speak, type, or pick a command below.',
      );
    }

    // 1) Boiler shutoff / standby commands ("kombiyi kapat", "ısıtmayı kapat", "turn off")
    if (text.contains('kapat') ||
        text.contains('durdur') ||
        text.contains('kapa') ||
        text.contains('turn off') ||
        text.contains('boiler off') ||
        text.contains('stop heating')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: minTemp,
        newPreset: null,
        navigateTab: TabId.termo,
        replyTr: 'Kombi kapatıldı ve bekleme moduna (10.0°C) alındı.',
        replyEn: 'Boiler turned off and placed in standby (10.0°C).',
      );
    }

    // 2) Relative adjustments ("kombiyi 5 derece arttır", "2 derece azalt", "düşür", "yükselt")
    final hasIncrease = text.contains('arttır') ||
        text.contains('artır') ||
        text.contains('yükselt') ||
        text.contains('çoğalt') ||
        text.contains('aç ') ||
        text.contains('increase') ||
        text.contains('raise') ||
        text.contains('up');
    final hasDecrease = text.contains('azalt') ||
        text.contains('düşür') ||
        text.contains('indir') ||
        text.contains('kıs') ||
        text.contains('decrease') ||
        text.contains('lower') ||
        text.contains('down');

    if (hasIncrease || hasDecrease) {
      final rawDelta = _extractSignedOrUnsignedDeltaNumber(text) ?? 1.0;
      final delta = rawDelta.clamp(0.5, 15.0);
      final next = snapTemperature(currentTargetTemp + (hasDecrease ? -delta : delta));
      final preset = findMatchingPreset(next);
      return VoiceCommandResult(
        handled: true,
        newTargetTemp: next,
        newPreset: preset?.id,
        navigateTab: TabId.termo,
        replyTr: hasDecrease
            ? 'Sıcaklık ${delta.toStringAsFixed(1)}°C azaltılarak ${next.toStringAsFixed(1)}°C yapıldı.'
            : 'Sıcaklık ${delta.toStringAsFixed(1)}°C arttırılarak ${next.toStringAsFixed(1)}°C yapıldı.',
        replyEn: hasDecrease
            ? 'Temperature lowered by ${delta.toStringAsFixed(1)}°C to ${next.toStringAsFixed(1)}°C.'
            : 'Temperature raised by ${delta.toStringAsFixed(1)}°C to ${next.toStringAsFixed(1)}°C.',
      );
    }

    // 3) Boiler turn-on command ("kombiyi aç", "ısıtmayı başlat", "turn on")
    if ((text.contains('kombi') && text.contains('aç')) ||
        (text.contains('ısıt') && (text.contains('aç') || text.contains('başlat'))) ||
        text.contains('turn on') ||
        text.contains('start heating')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 23.0,
        newPreset: PresetId.konfor,
        navigateTab: TabId.termo,
        replyTr: 'Kombi açıldı ve hedef sıcaklık 23.0°C olarak ayarlandı.',
        replyEn: 'Boiler turned on and target set to 23.0°C.',
      );
    }

    // 4) Preset modes ("eko", "konfor", "gece", "boost")
    if (text.contains('eko') || text.contains('eco')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 20.0,
        newPreset: PresetId.eko,
        navigateTab: TabId.termo,
        replyTr: 'Eko modu (20.0°C) etkinleştirildi.',
        replyEn: 'Eco mode (20.0°C) activated.',
      );
    }
    if (text.contains('konfor') || text.contains('comfort')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 22.5,
        newPreset: PresetId.konfor,
        navigateTab: TabId.termo,
        replyTr: 'Konfor modu (22.5°C) etkinleştirildi.',
        replyEn: 'Comfort mode (22.5°C) activated.',
      );
    }
    if (text.contains('gece') || text.contains('night')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 18.5,
        newPreset: PresetId.gece,
        navigateTab: TabId.termo,
        replyTr: 'Gece modu (18.5°C) etkinleştirildi.',
        replyEn: 'Night mode (18.5°C) activated.',
      );
    }
    if (text.contains('boost') || text.contains('hızlı') || text.contains('yüksek') || text.contains('turbo')) {
      return const VoiceCommandResult(
        handled: true,
        newTargetTemp: 25.0,
        newPreset: PresetId.boost,
        navigateTab: TabId.termo,
        replyTr: 'Boost modu (25.0°C) etkinleştirildi.',
        replyEn: 'Boost mode (25.0°C) activated.',
      );
    }

    // 5) Explicit target temperature ("24 derece yap", "23.5", "22°")
    final tempMatch = RegExp(r'(\d{2}(?:[.,]\d)?)').firstMatch(text);
    if (tempMatch != null) {
      final parsed = double.tryParse(tempMatch.group(1)!.replaceAll(',', '.'));
      if (parsed != null && parsed >= 5.0 && parsed <= 40.0) {
        final snapped = snapTemperature(parsed);
        final preset = findMatchingPreset(snapped);
        return VoiceCommandResult(
          handled: true,
          newTargetTemp: snapped,
          newPreset: preset?.id,
          navigateTab: TabId.termo,
          replyTr: 'Hedef sıcaklık ${snapped.toStringAsFixed(1)}°C olarak ayarlandı.',
          replyEn: 'Target temperature set to ${snapped.toStringAsFixed(1)}°C.',
        );
      }
    }

    // 6) Tab navigation
    if (text.contains('hava') || text.contains('weather')) {
      return const VoiceCommandResult(
        handled: true,
        navigateTab: TabId.hava,
        replyTr: 'Hava durumu ekranına geçiliyor.',
        replyEn: 'Opening weather forecast.',
      );
    }
    if (text.contains('rapor') || text.contains('analiz') || text.contains('tüketim') || text.contains('report')) {
      return const VoiceCommandResult(
        handled: true,
        navigateTab: TabId.rapor,
        replyTr: 'Tüketim ve analiz raporuna geçiliyor.',
        replyEn: 'Opening consumption report.',
      );
    }
    if (text.contains('program') || text.contains('zaman') || text.contains('schedule')) {
      return const VoiceCommandResult(
        handled: true,
        navigateTab: TabId.prog,
        replyTr: 'Haftalık zaman programına geçiliyor.',
        replyEn: 'Opening weekly schedule.',
      );
    }

    return const VoiceCommandResult(
      handled: false,
      replyTr: 'Anlaşılamadı. Örnek: "Kombiyi kapat", "5 derece arttır", "Eko mod" veya "24 derece yap".',
      replyEn: 'Not recognized. Try "Turn off boiler", "Raise 5 degrees", "Eco mode", or "Set 24°".',
    );
  }
}

enum SettingsItemId {
  vault,
  googleHome,
  smartDisplay,
  notifications,
  haptic,
  bootCeremony,
  termoBot,
  aiPhoneCall,
  espLog,
  cloudSync,
  resetHistory,
}

class EspLogEntry {
  final String timestamp;
  final String event;
  final String detail;
  final bool isWarning;

  const EspLogEntry({
    required this.timestamp,
    required this.event,
    required this.detail,
    this.isWarning = false,
  });
}

enum SmartDisplayMode {
  aod,
  silentVideoMp3,
  liveNature,
  slideshow,
  singlePhoto,
}

enum SlideTransitionEffect {
  fade,
  slide,
  zoom,
}

enum VisualLayoutMode {
  cover,
  contain,
  framed,
}

enum EqualizerStyle {
  bars,
  wave,
  pulse,
}

enum AmbientSoundtrack {
  fireplaceCrackling,
  nightRain,
  cozyJazzLofi,
  deepSpace,
  forestBreeze,
  customMp3,
}

enum MascotCharacter {
  termoBot,
  mirnav,
  puki,
  mert,
  ela,
}

enum MascotBehavior {
  idle,
  patrol,
  knock,
  think,
  read,
  deepSleep,
}

enum ScreensaverBackdrop {
  oledBlack,
  termoLab,
  warmHearth,
  nightNebula,
  custom,
}

enum BootCeremonyStyle {
  thermalPulse,
  precisionSweep,
  minimalRadar,
}

enum AiCallTriggerMode {
  onIgnition,
  ignitionAndSafety,
  criticalOnly,
}

enum AiCallReason {
  ignition,
  boilerOff,
  coldRoom,
  hotRoom,
  safetyAlert,
  manualTest,
}

class HourlyWeatherSlot {
  final String hour;
  final int temp;
  final String conditionTr;
  final String conditionEn;
  final String rainChance;
  final String windKmh;
  final IconData icon;

  const HourlyWeatherSlot({
    required this.hour,
    required this.temp,
    required this.conditionTr,
    required this.conditionEn,
    required this.rainChance,
    required this.windKmh,
    required this.icon,
  });
}

class DailyWeatherForecast {
  final String dayTr;
  final String dayEn;
  final String dateLabel;
  final String conditionTr;
  final String conditionEn;
  final int highTemp;
  final int lowTemp;
  final String rainChance;
  final IconData icon;
  final List<HourlyWeatherSlot> hourly;

  const DailyWeatherForecast({
    required this.dayTr,
    required this.dayEn,
    required this.dateLabel,
    required this.conditionTr,
    required this.conditionEn,
    required this.highTemp,
    required this.lowTemp,
    required this.rainChance,
    required this.icon,
    required this.hourly,
  });

  static const List<DailyWeatherForecast> sample5Days = [
    DailyWeatherForecast(
      dayTr: 'Bugün',
      dayEn: 'Today',
      dateLabel: '19 Kas',
      conditionTr: 'Yağmurlu',
      conditionEn: 'Rainy',
      highTemp: 20,
      lowTemp: 17,
      rainChance: '%38',
      icon: Icons.umbrella_outlined,
      hourly: [
        HourlyWeatherSlot(hour: '09:00', temp: 17, conditionTr: 'Hafif Yağmur', conditionEn: 'Light Rain', rainChance: '%30', windKmh: '12 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '12:00', temp: 19, conditionTr: 'Yağmurlu', conditionEn: 'Rainy', rainChance: '%38', windKmh: '15 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '15:00', temp: 20, conditionTr: 'Parçalı Bulutlu', conditionEn: 'Partly Cloudy', rainChance: '%25', windKmh: '14 km/s', icon: Icons.wb_cloudy_outlined),
        HourlyWeatherSlot(hour: '18:00', temp: 18, conditionTr: 'Çisenti', conditionEn: 'Drizzle', rainChance: '%45', windKmh: '16 km/s', icon: Icons.grain_rounded),
        HourlyWeatherSlot(hour: '21:00', temp: 17, conditionTr: 'Bulutlu', conditionEn: 'Cloudy', rainChance: '%20', windKmh: '11 km/s', icon: Icons.cloud_outlined),
        HourlyWeatherSlot(hour: '00:00', temp: 16, conditionTr: 'Serin', conditionEn: 'Cool', rainChance: '%15', windKmh: '10 km/s', icon: Icons.nights_stay_outlined),
      ],
    ),
    DailyWeatherForecast(
      dayTr: 'Yarın',
      dayEn: 'Tomorrow',
      dateLabel: '20 Kas',
      conditionTr: 'Gök Gürültülü Fırtına',
      conditionEn: 'Thunderstorm',
      highTemp: 21,
      lowTemp: 15,
      rainChance: '%90',
      icon: Icons.thunderstorm_outlined,
      hourly: [
        HourlyWeatherSlot(hour: '09:00', temp: 16, conditionTr: 'Sağanak', conditionEn: 'Showers', rainChance: '%75', windKmh: '19 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '12:00', temp: 19, conditionTr: 'Gök Gürültülü', conditionEn: 'Thunderstorm', rainChance: '%90', windKmh: '24 km/s', icon: Icons.thunderstorm_outlined),
        HourlyWeatherSlot(hour: '15:00', temp: 21, conditionTr: 'Kuvvetli Sağanak', conditionEn: 'Heavy Rain', rainChance: '%85', windKmh: '22 km/s', icon: Icons.thunderstorm_outlined),
        HourlyWeatherSlot(hour: '18:00', temp: 18, conditionTr: 'Yağmurlu', conditionEn: 'Rainy', rainChance: '%65', windKmh: '18 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '21:00', temp: 16, conditionTr: 'Bulutlu', conditionEn: 'Cloudy', rainChance: '%40', windKmh: '14 km/s', icon: Icons.cloud_outlined),
        HourlyWeatherSlot(hour: '00:00', temp: 15, conditionTr: 'Hafif Yağmur', conditionEn: 'Light Rain', rainChance: '%35', windKmh: '12 km/s', icon: Icons.umbrella_outlined),
      ],
    ),
    DailyWeatherForecast(
      dayTr: 'Cumartesi',
      dayEn: 'Saturday',
      dateLabel: '21 Kas',
      conditionTr: 'Gök Gürültülü Fırtına',
      conditionEn: 'Thunderstorm',
      highTemp: 19,
      lowTemp: 13,
      rainChance: '%38',
      icon: Icons.thunderstorm_outlined,
      hourly: [
        HourlyWeatherSlot(hour: '09:00', temp: 14, conditionTr: 'Çok Bulutlu', conditionEn: 'Overcast', rainChance: '%30', windKmh: '15 km/s', icon: Icons.cloud_outlined),
        HourlyWeatherSlot(hour: '12:00', temp: 18, conditionTr: 'Gök Gürültülü', conditionEn: 'Storms', rainChance: '%38', windKmh: '20 km/s', icon: Icons.thunderstorm_outlined),
        HourlyWeatherSlot(hour: '15:00', temp: 19, conditionTr: 'Sağanak', conditionEn: 'Showers', rainChance: '%42', windKmh: '18 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '18:00', temp: 16, conditionTr: 'Parçalı Bulutlu', conditionEn: 'Partly Cloudy', rainChance: '%22', windKmh: '13 km/s', icon: Icons.wb_cloudy_outlined),
        HourlyWeatherSlot(hour: '21:00', temp: 14, conditionTr: 'Açık & Serin', conditionEn: 'Clear', rainChance: '%12', windKmh: '10 km/s', icon: Icons.nights_stay_outlined),
        HourlyWeatherSlot(hour: '00:00', temp: 13, conditionTr: 'Serin', conditionEn: 'Chilly', rainChance: '%10', windKmh: '9 km/s', icon: Icons.nights_stay_outlined),
      ],
    ),
    DailyWeatherForecast(
      dayTr: 'Pazar',
      dayEn: 'Sunday',
      dateLabel: '22 Kas',
      conditionTr: 'Çok Bulutlu',
      conditionEn: 'Mostly Cloudy',
      highTemp: 17,
      lowTemp: 11,
      rainChance: '%27',
      icon: Icons.cloud_outlined,
      hourly: [
        HourlyWeatherSlot(hour: '09:00', temp: 12, conditionTr: 'Serin & Puslu', conditionEn: 'Misty', rainChance: '%18', windKmh: '10 km/s', icon: Icons.blur_on_rounded),
        HourlyWeatherSlot(hour: '12:00', temp: 16, conditionTr: 'Çok Bulutlu', conditionEn: 'Cloudy', rainChance: '%27', windKmh: '12 km/s', icon: Icons.cloud_outlined),
        HourlyWeatherSlot(hour: '15:00', temp: 17, conditionTr: 'Parçalı Bulutlu', conditionEn: 'Partly Cloudy', rainChance: '%20', windKmh: '13 km/s', icon: Icons.wb_cloudy_outlined),
        HourlyWeatherSlot(hour: '18:00', temp: 14, conditionTr: 'Bulutlu', conditionEn: 'Cloudy', rainChance: '%22', windKmh: '11 km/s', icon: Icons.cloud_outlined),
        HourlyWeatherSlot(hour: '21:00', temp: 12, conditionTr: 'Soğuk', conditionEn: 'Cold', rainChance: '%15', windKmh: '8 km/s', icon: Icons.nights_stay_outlined),
        HourlyWeatherSlot(hour: '00:00', temp: 11, conditionTr: 'Ayaz', conditionEn: 'Frosty', rainChance: '%10', windKmh: '7 km/s', icon: Icons.nights_stay_outlined),
      ],
    ),
    DailyWeatherForecast(
      dayTr: 'Pazartesi',
      dayEn: 'Monday',
      dateLabel: '23 Kas',
      conditionTr: 'Gök Gürültülü Fırtına',
      conditionEn: 'Thunderstorm',
      highTemp: 20,
      lowTemp: 13,
      rainChance: '%93',
      icon: Icons.thunderstorm_outlined,
      hourly: [
        HourlyWeatherSlot(hour: '09:00', temp: 14, conditionTr: 'Yağmurlu', conditionEn: 'Rainy', rainChance: '%78', windKmh: '18 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '12:00', temp: 18, conditionTr: 'Gök Gürültülü', conditionEn: 'Storms', rainChance: '%93', windKmh: '26 km/s', icon: Icons.thunderstorm_outlined),
        HourlyWeatherSlot(hour: '15:00', temp: 20, conditionTr: 'Sağanak Yağış', conditionEn: 'Heavy Rain', rainChance: '%88', windKmh: '24 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '18:00', temp: 17, conditionTr: 'Yağmurlu', conditionEn: 'Rainy', rainChance: '%72', windKmh: '19 km/s', icon: Icons.umbrella_outlined),
        HourlyWeatherSlot(hour: '21:00', temp: 15, conditionTr: 'Hafif Yağmur', conditionEn: 'Light Rain', rainChance: '%50', windKmh: '15 km/s', icon: Icons.grain_rounded),
        HourlyWeatherSlot(hour: '00:00', temp: 13, conditionTr: 'Bulutlu', conditionEn: 'Cloudy', rainChance: '%30', windKmh: '12 km/s', icon: Icons.cloud_outlined),
      ],
    ),
  ];
}

class SystemSettingsState {
  final List<SettingsItemId> menuOrder;
  final String vaultPin;
  final bool vaultUnlocked;
  final String telegramToken;
  final String telegramChatId;
  final bool googleHomeLinked;
  final String googleHomeRoom;
  final bool smartDisplayEnabled;
  final SmartDisplayMode smartDisplayMode;
  final int slideDurationSeconds;
  final SlideTransitionEffect slideEffect;
  final VisualLayoutMode smartDisplayLayout;
  final AmbientSoundtrack ambientSoundtrack;
  final String customAudioLabel;
  final String customAudioSource;
  final double ambientVolume;
  final bool marqueeTrackEnabled;
  final bool equalizerEnabled;
  final EqualizerStyle equalizerStyle;
  final int displayBrightness;
  final int displaySleepMinutes;
  final bool oledPixelShiftEnabled;
  final bool notifications3hEnabled;
  final bool emergencyBoilerAlerts;
  final bool weatherAlertsEnabled;
  final bool notifyChimeEnabled;
  final String lastNotificationAt;
  final bool hapticEnabled;
  final int hapticStrength;
  final bool bootCeremonyEnabled;
  final BootCeremonyStyle bootCeremonyStyle;
  final int bootCeremonyDurationMs;
  final bool bootSoundChimeEnabled;
  final bool termoBotEnabled;
  final MascotCharacter mascotCharacter;
  final int screensaverIdleSeconds;
  final ScreensaverBackdrop screensaverBackdrop;
  final bool screensaverBlurBg;
  final bool mascotSoundsEnabled;
  final String screensaverCustomBgSource;
  final String screensaverCustomBgLabel;
  final double mascotScale;
  final bool aiPhoneCallEnabled;
  final int aiCallRingSeconds;
  final AiCallTriggerMode aiCallTriggerMode;
  final bool aiCallMissedAlertEnabled;
  final bool aiCallVoiceBriefEnabled;
  final String aiCallLastOutcome;
  final String femaleVoiceName;
  final String maleVoiceName;
  final String espDeviceId;
  final bool espOnline;
  final String firebaseRtdbUrl;
  final bool cloudSyncEnabled;
  final List<EspLogEntry> espLogs;

  const SystemSettingsState({
    required this.menuOrder,
    required this.vaultPin,
    required this.vaultUnlocked,
    required this.telegramToken,
    required this.telegramChatId,
    required this.googleHomeLinked,
    required this.googleHomeRoom,
    required this.smartDisplayEnabled,
    required this.smartDisplayMode,
    required this.slideDurationSeconds,
    required this.slideEffect,
    required this.smartDisplayLayout,
    required this.ambientSoundtrack,
    required this.customAudioLabel,
    required this.customAudioSource,
    required this.ambientVolume,
    required this.marqueeTrackEnabled,
    required this.equalizerEnabled,
    required this.equalizerStyle,
    required this.displayBrightness,
    required this.displaySleepMinutes,
    required this.oledPixelShiftEnabled,
    required this.notifications3hEnabled,
    required this.emergencyBoilerAlerts,
    required this.weatherAlertsEnabled,
    required this.notifyChimeEnabled,
    required this.lastNotificationAt,
    required this.hapticEnabled,
    required this.hapticStrength,
    required this.bootCeremonyEnabled,
    required this.bootCeremonyStyle,
    required this.bootCeremonyDurationMs,
    required this.bootSoundChimeEnabled,
    required this.termoBotEnabled,
    required this.mascotCharacter,
    required this.screensaverIdleSeconds,
    required this.screensaverBackdrop,
    required this.screensaverBlurBg,
    required this.mascotSoundsEnabled,
    required this.screensaverCustomBgSource,
    required this.screensaverCustomBgLabel,
    required this.mascotScale,
    required this.aiPhoneCallEnabled,
    required this.aiCallRingSeconds,
    required this.aiCallTriggerMode,
    required this.aiCallMissedAlertEnabled,
    required this.aiCallVoiceBriefEnabled,
    required this.aiCallLastOutcome,
    this.femaleVoiceName = '',
    this.maleVoiceName = '',
    required this.espDeviceId,
    required this.espOnline,
    required this.firebaseRtdbUrl,
    required this.cloudSyncEnabled,
    required this.espLogs,
  });

  static const List<SettingsItemId> defaultMenuOrder = [
    SettingsItemId.vault,
    SettingsItemId.googleHome,
    SettingsItemId.smartDisplay,
    SettingsItemId.notifications,
    SettingsItemId.haptic,
    SettingsItemId.bootCeremony,
    SettingsItemId.termoBot,
    SettingsItemId.aiPhoneCall,
    SettingsItemId.espLog,
    SettingsItemId.cloudSync,
    SettingsItemId.resetHistory,
  ];

  factory SystemSettingsState.defaults() => const SystemSettingsState(
        menuOrder: defaultMenuOrder,
        vaultPin: '1234',
        vaultUnlocked: false,
        telegramToken: '',
        telegramChatId: '',
        googleHomeLinked: false,
        googleHomeRoom: 'Salon',
        smartDisplayEnabled: true,
        smartDisplayMode: SmartDisplayMode.slideshow,
        slideDurationSeconds: 15,
        slideEffect: SlideTransitionEffect.slide,
        smartDisplayLayout: VisualLayoutMode.cover,
        ambientSoundtrack: AmbientSoundtrack.fireplaceCrackling,
        customAudioLabel: '',
        customAudioSource: '',
        ambientVolume: 0.5,
        marqueeTrackEnabled: true,
        equalizerEnabled: true,
        equalizerStyle: EqualizerStyle.bars,
        displayBrightness: 85,
        displaySleepMinutes: 0,
        oledPixelShiftEnabled: true,
        notifications3hEnabled: true,
        emergencyBoilerAlerts: true,
        weatherAlertsEnabled: true,
        notifyChimeEnabled: true,
        lastNotificationAt: '',
        hapticEnabled: true,
        hapticStrength: 80,
        bootCeremonyEnabled: true,
        bootCeremonyStyle: BootCeremonyStyle.thermalPulse,
        bootCeremonyDurationMs: 1800,
        bootSoundChimeEnabled: true,
        termoBotEnabled: true,
        mascotCharacter: MascotCharacter.termoBot,
        screensaverIdleSeconds: 30,
        screensaverBackdrop: ScreensaverBackdrop.oledBlack,
        screensaverBlurBg: false,
        mascotSoundsEnabled: true,
        screensaverCustomBgSource: '',
        screensaverCustomBgLabel: '',
        mascotScale: 1.0,
        aiPhoneCallEnabled: true,
        aiCallRingSeconds: 10,
        aiCallTriggerMode: AiCallTriggerMode.ignitionAndSafety,
        aiCallMissedAlertEnabled: true,
        aiCallVoiceBriefEnabled: true,
        aiCallLastOutcome: '',
        femaleVoiceName: '',
        maleVoiceName: '',
        espDeviceId: 'ESP32-KOMBI-01',
        espOnline: false,
        firebaseRtdbUrl: 'https://kombi-kontrol-default-rtdb.firebaseio.com',
        cloudSyncEnabled: false,
        espLogs: [
          EspLogEntry(timestamp: '23:10', event: 'Modülasyon %36', detail: 'Oda 21.8°C → Hedef 22.5°C'),
          EspLogEntry(timestamp: '20:45', event: 'Brülör Ateşleme', detail: 'Basınç 1.6 Bar normal'),
          EspLogEntry(timestamp: '16:12', event: 'WDT Kontrolü', detail: 'Çevrimdışı tampon kaydedildi', isWarning: true),
        ],
      );

  String ambientTrackTitle(LangCode lang) {
    final tr = lang == LangCode.tr;
    switch (ambientSoundtrack) {
      case AmbientSoundtrack.fireplaceCrackling:
        return tr ? 'Şömine Çıtırtısı (Ambiyans 432Hz)' : 'Fireplace Crackling (432Hz Ambient)';
      case AmbientSoundtrack.nightRain:
        return tr ? 'Gece Yağmuru & Cam Sesi' : 'Midnight Rain on Glass';
      case AmbientSoundtrack.cozyJazzLofi:
        return tr ? 'Sıcak Lo-Fi Caz Döngüsü' : 'Warm Lo-Fi Jazz Loop';
      case AmbientSoundtrack.deepSpace:
        return tr ? 'Derin Uzay & Obsidyen Drone' : 'Deep Space Obsidian Drone';
      case AmbientSoundtrack.forestBreeze:
        return tr ? 'Gece Ormanı Esintisi' : 'Night Forest Breeze';
      case AmbientSoundtrack.customMp3:
        final trimmed = customAudioLabel.trim();
        if (trimmed.isNotEmpty) return trimmed;
        return tr ? 'Dışarıdan Özel MP3 Akışı' : 'Custom External MP3 Stream';
    }
  }

  SystemSettingsState copyWith({
    List<SettingsItemId>? menuOrder,
    String? vaultPin,
    bool? vaultUnlocked,
    String? telegramToken,
    String? telegramChatId,
    bool? googleHomeLinked,
    String? googleHomeRoom,
    bool? smartDisplayEnabled,
    SmartDisplayMode? smartDisplayMode,
    int? slideDurationSeconds,
    SlideTransitionEffect? slideEffect,
    VisualLayoutMode? smartDisplayLayout,
    AmbientSoundtrack? ambientSoundtrack,
    String? customAudioLabel,
    String? customAudioSource,
    double? ambientVolume,
    bool? marqueeTrackEnabled,
    bool? equalizerEnabled,
    EqualizerStyle? equalizerStyle,
    int? displayBrightness,
    int? displaySleepMinutes,
    bool? oledPixelShiftEnabled,
    bool? notifications3hEnabled,
    bool? emergencyBoilerAlerts,
    bool? weatherAlertsEnabled,
    bool? notifyChimeEnabled,
    String? lastNotificationAt,
    bool? hapticEnabled,
    int? hapticStrength,
    bool? bootCeremonyEnabled,
    BootCeremonyStyle? bootCeremonyStyle,
    int? bootCeremonyDurationMs,
    bool? bootSoundChimeEnabled,
    bool? termoBotEnabled,
    MascotCharacter? mascotCharacter,
    int? screensaverIdleSeconds,
    ScreensaverBackdrop? screensaverBackdrop,
    bool? screensaverBlurBg,
    bool? mascotSoundsEnabled,
    String? screensaverCustomBgSource,
    String? screensaverCustomBgLabel,
    double? mascotScale,
    bool? aiPhoneCallEnabled,
    int? aiCallRingSeconds,
    AiCallTriggerMode? aiCallTriggerMode,
    bool? aiCallMissedAlertEnabled,
    bool? aiCallVoiceBriefEnabled,
    String? aiCallLastOutcome,
    String? femaleVoiceName,
    String? maleVoiceName,
    String? espDeviceId,
    bool? espOnline,
    String? firebaseRtdbUrl,
    bool? cloudSyncEnabled,
    List<EspLogEntry>? espLogs,
  }) {
    return SystemSettingsState(
      menuOrder: menuOrder ?? this.menuOrder,
      vaultPin: vaultPin ?? this.vaultPin,
      vaultUnlocked: vaultUnlocked ?? this.vaultUnlocked,
      telegramToken: telegramToken ?? this.telegramToken,
      telegramChatId: telegramChatId ?? this.telegramChatId,
      googleHomeLinked: googleHomeLinked ?? this.googleHomeLinked,
      googleHomeRoom: googleHomeRoom ?? this.googleHomeRoom,
      smartDisplayEnabled: smartDisplayEnabled ?? this.smartDisplayEnabled,
      smartDisplayMode: smartDisplayMode ?? this.smartDisplayMode,
      slideDurationSeconds: slideDurationSeconds ?? this.slideDurationSeconds,
      slideEffect: slideEffect ?? this.slideEffect,
      smartDisplayLayout: smartDisplayLayout ?? this.smartDisplayLayout,
      ambientSoundtrack: ambientSoundtrack ?? this.ambientSoundtrack,
      customAudioLabel: customAudioLabel ?? this.customAudioLabel,
      customAudioSource: customAudioSource ?? this.customAudioSource,
      ambientVolume: (ambientVolume ?? this.ambientVolume).clamp(0.0, 1.0),
      marqueeTrackEnabled: marqueeTrackEnabled ?? this.marqueeTrackEnabled,
      equalizerEnabled: equalizerEnabled ?? this.equalizerEnabled,
      equalizerStyle: equalizerStyle ?? this.equalizerStyle,
      displayBrightness: (displayBrightness ?? this.displayBrightness).clamp(10, 100),
      displaySleepMinutes: displaySleepMinutes ?? this.displaySleepMinutes,
      oledPixelShiftEnabled: oledPixelShiftEnabled ?? this.oledPixelShiftEnabled,
      notifications3hEnabled: notifications3hEnabled ?? this.notifications3hEnabled,
      emergencyBoilerAlerts: emergencyBoilerAlerts ?? this.emergencyBoilerAlerts,
      weatherAlertsEnabled: weatherAlertsEnabled ?? this.weatherAlertsEnabled,
      notifyChimeEnabled: notifyChimeEnabled ?? this.notifyChimeEnabled,
      lastNotificationAt: lastNotificationAt ?? this.lastNotificationAt,
      hapticEnabled: hapticEnabled ?? this.hapticEnabled,
      hapticStrength: (hapticStrength ?? this.hapticStrength).clamp(40, 100),
      bootCeremonyEnabled: bootCeremonyEnabled ?? this.bootCeremonyEnabled,
      bootCeremonyStyle: bootCeremonyStyle ?? this.bootCeremonyStyle,
      bootCeremonyDurationMs: (bootCeremonyDurationMs ?? this.bootCeremonyDurationMs).clamp(900, 3500),
      bootSoundChimeEnabled: bootSoundChimeEnabled ?? this.bootSoundChimeEnabled,
      termoBotEnabled: termoBotEnabled ?? this.termoBotEnabled,
      mascotCharacter: mascotCharacter ?? this.mascotCharacter,
      screensaverIdleSeconds: screensaverIdleSeconds ?? this.screensaverIdleSeconds,
      screensaverBackdrop: screensaverBackdrop ?? this.screensaverBackdrop,
      screensaverBlurBg: screensaverBlurBg ?? this.screensaverBlurBg,
      mascotSoundsEnabled: mascotSoundsEnabled ?? this.mascotSoundsEnabled,
      screensaverCustomBgSource: screensaverCustomBgSource ?? this.screensaverCustomBgSource,
      screensaverCustomBgLabel: screensaverCustomBgLabel ?? this.screensaverCustomBgLabel,
      mascotScale: (mascotScale ?? this.mascotScale).clamp(0.60, 1.60),
      aiPhoneCallEnabled: aiPhoneCallEnabled ?? this.aiPhoneCallEnabled,
      aiCallRingSeconds: (aiCallRingSeconds ?? this.aiCallRingSeconds).clamp(5, 30),
      aiCallTriggerMode: aiCallTriggerMode ?? this.aiCallTriggerMode,
      aiCallMissedAlertEnabled: aiCallMissedAlertEnabled ?? this.aiCallMissedAlertEnabled,
      aiCallVoiceBriefEnabled: aiCallVoiceBriefEnabled ?? this.aiCallVoiceBriefEnabled,
      aiCallLastOutcome: aiCallLastOutcome ?? this.aiCallLastOutcome,
      femaleVoiceName: femaleVoiceName ?? this.femaleVoiceName,
      maleVoiceName: maleVoiceName ?? this.maleVoiceName,
      espDeviceId: espDeviceId ?? this.espDeviceId,
      espOnline: espOnline ?? this.espOnline,
      firebaseRtdbUrl: firebaseRtdbUrl ?? this.firebaseRtdbUrl,
      cloudSyncEnabled: cloudSyncEnabled ?? this.cloudSyncEnabled,
      espLogs: espLogs ?? this.espLogs,
    );
  }

  Map<String, dynamic> toJson() => {
        'menuOrder': menuOrder.map((e) => e.name).toList(),
        'vaultPin': vaultPin,
        'telegramToken': telegramToken,
        'telegramChatId': telegramChatId,
        'googleHomeLinked': googleHomeLinked,
        'googleHomeRoom': googleHomeRoom,
        'smartDisplayEnabled': smartDisplayEnabled,
        'smartDisplayMode': smartDisplayMode.name,
        'slideDurationSeconds': slideDurationSeconds,
        'slideEffect': slideEffect.name,
        'smartDisplayLayout': smartDisplayLayout.name,
        'ambientSoundtrack': ambientSoundtrack.name,
        'customAudioLabel': customAudioLabel,
        'customAudioSource': customAudioSource,
        'ambientVolume': ambientVolume,
        'marqueeTrackEnabled': marqueeTrackEnabled,
        'equalizerEnabled': equalizerEnabled,
        'equalizerStyle': equalizerStyle.name,
        'displayBrightness': displayBrightness,
        'displaySleepMinutes': displaySleepMinutes,
        'oledPixelShiftEnabled': oledPixelShiftEnabled,
        'notifications3hEnabled': notifications3hEnabled,
        'emergencyBoilerAlerts': emergencyBoilerAlerts,
        'weatherAlertsEnabled': weatherAlertsEnabled,
        'notifyChimeEnabled': notifyChimeEnabled,
        'lastNotificationAt': lastNotificationAt,
        'hapticEnabled': hapticEnabled,
        'hapticStrength': hapticStrength,
        'bootCeremonyEnabled': bootCeremonyEnabled,
        'bootCeremonyStyle': bootCeremonyStyle.name,
        'bootCeremonyDurationMs': bootCeremonyDurationMs,
        'bootSoundChimeEnabled': bootSoundChimeEnabled,
        'termoBotEnabled': termoBotEnabled,
        'mascotCharacter': mascotCharacter.name,
        'screensaverIdleSeconds': screensaverIdleSeconds,
        'screensaverBackdrop': screensaverBackdrop.name,
        'screensaverBlurBg': screensaverBlurBg,
        'mascotSoundsEnabled': mascotSoundsEnabled,
        'screensaverCustomBgSource': screensaverCustomBgSource,
        'screensaverCustomBgLabel': screensaverCustomBgLabel,
        'mascotScale': mascotScale,
        'aiPhoneCallEnabled': aiPhoneCallEnabled,
        'aiCallRingSeconds': aiCallRingSeconds,
        'aiCallTriggerMode': aiCallTriggerMode.name,
        'aiCallMissedAlertEnabled': aiCallMissedAlertEnabled,
        'aiCallVoiceBriefEnabled': aiCallVoiceBriefEnabled,
        'aiCallLastOutcome': aiCallLastOutcome,
        'femaleVoiceName': femaleVoiceName,
        'maleVoiceName': maleVoiceName,
        'espDeviceId': espDeviceId,
        'firebaseRtdbUrl': firebaseRtdbUrl,
        'cloudSyncEnabled': cloudSyncEnabled,
      };

  /// Generates a PIN-derived encrypted JSON backup envelope for zero-knowledge export.
  String buildEncryptedBackupJson({required String locationName}) {
    final plainMap = {
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'locationName': locationName,
      'settings': toJson(),
    };
    final plainBytes = utf8.encode(jsonEncode(plainMap));
    final keyBytes = utf8.encode('termostat_pbkdf2_${vaultPin}_salt_v1');
    final cipherBytes = List<int>.generate(
      plainBytes.length,
      (i) => plainBytes[i] ^ keyBytes[i % keyBytes.length] ^ ((i * 31 + 7) & 0xFF),
    );
    var fnv = 0x811C9DC5;
    for (final b in cipherBytes) {
      fnv ^= b;
      fnv = (fnv * 0x01000193) & 0xFFFFFFFF;
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'termostat-vault-aes256-v1',
      'kdf': 'PBKDF2-HMAC',
      'cipher': 'AES-256-GCM',
      'checksum': fnv.toRadixString(16).padLeft(8, '0'),
      'payload': base64Encode(cipherBytes),
    });
  }

  static T _parseEnum<T extends Enum>(String? raw, List<T> values, T fallback) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  factory SystemSettingsState.fromJson(Map<String, dynamic> map) {
    final defaults = SystemSettingsState.defaults();
    final rawOrder = map['menuOrder'];
    List<SettingsItemId> parsedOrder = defaults.menuOrder;
    if (rawOrder is List) {
      final items = <SettingsItemId>[];
      for (final name in rawOrder) {
        for (final id in SettingsItemId.values) {
          if (id.name == name && !items.contains(id)) {
            items.add(id);
          }
        }
      }
      for (final id in SystemSettingsState.defaultMenuOrder) {
        if (!items.contains(id)) items.add(id);
      }
      if (items.isNotEmpty) parsedOrder = items;
    }

    return defaults.copyWith(
      menuOrder: parsedOrder,
      vaultPin: (map['vaultPin'] as String?) ?? defaults.vaultPin,
      telegramToken: (map['telegramToken'] as String?) ?? defaults.telegramToken,
      telegramChatId: (map['telegramChatId'] as String?) ?? defaults.telegramChatId,
      googleHomeLinked: (map['googleHomeLinked'] as bool?) ?? defaults.googleHomeLinked,
      googleHomeRoom: (map['googleHomeRoom'] as String?) ?? defaults.googleHomeRoom,
      smartDisplayEnabled: (map['smartDisplayEnabled'] as bool?) ?? defaults.smartDisplayEnabled,
      smartDisplayMode: _parseEnum(map['smartDisplayMode'] as String?, SmartDisplayMode.values, defaults.smartDisplayMode),
      slideDurationSeconds: (map['slideDurationSeconds'] as int?) ?? defaults.slideDurationSeconds,
      slideEffect: _parseEnum(map['slideEffect'] as String?, SlideTransitionEffect.values, defaults.slideEffect),
      smartDisplayLayout: _parseEnum(map['smartDisplayLayout'] as String?, VisualLayoutMode.values, defaults.smartDisplayLayout),
      ambientSoundtrack: _parseEnum(map['ambientSoundtrack'] as String?, AmbientSoundtrack.values, defaults.ambientSoundtrack),
      customAudioLabel: (map['customAudioLabel'] as String?) ?? defaults.customAudioLabel,
      customAudioSource: (map['customAudioSource'] as String?) ?? defaults.customAudioSource,
      ambientVolume: (map['ambientVolume'] as num?)?.toDouble() ?? defaults.ambientVolume,
      marqueeTrackEnabled: (map['marqueeTrackEnabled'] as bool?) ?? defaults.marqueeTrackEnabled,
      equalizerEnabled: (map['equalizerEnabled'] as bool?) ?? defaults.equalizerEnabled,
      equalizerStyle: _parseEnum(map['equalizerStyle'] as String?, EqualizerStyle.values, defaults.equalizerStyle),
      displayBrightness: (map['displayBrightness'] as int?) ?? defaults.displayBrightness,
      displaySleepMinutes: (map['displaySleepMinutes'] as int?) ?? defaults.displaySleepMinutes,
      oledPixelShiftEnabled: (map['oledPixelShiftEnabled'] as bool?) ?? defaults.oledPixelShiftEnabled,
      notifications3hEnabled: (map['notifications3hEnabled'] as bool?) ?? defaults.notifications3hEnabled,
      emergencyBoilerAlerts: (map['emergencyBoilerAlerts'] as bool?) ?? defaults.emergencyBoilerAlerts,
      weatherAlertsEnabled: (map['weatherAlertsEnabled'] as bool?) ?? defaults.weatherAlertsEnabled,
      notifyChimeEnabled: (map['notifyChimeEnabled'] as bool?) ?? defaults.notifyChimeEnabled,
      lastNotificationAt: (map['lastNotificationAt'] as String?) ?? defaults.lastNotificationAt,
      hapticEnabled: (map['hapticEnabled'] as bool?) ?? defaults.hapticEnabled,
      hapticStrength: (map['hapticStrength'] as int?) ?? defaults.hapticStrength,
      bootCeremonyEnabled: (map['bootCeremonyEnabled'] as bool?) ?? defaults.bootCeremonyEnabled,
      bootCeremonyStyle: _parseEnum(map['bootCeremonyStyle'] as String?, BootCeremonyStyle.values, defaults.bootCeremonyStyle),
      bootCeremonyDurationMs: (map['bootCeremonyDurationMs'] as int?) ?? defaults.bootCeremonyDurationMs,
      bootSoundChimeEnabled: (map['bootSoundChimeEnabled'] as bool?) ?? defaults.bootSoundChimeEnabled,
      termoBotEnabled: (map['termoBotEnabled'] as bool?) ?? defaults.termoBotEnabled,
      mascotCharacter: _parseEnum(map['mascotCharacter'] as String?, MascotCharacter.values, defaults.mascotCharacter),
      screensaverIdleSeconds: (map['screensaverIdleSeconds'] as int?) ?? defaults.screensaverIdleSeconds,
      screensaverBackdrop: _parseEnum(map['screensaverBackdrop'] as String?, ScreensaverBackdrop.values, defaults.screensaverBackdrop),
      screensaverBlurBg: (map['screensaverBlurBg'] as bool?) ?? defaults.screensaverBlurBg,
      mascotSoundsEnabled: (map['mascotSoundsEnabled'] as bool?) ?? defaults.mascotSoundsEnabled,
      screensaverCustomBgSource: (map['screensaverCustomBgSource'] as String?) ?? defaults.screensaverCustomBgSource,
      screensaverCustomBgLabel: (map['screensaverCustomBgLabel'] as String?) ?? defaults.screensaverCustomBgLabel,
      mascotScale: (map['mascotScale'] as num?)?.toDouble() ?? defaults.mascotScale,
      aiPhoneCallEnabled: (map['aiPhoneCallEnabled'] as bool?) ?? defaults.aiPhoneCallEnabled,
      aiCallRingSeconds: (map['aiCallRingSeconds'] as int?) ?? defaults.aiCallRingSeconds,
      aiCallTriggerMode: _parseEnum(
        map['aiCallTriggerMode'] as String?,
        AiCallTriggerMode.values,
        defaults.aiCallTriggerMode,
      ),
      aiCallMissedAlertEnabled: (map['aiCallMissedAlertEnabled'] as bool?) ?? defaults.aiCallMissedAlertEnabled,
      aiCallVoiceBriefEnabled: (map['aiCallVoiceBriefEnabled'] as bool?) ?? defaults.aiCallVoiceBriefEnabled,
      aiCallLastOutcome: (map['aiCallLastOutcome'] as String?) ?? defaults.aiCallLastOutcome,
      femaleVoiceName: (map['femaleVoiceName'] as String?) ?? defaults.femaleVoiceName,
      maleVoiceName: (map['maleVoiceName'] as String?) ?? defaults.maleVoiceName,
      espDeviceId: (map['espDeviceId'] as String?) ?? defaults.espDeviceId,
      firebaseRtdbUrl: (map['firebaseRtdbUrl'] as String?) ?? defaults.firebaseRtdbUrl,
      cloudSyncEnabled: (map['cloudSyncEnabled'] as bool?) ?? defaults.cloudSyncEnabled,
    );
  }
}

enum AppThemeMode {
  liquidGlass,
  darkNight,
  lightDay,
  autoSmart,
  obsidianLavender,
  tactileDeck,
}

enum ObsidianPalette {
  pastelLavender,
  dustyLilac,
  royalViolet,
  deepObsidian,
}

enum PerformanceMode {
  ultra60fps,
  ecoBattery,
}

enum WeatherEffectPreview {
  live,
  sunny,
  partlyCloudy,
  rainy,
  snowy,
  foggy,
}

enum ReportSubTab {
  heatMap,
  usageBill,
  boilerSensors,
}

enum ScheduleSubTab {
  smartSchedule,
  dailySavings,
}

class ThemePaletteSpec {
  final bool isLight;
  final bool isTactileDeck;
  final bool isLiquidGlass;
  final double daylightMix;
  final double tactileWarmth;
  final Color scaffoldBg;
  final Color cardBg;
  final Color cardBorder;
  final Color sheetBg;
  final Color textPrimary;
  final Color textSecondary;
  final RgbAccent? themeOverrideAccent;

  const ThemePaletteSpec({
    required this.isLight,
    required this.isTactileDeck,
    required this.isLiquidGlass,
    required this.daylightMix,
    required this.tactileWarmth,
    required this.scaffoldBg,
    required this.cardBg,
    required this.cardBorder,
    required this.sheetBg,
    required this.textPrimary,
    required this.textSecondary,
    this.themeOverrideAccent,
  });
}

class VisualCustomizationState {
  final AppThemeMode theme;
  final ObsidianPalette obsidianPalette;
  final PerformanceMode performanceMode;
  final WeatherEffectPreview weatherPreview;
  final List<TabId> tabOrder;
  final List<ReportSubTab> reportSubTabOrder;
  final List<ScheduleSubTab> scheduleSubTabOrder;

  const VisualCustomizationState({
    required this.theme,
    required this.obsidianPalette,
    required this.performanceMode,
    required this.weatherPreview,
    required this.tabOrder,
    required this.reportSubTabOrder,
    required this.scheduleSubTabOrder,
  });

  static const List<TabId> defaultTabOrder = [
    TabId.termo,
    TabId.hava,
    TabId.rapor,
    TabId.prog,
  ];

  static const List<ReportSubTab> defaultReportSubOrder = [
    ReportSubTab.heatMap,
    ReportSubTab.usageBill,
    ReportSubTab.boilerSensors,
  ];

  static const List<ScheduleSubTab> defaultScheduleSubOrder = [
    ScheduleSubTab.smartSchedule,
    ScheduleSubTab.dailySavings,
  ];

  factory VisualCustomizationState.defaults() => const VisualCustomizationState(
        theme: AppThemeMode.liquidGlass,
        obsidianPalette: ObsidianPalette.pastelLavender,
        performanceMode: PerformanceMode.ultra60fps,
        weatherPreview: WeatherEffectPreview.live,
        tabOrder: defaultTabOrder,
        reportSubTabOrder: defaultReportSubOrder,
        scheduleSubTabOrder: defaultScheduleSubOrder,
      );

  List<TabMeta> get orderedTabs {
    final result = <TabMeta>[];
    for (final id in tabOrder) {
      for (final meta in ThermostatMath.tabs) {
        if (meta.id == id) result.add(meta);
      }
    }
    for (final meta in ThermostatMath.tabs) {
      if (!result.any((r) => r.id == meta.id)) result.add(meta);
    }
    return result;
  }

  ThemePaletteSpec resolvePalette([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    final autoIsLight = hour >= 7 && hour < 19;

    switch (theme) {
      case AppThemeMode.lightDay:
        return ThemePaletteSpec(
          isLight: true,
          isTactileDeck: false,
          isLiquidGlass: false,
          daylightMix: 1.0,
          tactileWarmth: 0.0,
          scaffoldBg: const Color(0xFFDCE7F5),
          cardBg: Colors.white.withValues(alpha: 0.72),
          cardBorder: const Color(0xFF0F172A).withValues(alpha: 0.12),
          sheetBg: const Color(0xFFF1F5F9),
          textPrimary: const Color(0xFF0F172A),
          textSecondary: const Color(0xFF334155),
        );
      case AppThemeMode.autoSmart:
        if (autoIsLight) {
          return ThemePaletteSpec(
            isLight: true,
            isTactileDeck: false,
            isLiquidGlass: true,
            daylightMix: 0.92,
            tactileWarmth: 0.0,
            scaffoldBg: const Color(0xFFD8E5F4),
            cardBg: Colors.white.withValues(alpha: 0.70),
            cardBorder: const Color(0xFF0F172A).withValues(alpha: 0.12),
            sheetBg: const Color(0xFFF1F5F9),
            textPrimary: const Color(0xFF0F172A),
            textSecondary: const Color(0xFF334155),
          );
        }
        return ThemePaletteSpec(
          isLight: false,
          isTactileDeck: false,
          isLiquidGlass: true,
          daylightMix: 0.0,
          tactileWarmth: 0.0,
          scaffoldBg: const Color(0xFF040406),
          cardBg: Colors.white.withValues(alpha: 0.05),
          cardBorder: Colors.white.withValues(alpha: 0.10),
          sheetBg: const Color(0xFF0D0E14),
          textPrimary: Colors.white,
          textSecondary: Colors.white.withValues(alpha: 0.62),
        );
      case AppThemeMode.darkNight:
        return ThemePaletteSpec(
          isLight: false,
          isTactileDeck: false,
          isLiquidGlass: false,
          daylightMix: 0.0,
          tactileWarmth: 0.0,
          scaffoldBg: const Color(0xFF020305),
          cardBg: const Color(0xFF0B0E17).withValues(alpha: 0.85),
          cardBorder: Colors.white.withValues(alpha: 0.08),
          sheetBg: const Color(0xFF090B11),
          textPrimary: Colors.white,
          textSecondary: Colors.white.withValues(alpha: 0.58),
        );
      case AppThemeMode.obsidianLavender:
        final RgbAccent lavAccent;
        final Color cardTint;
        switch (obsidianPalette) {
          case ObsidianPalette.pastelLavender:
            lavAccent = const RgbAccent(0.76, 0.60, 1.0);
            cardTint = const Color(0xFF1A1429).withValues(alpha: 0.76);
            break;
          case ObsidianPalette.dustyLilac:
            lavAccent = const RgbAccent(0.68, 0.54, 0.88);
            cardTint = const Color(0xFF191523).withValues(alpha: 0.78);
            break;
          case ObsidianPalette.royalViolet:
            lavAccent = const RgbAccent(0.55, 0.36, 1.0);
            cardTint = const Color(0xFF16102B).withValues(alpha: 0.80);
            break;
          case ObsidianPalette.deepObsidian:
            lavAccent = const RgbAccent(0.58, 0.56, 0.72);
            cardTint = const Color(0xFF121218).withValues(alpha: 0.85);
            break;
        }
        return ThemePaletteSpec(
          isLight: false,
          isTactileDeck: false,
          isLiquidGlass: true,
          daylightMix: 0.0,
          tactileWarmth: 0.12,
          scaffoldBg: const Color(0xFF09070F),
          cardBg: cardTint,
          cardBorder: lavAccent.toColor(0.24),
          sheetBg: const Color(0xFF110D1B),
          textPrimary: const Color(0xFFF5F0FF),
          textSecondary: const Color(0xFFC4B5FD).withValues(alpha: 0.78),
          themeOverrideAccent: lavAccent,
        );
      case AppThemeMode.tactileDeck:
        return ThemePaletteSpec(
          isLight: false,
          isTactileDeck: true,
          isLiquidGlass: false,
          daylightMix: 0.0,
          tactileWarmth: 1.0,
          scaffoldBg: const Color(0xFF0C0A09),
          cardBg: const Color(0xFF1C1917).withValues(alpha: 0.90),
          cardBorder: const Color(0xFFD97706).withValues(alpha: 0.25),
          sheetBg: const Color(0xFF161311),
          textPrimary: const Color(0xFFFAF7F2),
          textSecondary: const Color(0xFFD6CFC7),
          themeOverrideAccent: const RgbAccent(0.98, 0.62, 0.22),
        );
      case AppThemeMode.liquidGlass:
        return ThemePaletteSpec(
          isLight: false,
          isTactileDeck: false,
          isLiquidGlass: true,
          daylightMix: 0.0,
          tactileWarmth: 0.0,
          scaffoldBg: const Color(0xFF040406),
          cardBg: Colors.white.withValues(alpha: 0.05),
          cardBorder: Colors.white.withValues(alpha: 0.11),
          sheetBg: const Color(0xFF0D0E14),
          textPrimary: Colors.white,
          textSecondary: Colors.white.withValues(alpha: 0.58),
        );
    }
  }

  VisualCustomizationState copyWith({
    AppThemeMode? theme,
    ObsidianPalette? obsidianPalette,
    PerformanceMode? performanceMode,
    WeatherEffectPreview? weatherPreview,
    List<TabId>? tabOrder,
    List<ReportSubTab>? reportSubTabOrder,
    List<ScheduleSubTab>? scheduleSubTabOrder,
  }) {
    return VisualCustomizationState(
      theme: theme ?? this.theme,
      obsidianPalette: obsidianPalette ?? this.obsidianPalette,
      performanceMode: performanceMode ?? this.performanceMode,
      weatherPreview: weatherPreview ?? this.weatherPreview,
      tabOrder: tabOrder ?? this.tabOrder,
      reportSubTabOrder: reportSubTabOrder ?? this.reportSubTabOrder,
      scheduleSubTabOrder: scheduleSubTabOrder ?? this.scheduleSubTabOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'theme': theme.name,
        'obsidianPalette': obsidianPalette.name,
        'performanceMode': performanceMode.name,
        'weatherPreview': weatherPreview.name,
        'tabOrder': tabOrder.map((e) => e.name).toList(),
        'reportSubTabOrder': reportSubTabOrder.map((e) => e.name).toList(),
        'scheduleSubTabOrder': scheduleSubTabOrder.map((e) => e.name).toList(),
      };

  static List<T> _parseEnumOrder<T extends Enum>(
    dynamic raw,
    List<T> values,
    List<T> fallback,
  ) {
    if (raw is! List) return fallback;
    final parsed = <T>[];
    for (final item in raw) {
      for (final v in values) {
        if (v.name == item && !parsed.contains(v)) parsed.add(v);
      }
    }
    for (final v in fallback) {
      if (!parsed.contains(v)) parsed.add(v);
    }
    return parsed.isEmpty ? fallback : parsed;
  }

  factory VisualCustomizationState.fromJson(Map<String, dynamic> map) {
    final d = VisualCustomizationState.defaults();

    AppThemeMode parseTheme(String? n) {
      for (final v in AppThemeMode.values) {
        if (v.name == n) return v;
      }
      return d.theme;
    }

    ObsidianPalette parseObs(String? n) {
      for (final v in ObsidianPalette.values) {
        if (v.name == n) return v;
      }
      return d.obsidianPalette;
    }

    PerformanceMode parsePerf(String? n) {
      for (final v in PerformanceMode.values) {
        if (v.name == n) return v;
      }
      return d.performanceMode;
    }

    WeatherEffectPreview parseWeather(String? n) {
      for (final v in WeatherEffectPreview.values) {
        if (v.name == n) return v;
      }
      return d.weatherPreview;
    }

    return VisualCustomizationState(
      theme: parseTheme(map['theme'] as String?),
      obsidianPalette: parseObs(map['obsidianPalette'] as String?),
      performanceMode: parsePerf(map['performanceMode'] as String?),
      weatherPreview: parseWeather(map['weatherPreview'] as String?),
      tabOrder: _parseEnumOrder(map['tabOrder'], TabId.values, defaultTabOrder),
      reportSubTabOrder: _parseEnumOrder(
        map['reportSubTabOrder'],
        ReportSubTab.values,
        defaultReportSubOrder,
      ),
      scheduleSubTabOrder: _parseEnumOrder(
        map['scheduleSubTabOrder'],
        ScheduleSubTab.values,
        defaultScheduleSubOrder,
      ),
    );
  }
}


