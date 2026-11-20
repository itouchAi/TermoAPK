import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
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
  final String assetPath;

  const MascotMeta({
    required this.name,
    required this.roleTr,
    required this.roleEn,
    required this.icon,
    required this.color,
    required this.assetPath,
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
          assetPath: 'assets/mascots/termo_bot.jpg',
        );
      case MascotCharacter.mirnav:
        return const MascotMeta(
          name: 'Mırnav',
          roleTr: 'Petek Kedisi',
          roleEn: 'Radiator Cat',
          icon: Icons.pets_rounded,
          color: Color(0xFFF59E0B),
          assetPath: 'assets/mascots/mirnav.jpg',
        );
      case MascotCharacter.puki:
        return const MascotMeta(
          name: 'Puki',
          roleTr: 'Tavşan',
          roleEn: 'Bunny',
          icon: Icons.cruelty_free_rounded,
          color: Color(0xFFF472B6),
          assetPath: 'assets/mascots/puki.jpg',
        );
      case MascotCharacter.mert:
        return const MascotMeta(
          name: 'Mert',
          roleTr: 'Erkek Asistan',
          roleEn: 'Male Assistant',
          icon: Icons.face_6_rounded,
          color: Color(0xFF60A5FA),
          assetPath: 'assets/mascots/mert.jpg',
        );
      case MascotCharacter.ela:
        return const MascotMeta(
          name: 'Ela',
          roleTr: 'Kadın Asistan',
          roleEn: 'Female Assistant',
          icon: Icons.face_3_rounded,
          color: Color(0xFFA78BFA),
          assetPath: 'assets/mascots/ela.jpg',
        );
    }
  }
}

/// Decodes and caches base64 custom wallpaper bytes once per URI so animations stay 60 FPS.
class ScreensaverCustomWallpaper extends StatelessWidget {
  final String source;
  final BoxFit fit;

  const ScreensaverCustomWallpaper({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
  });

  static String? _cachedDataUri;
  static Uint8List? _cachedBytes;

  static Uint8List? _decodeDataUri(String src) {
    if (_cachedDataUri == src && _cachedBytes != null) return _cachedBytes;
    final commaIdx = src.indexOf(',');
    if (commaIdx <= 0) return null;
    try {
      final bytes = base64Decode(src.substring(commaIdx + 1));
      _cachedDataUri = src;
      _cachedBytes = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return const SizedBox.shrink();

    if (trimmed.startsWith('data:image/')) {
      final bytes = _decodeDataUri(trimmed);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      }
      return const SizedBox.shrink();
    }

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Image.network(
        trimmed,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    return const SizedBox.shrink();
  }
}

/// High-fidelity Unreal-style 3D Mascot Portrait with real-time animated behavior overlays.
class MascotAvatar extends StatelessWidget {
  final MascotCharacter character;
  final double size;
  final bool sleeping;
  final bool happy;
  final MascotBehavior behavior;
  final double phase;
  final bool showBehaviorOverlay;

