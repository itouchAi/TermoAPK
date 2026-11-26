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
      style: DialRingStyle.liquidPlasma,
      titleTr: 'Sıvı Plazma Yörüngesi',
      titleEn: 'Liquid Plasma Orbit',
      badgeTr: 'Akışkan Neon',
      badgeEn: 'Fluid Neon',
      descriptionTr:
          'Hedef dereceye kadar akan parlak plazma arkı, kuyruklu yıldız ucu ve çift ters korona halkası.',
      descriptionEn:
          'Flowing glowing plasma arc up to the target degree with a comet-head flare and dual corona filaments.',
      swatchColor: Color(0xFFFF7A24),
      icon: Icons.blur_circular_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.chronoTurbine,
      titleTr: 'Kronometre Türbin',
      titleEn: 'Chrono Turbine',
      badgeTr: 'Mekanik 3D',
      badgeEn: 'Mechanical',
      descriptionTr:
          'Karşılıklı dönen hassas vernier çentikleri, türbin kanatçıkları ve metalik yansıma süpürmesi.',
      descriptionEn:
          'Counter-rotating precision vernier notches, turbine micro-vanes, and crisp metallic sweep glints.',
      swatchColor: Color(0xFF38BDF8),
      icon: Icons.precision_manufacturing_outlined,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.thermalPulse,
      titleTr: 'Termal Nabız Dalgası',
      titleEn: 'Thermal Pulse Wave',
      badgeTr: 'Isı Dalgalı',
      badgeEn: 'Heat Ripple',
      descriptionTr:
          'Merkezden dışa nefes alan eş merkezli ısı halkaları ve alev oranına duyarlı harmonik dalga.',
      descriptionEn:
          'Concentric thermal ripples breathing outward from the core with a flame-reactive harmonic wave.',
      swatchColor: Color(0xFFFF4D47),
      icon: Icons.waves_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.holoPrism,
      titleTr: 'Holografik Prizma',
      titleEn: 'Holographic Prism',
      badgeTr: 'Safir Kırılım',
      badgeEn: 'Sapphire Glass',
      descriptionTr:
          'Prizmatik gökkuşağı ışık kırılımı, safir cam kenar parıltısı ve dönen kristal yansımalar.',
      descriptionEn:
          'Iridescent spectral rim refraction, sapphire bezel flare arcs, and rotating crystal highlights.',
      swatchColor: Color(0xFFC084FC),
      icon: Icons.auto_awesome_rounded,
    ),
    DialRingStyleInfo(
      style: DialRingStyle.magneticFlux,
      titleTr: 'Manyetik Akı Yörüngesi',
      titleEn: 'Magnetic Flux Field',
      badgeTr: 'Parçacık Akı',
      badgeEn: 'Flux Particles',
      descriptionTr:
          'Elips manyetik alan çizgileri ve hedef göstergeye doğru süzülen parlak enerji parçacıkları.',
      descriptionEn:
          'Precessing elliptical magnetic field orbits with luminous micro-sparks gliding toward the needle.',
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
}

/// High-performance 60 FPS animated canvas layer rendered behind/around the dial
/// face and perimeter ticks.
class DialRingEffectLayer extends StatelessWidget {
  final DialRingStyle style;
  final Animation<double> animation;
  final double sizePx;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;
  final bool showOuterRipples;

  const DialRingEffectLayer({
    super.key,
    required this.style,
    required this.animation,
    required this.sizePx,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    this.flameIntensity = 0.65,
    this.showOuterRipples = true,
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
              painter: DialRingEffectsPainter(
                style: style,
                phase: animation.value,
                activeAngleDeg: activeAngleDeg,
                accentColor: accentColor,
                isLight: isLight,
                flameIntensity: flameIntensity,
                showOuterRipples: showOuterRipples,
              ),
            );
          },
        ),
      ),
    );
  }
}

class DialRingEffectsPainter extends CustomPainter {
  final DialRingStyle style;
  final double phase; // Seamless [0.0, 1.0)
  final double activeAngleDeg; // [-135, 135]
  final Color accentColor;
  final bool isLight;
  final double flameIntensity; // [0.0, 1.0]
  final bool showOuterRipples;

