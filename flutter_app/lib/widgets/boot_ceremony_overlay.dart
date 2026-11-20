import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';

class BootCeremonyOverlay extends StatefulWidget {
  final BootCeremonyStyle style;
  final int durationMs;
  final bool soundChimeEnabled;
  final bool hapticEnabled;
  final int hapticStrength;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final String locationName;
  final Color accentColor;
  final LangCode lang;
  final VoidCallback onComplete;

  const BootCeremonyOverlay({
    super.key,
    required this.style,
    required this.durationMs,
    required this.soundChimeEnabled,
    required this.hapticEnabled,
    required this.hapticStrength,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.locationName,
    required this.accentColor,
    required this.lang,
    required this.onComplete,
  });

  @override
  State<BootCeremonyOverlay> createState() => _BootCeremonyOverlayState();
}

class _BootCeremonyOverlayState extends State<BootCeremonyOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _completed = false;
  bool _stage2HapticFired = false;
  bool _stage3ChimeFired = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.durationMs.clamp(900, 3500);
    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: ms),
    )
      ..addListener(() {
        final v = _ctrl.value;
        if (!_stage2HapticFired && v >= 0.35) {
          _stage2HapticFired = true;
          if (widget.hapticEnabled) {
            HardwareService.vibrateMs(
              35,
              amplitude: HardwareService.scaledAmplitude(120, widget.hapticStrength),
            );
          }
        }
        if (!_stage3ChimeFired && v >= 0.78) {
          _stage3ChimeFired = true;
          if (widget.soundChimeEnabled) {
            AmbientAudioService.playNotificationChime();
          }
          if (widget.hapticEnabled) {
            HardwareService.vibrateMs(
              55,
              amplitude: HardwareService.scaledAmplitude(185, widget.hapticStrength),
            );
          }
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_completed) {
          _completed = true;
          widget.onComplete();
        }
      });

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _skip() {
    if (_completed) return;
    _completed = true;
    _ctrl.stop();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.lang == LangCode.tr;

    return SizedBox.expand(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final t = _ctrl.value.clamp(0.0, 1.0);
          final fadeOut = t > 0.88 ? (1.0 - ((t - 0.88) / 0.12)).clamp(0.0, 1.0) : 1.0;
          final sweepProgress = ((t - 0.10) / 0.68).clamp(0.0, 1.0);
          final easedSweep = Curves.easeOutCubic.transform(sweepProgress);
          final displayTemp = ThermostatMath.lerp(
            ThermostatMath.minTemp,
            widget.targetTemp,
            easedSweep,
          );
          final percent = (t * 100).round().clamp(0, 100);

          final String statusLabel;
          if (t < 0.35) {
            statusLabel = tr ? 'OpenTherm v4.2 & NTC sensörleri doğrulanıyor...' : 'Verifying OpenTherm v4.2 & NTC sensors...';
          } else if (t < 0.75) {
            statusLabel = tr ? 'Termostat kadranı ve brülör eşiği kalibre ediliyor...' : 'Calibrating rotary dial & burner curve...';
          } else {
            statusLabel = tr ? 'Sistem hazır · ${widget.locationName}' : 'System ready · ${widget.locationName}';
          }

          return Opacity(
            opacity: fadeOut,
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.1),
                  radius: 1.05,
                  colors: [
                    widget.accentColor.withValues(alpha: widget.style == BootCeremonyStyle.minimalRadar ? 0.12 : 0.22),
                    const Color(0xFF040406),
                  ],
                ),
              ),
              child: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 196,
                              height: 196,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  CustomPaint(
                                    size: const Size(196, 196),
                                    painter: _BootDialPainter(
                                      progress: t,
                                      sweepProgress: easedSweep,
                                      style: widget.style,
                                      accentColor: widget.accentColor,
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        t >= 0.78
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.local_fire_department_outlined,
                                        size: 24,
                                        color: t >= 0.78 ? const Color(0xFF10B981) : widget.accentColor,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${displayTemp.toStringAsFixed(1)}°',
                                        style: const TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          height: 1.0,
                                          fontFeatures: [FontFeature.tabularFigures()],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '%$percent',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: widget.accentColor,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Termostat Flow',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: -0.3,
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              statusLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.70),
                                decoration: TextDecoration.none,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _DiagnosticChip(
                                  label: '${tr ? 'Oda' : 'Room'}: ${widget.roomTemp.toStringAsFixed(1)}°C',
                                  active: t >= 0.25,
                                  color: const Color(0xFF38BDF8),
                                ),
                                _DiagnosticChip(
                                  label: '${tr ? 'Basınç' : 'Press'}: ${widget.boiler.waterPressureBar.toStringAsFixed(1)} Bar',
                                  active: t >= 0.45,
                                  color: const Color(0xFF10B981),
                                ),
                                _DiagnosticChip(
                                  label: widget.boiler.modulationActive ? 'OpenTherm OK' : 'Standby OK',
                                  active: t >= 0.68,
                                  color: widget.accentColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: GestureDetector(
                        onTap: _skip,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Text(
                            tr ? 'Atla ›' : 'Skip ›',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.85),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DiagnosticChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _DiagnosticChip({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.45),
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _BootDialPainter extends CustomPainter {
  final double progress;
  final double sweepProgress;
  final BootCeremonyStyle style;
  final Color accentColor;

  const _BootDialPainter({
    required this.progress,
    required this.sweepProgress,
    required this.style,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.44;

    if (style == BootCeremonyStyle.thermalPulse) {
      for (int ring = 0; ring < 2; ring++) {
        final wave = (progress * 2.2 + ring * 0.5) % 1.0;
        final r = radius * (0.72 + wave * 0.42);
        canvas.drawCircle(
          center,
          r,
          Paint()
            ..color = accentColor.withValues(alpha: (1.0 - wave) * 0.24)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }
    } else if (style == BootCeremonyStyle.minimalRadar) {
      final radarAngle = progress * math.pi * 4.0 - math.pi / 2;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.84),
        radarAngle,
        math.pi * 0.65,
        false,
        Paint()
          ..color = accentColor.withValues(alpha: 0.60)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
    }

    const totalTicks = 45;
    final activeTicks = (sweepProgress * totalTicks).round();
    for (int i = 0; i < totalTicks; i++) {
      final tickDeg = -135.0 + (i / (totalTicks - 1)) * 270.0;
      final rad = (tickDeg - 90.0) * math.pi / 180.0;
      final isLit = i <= activeTicks;
      final isMajor = i % 4 == 0;
      final len = isMajor ? 11.0 : 7.0;

      final p1 = Offset(
        center.dx + math.cos(rad) * (radius - len),
        center.dy + math.sin(rad) * (radius - len),
      );
      final p2 = Offset(
        center.dx + math.cos(rad) * radius,
        center.dy + math.sin(rad) * radius,
      );

      canvas.drawLine(
        p1,
        p2,
        Paint()
          ..color = isLit
              ? accentColor.withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.14)
          ..strokeWidth = isMajor ? 2.5 : 1.7
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(
      center,
      radius * 0.72,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _BootDialPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.sweepProgress != sweepProgress ||
      oldDelegate.style != style ||
      oldDelegate.accentColor != accentColor;
}
