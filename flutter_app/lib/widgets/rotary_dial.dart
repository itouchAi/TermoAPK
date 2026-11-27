import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/thermostat_state.dart';
import 'dial_ring_effects.dart';
import 'tactile_button.dart';

class RotaryDial extends StatefulWidget {
  final double targetTemp;
  final ValueChanged<double> onChangeTarget;
  final String modeName;
  final Color accentColor;
  final BoilerTelemetry boiler;
  final LangCode lang;
  final ThemePaletteSpec palette;
  final double sizePx;
  final bool compact;
  final DialRingStyle dialRingStyle;
  final PerformanceMode performanceMode;

  const RotaryDial({
    super.key,
    required this.targetTemp,
    required this.onChangeTarget,
    required this.modeName,
    required this.accentColor,
    required this.boiler,
    required this.lang,
    required this.palette,
    this.sizePx = 232.0,
    this.compact = false,
    this.dialRingStyle = DialRingStyle.classic,
    this.performanceMode = PerformanceMode.ultra60fps,
  });

  /// Exact outermost radius of the 45 perimeter tick marks.
  static double outerTickRadiusForSize(double sizePx) => sizePx * 0.455;

  @override
  State<RotaryDial> createState() => _RotaryDialState();
}

class _RotaryDialState extends State<RotaryDial> with TickerProviderStateMixin {
  static const double _hoverScale = 1.018;
  static const double _pressScale = 1.034;

  late final AnimationController _tactileCtrl;
  late final AnimationController _ringAnimCtrl;
  final GlobalKey _dialCircleKey = GlobalKey();
  final Object _dialFocusToken = Object();

  bool _hovered = false;
  bool _pressed = false;
  double _wheelAccum = 0.0;
  DateTime? _lastWheelStepAt;

  @override
  void initState() {
    super.initState();
    _tactileCtrl = AnimationController.unbounded(vsync: this, value: 1.0);
    _ringAnimCtrl = AnimationController(
      vsync: this,
      duration: _durationForPerf(widget.performanceMode),
    );
    _syncRingAnimation();
  }

  Duration _durationForPerf(PerformanceMode mode) => mode == PerformanceMode.ecoBattery
      ? const Duration(seconds: 10)
      : const Duration(seconds: 6);

  void _syncRingAnimation() {
    if (widget.dialRingStyle == DialRingStyle.classic) {
      if (_ringAnimCtrl.isAnimating) {
        _ringAnimCtrl.stop();
      }
      return;
    }
    final wanted = _durationForPerf(widget.performanceMode);
    if (_ringAnimCtrl.duration != wanted) {
      _ringAnimCtrl.duration = wanted;
    }
    if (!_ringAnimCtrl.isAnimating) {
      _ringAnimCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant RotaryDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dialRingStyle != widget.dialRingStyle ||
        oldWidget.performanceMode != widget.performanceMode) {
      _syncRingAnimation();
    }
  }

  @override
  void dispose() {
    TactileMotionScope.endFocus(_dialFocusToken);
    _ringAnimCtrl.dispose();
    _tactileCtrl.dispose();
    super.dispose();
  }

