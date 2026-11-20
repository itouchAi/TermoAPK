import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';

class MascotMeta {
  final String name;
  final String roleTr;
  final String roleEn;
  final IconData icon;
  final Color color;

  const MascotMeta({
    required this.name,
    required this.roleTr,
    required this.roleEn,
    required this.icon,
    required this.color,
  });

  static MascotMeta of(MascotCharacter c) {
    switch (c) {
      case MascotCharacter.termoBot:
        return const MascotMeta(
          name: 'TermoBot',
          roleTr: 'Retro Robot',
          roleEn: 'Retro Robot',
          icon: Icons.smart_toy_rounded,
          color: Color(0xFF38BDF8),
        );
      case MascotCharacter.mirnav:
        return const MascotMeta(
          name: 'Mırnav',
          roleTr: 'Petek Kedisi',
          roleEn: 'Radiator Cat',
          icon: Icons.pets_rounded,
          color: Color(0xFFF59E0B),
        );
      case MascotCharacter.puki:
        return const MascotMeta(
          name: 'Puki',
          roleTr: 'Tavşan',
          roleEn: 'Bunny',
          icon: Icons.cruelty_free_rounded,
          color: Color(0xFFF472B6),
        );
      case MascotCharacter.mert:
        return const MascotMeta(
          name: 'Mert',
          roleTr: 'Erkek Asistan',
          roleEn: 'Male Assistant',
          icon: Icons.face_6_rounded,
          color: Color(0xFF60A5FA),
        );
      case MascotCharacter.ela:
        return const MascotMeta(
          name: 'Ela',
          roleTr: 'Kadın Asistan',
          roleEn: 'Female Assistant',
          icon: Icons.face_3_rounded,
          color: Color(0xFFA78BFA),
        );
    }
  }
}

/// Custom vector-illustrated mascot avatar supporting awake, happy, and sleeping eyes.
class MascotAvatar extends StatelessWidget {
  final MascotCharacter character;
  final double size;
  final bool sleeping;
  final bool happy;
  final double phase;

  const MascotAvatar({
    super.key,
    required this.character,
    this.size = 44,
    this.sleeping = false,
    this.happy = false,
    this.phase = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(character);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            meta.color.withValues(alpha: 0.24),
            const Color(0xFF131622).withValues(alpha: 0.94),
          ],
        ),
        border: Border.all(color: meta.color.withValues(alpha: sleeping ? 0.45 : 0.85), width: size > 60 ? 2.2 : 1.5),
        boxShadow: [
          BoxShadow(
            color: meta.color.withValues(alpha: sleeping ? 0.18 : 0.42),
            blurRadius: size * 0.34,
          ),
        ],
      ),
      child: CustomPaint(
        painter: _MascotAvatarPainter(
          character: character,
          color: meta.color,
          sleeping: sleeping,
          happy: happy,
          phase: phase,
        ),
      ),
    );
  }
}

class _MascotAvatarPainter extends CustomPainter {
  final MascotCharacter character;
  final Color color;
  final bool sleeping;
  final bool happy;
  final double phase;

