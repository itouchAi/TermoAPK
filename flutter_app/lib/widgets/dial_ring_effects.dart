import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

class DialRingStyleInfo {
  final DialRingStyle style;
  final String titleTr;
  final String titleEn;
  final String badgeTr;
  final String badgeEn;
  final String descriptionTr;
  final String descriptionEn;
  final Color swatchColor;
  final IconData icon;

  const DialRingStyleInfo({
    required this.style,
    required this.titleTr,
    required this.titleEn,
    required this.badgeTr,
    required this.badgeEn,
    required this.descriptionTr,
    required this.descriptionEn,
    required this.swatchColor,
    required this.icon,
  });

  static const List<DialRingStyleInfo> dynamicFive = [
    DialRingStyleInfo(
      style: DialRingStyle.boilerFlame,
      titleTr: 'Gerçekçi Kombi Alevi',
      titleEn: 'Realistic Boiler Flame',
      badgeTr: 'Brülör Odası',
      badgeEn: 'Burner Core',
      descriptionTr:
          'Beklemede sönük pilot; ısı yükseldikçe mavi gaz alevi harlanıp turuncu-altın alevlere ve kıvılcımlara dönüşür.',
      descriptionEn:
          'Dim pilot on standby; ignites crisp blue gas jets that roar taller into amber-gold flames & embers as heat rises.',
      swatchColor: Color(0xFF38BDF8),
      icon: Icons.local_fire_department_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.autoTacho,
      titleTr: 'Süper Oto Kadranı (10–30)',
      titleEn: 'Motorsport Gauge (10–30)',
      badgeTr: '3D İbre & Redline',
      badgeEn: '3D Needle',
      descriptionTr:
          '10–30 rakamlı spor araç kadranı, fırçalanmış metal yüzey, 26–30° kırmızı redline bölgesi ve fiziksel 3D ibre.',
      descriptionEn:
          'Motorsport dial with 10–30 numerals, machined metallic face, 26–30° crimson redline zone, and a physical 3D needle.',
      swatchColor: Color(0xFFEF4444),
      icon: Icons.speed_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.thermoMercury,
      titleTr: 'Sıvı Termal Hazne',
      titleEn: 'Liquid Thermal Chamber',
      badgeTr: 'Dinamik Sıvı',
      badgeEn: 'Fluid Level',
      descriptionTr:
          'Cam küre içinde dereceyle yükselip alçalan dalgalı termal sıvı seviyesi, menisküs parıltısı ve yükselen kabarcıklar.',
      descriptionEn:
          'Sloshing thermal liquid inside the glass sphere that rises with temperature, complete with glowing meniscus & bubbles.',
      swatchColor: Color(0xFFFF7A24),
      icon: Icons.water_drop_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.chronoRadar,
      titleTr: 'Tourbillon & Termal Radar',
      titleEn: 'Tourbillon & Thermal Radar',
      badgeTr: 'Mekanik HUD',
      badgeEn: 'Mech HUD',
      descriptionTr:
          'Kadran içinde ters yönde dönen iskelet dişli çarklar, pusula ölçeği ve dönen termal radar tarama ışını.',
      descriptionEn:
          'Counter-rotating skeletonized tourbillon gears inside the face with compass ticks and a sweeping thermal radar beam.',
      swatchColor: Color(0xFFC084FC),
      icon: Icons.radar_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.magneticFlux,
      titleTr: 'Manyetik Akı Reaktörü',
      titleEn: 'Magnetic Flux Reactor',
      badgeTr: 'Gelişmiş Çekirdek',
      badgeEn: 'Reactor Core',
      descriptionTr:
          'İç reaktör çekirdeği, camdan geçen manyetik alan halkaları ve hedef ibreye kilitlenen akışkan enerji parçacıkları.',
      descriptionEn:
          'Suspended magnetic reactor core, orbital field lines piercing the bezel, and luminous flux particles locking onto target.',
      swatchColor: Color(0xFF38D994),
      icon: Icons.track_changes_rounded,
    ),
  ];

  static DialRingStyleInfo? findDynamic(DialRingStyle style) {
    for (final item in dynamicFive) {
      if (item.style == style) return item;
    }
    return null;
  }

  /// Dynamic heat accent color computed for live thermal styles (e.g. blue pilot
  /// -> cyan gas -> roaring amber-orange for boilerFlame).
  static Color resolveDialAccent({
    required DialRingStyle style,
    required Color baseAccent,
    required double targetTemp,
    required double flameIntensity,
  }) {
    if (style == DialRingStyle.boilerFlame) {
      if (flameIntensity <= 0.05) {
        return const Color(0xFF38BDF8);
      }
      final tempNorm = ((targetTemp - 18.0) / 10.0).clamp(0.0, 1.0);
      final heat = (flameIntensity * 0.65 + tempNorm * 0.35).clamp(0.0, 1.0);
      if (heat < 0.45) {
        return Color.lerp(
          const Color(0xFF38BDF8),
          const Color(0xFF60A5FA),
          heat / 0.45,
        )!;
      }
      return Color.lerp(
        const Color(0xFF38BDF8),
        const Color(0xFFFF7A24),
        ((heat - 0.45) / 0.55).clamp(0.0, 1.0),
      )!;
    }
    if (style == DialRingStyle.autoTacho && targetTemp >= 26.0) {
      return const Color(0xFFEF4444);
    }
    if (style == DialRingStyle.thermoMercury) {
      final norm = ((targetTemp - 10.0) / 20.0).clamp(0.0, 1.0);
      if (norm < 0.45) {
        return Color.lerp(
          const Color(0xFF38BDF8),
          const Color(0xFF38D994),
          norm / 0.45,
        )!;
      }
      return Color.lerp(
        const Color(0xFF38D994),
        const Color(0xFFFF5722),
        (norm - 0.45) / 0.55,
      )!;
    }
    return baseAccent;
  }
}

