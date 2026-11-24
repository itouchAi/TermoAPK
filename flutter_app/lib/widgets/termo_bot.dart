import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';
import '../services/media_storage_service.dart';

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

    final syncBytes = MediaStorageService.getCachedBytes(trimmed);
    if (syncBytes != null) {
      return Image.memory(
        syncBytes,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (MediaStorageService.isPersistedKey(trimmed)) {
      return FutureBuilder<Uint8List?>(
        future: MediaStorageService.loadBytes(trimmed),
        builder: (context, snap) {
          final data = snap.data;
          if (data == null || data.isEmpty) return const SizedBox.shrink();
          return Image.memory(
            data,
            fit: fit,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      );
    }

    return const SizedBox.shrink();
  }
}

/// Full-body 3D-shaded rigged skeletal Mascot Actor supporting genuine limb, head, eye, and prop kinematics:
/// - idle: breathing, natural eye blink, subtle hand sway (waves happily on wake)
/// - patrol: true alternating left/right leg & arm gait + facing turn + bouncing ears/tail
/// - knock: raises arm & knocks 3 times on glass with impact ripples
/// - think: tilts head, puts hand up to forehead/temple, looks up at thought cloud
/// - read: pulls out an open illuminated book in both hands, eyes scan lines & turns page
/// - deepSleep: lies horizontally on ground, closes both eyelids, dims 50%, breathes deeply with floating z Z z
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
    this.size = 72,
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
    final activeBehavior = sleeping ? MascotBehavior.deepSleep : behavior;
    final isSleep = activeBehavior == MascotBehavior.deepSleep;

    if (!frameless) {
      // Compact rounded studio thumbnail for character selector cards
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.26),
          border: Border.all(
            color: happy ? const Color(0xFFFBBF24) : meta.color.withValues(alpha: 0.72),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: meta.color.withValues(alpha: 0.28),
              blurRadius: size * 0.24,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Image.asset(
            meta.assetPath,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => CustomPaint(
              painter: _RiggedMascotPainter(
                character: character,
                accent: meta.color,
                behavior: MascotBehavior.idle,
                happy: happy,
                phase: phase,
                facingDirection: 1.0,
                showProps: false,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Opacity(
        opacity: isSleep ? 0.56 : 1.0,
        child: CustomPaint(
          painter: _RiggedMascotPainter(
            character: character,
            accent: meta.color,
            behavior: activeBehavior,
            happy: happy,
            phase: phase,
            facingDirection: facingDirection,
            showProps: showBehaviorOverlay,
          ),
        ),
      ),
    );
  }
}

class _RiggedMascotPainter extends CustomPainter {
  final MascotCharacter character;
  final Color accent;
  final MascotBehavior behavior;
  final bool happy;
  final double phase;
  final double facingDirection;
  final bool showProps;

  const _RiggedMascotPainter({
    required this.character,
    required this.accent,
    required this.behavior,
    required this.happy,
    required this.phase,
    required this.facingDirection,
    required this.showProps,
  });

  /// Solves a smooth 2-bone limb elbow/knee bend point in 2D space.
  Offset _solveJoint(Offset root, Offset target, double l1, double l2, double bendSign) {
    final dx = target.dx - root.dx;
    final dy = target.dy - root.dy;
    final maxReach = math.max(0.01, l1 + l2 - 0.05);
    final dist = math.sqrt(dx * dx + dy * dy).clamp(0.001, maxReach);
    final cosA = ((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)).clamp(-1.0, 1.0);
    final baseAngle = math.atan2(dy, dx);
    final jointAngle = baseAngle + bendSign * math.acos(cosA);
    return Offset(
      root.dx + math.cos(jointAngle) * l1,
      root.dy + math.sin(jointAngle) * l1,
    );
  }

  Paint _limbPaint(Color base, double width, Offset a, Offset b) {
    return Paint()
      ..shader = ui.Gradient.linear(
        a.translate(-width * 0.35, -width * 0.35),
        b.translate(width * 0.35, width * 0.35),
        [
          Color.lerp(base, Colors.white, 0.34)!,
          base,
          Color.lerp(base, Colors.black, 0.44)!,
        ],
        [0.0, 0.50, 1.0],
      )
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
  }

  void _drawCapsuleLimb(Canvas canvas, Offset root, Offset mid, Offset tip, double width, Color base) {
    final rimOutline = Paint()
      ..color = Colors.black.withValues(alpha: 0.34)
      ..strokeWidth = width + (width * 0.22)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(root, mid, rimOutline);
    canvas.drawLine(mid, tip, rimOutline);

    canvas.drawLine(root, mid, _limbPaint(base, width, root, mid));
    canvas.drawLine(mid, tip, _limbPaint(base, width * 0.94, mid, tip));

    // Specular edge sheen & sculpted joint socket
    final sheen = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = width * 0.24
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(root.translate(-width * 0.14, -width * 0.12), mid.translate(-width * 0.14, -width * 0.12), sheen);
    canvas.drawCircle(mid, width * 0.46, Paint()..color = Color.lerp(base, Colors.black, 0.24)!);
    canvas.drawCircle(mid.translate(-width * 0.08, -width * 0.08), width * 0.30, Paint()..color = Color.lerp(base, Colors.white, 0.22)!);
  }

  Paint _spherePaint(Rect rect, Color light, Color mid, Color dark) {
    return Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.34, -0.40),
        radius: 0.94,
        colors: [light, mid, dark],
        stops: const [0.0, 0.54, 1.0],
      ).createShader(rect);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2.0 || size.height < 2.0) return;
    final u = size.width / 100.0;
    final cx = size.width * 0.50;
    final groundY = size.height * 0.90;
    final p2 = phase * math.pi * 2;
    final isSleep = behavior == MascotBehavior.deepSleep;

    // Character color palette (3D shaded tones)
    late final Color bodyPrimary;
    late final Color bodyLight;
    late final Color bodyDark;
    late final Color headBase;
    late final Color headLight;
    late final Color headDark;
    late final Color limbColor;
    late final Color handColor;
    late final Color shoeColor;

    switch (character) {
      case MascotCharacter.termoBot:
        bodyPrimary = const Color(0xFF334155);
        bodyLight = const Color(0xFF94A3B8);
        bodyDark = const Color(0xFF0F172A);
        headBase = const Color(0xFF475569);
        headLight = const Color(0xFFCBD5E1);
        headDark = const Color(0xFF1E293B);
        limbColor = const Color(0xFF475569);
        handColor = const Color(0xFF38BDF8);
        shoeColor = const Color(0xFF1E293B);
        break;
      case MascotCharacter.mirnav:
        bodyPrimary = const Color(0xFFEA580C);
        bodyLight = const Color(0xFFFDBA74);
        bodyDark = const Color(0xFF7C2D12);
        headBase = const Color(0xFFF97316);
        headLight = const Color(0xFFFED7AA);
        headDark = const Color(0xFF9A3412);
        limbColor = const Color(0xFFEA580C);
        handColor = const Color(0xFFFFEDD5);
        shoeColor = const Color(0xFFFFEDD5);
        break;
      case MascotCharacter.puki:
        bodyPrimary = const Color(0xFFFBCFE8);
        bodyLight = const Color(0xFFFFF1F2);
        bodyDark = const Color(0xFFBE185D);
        headBase = const Color(0xFFFCE7F3);
        headLight = const Color(0xFFFFFFFF);
        headDark = const Color(0xFFF472B6);
        limbColor = const Color(0xFFF9A8D4);
        handColor = const Color(0xFFFFF1F2);
        shoeColor = const Color(0xFFF472B6);
        break;
      case MascotCharacter.mert:
        bodyPrimary = const Color(0xFF1E3A5F);
        bodyLight = const Color(0xFF3B82F6);
        bodyDark = const Color(0xFF0F172A);
        headBase = const Color(0xFFF3C6A5);
        headLight = const Color(0xFFFFE4CF);
        headDark = const Color(0xFFC2855C);
        limbColor = const Color(0xFF1D4ED8);
        handColor = const Color(0xFFF3C6A5);
        shoeColor = const Color(0xFF1E293B);
        break;
      case MascotCharacter.ela:
        bodyPrimary = const Color(0xFF4C1D95);
        bodyLight = const Color(0xFFA78BFA);
        bodyDark = const Color(0xFF1E1B4B);
        headBase = const Color(0xFFF7CEB2);
        headLight = const Color(0xFFFFEAD9);
        headDark = const Color(0xFFC98B68);
        limbColor = const Color(0xFF6D28D9);
        handColor = const Color(0xFFF7CEB2);
        shoeColor = const Color(0xFF312E81);
        break;
    }

    // ------------------------------------------------------------------
    // 1. Ground Shadow (wide horizontal oval when lying down in deepSleep)
    // ------------------------------------------------------------------
    final shadowWidth = isSleep ? 68 * u : (behavior == MascotBehavior.knock ? 46 * u : 38 * u);
    final shadowHeight = isSleep ? 9 * u : 7 * u;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, groundY + 1.5 * u), width: shadowWidth, height: shadowHeight),
      Paint()
        ..color = Colors.black.withValues(alpha: isSleep ? 0.52 : 0.45)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, 4.0 * u),
    );

    if (isSleep) {
      // ================================================================
      // FULL HORIZONTAL LYING-DOWN SLEEP POSE (Yere uzanıp uyuma + gözler kapalı)
      // ================================================================
      final breath = math.sin(p2);
      final sleepCenterY = groundY - 12 * u;

      canvas.save();
      // Tail curled peacefully for cat/bunny
      if (character == MascotCharacter.mirnav) {
        final tailWave = math.sin(p2) * 3 * u;
        final tailPath = Path()
          ..moveTo(cx + 12 * u, sleepCenterY - 2 * u)
          ..quadraticBezierTo(cx + 28 * u, sleepCenterY - 14 * u + tailWave, cx + 34 * u, sleepCenterY - 3 * u);
        canvas.drawPath(tailPath, _limbPaint(bodyPrimary, 4.2 * u, Offset(cx + 12 * u, sleepCenterY), Offset(cx + 34 * u, sleepCenterY)));
      }

      // Relaxed bent legs stretched out to the right on floor
      final hip = Offset(cx + 8 * u, sleepCenterY);
      final backKnee = Offset(cx + 20 * u, sleepCenterY + 2.5 * u);
      final backFoot = Offset(cx + 32 * u, sleepCenterY + 5.5 * u);
      final frontKnee = Offset(cx + 19 * u, sleepCenterY - 3.5 * u);
      final frontFoot = Offset(cx + 30 * u, sleepCenterY + 2.0 * u);

      final legTone = (character == MascotCharacter.mert || character == MascotCharacter.ela)
          ? const Color(0xFF1E293B)
          : limbColor;
      _drawCapsuleLimb(canvas, hip, backKnee, backFoot, 5.8 * u, Color.lerp(legTone, Colors.black, 0.2)!);
      _drawCapsuleLimb(canvas, hip, frontKnee, frontFoot, 6.2 * u, legTone);
      canvas.drawOval(Rect.fromCenter(center: backFoot, width: 6.5 * u, height: 4.5 * u), Paint()..color = shoeColor);
      canvas.drawOval(Rect.fromCenter(center: frontFoot, width: 7.0 * u, height: 4.8 * u), Paint()..color = shoeColor);

      // Horizontal torso gently rising & falling with deep breath
      final chestRect = Rect.fromCenter(
        center: Offset(cx - 2 * u, sleepCenterY - breath * 1.1 * u),
        width: 28 * u,
        height: (16 + breath * 1.4) * u,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(chestRect, Radius.circular(8 * u)),
        _spherePaint(chestRect, bodyLight, bodyPrimary, bodyDark),
      );

      // Arm curled under head as a pillow + top arm resting over side
      final shoulderTop = Offset(cx - 12 * u, sleepCenterY - 4 * u - breath * 0.8 * u);
      final pillowElbow = Offset(cx - 25 * u, sleepCenterY + 3 * u);
      final pillowHand = Offset(cx - 20 * u, sleepCenterY - 6 * u);
      _drawCapsuleLimb(canvas, shoulderTop.translate(0, 5 * u), pillowElbow, pillowHand, 5.0 * u, limbColor);
      _drawCapsuleLimb(
        canvas,
        shoulderTop,
        Offset(cx - 3 * u, sleepCenterY + 3.5 * u),
        Offset(cx + 6 * u, sleepCenterY + 2.5 * u),
        5.2 * u,
        limbColor,
      );
      canvas.drawCircle(Offset(cx + 6.5 * u, sleepCenterY + 2.5 * u), 3.0 * u, Paint()..color = handColor);

      // Head tilted horizontally resting on arm pillow with CLOSED EYES
      canvas.save();
      canvas.translate(cx - 21 * u, sleepCenterY - 6 * u);
      canvas.rotate(-0.22 + breath * 0.02);
      _drawCharacterHead(
        canvas: canvas,
        u: u,
        headBase: headBase,
        headLight: headLight,
        headDark: headDark,
        eyesClosed: true,
        eyeLook: Offset.zero,
        mouthHappy: false,
        mouthOpen: false,
        phase: phase,
      );
      canvas.restore();
      canvas.restore();

      // Floating unmirrored "z Z z" above sleeping head
      if (showProps) {
        _drawFloatingZzz(canvas, Offset(cx - 18 * u, sleepCenterY - 22 * u), u, phase);
      }
      return;
    }

    // ================================================================
    // STANDING / WALKING / ACTING KINEMATICS
    // ================================================================
    final rushScale = behavior == MascotBehavior.knock
        ? 1.12 + math.sin((phase * 2.0 % 1.0) * math.pi).abs() * 0.14
        : (happy ? 1.05 : 1.0);

    // Stride & Posture Calculations
    double walkCycle = 0.0;
    double hopY = 0.0;
    double torsoLean = 0.0;
    double headTilt = 0.0;
    Offset eyeLook = Offset.zero;
    bool eyesClosed = false;
    bool mouthHappy = happy;
    bool mouthOpen = false;

    // Book pullout progress (0 -> 1 smoothly pulls book from side up to chest)
    double bookPull = 0.0;
    double pageFlip = 0.0;

    switch (behavior) {
      case MascotBehavior.idle:
        // Natural standing breath & periodic 150ms blink
        hopY = math.sin(p2) * 1.4 * u;
        torsoLean = math.sin(p2 * 0.5) * 0.03;
        headTilt = math.cos(p2 * 0.5) * 0.04;
        eyeLook = Offset(math.sin(p2 * 0.5) * 1.4 * u, 0);
        // Blink twice per phase loop briefly
        final bMod = (phase * 2.0) % 1.0;
        eyesClosed = bMod > 0.91 && bMod < 0.97;
        break;

      case MascotBehavior.patrol:
        // Crisp 2-step gait cycle
        walkCycle = p2 * 2.0;
        hopY = -math.sin(walkCycle).abs() * 5.2 * u;
        torsoLean = 0.12;
        headTilt = -0.05;
        eyeLook = Offset(1.5 * u, 0);
        mouthHappy = true;
        break;

      case MascotBehavior.knock:
        // Rhythmic 3-tap knock impulse
        final burst = (phase * 2.0) % 1.0;
        final hit1 = math.exp(-math.pow((burst - 0.22) * 15, 2));
        final hit2 = math.exp(-math.pow((burst - 0.42) * 15, 2));
        final hit3 = math.exp(-math.pow((burst - 0.62) * 15, 2));
        final impulse = (hit1 + hit2 + hit3).clamp(0.0, 1.0);
        hopY = -impulse * 3.0 * u;
        torsoLean = 0.10 + impulse * 0.06;
        headTilt = 0.06;
        eyeLook = Offset(0.5 * u, -0.3 * u);
        mouthOpen = impulse > 0.35;
        break;

      case MascotBehavior.think:
        hopY = math.sin(p2) * 1.2 * u;
        torsoLean = -0.06;
        headTilt = -0.14 + math.sin(p2) * 0.03;
        eyeLook = Offset(1.2 * u, -1.6 * u);
        break;

      case MascotBehavior.read:
        // Book lifts out smoothly in first 25%, then pages flip & eyes track left-right
        bookPull = (phase < 0.22) ? (phase / 0.22) : 1.0;
        pageFlip = (math.sin(p2 * 2.0) * 0.5 + 0.5);
        hopY = 2.0 * u + math.cos(p2) * 0.8 * u;
        torsoLean = 0.08;
        headTilt = 0.16 * bookPull;
        // Eyes scan left-to-right across open pages
        eyeLook = Offset(math.sin(p2 * 2.0) * 1.9 * u, 1.3 * u);
        final bMod = (phase * 2.0) % 1.0;
        eyesClosed = bMod > 0.93;
        break;

      case MascotBehavior.deepSleep:
        break;
    }

    if (happy) {
      hopY = -math.sin(p2 * 3.0).abs() * 7.5 * u;
      torsoLean = -0.04;
      headTilt = math.sin(p2 * 3.0) * 0.08;
      mouthHappy = true;
      mouthOpen = true;
    }

    // Save canvas & apply facingDirection mirror + rush scale from groundY
    canvas.save();
    canvas.translate(cx, groundY);
    canvas.scale(facingDirection * rushScale, rushScale);
    canvas.translate(-cx, -groundY);

    // Skeleton Anchor Points
    final hipCenter = Offset(cx, groundY - 26 * u + hopY);
    final shoulderCenter = Offset(
      hipCenter.dx + math.sin(torsoLean) * 20 * u,
      hipCenter.dy - math.cos(torsoLean) * 20 * u,
    );
    final headCenter = Offset(
      shoulderCenter.dx + math.sin(torsoLean + headTilt * 0.4) * 13.5 * u,
      shoulderCenter.dy - math.cos(torsoLean + headTilt * 0.4) * 13.5 * u,
    );

    // ------------------------------------------------------------------
    // 2. Legs & Feet Targets (2-bone articulated thigh -> knee -> ankle)
    // ------------------------------------------------------------------
    final legTone = (character == MascotCharacter.mert || character == MascotCharacter.ela)
        ? const Color(0xFF1E293B)
        : limbColor;

    late Offset lFootTarget;
    late Offset rFootTarget;
    if (behavior == MascotBehavior.patrol) {
      final swing = math.sin(walkCycle);
      final lLift = math.max(0.0, math.cos(walkCycle)) * 7.5 * u;
      final rLift = math.max(0.0, -math.cos(walkCycle)) * 7.5 * u;
      lFootTarget = Offset(cx - 5.5 * u + swing * 12.0 * u, groundY - 2.5 * u - lLift);
      rFootTarget = Offset(cx + 5.5 * u - swing * 12.0 * u, groundY - 2.5 * u - rLift);
    } else if (behavior == MascotBehavior.think) {
      // One foot slightly tapped forward
      final footTap = math.sin(p2 * 3.0).abs() * 2.2 * u;
      lFootTarget = Offset(cx - 6.5 * u, groundY - 2.5 * u);
      rFootTarget = Offset(cx + 7.5 * u, groundY - 2.5 * u - footTap);
    } else {
      lFootTarget = Offset(cx - 6.5 * u, groundY - 2.5 * u);
      rFootTarget = Offset(cx + 6.5 * u, groundY - 2.5 * u);
    }

    final lHip = hipCenter.translate(-4.8 * u, 1.5 * u);
    final rHip = hipCenter.translate(4.8 * u, 1.5 * u);
    final lKnee = _solveJoint(lHip, lFootTarget, 13.2 * u, 13.2 * u, -1.0);
    final rKnee = _solveJoint(rHip, rFootTarget, 13.2 * u, 13.2 * u, -1.0);

    // Cat / Bunny animated tail behind body
    if (character == MascotCharacter.mirnav) {
      final tailWag = math.sin(p2 * (behavior == MascotBehavior.patrol ? 3.0 : 1.5)) * 6.5 * u;
      final tailPath = Path()
        ..moveTo(hipCenter.dx - 4 * u, hipCenter.dy - 1 * u)
        ..cubicTo(
          hipCenter.dx - 18 * u,
          hipCenter.dy - 4 * u + tailWag,
          hipCenter.dx - 24 * u,
          hipCenter.dy - 18 * u - tailWag * 0.5,
          hipCenter.dx - 19 * u,
          hipCenter.dy - 24 * u + tailWag * 0.4,
        );
      canvas.drawPath(
        tailPath,
        Paint()
          ..color = bodyPrimary
          ..strokeWidth = 4.2 * u
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    } else if (character == MascotCharacter.puki) {
      canvas.drawCircle(
        hipCenter.translate(-7.5 * u, -1 * u),
        4.2 * u,
        Paint()..color = Colors.white.withValues(alpha: 0.94),
      );
    }

    // ------------------------------------------------------------------
    // 3. Arms Targets (2-bone articulated shoulder -> elbow -> hand)
    // ------------------------------------------------------------------
    final lShoulder = shoulderCenter.translate(-10.5 * u, 3.0 * u);
    final rShoulder = shoulderCenter.translate(10.5 * u, 3.0 * u);

    late Offset lHandTarget;
    late Offset rHandTarget;
    double lBend = 1.0;
    double rBend = -1.0;

    if (happy) {
      // High cheerful wave with right hand!
      final wave = math.sin(p2 * 4.0) * 6.0 * u;
      lHandTarget = Offset(lShoulder.dx - 4.0 * u, lShoulder.dy + 16.0 * u);
      rHandTarget = Offset(rShoulder.dx + 8.0 * u + wave, headCenter.dy - 14.0 * u);
      rBend = 1.0;
    } else {
      switch (behavior) {
        case MascotBehavior.idle:
          final sway = math.sin(p2) * 2.5 * u;
          lHandTarget = Offset(lShoulder.dx - 4.0 * u, hipCenter.dy + 2.0 * u + sway);
          rHandTarget = Offset(rShoulder.dx + 4.0 * u, hipCenter.dy + 2.0 * u - sway);
          break;
        case MascotBehavior.patrol:
          // Arms swing in opposite phase to legs
          final armSwing = math.sin(walkCycle);
          lHandTarget = Offset(lShoulder.dx - armSwing * 11.0 * u, hipCenter.dy - 1.0 * u - armSwing.abs() * 2.0 * u);
          rHandTarget = Offset(rShoulder.dx + armSwing * 11.0 * u, hipCenter.dy - 1.0 * u - armSwing.abs() * 2.0 * u);
          lBend = armSwing >= 0 ? 1.0 : -1.0;
          rBend = armSwing >= 0 ? 1.0 : -1.0;
          break;
        case MascotBehavior.knock:
          // Right arm lifts high and knocks forward 3 times; left rests at side
          final burst = (phase * 2.0) % 1.0;
          final hit1 = math.exp(-math.pow((burst - 0.22) * 15, 2));
          final hit2 = math.exp(-math.pow((burst - 0.42) * 15, 2));
          final hit3 = math.exp(-math.pow((burst - 0.62) * 15, 2));
          final punch = (hit1 + hit2 + hit3).clamp(0.0, 1.0);
          lHandTarget = Offset(lShoulder.dx - 4.5 * u, hipCenter.dy + 1.0 * u);
          rHandTarget = Offset(
            cx + 8.0 * u + punch * 8.0 * u,
            headCenter.dy + 1.0 * u - punch * 4.0 * u,
          );
          rBend = 1.0;
          break;
        case MascotBehavior.think:
          // Right hand goes UP to forehead / temple; left arm crosses to hold elbow
          final scratch = math.sin(p2 * 2.0) * 1.4 * u;
          rHandTarget = Offset(headCenter.dx + 9.5 * u, headCenter.dy + 1.5 * u + scratch);
          lHandTarget = Offset(cx + 2.5 * u, shoulderCenter.dy + 11.5 * u);
          rBend = 1.0;
          lBend = -1.0;
          break;
        case MascotBehavior.read:
          // Pulls book up with both hands; right hand periodically reaches to turn page
          final pull = bookPull;
          final turnAmt = math.max(0.0, math.sin(p2 * 2.0));
          lHandTarget = Offset(
            ui.lerpDouble(lShoulder.dx - 3 * u, cx - 8.5 * u, pull)!,
            ui.lerpDouble(hipCenter.dy + 2 * u, shoulderCenter.dy + 11.5 * u, pull)!,
          );
          rHandTarget = Offset(
            ui.lerpDouble(rShoulder.dx + 4 * u, cx + 8.5 * u - turnAmt * 5.0 * u, pull)!,
            ui.lerpDouble(hipCenter.dy + 2 * u, shoulderCenter.dy + 11.5 * u - turnAmt * 2.5 * u, pull)!,
          );
          lBend = -1.0;
          rBend = 1.0;
          break;
        case MascotBehavior.deepSleep:
          lHandTarget = Offset.zero;
          rHandTarget = Offset.zero;
          break;
      }
    }

    final lElbow = _solveJoint(lShoulder, lHandTarget, 10.5 * u, 10.5 * u, lBend);
    final rElbow = _solveJoint(rShoulder, rHandTarget, 10.5 * u, 10.5 * u, rBend);

    // Draw back leg first
    _drawCapsuleLimb(canvas, lHip, lKnee, lFootTarget, 6.4 * u, Color.lerp(legTone, Colors.black, 0.16)!);
    final lBootRect = Rect.fromCenter(center: lFootTarget.translate(1.8 * u, 1.8 * u), width: 8.6 * u, height: 5.2 * u);
    canvas.drawOval(lBootRect, _spherePaint(lBootRect, Color.lerp(shoeColor, Colors.white, 0.28)!, shoeColor, Color.lerp(shoeColor, Colors.black, 0.45)!));

    // Draw back arm behind torso
    _drawCapsuleLimb(canvas, lShoulder, lElbow, lHandTarget, 5.4 * u, Color.lerp(limbColor, Colors.black, 0.14)!);
    final lHandRect = Rect.fromCenter(center: lHandTarget, width: 6.6 * u, height: 6.6 * u);
    canvas.drawOval(lHandRect, _spherePaint(lHandRect, Color.lerp(handColor, Colors.white, 0.35)!, handColor, Color.lerp(handColor, Colors.black, 0.32)!));

    // Draw front leg
    _drawCapsuleLimb(canvas, rHip, rKnee, rFootTarget, 6.8 * u, legTone);
    final rBootRect = Rect.fromCenter(center: rFootTarget.translate(1.8 * u, 1.8 * u), width: 8.8 * u, height: 5.4 * u);
    canvas.drawOval(rBootRect, _spherePaint(rBootRect, Color.lerp(shoeColor, Colors.white, 0.30)!, shoeColor, Color.lerp(shoeColor, Colors.black, 0.42)!));

    // ------------------------------------------------------------------
    // 4. Torso (3D Radial Lit Capsule + Neck Ambient Shadow + Emblem)
    // ------------------------------------------------------------------
    canvas.save();
    canvas.translate(hipCenter.dx, hipCenter.dy);
    canvas.rotate(torsoLean);
    final torsoRect = Rect.fromLTWH(-11.5 * u, -22.0 * u, 23.0 * u, 23.0 * u);
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, Radius.circular(9.5 * u)),
      _spherePaint(torsoRect, bodyLight, bodyPrimary, bodyDark),
    );
    // Neck occlusion shadow & soft specular rim highlight
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, -20.5 * u), width: 13 * u, height: 4.5 * u),
      Paint()..color = Colors.black.withValues(alpha: 0.28),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(torsoRect, Radius.circular(9.5 * u)),
      Paint()
        ..color = accent.withValues(alpha: 0.48)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * u,
    );

    if (character == MascotCharacter.termoBot) {
      // Glowing copper thermal coil core on robot chest
      canvas.drawCircle(Offset(0, -11.5 * u), 4.6 * u, Paint()..color = const Color(0xFF0F172A));
      canvas.drawCircle(
        Offset(0, -11.5 * u),
        3.5 * u,
        Paint()
          ..color = const Color(0xFFF97316)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * u,
      );
      canvas.drawCircle(Offset(0, -11.5 * u), 1.5 * u, Paint()..color = const Color(0xFF38BDF8));
    } else if (character == MascotCharacter.mirnav) {
      // Brass smart-thermostat collar medallion
      canvas.drawLine(Offset(-7 * u, -19.5 * u), Offset(7 * u, -19.5 * u), Paint()..color = const Color(0xFF1E293B)..strokeWidth = 2.4 * u);
      canvas.drawCircle(Offset(0, -16.5 * u), 3.1 * u, Paint()..color = const Color(0xFFFBBF24));
      canvas.drawCircle(Offset(0, -16.5 * u), 1.8 * u, Paint()..color = const Color(0xFF18181B));
    } else if (character == MascotCharacter.puki) {
      // Knitted plum scarf & glowing pink heart badge
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -19 * u), width: 17 * u, height: 5.5 * u), Radius.circular(3 * u)),
        Paint()..color = const Color(0xFF581C87),
      );
      canvas.drawCircle(Offset(3.5 * u, -18.8 * u), 2.1 * u, Paint()..color = const Color(0xFFF472B6));
    } else if (character == MascotCharacter.mert) {
      // Zip line + cyan smart-home house badge
      canvas.drawLine(Offset(0, -21 * u), Offset(0, -1 * u), Paint()..color = Colors.white.withValues(alpha: 0.22)..strokeWidth = 1.1 * u);
      canvas.drawCircle(Offset(4.5 * u, -13.5 * u), 2.3 * u, Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.85));
    } else if (character == MascotCharacter.ela) {
      // Glowing violet ambient pin
      canvas.drawCircle(Offset(4.2 * u, -13.5 * u), 2.3 * u, Paint()..color = const Color(0xFFC4B5FD));
    }
    canvas.restore();

    // ------------------------------------------------------------------
    // 5. Head (3D Lit + Expressive Animated Eyes/Eyelids/Ears/Hair)
    // ------------------------------------------------------------------
    canvas.save();
    canvas.translate(headCenter.dx, headCenter.dy);
    canvas.rotate(headTilt);
    _drawCharacterHead(
      canvas: canvas,
      u: u,
      headBase: headBase,
      headLight: headLight,
      headDark: headDark,
      eyesClosed: eyesClosed,
      eyeLook: eyeLook,
      mouthHappy: mouthHappy,
      mouthOpen: mouthOpen,
      phase: phase,
    );
    canvas.restore();

    // ------------------------------------------------------------------
    // 6. Open 3D Book Held In Front When Reading (Kitabı çıkarıp okuma hareketi)
    // ------------------------------------------------------------------
    if (behavior == MascotBehavior.read && bookPull > 0.08) {
      final bookCenter = Offset(cx + 2.5 * u, shoulderCenter.dy + 11.0 * u + (1.0 - bookPull) * 14.0 * u);
      _drawHeldOpenBook(canvas, bookCenter, u * bookPull, accent, pageFlip);
    }

    // ------------------------------------------------------------------
    // 7. Front Arm Drawn Over Chest / Holding Book / Touching Temple / Knocking
    // ------------------------------------------------------------------
    _drawCapsuleLimb(canvas, rShoulder, rElbow, rHandTarget, 5.6 * u, limbColor);
    final rHandRect = Rect.fromCenter(center: rHandTarget, width: 6.8 * u, height: 6.8 * u);
    canvas.drawOval(rHandRect, _spherePaint(rHandRect, Color.lerp(handColor, Colors.white, 0.38)!, handColor, Color.lerp(handColor, Colors.black, 0.30)!));
    canvas.drawCircle(rHandTarget.translate(-1.2 * u, -1.2 * u), 1.0 * u, Paint()..color = Colors.white.withValues(alpha: 0.55));

    // Knock glass pane & concentric ripples right at knuckle impact point
    if (showProps && behavior == MascotBehavior.knock) {
      final glassX = cx + 22.0 * u;
      canvas.drawLine(
        Offset(glassX, headCenter.dy - 14 * u),
        Offset(glassX, groundY - 6 * u),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(glassX, headCenter.dy - 14 * u),
            Offset(glassX, groundY - 6 * u),
            [Colors.transparent, Colors.white.withValues(alpha: 0.34), Colors.transparent],
            [0.0, 0.5, 1.0],
          )
          ..strokeWidth = 1.6 * u,
      );
      final burst = (phase * 2.0) % 1.0;
      for (final start in [0.20, 0.40, 0.60]) {
        final dt = burst - start;
        if (dt >= 0 && dt < 0.35) {
          final k = dt / 0.35;
          canvas.drawCircle(
            rHandTarget,
            (3.5 + k * 15.0) * u,
            Paint()
              ..color = accent.withValues(alpha: (1.0 - k) * 0.80)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.7 * u,
          );
        }
      }
    }

    canvas.restore(); // undo horizontal flip / rush scale before drawing unflipped clouds

    // ------------------------------------------------------------------
    // 8. Unflipped Scene Effects (Thought Cloud, Sparkles)
    // ------------------------------------------------------------------
    if (showProps && behavior == MascotBehavior.think) {
      final cloudSide = facingDirection >= 0 ? 1.0 : -1.0;
      final headWorldX = cx + (headCenter.dx - cx) * facingDirection * rushScale;
      final headWorldY = groundY + (headCenter.dy - groundY) * rushScale;
      _drawThoughtWisps(canvas, Offset(headWorldX + cloudSide * 18 * u, headWorldY - 12 * u), cloudSide, u, phase, accent);
    }
    if (showProps && happy) {
      _drawHappyStars(canvas, Offset(cx, headCenter.dy), u, phase, accent);
    }
  }

  void _drawCharacterHead({
    required Canvas canvas,
    required double u,
    required Color headBase,
    required Color headLight,
    required Color headDark,
    required bool eyesClosed,
    required Offset eyeLook,
    required bool mouthHappy,
    required bool mouthOpen,
    required double phase,
  }) {
    final p2 = phase * math.pi * 2;
    final earBounce = behavior == MascotBehavior.patrol ? math.sin(p2 * 2.0) * 0.14 : (behavior == MascotBehavior.deepSleep ? 0.35 : 0.0);

    switch (character) {
      case MascotCharacter.termoBot:
        // Beacon antenna
        canvas.drawLine(Offset(0, -13 * u), Offset(0, -19.5 * u), Paint()..color = headLight..strokeWidth = 1.8 * u);
        canvas.drawCircle(
          Offset(0, -20.5 * u),
          2.4 * u,
          Paint()..color = behavior == MascotBehavior.deepSleep ? const Color(0xFF64748B) : const Color(0xFFFBBF24),
        );
        // 3D Titanium helmet sphere
        final hRect = Rect.fromCenter(center: Offset.zero, width: 28 * u, height: 24 * u);
        canvas.drawRRect(RRect.fromRectAndRadius(hRect, Radius.circular(9.5 * u)), _spherePaint(hRect, headLight, headBase, headDark));
        // Dark sapphire visor glass
        final visor = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, 0.5 * u), width: 22 * u, height: 15 * u), Radius.circular(6 * u));
        canvas.drawRRect(visor, Paint()..color = const Color(0xFF06121E));
        canvas.drawRRect(visor, Paint()..color = accent.withValues(alpha: 0.72)..style = PaintingStyle.stroke..strokeWidth = 1.1 * u);
        _drawFaceEyesAndMouth(
          canvas: canvas,
          u: u,
          eyeColor: accent,
          irisColor: accent,
          eyesClosed: eyesClosed,
          eyeLook: eyeLook,
          mouthHappy: mouthHappy,
          mouthOpen: mouthOpen,
          isLed: true,
        );
        break;

      case MascotCharacter.mirnav:
        // Pointed 3D Cat Ears
        for (final sign in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(sign * 8.5 * u, -9.5 * u);
          canvas.rotate(sign * (0.12 + earBounce));
          final ear = Path()
            ..moveTo(-4.5 * u, 2 * u)
            ..lineTo(0, -8.5 * u)
            ..lineTo(4.5 * u, 2 * u)
            ..close();
          canvas.drawPath(ear, Paint()..color = headBase);
          final inner = Path()
            ..moveTo(-2.5 * u, 1.2 * u)
            ..lineTo(0, -5.5 * u)
            ..lineTo(2.5 * u, 1.2 * u)
            ..close();
          canvas.drawPath(inner, Paint()..color = const Color(0xFFFDA4AF));
          canvas.restore();
        }
        final catRect = Rect.fromCenter(center: Offset.zero, width: 26 * u, height: 23 * u);
        canvas.drawOval(catRect, _spherePaint(catRect, headLight, headBase, headDark));
        _drawFaceEyesAndMouth(
          canvas: canvas,
          u: u,
          eyeColor: Colors.white,
          irisColor: const Color(0xFFD97706),
          eyesClosed: eyesClosed,
          eyeLook: eyeLook,
          mouthHappy: mouthHappy,
          mouthOpen: mouthOpen,
          catWhiskers: true,
        );
        break;

      case MascotCharacter.puki:
        // Long floppy articulated bunny ears
        for (final sign in [-1.0, 1.0]) {
          canvas.save();
          canvas.translate(sign * 5.2 * u, -10.5 * u);
          canvas.rotate(sign * (0.14 + earBounce));
          final earRect = Rect.fromCenter(center: Offset(0, -7.5 * u), width: 6.5 * u, height: 16.5 * u);
          canvas.drawOval(earRect, _spherePaint(earRect, headLight, headBase, headDark));
          canvas.drawOval(Rect.fromCenter(center: Offset(0, -7.0 * u), width: 3.4 * u, height: 11.5 * u), Paint()..color = const Color(0xFFF9A8D4));
          canvas.restore();
        }
        final bunnyRect = Rect.fromCenter(center: Offset.zero, width: 25 * u, height: 22 * u);
        canvas.drawOval(bunnyRect, _spherePaint(bunnyRect, headLight, headBase, headDark));
        _drawFaceEyesAndMouth(
          canvas: canvas,
          u: u,
          eyeColor: Colors.white,
          irisColor: const Color(0xFF4C0519),
          eyesClosed: eyesClosed,
          eyeLook: eyeLook,
          mouthHappy: mouthHappy,
          mouthOpen: mouthOpen,
          pinkNose: true,
        );
        break;

      case MascotCharacter.mert:
        final mertRect = Rect.fromCenter(center: Offset.zero, width: 23 * u, height: 24 * u);
        canvas.drawOval(mertRect, _spherePaint(mertRect, headLight, headBase, headDark));
        // Sculpted dark hair quiff
        final hair = Path()
          ..moveTo(-11.5 * u, -3 * u)
          ..quadraticBezierTo(-11.5 * u, -15 * u, 0, -14.5 * u)
          ..quadraticBezierTo(12 * u, -14.5 * u, 11.5 * u, -3 * u)
          ..quadraticBezierTo(5 * u, -8.5 * u, -11.5 * u, -3 * u)
          ..close();
        canvas.drawPath(hair, Paint()..color = const Color(0xFF1E293B));
        // Glowing blue HUD earpiece
        canvas.drawCircle(Offset(11.5 * u, 0), 2.3 * u, Paint()..color = const Color(0xFF38BDF8));
        _drawFaceEyesAndMouth(
          canvas: canvas,
          u: u,
          eyeColor: Colors.white,
          irisColor: const Color(0xFF1E293B),
          eyesClosed: eyesClosed,
          eyeLook: eyeLook,
          mouthHappy: mouthHappy,
          mouthOpen: mouthOpen,
          brows: true,
        );
        break;

      case MascotCharacter.ela:
        // Chestnut bob hair back layer
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, 1.5 * u), width: 28 * u, height: 28 * u), Radius.circular(13 * u)),
          Paint()..color = const Color(0xFF451A03),
        );
        final elaRect = Rect.fromCenter(center: Offset.zero, width: 22.5 * u, height: 23.5 * u);
        canvas.drawOval(elaRect, _spherePaint(elaRect, headLight, headBase, headDark));
        // Hair fringe
        final fringe = Path()
          ..moveTo(-11.5 * u, -2 * u)
          ..quadraticBezierTo(-9 * u, -14 * u, 2 * u, -13.5 * u)
          ..quadraticBezierTo(11.5 * u, -13 * u, 11.5 * u, -1.5 * u)
          ..quadraticBezierTo(2 * u, -9.5 * u, -11.5 * u, -2 * u)
          ..close();
        canvas.drawPath(fringe, Paint()..color = const Color(0xFF5D2A0C));
        _drawFaceEyesAndMouth(
          canvas: canvas,
          u: u,
          eyeColor: Colors.white,
          irisColor: const Color(0xFF5D2A0C),
          eyesClosed: eyesClosed,
          eyeLook: eyeLook,
          mouthHappy: mouthHappy,
          mouthOpen: mouthOpen,
          brows: true,
        );
        break;
    }
  }

  void _drawFaceEyesAndMouth({
    required Canvas canvas,
    required double u,
    required Color eyeColor,
    required Color irisColor,
    required bool eyesClosed,
    required Offset eyeLook,
    required bool mouthHappy,
    required bool mouthOpen,
    bool isLed = false,
    bool brows = false,
    bool catWhiskers = false,
    bool pinkNose = false,
  }) {
    final eyeY = -1.2 * u;
    final spread = 4.6 * u;

    for (final sign in [-1.0, 1.0]) {
      final ex = sign * spread;
      if (eyesClosed) {
        // Closed curved sleeping / blinking eyelid
        canvas.drawArc(
          Rect.fromCenter(center: Offset(ex, eyeY + 0.8 * u), width: 4.8 * u, height: 3.0 * u),
          0.1,
          math.pi - 0.2,
          false,
          Paint()
            ..color = isLed ? eyeColor : const Color(0xFF1E293B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 * u
            ..strokeCap = StrokeCap.round,
        );
      } else if (isLed) {
        final ledCenter = Offset(ex + eyeLook.dx * 0.6, eyeY + eyeLook.dy * 0.6);
        if (mouthHappy) {
          canvas.drawArc(
            Rect.fromCenter(center: ledCenter.translate(0, 0.6 * u), width: 4.6 * u, height: 3.4 * u),
            math.pi,
            math.pi,
            false,
            Paint()
              ..color = eyeColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.9 * u
              ..strokeCap = StrokeCap.round,
          );
        } else {
          canvas.drawCircle(ledCenter, 2.3 * u, Paint()..color = eyeColor);
          canvas.drawCircle(ledCenter.translate(-0.6 * u, -0.7 * u), 0.7 * u, Paint()..color = Colors.white);
        }
      } else {
        // Expressive sclera + tracking iris + specular dot
        canvas.drawOval(Rect.fromCenter(center: Offset(ex, eyeY), width: 4.8 * u, height: 5.4 * u), Paint()..color = eyeColor);
        final pupilCenter = Offset(
          ex + (eyeLook.dx * 0.45).clamp(-1.1 * u, 1.1 * u),
          eyeY + (eyeLook.dy * 0.45).clamp(-1.1 * u, 1.1 * u),
        );
        canvas.drawCircle(pupilCenter, 1.75 * u, Paint()..color = irisColor);
        canvas.drawCircle(pupilCenter.translate(-0.5 * u, -0.6 * u), 0.65 * u, Paint()..color = Colors.white);
      }

      if (brows && !eyesClosed) {
        final browLift = behavior == MascotBehavior.think ? (sign > 0 ? -1.1 * u : 0.4 * u) : 0.0;
        canvas.drawLine(
          Offset(ex - 2.3 * u, eyeY - 3.8 * u + browLift),
          Offset(ex + 2.3 * u, eyeY - 3.8 * u),
          Paint()
            ..color = const Color(0xFF27170C)
            ..strokeWidth = 1.2 * u
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    if (catWhiskers) {
      canvas.drawCircle(Offset(0, 2.2 * u), 1.3 * u, Paint()..color = const Color(0xFFFB7185));
      final wPaint = Paint()..color = Colors.white.withValues(alpha: 0.78)..strokeWidth = 0.85 * u;
      canvas.drawLine(Offset(-5.5 * u, 2.0 * u), Offset(-11.5 * u, 1.0 * u), wPaint);
      canvas.drawLine(Offset(-5.5 * u, 3.2 * u), Offset(-11.0 * u, 3.8 * u), wPaint);
      canvas.drawLine(Offset(5.5 * u, 2.0 * u), Offset(11.5 * u, 1.0 * u), wPaint);
      canvas.drawLine(Offset(5.5 * u, 3.2 * u), Offset(11.0 * u, 3.8 * u), wPaint);
    } else if (pinkNose) {
      canvas.drawCircle(Offset(0, 1.8 * u), 1.4 * u, Paint()..color = const Color(0xFFF43F5E));
    }

    // Mouth
    final mY = 4.6 * u;
    if (mouthOpen) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, mY), width: 4.0 * u, height: 3.0 * u),
        Paint()..color = isLed ? eyeColor : const Color(0xFF7F1D1D),
      );
    } else {
      canvas.drawArc(
        Rect.fromCenter(center: Offset(0, mY - (mouthHappy ? 0.8 * u : 0.0)), width: 5.5 * u, height: 3.4 * u),
        0.18,
        math.pi - 0.36,
        false,
        Paint()
          ..color = isLed ? eyeColor : const Color(0xFF7C2D12)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3 * u
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawHeldOpenBook(Canvas canvas, Offset center, double u, Color accent, double pageFlip) {
    final bw = 20 * u;
    final bh = 13 * u;
    final leftPage = Path()
      ..moveTo(center.dx, center.dy + bh * 0.4)
      ..quadraticBezierTo(center.dx - bw * 0.25, center.dy + bh * 0.15, center.dx - bw * 0.50, center.dy + bh * 0.28)
      ..lineTo(center.dx - bw * 0.45, center.dy - bh * 0.55)
      ..quadraticBezierTo(center.dx - bw * 0.22, center.dy - bh * 0.65, center.dx, center.dy - bh * 0.35)
      ..close();

    final rightPage = Path()
      ..moveTo(center.dx, center.dy + bh * 0.4)
      ..quadraticBezierTo(center.dx + bw * 0.25, center.dy + bh * 0.15, center.dx + bw * 0.50, center.dy + bh * 0.28)
      ..lineTo(center.dx + bw * 0.45, center.dy - bh * 0.55)
      ..quadraticBezierTo(center.dx + bw * 0.22, center.dy - bh * 0.65, center.dx, center.dy - bh * 0.35)
      ..close();

    // Soft glowing page light onto reader's face
    canvas.drawOval(
      Rect.fromCenter(center: center.translate(0, -bh * 0.2), width: bw * 1.15, height: bh * 1.4),
      Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFF7DD3FC).withValues(alpha: 0.25), Colors.transparent],
        ).createShader(Rect.fromCenter(center: center, width: bw * 1.2, height: bh * 1.5)),
    );

    final cover = Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.stroke..strokeWidth = 2.0 * u;
    canvas.drawPath(leftPage, Paint()..color = const Color(0xFFE0F2FE));
    canvas.drawPath(rightPage, Paint()..color = const Color(0xFFF0F9FF));
    canvas.drawPath(leftPage, Paint()..color = accent.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0 * u);
    canvas.drawPath(rightPage, Paint()..color = accent.withValues(alpha: 0.85)..style = PaintingStyle.stroke..strokeWidth = 1.0 * u);
    canvas.drawLine(Offset(center.dx, center.dy + bh * 0.42), Offset(center.dx, center.dy - bh * 0.35), cover);

    // Readable text lines on left and right pages
    final linePaint = Paint()..color = const Color(0xFF0369A1).withValues(alpha: 0.45)..strokeWidth = 0.85 * u..strokeCap = StrokeCap.round;
    for (int row = 0; row < 3; row++) {
      final ly = center.dy - bh * 0.25 + row * (bh * 0.18);
      canvas.drawLine(Offset(center.dx - bw * 0.36, ly), Offset(center.dx - bw * 0.10, ly - 0.6 * u), linePaint);
      canvas.drawLine(Offset(center.dx + bw * 0.10, ly - 0.6 * u), Offset(center.dx + bw * 0.36, ly), linePaint);
    }

    // Turning page animation
    final flipX = center.dx + (0.5 - pageFlip) * bw * 0.72;
    final turn = Path()
      ..moveTo(center.dx, center.dy + bh * 0.4)
      ..quadraticBezierTo((center.dx + flipX) * 0.5, center.dy - bh * 0.2, flipX, center.dy + bh * 0.15)
      ..lineTo(flipX, center.dy - bh * 0.55)
      ..quadraticBezierTo((center.dx + flipX) * 0.5, center.dy - bh * 0.70, center.dx, center.dy - bh * 0.35)
      ..close();
    canvas.drawPath(turn, Paint()..color = Colors.white.withValues(alpha: 0.65));
  }

  void _drawThoughtWisps(Canvas canvas, Offset center, double side, double u, double phase, Color accent) {
    final bob = math.sin(phase * math.pi * 2) * 2.5 * u;
    final p1 = center.translate(-side * 8 * u, 9 * u + bob * 0.3);
    final p2 = center.translate(-side * 4 * u, 4 * u + bob * 0.6);
    final fill = Paint()..color = Colors.white.withValues(alpha: 0.22);
    final rim = Paint()..color = accent.withValues(alpha: 0.78)..style = PaintingStyle.stroke..strokeWidth = 1.1 * u;
    canvas.drawCircle(p1, 2.0 * u, fill);
    canvas.drawCircle(p1, 2.0 * u, rim);
    canvas.drawCircle(p2, 3.0 * u, fill);
    canvas.drawCircle(p2, 3.0 * u, rim);

    final cloud = center.translate(0, -4 * u + bob);
    final cw = 18 * u;
    final path = Path()
      ..addOval(Rect.fromCenter(center: cloud, width: cw, height: cw * 0.62))
      ..addOval(Rect.fromCenter(center: cloud.translate(-cw * 0.26, 1.5 * u), width: cw * 0.56, height: cw * 0.46))
      ..addOval(Rect.fromCenter(center: cloud.translate(cw * 0.24, 1.5 * u), width: cw * 0.52, height: cw * 0.44));
    canvas.drawPath(path, Paint()..color = const Color(0xFF0F172A).withValues(alpha: 0.90));
    canvas.drawPath(path, rim);
    for (int i = -1; i <= 1; i++) {
      final pulse = 0.4 + 0.6 * math.sin(phase * math.pi * 4 - i * 0.8).abs();
      canvas.drawCircle(cloud.translate(i * 4.0 * u, 0), 1.4 * u, Paint()..color = const Color(0xFFFBBF24).withValues(alpha: pulse));
    }
  }

  void _drawFloatingZzz(Canvas canvas, Offset origin, double u, double phase) {
    final letters = ['z', 'Z', 'z'];
    for (int i = 0; i < 3; i++) {
      final t = (phase + i * 0.33) % 1.0;
      final alpha = math.sin(t * math.pi).clamp(0.0, 1.0);
      final x = origin.dx + i * 5.5 * u + math.sin(t * math.pi * 2) * 3.0 * u;
      final y = origin.dy - t * 22.0 * u;
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: TextStyle(
            fontSize: ((8.0 + t * 4.5) * u).clamp(8.0, 20.0),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF93C5FD).withValues(alpha: alpha * 0.95),
            shadows: const [Shadow(color: Colors.black87, blurRadius: 5)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x, y));
    }
  }

  void _drawHappyStars(Canvas canvas, Offset center, double u, double phase, Color accent) {
    for (int i = 0; i < 5; i++) {
      final a = i * (math.pi * 2 / 5) + phase * math.pi * 2;
      final pt = center.translate(math.cos(a) * 20 * u, math.sin(a) * 16 * u);
      canvas.drawCircle(pt, 1.8 * u, Paint()..color = (i.isEven ? const Color(0xFFFBBF24) : accent));
    }
  }

  @override
  bool shouldRepaint(covariant _RiggedMascotPainter oldDelegate) =>
      oldDelegate.character != character ||
      oldDelegate.accent != accent ||
      oldDelegate.behavior != behavior ||
      oldDelegate.happy != happy ||
      oldDelegate.phase != phase ||
      oldDelegate.facingDirection != facingDirection ||
      oldDelegate.showProps != showProps;
}