  const MascotAvatar({
    super.key,
    required this.character,
    this.size = 48,
    this.sleeping = false,
    this.happy = false,
    this.behavior = MascotBehavior.idle,
    this.phase = 0.0,
    this.showBehaviorOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(character);
    final isSleep = sleeping || behavior == MascotBehavior.deepSleep;
    final breath = 1.0 + math.sin(phase * math.pi * 2) * (isSleep ? 0.015 : 0.032);
    final lean = behavior == MascotBehavior.patrol
        ? math.sin(phase * math.pi * 6) * 0.06
        : (behavior == MascotBehavior.knock ? math.sin(phase * math.pi * 8) * 0.08 : 0.0);
    final knockScale = behavior == MascotBehavior.knock
        ? 1.0 + math.sin(phase * math.pi * 8).abs() * 0.09
        : 1.0;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Ripple rings for knock behavior
          if (showBehaviorOverlay && behavior == MascotBehavior.knock)
            Positioned.fill(
              child: CustomPaint(
                painter: _KnockRipplePainter(
                  color: meta.color,
                  progress: phase,
                ),
              ),
            ),

          // 3D Unreal Portrait Orb
          Transform.rotate(
            angle: lean,
            child: Transform.scale(
              scale: breath * knockScale,
              child: Opacity(
                opacity: isSleep ? 0.52 : 1.0,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: happy
                          ? const Color(0xFFFBBF24)
                          : meta.color.withValues(alpha: isSleep ? 0.40 : 0.85),
                      width: size > 70 ? 2.6 : 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (happy ? const Color(0xFFFBBF24) : meta.color).withValues(alpha: isSleep ? 0.16 : 0.46),
                        blurRadius: size * (happy ? 0.45 : 0.30),
                        spreadRadius: happy ? 2.0 : 0.0,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(
                          meta.assetPath,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => CustomPaint(
                            painter: _MascotFallbackPainter(
                              character: character,
                              color: meta.color,
                              sleeping: isSleep,
                              happy: happy,
                              phase: phase,
                            ),
                          ),
                        ),
                        // Cool nocturnal veil on Deep Sleep
                        if (isSleep)
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  const Color(0xFF0F172A).withValues(alpha: 0.48),
                                  const Color(0xFF1E1B4B).withValues(alpha: 0.38),
                                ],
                              ),
                            ),
                          ),
                        // Subtle top glass rim specular arc for 3D depth
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: isSleep ? 0.08 : 0.22),
                                Colors.transparent,
                                meta.color.withValues(alpha: 0.12),
                              ],
                              stops: const [0.0, 0.42, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Behavior Overlay Props
          if (showBehaviorOverlay && isSleep)
            Positioned(
              top: -size * 0.22 - (phase * 10.0) % 10.0,
              right: -size * 0.10,
              child: Text(
                'z Z',
                style: TextStyle(
                  fontSize: (size * 0.18).clamp(9.0, 18.0),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF7DD3FC).withValues(alpha: 0.92),
                  shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                  decoration: TextDecoration.none,
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.think)
            Positioned(
              top: -size * 0.14,
              right: -size * 0.16,
              child: Transform.translate(
                offset: Offset(0, math.sin(phase * math.pi * 2) * 3.0),
                child: Container(
                  padding: EdgeInsets.all((size * 0.06).clamp(3.0, 6.0)),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF1E1B2E).withValues(alpha: 0.94),
                    border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.8)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFFFBBF24).withValues(alpha: 0.45), blurRadius: 8),
                    ],
                  ),
                  child: Icon(
                    Icons.lightbulb_rounded,
                    size: (size * 0.20).clamp(10.0, 22.0),
                    color: const Color(0xFFFBBF24),
                  ),
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.read)
            Positioned(
              bottom: -size * 0.06,
              right: -size * 0.12,
              child: Transform.translate(
                offset: Offset(0, math.cos(phase * math.pi * 2) * 2.0),
                child: Container(
                  padding: EdgeInsets.all((size * 0.06).clamp(3.0, 6.0)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFF0F172A).withValues(alpha: 0.94),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.8)),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.40), blurRadius: 8),
                    ],
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: (size * 0.19).clamp(10.0, 20.0),
                    color: const Color(0xFF38BDF8),
                  ),
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.knock)
            Positioned(
              bottom: -size * 0.06,
              left: -size * 0.12,
              child: Container(
                padding: EdgeInsets.all((size * 0.055).clamp(3.0, 6.0)),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF18181B).withValues(alpha: 0.94),
                  border: Border.all(color: meta.color.withValues(alpha: 0.85)),
                ),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: (size * 0.18).clamp(10.0, 19.0),
                  color: meta.color,
                ),
              ),
            ),

          if (showBehaviorOverlay && happy)
            Positioned(
              top: -size * 0.10,
              left: -size * 0.08,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: (size * 0.22).clamp(11.0, 22.0),
                color: const Color(0xFFFBBF24),
              ),
            ),
        ],
      ),
    );
  }
}

