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

/// Unreal Engine 3D Character Actor with frameless radial feathering, 3D perspective kinematics,
/// and organic scene-integrated animations (zero circular badge rings or corner pill icons).
class MascotAvatar extends StatelessWidget {
  final MascotCharacter character;
  final double size;
  final bool sleeping;
  final bool happy;
  final MascotBehavior behavior;
  final double phase;
  final double facingDirection; // +1 = facing right, -1 = facing left
  final bool showBehaviorOverlay;
  final bool frameless;

  const MascotAvatar({
    super.key,
    required this.character,
    this.size = 64,
    this.sleeping = false,
    this.happy = false,
    this.behavior = MascotBehavior.idle,
    this.phase = 0.0,
    this.facingDirection = 1.0,
    this.showBehaviorOverlay = true,
    this.frameless = true,
  });

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(character);
    final isSleep = sleeping || behavior == MascotBehavior.deepSleep;
    final p2 = phase * math.pi * 2;

    // 3D kinematic motion parameters per behavior
    double tx = 0.0;
    double ty = 0.0;
    double rotX = 0.0;
    double rotY = 0.0;
    double rotZ = 0.0;
    double scaleX = 1.0;
    double scaleY = 1.0;

    if (happy) {
      final bounce = math.sin(phase * math.pi * 8).abs();
      ty = -bounce * (size * 0.14);
      scaleX = 1.06 + bounce * 0.06;
      scaleY = 1.06 + bounce * 0.08;
      rotZ = math.sin(phase * math.pi * 6) * 0.07;
    } else if (isSleep) {
      // Deep rhythmic chest breathing + drowsy head nod
      final breath = math.sin(p2);
      ty = size * 0.07 + breath * 1.5;
      scaleX = 1.0 + breath * 0.024;
      scaleY = 1.0 - breath * 0.020;
      rotX = 0.22 + breath * 0.03;
      rotZ = -0.07 + math.cos(p2) * 0.02;
    } else {
      switch (behavior) {
        case MascotBehavior.idle:
          final breath = math.sin(p2);
          ty = breath * (size * 0.025);
          scaleX = 1.0 + breath * 0.018;
          scaleY = 1.0 - breath * 0.018;
          rotY = math.sin(p2 * 0.5) * 0.16;
          rotZ = math.cos(p2 * 0.5) * 0.035;
          break;
        case MascotBehavior.patrol:
          // Stride step cycle: 4 steps per phase cycle
          final stepWave = math.sin(p2 * 3.0);
          final strideHop = stepWave.abs();
          ty = -strideHop * (size * 0.11);
          rotZ = stepWave * 0.10 * facingDirection;
          rotX = -0.10; // forward walk lean
          rotY = facingDirection >= 0 ? -0.20 : 0.20;
          scaleY = 0.97 + strideHop * 0.06;
          scaleX = 1.03 - strideHop * 0.03;
          break;
        case MascotBehavior.knock:
          // Rushes right up to the front glass & taps 3 times cleanly
          final burst = (phase * 2.0) % 1.0;
          final hit1 = math.exp(-math.pow((burst - 0.20) * 14, 2));
          final hit2 = math.exp(-math.pow((burst - 0.38) * 14, 2));
          final hit3 = math.exp(-math.pow((burst - 0.56) * 14, 2));
          final knockImpulse = (hit1 + hit2 + hit3).clamp(0.0, 1.0);
          final rush = 1.14 + knockImpulse * 0.22;
          scaleX = rush;
          scaleY = rush;
          tx = math.sin(burst * math.pi * 6) * knockImpulse * 4.0;
          ty = -knockImpulse * (size * 0.08);
          rotX = -0.18 - knockImpulse * 0.10;
          rotZ = (hit1 - hit2) * 0.09;
          break;
        case MascotBehavior.think:
          // Thoughtful head tilt & curious glance upward
          final sway = math.sin(p2);
          ty = -size * 0.03 + sway * 2.5;
          rotZ = -0.14 + sway * 0.03;
          rotY = 0.24 + math.cos(p2) * 0.05;
          rotX = -0.06;
          scaleX = 1.03;
          scaleY = 1.03;
          break;
        case MascotBehavior.read:
          // Calm downward bow + horizontal eye-line reading sweep left <-> right
          final scan = math.sin(p2 * 2.0);
          ty = size * 0.05 + math.cos(p2) * 1.5;
          rotX = 0.18;
          rotY = scan * 0.22;
          rotZ = scan * 0.03;
          scaleX = 0.99;
          scaleY = 0.99;
          break;
        case MascotBehavior.deepSleep:
          break;
      }
    }