/// Renders the outer animated bezel, perimeter scale, numerals (for AutoTacho),
/// and orbiting particle/radar effects around the dial face.
class DialRingEffectLayer extends StatelessWidget {
  final DialRingStyle style;
  final Animation<double> animation;
  final double sizePx;
  final double targetTemp;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;

  const DialRingEffectLayer({
    super.key,
    required this.style,
    required this.animation,
    required this.sizePx,
    required this.targetTemp,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    this.flameIntensity = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    if (style == DialRingStyle.classic) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return CustomPaint(
              size: Size(sizePx, sizePx),
              painter: DialOuterEffectsPainter(
                style: style,
                phase: animation.value,
                targetTemp: targetTemp,
                activeAngleDeg: activeAngleDeg,
                accentColor: accentColor,
                isLight: isLight,
                flameIntensity: flameIntensity,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Renders the animated interior physics/mechanics INSIDE the circular dial face
/// (flames, racing needle & gauge face, sloshing mercury, tourbillon radar, reactor core).
class DialInteriorEffectLayer extends StatelessWidget {
  final DialRingStyle style;
  final Animation<double> animation;
  final double diameterPx;
  final double targetTemp;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;

  const DialInteriorEffectLayer({
    super.key,
    required this.style,
    required this.animation,
    required this.diameterPx,
    required this.targetTemp,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    this.flameIntensity = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    if (style == DialRingStyle.classic) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            return CustomPaint(
              size: Size(diameterPx, diameterPx),
              painter: DialInteriorEffectsPainter(
                style: style,
                phase: animation.value,
                targetTemp: targetTemp,
                activeAngleDeg: activeAngleDeg,
                accentColor: accentColor,
                isLight: isLight,
                flameIntensity: flameIntensity,
              ),
            );
          },
        ),
      ),
    );
  }
}

class DialOuterEffectsPainter extends CustomPainter {
  final DialRingStyle style;
  final double phase;
  final double targetTemp;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;

  const DialOuterEffectsPainter({
    required this.style,
    required this.phase,
    required this.targetTemp,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    required this.flameIntensity,
  });

  static double _degToRad(double deg) => (deg - 90.0) * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == DialRingStyle.classic || size.isEmpty) return;
    final d = math.min(size.width, size.height);
    final center = size.center(Offset.zero);
    final scale = (d / 232.0).clamp(0.28, 1.35);
    final outerTickR = d * 0.455;
    final faceR = d * 0.38;
    final trackR = (faceR + outerTickR) * 0.50;
    final startRad = _degToRad(ThermostatMath.dialStartDeg);
    final activeRad = _degToRad(activeAngleDeg);
    final activeSweep = math.max(0.05, activeRad - startRad);
    final twoPi = math.pi * 2.0;

    switch (style) {
      case DialRingStyle.classic:
        break;
      case DialRingStyle.boilerFlame:
        _paintBoilerOuter(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
          twoPi,
        );
        break;
      case DialRingStyle.autoTacho:
        _paintAutoTachoOuter(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
        );
        break;
      case DialRingStyle.thermoMercury:
        _paintThermoMercuryOuter(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
          twoPi,
        );
        break;
      case DialRingStyle.chronoRadar:
        _paintChronoRadarOuter(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
          twoPi,
        );
        break;
      case DialRingStyle.magneticFlux:
        _paintMagneticFluxOuter(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
          twoPi,
        );
        break;
    }
  }

