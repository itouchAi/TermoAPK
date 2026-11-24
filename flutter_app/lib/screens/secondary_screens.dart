import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/notification_service.dart';

enum _WeatherAnimKind {
  rain,
  storm,
  snow,
  sun,
  partlyCloudy,
  cloudy,
  fog,
  clearNight,
}

_WeatherAnimKind _resolveWeatherAnimKind({
  required String conditionTr,
  required String conditionEn,
  required IconData fallbackIcon,
}) {
  final raw = '${conditionTr.toLowerCase()} ${conditionEn.toLowerCase()}';
  if (raw.contains('fırtına') ||
      raw.contains('gök') ||
      raw.contains('thunder') ||
      raw.contains('storm')) {
    return _WeatherAnimKind.storm;
  }
  if (raw.contains('kar') || raw.contains('snow') || raw.contains('sleet') || raw.contains('ayaz')) {
    return _WeatherAnimKind.snow;
  }
  if (raw.contains('yağmur') ||
      raw.contains('sağanak') ||
      raw.contains('çisenti') ||
      raw.contains('rain') ||
      raw.contains('shower') ||
      raw.contains('drizzle')) {
    return _WeatherAnimKind.rain;
  }
  if (raw.contains('sis') || raw.contains('pus') || raw.contains('fog') || raw.contains('mist')) {
    return _WeatherAnimKind.fog;
  }
  if (raw.contains('parçalı') || raw.contains('partly')) {
    return _WeatherAnimKind.partlyCloudy;
  }
  if (raw.contains('güneş') || raw.contains('sun')) {
    return _WeatherAnimKind.sun;
  }
  if (raw.contains('bulut') || raw.contains('cloud') || raw.contains('overcast')) {
    return _WeatherAnimKind.cloudy;
  }
  if (raw.contains('serin') || raw.contains('soğuk') || raw.contains('night') || raw.contains('clear') || raw.contains('açık')) {
    if (fallbackIcon == Icons.wb_sunny_outlined) return _WeatherAnimKind.sun;
    return _WeatherAnimKind.clearNight;
  }
  if (fallbackIcon == Icons.thunderstorm_outlined) return _WeatherAnimKind.storm;
  if (fallbackIcon == Icons.ac_unit_rounded) return _WeatherAnimKind.snow;
  if (fallbackIcon == Icons.water_drop_outlined || fallbackIcon == Icons.umbrella_outlined) {
    return _WeatherAnimKind.rain;
  }
  if (fallbackIcon == Icons.blur_on_rounded) return _WeatherAnimKind.fog;
  if (fallbackIcon == Icons.wb_cloudy_outlined) return _WeatherAnimKind.partlyCloudy;
  if (fallbackIcon == Icons.wb_sunny_outlined) return _WeatherAnimKind.sun;
  if (fallbackIcon == Icons.nights_stay_outlined) return _WeatherAnimKind.clearNight;
  return _WeatherAnimKind.cloudy;
}

class _AnimatedWeatherIcon extends StatelessWidget {
  final String conditionTr;
  final String conditionEn;
  final IconData fallbackIcon;
  final double size;
  final Color color;
  final Animation<double> animation;
  final bool selected;

  const _AnimatedWeatherIcon({
    required this.conditionTr,
    required this.conditionEn,
    required this.fallbackIcon,
    required this.size,
    required this.color,
    required this.animation,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = _resolveWeatherAnimKind(
      conditionTr: conditionTr,
      conditionEn: conditionEn,
      fallbackIcon: fallbackIcon,
    );
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => CustomPaint(
          painter: _WeatherSymbolPainter(
            kind: kind,
            phase: animation.value,
            color: color,
            selected: selected,
          ),
        ),
      ),
    );
  }
}

class _WeatherSymbolPainter extends CustomPainter {
  final _WeatherAnimKind kind;
  final double phase;
  final Color color;
  final bool selected;

  const _WeatherSymbolPainter({
    required this.kind,
    required this.phase,
    required this.color,
    required this.selected,
  });

  Path _cloudPath(Size s, {double dx = 0, double dy = 0, double scale = 1.0}) {
    final w = s.width * scale;
    final h = s.height * scale;
    final ox = (s.width - w) * 0.5 + dx;
    final oy = dy;
    final p = Path();
    p.moveTo(ox + w * 0.28, oy + h * 0.64);
    p.lineTo(ox + w * 0.74, oy + h * 0.64);
    p.cubicTo(
      ox + w * 0.88,
      oy + h * 0.64,
      ox + w * 0.92,
      oy + h * 0.44,
      ox + w * 0.78,
      oy + h * 0.40,
    );
    p.cubicTo(
      ox + w * 0.78,
      oy + h * 0.22,
      ox + w * 0.56,
      oy + h * 0.16,
      ox + w * 0.46,
      oy + h * 0.28,
    );
    p.cubicTo(
      ox + w * 0.34,
      oy + h * 0.20,
      ox + w * 0.18,
      oy + h * 0.30,
      ox + w * 0.21,
      oy + h * 0.42,
    );
    p.cubicTo(
      ox + w * 0.10,
      oy + h * 0.46,
      ox + w * 0.14,
      oy + h * 0.64,
      ox + w * 0.28,
      oy + h * 0.64,
    );
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = (size.width * 0.088).clamp(1.4, 2.3);
    final cloudPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final t = phase * math.pi * 2.0;

    switch (kind) {
      case _WeatherAnimKind.rain:
        final bobY = math.sin(t) * size.height * 0.03;
        canvas.drawPath(_cloudPath(size, dy: -size.height * 0.06 + bobY), cloudPaint);
        final dropPaint = Paint()
          ..color = selected ? Colors.white : const Color(0xFF38BDF8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeW * 0.92).clamp(1.3, 2.1)
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final p = (phase * 1.4 + i * 0.33) % 1.0;
          final x = size.width * (0.31 + i * 0.19) - p * size.width * 0.05;
          final yStart = size.height * 0.62 + p * size.height * 0.24;
          final alpha = math.sin(p * math.pi).clamp(0.15, 1.0);
          dropPaint.color = (selected ? Colors.white : const Color(0xFF38BDF8)).withValues(alpha: alpha);
          canvas.drawLine(
            Offset(x, yStart),
            Offset(x - size.width * 0.04, yStart + size.height * 0.14),
            dropPaint,
          );
        }
        break;

      case _WeatherAnimKind.storm:
        final bobX = math.sin(t * 2) * size.width * 0.025;
        canvas.drawPath(_cloudPath(size, dx: bobX, dy: -size.height * 0.08), cloudPaint);
        final flash = (math.sin(t * 3.0) > 0.2) ? 1.0 : 0.45;
        final boltPaint = Paint()
          ..color = (selected ? const Color(0xFFFEF08A) : const Color(0xFFFBBF24)).withValues(alpha: flash)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeW * 1.05).clamp(1.5, 2.5)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final bolt = Path()
          ..moveTo(size.width * 0.54, size.height * 0.54)
          ..lineTo(size.width * 0.44, size.height * 0.73)
          ..lineTo(size.width * 0.54, size.height * 0.73)
          ..lineTo(size.width * 0.46, size.height * 0.92);
        canvas.drawPath(bolt, boltPaint);
        break;

