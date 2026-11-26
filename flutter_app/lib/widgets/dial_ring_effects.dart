import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

/// Shared GPU GLSL shader cache for dial interiors (`boilerFlame` and `thermoMercury`).
/// Fails gracefully to procedural Canvas fallback in headless widget tests.
class DialShaderBank {
  DialShaderBank._();

  static ui.FragmentProgram? flameProgram;
  static ui.FragmentProgram? liquidProgram;
  static Future<void>? _loadFuture;

  static Future<void> ensureLoaded() {
    return _loadFuture ??= _loadAll();
  }

  static Future<void> _loadAll() async {
    try {
      flameProgram ??=
          await ui.FragmentProgram.fromAsset('shaders/boiler_flame.frag');
    } catch (_) {}
    try {
      liquidProgram ??=
          await ui.FragmentProgram.fromAsset('shaders/thermo_liquid.frag');
    } catch (_) {}
  }
}

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

  static const List<DialRingStyleInfo> dynamicThemes = [
    DialRingStyleInfo(
      style: DialRingStyle.boilerFlame,
      titleTr: 'Gerçekçi Kombi Alevi',
      titleEn: 'Realistic Boiler Flame',
      badgeTr: 'GLSL Volümetrik',
      badgeEn: 'GLSL Fire',
      descriptionTr:
          'GPU shader tabanlı gerçekçi yanma odası: sönük mavi pilot ışığı, mavi gaz brülörü ve ısı arttıkça harlanan türbülanslı alev & kıvılcımlar.',
      descriptionEn:
          'GPU volumetric combustion shader: dim pilot glow on standby, blue gas jets, and turbulent roaring amber flames & rising embers.',
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
      badgeTr: 'GLSL Sıvı & Kostik',
      badgeEn: 'GLSL Fluid',
      descriptionTr:
          'Cam küre içinde dereceyle yükselip alçalan gerçekçi dalgalı termal sıvı, yüzey kostikleri ve yükselen mikro kabarcıklar.',
      descriptionEn:
          'GPU-shaded sloshing thermal liquid inside the glass sphere with underwater caustics, glowing meniscus & rising micro-bubbles.',
      swatchColor: Color(0xFFFF7A24),
      icon: Icons.water_drop_rounded,
    ),
  ];

  static DialRingStyleInfo? findDynamic(DialRingStyle style) {
    for (final item in dynamicThemes) {
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

/// Renders the outer animated bezel and perimeter scale around the dial face.
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

/// Renders the GPU-shaded / mechanical interior INSIDE the circular dial face
/// (`boilerFlame` volumetric GLSL fire, `autoTacho` 10-30 3D needle gauge,
/// `thermoMercury` GLSL volumetric liquid & caustics).
class DialInteriorEffectLayer extends StatefulWidget {
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
  State<DialInteriorEffectLayer> createState() =>
      _DialInteriorEffectLayerState();
}

class _DialInteriorEffectLayerState extends State<DialInteriorEffectLayer> {
  double _lastPhase = 0.0;
  double _elapsedSec = 0.0;

  @override
  void initState() {
    super.initState();
    _lastPhase = widget.animation.value;
    widget.animation.addListener(_onTick);
    DialShaderBank.ensureLoaded().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant DialInteriorEffectLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeListener(_onTick);
      _lastPhase = widget.animation.value;
      widget.animation.addListener(_onTick);
    }
  }

  void _onTick() {
    final cur = widget.animation.value;
    var delta = cur - _lastPhase;
    if (delta < 0.0) delta += 1.0;
    _lastPhase = cur;
    // Continuous seconds derived from parent animation so GLSL noise/embers
    // never snap or reset on animation controller loop boundaries.
    _elapsedSec += delta * 6.0;
  }

  @override
  void dispose() {
    widget.animation.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.style == DialRingStyle.classic) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            return CustomPaint(
              size: Size(widget.diameterPx, widget.diameterPx),
              painter: DialInteriorEffectsPainter(
                style: widget.style,
                phase: widget.animation.value,
                elapsedSec: _elapsedSec,
                targetTemp: widget.targetTemp,
                activeAngleDeg: widget.activeAngleDeg,
                accentColor: widget.accentColor,
                isLight: widget.isLight,
                flameIntensity: widget.flameIntensity,
                flameProgram: DialShaderBank.flameProgram,
                liquidProgram: DialShaderBank.liquidProgram,
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
          outerTickR,
          scale,
          activeRad,
          twoPi,
        );
        break;
      case DialRingStyle.autoTacho:
        _paintAutoTachoOuter(
          canvas,
          center,
          faceR,
          outerTickR,
          scale,
          startRad,
          activeSweep,
        );
        break;
      case DialRingStyle.thermoMercury:
        _paintThermoMercuryOuter(
          canvas,
          center,
          trackR,
          outerTickR,
          scale,
          startRad,
          activeRad,
          activeSweep,
        );
        break;
    }
  }

  void _paintBoilerOuter(
    Canvas canvas,
    Offset center,
    double faceR,
    double outerTickR,
    double scale,
    double activeRad,
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
        tickColor = flameIntensity <= 0.05
            ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
            : Color.lerp(
                const Color(0xFF38BDF8),
                const Color(0xFFFF6B1A),
                (tFrac * effectiveHeat * 1.15).clamp(0.0, 1.0),
              )!;
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
    double outerTickR,
    double scale,
    double startRad,
    double activeSweep,
  ) {
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
    double trackR,
    double outerTickR,
    double scale,
    double startRad,
    double activeRad,
    double activeSweep,
  ) {
    final fluidColor = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.thermoMercury,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );

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
  final double elapsedSec;
  final double targetTemp;
  final double activeAngleDeg;
  final Color accentColor;
  final bool isLight;
  final double flameIntensity;
  final ui.FragmentProgram? flameProgram;
  final ui.FragmentProgram? liquidProgram;

  const DialInteriorEffectsPainter({
    required this.style,
    required this.phase,
    required this.elapsedSec,
    required this.targetTemp,
    required this.activeAngleDeg,
    required this.accentColor,
    required this.isLight,
    required this.flameIntensity,
    this.flameProgram,
    this.liquidProgram,
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
    }

    // Crisp top glass rim specular arc
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
    final prog = flameProgram;
    if (prog != null) {
      final tempNorm = ((targetTemp - ThermostatMath.minTemp) /
              (ThermostatMath.maxTemp - ThermostatMath.minTemp))
          .clamp(0.0, 1.0);
      final shader = prog.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, elapsedSec);
      shader.setFloat(3, flameIntensity.clamp(0.0, 1.0));
      shader.setFloat(4, tempNorm);
      shader.setFloat(5, isLight ? 1.0 : 0.0);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }

    // Smooth atmospheric volumetric fallback when shader program is loading / headless test
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.0, 0.35),
          radius: 0.95,
          colors: [Color(0xFF131822), Color(0xFF090B10), Color(0xFF040507)],
        ).createShader(Offset.zero & size),
    );
    final isHeating = flameIntensity > 0.05;
    final thermalCol = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.boilerFlame,
      baseAccent: accentColor,
      targetTemp: targetTemp,
      flameIntensity: flameIntensity,
    );
    final pulse = 0.88 + 0.12 * math.sin(phase * twoPi * 3.0);
    final glowCenter = Offset(center.dx, center.dy + r * (isHeating ? 0.32 : 0.56));
    final glowRadius = r * (isHeating ? (0.65 + 0.35 * flameIntensity) : 0.32) * pulse;
    canvas.drawCircle(
      glowCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: isHeating ? 0.55 : 0.30),
            thermalCol.withValues(alpha: isHeating ? 0.68 : 0.45),
            const Color(0xFF1D4ED8).withValues(alpha: 0.18),
            Colors.transparent,
          ],
          stops: const [0.0, 0.32, 0.68, 1.0],
        ).createShader(Rect.fromCircle(center: glowCenter, radius: glowRadius)),
    );
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

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(activeRad + math.pi / 2.0);

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

    canvas.drawPath(
      needlePath.shift(Offset(1.8 * scale, 2.2 * scale)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale),
    );

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
    final fillFrac = 0.16 + norm * 0.74;

    final prog = liquidProgram;
    if (prog != null) {
      final shader = prog.fragmentShader();
      shader.setFloat(0, size.width);
      shader.setFloat(1, size.height);
      shader.setFloat(2, elapsedSec);
      shader.setFloat(3, fillFrac);
      shader.setFloat(4, flameIntensity.clamp(0.0, 1.0));
      shader.setFloat(5, fluidColor.r);
      shader.setFloat(6, fluidColor.g);
      shader.setFloat(7, fluidColor.b);
      shader.setFloat(8, isLight ? 1.0 : 0.0);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }

    // Canvas fallback when shader is loading / headless test
    final deepFluid = Color.lerp(fluidColor, Colors.black, 0.35)!;
    final brightMeniscus = Color.lerp(fluidColor, Colors.white, 0.55)!;

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

    final surfaceY = (center.dy + r) - (2.0 * r * fillFrac);
    final amp = (3.5 + 3.0 * flameIntensity) * scale;

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
    canvas.drawPath(backWave, Paint()..color = deepFluid.withValues(alpha: 0.58));

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

    canvas.drawPath(
      meniscus,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * scale
        ..color = brightMeniscus.withValues(alpha: 0.90),
    );

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

  @override
  bool shouldRepaint(covariant DialInteriorEffectsPainter oldDelegate) =>
      oldDelegate.style != style ||
      oldDelegate.phase != phase ||
      oldDelegate.elapsedSec != elapsedSec ||
      oldDelegate.targetTemp != targetTemp ||
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isLight != isLight ||
      oldDelegate.flameIntensity != flameIntensity ||
      oldDelegate.flameProgram != flameProgram ||
      oldDelegate.liquidProgram != liquidProgram;
}

/// Live animated miniature full-dial preview card widget sharing a parent
/// [animation] so all preview cards in the Theme sheet animate smoothly on one Ticker.
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