  void _paintBoilerOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
    double twoPi,
  ) {
    final effectiveHeat = flameIntensity <= 0.05
        ? 0.08
        : (flameIntensity * 0.72 +
                ((targetTemp - 18.0) / 12.0).clamp(0.0, 1.0) * 0.28)
            .clamp(0.18, 1.0);
    final thermalColor = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.boilerFlame,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );

    // Warm/cool ambient bezel halo modulated by burner flicker
    final flicker = 0.88 + 0.12 * math.sin(phase * twoPi * 3.0);
    canvas.drawCircle(
      center,
      faceR + 3.0 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (4.0 + 4.0 * effectiveHeat) * scale
        ..color = thermalColor.withValues(
            alpha: (isLight ? 0.20 : 0.34) * effectiveHeat * flicker)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.5 * scale),
    );

    // Precision boiler perimeter ticks glowing stronger with heat
    const totalTicks = 45;
    final unlit = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.14);

    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = _degToRad(tickDeg);
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 4 == 0;
      final len = (isMajor ? 10.0 : 7.0) * scale;

      Color tickColor = unlit;
      if (isLit) {
        final tFrac = i / (totalTicks - 1);
        final ember = flameIntensity <= 0.05
            ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
            : Color.lerp(
                const Color(0xFF38BDF8),
                const Color(0xFFFF6B1A),
                (tFrac * effectiveHeat * 1.15).clamp(0.0, 1.0),
              )!;
        tickColor = ember;
      }
      canvas.drawLine(
        Offset(center.dx + math.cos(rad) * (outerTickR - len),
            center.dy + math.sin(rad) * (outerTickR - len)),
        Offset(center.dx + math.cos(rad) * outerTickR,
            center.dy + math.sin(rad) * outerTickR),
        Paint()
          ..color = tickColor
          ..strokeWidth = (isMajor ? 2.6 : 1.8) * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    // Glowing thermal valve jewel on the outer arc
    final tip = Offset(
      center.dx + math.cos(activeRad) * (outerTickR + 3.0 * scale),
      center.dy + math.sin(activeRad) * (outerTickR + 3.0 * scale),
    );
    canvas.drawCircle(
      tip,
      5.0 * scale,
      Paint()
        ..color = thermalColor.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 * scale),
    );
    canvas.drawCircle(tip, 2.3 * scale, Paint()..color = Colors.white);
  }

  void _paintAutoTachoOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
  ) {
    // Machined metallic outer bezel rim
    canvas.drawCircle(
      center,
      outerTickR + 3.8 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..color = isLight
            ? const Color(0xFF334155).withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.22),
    );

    // Motorsport ticks with permanent redline zone (26..30°C => norm >= 0.8)
    const totalTicks = 41;
    final unlit = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.24);
    const redline = Color(0xFFEF4444);

    for (int i = 0; i < totalTicks; i++) {
      final frac = i / (totalTicks - 1);
      final tickDeg = -135.0 + frac * 270.0;
      final rad = _degToRad(tickDeg);
      final isRedline = frac >= 0.80; // 26°C - 30°C
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 10 == 0;
      final isMid = i % 5 == 0;
      final len = (isMajor ? 12.0 : (isMid ? 8.5 : 5.5)) * scale;

      Color color;
      if (isRedline) {
        color = redline.withValues(alpha: isLit ? 1.0 : 0.55);
      } else if (isLit) {
        color = Color.lerp(
          isLight ? const Color(0xFF0EA5E9) : Colors.white,
          const Color(0xFFFF7A24),
          (frac / 0.80).clamp(0.0, 1.0),
        )!;
      } else {
        color = unlit;
      }

      canvas.drawLine(
        Offset(center.dx + math.cos(rad) * (outerTickR - len),
            center.dy + math.sin(rad) * (outerTickR - len)),
        Offset(center.dx + math.cos(rad) * outerTickR,
            center.dy + math.sin(rad) * outerTickR),
        Paint()
          ..color = color
          ..strokeWidth = (isMajor ? 2.8 : (isMid ? 2.0 : 1.3)) * scale
          ..strokeCap = StrokeCap.butt,
      );
    }

    // Active motorsport sweep arc inside the bezel
    final arcRect = Rect.fromCircle(center: center, radius: faceR + 3.2 * scale);
    canvas.drawArc(
      arcRect,
      startRad,
      activeSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * scale
        ..strokeCap = StrokeCap.butt
        ..shader = const SweepGradient(
          colors: [
            Color(0xFF38BDF8),
            Color(0xFFF59E0B),
            Color(0xFFEF4444),
            Color(0xFFEF4444),
          ],
          stops: [0.0, 0.38, 0.60, 0.76],
          transform: GradientRotation(math.pi * 0.75),
        ).createShader(arcRect),
    );
  }

  void _paintThermoMercuryOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
    double twoPi,
  ) {
    final fluidColor = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.thermoMercury,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );

    // Glass etched perimeter graduations
    const totalTicks = 45;
    final unlit = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.15);
    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = _degToRad(tickDeg);
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 4 == 0;
      final len = (isMajor ? 10.0 : 6.5) * scale;
      canvas.drawLine(
        Offset(center.dx + math.cos(rad) * (outerTickR - len),
            center.dy + math.sin(rad) * (outerTickR - len)),
        Offset(center.dx + math.cos(rad) * outerTickR,
            center.dy + math.sin(rad) * outerTickR),
        Paint()
          ..color = isLit ? fluidColor.withValues(alpha: 0.92) : unlit
          ..strokeWidth = (isMajor ? 2.4 : 1.6) * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    // Luminous fluid gauge collar around glass rim
    final collarRect = Rect.fromCircle(center: center, radius: trackR);
    canvas.drawArc(
      collarRect,
      startRad,
      activeSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2 * scale
        ..strokeCap = StrokeCap.round
        ..color = fluidColor.withValues(alpha: 0.65),
    );

    // Floating meniscus target marker
    final tip = Offset(
      center.dx + math.cos(activeRad) * trackR,
      center.dy + math.sin(activeRad) * trackR,
    );
    canvas.drawCircle(
      tip,
      5.5 * scale,
      Paint()
        ..color = fluidColor.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 * scale),
    );
    canvas.drawCircle(tip, 2.5 * scale, Paint()..color = Colors.white);
  }

  void _paintChronoRadarOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
    double twoPi,
  ) {
    final sweepAngle = startRad + phase * twoPi;
    const totalTicks = 45;
    final unlit = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.16);

    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = _degToRad(tickDeg);
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 4 == 0;
      final len = (isMajor ? 10.0 : 7.0) * scale;

      // Subtle sonar flash when radar beam passes each tick
      final beamDist = ((rad - sweepAngle) % twoPi + twoPi) % twoPi;
      final beamBoost = beamDist < 0.55 ? (1.0 - beamDist / 0.55) : 0.0;

      Color c = isLit ? accentColor.withValues(alpha: 0.90) : unlit;
      if (beamBoost > 0.05) {
        c = Color.lerp(c, Colors.white, beamBoost * 0.65)!;
      }

      canvas.drawLine(
        Offset(center.dx + math.cos(rad) * (outerTickR - len),
            center.dy + math.sin(rad) * (outerTickR - len)),
        Offset(center.dx + math.cos(rad) * outerTickR,
            center.dy + math.sin(rad) * outerTickR),
        Paint()
          ..color = c
          ..strokeWidth = (isMajor ? 2.5 : 1.7) * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    // Outer HUD compass ring + target lock triangle
    canvas.drawCircle(
      center,
      outerTickR + 4.0 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale
        ..color = accentColor.withValues(alpha: 0.28),
    );
    final lockTip = Offset(
      center.dx + math.cos(activeRad) * (outerTickR + 3.5 * scale),
      center.dy + math.sin(activeRad) * (outerTickR + 3.5 * scale),
    );
    canvas.drawCircle(lockTip, 2.8 * scale, Paint()..color = accentColor);
  }

  void _paintMagneticFluxOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
    double twoPi,
  ) {
    final cyanCore = Color.lerp(accentColor, const Color(0xFF38BDF8), 0.40)!;
    final brightCore = Color.lerp(accentColor, Colors.white, 0.65)!;

    // Perimeter ticks illuminated cleanly
    const totalTicks = 45;
    final unlit = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.15);
    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = _degToRad(tickDeg);
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 4 == 0;
      final len = (isMajor ? 10.0 : 7.0) * scale;
      canvas.drawLine(
        Offset(center.dx + math.cos(rad) * (outerTickR - len),
            center.dy + math.sin(rad) * (outerTickR - len)),
        Offset(center.dx + math.cos(rad) * outerTickR,
            center.dy + math.sin(rad) * outerTickR),
        Paint()
          ..color = isLit ? accentColor.withValues(alpha: 0.92) : unlit
          ..strokeWidth = (isMajor ? 2.5 : 1.7) * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    // 3 precessing elliptical magnetic field orbits
    for (int i = 0; i < 3; i++) {
      final tilt = i * (math.pi / 3.0) +
          0.22 * math.sin(phase * twoPi + i * 2.094);
      final rx = outerTickR * (1.04 + 0.025 * math.sin(phase * twoPi + i));
      final ry = outerTickR * (0.90 + 0.025 * math.cos(phase * twoPi + i));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (i == 0 ? 1.6 : 1.1) * scale
          ..color = (i == 1 ? cyanCore : accentColor)
              .withValues(alpha: isLight ? 0.36 : 0.44),
      );
      canvas.restore();
    }

    // 10 luminous flux particles gliding along the heated arc onto the pole
    const particleCount = 10;
    for (int p = 0; p < particleCount; p++) {
      final t = (phase + p / particleCount) % 1.0;
      final easedT = math.pow(t, 1.15).toDouble();
      final theta = startRad + activeSweep * easedT;
      final radialWave = math.sin(t * twoPi * 2.0 + p * 1.1) * 4.5 * scale;
      final pr = trackR + radialWave;
      final pos = Offset(
        center.dx + math.cos(theta) * pr,
        center.dy + math.sin(theta) * pr,
      );
      final env = math.sin(t * math.pi).clamp(0.0, 1.0);
      final r = (1.6 + 1.9 * env) * scale;

      canvas.drawCircle(
        pos,
        r * 2.2,
        Paint()
          ..color = accentColor.withValues(alpha: 0.48 * env)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * scale),
      );
      canvas.drawCircle(
        pos,
        r,
        Paint()..color = brightCore.withValues(alpha: 0.95 * env),
      );
    }

    final pole = Offset(
      center.dx + math.cos(activeRad) * trackR,
      center.dy + math.sin(activeRad) * trackR,
    );
    canvas.drawCircle(
      pole,
      6.5 * scale,
      Paint()
        ..color = accentColor.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale),
    );
    canvas.drawCircle(pole, 2.7 * scale, Paint()..color = brightCore);
  }

  @override
  bool shouldRepaint(covariant DialOuterEffectsPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.phase != phase ||
      oldDelegate.targetTemp != targetTemp ||
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isLight != isLight ||
      oldDelegate.flameIntensity != flameIntensity;
}