      case _WeatherAnimKind.snow:
        final snowColor = selected ? Colors.white : const Color(0xFFBAE6FD);
        final flakePaint = Paint()
          ..color = snowColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeW * 0.78).clamp(1.2, 1.8)
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final p = (phase + i * 0.34) % 1.0;
          final cx = size.width * (0.28 + i * 0.22) + math.sin((phase + i * 0.4) * math.pi * 2) * size.width * 0.06;
          final cy = size.height * (0.20 + p * 0.66);
          final r = size.width * 0.09;
          final alpha = math.sin(p * math.pi).clamp(0.25, 1.0);
          flakePaint.color = snowColor.withValues(alpha: alpha);
          final rot = t + i;
          for (int k = 0; k < 3; k++) {
            final a = rot + k * (math.pi / 3.0);
            canvas.drawLine(
              Offset(cx - math.cos(a) * r, cy - math.sin(a) * r),
              Offset(cx + math.cos(a) * r, cy + math.sin(a) * r),
              flakePaint,
            );
          }
        }
        break;

      case _WeatherAnimKind.sun:
        final sunColor = selected ? const Color(0xFFFEF08A) : const Color(0xFFFBBF24);
        final sunPaint = Paint()
          ..color = sunColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round;
        final center = Offset(size.width * 0.5, size.height * 0.5);
        final coreR = size.width * (0.21 + 0.02 * math.sin(t));
        canvas.drawCircle(center, coreR, sunPaint);
        for (int i = 0; i < 8; i++) {
          final a = t * 0.5 + i * (math.pi / 4.0);
          final r1 = size.width * 0.31;
          final r2 = size.width * 0.42;
          canvas.drawLine(
            Offset(center.dx + math.cos(a) * r1, center.dy + math.sin(a) * r1),
            Offset(center.dx + math.cos(a) * r2, center.dy + math.sin(a) * r2),
            sunPaint,
          );
        }
        break;

      case _WeatherAnimKind.partlyCloudy:
        final sunColor = selected ? const Color(0xFFFEF08A) : const Color(0xFFFBBF24);
        final sunCenter = Offset(size.width * 0.33, size.height * 0.34);
        final sunPaint = Paint()
          ..color = sunColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = (strokeW * 0.86).clamp(1.2, 2.0)
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(sunCenter, size.width * 0.14, sunPaint);
        for (int i = 0; i < 5; i++) {
          final a = t * 0.45 + i * (math.pi / 2.6) - math.pi * 0.9;
          canvas.drawLine(
            Offset(sunCenter.dx + math.cos(a) * size.width * 0.21, sunCenter.dy + math.sin(a) * size.width * 0.21),
            Offset(sunCenter.dx + math.cos(a) * size.width * 0.27, sunCenter.dy + math.sin(a) * size.width * 0.27),
            sunPaint,
          );
        }
        final drift = math.sin(t) * size.width * 0.04;
        canvas.drawPath(_cloudPath(size, dx: drift + size.width * 0.05, dy: size.height * 0.08, scale: 0.88), cloudPaint);
        break;

      case _WeatherAnimKind.cloudy:
        final drift = math.sin(t) * size.width * 0.045;
        canvas.drawPath(_cloudPath(size, dx: drift, dy: size.height * 0.04), cloudPaint);
        break;

      case _WeatherAnimKind.fog:
        final fogPaint = Paint()
          ..color = color.withValues(alpha: 0.88)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 3; i++) {
          final shift = math.sin(t + i * 1.4) * size.width * 0.08;
          final y = size.height * (0.34 + i * 0.17);
          canvas.drawLine(
            Offset(size.width * 0.20 + shift, y),
            Offset(size.width * 0.80 + shift, y),
            fogPaint,
          );
        }
        break;

      case _WeatherAnimKind.clearNight:
        final moonPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final moon = Path()
          ..addArc(
            Rect.fromCircle(center: Offset(size.width * 0.5, size.height * 0.52), radius: size.width * 0.27),
            -math.pi * 0.35,
            math.pi * 1.38,
          );
        canvas.drawPath(moon, moonPaint);
        final starAlpha = (0.4 + 0.6 * (0.5 + 0.5 * math.sin(t * 2.0))).clamp(0.25, 1.0);
        final starPaint = Paint()..color = (selected ? Colors.white : const Color(0xFFFDE68A)).withValues(alpha: starAlpha);
        canvas.drawCircle(Offset(size.width * 0.68, size.height * 0.30), size.width * 0.045, starPaint);
        canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.44), size.width * 0.032, starPaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherSymbolPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}

