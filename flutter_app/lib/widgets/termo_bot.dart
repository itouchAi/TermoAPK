import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

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

class TermoBotOverlay extends StatefulWidget {
  final bool enabled;
  final bool isSleeping;
  final MascotCharacter character;
  final bool soundsEnabled;
  final LangCode lang;
  final Color accentColor;
  final double bottomOffset;
  final VoidCallback onWake;

  const TermoBotOverlay({
    super.key,
    required this.enabled,
    required this.isSleeping,
    required this.character,
    required this.soundsEnabled,
    required this.lang,
    required this.accentColor,
    required this.bottomOffset,
    required this.onWake,
  });

  @override
  State<TermoBotOverlay> createState() => _TermoBotOverlayState();
}

class _TermoBotOverlayState extends State<TermoBotOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _walkCtrl;
  int _walkCycles = 0;
  bool _napping = false;
  Timer? _bubbleTimer;
  String? _speech;

  @override
  void initState() {
    super.initState();
    _walkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _walkCycles++;
          if (_walkCycles >= 3) {
            if (mounted) setState(() => _napping = true);
          } else {
            _walkCtrl.reverse();
          }
        } else if (status == AnimationStatus.dismissed) {
          _walkCycles++;
          if (_walkCycles >= 3) {
            if (mounted) setState(() => _napping = true);
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
      _walkCycles = 0;
      _walkCtrl.forward();
    } else if ((!widget.enabled || !widget.isSleeping) && (_walkCtrl.isAnimating || _napping)) {
      _walkCtrl.stop();
      _napping = false;
      _walkCycles = 0;
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
    setState(() {
      _napping = false;
      _walkCycles = 0;
      _speech = widget.lang == LangCode.tr
          ? '${meta.name}: Sistem dengede!'
          : '${meta.name}: System balanced!';
    });
    _bubbleTimer?.cancel();
    _bubbleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _speech = null);
    });
    widget.onWake();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !widget.isSleeping) return const SizedBox.shrink();

    final meta = MascotMeta.of(widget.character);
    final width = MediaQuery.of(context).size.width;
    final maxWalk = math.max(80.0, width - 130.0);

    return AnimatedBuilder(
      animation: _walkCtrl,
      builder: (context, child) {
        final x = 18.0 + (_napping ? 0.15 : _walkCtrl.value) * (maxWalk * 0.45);
        final bob = _napping ? 0.0 : math.sin(_walkCtrl.value * math.pi * 10).abs() * 3.0;
        return Positioned(
          left: x,
          bottom: widget.bottomOffset + bob,
          child: GestureDetector(
            onTap: _handleTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_speech != null || _napping)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141620).withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: meta.color.withValues(alpha: 0.55)),
                    ),
                    child: Text(
                      _speech ?? 'zZz · ${meta.name}',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF151822).withValues(alpha: 0.92),
                    border: Border.all(color: meta.color.withValues(alpha: 0.75), width: 1.6),
                    boxShadow: [
                      BoxShadow(color: meta.color.withValues(alpha: 0.38), blurRadius: 14),
                    ],
                  ),
                  child: Icon(
                    _napping ? Icons.bedtime_outlined : meta.icon,
                    size: 21,
                    color: meta.color,
                  ),
                ),
              ],
            ),
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
  final double roomTemp;
  final double targetTemp;
  final Color accentColor;
  final LangCode lang;
  final VoidCallback onExit;

  const FullscreenScreensaverOverlay({
    super.key,
    required this.character,
    required this.backdrop,
    required this.blurBackground,
    required this.soundsEnabled,
    required this.roomTemp,
    required this.targetTemp,
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

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onExit,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedBuilder(
              animation: _anim,
              builder: (context, _) => CustomPaint(
                painter: _ScreensaverBackdropPainter(
                  backdrop: widget.backdrop,
                  progress: _anim.value,
                  accentColor: widget.accentColor,
                ),
              ),
            ),
            if (widget.blurBackground)
              BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(color: Colors.black.withValues(alpha: 0.25)),
              ),
            Center(
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) {
                  final dx = math.sin(_anim.value * math.pi * 2) * 32.0;
                  final dy = math.cos(_anim.value * math.pi * 4).abs() * -8.0;
                  return Transform.translate(
                    offset: Offset(dx, dy),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF151822).withValues(alpha: 0.90),
                            border: Border.all(color: meta.color, width: 2.2),
                            boxShadow: [
                              BoxShadow(color: meta.color.withValues(alpha: 0.45), blurRadius: 28),
                            ],
                          ),
                          child: Icon(meta.icon, size: 46, color: meta.color),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '${meta.name} · ${tr ? meta.roleTr : meta.roleEn}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${tr ? 'Oda' : 'Room'} ${widget.roomTemp.toStringAsFixed(1)}°C  →  ${tr ? 'Hedef' : 'Target'} ${widget.targetTemp.toStringAsFixed(1)}°C',
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.78)),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          widget.soundsEnabled
                              ? (tr ? 'Maskot sesleri açık · Dokunup çıkın' : 'Mascot sounds on · Tap to exit')
                              : (tr ? 'Sessiz mod · Dokunup çıkın' : 'Silent mode · Tap to exit'),
                          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.48)),
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
    );
  }
}

class _ScreensaverBackdropPainter extends CustomPainter {
  final ScreensaverBackdrop backdrop;
  final double progress;
  final Color accentColor;

  const _ScreensaverBackdropPainter({
    required this.backdrop,
    required this.progress,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (backdrop) {
      case ScreensaverBackdrop.oledBlack:
        canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
        break;
      case ScreensaverBackdrop.termoLab:
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF040B14));
        final gridPaint = Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: 0.12)
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
              colors: const [Color(0xFF7C2D12), Color(0xFF2B0F08), Color(0xFF090404)],
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
              colors: const [Color(0xFF311B6B), Color(0xFF130B2E), Color(0xFF040308)],
            ).createShader(Offset.zero & size),
        );
        break;
      case ScreensaverBackdrop.custom:
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              colors: [accentColor.withValues(alpha: 0.35), const Color(0xFF06070B)],
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
      oldDelegate.accentColor != accentColor;
}