class DialInteriorEffectsPainter extends CustomPainter {
  final DialRingStyle style;
  final double phase;
  final double targetTemp;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;

  const DialInteriorEffectsPainter({
    required this.style,
    required this.phase,
    required this.targetTemp,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    required this.flameIntensity,
  });

  static double _degToRad(double deg) => (deg - 90.0) * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == DialRingStyle.classic || size.isEmpty) return;
    final d = math.min(size.width, size.height);
    final center = size.center(Offset.zero);
    final r = d * 0.5;
    final scale = (d / 176.0).clamp(0.28, 1.4);
    final twoPi = math.pi * 2.0;
    final startRad = _degToRad(ThermostatMath.dialStartDeg);
    final activeRad = _degToRad(activeAngleDeg);

    switch (style) {
      case DialRingStyle.classic:
        break;
      case DialRingStyle.boilerFlame:
        _paintBoilerInterior(canvas, size, center, r, scale, twoPi);
        break;
      case DialRingStyle.autoTacho:
        _paintAutoTachoInterior(
            canvas, size, center, r, scale, startRad, activeRad);
        break;
      case DialRingStyle.thermoMercury:
        _paintThermoMercuryInterior(canvas, size, center, r, scale, twoPi);
        break;
      case DialRingStyle.chronoRadar:
        _paintChronoRadarInterior(
            canvas, center, r, scale, startRad, activeRad, twoPi);
        break;
      case DialRingStyle.magneticFlux:
        _paintMagneticFluxInterior(canvas, center, r, scale, activeRad, twoPi);
        break;
    }

    // Subtle crisp glass rim specular at top
    canvas.drawArc(
      Rect.fromLTWH(1.0, 1.0, size.width - 2.0, size.height - 2.0),
      -math.pi * 0.86,
      math.pi * 0.72,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 * scale
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: isLight ? 0.82 : 0.24),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  void _paintBoilerInterior(
    Canvas canvas,
    Size size,
    Offset center,
    double r,
    double scale,
    double twoPi,
  ) {
    // Deep recessed combustion chamber backdrop (dark even in light UI so real flames glow vividly)
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.0, 0.35),
          radius: 0.95,
          colors: const [
            Color(0xFF131822),
            Color(0xFF090B10),
            Color(0xFF040507),
          ],
        ).createShader(Offset.zero & size),
    );

    final isHeating = flameIntensity > 0.05;
    final tempHeat = ((targetTemp - 18.0) / 11.0).clamp(0.0, 1.0);
    final heat = isHeating
        ? (flameIntensity * 0.68 + tempHeat * 0.32).clamp(0.18, 1.0)
        : 0.0;

    final grateY = center.dy + r * 0.76;

    // 1. Resting Pilot Glow (when standby / off)
    if (!isHeating) {
      final pilotPulse = 0.85 + 0.15 * math.sin(phase * twoPi * 3.0);
      final pilotBase = Offset(center.dx, grateY - 4.0 * scale);
      canvas.drawCircle(
        pilotBase,
        r * 0.28 * pilotPulse,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xFF38BDF8).withValues(alpha: 0.30),
              const Color(0xFF1D4ED8).withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: pilotBase, radius: r * 0.30)),
      );
      _drawFlameTongue(
        canvas,
        baseX: center.dx,
        baseY: grateY,
        width: 14.0 * scale,
        height: 22.0 * scale * pilotPulse,
        sway: 2.2 * scale * math.sin(phase * twoPi * 3.0),
        colorBottom: const Color(0xFF60A5FA),
        colorTop: const Color(0xFF38BDF8).withValues(alpha: 0.85),
        coreColor: Colors.white.withValues(alpha: 0.85),
        blurSigma: 2.5 * scale,
      );
    } else {
      // 2. Active Gas Burner: Thermal chamber bloom
      final bloomCenter = Offset(center.dx, center.dy + r * 0.45);
      final bloomColor = Color.lerp(
        const Color(0xFF0284C7),
        const Color(0xFFFF5E1A),
        ((heat - 0.35) / 0.65).clamp(0.0, 1.0),
      )!;
      canvas.drawCircle(
        bloomCenter,
        r * (0.68 + 0.38 * heat),
        Paint()
          ..shader = RadialGradient(
            colors: [
              bloomColor.withValues(alpha: 0.28 + 0.28 * heat),
              const Color(0xFF1D4ED8).withValues(alpha: 0.18),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(
            center: bloomCenter,
            radius: r * (0.68 + 0.38 * heat),
          )),
      );

      // 3. Upper Roaring Amber-Orange-White Flame Licks (emerge strongly as heat > 0.38)
      final orangeFactor = ((heat - 0.30) / 0.70).clamp(0.0, 1.0);
      if (orangeFactor > 0.02) {
        const upperJets = 7;
        for (int i = 0; i < upperJets; i++) {
          final normX = (i - (upperJets - 1) / 2.0) / ((upperJets - 1) / 2.0);
          final arch = 1.0 - normX * normX * 0.38;
          final x = center.dx + normX * r * 0.62;
          final y = grateY - (1.0 - arch) * 14.0 * scale;
          final osc = math.sin(phase * twoPi * 3.0 + i * 1.15);
          final osc2 = math.cos(phase * twoPi * 5.0 - i * 0.85);
          final h = r * (0.36 + 0.74 * orangeFactor) * arch * (0.88 + 0.16 * osc);
          final w = (18.0 + 14.0 * orangeFactor) * scale * arch;
          _drawFlameTongue(
            canvas,
            baseX: x,
            baseY: y,
            width: w,
            height: h,
            sway: (4.5 + 3.5 * orangeFactor) * scale * osc2,
            colorBottom: const Color(0xFFEA580C).withValues(alpha: 0.75 * orangeFactor),
            colorTop: Color.lerp(
              const Color(0xFFF59E0B),
              const Color(0xFFFEF08A),
              orangeFactor * 0.65,
            )!.withValues(alpha: 0.85 * orangeFactor),
            coreColor: const Color(0xFFFFFBEB).withValues(alpha: 0.65 * orangeFactor),
            blurSigma: 4.5 * scale,
          );
        }
      }

      // 4. Crisp High-Velocity Blue & Cyan Bunsen Gas Jets at the burner nozzles
      const blueJets = 9;
      for (int i = 0; i < blueJets; i++) {
        final normX = (i - (blueJets - 1) / 2.0) / ((blueJets - 1) / 2.0);
        final arch = 1.0 - normX * normX * 0.36;
        final x = center.dx + normX * r * 0.68;
        final y = grateY - (1.0 - arch) * 12.0 * scale;
        final osc = math.sin(phase * twoPi * 4.0 + i * 0.95);
        final osc2 = math.cos(phase * twoPi * 6.0 + i * 1.4);
        final h = r * (0.24 + 0.36 * heat) * arch * (0.90 + 0.12 * osc);
        final w = (11.0 + 7.5 * heat) * scale;
        _drawFlameTongue(
          canvas,
          baseX: x,
          baseY: y,
          width: w,
          height: h,
          sway: 2.8 * scale * osc2,
          colorBottom: const Color(0xFF1D4ED8),
          colorTop: const Color(0xFF38BDF8),
          coreColor: const Color(0xFFE0F2FE),
          blurSigma: 2.2 * scale,
        );
      }

      // 5. Rising incandescent micro-embers inside glass chamber when roaring
      if (orangeFactor > 0.15) {
        const sparkCount = 12;
        for (int s = 0; s < sparkCount; s++) {
          final life = (phase * 2.0 + s / sparkCount) % 1.0;
          final xSpread = math.sin(s * 2.3 + life * twoPi) * r * 0.48;
          final sx = center.dx + xSpread;
          final sy = grateY - life * r * (0.75 + 0.55 * orangeFactor);
          final alpha = (1.0 - life) * math.sin(life * math.pi) * orangeFactor;
          if (alpha > 0.02) {
            canvas.drawCircle(
              Offset(sx, sy),
              (1.3 + 1.1 * (1.0 - life)) * scale,
              Paint()
                ..color = Color.lerp(
                  const Color(0xFFFFD166),
                  const Color(0xFFFF5722),
                  life,
                )!
                    .withValues(alpha: alpha.clamp(0.0, 0.95)),
            );
          }
        }
      }
    }

    // Curved cast-iron multi-nozzle burner grate along the chamber floor
    final gratePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * scale
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF334155).withValues(alpha: 0.85);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + r * 0.20),
        width: r * 1.56,
        height: r * 1.18,
      ),
      0.34 * math.pi,
      0.32 * math.pi,
      false,
      gratePaint,
    );

    // Soft smoky center legibility shield so digits never wash out
    canvas.drawCircle(
      center,
      r * 0.62,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF07090E).withValues(alpha: 0.62),
            const Color(0xFF07090E).withValues(alpha: 0.25),
            Colors.transparent,
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.62)),
    );
  }

  void _drawFlameTongue(
    Canvas canvas, {
    required double baseX,
    required double baseY,
    required double width,
    required double height,
    required double sway,
    required Color colorBottom,
    required Color colorTop,
    required Color coreColor,
    required double blurSigma,
  }) {
    final halfW = width * 0.5;
    final tipX = baseX + sway;
    final tipY = baseY - height;
    final path = Path()
      ..moveTo(baseX - halfW, baseY)
      ..cubicTo(
        baseX - halfW * 1.05,
        baseY - height * 0.42,
        tipX - halfW * 0.25,
        baseY - height * 0.72,
        tipX,
        tipY,
      )
      ..cubicTo(
        tipX + halfW * 0.25,
        baseY - height * 0.72,
        baseX + halfW * 1.05,
        baseY - height * 0.42,
        baseX + halfW,
        baseY,
      )
      ..close();

    final bounds = Rect.fromLTRB(
      baseX - width,
      tipY - 4,
      baseX + width,
      baseY + 2,
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [colorBottom, colorTop],
        ).createShader(bounds)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma),
    );

    // Bright inner plasma core
    final innerPath = Path()
      ..moveTo(baseX - halfW * 0.42, baseY)
      ..quadraticBezierTo(
        baseX + sway * 0.45,
        baseY - height * 0.55,
        baseX + sway * 0.65,
        baseY - height * 0.62,
      )
      ..quadraticBezierTo(
        baseX + halfW * 0.42 + sway * 0.3,
        baseY - height * 0.30,
        baseX + halfW * 0.42,
        baseY,
      )
      ..close();
    canvas.drawPath(innerPath, Paint()..color = coreColor);
  }

  void _paintAutoTachoInterior(
    Canvas canvas,
    Size size,
    Offset center,
    double r,
    double scale,
    double startRad,
    double activeRad,
  ) {
    // Machined brushed-metal concentric dial surface
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: isLight
              ? const [Color(0xFFF8FAFC), Color(0xFFE2E8F0), Color(0xFFCBD5E1)]
              : const [Color(0xFF1F242E), Color(0xFF13161D), Color(0xFF0A0C10)],
        ).createShader(Offset.zero & size),
    );

    // Subtle concentric lathe grooves
    for (final frac in [0.92, 0.84, 0.66, 0.56]) {
      canvas.drawCircle(
        center,
        r * frac,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8 * scale
          ..color = (isLight ? Colors.black : Colors.white)
              .withValues(alpha: frac == 0.84 ? 0.14 : 0.05),
      );
    }

    // Active motorsport glowing track inside dial rim
    final activeSweep = math.max(0.05, activeRad - startRad);
    final gaugeRect = Rect.fromCircle(center: center, radius: r * 0.90);
    canvas.drawArc(
      gaugeRect,
      startRad,
      activeSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.5 * scale
        ..strokeCap = StrokeCap.butt
        ..color = (targetTemp >= 26.0
                ? const Color(0xFFEF4444)
                : const Color(0xFFFF7A24))
            .withValues(alpha: 0.25),
    );

    // Crisp numeric scale markers: 10, 15, 20, 25, 30 (shown on full dials >= 115px)
    if (r * 2 >= 115.0) {
      const labels = [10, 15, 20, 25, 30];
      for (final val in labels) {
        final norm = (val - 10.0) / 20.0;
        final deg = -135.0 + norm * 270.0;
        final rad = _degToRad(deg);
        final numR = r * 0.75;
        final isRed = val >= 25;
        final isNearActive = (val - targetTemp).abs() <= 2.5;
        final tp = TextPainter(
          text: TextSpan(
            text: '$val',
            style: TextStyle(
              fontSize: 10.5 * scale,
              fontWeight: FontWeight.w800,
              color: val == 30
                  ? const Color(0xFFEF4444)
                  : isNearActive
                      ? (isLight ? const Color(0xFF0F172A) : Colors.white)
                      : (isRed
                          ? const Color(0xFFEF4444).withValues(alpha: 0.80)
                          : (isLight
                              ? const Color(0xFF334155)
                              : Colors.white.withValues(alpha: 0.65))),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos = Offset(
          center.dx + math.cos(rad) * numR - tp.width / 2,
          center.dy + math.sin(rad) * numR - tp.height / 2,
        );
        tp.paint(canvas, pos);
      }
    }

    // Physical 3D Tapered Tachometer Needle (drawn BEFORE center hub cap so text sits crisp inside hub!)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(activeRad + math.pi / 2.0); // 0° points straight up at activeRad

    final needleTipY = -r * 0.93;
    final needleBaseY = -r * 0.38;
    final baseHalfW = 3.8 * scale;
    final tipHalfW = 1.0 * scale;

    final needlePath = Path()
      ..moveTo(-baseHalfW, needleBaseY)
      ..lineTo(-tipHalfW, needleTipY)
      ..lineTo(tipHalfW, needleTipY)
      ..lineTo(baseHalfW, needleBaseY)
      ..close();

    // Soft needle drop shadow
    canvas.drawPath(
      needlePath.shift(Offset(1.8 * scale, 2.2 * scale)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale),
    );

    // Vivid racing red/orange 3D needle body + luminous spine
    final needleColor = targetTemp >= 26.0
        ? const Color(0xFFEF4444)
        : const Color(0xFFFF4D2E);
    canvas.drawPath(
      needlePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            needleColor,
            Color.lerp(needleColor, Colors.white, 0.25)!,
          ],
        ).createShader(Rect.fromLTRB(-5, needleTipY, 5, needleBaseY)),
    );
    canvas.drawLine(
      Offset(0, needleBaseY),
      Offset(0, needleTipY + 1.5 * scale),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.1 * scale
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // Machined center gauge window cap so digits pop like an OLED cluster inside the tachometer
    canvas.drawCircle(
      center,
      r * 0.56,
      Paint()
        ..color = isLight
            ? Colors.white.withValues(alpha: 0.90)
            : const Color(0xFF0C0E14).withValues(alpha: 0.90),
    );
    canvas.drawCircle(
      center,
      r * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..color = isLight
            ? const Color(0xFF94A3B8).withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.16),
    );
  }

  void _paintThermoMercuryInterior(
    Canvas canvas,
    Size size,
    Offset center,
    double r,
    double scale,
    double twoPi,
  ) {
    final norm = ((targetTemp - ThermostatMath.minTemp) /
            (ThermostatMath.maxTemp - ThermostatMath.minTemp))
        .clamp(0.0, 1.0);
    final fluidColor = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.thermoMercury,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );
    final deepFluid = Color.lerp(fluidColor, Colors.black, 0.35)!;
    final brightMeniscus = Color.lerp(fluidColor, Colors.white, 0.55)!;

    // Translucent dark/light glass interior
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 1.0,
          colors: isLight
              ? const [Color(0xFFF8FAFC), Color(0xFFE2E8F0)]
              : const [Color(0xFF171B24), Color(0xFF090B10)],
        ).createShader(Offset.zero & size),
    );

    final fillFrac = 0.16 + norm * 0.74;
    final surfaceY = (center.dy + r) - (2.0 * r * fillFrac);
    final amp = (3.5 + 3.0 * flameIntensity) * scale;

    // Back wave
    final backWave = Path()..moveTo(center.dx - r - 2, center.dy + r + 2);
    for (double x = center.dx - r - 2; x <= center.dx + r + 2; x += 4.0) {
      final nx = (x - (center.dx - r)) / (2.0 * r);
      final wy = surfaceY +
          math.cos(nx * twoPi * 1.5 - phase * twoPi) * amp * 0.85;
      backWave.lineTo(x, wy);
    }
    backWave
      ..lineTo(center.dx + r + 2, center.dy + r + 2)
      ..close();
    canvas.drawPath(
      backWave,
      Paint()..color = deepFluid.withValues(alpha: 0.58),
    );

    // Front wave
    final frontWave = Path()..moveTo(center.dx - r - 2, center.dy + r + 2);
    final meniscus = Path();
    bool first = true;
    for (double x = center.dx - r - 2; x <= center.dx + r + 2; x += 4.0) {
      final nx = (x - (center.dx - r)) / (2.0 * r);
      final wy = surfaceY + math.sin(nx * twoPi * 1.5 + phase * twoPi) * amp;
      frontWave.lineTo(x, wy);
      if (first) {
        meniscus.moveTo(x, wy);
        first = false;
      } else {
        meniscus.lineTo(x, wy);
      }
    }
    frontWave
      ..lineTo(center.dx + r + 2, center.dy + r + 2)
      ..close();

    canvas.drawPath(
      frontWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fluidColor.withValues(alpha: 0.85),
            deepFluid.withValues(alpha: 0.92),
          ],
        ).createShader(Rect.fromLTRB(
            center.dx - r, surfaceY - amp, center.dx + r, center.dy + r)),
    );

    // Luminous meniscus surface highlight
    canvas.drawPath(
      meniscus,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * scale
        ..color = brightMeniscus.withValues(alpha: 0.90),
    );

    // Rising bubbles inside fluid when heating
    if (flameIntensity > 0.05) {
      const bubbleCount = 8;
      for (int b = 0; b < bubbleCount; b++) {
        final t = (phase * 1.0 + b / bubbleCount) % 1.0;
        final bx = center.dx + math.sin(b * 2.1 + t * twoPi) * r * 0.55;
        final by = (center.dy + r * 0.88) -
            t * ((center.dy + r * 0.88) - surfaceY - 4.0 * scale);
        if (by > surfaceY + 3.0 * scale) {
          canvas.drawCircle(
            Offset(bx, by),
            (1.5 + (b % 3) * 0.65) * scale,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.0 * scale
              ..color = Colors.white.withValues(alpha: 0.55 * (1.0 - t)),
          );
        }
      }
    }

    // Center legibility shield
    canvas.drawCircle(
      center,
      r * 0.56,
      Paint()
        ..shader = RadialGradient(
          colors: [
            (isLight ? Colors.white : const Color(0xFF0A0D14))
                .withValues(alpha: 0.66),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: r * 0.56)),
    );
  }

  void _paintChronoRadarInterior(
    Canvas canvas,
    Offset center,
    double r,
    double scale,
    double startRad,
    double activeRad,
    double twoPi,
  ) {
    final hudLine = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.16)
        : Colors.white.withValues(alpha: 0.14);

    // Rangefinder concentric circles
    for (final frac in [0.46, 0.70, 0.89]) {
      canvas.drawCircle(
        center,
        r * frac,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9 * scale
          ..color = hudLine,
      );
    }

    // 12-tooth outer rotating skeleton tourbillon gear
    const teeth = 12;
    final step = twoPi / teeth;
    final rot = phase * step;
    for (int i = 0; i < teeth; i++) {
      final a = rot + i * step;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.82),
        a,
        step * 0.45,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.2 * scale
          ..color = accentColor.withValues(alpha: isLight ? 0.35 : 0.42),
      );
    }

    // 18-vane inner counter-rotating escapement ring
    const innerCount = 18;
    final iStep = twoPi / innerCount;
    final iRot = -phase * iStep * 2.0;
    for (int i = 0; i < innerCount; i++) {
      final a = iRot + i * iStep;
      canvas.drawLine(
        Offset(center.dx + math.cos(a) * r * 0.60,
            center.dy + math.sin(a) * r * 0.60),
        Offset(center.dx + math.cos(a + 0.06) * r * 0.69,
            center.dy + math.sin(a + 0.06) * r * 0.69),
        Paint()
          ..color = hudLine.withValues(alpha: 0.35)
          ..strokeWidth = 1.4 * scale
          ..strokeCap = StrokeCap.round,
      );
    }

    // Rotating translucent sonar/radar sweep beam
    final sweepStart = startRad + phase * twoPi;
    final sweepRect = Rect.fromCircle(center: center, radius: r * 0.96);
    canvas.drawArc(
      sweepRect,
      sweepStart,
      0.85,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: 0.85,
          colors: [
            Colors.transparent,
            accentColor.withValues(alpha: isLight ? 0.14 : 0.22),
            accentColor.withValues(alpha: isLight ? 0.38 : 0.48),
          ],
          stops: const [0.0, 0.72, 1.0],
          transform: GradientRotation(sweepStart),
        ).createShader(sweepRect),
    );

    // Target lock bearing line + jewel marker
    canvas.drawLine(
      Offset(center.dx + math.cos(activeRad) * r * 0.55,
          center.dy + math.sin(activeRad) * r * 0.55),
      Offset(center.dx + math.cos(activeRad) * r * 0.92,
          center.dy + math.sin(activeRad) * r * 0.92),
      Paint()
        ..color = accentColor
        ..strokeWidth = 2.4 * scale
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(center.dx + math.cos(activeRad) * r * 0.90,
          center.dy + math.sin(activeRad) * r * 0.90),
      3.0 * scale,
      Paint()..color = Colors.white,
    );
  }

  void _paintMagneticFluxInterior(
    Canvas canvas,
    Offset center,
    double r,
    double scale,
    double activeRad,
    double twoPi,
  ) {
    final cyanCore = Color.lerp(accentColor, const Color(0xFF38BDF8), 0.42)!;

    // Ferrofluid resonance pulse waves inside the core
    for (int k = 0; k < 2; k++) {
      final w = (phase + k * 0.5) % 1.0;
      final pulseR = r * (0.35 + 0.58 * w);
      canvas.drawCircle(
        center,
        pulseR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * scale
          ..color = (k == 0 ? accentColor : cyanCore)
              .withValues(alpha: (1.0 - w) * 0.42),
      );
    }

    // Internal tilted magnetic field ring piercing the glass chamber
    for (int i = 0; i < 2; i++) {
      final tilt = activeRad + i * math.pi * 0.5 + 0.15 * math.sin(phase * twoPi);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: r * 1.72, height: r * 0.78),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 * scale
          ..color = (i == 0 ? accentColor : cyanCore)
              .withValues(alpha: isLight ? 0.25 : 0.34),
      );
      canvas.restore();
    }

    // Glowing magnetic lock jewel on inner perimeter
    final jewel = Offset(
      center.dx + math.cos(activeRad) * r * 0.84,
      center.dy + math.sin(activeRad) * r * 0.84,
    );
    canvas.drawCircle(
      jewel,
      6.0 * scale,
      Paint()
        ..color = accentColor.withValues(alpha: 0.65)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale),
    );
    canvas.drawCircle(jewel, 2.8 * scale, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant DialInteriorEffectsPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.phase != phase ||
      oldDelegate.targetTemp != targetTemp ||
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isLight != isLight ||
      oldDelegate.flameIntensity != flameIntensity;
}