class _BlurredDepthSubTabSwitcher extends StatelessWidget {
  final Widget child;
  final bool disableBlur;

  const _BlurredDepthSubTabSwitcher({
    required this.child,
    this.disableBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (childWidget, anim) {
        final isIncoming = childWidget.key == child.key;
        final scale = Tween<double>(
          begin: isIncoming ? 0.97 : 0.91,
          end: 1.0,
        ).animate(anim);
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        Widget content = FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: childWidget,
          ),
        );
        if (!disableBlur) {
          content = AnimatedBuilder(
            animation: anim,
            builder: (_, built) {
              final sigma = ((1.0 - anim.value) * (isIncoming ? 2.4 : 6.5)).clamp(0.0, 7.5);
              if (sigma < 0.25) return built!;
              return ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                child: built,
              );
            },
            child: content,
          );
        }
        return content;
      },
      child: child,
    );
  }
}

class WeatherScreen extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final ThemePaletteSpec palette;
  final VoidCallback onApplyEcoCompensation;
  final bool weatherAlertsEnabled;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry? boiler;
  final SystemSettingsState? settings;
  final PerformanceMode performanceMode;
  final ValueChanged<bool>? onToggleWeatherAlerts;
  final ValueChanged<String>? onChangeLocation;

  const WeatherScreen({
    super.key,
    required this.lang,
    required this.locationName,
    required this.palette,
    required this.onApplyEcoCompensation,
    this.weatherAlertsEnabled = true,
    this.roomTemp = 21.8,
    this.targetTemp = 22.5,
    this.boiler,
    this.settings,
    this.performanceMode = PerformanceMode.balanced,
    this.onToggleWeatherAlerts,
    this.onChangeLocation,
  });

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> with SingleTickerProviderStateMixin {
  int _selectedDay = 0;
  bool _hourlyExpanded = false;
  String? _toastMsg;
  late final AnimationController _weatherAnimCtrl;

  static const _locations = ['Ev · İstanbul', 'Ev (Kadıköy)', 'Yazlık · İzmir', 'Ofis · Ankara'];

  @override
  void initState() {
    super.initState();
    _weatherAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant WeatherScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.performanceMode != widget.performanceMode) {
      if (widget.performanceMode == PerformanceMode.ecoBattery) {
        _weatherAnimCtrl.duration = const Duration(milliseconds: 4800);
        if (_weatherAnimCtrl.isAnimating) _weatherAnimCtrl.repeat();
      } else {
        _weatherAnimCtrl.duration = const Duration(milliseconds: 2800);
        if (_weatherAnimCtrl.isAnimating) _weatherAnimCtrl.repeat();
      }
    }
  }

  @override
  void dispose() {
    _weatherAnimCtrl.dispose();
    super.dispose();
  }

  void _showPrecautionsModal(bool tr, ThemePaletteSpec p) {
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: p.sheetBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr ? 'Akıllı Tedbir & Kompanzasyon' : 'Smart Weather Precautions',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.textPrimary),
              ),
            ),
          ],
        ),
        content: Text(
          tr
              ? 'Yarın ve Pazartesi için %90 üzeri yağış ve gece 11-13°C ısı düşüşü öngörülüyor. Kombi su sıcaklığı modülasyon eğrisi +%6 ön ısıtmaya ve Eko dengelemeye ayarlanabilir.'
              : 'Over 90% rain and 11-13°C night drop expected. Boiler modulation curve can apply +6% pre-heat and Eco compensation.',
          style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(tr ? 'Kapat' : 'Close'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dCtx).pop();
              widget.onApplyEcoCompensation();
              setState(() {
                _toastMsg = tr ? 'Eko dış ısı kompanzasyonu uygulandı.' : 'Eco weather compensation applied.';
              });
            },
            child: Text(tr ? 'Eko Önlemi Uygula' : 'Apply Eco Mode'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isLandscape = width > MediaQuery.of(context).size.height;
    final wideRow = width >= 660;
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final days = DailyWeatherForecast.sample5Days;
    final activeDay = days[_selectedDay];
    final skyAccent = p.isLight ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC);
    const amberAccent = Color(0xFFF59E0B);

    Widget buildDayCard(int i) {
      final day = days[i];
      final selected = i == _selectedDay;
      return GestureDetector(
        onTap: () {
          setState(() {
            if (_selectedDay == i) {
              _hourlyExpanded = !_hourlyExpanded;
            } else {
              _selectedDay = i;
              _hourlyExpanded = true;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFFEA580C).withValues(alpha: 0.72),
                      const Color(0xFF7C2D12).withValues(alpha: 0.65),
                    ],
                  )
                : null,
            color: selected ? null : p.cardBg,
            border: Border.all(
              color: selected ? amberAccent : p.cardBorder,
              width: selected ? 1.4 : 1.0,
            ),
            boxShadow: selected
                ? [BoxShadow(color: amberAccent.withValues(alpha: 0.25), blurRadius: 16)]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      tr ? day.dayTr : day.dayEn,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : p.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFBBF24)),
                    ),
                  ],
                ],
              ),
              Text(
                day.dateLabel,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white70 : p.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              _AnimatedWeatherIcon(
                conditionTr: day.conditionTr,
                conditionEn: day.conditionEn,
                fallbackIcon: day.icon,
                size: 24,
                color: selected ? Colors.white : skyAccent,
                animation: _weatherAnimCtrl,
                selected: selected,
              ),
              const SizedBox(height: 8),
              Text(
                tr ? day.conditionTr : day.conditionEn,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: selected ? Colors.white.withValues(alpha: 0.90) : p.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${day.highTemp}°',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : p.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${day.lowTemp}°',
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.white70 : p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : amberAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  day.rainChance,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: selected ? const Color(0xFF9A3412) : amberAccent,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 460),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      children: [
                        _AnimatedWeatherIcon(
                          conditionTr: 'Güneşli',
                          conditionEn: 'Sunny',
                          fallbackIcon: Icons.wb_sunny_outlined,
                          size: 18,
                          color: const Color(0xFFFBBF24),
                          animation: _weatherAnimCtrl,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            tr ? 'Bölgesel Hava Durumu & 5 Günlük Tahmin' : 'Regional Weather & 5-Day Forecast',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    tr ? 'Saatlik için güne dokunun' : 'Tap day for hourly',
                    style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Top Location, Alerts & Current Weather Strip
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PopupMenuButton<String>(
                    color: p.sheetBg,
                    onSelected: (loc) => widget.onChangeLocation?.call(loc),
                    itemBuilder: (_) => [
                      for (final loc in _locations)
                        PopupMenuItem(
                          value: loc,
                          child: Text(loc, style: TextStyle(color: p.textPrimary, fontSize: 13)),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: p.cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: p.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFF43F5E)),
                          const SizedBox(width: 5),
                          Text(
                            widget.locationName,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: p.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => widget.onToggleWeatherAlerts?.call(!widget.weatherAlertsEnabled),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: widget.weatherAlertsEnabled
                                ? amberAccent.withValues(alpha: 0.16)
                                : p.cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: widget.weatherAlertsEnabled ? amberAccent.withValues(alpha: 0.50) : p.cardBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_active_outlined,
                                size: 13,
                                color: widget.weatherAlertsEnabled ? amberAccent : p.textSecondary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                widget.weatherAlertsEnabled
                                    ? (tr ? 'Hava Bildirimleri Açık' : 'Weather Alerts On')
                                    : (tr ? 'Bildirimler Kapalı' : 'Alerts Off'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: widget.weatherAlertsEnabled ? amberAccent : p.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '17.7°C',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('%58 · 15 km/s', style: TextStyle(fontSize: 11, color: skyAccent)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 5-Day Horizontal Cards
              if (wideRow)
                Row(
                  children: [
                    for (int i = 0; i < days.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: buildDayCard(i)),
                    ],
                  ],
                )
              else
                SizedBox(
                  height: 162,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: days.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => SizedBox(width: 114, child: buildDayCard(i)),
                  ),
                ),

              // Hourly Forecast Drawer / Panel on Day Tap
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _hourlyExpanded
                      ? Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: p.cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: amberAccent.withValues(alpha: 0.40)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${tr ? activeDay.dayTr : activeDay.dayEn} (${activeDay.dateLabel}) · ${tr ? 'Saat Bazlı Tahmin' : 'Hourly Forecast'}',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() => _hourlyExpanded = false),
                                    child: Icon(Icons.keyboard_arrow_up_rounded, color: p.textSecondary, size: 20),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                height: 98,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: activeDay.hourly.length,
                                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                                  itemBuilder: (_, hi) {
                                    final h = activeDay.hourly[hi];
                                    return Container(
                                      width: 88,
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: p.scaffoldBg.withValues(alpha: 0.45),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: p.cardBorder),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(h.hour, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textSecondary)),
                                          _AnimatedWeatherIcon(
                                            conditionTr: h.conditionTr,
                                            conditionEn: h.conditionEn,
                                            fallbackIcon: h.icon,
                                            size: 18,
                                            color: skyAccent,
                                            animation: _weatherAnimCtrl,
                                          ),
                                          Text(
                                            '${h.temp}°C',
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: p.textPrimary,
                                              fontFeatures: const [FontFeature.tabularFigures()],
                                            ),
                                          ),
                                          Text(
                                            '${h.rainChance} · ${h.windKmh}',
                                            style: TextStyle(fontSize: 9.5, color: p.textSecondary),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ),

              const SizedBox(height: 12),

              // Bottom 3-Hour Notification & Smart Precautions Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: amberAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: amberAccent.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 18, color: amberAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr
                                    ? '3 Saatlik Bildirim & Akıllı Tedbir Sistemi Devrede'
                                    : '3-Hour Alert & Smart Precaution Active',
                                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: amberAccent),
                              ),
                              Text(
                                tr
                                    ? 'Önümüzdeki günlerde yağış ve ani ısı düşüşü bekleniyor. Tedbirler hazır.'
                                    : 'Rain and sudden temperature drop ahead. Smart precautions ready.',
                                style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FilledButton(
                          onPressed: () => _showPrecautionsModal(tr, p),
                          style: FilledButton.styleFrom(
                            backgroundColor: amberAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(tr ? 'Önlemleri Gör' : 'View Precautions', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            final activeBoiler = widget.boiler ??
                                ThermostatMath.computeBoilerTelemetry(widget.roomTemp, widget.targetTemp);
                            final res = await NotificationService.dispatchNotification(
                              context: context,
                              lang: widget.lang,
                              locationName: widget.locationName,
                              roomTemp: widget.roomTemp,
                              targetTemp: widget.targetTemp,
                              boiler: activeBoiler,
                              settings: widget.settings ?? SystemSettingsState.defaults(),
                              customTitle: tr
                                  ? '🌧️ Hava & Donma Koruma Test Bildirimi'
                                  : '🌧️ Weather & Freeze Guard Test Alert',
                              customBody: tr
                                  ? '${widget.locationName}: Yarın %90 yağış & gece 11-13°C düşüş bekleniyor. Oda ${widget.roomTemp.toStringAsFixed(1)}°C.'
                                  : '${widget.locationName}: 90% rain & 11-13°C night drop ahead. Room ${widget.roomTemp.toStringAsFixed(1)}°C.',
                              severityOverride: AlertSeverity.warning,
                            );
                            if (!mounted) return;
                            setState(() {
                              _toastMsg = tr ? res.statusTextTr : res.statusTextEn;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.textPrimary,
                            side: BorderSide(color: p.cardBorder),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(tr ? 'Test Bildirimi' : 'Test Alert', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (_toastMsg != null) ...[
                      const SizedBox(height: 6),
                      Text(_toastMsg!, style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportScreen extends StatefulWidget {
  final LangCode lang;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final List<ReportSubTab> subTabOrder;
  final ThemePaletteSpec palette;
  final PerformanceMode performanceMode;
  final VoidCallback? onBoundaryPrevMainTab;
  final VoidCallback? onBoundaryNextMainTab;

  const ReportScreen({
    super.key,
    required this.lang,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.subTabOrder,
    required this.palette,
    this.performanceMode = PerformanceMode.balanced,
    this.onBoundaryPrevMainTab,
    this.onBoundaryNextMainTab,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _periodIndex = 0; // 0: Günlük, 1: Haftalık, 2: Aylık
  int _dayOptionIdx = 0;
  int _selectedHourIdx = 0;
  ReportSubTab? _selectedSubTab;
  DateTime? _lastSubSwitchAt;

  ReportSubTab get _activeSubTab {
    if (_selectedSubTab != null && widget.subTabOrder.contains(_selectedSubTab)) {
      return _selectedSubTab!;
    }
    return widget.subTabOrder.first;
  }

  void _stepSubTab(int dir) {
    if (dir == 0) return;
    final now = DateTime.now();
    if (_lastSubSwitchAt != null && now.difference(_lastSubSwitchAt!).inMilliseconds < 220) {
      return;
    }
    _lastSubSwitchAt = now;
    final order = widget.subTabOrder;
    final curIdx = order.indexOf(_activeSubTab).clamp(0, order.length - 1);
    final nextIdx = curIdx + dir;
    if (nextIdx >= 0 && nextIdx < order.length) {
      setState(() => _selectedSubTab = order[nextIdx]);
    } else if (nextIdx < 0) {
      widget.onBoundaryPrevMainTab?.call();
    } else {
      widget.onBoundaryNextMainTab?.call();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final dir = (dx.abs() > dy.abs() ? dx : dy);
    if (dir.abs() < 6.0) return;
    _stepSubTab(dir > 0 ? 1 : -1);
  }

  String _subTabLabel(ReportSubTab t, bool tr) {
    switch (t) {
      case ReportSubTab.heatMap:
        return tr ? '🌡️ Sıcaklık Haritası' : '🌡️ Heat Map';
      case ReportSubTab.usageBill:
        return tr ? '💰 Tüketim ve Fatura' : '💰 Usage & Bill';
      case ReportSubTab.boilerSensors:
        return tr ? '🔥 Kombi & Sensörler' : '🔥 Boiler & Sensors';
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final isLandscape = width > media.size.height;
    final wideHourStrip = width >= 540;
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final themeAccent = p.themeOverrideAccent?.toColor() ??
        (p.isLight ? const Color(0xFF6D28D9) : const Color(0xFFA78BFA));
    final emerald = p.isLight ? const Color(0xFF059669) : const Color(0xFF34D399);
    final multiplier = _periodIndex == 0 ? 1 : (_periodIndex == 1 ? 7 : 30);
    final gasM3 = (widget.boiler.isHeating ? 1.85 : 1.12) * multiplier;
    final costTl = gasM3 * 10.25;
    final savedTl = costTl * 0.28;

    final dayOptions = [
      (tr ? '2026-11-23 (Bugün)' : '2026-11-23 (Today)', '1s 30d', '22s 30d', [21.8, 20.6, 21.0, 21.4, 21.6, 21.8], [true, false, true, false, true, true]),
      (tr ? '2026-11-22 (Dün)' : '2026-11-22 (Yesterday)', '2s 15d', '21s 45d', [20.9, 20.1, 21.2, 21.5, 21.8, 21.3], [false, false, true, true, true, false]),
      (tr ? '2026-11-21 (Cmt)' : '2026-11-21 (Sat)', '3s 05d', '20s 55d', [21.4, 21.0, 21.8, 22.0, 22.1, 21.6], [true, false, true, true, true, false]),
    ];
    final dayEntry = dayOptions[_dayOptionIdx % dayOptions.length];
    const hours = ['00:00', '04:00', '08:00', '12:00', '16:00', '20:00'];

    Widget buildHeatMapView() {
      Widget buildHourTile(int i) {
        final selected = i == _selectedHourIdx;
        final activeBurn = dayEntry.$5[i];
        final tVal = dayEntry.$4[i];
        return GestureDetector(
          onTap: () => setState(() => _selectedHourIdx = i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? themeAccent.withValues(alpha: 0.20)
                  : p.scaffoldBg.withValues(alpha: p.isLight ? 0.55 : 0.36),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? themeAccent : p.cardBorder,
                width: selected ? 1.4 : 1.0,
              ),
              boxShadow: selected
                  ? [BoxShadow(color: themeAccent.withValues(alpha: 0.22), blurRadius: 14)]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  hours[i],
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? p.textPrimary : p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 5),
                if (selected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: emerald.withValues(alpha: 0.24),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: emerald.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      '${tVal.toStringAsFixed(1)}°',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: p.isLight ? const Color(0xFF065F46) : Colors.white,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  )
                else
                  Text(
                    '${tVal.toStringAsFixed(1)}°',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: p.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                const SizedBox(height: 5),
                Text(
                  activeBurn
                      ? (tr ? '🔥 Aktif' : '🔥 Active')
                      : (tr ? '❄️ Bekleme' : '❄️ Idle'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: activeBurn ? themeAccent : p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      }

      return Container(
        key: const ValueKey(ReportSubTab.heatMap),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: themeAccent),
                    ),
                    const SizedBox(width: 7),
                    Icon(Icons.bar_chart_rounded, size: 15, color: themeAccent),
                    const SizedBox(width: 6),
                    Text(
                      tr ? 'SICAKLIK HARİTASI' : 'HEAT MAP',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: themeAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: themeAccent.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    '${widget.roomTemp.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: themeAccent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Full-width Segmented Günlük / Haftalık / Aylık bar matching Screenshot 3
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                children: [
                  for (final seg in [
                    (0, tr ? 'Günlük' : 'Daily'),
                    (1, tr ? 'Haftalık' : 'Weekly'),
                    (2, tr ? 'Aylık' : 'Monthly'),
                  ])
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _periodIndex = seg.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _periodIndex == seg.$1
                                ? themeAccent.withValues(alpha: 0.28)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _periodIndex == seg.$1 ? themeAccent : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            seg.$2,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _periodIndex == seg.$1 ? p.textPrimary : p.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Examined Day + Active Burn Summary Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.40 : 0.36),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.cardBorder),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 13, color: themeAccent),
                          const SizedBox(width: 6),
                          Text(
                            tr ? 'İncelenen Gün:' : 'Selected Day:',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textSecondary),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _dayOptionIdx = (_dayOptionIdx + 1) % dayOptions.length),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: themeAccent.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: themeAccent.withValues(alpha: 0.65)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                dayEntry.$1,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: p.textPrimary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: themeAccent)),
                          const SizedBox(width: 6),
                          Text(
                            '${tr ? 'Aktif Yanma:' : 'Active Burn:'} ',
                            style: TextStyle(fontSize: 11, color: p.textSecondary),
                          ),
                          Text(
                            dayEntry.$2,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: themeAccent),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: p.textSecondary.withValues(alpha: 0.65)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${tr ? 'Beklemede:' : 'Standby:'} ',
                            style: TextStyle(fontSize: 11, color: p.textSecondary),
                          ),
                          Text(
                            dayEntry.$3,
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Sıcaklık Haritası' : 'Hourly Heat Map',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                ),
                Flexible(
                  child: Text(
                    tr ? '(Saat kutucuklarına dokunarak detayları inceleyin)' : '(Tap hour blocks for details)',
                    style: TextStyle(fontSize: 10, color: p.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (wideHourStrip)
              Row(
                children: [
                  for (int i = 0; i < hours.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: buildHourTile(i)),
                  ],
                ],
              )
            else
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.32,
                children: [
                  for (int i = 0; i < hours.length; i++) buildHourTile(i),
                ],
              ),
          ],
        ),
      );
    }

    Widget buildUsageBillView() {
      return Container(
        key: const ValueKey(ReportSubTab.usageBill),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: themeAccent)),
                    const SizedBox(width: 7),
                    Text(
                      tr ? '💰 TÜKETİM VE FATURA' : '💰 USAGE & BILL',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.textPrimary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: themeAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: themeAccent.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    _periodIndex == 0
                        ? (tr ? 'Seçili Gün Özeti' : 'Selected Day')
                        : _periodIndex == 1
                            ? (tr ? 'Haftalık Özet' : 'Weekly Summary')
                            : (tr ? 'Aylık Özet' : 'Monthly Summary'),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: themeAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.40 : 0.36),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr ? 'Doğalgaz m³ Birim Fiyatı' : 'Natural Gas Unit Rate',
                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                  ),
                  Text(
                    '10.25 ₺ / m³',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: themeAccent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    title: tr ? 'SAYAÇ TÜKETİMİ' : 'GAS METER USAGE',
                    value: '${gasM3.toStringAsFixed(2)} m³',
                    sub: tr ? 'Aktif yanma: ${dayEntry.$2}' : 'Active burn: ${dayEntry.$2}',
                    palette: p,
                    accentTextColor: p.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: tr ? 'TAHMİNİ TUTAR' : 'ESTIMATED BILL',
                    value: '${costTl.toStringAsFixed(2)} ₺',
                    sub: tr ? '↘ ~${savedTl.toStringAsFixed(2)} ₺ Tasarruf' : '↘ ~${savedTl.toStringAsFixed(2)} ₺ Saved',
                    palette: p,
                    accentTextColor: emerald,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr
                  ? '💡 Modülasyonlu kombi alev kontrolü ile standart on/off termostatlara göre ~%28 tasarruf sağlanır.'
                  : '💡 Modulated boiler flame control achieves ~28% savings compared to standard on/off thermostats.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: p.textSecondary),
            ),
          ],
        ),
      );
    }

    Widget buildSensorsView() {
      return Container(
        key: const ValueKey(ReportSubTab.boilerSensors),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: themeAccent)),
                    const SizedBox(width: 7),
                    Text(
                      tr ? '🔥 KOMBİ & SENSÖRLER' : '🔥 BOILER & SENSORS',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.textPrimary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: emerald.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: emerald.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    widget.boiler.modulationActive ? 'OpenTherm v4.2' : 'Standby',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: p.cardBorder, height: 1),
            const SizedBox(height: 8),
            _SensorRow(label: tr ? 'Gidiş Suyu Sıcaklığı' : 'Supply Water Temp', value: widget.boiler.isHeating ? '54.2°C' : '29.4°C', palette: p),
            _SensorRow(label: tr ? 'Dönüş Suyu Sıcaklığı' : 'Return Water Temp', value: widget.boiler.isHeating ? '42.6°C' : '26.8°C', palette: p),
            _SensorRow(label: tr ? 'Alev Gücü' : 'Flame Power', value: '%${widget.boiler.flamePercent}', palette: p),
            _SensorRow(label: tr ? 'Sirkülasyon Pompası' : 'Circulation Pump', value: '${widget.boiler.pumpRpm} RPM', palette: p),
            _SensorRow(label: tr ? 'Tesisat Basıncı' : 'Loop Water Pressure', value: '${widget.boiler.waterPressureBar} Bar (Normal)', palette: p),
            _SensorRow(label: tr ? 'İyonizasyon Alev Sensörü' : 'Ionization Flame Sensor', value: widget.boiler.isHeating ? '18.4 µA OK' : '0.0 µA', palette: p),
          ],
        ),
      );
    }

    final activePanel = switch (_activeSubTab) {
      ReportSubTab.heatMap => buildHeatMapView(),
      ReportSubTab.usageBill => buildUsageBillView(),
      ReportSubTab.boilerSensors => buildSensorsView(),
    };

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0.0;
          if (v.abs() < 160) return;
          _stepSubTab(v < 0 ? 1 : -1);
        },
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: constraints.maxHeight < 460
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 17, color: themeAccent),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                tr ? '24s Sıcaklık & Tüketim Analitiği' : '24h Heat & Usage Analytics',
                                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        tr ? '👆 Parmakla Kaydırın / Wheel' : '👆 Swipe / Mouse Wheel',
                        style: TextStyle(fontSize: 10, color: p.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Centered Floating Capsule Sub-Tab Switcher (Screenshot 3 & 4)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.cardBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: p.isLight ? 0.08 : 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final sub in widget.subTabOrder) ...[
                              GestureDetector(
                                onTap: () => setState(() => _selectedSubTab = sub),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _activeSubTab == sub
                                        ? themeAccent.withValues(alpha: 0.28)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _activeSubTab == sub ? themeAccent : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    _subTabLabel(sub, tr),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: _activeSubTab == sub ? p.textPrimary : p.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _BlurredDepthSubTabSwitcher(
                    disableBlur: widget.performanceMode == PerformanceMode.ecoBattery,
                    child: activePanel,
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemePaletteSpec palette;

  const _SensorRow({required this.label, required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: palette.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String sub;
  final ThemePaletteSpec palette;
  final Color accentTextColor;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.sub,
    required this.palette,
    required this.accentTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: palette.scaffoldBg.withValues(alpha: palette.isLight ? 0.45 : 0.36),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: accentTextColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class ScheduleScreen extends StatefulWidget {
  final LangCode lang;
  final List<ScheduleSlot> slots;
  final List<ScheduleSubTab> subTabOrder;
  final ThemePaletteSpec palette;
  final BoilerTelemetry? boiler;
  final PerformanceMode performanceMode;
  final void Function(String id, {bool? enabled, double? targetTemp}) onUpdateSlot;
  final VoidCallback onSaveSchedule;
  final bool savedNotice;
  final VoidCallback? onBoundaryPrevMainTab;
  final VoidCallback? onBoundaryNextMainTab;

  const ScheduleScreen({
    super.key,
    required this.lang,
    required this.slots,
    required this.subTabOrder,
    required this.palette,
    this.boiler,
    this.performanceMode = PerformanceMode.balanced,
    required this.onUpdateSlot,
    required this.onSaveSchedule,
    required this.savedNotice,
    this.onBoundaryPrevMainTab,
    this.onBoundaryNextMainTab,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  ScheduleSubTab? _selectedSubTab;
  DateTime? _lastSubSwitchAt;

  ScheduleSubTab get _activeSubTab {
    if (_selectedSubTab != null && widget.subTabOrder.contains(_selectedSubTab)) {
      return _selectedSubTab!;
    }
    return widget.subTabOrder.first;
  }

  void _stepSubTab(int dir) {
    if (dir == 0) return;
    final now = DateTime.now();
    if (_lastSubSwitchAt != null && now.difference(_lastSubSwitchAt!).inMilliseconds < 220) {
      return;
    }
    _lastSubSwitchAt = now;
    final order = widget.subTabOrder;
    final curIdx = order.indexOf(_activeSubTab).clamp(0, order.length - 1);
    final nextIdx = curIdx + dir;
    if (nextIdx >= 0 && nextIdx < order.length) {
      setState(() => _selectedSubTab = order[nextIdx]);
    } else if (nextIdx < 0) {
      widget.onBoundaryPrevMainTab?.call();
    } else {
      widget.onBoundaryNextMainTab?.call();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    final dir = (dx.abs() > dy.abs() ? dx : dy);
    if (dir.abs() < 6.0) return;
    _stepSubTab(dir > 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isLandscape = width > MediaQuery.of(context).size.height;
    final wideKpi = width >= 540;
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final emerald = p.isLight ? const Color(0xFF059669) : const Color(0xFF34D399);
    final themeAccent = p.themeOverrideAccent?.toColor() ?? emerald;
    final liveBoiler = widget.boiler ?? ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    final gasEstimate = liveBoiler.isHeating ? 1.42 : 1.08;
    final tlEstimate = gasEstimate * 10.28;
    final savedTl = tlEstimate * 0.28;
    final flameFrac = (liveBoiler.flamePercent / 100.0).clamp(0.08, 1.0);

    Widget buildSmartScheduleCard() {
      return Container(
        key: const ValueKey(ScheduleSubTab.smartSchedule),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr ? 'AKILLI ZAMANLAMA' : 'SMART SCHEDULE',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.textPrimary),
                    ),
                    Text(
                      tr ? 'Cihaz hafızasına otomatik kaydedilir' : 'Saved locally to device',
                      style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: widget.onSaveSchedule,
                  icon: Icon(widget.savedNotice ? Icons.check_rounded : Icons.save_outlined, size: 15),
                  label: Text(
                    widget.savedNotice ? (tr ? 'Kaydedildi' : 'Saved') : (tr ? 'Kaydet' : 'Save'),
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: themeAccent.withValues(alpha: 0.24),
                    foregroundColor: themeAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: isLandscape ? 2 : 1,
              crossAxisSpacing: 10,
              mainAxisSpacing: 8,
              childAspectRatio: isLandscape ? 4.4 : 4.7,
              children: [
                for (final slot in widget.slots)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.42 : 0.36),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Switch(
                          value: slot.enabled,
                          activeThumbColor: emerald,
                          onChanged: (v) => widget.onUpdateSlot(slot.id, enabled: v),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                tr ? slot.labelTr : slot.labelEn,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
                              ),
                              Text(
                                slot.time,
                                style: TextStyle(fontSize: 11, color: p.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => widget.onUpdateSlot(
                            slot.id,
                            targetTemp: ThermostatMath.snapTemperature(slot.targetTemp - 0.5),
                          ),
                          icon: Icon(Icons.remove_rounded, size: 16, color: p.textPrimary),
                        ),
                        Text(
                          '${slot.targetTemp.toStringAsFixed(1)}°',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        IconButton(
                          onPressed: () => widget.onUpdateSlot(
                            slot.id,
                            targetTemp: ThermostatMath.snapTemperature(slot.targetTemp + 0.5),
                          ),
                          icon: Icon(Icons.add_rounded, size: 16, color: p.textPrimary),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    Widget buildDailySavingsCard() {
      final kpiCards = [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.38),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.access_time_rounded, size: 13, color: p.isLight ? const Color(0xFF0284C7) : const Color(0xFF60A5FA)),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      tr ? 'Günlük Çalışma Süresi' : 'Daily Burn Time',
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '1s 30d',
                style: TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(tr ? 'Bugün yanma' : 'Today active', style: TextStyle(fontSize: 10.5, color: p.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.38),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_fire_department_outlined, size: 13, color: themeAccent),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      tr ? 'Toplam Doğalgaz' : 'Total Gas Usage',
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '~${gasEstimate.toStringAsFixed(2)} ',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: themeAccent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: 'm³',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(tr ? '24 kW brülör' : '24 kW burner', style: TextStyle(fontSize: 10.5, color: p.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          decoration: BoxDecoration(
            color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.38),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.cardBorder),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.monetization_on_outlined, size: 13, color: emerald),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      tr ? 'Tahmini Tutar' : 'Est. Cost',
                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '~${tlEstimate.toStringAsFixed(1)} ',
                      style: TextStyle(
                        fontSize: 17.5,
                        fontWeight: FontWeight.w800,
                        color: emerald,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    TextSpan(
                      text: 'TL',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                tr ? '↘ ~${savedTl.toStringAsFixed(1)} TL tasarruf' : '↘ ~${savedTl.toStringAsFixed(1)} TL saved',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: emerald),
              ),
            ],
          ),
        ),
      ];

      return Container(
        key: const ValueKey(ScheduleSubTab.dailySavings),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: p.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header row matching Screenshot 5
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: themeAccent)),
                    const SizedBox(width: 7),
                    Text(
                      tr ? 'GÜNLÜK TÜKETİM & TASARRUF' : 'DAILY USAGE & SAVINGS',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.textPrimary),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: emerald.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: emerald.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    tr ? '✨ A++ Verimlilik' : '✨ A++ Efficiency',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: emerald),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: p.cardBorder, height: 1),
            const SizedBox(height: 14),

            // 3 KPI Cards
            if (wideKpi)
              Row(
                children: [
                  Expanded(child: kpiCards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: kpiCards[1]),
                  const SizedBox(width: 10),
                  Expanded(child: kpiCards[2]),
                ],
              )
            else
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: kpiCards[0]),
                      const SizedBox(width: 8),
                      Expanded(child: kpiCards[1]),
                    ],
                  ),
                  const SizedBox(height: 8),
                  kpiCards[2],
                ],
              ),

            const SizedBox(height: 14),

            // Modulation Efficiency Banner matching Screenshot 5
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: emerald.withValues(alpha: p.isLight ? 0.08 : 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: emerald.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: emerald),
                      const SizedBox(width: 5),
                      Text(
                        tr ? 'Modülasyon Verimliliği:' : 'Modulation Efficiency:',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: emerald),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr
                        ? 'Kombi oda sıcaklığına yaklaştıkça modülasyonu otomatik kısarak doğalgaz sarfiyatını %20 ila %28 oranında azaltır.'
                        : 'As room temperature approaches target, boiler modulation automatically steps down flame to save 20%–28% gas.',
                    style: TextStyle(fontSize: 11, color: p.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        tr ? 'Alev Gücü:' : 'Flame Power:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 7,
                            color: p.scaffoldBg.withValues(alpha: 0.55),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: flameFrac,
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: LinearGradient(
                                      colors: [emerald, const Color(0xFFF59E0B)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '%${liveBoiler.flamePercent}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: emerald,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Bottom Water Pressure + Circulation Pump Pills
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.38),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.speed_outlined, size: 13, color: p.isLight ? const Color(0xFF0284C7) : const Color(0xFF60A5FA)),
                            const SizedBox(width: 5),
                            Text(tr ? 'Su Basıncı:' : 'Pressure:', style: TextStyle(fontSize: 11, color: p.textSecondary)),
                          ],
                        ),
                        Text(
                          '${liveBoiler.waterPressureBar} Bar',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.45 : 0.38),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.show_chart_rounded, size: 13, color: emerald),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  tr ? 'Sirkülasyon Pompası:' : 'Circ. Pump:',
                                  style: TextStyle(fontSize: 11, color: p.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${liveBoiler.pumpRpm} RPM',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final activePanel = _activeSubTab == ScheduleSubTab.smartSchedule
        ? buildSmartScheduleCard()
        : buildDailySavingsCard();

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0.0;
          if (v.abs() < 160) return;
          _stepSubTab(v < 0 ? 1 : -1);
        },
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: constraints.maxHeight < 460
                ? const ClampingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Centered Capsule Sub-Tabs Switcher matching Screenshot 5
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: p.cardBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: p.isLight ? 0.08 : 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final sub in widget.subTabOrder) ...[
                              GestureDetector(
                                onTap: () => setState(() => _selectedSubTab = sub),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: _activeSubTab == sub
                                        ? themeAccent.withValues(alpha: 0.28)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _activeSubTab == sub ? themeAccent : Colors.transparent,
                                    ),
                                  ),
                                  child: Text(
                                    sub == ScheduleSubTab.smartSchedule
                                        ? (tr ? '⏰ Akıllı Zamanlama' : '⏰ Smart Schedule')
                                        : (tr ? '💰 Günlük Tüketim & Tasarruf' : '💰 Daily Usage & Savings'),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: _activeSubTab == sub ? p.textPrimary : p.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _BlurredDepthSubTabSwitcher(
                    disableBlur: widget.performanceMode == PerformanceMode.ecoBattery,
                    child: activePanel,
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
    );
  }
}