  const _MascotAvatarPainter({
    required this.character,
    required this.color,
    required this.sleeping,
    required this.happy,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.30;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.055).clamp(1.4, 3.2)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    void drawEyes(double eyeY, double spread) {
      final eyePaint = Paint()
        ..color = Colors.white
        ..style = sleeping ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = (size.width * 0.045).clamp(1.2, 2.5)
        ..strokeCap = StrokeCap.round;

      if (sleeping) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx - spread, eyeY), width: r * 0.34, height: r * 0.22),
          0,
          math.pi,
          false,
          eyePaint,
        );
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx + spread, eyeY), width: r * 0.34, height: r * 0.22),
          0,
          math.pi,
          false,
          eyePaint,
        );
      } else if (happy) {
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx - spread, eyeY + r * 0.05), width: r * 0.34, height: r * 0.28),
          math.pi,
          math.pi,
          false,
          eyePaint..style = PaintingStyle.stroke,
        );
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx + spread, eyeY + r * 0.05), width: r * 0.34, height: r * 0.28),
          math.pi,
          math.pi,
          false,
          eyePaint..style = PaintingStyle.stroke,
        );
      } else {
        final er = (r * 0.14).clamp(1.6, 5.2);
        canvas.drawCircle(Offset(cx - spread, eyeY), er, eyePaint);
        canvas.drawCircle(Offset(cx + spread, eyeY), er, eyePaint);
      }
    }

    switch (character) {
      case MascotCharacter.termoBot:
        // Antenna with subtle beacon
        canvas.drawLine(Offset(cx, cy - r * 0.72), Offset(cx, cy - r * 1.15), stroke);
        canvas.drawCircle(
          Offset(cx, cy - r * 1.2),
          r * 0.14,
          Paint()..color = sleeping ? color.withValues(alpha: 0.4) : const Color(0xFFFBBF24),
        );
        // Visor head
        final headRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, cy + r * 0.08), width: r * 1.65, height: r * 1.32),
          Radius.circular(r * 0.42),
        );
        canvas.drawRRect(headRect, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawRRect(headRect, stroke);
        drawEyes(cy + r * 0.05, r * 0.36);
        break;

      case MascotCharacter.mirnav:
        // Pointed cat ears
        final leftEar = Path()
          ..moveTo(cx - r * 0.65, cy - r * 0.32)
          ..lineTo(cx - r * 0.78, cy - r * 1.05)
          ..lineTo(cx - r * 0.18, cy - r * 0.62)
          ..close();
        final rightEar = Path()
          ..moveTo(cx + r * 0.65, cy - r * 0.32)
          ..lineTo(cx + r * 0.78, cy - r * 1.05)
          ..lineTo(cx + r * 0.18, cy - r * 0.62)
          ..close();
        canvas.drawPath(leftEar, fill);
        canvas.drawPath(rightEar, fill);
        canvas.drawCircle(Offset(cx, cy + r * 0.08), r * 0.74, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawCircle(Offset(cx, cy + r * 0.08), r * 0.74, stroke);
        drawEyes(cy - r * 0.02, r * 0.30);
        // Whiskers
        final wPaint = stroke..strokeWidth = (stroke.strokeWidth * 0.7);
        canvas.drawLine(Offset(cx - r * 0.45, cy + r * 0.24), Offset(cx - r * 0.96, cy + r * 0.18), wPaint);
        canvas.drawLine(Offset(cx + r * 0.45, cy + r * 0.24), Offset(cx + r * 0.96, cy + r * 0.18), wPaint);
        break;

      case MascotCharacter.puki:
        // Tall floppy bunny ears
        final earWobble = math.sin(phase * math.pi * 2) * (sleeping ? 0.0 : r * 0.08);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx - r * 0.32 + earWobble, cy - r * 0.72), width: r * 0.38, height: r * 0.95),
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + r * 0.32 - earWobble, cy - r * 0.72), width: r * 0.38, height: r * 0.95),
          stroke,
        );
        canvas.drawCircle(Offset(cx, cy + r * 0.18), r * 0.68, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawCircle(Offset(cx, cy + r * 0.18), r * 0.68, stroke);
        drawEyes(cy + r * 0.10, r * 0.26);
        canvas.drawCircle(Offset(cx, cy + r * 0.34), r * 0.10, Paint()..color = Colors.white);
        break;

      case MascotCharacter.mert:
        // Friendly male assistant face & subtle headset arc
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy), width: r * 1.66, height: r * 1.66),
          math.pi,
          math.pi,
          false,
          stroke,
        );
        canvas.drawCircle(Offset(cx, cy + r * 0.10), r * 0.72, Paint()..color = color.withValues(alpha: 0.20));
        canvas.drawCircle(Offset(cx, cy + r * 0.10), r * 0.72, stroke);
        drawEyes(cy + r * 0.02, r * 0.28);
        // Smile
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy + r * 0.28), width: r * 0.56, height: r * 0.34),
          0.15,
          math.pi - 0.3,
          false,
          stroke..strokeWidth = stroke.strokeWidth * 0.85,
        );
        break;

      case MascotCharacter.ela:
        // Female assistant silhouette with warm glowing halo/headband
        final hair = Path()
          ..addArc(Rect.fromCenter(center: Offset(cx, cy + r * 0.05), width: r * 1.66, height: r * 1.66), math.pi * 0.85, math.pi * 1.3);
        canvas.drawPath(hair, stroke);
        canvas.drawCircle(Offset(cx, cy + r * 0.12), r * 0.68, Paint()..color = color.withValues(alpha: 0.22));
        canvas.drawCircle(Offset(cx, cy + r * 0.12), r * 0.68, stroke);
        drawEyes(cy + r * 0.06, r * 0.26);
        canvas.drawArc(
          Rect.fromCenter(center: Offset(cx, cy + r * 0.28), width: r * 0.48, height: r * 0.30),
          0.2,
          math.pi - 0.4,
          false,
          stroke..strokeWidth = stroke.strokeWidth * 0.85,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _MascotAvatarPainter oldDelegate) =>
      oldDelegate.character != character ||
      oldDelegate.color != color ||
      oldDelegate.sleeping != sleeping ||
      oldDelegate.happy != happy ||
      oldDelegate.phase != phase;
}

