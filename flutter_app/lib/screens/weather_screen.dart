import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/notification_service.dart';
import '../services/weather_service.dart';
import '../widgets/tactile_button.dart';

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

class WeatherScreen extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final ThemePaletteSpec palette;
  final VoidCallback onApplyEcoCompensation;
  final bool weatherAlertsEnabled;
  final double? roomTemp;
  final double targetTemp;
  final BoilerTelemetry? boiler;
  final BoilerHardwareSensors sensors;
  final SystemSettingsState? settings;
  final PerformanceMode performanceMode;
  final ValueChanged<bool>? onToggleWeatherAlerts;
  final ValueChanged<String>? onChangeLocation;
  final WeatherReport? weatherReport;
  final bool isLoadingWeather;
  final String? weatherError;
  final VoidCallback? onRefreshWeather;

  const WeatherScreen({
    super.key,
    required this.lang,
    required this.locationName,
    required this.palette,
    required this.onApplyEcoCompensation,
    this.weatherAlertsEnabled = true,
    this.roomTemp,
    this.targetTemp = 22.5,
    this.boiler,
    this.sensors = const BoilerHardwareSensors.disconnected(),
    this.settings,
    this.performanceMode = PerformanceMode.ultra60fps,
    this.onToggleWeatherAlerts,
    this.onChangeLocation,
    this.weatherReport,
    this.isLoadingWeather = false,
    this.weatherError,
    this.onRefreshWeather,
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
    if (oldWidget.locationName != widget.locationName) {
      _selectedDay = 0;
      _hourlyExpanded = false;
    }
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

  void _showPrecautionsModal(bool tr, ThemePaletteSpec p, WeatherReport? report) {
    final city = report?.cityName ?? SystemSettingsState.extractCityName(widget.locationName);
    final nextDays = report?.days ?? const <DailyWeatherForecast>[];
    final minUpcoming = nextDays.isEmpty
        ? null
        : nextDays.map((d) => d.lowTemp).reduce((a, b) => a < b ? a : b);
    final maxRain = nextDays.isEmpty
        ? null
        : nextDays
            .map((d) => int.tryParse(d.rainChance.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
            .reduce((a, b) => a > b ? a : b);

    final bodyText = report == null
        ? (tr
            ? '$city için canlı hava tahmini henüz alınamadı. Yenile düğmesine basarak güncel tahmini çektikten sonra dış ısı kompanzasyonu önerileri oluşturulur.'
            : 'Live forecast for $city is not loaded yet. Tap Refresh to load forecast data for outdoor compensation guidance.')
        : (tr
            ? '$city şu an ${report.currentTempC.toStringAsFixed(1)}°C (${report.conditionTr}). Önümüzdeki 5 gün en düşük sıcaklık ${minUpcoming ?? report.currentTempC.round()}°C ve en yüksek yağış ihtimali %${maxRain ?? 0} bekleniyor. Eko dengeleme ile kombi ön ısıtması dengelenebilir.'
            : '$city is currently ${report.currentTempC.toStringAsFixed(1)}°C (${report.conditionEn}). 5-day low is ${minUpcoming ?? report.currentTempC.round()}°C with up to ${maxRain ?? 0}% rain probability. Eco weather compensation can balance pre-heating.');

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
          bodyText,
          style: TextStyle(fontSize: 13, color: p.textSecondary, height: 1.45),
        ),
        actions: [
          TactilePress(
            child: TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(tr ? 'Kapat' : 'Close'),
            ),
          ),
          TactilePress(
            child: FilledButton(
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
    final report = widget.weatherReport;
    final days = report?.days ?? const <DailyWeatherForecast>[];
    final safeSelectedIdx = days.isEmpty ? 0 : _selectedDay.clamp(0, days.length - 1);
    final activeDay = days.isEmpty ? null : days[safeSelectedIdx];
    final skyAccent = p.isLight ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC);
    const amberAccent = Color(0xFFF59E0B);

    Widget buildDayCard(int i) {
      final day = days[i];
      final selected = i == safeSelectedIdx;
      return TactilePress.card(
        child: GestureDetector(
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
        ),
      );
    }

    final currentTempStr = report != null ? '${report.currentTempC.toStringAsFixed(1)}°C' : '--.-°C';
    final currentMetaStr = report != null
        ? '%${report.humidityPercent} · ${report.windKmh.round()} km/s'
        : (widget.isLoadingWeather ? (tr ? 'Yükleniyor...' : 'Loading...') : '-- · --');
    final cityTitle = report?.cityName ?? SystemSettingsState.extractCityName(widget.locationName);
    final updatedTimeLabel = report != null
        ? '${report.fetchedAt.hour.toString().padLeft(2, '0')}:${report.fetchedAt.minute.toString().padLeft(2, '0')}'
        : null;

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
                          conditionTr: report?.conditionTr ?? 'Parçalı Bulutlu',
                          conditionEn: report?.conditionEn ?? 'Partly Cloudy',
                          fallbackIcon: report?.icon ?? Icons.wb_sunny_outlined,
                          size: 18,
                          color: const Color(0xFFFBBF24),
                          animation: _weatherAnimCtrl,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            tr ? 'Canlı Hava Durumu · $cityTitle' : 'Live Weather · $cityTitle',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (updatedTimeLabel != null)
                        Text(
                          updatedTimeLabel,
                          style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                        ),
                      const SizedBox(width: 6),
                      TactilePress(
                        child: GestureDetector(
                          onTap: widget.isLoadingWeather ? null : widget.onRefreshWeather,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: p.cardBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: p.cardBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.isLoadingWeather)
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: skyAccent,
                                    ),
                                  )
                                else
                                  Icon(Icons.refresh_rounded, size: 13, color: skyAccent),
                                const SizedBox(width: 4),
                                Text(
                                  tr ? 'Yenile' : 'Refresh',
                                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
                  TactilePress(
                    child: PopupMenuButton<String>(
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
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TactilePress(
                        child: GestureDetector(
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
                      ),
                      const SizedBox(width: 10),
                      Text(
                        currentTempStr,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(currentMetaStr, style: TextStyle(fontSize: 11, color: skyAccent)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (widget.weatherError != null && days.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, size: 18, color: Color(0xFFF87171)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.weatherError!,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
                            ),
                          ),
                        ],
                      ),
                      if (widget.onRefreshWeather != null) ...[
                        const SizedBox(height: 10),
                        TactilePress(
                          child: OutlinedButton.icon(
                            onPressed: widget.onRefreshWeather,
                            icon: const Icon(Icons.refresh_rounded, size: 15),
                            label: Text(tr ? 'Tekrar Dene' : 'Retry'),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (days.isEmpty)
                Container(
                  height: 162,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(strokeWidth: 2.2, color: skyAccent),
                      const SizedBox(height: 10),
                      Text(
                        tr ? '$cityTitle için canlı hava verisi çekiliyor...' : 'Fetching live forecast for $cityTitle...',
                        style: TextStyle(fontSize: 12, color: p.textSecondary),
                      ),
                    ],
                  ),
                )
              else ...[
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
                if (activeDay != null)
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
                                      TactilePress(
                                        child: GestureDetector(
                                          onTap: () => setState(() => _hourlyExpanded = false),
                                          child: Icon(Icons.keyboard_arrow_up_rounded, color: p.textSecondary, size: 20),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (activeDay.hourly.isEmpty)
                                    Text(
                                      tr ? 'Bu gün için saatlik tahmin verisi yok.' : 'No hourly data available for this day.',
                                      style: TextStyle(fontSize: 11, color: p.textSecondary),
                                    )
                                  else
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
              ],

              const SizedBox(height: 12),

              // Bottom Notification & Smart Precautions Banner
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
                                report == null
                                    ? (tr
                                        ? '$cityTitle canlı hava raporu bekleniyor.'
                                        : 'Waiting for live weather report for $cityTitle.')
                                    : (report.hasRainRiskSoon || report.hasColdDropSoon)
                                        ? (tr
                                            ? '$cityTitle için yağış veya serinleme öngörülüyor (${report.conditionTr}). Tedbirler hazır.'
                                            : 'Rain or cooling trend forecast for $cityTitle (${report.conditionEn}). Precautions ready.')
                                        : (tr
                                            ? '$cityTitle (${report.conditionTr}, ${report.currentTempC.toStringAsFixed(1)}°C) stabil seyrediyor.'
                                            : '$cityTitle (${report.conditionEn}, ${report.currentTempC.toStringAsFixed(1)}°C) is steady.'),
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
                        TactilePress(
                          child: FilledButton(
                            onPressed: () => _showPrecautionsModal(tr, p, report),
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
                        ),
                        const SizedBox(width: 8),
                        TactilePress(
                          child: OutlinedButton(
                            onPressed: () async {
                              final activeBoiler = widget.boiler ??
                                  ThermostatMath.computeBoilerTelemetry(widget.roomTemp, widget.targetTemp);
                              final weatherDesc = report != null
                                  ? '${report.cityName} ${report.currentTempC.toStringAsFixed(1)}°C (${tr ? report.conditionTr : report.conditionEn})'
                                  : widget.locationName;
                              final res = await NotificationService.dispatchNotification(
                                context: context,
                                lang: widget.lang,
                                locationName: widget.locationName,
                                roomTemp: widget.roomTemp,
                                targetTemp: widget.targetTemp,
                                outsideTemp: report?.currentTempC,
                                boiler: activeBoiler,
                                sensors: widget.sensors,
                                settings: widget.settings ?? SystemSettingsState.defaults(),
                                customTitle: tr
                                    ? '🌧️ Hava & Donma Koruma Test Bildirimi'
                                    : '🌧️ Weather & Freeze Guard Test Alert',
                                customBody: tr
                                    ? '$weatherDesc · Oda ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'}.'
                                    : '$weatherDesc · Room ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'}.',
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
