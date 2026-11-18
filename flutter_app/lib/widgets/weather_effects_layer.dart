import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/thermostat_state.dart';

class WeatherEffectsLayer extends StatefulWidget {
  final WeatherEffectPreview preview;
  final PerformanceMode performanceMode;
  final bool isLightTheme;

  const WeatherEffectsLayer({
    super.key,
    required this.preview,
    required this.performanceMode,
    required this.isLightTheme,
  });

  @override
  State<WeatherEffectsLayer> createState() => _WeatherEffectsLayerState();
}

class _WeatherEffectsLayerState extends State<WeatherEffectsLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _timeSec = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        _timeSec = elapsed.inMicroseconds / 1000000.0;
      });
    });
    if (widget.performanceMode == PerformanceMode.ultra60fps) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant WeatherEffectsLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.performanceMode == PerformanceMode.ecoBattery) {
      if (_ticker.isActive) _ticker.stop();
    } else {
      if (!_ticker.isActive) _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effective = widget.preview == WeatherEffectPreview.live
        ? WeatherEffectPreview.partlyCloudy
        : widget.preview;

    return IgnorePointer(
      child: CustomPaint(
        painter: _WeatherPainter(
          effect: effective,
          timeSec: widget.performanceMode == PerformanceMode.ecoBattery ? 2.4 : _timeSec,
          isEco: widget.performanceMode == PerformanceMode.ecoBattery,
          isLightTheme: widget.isLightTheme,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  final WeatherEffectPreview effect;
  final double timeSec;
  final bool isEco;
  final bool isLightTheme;

  const _WeatherPainter({
    required this.effect,
    required this.timeSec,
    required this.isEco,
    required this.isLightTheme,
  });

  double _hash(int i) {
    final x = math.sin(i * 127.1 + 311.7) * 43758.5453123;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (effect) {
      case WeatherEffectPreview.sunny:
        _paintSunny(canvas, size);
        break;
      case WeatherEffectPreview.partlyCloudy:
      case WeatherEffectPreview.live:
        _paintPartlyCloudy(canvas, size);
        break;
      case WeatherEffectPreview.rainy:
        _paintRain(canvas, size);
        break;
      case WeatherEffectPreview.snowy:
        _paintSnow(canvas, size);
        break;
      case WeatherEffectPreview.foggy:
        _paintFog(canvas, size);
        break;
    }
  }

  void _paintSunny(Canvas canvas, Size size) {
    final sunCenter = Offset(size.width * 0.84, size.height * 0.14);
    final pulse = 1.0 + 0.08 * math.sin(timeSec * 0.9);
    final sunPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFBBF24).withValues(alpha: isLightTheme ? 0.30 : 0.20),
          const Color(0xFFF59E0B).withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: sunCenter, radius: 210 * pulse));
    canvas.drawCircle(sunCenter, 210 * pulse, sunPaint);

    if (isEco) return;
    final motePaint = Paint()..color = const Color(0xFFFDE68A).withValues(alpha: 0.20);
    for (int i = 0; i < 14; i++) {
      final bx = _hash(i) * size.width;
      final by = _hash(i + 40) * size.height * 0.7;
      final dx = math.sin(timeSec * 0.5 + i) * 14;
      final dy = math.cos(timeSec * 0.4 + i * 0.7) * 10;
      canvas.drawCircle(Offset(bx + dx, by + dy), 1.6 + _hash(i + 9) * 1.4, motePaint);
    }
  }

  void _paintPartlyCloudy(Canvas canvas, Size size) {
    final cloudBase = isLightTheme
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFF93C5FD).withValues(alpha: 0.06);
    final count = isEco ? 2 : 4;
    for (int i = 0; i < count; i++) {
      final speed = 10.0 + i * 4.5;
      final x = ((_hash(i * 3) * size.width + timeSec * speed) % (size.width + 260)) - 130;
      final y = size.height * (0.12 + i * 0.09);
      final r = 75.0 + i * 22.0;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [cloudBase, Colors.transparent],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: r));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final dropPaint = Paint()
      ..color = (isLightTheme ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC))
          .withValues(alpha: isLightTheme ? 0.24 : 0.16)
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round;

    final count = isEco ? 14 : 34;
    for (int i = 0; i < count; i++) {
      final speed = 260.0 + _hash(i + 12) * 180.0;
      final x = ((_hash(i) * size.width) - timeSec * 45) % size.width;
      final y = ((_hash(i + 100) * size.height) + timeSec * speed) % (size.height + 40) - 20;
      final len = 12.0 + _hash(i + 200) * 12.0;
      canvas.drawLine(Offset(x, y), Offset(x - 3.0, y + len), dropPaint);
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final flakePaint = Paint()
      ..color = (isLightTheme ? const Color(0xFF475569) : Colors.white)
          .withValues(alpha: isLightTheme ? 0.26 : 0.24);

    final count = isEco ? 12 : 28;
    for (int i = 0; i < count; i++) {
      final speed = 38.0 + _hash(i + 17) * 32.0;
      final baseX = _hash(i) * size.width;
      final sway = math.sin(timeSec * 1.4 + i) * 14.0;
      final x = (baseX + sway) % size.width;
      final y = ((_hash(i + 88) * size.height) + timeSec * speed) % (size.height + 20) - 10;
      final r = 1.6 + _hash(i + 55) * 2.1;
      canvas.drawCircle(Offset(x, y), r, flakePaint);
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    final fogColor = isLightTheme
        ? Colors.white.withValues(alpha: 0.30)
        : const Color(0xFFCBD5E1).withValues(alpha: 0.06);
    final bands = isEco ? 2 : 4;
    for (int i = 0; i < bands; i++) {
      final y = size.height * (0.18 + i * 0.18);
      final drift = math.sin(timeSec * 0.3 + i * 1.5) * 35.0;
      final rect = Rect.fromCenter(center: Offset(size.width * 0.5 + drift, y), width: size.width * 1.3, height: 110);
      final paint = Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, fogColor, Colors.transparent],
        ).createShader(rect);
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherPainter oldDelegate) =>
      oldDelegate.effect != effect ||
      oldDelegate.timeSec != timeSec ||
      oldDelegate.isEco != isEco ||
      oldDelegate.isLightTheme != isLightTheme;
}