/// Live animated miniature full-dial preview card widget sharing a parent
/// [animation] so all 5 cards in the Theme sheet animate smoothly on one Ticker.
class DialRingPreviewThumb extends StatelessWidget {
  final DialRingStyle style;
  final Animation<double> animation;
  final double sizePx;
  final Color accentColor;
  final ThemePaletteSpec palette;
  final double targetTemp;
  final double flameIntensity;

  const DialRingPreviewThumb({
    super.key,
    required this.style,
    required this.animation,
    this.sizePx = 78.0,
    required this.accentColor,
    required this.palette,
    this.targetTemp = 23.0,
    this.flameIntensity = 0.65,
  });

  @override
  Widget build(BuildContext context) {
    final activeAngleDeg = ThermostatMath.tempToAngleDeg(targetTemp);
    final innerDiameter = sizePx * 0.76;
    final isLight = palette.isLight;
    final effectiveAccent = DialRingStyleInfo.resolveDialAccent(
      style: style,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );

    return SizedBox(
      width: sizePx,
      height: sizePx,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DialRingEffectLayer(
            style: style,
            animation: animation,
            sizePx: sizePx,
            targetTemp: targetTemp,
            activeAngleDeg: activeAngleDeg,
            accentColor: effectiveAccent,
            isLight: isLight,
            flameIntensity: flameIntensity,
          ),
          Container(
            width: innerDiameter,
            height: innerDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLight ? const Color(0xFFE2E8F0) : const Color(0xFF101218),
              border: Border.all(
                color: effectiveAccent.withValues(alpha: 0.42),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: effectiveAccent.withValues(alpha: 0.24),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipOval(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: DialInteriorEffectLayer(
                      style: style,
                      animation: animation,
                      diameterPx: innerDiameter,
                      targetTemp: targetTemp,
                      activeAngleDeg: activeAngleDeg,
                      accentColor: effectiveAccent,
                      isLight: isLight,
                      flameIntensity: flameIntensity,
                    ),
                  ),
                  Text(
                    '${targetTemp.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: sizePx * 0.20,
                      fontWeight: FontWeight.w800,
                      color: style == DialRingStyle.boilerFlame
                          ? Colors.white
                          : palette.textPrimary,
                      shadows: style == DialRingStyle.boilerFlame
                          ? const [
                              Shadow(color: Colors.black87, blurRadius: 6),
                            ]
                          : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
