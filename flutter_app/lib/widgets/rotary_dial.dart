import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

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
  });

  @override
  State<RotaryDial> createState() => _RotaryDialState();
}

class _RotaryDialState extends State<RotaryDial> {
  void _updateFromLocalOffset(Offset localPosition) {
    final center = Offset(widget.sizePx / 2, widget.sizePx / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final next = ThermostatMath.pointerOffsetToTemp(dx, dy);
    if ((next - widget.targetTemp).abs() >= 0.05) {
      widget.onChangeTarget(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAngleDeg = ThermostatMath.tempToAngleDeg(widget.targetTemp);
    final innerDiameter = widget.sizePx * 0.76;
    final knobRadius = innerDiameter * 0.39;
    final isLight = widget.palette.isLight;
    final isTactile = widget.palette.isTactileDeck;

    final dialColors = isLight
        ? const [Color(0xFFFFFFFF), Color(0xFFF1F5F9), Color(0xFFE2E8F0)]
        : isTactile
            ? const [Color(0xFF2D2724), Color(0xFF1C1816), Color(0xFF100E0C)]
            : const [Color(0xFF23252D), Color(0xFF17181F), Color(0xFF0F1015)];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanDown: (details) => _updateFromLocalOffset(details.localPosition),
          onPanUpdate: (details) => _updateFromLocalOffset(details.localPosition),
          child: SizedBox(
            width: widget.sizePx,
            height: widget.sizePx,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ambient radial glow
                Container(
                  width: widget.sizePx * 0.88,
                  height: widget.sizePx * 0.88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        widget.accentColor.withValues(alpha: isLight ? 0.24 : 0.20),
                        widget.accentColor.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),

                // 45 Segmented radial perimeter ticks
                CustomPaint(
                  size: Size(widget.sizePx, widget.sizePx),
                  painter: _TickRingPainter(
                    activeAngleDeg: activeAngleDeg,
                    accentColor: widget.accentColor,
                    unlitTickColor: isLight
                        ? const Color(0xFF0F172A).withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.14),
                  ),
                ),

                // Inner dial face
                Container(
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
                      color: isTactile
                          ? const Color(0xFFD97706).withValues(alpha: 0.35)
                          : widget.palette.cardBorder,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isLight ? 0.18 : 0.72),
                        blurRadius: isLight ? 22 : 30,
                        offset: const Offset(0, 12),
                      ),
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: 0.16),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Rotating glowing indicator pill
                      Transform.rotate(
                        angle: activeAngleDeg * math.pi / 180.0,
                        child: Transform.translate(
                          offset: Offset(0, -knobRadius),
                          child: Container(
                            width: 6,
                            height: 15,
                            decoration: BoxDecoration(
                              color: widget.accentColor,
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.accentColor,
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.lang == LangCode.tr ? 'HEDEF TERMOSTAT' : 'TARGET THERMOSTAT',
                            style: TextStyle(
                              fontSize: widget.compact ? 9 : 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                              color: widget.palette.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.targetTemp.toStringAsFixed(1)}°',
                            style: TextStyle(
                              fontSize: widget.compact ? 30 : 42,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                              color: widget.palette.textPrimary,
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
                              color: widget.accentColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.local_fire_department_rounded,
                                size: 12,
                                color: widget.boiler.isHeating
                                    ? widget.accentColor
                                    : widget.palette.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.lang == LangCode.tr
                                    ? widget.boiler.statusTextTr
                                    : widget.boiler.statusTextEn,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: widget.palette.textSecondary,
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
              ],
            ),
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
                ThermostatMath.snapTemperature(widget.targetTemp - ThermostatMath.tempStep),
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
                ThermostatMath.snapTemperature(widget.targetTemp + ThermostatMath.tempStep),
              ),
            ),
          ],
        ),
      ],
    );
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
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: Material(
        color: palette.cardBg,
        shape: CircleBorder(
          side: BorderSide(color: palette.cardBorder),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: palette.textPrimary, size: 18),
          ),
        ),
      ),
    );
  }
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
    final tickRadius = size.width * 0.455;

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