  void _updateFromLocalOffset(Offset localPosition) {
    final center = Offset(widget.sizePx / 2, widget.sizePx / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final next = ThermostatMath.pointerOffsetToTemp(dx, dy);
    if ((next - widget.targetTemp).abs() >= 0.05) {
      widget.onChangeTarget(next);
    }
  }

  void _animateTactile({required bool isRelease}) {
    if (!mounted) return;
    final tactileOn = TactileMotionScope.isEnabled(context);
    if (!tactileOn) {
      _tactileCtrl.value = 1.0;
      return;
    }
    final target = _pressed ? _pressScale : (_hovered ? _hoverScale : 1.0);
    if (_pressed) {
      _tactileCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 95),
        curve: Curves.easeOutCubic,
      );
    } else if (isRelease) {
      _tactileCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
      );
    } else {
      _tactileCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 145),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _syncDialFocus() {
    if (!mounted || !TactileMotionScope.isEnabled(context)) {
      TactileMotionScope.endFocus(_dialFocusToken);
      return;
    }
    if (!_hovered && !_pressed) {
      TactileMotionScope.endFocus(_dialFocusToken);
      return;
    }
    final dialCtx = _dialCircleKey.currentContext ?? context;
    final outerRadius = RotaryDial.outerTickRadiusForSize(widget.sizePx);
    final activeScale = _pressed ? _pressScale : _hoverScale;
    TactileMotionScope.beginFocus(
      dialCtx,
      token: _dialFocusToken,
      isCircle: true,
      isPressed: _pressed,
      overrideCircleRadius: outerRadius * activeScale + 6.0,
    );
  }

  void _beginDialPress() {
    if (!_pressed) {
      setState(() => _pressed = true);
    }
    if (TactileMotionScope.isEnabled(context)) {
      _animateTactile(isRelease: false);
      _syncDialFocus();
    }
  }

  void _endDialPress() {
    if (_pressed) {
      setState(() => _pressed = false);
      _animateTactile(isRelease: true);
    }
    _syncDialFocus();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    TactileMotionScope.markScrollEventConsumed(event);
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      _handleResolvedScrollEvent,
    );
  }

  void _handleResolvedScrollEvent(PointerSignalEvent resolved) {
    if (!mounted || resolved is! PointerScrollEvent) return;
    final dy = resolved.scrollDelta.dy;
    final dx = resolved.scrollDelta.dx;
    final raw = dy != 0.0 ? -dy : dx;
    if (raw.abs() < 0.5) return;

    final now = DateTime.now();
    if (_lastWheelStepAt != null &&
        now.difference(_lastWheelStepAt!).inMilliseconds > 220) {
      _wheelAccum = 0.0;
    }
    _wheelAccum += raw;
    if (_wheelAccum.abs() >= 10.0 ||
        _lastWheelStepAt == null ||
        now.difference(_lastWheelStepAt!).inMilliseconds >= 65) {
      final dir = _wheelAccum > 0 ? 1.0 : -1.0;
      _wheelAccum = 0.0;
      _lastWheelStepAt = now;
      final next = ThermostatMath.snapTemperature(
        widget.targetTemp + dir * ThermostatMath.tempStep,
      );
      if ((next - widget.targetTemp).abs() >= 0.05) {
        widget.onChangeTarget(next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tactileActive = TactileMotionScope.isEnabled(context);
    if (!tactileActive) {
      if (_tactileCtrl.value != 1.0) {
        _tactileCtrl.value = 1.0;
      }
      _hovered = false;
      _pressed = false;
      TactileMotionScope.endFocus(_dialFocusToken);
    }

    final activeAngleDeg = ThermostatMath.tempToAngleDeg(widget.targetTemp);
    final outerTickRadius = RotaryDial.outerTickRadiusForSize(widget.sizePx);
    final innerDiameter = widget.sizePx * 0.76;
    final knobRadius = innerDiameter * 0.39;
    final isLight = widget.palette.isLight;
    final isTactile = widget.palette.isTactileDeck;
    final isDynamic = widget.dialRingStyle != DialRingStyle.classic;

    final flameIntensity = widget.boiler.isHeating
        ? (widget.boiler.flamePercent / 100.0).clamp(0.18, 1.0)
        : 0.0;
    final effectiveAccent = isDynamic
        ? DialRingStyleInfo.resolveDialAccent(
            style: widget.dialRingStyle,
            baseAccent: widget.accentColor,
            targetTemp: widget.targetTemp,
            flameIntensity: flameIntensity,
          )
        : widget.accentColor;

    final isFlameStyle = widget.dialRingStyle == DialRingStyle.boilerFlame;
    final centerPrimaryColor =
        isFlameStyle ? Colors.white : widget.palette.textPrimary;
    final centerSecondaryColor =
        isFlameStyle ? Colors.white70 : widget.palette.textSecondary;

    final dialColors = isLight
        ? const [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFE2E8F0)]
        : isTactile
            ? const [Color(0xFF2D2724), Color(0xFF1C1816), Color(0xFF100E0C)]
            : const [Color(0xFF23252D), Color(0xFF17181F), Color(0xFF0F1015)];

    final dialFace = Container(
      width: innerDiameter,
      height: innerDiameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dialColors,
        ),
        border: Border.all(
          width: isTactile ? 2.0 : 1.0,
          color: isFlameStyle
              ? effectiveAccent.withValues(alpha: 0.45)
              : isTactile
                  ? const Color(0xFFD97706).withValues(alpha: 0.35)
                  : (isLight
                      ? widget.palette.cardBorder
                      : Colors.white.withValues(alpha: 0.10)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isLight ? 0.20 : 0.78),
            blurRadius: isLight ? 24 : 36,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: effectiveAccent.withValues(
              alpha: (tactileActive && _pressed)
                  ? (isLight ? 0.30 : 0.40)
                  : (isLight ? 0.16 : 0.22),
            ),
            blurRadius: (tactileActive && _pressed) ? 36 : 28,
            spreadRadius: (tactileActive && _pressed) ? 2 : 0,
          ),
        ],
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (!isDynamic) ...[
              // 3D top specular highlight & bottom concave inner shadow
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _DialBevelPainter(isLight: isLight),
                  ),
                ),
              ),

              // Rotating glowing indicator pill
              Transform.rotate(
                angle: activeAngleDeg * math.pi / 180.0,
                child: Transform.translate(
                  offset: Offset(0, -knobRadius),
                  child: Container(
                    width: 6,
                    height: 15,
                    decoration: BoxDecoration(
                      color: Color.lerp(effectiveAccent, Colors.white, 0.28),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.75),
                          blurRadius: 4,
                        ),
                        BoxShadow(
                          color: effectiveAccent,
                          blurRadius: 14,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else
              // Bespoke full-dial physics/mechanics interior (flames, tacho needle, liquid, radar, reactor)
              Positioned.fill(
                child: DialInteriorEffectLayer(
                  style: widget.dialRingStyle,
                  animation: _ringAnimCtrl,
                  diameterPx: innerDiameter,
                  targetTemp: widget.targetTemp,
                  activeAngleDeg: activeAngleDeg,
                  accentColor: effectiveAccent,
                  isLight: isLight,
                  flameIntensity: flameIntensity,
                ),
              ),

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.lang == LangCode.tr
                      ? 'HEDEF TERMOSTAT'
                      : 'TARGET THERMOSTAT',
                  style: TextStyle(
                    fontSize: widget.compact ? 9 : 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: centerSecondaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.targetTemp.toStringAsFixed(1)}°',
                  style: TextStyle(
                    fontSize: widget.compact ? 30 : 44,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    letterSpacing: -0.5,
                    color: centerPrimaryColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.modeName,
                  style: TextStyle(
                    fontSize: widget.compact ? 9 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: effectiveAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.boiler.hasSensorReading
                          ? Icons.local_fire_department_outlined
                          : Icons.link_off_rounded,
                      size: 12,
                      color: widget.boiler.isHeating
                          ? effectiveAccent
                          : centerSecondaryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      widget.lang == LangCode.tr
                          ? widget.boiler.statusTextTr
                          : widget.boiler.statusTextEn,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: centerSecondaryColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final dialWithTicks = SizedBox(
      key: _dialCircleKey,
      width: widget.sizePx,
      height: widget.sizePx,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (isDynamic)
            DialRingEffectLayer(
              style: widget.dialRingStyle,
              animation: _ringAnimCtrl,
              sizePx: widget.sizePx,
              targetTemp: widget.targetTemp,
              activeAngleDeg: activeAngleDeg,
              accentColor: effectiveAccent,
              isLight: isLight,
              flameIntensity: flameIntensity,
            )
          else
            // 45 Segmented radial perimeter ticks (Classic)
            CustomPaint(
              size: Size(widget.sizePx, widget.sizePx),
              painter: _TickRingPainter(
                activeAngleDeg: activeAngleDeg,
                accentColor: effectiveAccent,
                unlitTickColor: isLight
                    ? const Color(0xFF0F172A).withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.16),
              ),
            ),

          // Inner sculpted 3D dial face
          dialFace,
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.sizePx,
          height: widget.sizePx,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Wide feathered atmospheric radial aura behind the dial
              OverflowBox(
                maxWidth: widget.sizePx * 1.48,
                maxHeight: widget.sizePx * 1.48,
                child: IgnorePointer(
                  child: Container(
                    width: widget.sizePx * 1.42,
                    height: widget.sizePx * 1.42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.05),
                        radius: 0.5,
                        colors: [
                          effectiveAccent.withValues(
                            alpha: (tactileActive && _pressed)
                                ? (isLight ? 0.28 : 0.34)
                                : (isLight ? 0.20 : 0.25),
                          ),
                          effectiveAccent
                              .withValues(alpha: isLight ? 0.08 : 0.09),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.48, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // Exact circular touch, wheel, and hover region bounded at the
              // outer tips of the 45 perimeter tick marks (r = sizePx * 0.455).
              _CircularHitTest(
                radius: outerTickRadius,
                child: MouseRegion(
                  cursor: _pressed
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab,
                  onEnter: (_) {
                    if (!_hovered) {
                      setState(() => _hovered = true);
                    }
                    if (tactileActive) {
                      _syncDialFocus();
                      if (!_pressed) {
                        _animateTactile(isRelease: false);
                      }
                    }
                  },
                  onExit: (_) {
                    final wasPressed = _pressed;
                    if (_hovered || _pressed) {
                      setState(() {
                        _hovered = false;
                        _pressed = false;
                      });
                    }
                    _syncDialFocus();
                    if (tactileActive) {
                      _animateTactile(isRelease: wasPressed);
                    }
                  },
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerSignal: _handlePointerSignal,
                    onPointerDown: (details) {
                      _beginDialPress();
                      _updateFromLocalOffset(details.localPosition);
                    },
                    onPointerMove: (details) =>
                        _updateFromLocalOffset(details.localPosition),
                    onPointerUp: (_) => _endDialPress(),
                    onPointerCancel: (_) => _endDialPress(),
                    child: RawGestureDetector(
                      behavior: HitTestBehavior.opaque,
                      gestures: <Type, GestureRecognizerFactory>{
                        EagerGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                EagerGestureRecognizer>(
                          () => EagerGestureRecognizer(),
                          (EagerGestureRecognizer instance) {},
                        ),
                      },
                      child: tactileActive
                          ? AnimatedBuilder(
                              animation: _tactileCtrl,
                              builder: (context, child) {
                                final s = _tactileCtrl.value;
                                final t = ((s - 1.0) / (_pressScale - 1.0))
                                    .clamp(0.0, 1.2);
                                final dy = -2.0 * t;
                                return Transform.translate(
                                  offset: Offset(0.0, dy),
                                  child: Transform.scale(
                                    scale: s,
                                    alignment: Alignment.center,
                                    child: child,
                                  ),
                                );
                              },
                              child: dialWithTicks,
                            )
                          : dialWithTicks,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: widget.compact ? 6 : 14),

        // Tactile - / ±0.5°C / + Stepper Row
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepperButton(
              icon: Icons.remove_rounded,
              size: widget.compact ? 40 : 44,
              enabled: widget.targetTemp > ThermostatMath.minTemp,
              palette: widget.palette,
              onTap: () => widget.onChangeTarget(
                ThermostatMath.snapTemperature(
                  widget.targetTemp - ThermostatMath.tempStep,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '±0.5°C',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: widget.palette.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _StepperButton(
              icon: Icons.add_rounded,
              size: widget.compact ? 40 : 44,
              enabled: widget.targetTemp < ThermostatMath.maxTemp,
              palette: widget.palette,
              onTap: () => widget.onChangeTarget(
                ThermostatMath.snapTemperature(
                  widget.targetTemp + ThermostatMath.tempStep,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Constrains pointer hit-testing (touch, pan, hover, and mouse wheel) strictly
/// to a circle centered on this box with the given [radius].
class _CircularHitTest extends SingleChildRenderObjectWidget {
  final double radius;

  const _CircularHitTest({
    required this.radius,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCircularHitTest(radius: radius);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCircularHitTest renderObject,
  ) {
    renderObject.radius = radius;
  }
}

class _RenderCircularHitTest extends RenderProxyBox {
  double _radius;

  _RenderCircularHitTest({required double radius}) : _radius = radius;

  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final center = size.center(Offset.zero);
    if ((position - center).distance > _radius) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool enabled;
  final ThemePaletteSpec palette;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.size,
    required this.enabled,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLight = palette.isLight;
    return TactilePress(
      enabled: enabled,
      focusCircle: true,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isLight ? palette.cardBg : Colors.white.withValues(alpha: 0.065),
            border: Border.all(
              color: isLight
                  ? palette.cardBorder
                  : Colors.white.withValues(alpha: 0.13),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isLight ? 0.12 : 0.48),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipOval(
            child: CustomPaint(
              painter: _CircleTopRimPainter(isLight: isLight),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enabled ? onTap : null,
                  child: Center(
                    child: Icon(icon, color: palette.textPrimary, size: 18),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialBevelPainter extends CustomPainter {
  final bool isLight;

  const _DialBevelPainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Bottom concave shading (simulates CSS inset 0 -10px 24px rgba(0,0,0,0.65))
    final bottomShade = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.transparent,
          Colors.black.withValues(alpha: isLight ? 0.08 : 0.56),
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawOval(rect, bottomShade);

    // Top specular rim arc (simulates CSS inset 0 1px 1px rgba(255,255,255,0.16))
    final arcRect =
        Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6);
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: isLight ? 0.85 : 0.18),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawArc(arcRect, -math.pi * 0.88, math.pi * 0.76, false, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _DialBevelPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}

class _CircleTopRimPainter extends CustomPainter {
  final bool isLight;

  const _CircleTopRimPainter({required this.isLight});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect =
        Rect.fromLTWH(0.8, 0.8, size.width - 1.6, size.height - 1.6);
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withValues(alpha: isLight ? 0.70 : 0.18),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawArc(arcRect, -math.pi * 0.85, math.pi * 0.70, false, rimPaint);
  }

  @override
  bool shouldRepaint(covariant _CircleTopRimPainter oldDelegate) =>
      oldDelegate.isLight != isLight;
}

class _TickRingPainter extends CustomPainter {
  final double activeAngleDeg;
  final Color accentColor;
  final Color unlitTickColor;

  const _TickRingPainter({
    required this.activeAngleDeg,
    required this.accentColor,
    required this.unlitTickColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const totalTicks = 45;
    final center = Offset(size.width / 2, size.height / 2);
    final tickRadius = RotaryDial.outerTickRadiusForSize(size.width);

    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = (tickDeg - 90.0) * math.pi / 180.0;
      final isLit = tickDeg <= activeAngleDeg + 1.5;
      final isMajor = i % 4 == 0;
      final len = isMajor ? 10.0 : 7.0;

      final p1 = Offset(
        center.dx + math.cos(rad) * (tickRadius - len),
        center.dy + math.sin(rad) * (tickRadius - len),
      );
      final p2 = Offset(
        center.dx + math.cos(rad) * tickRadius,
        center.dy + math.sin(rad) * tickRadius,
      );

      final paint = Paint()
        ..color = isLit ? accentColor.withValues(alpha: 0.95) : unlitTickColor
        ..strokeWidth = isMajor ? 2.6 : 1.9
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TickRingPainter oldDelegate) =>
      oldDelegate.activeAngleDeg != activeAngleDeg ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.unlitTickColor != unlitTickColor;
}