class _KnockRipplePainter extends CustomPainter {
  final Color color;
  final double progress;

  const _KnockRipplePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 2; i++) {
      final t = (progress * 2.0 + i * 0.5) % 1.0;
      final radius = (size.width * 0.48) + t * (size.width * 0.34);
      final paint = Paint()
        ..color = color.withValues(alpha: (1.0 - t) * 0.52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _KnockRipplePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _MascotFallbackPainter extends CustomPainter {
  final MascotCharacter character;
  final Color color;
  final bool sleeping;
  final bool happy;
  final double phase;

  const _MascotFallbackPainter({
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
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF10131D));
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.055).clamp(1.4, 3.2)
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(cx, cy), r * 0.85, stroke);
    final eyePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - r * 0.3, cy - r * 0.05), r * 0.12, eyePaint);
    canvas.drawCircle(Offset(cx + r * 0.3, cy - r * 0.05), r * 0.12, eyePaint);
  }

  @override
  bool shouldRepaint(covariant _MascotFallbackPainter oldDelegate) =>
      oldDelegate.character != character ||
      oldDelegate.color != color ||
      oldDelegate.sleeping != sleeping ||
      oldDelegate.happy != happy ||
      oldDelegate.phase != phase;
}

/// Interactive preview stage in Settings for testing all 6 mascot behaviors and custom wallpapers.
class MascotBehaviorStage extends StatefulWidget {
  final MascotCharacter character;
  final MascotBehavior behavior;
  final ScreensaverBackdrop backdrop;
  final bool blurBackground;
  final String customBgSource;
  final String customBgLabel;
  final bool soundsEnabled;
  final bool hapticEnabled;
  final int hapticStrength;
  final Color accentColor;
  final LangCode lang;
  final VoidCallback onWakeToIdle;

  const MascotBehaviorStage({
    super.key,
    required this.character,
    required this.behavior,
    required this.backdrop,
    required this.blurBackground,
    required this.customBgSource,
    required this.customBgLabel,
    required this.soundsEnabled,
    required this.hapticEnabled,
    required this.hapticStrength,
    required this.accentColor,
    required this.lang,
    required this.onWakeToIdle,
  });

  @override
  State<MascotBehaviorStage> createState() => _MascotBehaviorStageState();
}