/// Interactive preview stage in Settings for testing all 6 mascot physical animations, wallpapers & size.
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
      return tr ? '✨ El Sallıyor · Uyandı!' : '✨ Waving · Awake!';
    }
    switch (b) {
      case MascotBehavior.idle:
        return tr ? 'Boşta · Göz Kırpıyor' : 'Idle · Ready';
      case MascotBehavior.patrol:
        return tr ? 'Yürüyor · Adım Döngüsü' : 'Walking · Patrol';
      case MascotBehavior.knock:
        return tr ? 'Elini Kaldırıp Camı Tıklatıyor' : 'Knocking on Glass';
      case MascotBehavior.think:
        return tr ? 'Elini Başına Götürüp Düşünüyor' : 'Hand on Head · Thinking';
      case MascotBehavior.read:
        return tr ? 'Kitabı Çıkarıp Okuyor' : 'Pulling Book & Reading';
      case MascotBehavior.deepSleep:
        return tr ? 'Yere Uzandı · Gözler Kapalı (%50 Kısık)' : 'Lying Asleep (50% Dim)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = MascotMeta.of(widget.character);
    final tr = widget.lang == LangCode.tr;
    final hasCustomBg = widget.backdrop == ScreensaverBackdrop.custom && widget.customBgSource.trim().isNotEmpty;
    final effectiveBehavior = _wakingUp ? MascotBehavior.idle : widget.behavior;
    final scaledSize = (98.0 * widget.mascotScale).clamp(58.0, 146.0);
    final scalePct = (widget.mascotScale * 100).round();

    return GestureDetector(
      onTap: _triggerWake,
      child: Container(
        height: 252,
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

              // 4b) Behavior status pill fixed cleanly in upper stage band so it never overlaps mascot head/knock/thought
              Positioned(
                top: 40,
                left: 10,
                right: 10,
                child: Center(
                  child: Container(
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
                ),
              ),

              // 5) Center articulated full-body Mascot unobstructed on floor
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (context, _) {
                      final angle = _anim.value * math.pi * 2;
                      final patrolDx = effectiveBehavior == MascotBehavior.patrol
                          ? math.sin(angle) * 72.0
                          : 0.0;
                      final facingDir = effectiveBehavior == MascotBehavior.patrol
                          ? (math.cos(angle) >= 0 ? 1.0 : -1.0)
                          : 1.0;

                      return Transform.translate(
                        offset: Offset(patrolDx, 0.0),
                        child: MascotAvatar(
                          character: widget.character,
                          size: scaledSize,
                          behavior: effectiveBehavior,
                          sleeping: effectiveBehavior == MascotBehavior.deepSleep,
                          happy: _wakingUp,
                          phase: _anim.value,
                          facingDirection: facingDir,
                          frameless: true,
                        ),
                      );
                    },
                  ),
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
    final scaledSize = (82.0 * widget.mascotScale).clamp(48.0, 132.0);

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
                    margin: const EdgeInsets.only(bottom: 4),
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

  /// Generates 3 shuffled cycles of all non-sleep animations (each repeating 3 times).
  static List<MascotBehavior> buildBehaviorSequence([math.Random? rng]) {
    final random = rng ?? math.Random();
    const pool = [
      MascotBehavior.patrol,
      MascotBehavior.knock,
      MascotBehavior.think,
      MascotBehavior.read,
    ];
    final plan = <MascotBehavior>[];
    for (int cycle = 0; cycle < 3; cycle++) {
      final batch = List<MascotBehavior>.from(pool)..shuffle(random);
      if (plan.isNotEmpty && batch.first == plan.last && batch.length > 1) {
        final swap = batch.first;
        batch[0] = batch[batch.length - 1];
        batch[batch.length - 1] = swap;
      }
      plan.addAll(batch);
    }
    return plan;
  }

  @override
  State<FullscreenScreensaverOverlay> createState() => _FullscreenScreensaverOverlayState();
}

class _FullscreenScreensaverOverlayState extends State<FullscreenScreensaverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late Timer _clockTimer;
  final math.Random _rng = math.Random();
  DateTime _now = DateTime.now();
  bool _happy = false;
  bool _sleepDimmed = false;
  String? _reactionText;
  Timer? _reactionTimer;
  Timer? _behaviorTimer;
  List<MascotBehavior> _behaviorPlan = const [];
  int _stepIndex = 0;
  MascotBehavior _currentBehavior = MascotBehavior.patrol;
  double _patrolDx = 0.0;
  double _facingDir = 1.0;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200))
      ..addListener(() {
        final angle = _anim.value * math.pi * 2;
        final targetDx = _currentBehavior == MascotBehavior.patrol && !_happy
            ? math.sin(angle) * 58.0
            : 0.0;
        _patrolDx += (targetDx - _patrolDx) * 0.12;
        if (_currentBehavior == MascotBehavior.patrol && !_happy) {
          _facingDir = math.cos(angle) >= 0 ? 1.0 : -1.0;
        } else {
          _facingDir = 1.0;
        }
      })
      ..repeat();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    if (widget.soundsEnabled) {
      AmbientAudioService.playMascotSound(widget.character);
    }
    _startBehaviorSequence();
  }

  void _startBehaviorSequence() {
    _behaviorTimer?.cancel();
    _behaviorPlan = FullscreenScreensaverOverlay.buildBehaviorSequence(_rng);
    _stepIndex = 0;
    if (_sleepDimmed) {
      _sleepDimmed = false;
      HardwareService.exitSmartDisplayHardware();
    }
    _advanceBehaviorStep();
  }

  void _advanceBehaviorStep() {
    if (!mounted) return;
    if (_stepIndex >= _behaviorPlan.length) {
      setState(() {
        _currentBehavior = MascotBehavior.deepSleep;
        _sleepDimmed = true;
      });
      HardwareService.updateSmartDisplayBrightness(18);
      if (widget.soundsEnabled) {
        AmbientAudioService.playMascotSound(widget.character, sleepy: true);
      }
      return;
    }

    final nextBehavior = _behaviorPlan[_stepIndex];
    _stepIndex++;
    setState(() {
      _currentBehavior = nextBehavior;
      _sleepDimmed = false;
    });

    // Random 3–4 seconds per behavior before advancing to next random move
    final durationMs = 3000 + _rng.nextInt(1001);
    _behaviorTimer?.cancel();
    _behaviorTimer = Timer(Duration(milliseconds: durationMs), _advanceBehaviorStep);
  }

  @override
  void dispose() {
    _behaviorTimer?.cancel();
    _reactionTimer?.cancel();
    _clockTimer.cancel();
    _anim.dispose();
    if (_sleepDimmed) {
      HardwareService.exitSmartDisplayHardware();
    }
    super.dispose();
  }

  void _handleExit() {
    if (_sleepDimmed) {
      HardwareService.exitSmartDisplayHardware();
    }
    widget.onExit();
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
    if (_sleepDimmed) {
      HardwareService.exitSmartDisplayHardware();
    }
    final isHeating = widget.boiler?.isHeating ?? (widget.targetTemp > widget.roomTemp + 0.1);
    _behaviorTimer?.cancel();
    setState(() {
      _happy = true;
      _sleepDimmed = false;
      _currentBehavior = MascotBehavior.idle;
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
        _startBehaviorSequence();
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
    final scaledSize = (146.0 * widget.mascotScale).clamp(90.0, 234.0);
    final cycleNum = _currentBehavior == MascotBehavior.deepSleep
        ? 3
        : (((_stepIndex - 1).clamp(0, 11) ~/ 4) + 1);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleExit,
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

              // 4) Foreground clock, articulated animated mascot (tappable to pet), and live telemetry
              Center(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (context, _) {
                    final oledShiftX = ((_now.minute % 3) - 1) * 4.0;
                    final oledShiftY = ((_now.minute % 5) - 2) * 2.0;

                    return Transform.translate(
                      offset: Offset(oledShiftX, oledShiftY),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$hh:$mm',
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2.0,
                              color: Colors.white.withValues(alpha: _sleepDimmed ? 0.56 : 0.90),
                              fontFeatures: const [FontFeature.tabularFigures()],
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Transform.translate(
                            offset: Offset(_patrolDx, 0.0),
                            child: GestureDetector(
                              onTap: _petMascot,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_reactionText != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 8),
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
                                    behavior: _currentBehavior,
                                    sleeping: _currentBehavior == MascotBehavior.deepSleep,
                                    happy: _happy,
                                    phase: _anim.value,
                                    facingDirection: _facingDir,
                                    frameless: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _sleepDimmed
                                ? '${meta.name} · ${tr ? 'Uyku Modu (%50 Kısık)' : 'Sleep Mode (Dimmed)'}'
                                : '${meta.name} · ${tr ? meta.roleTr : meta.roleEn} ($cycleNum/3)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: _sleepDimmed ? 0.65 : 1.0),
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

              // 5) Smooth night-sleep dimming veil when deep sleep engages after 3 cycles
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _sleepDimmed ? 0.50 : 0.0,
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeInOut,
                  child: const ColoredBox(color: Colors.black),
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