class TermoBotOverlay extends StatefulWidget {
  final bool enabled;
  final bool isSleeping;
  final MascotCharacter character;
  final bool soundsEnabled;
  final bool hapticEnabled;
  final int hapticStrength;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final LangCode lang;
  final Color accentColor;
  final double bottomOffset;
  final VoidCallback onWake;
  final VoidCallback? onOpenScreensaver;

  const TermoBotOverlay({
    super.key,
    required this.enabled,
    required this.isSleeping,
    required this.character,
    required this.soundsEnabled,
    this.hapticEnabled = true,
    this.hapticStrength = 80,
    this.roomTemp = 21.8,
    this.targetTemp = 22.5,
    required this.boiler,
    required this.lang,
    required this.accentColor,
    required this.bottomOffset,
    required this.onWake,
    this.onOpenScreensaver,
  });

  @override
  State<TermoBotOverlay> createState() => _TermoBotOverlayState();
}

class _TermoBotOverlayState extends State<TermoBotOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _walkCtrl;
  int _walkHalfLegs = 0;
  bool _napping = false;
  bool _happy = false;
  Timer? _bubbleTimer;
  String? _speech;

  @override
  void initState() {
    super.initState();
    _walkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..addStatusListener((status) {
        // 3 full round-trips = 6 half-legs (forward+reverse x 3)
        if (status == AnimationStatus.completed) {
          _walkHalfLegs++;
          if (_walkHalfLegs >= 6) {
            if (mounted) {
              setState(() => _napping = true);
              if (widget.soundsEnabled) {
                AmbientAudioService.playMascotSound(widget.character, sleepy: true);
              }
            }
          } else {
            _walkCtrl.reverse();
          }
        } else if (status == AnimationStatus.dismissed) {
          _walkHalfLegs++;
          if (_walkHalfLegs >= 6) {
            if (mounted) {
              setState(() => _napping = true);
              if (widget.soundsEnabled) {
                AmbientAudioService.playMascotSound(widget.character, sleepy: true);
              }
            }
          } else {
            _walkCtrl.forward();
          }
        }
      });
  }

  @override
  void didUpdateWidget(covariant TermoBotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.isSleeping && !_walkCtrl.isAnimating && !_napping) {
      _walkHalfLegs = 0;
      _happy = false;
      _walkCtrl.forward();
    } else if ((!widget.enabled || !widget.isSleeping) && (_walkCtrl.isAnimating || _napping)) {
      _walkCtrl.stop();
      _napping = false;
      _happy = false;
      _walkHalfLegs = 0;
    }
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _walkCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        45,
        amplitude: HardwareService.scaledAmplitude(145, widget.hapticStrength),
      );
    }
    if (widget.soundsEnabled) {
      AmbientAudioService.playMascotSound(widget.character);
    }
    final statusLine = widget.boiler.isHeating
        ? (tr
            ? 'Kombi %${widget.boiler.flamePercent} devrede (${widget.targetTemp.toStringAsFixed(1)}°)'
            : 'Boiler ${widget.boiler.flamePercent}% active (${widget.targetTemp.toStringAsFixed(1)}°)')
        : (tr
            ? 'Oda ${widget.roomTemp.toStringAsFixed(1)}°C dengede!'
            : 'Room ${widget.roomTemp.toStringAsFixed(1)}°C steady!');

    setState(() {
      _napping = false;
      _happy = true;
      _walkHalfLegs = 0;
      _speech = '${meta.name}: $statusLine';
    });
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _speech = null;
          _happy = false;
        });
      }
    });
    widget.onWake();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || (!widget.isSleeping && _speech == null)) {
      return const SizedBox.shrink();
    }

    final meta = MascotMeta.of(widget.character);
    final width = MediaQuery.of(context).size.width;
    final maxWalk = math.max(96.0, width - 160.0);

    return AnimatedBuilder(
      animation: _walkCtrl,
      builder: (context, child) {
        final x = 18.0 + (_napping ? 0.15 : _walkCtrl.value) * (maxWalk * 0.55);
        final bob = _napping ? 0.0 : math.sin(_walkCtrl.value * math.pi * 12).abs() * 3.5;
        return Positioned(
          left: x,
          bottom: widget.bottomOffset + bob,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _handleTap,
                onLongPress: widget.onOpenScreensaver,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_speech != null || _napping)
                      Container(
                        margin: const EdgeInsets.only(bottom: 5),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141620).withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: meta.color.withValues(alpha: 0.58)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 10),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _speech ?? 'zZz · ${meta.name}',
                              style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            if (widget.onOpenScreensaver != null && _napping) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: widget.onOpenScreensaver,
                                child: Icon(Icons.fullscreen_rounded, size: 15, color: meta.color),
                              ),
                            ],
                          ],
                        ),
                      ),
                    MascotAvatar(
                      character: widget.character,
                      size: 46,
                      sleeping: _napping,
                      happy: _happy,
                      phase: _walkCtrl.value,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class FullscreenScreensaverOverlay extends StatefulWidget {
  final MascotCharacter character;
  final ScreensaverBackdrop backdrop;
  final bool blurBackground;
  final bool soundsEnabled;
  final bool hapticEnabled;
  final int hapticStrength;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry? boiler;
  final String locationName;
  final Color accentColor;
  final LangCode lang;
  final VoidCallback onExit;

  const FullscreenScreensaverOverlay({
    super.key,
    required this.character,
    required this.backdrop,
    required this.blurBackground,
    required this.soundsEnabled,
    this.hapticEnabled = true,
    this.hapticStrength = 80,
    required this.roomTemp,
    required this.targetTemp,
    this.boiler,
    this.locationName = '',
    required this.accentColor,
    required this.lang,
    required this.onExit,
  });

  @override
  State<FullscreenScreensaverOverlay> createState() => _FullscreenScreensaverOverlayState();
}

class _FullscreenScreensaverOverlayState extends State<FullscreenScreensaverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late Timer _clockTimer;
  DateTime _now = DateTime.now();
  bool _happy = false;
  String? _reactionText;
  Timer? _reactionTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    if (widget.soundsEnabled) {
      AmbientAudioService.playMascotSound(widget.character);
    }
  }

  @override
  void dispose() {
    _reactionTimer?.cancel();
    _clockTimer.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _petMascot() {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        50,
        amplitude: HardwareService.scaledAmplitude(165, widget.hapticStrength),
      );
    }
    if (widget.soundsEnabled) {
      AmbientAudioService.playMascotSound(widget.character);
    }
    final isHeating = widget.boiler?.isHeating ?? (widget.targetTemp > widget.roomTemp + 0.1);
    setState(() {
      _happy = true;
      _reactionText = isHeating
          ? (tr ? '${meta.name}: Ev ısıtılıyor!' : '${meta.name}: Warming up!')
          : (tr ? '${meta.name}: Konfor sıcaklığı ideal!' : '${meta.name}: Comfort steady!');
    });
    _reactionTimer?.cancel();
    _reactionTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _happy = false;
          _reactionText = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    final activeBoiler = widget.boiler ?? ThermostatMath.computeBoilerTelemetry(widget.roomTemp, widget.targetTemp);

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onExit,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) Genuine BackdropFilter directly over underlying thermostat UI when blurBackground is enabled
              if (widget.blurBackground)
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: const SizedBox.expand(),
                ),
              // 2) Screensaver themed atmosphere (semi-translucent when blurBackground is active so blur reads cleanly)
              AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(
                  painter: _ScreensaverBackdropPainter(
                    backdrop: widget.backdrop,
                    progress: _anim.value,
                    accentColor: widget.accentColor,
                    translucentForBlur: widget.blurBackground,
                  ),
                ),
              ),
              // 3) Foreground clock, animated mascot avatar (tappable to pet), and live telemetry
              Center(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final dx = math.sin(_anim.value * math.pi * 2) * 34.0;
                    final dy = math.cos(_anim.value * math.pi * 4).abs() * -9.0;
                    // Subtle OLED pixel-shift offset
                    final oledShiftX = ((_now.minute % 3) - 1) * 4.0;
                    final oledShiftY = ((_now.minute % 5) - 2) * 2.0;

                    return Transform.translate(
                      offset: Offset(dx + oledShiftX, dy + oledShiftY),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$hh:$mm',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2.0,
                              color: Colors.white.withValues(alpha: 0.90),
                              fontFeatures: const [FontFeature.tabularFigures()],
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _petMascot,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_reactionText != null)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF141620).withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: meta.color.withValues(alpha: 0.65)),
                                    ),
                                    child: Text(
                                      _reactionText!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        decoration: TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                MascotAvatar(
                                  character: widget.character,
                                  size: 96,
                                  happy: _happy,
                                  phase: _anim.value,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${meta.name} · ${tr ? meta.roleTr : meta.roleEn}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                            ),
                            child: Text(
                              '${tr ? 'Oda' : 'Room'} ${widget.roomTemp.toStringAsFixed(1)}°C  →  ${tr ? 'Hedef' : 'Target'} ${widget.targetTemp.toStringAsFixed(1)}°C  ·  ${tr ? activeBoiler.statusTextTr : activeBoiler.statusTextEn}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white.withValues(alpha: 0.84),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            widget.soundsEnabled
                                ? (tr ? 'Maskota dokunun · Çıkmak için boşluğa dokunun' : 'Tap mascot to interact · Tap outside to exit')
                                : (tr ? 'Sessiz mod · Çıkmak için dokunun' : 'Silent mode · Tap to exit'),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.50),
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScreensaverBackdropPainter extends CustomPainter {
  final ScreensaverBackdrop backdrop;
  final double progress;
  final Color accentColor;
  final bool translucentForBlur;

  const _ScreensaverBackdropPainter({
    required this.backdrop,
    required this.progress,
    required this.accentColor,
    required this.translucentForBlur,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final veilAlpha = translucentForBlur ? 0.68 : 1.0;

    switch (backdrop) {
      case ScreensaverBackdrop.oledBlack:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = Colors.black.withValues(alpha: translucentForBlur ? 0.72 : 1.0),
        );
        break;
      case ScreensaverBackdrop.termoLab:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFF040B14).withValues(alpha: veilAlpha),
        );
        final gridPaint = Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.14)
          ..strokeWidth = 1.0;
        const step = 36.0;
        final shift = (progress * step) % step;
        for (double x = shift; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
        }
        for (double y = shift; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
        }
        break;
      case ScreensaverBackdrop.warmHearth:
        final pulse = 0.85 + 0.15 * math.sin(progress * math.pi * 2);
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0, 0.55),
              radius: 1.05 * pulse,
              colors: [
                const Color(0xFF7C2D12).withValues(alpha: veilAlpha),
                const Color(0xFF2B0F08).withValues(alpha: veilAlpha),
                const Color(0xFF090404).withValues(alpha: veilAlpha),
              ],
            ).createShader(Offset.zero & size),
        );
        break;
      case ScreensaverBackdrop.nightNebula:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              center: Alignment(math.cos(progress * math.pi * 2) * 0.3, -0.2),
              radius: 1.1,
              colors: [
                const Color(0xFF311B6B).withValues(alpha: veilAlpha),
                const Color(0xFF130B2E).withValues(alpha: veilAlpha),
                const Color(0xFF040308).withValues(alpha: veilAlpha),
              ],
            ).createShader(Offset.zero & size),
        );
        break;
      case ScreensaverBackdrop.custom:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              colors: [
                accentColor.withValues(alpha: translucentForBlur ? 0.32 : 0.40),
                const Color(0xFF06070B).withValues(alpha: veilAlpha),
              ],
              radius: 0.95,
            ).createShader(Offset.zero & size),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ScreensaverBackdropPainter oldDelegate) =>
      oldDelegate.backdrop != backdrop ||
      oldDelegate.progress != progress ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.translucentForBlur != translucentForBlur;
}