    final perspective = Matrix4.identity()
      ..setEntry(3, 2, 0.0022)
      ..rotateX(rotX)
      ..rotateY(rotY)
      ..rotateZ(rotZ);

    final imageCore = Image.asset(
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
    );

    // Frameless uses soft radial feather so dark studio bg melts into the scene (not a circular badge)
    final characterVisual = frameless
        ? ShaderMask(
            shaderCallback: (bounds) => const RadialGradient(
              center: Alignment(0, -0.04),
              radius: 0.50,
              colors: [
                Colors.white,
                Colors.white,
                Color(0x99FFFFFF),
                Colors.transparent,
              ],
              stops: [0.0, 0.56, 0.78, 0.98],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: Stack(
              fit: StackFit.expand,
              children: [
                imageCore,
                if (isSleep)
                  Container(
                    color: const Color(0xFF0B1022).withValues(alpha: 0.45),
                  ),
                if (happy)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFFBBF24).withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        : Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.26),
              border: Border.all(
                color: happy ? const Color(0xFFFBBF24) : meta.color.withValues(alpha: 0.72),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: meta.color.withValues(alpha: 0.28),
                  blurRadius: size * 0.25,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.24),
              child: imageCore,
            ),
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Soft ambient aura & grounded floor shadow (only when frameless floating actor)
          if (frameless) ...[
            Positioned(
              bottom: -size * 0.06,
              child: Container(
                width: size * (behavior == MascotBehavior.patrol ? 0.62 : 0.72),
                height: size * 0.14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isSleep ? 0.65 : 0.50),
                      blurRadius: size * 0.14,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: meta.color.withValues(alpha: isSleep ? 0.10 : 0.22),
                      blurRadius: size * 0.22,
                    ),
                  ],
                ),
              ),
            ),
            // Floor step glow during patrol
            if (showBehaviorOverlay && behavior == MascotBehavior.patrol)
              Positioned(
                bottom: -size * 0.05,
                left: facingDirection >= 0 ? -size * 0.26 : null,
                right: facingDirection < 0 ? -size * 0.26 : null,
                child: CustomPaint(
                  size: Size(size * 0.42, size * 0.14),
                  painter: _FootstepDustPainter(color: meta.color, progress: phase),
                ),
              ),
          ],

          // Animated 3D Character Layer
          Opacity(
            opacity: isSleep ? 0.50 : 1.0,
            child: Transform.translate(
              offset: Offset(tx, ty),
              child: Transform.scale(
                scaleX: scaleX,
                scaleY: scaleY,
                child: Transform(
                  alignment: Alignment.center,
                  transform: perspective,
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: characterVisual,
                  ),
                ),
              ),
            ),
          ),

          // Scene-Integrated Character Acting Props (no rounded badge circles)
          if (showBehaviorOverlay && isSleep)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SleepZzzPainter(progress: phase),
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.knock)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _KnockGlassWavePainter(color: meta.color, progress: phase),
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.think)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _ThoughtCloudPainter(color: meta.color, progress: phase),
                ),
              ),
            ),

          if (showBehaviorOverlay && behavior == MascotBehavior.read)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _OpenBook3DPainter(accent: meta.color, progress: phase),
                ),
              ),
            ),

          if (showBehaviorOverlay && happy)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _HappySparklesPainter(color: meta.color, progress: phase),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FootstepDustPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _FootstepDustPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 3; i++) {
      final t = (progress * 3.0 + i * 0.33) % 1.0;
      final r = (1.0 - t) * (size.height * 0.42);
      final x = size.width * (1.0 - t);
      final y = size.height * 0.55 - t * 4.0;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: (1.0 - t) * 0.34),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FootstepDustPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _KnockGlassWavePainter extends CustomPainter {
  final Color color;
  final double progress;

  const _KnockGlassWavePainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final burst = (progress * 2.0) % 1.0;
    final impactCenter = Offset(size.width * 0.52, size.height * 0.48);

    // Three expanding crisp screen-glass refraction rings at impact timing
    final starts = [0.18, 0.36, 0.54];
    for (final s in starts) {
      final dt = burst - s;
      if (dt >= 0 && dt < 0.42) {
        final k = dt / 0.42;
        final radius = size.width * (0.14 + k * 0.52);
        final alpha = (1.0 - k) * 0.65;
        canvas.drawCircle(
          impactCenter,
          radius,
          Paint()
            ..color = Colors.white.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * (1.0 - k * 0.6),
        );
        canvas.drawCircle(
          impactCenter,
          radius * 0.72,
          Paint()
            ..color = color.withValues(alpha: alpha * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KnockGlassWavePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _ThoughtCloudPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _ThoughtCloudPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final bob = math.sin(progress * math.pi * 2) * 3.5;
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.22);
    final rim = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    // Trailing rising thought droplets from mascot head toward top-right cloud
    final p1 = Offset(size.width * 0.72, size.height * 0.16 + bob * 0.4);
    final p2 = Offset(size.width * 0.84, size.height * 0.04 + bob * 0.7);
    canvas.drawCircle(p1, size.width * 0.045, fill);
    canvas.drawCircle(p1, size.width * 0.045, rim);
    canvas.drawCircle(p2, size.width * 0.068, fill);
    canvas.drawCircle(p2, size.width * 0.068, rim);

    // Fluffy organic thought cloud puff
    final cloudCenter = Offset(size.width * 0.96, -size.height * 0.10 + bob);
    final cw = size.width * 0.34;
    final path = Path()
      ..addOval(Rect.fromCenter(center: cloudCenter, width: cw, height: cw * 0.62))
      ..addOval(Rect.fromCenter(center: cloudCenter.translate(-cw * 0.26, 2), width: cw * 0.56, height: cw * 0.46))
      ..addOval(Rect.fromCenter(center: cloudCenter.translate(cw * 0.24, 2), width: cw * 0.52, height: cw * 0.44));
    canvas.drawPath(path, Paint()..color = const Color(0xFF141827).withValues(alpha: 0.88));
    canvas.drawPath(path, rim);

    // Three animated thinking pulse dots inside the thought cloud
    for (int i = -1; i <= 1; i++) {
      final pulse = 0.45 + 0.55 * math.sin(progress * math.pi * 4 - i * 0.9).abs();
      canvas.drawCircle(
        cloudCenter.translate(i * cw * 0.20, 0),
        (cw * 0.075).clamp(1.6, 4.0),
        Paint()..color = const Color(0xFFFBBF24).withValues(alpha: pulse),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ThoughtCloudPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _OpenBook3DPainter extends CustomPainter {
  final Color accent;
  final double progress;

  const _OpenBook3DPainter({required this.accent, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.50;
    final by = size.height * 0.86;
    final bw = size.width * 0.56;
    final bh = size.height * 0.22;
    final pageGlow = 0.72 + 0.28 * math.sin(progress * math.pi * 2);

    // Warm upward illumination onto mascot face from open luminous book
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, by - bh * 0.4), width: bw * 1.25, height: bh * 1.8),
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF7DD3FC).withValues(alpha: 0.30 * pageGlow),
            accent.withValues(alpha: 0.12),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCenter(center: Offset(cx, by - bh * 0.4), width: bw * 1.3, height: bh * 1.9)),
    );

    // Left & Right 3D open pages
    final leftPage = Path()
      ..moveTo(cx, by)
      ..quadraticBezierTo(cx - bw * 0.26, by - bh * 0.35, cx - bw * 0.50, by - bh * 0.18)
      ..lineTo(cx - bw * 0.44, by - bh * 1.02)
      ..quadraticBezierTo(cx - bw * 0.22, by - bh * 1.12, cx, by - bh * 0.76)
      ..close();

    final rightPage = Path()
      ..moveTo(cx, by)
      ..quadraticBezierTo(cx + bw * 0.26, by - bh * 0.35, cx + bw * 0.50, by - bh * 0.18)
      ..lineTo(cx + bw * 0.44, by - bh * 1.02)
      ..quadraticBezierTo(cx + bw * 0.22, by - bh * 1.12, cx, by - bh * 0.76)
      ..close();

    final cover = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.94)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final pageFill = Paint()..color = const Color(0xFFE0F2FE).withValues(alpha: 0.90);
    final edgeStroke = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    canvas.drawPath(leftPage, pageFill);
    canvas.drawPath(rightPage, pageFill);
    canvas.drawPath(leftPage, edgeStroke);
    canvas.drawPath(rightPage, edgeStroke);
    canvas.drawLine(Offset(cx, by + 1), Offset(cx, by - bh * 0.76), cover);

    // Turning translucent page sweeping cleanly across spine
    final flip = (math.sin(progress * math.pi * 2) * 0.5 + 0.5); // 0 -> 1
    final flipTipX = cx + (0.5 - flip) * bw * 0.72;
    final flipPage = Path()
      ..moveTo(cx, by)
      ..quadraticBezierTo((cx + flipTipX) * 0.5, by - bh * 0.65, flipTipX, by - bh * 0.35)
      ..lineTo(flipTipX * 0.98 + cx * 0.02, by - bh * 1.06)
      ..quadraticBezierTo((cx + flipTipX) * 0.5, by - bh * 1.20, cx, by - bh * 0.76)
      ..close();
    canvas.drawPath(flipPage, Paint()..color = Colors.white.withValues(alpha: 0.58));
  }

  @override
  bool shouldRepaint(covariant _OpenBook3DPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _SleepZzzPainter extends CustomPainter {
  final double progress;

  const _SleepZzzPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final letters = ['z', 'Z', 'z'];
    for (int i = 0; i < 3; i++) {
      final t = (progress + i * 0.33) % 1.0;
      final alpha = math.sin(t * math.pi).clamp(0.0, 1.0);
      final x = size.width * (0.72 + i * 0.08 + math.sin(t * math.pi * 2) * 0.04);
      final y = size.height * (0.24 - t * 0.36);
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            fontSize: (size.width * (0.14 + t * 0.08)).clamp(9.0, 22.0),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF93C5FD).withValues(alpha: alpha * 0.92),
            shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _SleepZzzPainter oldDelegate) => oldDelegate.progress != progress;
}

class _HappySparklesPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _HappySparklesPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 6; i++) {
      final angle = i * (math.pi / 3) + progress * math.pi * 2;
      final dist = size.width * (0.48 + 0.10 * math.sin(progress * math.pi * 4 + i));
      final pt = Offset(size.width / 2 + math.cos(angle) * dist, size.height / 2 + math.sin(angle) * dist);
      canvas.drawCircle(
        pt,
        (size.width * 0.032).clamp(1.8, 4.2),
        Paint()..color = (i.isEven ? const Color(0xFFFBBF24) : color).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HappySparklesPainter oldDelegate) =>
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

/// Interactive preview stage in Settings for testing all 6 mascot behaviors, custom wallpapers, and live mascot size.
class MascotBehaviorStage extends StatefulWidget {
  final MascotCharacter character;
  final MascotBehavior behavior;
  final double mascotScale;
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
    this.mascotScale = 1.0,
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
        return tr ? 'Boşta · Hazır' : 'Idle · Ready';
      case MascotBehavior.patrol:
        return tr ? 'Devriye Geziyor' : 'Patrolling';
      case MascotBehavior.knock:
        return tr ? 'Tık Tık · Camda!' : 'Knock Knock!';
      case MascotBehavior.think:
        return tr ? 'Tasarruf Analizi...' : 'Thinking...';
      case MascotBehavior.read:
        return tr ? 'Kombi Rehberi Okuyor' : 'Reading Manual';
      case MascotBehavior.deepSleep:
        return tr ? 'Derin Uyku (%50 Kısık)' : 'Deep Sleep (50% Dim)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    final hasCustomBg = widget.backdrop == ScreensaverBackdrop.custom && widget.customBgSource.trim().isNotEmpty;
    final effectiveBehavior = _wakingUp ? MascotBehavior.idle : widget.behavior;
    final scaledSize = (82.0 * widget.mascotScale).clamp(48.0, 134.0);
    final scalePct = (widget.mascotScale * 100).round();

    return GestureDetector(
      onTap: _triggerWake,
      child: Container(
        height: 224,
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

              // 4) Top chips inside stage (Mascot name + size % on left, backdrop on right)
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
                          Icon(meta.icon, size: 12, color: meta.color),
                          const SizedBox(width: 5),
                          Text(
                            '${meta.name} · %$scalePct',
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
                    final angle = _anim.value * math.pi * 2;
                    final patrolDx = effectiveBehavior == MascotBehavior.patrol
                        ? math.sin(angle) * 68.0
                        : 0.0;
                    // Derivative of sin(angle) is cos(angle): >0 moving right, <0 moving left
                    final facingDir = effectiveBehavior == MascotBehavior.patrol
                        ? (math.cos(angle) >= 0 ? 1.0 : -1.0)
                        : 1.0;

                    return Transform.translate(
                      offset: Offset(patrolDx, 12.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: effectiveBehavior == MascotBehavior.deepSleep
                                  ? const Color(0xFF1E1B4B).withValues(alpha: 0.88)
                                  : const Color(0xFF111522).withValues(alpha: 0.88),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: (_wakingUp ? const Color(0xFFFBBF24) : meta.color).withValues(alpha: 0.50),
                              ),
                            ),
                            child: Text(
                              _behaviorPill(effectiveBehavior, tr),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          MascotAvatar(
                            character: widget.character,
                            size: scaledSize,
                            behavior: effectiveBehavior,
                            sleeping: effectiveBehavior == MascotBehavior.deepSleep,
                            happy: _wakingUp,
                            phase: _anim.value,
                            facingDirection: facingDir,
                            frameless: true,
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
  final double mascotScale;
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
    this.mascotScale = 1.0,
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
          } else if (_walkHalfLegs == 3) {
            if (mounted) setState(() => _behavior = MascotBehavior.knock);
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
    final scaledSize = (64.0 * widget.mascotScale).clamp(38.0, 108.0);

    return AnimatedBuilder(
      animation: _walkCtrl,
      builder: (context, child) {
        final x = 18.0 + (napping ? 0.15 : _walkCtrl.value) * (maxWalk * 0.55);
        final facingDir = _walkCtrl.status == AnimationStatus.reverse ? -1.0 : 1.0;

        return Positioned(
          left: x,
          bottom: widget.bottomOffset,
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
                  size: scaledSize,
                  behavior: _behavior,
                  sleeping: napping,
                  happy: _happy,
                  phase: _walkCtrl.value,
                  facingDirection: facingDir,
                  frameless: true,
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
  final double mascotScale;
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
    this.mascotScale = 1.0,
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
    final scaledSize = (138.0 * widget.mascotScale).clamp(84.0, 224.0);

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

              // 4) Foreground clock, floating 3D Unreal mascot (tappable to pet), and live telemetry
              Center(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final dx = math.sin(_anim.value * math.pi * 2) * 34.0;
                    final dy = math.cos(_anim.value * math.pi * 4).abs() * -9.0;
                    final oledShiftX = ((_now.minute % 3) - 1) * 4.0;
                    final oledShiftY = ((_now.minute % 5) - 2) * 2.0;
                    final facingDir = math.cos(_anim.value * math.pi * 2) >= 0 ? 1.0 : -1.0;

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
                                  size: scaledSize,
                                  behavior: MascotBehavior.patrol,
                                  happy: _happy,
                                  phase: _anim.value,
                                  facingDirection: facingDir,
                                  frameless: true,
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