  const DialRingEffectsPainter({
    required this.style,
    required this.phase,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    this.flameIntensity = 0.65,
    this.showOuterRipples = true,
  });

  static double _degToCanvasRad(double deg) => (deg - 90.0) * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == DialRingStyle.classic || size.isEmpty) return;

    final center = size.center(Offset.zero);
    final d = math.min(size.width, size.height);
    final scale = (d / 232.0).clamp(0.26, 1.35);
    final faceR = d * 0.38;
    final outerTickR = d * 0.455;
    final trackR = (faceR + outerTickR) * 0.50;
    final startRad = _degToCanvasRad(ThermostatMath.dialStartDeg);
    final activeRad = _degToCanvasRad(activeAngleDeg);
    final fullSweepRad = 270.0 * math.pi / 180.0;
    final activeSweepRad = math.max(0.06, activeRad - startRad);
    final twoPi = math.pi * 2.0;

    switch (style) {
      case DialRingStyle.classic:
        break;
      case DialRingStyle.liquidPlasma:
        _paintLiquidPlasma(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          fullSweepRad,
          activeSweepRad,
          twoPi,
        );
        break;
      case DialRingStyle.chronoTurbine:
        _paintChronoTurbine(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweepRad,
          twoPi,
        );
        break;
      case DialRingStyle.thermalPulse:
        _paintThermalPulse(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweepRad,
          twoPi,
        );
        break;
      case DialRingStyle.holoPrism:
        _paintHoloPrism(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweepRad,
          twoPi,
        );
        break;
      case DialRingStyle.magneticFlux:
        _paintMagneticFlux(
          canvas,
          center,
          faceR,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweepRad,
          twoPi,
        );
        break;
    }
  }

  void _paintLiquidPlasma(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double fullSweepRad,
    double activeSweepRad,
    double twoPi,
  ) {
    final trackRect = Rect.fromCircle(center: center, radius: trackR);
    final outerOrbitRect =
        Rect.fromCircle(center: center, radius: outerTickR + 3.2 * scale);

    // Subtle recessed base arc
    canvas.drawArc(
      trackRect,
      startRad,
      fullSweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2 * scale
        ..strokeCap = StrokeCap.round
        ..color = isLight
            ? const Color(0xFF0F172A).withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.07),
    );

    final hotCore = Color.lerp(accentColor, Colors.white, 0.55)!;
    final warmShift = Color.lerp(accentColor, const Color(0xFFFBBF24), 0.35)!;

    // Soft glowing plasma under-arc with traveling flow pulse
    final rot = phase * twoPi;
    final plasmaShader = SweepGradient(
      center: Alignment.center,
      colors: [
        accentColor.withValues(alpha: isLight ? 0.55 : 0.45),
        warmShift.withValues(alpha: 0.92),
        hotCore,
        accentColor.withValues(alpha: 0.85),
        accentColor.withValues(alpha: isLight ? 0.55 : 0.45),
      ],
      stops: const [0.0, 0.30, 0.52, 0.78, 1.0],
      transform: GradientRotation(rot),
    ).createShader(trackRect);

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = (9.0 + 2.0 * flameIntensity) * scale
      ..strokeCap = StrokeCap.round
      ..shader = plasmaShader
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.5 * scale);
    canvas.drawArc(trackRect, startRad, activeSweepRad, false, glowPaint);

    // Razor-sharp inner plasma filament
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * scale
      ..strokeCap = StrokeCap.round
      ..shader = plasmaShader;
    canvas.drawArc(trackRect, startRad, activeSweepRad, false, corePaint);

    // Dual counter-rotating outer corona filaments
    for (int k = 0; k < 2; k++) {
      final dir = k == 0 ? 1.0 : -2.0;
      final a0 = phase * twoPi * dir + k * math.pi * 0.85;
      final arcLen = k == 0 ? 1.35 : 0.82;
      canvas.drawArc(
        outerOrbitRect,
        a0,
        arcLen,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (k == 0 ? 1.8 : 1.3) * scale
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              Colors.transparent,
              accentColor.withValues(alpha: k == 0 ? 0.85 : 0.55),
              hotCore.withValues(alpha: 0.95),
              Colors.transparent,
            ],
            stops: const [0.0, 0.45, 0.82, 1.0],
            transform: GradientRotation(a0),
          ).createShader(outerOrbitRect),
      );
    }

    // Comet-head flare at the active target tip
    final tip = Offset(
      center.dx + math.cos(activeRad) * trackR,
      center.dy + math.sin(activeRad) * trackR,
    );
    final pulse = 0.85 + 0.25 * math.sin(phase * twoPi * 2.0);
    canvas.drawCircle(
      tip,
      7.5 * scale * pulse,
      Paint()
        ..color = accentColor.withValues(alpha: 0.58)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.5 * scale),
    );
    canvas.drawCircle(
      tip,
      3.0 * scale,
      Paint()..color = hotCore,
    );
  }

  void _paintChronoTurbine(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweepRad,
    double twoPi,
  ) {
    final crispLine = isLight
        ? const Color(0xFF0F172A).withValues(alpha: 0.24)
        : Colors.white.withValues(alpha: 0.22);

    // Outer precision bezel hairline
    final outerBezelR = outerTickR + 4.5 * scale;
    canvas.drawCircle(
      center,
      outerBezelR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 * scale
        ..color = crispLine.withValues(alpha: 0.18),
    );

    // 12-fold outer Vernier notches rotating clockwise cleanly (2*pi/12 per cycle)
    const outerNotches = 12;
    final outerStep = twoPi / outerNotches;
    final outerRot = phase * outerStep;
    final notchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * scale
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < outerNotches; i++) {
      final a = outerRot + i * outerStep;
      final isHighlighted =
          ((math.sin(a - activeRad) + 1.0) * 0.5) > 0.84;
      notchPaint.color = isHighlighted
          ? accentColor.withValues(alpha: 0.92)
          : crispLine;
      final rIn = outerTickR + 2.0 * scale;
      final rOut = outerTickR + (i % 3 == 0 ? 7.2 : 5.0) * scale;
      canvas.drawLine(
        Offset(center.dx + math.cos(a) * rIn, center.dy + math.sin(a) * rIn),
        Offset(center.dx + math.cos(a) * rOut, center.dy + math.sin(a) * rOut),
        notchPaint,
      );
    }

    // 18-fold inner turbine vanes rotating counter-clockwise (-2*pi/18 per cycle)
    const innerVanes = 18;
    final innerStep = twoPi / innerVanes;
    final innerRot = -phase * innerStep * 2.0;
    final vaneInnerR = faceR + 2.2 * scale;
    final vaneOuterR = faceR + 7.2 * scale;
    final vanePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.45 * scale
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < innerVanes; i++) {
      final a0 = innerRot + i * innerStep;
      final a1 = a0 + 0.085; // Angled turbine blade slant
      vanePaint.color = accentColor.withValues(
        alpha: (i % 3 == 0) ? (isLight ? 0.62 : 0.72) : (isLight ? 0.24 : 0.28),
      );
      canvas.drawLine(
        Offset(center.dx + math.cos(a0) * vaneInnerR,
            center.dy + math.sin(a0) * vaneInnerR),
        Offset(center.dx + math.cos(a1) * vaneOuterR,
            center.dy + math.sin(a1) * vaneOuterR),
        vanePaint,
      );
    }

    // Crisp illuminated Chrono active arc + orbiting metallic glint
    final trackRect = Rect.fromCircle(center: center, radius: trackR);
    canvas.drawArc(
      trackRect,
      startRad,
      activeSweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * scale
        ..strokeCap = StrokeCap.butt
        ..color = accentColor.withValues(alpha: 0.78),
    );

    final sweepRect = Rect.fromCircle(center: center, radius: outerBezelR);
    final glintAngle = phase * twoPi;
    canvas.drawArc(
      sweepRect,
      glintAngle,
      0.95,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            Colors.transparent,
            (isLight ? const Color(0xFF0F172A) : Colors.white)
                .withValues(alpha: 0.75),
            accentColor,
            Colors.transparent,
          ],
          stops: const [0.0, 0.42, 0.72, 1.0],
          transform: GradientRotation(glintAngle),
        ).createShader(sweepRect),
    );

    // Laser-sharp target chevron at activeRad
    final tipR = outerTickR + 7.5 * scale;
    final tip = Offset(
      center.dx + math.cos(activeRad) * tipR,
      center.dy + math.sin(activeRad) * tipR,
    );
    canvas.drawCircle(tip, 2.4 * scale, Paint()..color = accentColor);
  }

  void _paintThermalPulse(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweepRad,
    double twoPi,
  ) {
    final rippleBoost = 0.75 + 0.45 * flameIntensity;

    // 3 staggered concentric thermal ripples breathing outward
    if (showOuterRipples) {
      for (int k = 0; k < 3; k++) {
        final w = (phase + k / 3.0) % 1.0;
        final ease = 1.0 - math.pow(1.0 - w, 1.65).toDouble();
        final r = faceR * 0.98 + (outerTickR * 1.13 - faceR * 0.98) * ease;
        final alpha =
            (1.0 - w) * (1.0 - w) * (isLight ? 0.36 : 0.46) * rippleBoost;
        if (alpha > 0.01) {
          canvas.drawCircle(
            center,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = (2.8 - 1.6 * w) * scale
              ..color = accentColor.withValues(alpha: alpha.clamp(0.0, 0.7)),
          );
        }
      }
    }

    // Harmonic sinusoidal wave ring hugging the dial perimeter
    const steps = 96;
    final wavePath = Path();
    final waveBaseR = outerTickR + 1.5 * scale;
    final baseAmp = (2.6 + 2.4 * flameIntensity) * scale;

    for (int s = 0; s <= steps; s++) {
      final frac = s / steps;
      final theta = frac * twoPi;
      // Compute whether theta falls near the heated zone
      var rel = (theta - startRad) % twoPi;
      if (rel < 0) rel += twoPi;
      final isHotZone = rel <= activeSweepRad + 0.15;
      final amp = isHotZone ? baseAmp : baseAmp * 0.25;
      final harmonic = math.sin(10.0 * theta - phase * twoPi * 2.0) * 0.65 +
          math.cos(6.0 * theta + phase * twoPi) * 0.35;
      final r = waveBaseR + amp * harmonic;
      final pt = Offset(
        center.dx + math.cos(theta) * r,
        center.dy + math.sin(theta) * r,
      );
      if (s == 0) {
        wavePath.moveTo(pt.dx, pt.dy);
      } else {
        wavePath.lineTo(pt.dx, pt.dy);
      }
    }
    wavePath.close();

    canvas.drawPath(
      wavePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6 * scale
        ..color = accentColor.withValues(alpha: isLight ? 0.24 : 0.34)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale),
    );
    canvas.drawPath(
      wavePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7 * scale
        ..color = Color.lerp(accentColor, Colors.white, 0.25)!
            .withValues(alpha: isLight ? 0.78 : 0.88),
    );

    // Warm heated inner arc glow
    final trackRect = Rect.fromCircle(center: center, radius: trackR);
    canvas.drawArc(
      trackRect,
      startRad,
      activeSweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 * scale
        ..strokeCap = StrokeCap.round
        ..color = accentColor.withValues(alpha: isLight ? 0.35 : 0.42)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * scale),
    );

    // Thermal beacon pulse on target
    final beat = 0.5 + 0.5 * math.sin(phase * twoPi * 2.0);
    final beaconPos = Offset(
      center.dx + math.cos(activeRad) * trackR,
      center.dy + math.sin(activeRad) * trackR,
    );
    canvas.drawCircle(
      beaconPos,
      (4.5 + 3.0 * beat) * scale,
      Paint()
        ..color = accentColor.withValues(alpha: 0.45 * (1.0 - 0.35 * beat))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.5 * scale),
    );
  }

  void _paintHoloPrism(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweepRad,
    double twoPi,
  ) {
    final rot = phase * twoPi;
    final prismColors = <Color>[
      accentColor,
      const Color(0xFF38BDF8),
      const Color(0xFFC084FC),
      if (isLight) const Color(0xFF0EA5E9) else Colors.white,
      const Color(0xFFFBBF24),
      accentColor,
    ];
    const prismStops = <double>[0.0, 0.22, 0.44, 0.62, 0.82, 1.0];

    final outerPrismRect =
        Rect.fromCircle(center: center, radius: outerTickR + 2.6 * scale);
    final innerPrismRect =
        Rect.fromCircle(center: center, radius: faceR + 2.8 * scale);

    // Soft prismatic halo ring
    canvas.drawCircle(
      center,
      outerTickR + 2.6 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 * scale
        ..shader = SweepGradient(
          colors: prismColors
              .map((c) => c.withValues(alpha: isLight ? 0.34 : 0.40))
              .toList(),
          stops: prismStops,
          transform: GradientRotation(rot),
        ).createShader(outerPrismRect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.5 * scale),
    );

    // Crisp iridescent outer sapphire rim
    canvas.drawCircle(
      center,
      outerTickR + 2.6 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9 * scale
        ..shader = SweepGradient(
          colors: prismColors
              .map((c) => c.withValues(alpha: isLight ? 0.82 : 0.90))
              .toList(),
          stops: prismStops,
          transform: GradientRotation(rot),
        ).createShader(outerPrismRect),
    );

    // Counter-rotating inner bevel refraction ring
    canvas.drawCircle(
      center,
      faceR + 2.8 * scale,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * scale
        ..shader = SweepGradient(
          colors: prismColors
              .map((c) => c.withValues(alpha: isLight ? 0.55 : 0.65))
              .toList(),
          stops: prismStops,
          transform: GradientRotation(-rot),
        ).createShader(innerPrismRect),
    );

    // Dual crisp studio glass specular flare arcs
    for (int k = 0; k < 2; k++) {
      final a = rot + k * math.pi;
      canvas.drawArc(
        outerPrismRect,
        a,
        0.65,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 * scale
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: isLight ? 0.92 : 0.88),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
            transform: GradientRotation(a),
          ).createShader(outerPrismRect),
      );
    }

    // Active prismatic fill arc
    final trackRect = Rect.fromCircle(center: center, radius: trackR);
    canvas.drawArc(
      trackRect,
      startRad,
      activeSweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4 * scale
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: prismColors,
          stops: prismStops,
          transform: GradientRotation(rot * 0.5),
        ).createShader(trackRect),
    );
  }

  void _paintMagneticFlux(
    Canvas canvas,
    Offset center,
    double faceR,
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweepRad,
    double twoPi,
  ) {
    final cyanCore = Color.lerp(accentColor, const Color(0xFF38BDF8), 0.35)!;
    final brightCore = Color.lerp(accentColor, Colors.white, 0.65)!;

    // 3 precessing elliptical magnetic field orbits
    for (int i = 0; i < 3; i++) {
      final tilt = i * (math.pi / 3.0) +
          0.18 * math.sin(phase * twoPi + i * 2.094);
      final rx = outerTickR * (1.03 + 0.025 * math.sin(phase * twoPi + i));
      final ry = outerTickR * (0.89 + 0.025 * math.cos(phase * twoPi + i));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2, height: ry * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (i == 0 ? 1.5 : 1.1) * scale
          ..color = (i == 1 ? cyanCore : accentColor)
              .withValues(alpha: isLight ? 0.34 : 0.40),
      );
      canvas.restore();
    }

    // Subtle field rail along the active span
    final trackRect = Rect.fromCircle(center: center, radius: trackR);
    canvas.drawArc(
      trackRect,
      startRad,
      activeSweepRad,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 * scale
        ..strokeCap = StrokeCap.round
        ..color = accentColor.withValues(alpha: isLight ? 0.38 : 0.42),
    );

    // 8 luminous flux particles gliding along the active temperature span
    const particleCount = 8;
    for (int p = 0; p < particleCount; p++) {
      final t = (phase + p / particleCount) % 1.0;
      final easedT = math.pow(t, 1.18).toDouble();
      final theta = startRad + activeSweepRad * easedT;
      final radialWave =
          math.sin(t * twoPi * 2.0 + p * 1.1) * 4.5 * scale;
      final pr = trackR + radialWave;
      final pos = Offset(
        center.dx + math.cos(theta) * pr,
        center.dy + math.sin(theta) * pr,
      );
      // Fade in at start and flare right as it converges on target needle
      final envelope = math.sin(t * math.pi).clamp(0.0, 1.0);
      final radius = (1.6 + 1.8 * envelope) * scale;

      canvas.drawCircle(
        pos,
        radius * 2.1,
        Paint()
          ..color = accentColor.withValues(alpha: 0.45 * envelope)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.8 * scale),
      );
      canvas.drawCircle(
        pos,
        radius,
        Paint()..color = brightCore.withValues(alpha: 0.92 * envelope),
      );
    }

    // Target magnetic pole convergence node
    final pole = Offset(
      center.dx + math.cos(activeRad) * trackR,
      center.dy + math.sin(activeRad) * trackR,
    );
    canvas.drawCircle(
      pole,
      6.0 * scale,
      Paint()
        ..color = accentColor.withValues(alpha: 0.48)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale),
    );
    canvas.drawCircle(pole, 2.6 * scale, Paint()..color = brightCore);
  }

  @override
  bool shouldRepaint(covariant DialRingEffectsPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.phase != phase ||
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isLight != isLight ||
      oldDelegate.flameIntensity != flameIntensity ||
      oldDelegate.showOuterRipples != showOuterRipples;
}