class _MascotBehaviorStageState extends State<MascotBehaviorStage> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  bool _wakingUp = false;
  Timer? _wakeTimer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))..repeat();
  }

  @override
  void dispose() {
    _wakeTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _triggerWake() {
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        45,
        amplitude: HardwareService.scaledAmplitude(155, widget.hapticStrength),
      );
    }
    if (widget.soundsEnabled) {
      AmbientAudioService.playMascotSound(widget.character);
    }
    _wakeTimer?.cancel();
    setState(() => _wakingUp = true);
    _wakeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _wakingUp = false);
        widget.onWakeToIdle();
      }
    });
  }

  String _backdropLabel(bool tr) {
    if (widget.backdrop == ScreensaverBackdrop.custom && widget.customBgSource.isNotEmpty) {
      return widget.customBgLabel.isNotEmpty
          ? widget.customBgLabel
          : (tr ? 'Özel Görsel' : 'Custom Image');
    }
    switch (widget.backdrop) {
      case ScreensaverBackdrop.oledBlack:
        return tr ? 'Saf OLED Siyah' : 'Pure OLED Black';
      case ScreensaverBackdrop.termoLab:
        return 'Termo Lab';
      case ScreensaverBackdrop.warmHearth:
        return tr ? 'Sıcak Köşe' : 'Warm Hearth';
      case ScreensaverBackdrop.nightNebula:
        return 'Gece Nebula';
      case ScreensaverBackdrop.custom:
        return tr ? 'Özel / Tema' : 'Custom / Accent';
    }
  }

  String _behaviorPill(MascotBehavior b, bool tr) {
    if (_wakingUp) {
      return tr ? '✨ Uyanıyor...' : '✨ Waking up...';
    }
    switch (b) {
      case MascotBehavior.idle:
        return tr ? '🟢 Boşta · Hazır' : '🟢 Idle · Ready';
      case MascotBehavior.patrol:
        return tr ? '🐾 Devriye Geziyor' : '🐾 Patrolling';
      case MascotBehavior.knock:
        return tr ? '🤔 Tık Tık · Camda!' : '🤔 Knock Knock!';
      case MascotBehavior.think:
        return tr ? '💡 Tasarruf Analizi...' : '💡 Thinking...';
      case MascotBehavior.read:
        return tr ? '📖 Kombi Rehberi Okuyor' : '📖 Reading Manual';
      case MascotBehavior.deepSleep:
        return tr ? '🌙 Derin Uyku (%50 Kısık)' : '🌙 Deep Sleep (50% Dim)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    final hasCustomBg = widget.backdrop == ScreensaverBackdrop.custom && widget.customBgSource.trim().isNotEmpty;
    final effectiveBehavior = _wakingUp ? MascotBehavior.idle : widget.behavior;

    return GestureDetector(
      onTap: _triggerWake,
      child: Container(
        height: 196,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: meta.color.withValues(alpha: 0.30)),
          color: const Color(0xFF040508),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(17),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) Custom uploaded image / URL if active
              if (hasCustomBg)
                ScreensaverCustomWallpaper(source: widget.customBgSource),

              // 2) Live BackdropFilter when blurBackground is active
              if (widget.blurBackground)
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: const SizedBox.expand(),
                ),

              // 3) Procedural backdrop shader/painter
              AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(
                  painter: _ScreensaverBackdropPainter(
                    backdrop: widget.backdrop,
                    progress: _anim.value,
                    accentColor: widget.accentColor,
                    translucentForBlur: widget.blurBackground || hasCustomBg,
                  ),
                ),
              ),

              // 4) Top chips inside stage
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F131E).withValues(alpha: 0.84),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: meta.color.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MascotAvatar(
                            character: widget.character,
                            size: 16,
                            showBehaviorOverlay: false,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            meta.name,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F131E).withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                        ),
                        child: Text(
                          _backdropLabel(tr),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.86)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 5) Center animated 3D Mascot + Behavior Status
              Center(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final patrolDx = effectiveBehavior == MascotBehavior.patrol
                        ? math.sin(_anim.value * math.pi * 2) * 58.0
                        : 0.0;
                    final bobDy = effectiveBehavior == MascotBehavior.patrol
                        ? -math.sin(_anim.value * math.pi * 12).abs() * 5.0
                        : (effectiveBehavior == MascotBehavior.knock
                            ? math.sin(_anim.value * math.pi * 8) * 3.0
                            : 0.0);

                    return Transform.translate(
                      offset: Offset(patrolDx, 12 + bobDy),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: effectiveBehavior == MascotBehavior.deepSleep
                                  ? const Color(0xFF1E1B4B).withValues(alpha: 0.90)
                                  : const Color(0xFF111522).withValues(alpha: 0.90),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (_wakingUp ? const Color(0xFFFBBF24) : meta.color).withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              _behaviorPill(effectiveBehavior, tr),
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          MascotAvatar(
                            character: widget.character,
                            size: 86,
                            behavior: effectiveBehavior,
                            sleeping: effectiveBehavior == MascotBehavior.deepSleep,
                            happy: _wakingUp,
                            phase: _anim.value,
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
  MascotBehavior _behavior = MascotBehavior.patrol;
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
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          _walkHalfLegs++;
          if (_walkHalfLegs == 2) {
            if (mounted) setState(() => _behavior = MascotBehavior.think);
          } else if (_walkHalfLegs == 4) {
            if (mounted) setState(() => _behavior = MascotBehavior.read);
          } else if (_walkHalfLegs >= 6) {
            if (mounted) {
              setState(() => _behavior = MascotBehavior.deepSleep);
              if (widget.soundsEnabled) {
                AmbientAudioService.playMascotSound(widget.character, sleepy: true);
              }
            }
            return;
          } else {
            if (mounted) setState(() => _behavior = MascotBehavior.patrol);
          }
          if (status == AnimationStatus.completed) {
            _walkCtrl.reverse();
          } else {
            _walkCtrl.forward();
          }
        }
      });
  }

  @override
  void didUpdateWidget(covariant TermoBotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && widget.isSleeping && !_walkCtrl.isAnimating && _behavior != MascotBehavior.deepSleep) {
      _walkHalfLegs = 0;
      _behavior = MascotBehavior.patrol;
      _happy = false;
      _walkCtrl.forward();
    } else if ((!widget.enabled || !widget.isSleeping) && (_walkCtrl.isAnimating || _behavior == MascotBehavior.deepSleep)) {
      _walkCtrl.stop();
      _behavior = MascotBehavior.idle;
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
      _behavior = MascotBehavior.idle;
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
    final napping = _behavior == MascotBehavior.deepSleep;

    return AnimatedBuilder(
      animation: _walkCtrl,
      builder: (context, child) {
        final x = 18.0 + (napping ? 0.15 : _walkCtrl.value) * (maxWalk * 0.55);
        final bob = napping ? 0.0 : math.sin(_walkCtrl.value * math.pi * 12).abs() * 3.5;
        return Positioned(
          left: x,
          bottom: widget.bottomOffset + bob,
          child: GestureDetector(
            onTap: _handleTap,
            onLongPress: widget.onOpenScreensaver,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_speech != null || napping)
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
                        if (widget.onOpenScreensaver != null && napping) ...[
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
                  size: 52,
                  behavior: _behavior,
                  sleeping: napping,
                  happy: _happy,
                  phase: _walkCtrl.value,
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
  final String customBgSource;
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
    this.customBgSource = '',
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
    final hasCustomBg = widget.backdrop == ScreensaverBackdrop.custom && widget.customBgSource.trim().isNotEmpty;

    return Positioned.fill(
      child: GestureDetector(
        onTap: widget.onExit,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1) Custom wallpaper image when selected
              if (hasCustomBg)
                ScreensaverCustomWallpaper(source: widget.customBgSource),

              // 2) Genuine BackdropFilter directly over underlying thermostat UI / custom wallpaper
              if (widget.blurBackground)
                BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: const SizedBox.expand(),
                ),

              // 3) Screensaver themed atmosphere
              AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => CustomPaint(
                  painter: _ScreensaverBackdropPainter(
                    backdrop: widget.backdrop,
                    progress: _anim.value,
                    accentColor: widget.accentColor,
                    translucentForBlur: widget.blurBackground || hasCustomBg,
                  ),
                ),
              ),

              // 4) Foreground clock, 3D Unreal mascot portrait (tappable to pet), and live telemetry
              Center(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final dx = math.sin(_anim.value * math.pi * 2) * 34.0;
                    final dy = math.cos(_anim.value * math.pi * 4).abs() * -9.0;
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
                                  size: 122,
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
    final veilAlpha = translucentForBlur ? 0.58 : 1.0;

    switch (backdrop) {
      case ScreensaverBackdrop.oledBlack:
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = Colors.black.withValues(alpha: translucentForBlur ? 0.65 : 1.0),
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
                accentColor.withValues(alpha: translucentForBlur ? 0.24 : 0.40),
                const Color(0xFF06070B).withValues(alpha: translucentForBlur ? 0.48 : 1.0),
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