/// Compact live animated thumbnail of a thermostat dial using any [DialRingStyle],
/// driven by a shared parent [animation] so multiple preview cards animate smoothly
/// on a single Ticker.
class DialRingPreviewThumb extends StatelessWidget {
  final DialRingStyle style;
  final Animation<double> animation;
  final double sizePx;
  final Color accentColor;
  final ThemePaletteSpec palette;
  final double targetTemp;

  const DialRingPreviewThumb({
    super.key,
    required this.style,
    required this.animation,
    this.sizePx = 68.0,
    required this.accentColor,
    required this.palette,
    this.targetTemp = 22.5,
  });

  @override
  Widget build(BuildContext context) {
    final activeAngleDeg = ThermostatMath.tempToAngleDeg(targetTemp);
    final innerDiameter = sizePx * 0.72;
    final isLight = palette.isLight;
    final scale = (sizePx / 232.0).clamp(0.24, 1.0);

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
            activeAngleDeg: activeAngleDeg,
            accentColor: accentColor,
            isLight: isLight,
            flameIntensity: 0.78,
            showOuterRipples: false,
          ),
          CustomPaint(
            size: Size(sizePx, sizePx),
            painter: _MiniTickRingPainter(
              activeAngleDeg: activeAngleDeg,
              accentColor: accentColor,
              unlitTickColor: isLight
                  ? const Color(0xFF0F172A).withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.16),
              scale: scale,
            ),
          ),
          Container(
            width: innerDiameter,
            height: innerDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isLight
                    ? const [Color(0xFFFFFFFF), Color(0xFFE2E8F0)]
                    : const [Color(0xFF23252D), Color(0xFF0F1015)],
              ),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.35),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.24),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: activeAngleDeg * math.pi / 180.0,
                  child: Transform.translate(
                    offset: Offset(0, -innerDiameter * 0.35),
                    child: Container(
                      width: 3.0,
                      height: 6.0,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: [
                          BoxShadow(color: accentColor, blurRadius: 5),
                        ],
                      ),
                    ),
                  ),
                ),
                Text(
                  '${targetTemp.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: sizePx * 0.19,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTickRingPainter extends CustomPainter {
  final double activeAngleDeg;
  final Color accentColor;
  final Color unlitTickColor;
  final double scale;

  const _MiniTickRingPainter({
    required this.activeAngleDeg,
    required this.accentColor,
    required this.unlitTickColor,
    required this.scale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const totalTicks = 27;
    final center = Offset(size.width / 2, size.height / 2);
    final tickRadius = size.width * 0.455;

    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = (tickDeg - 90.0) * math.pi / 180.0;
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 3 == 0;
      final len = (isMajor ? 9.5 : 6.5) * scale;

      final p1 = Offset(
        center.dx + math.cos(rad) * (tickRadius - len),
        center.dy + math.sin(rad) * (tickRadius - len),
      );
      final p2 = Offset(
        center.dx + math.cos(rad) * tickRadius,
        center.dy + math.sin(rad) * tickRadius,
      );

      final paint = Paint()
        ..color = isLit ? accentColor.withValues(alpha: 0.92) : unlitTickColor
        ..strokeWidth = (isMajor ? 2.4 : 1.7) * scale
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniTickRingPainter oldDelegate) =>
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.unlitTickColor != unlitTickColor ||
      oldDelegate.scale != scale;
}
