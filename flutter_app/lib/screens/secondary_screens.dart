import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/notification_service.dart';

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
    this.onToggleWeatherAlerts,
    this.onChangeLocation,
  });

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  int _selectedDay = 0;
  bool _hourlyExpanded = false;
  String? _toastMsg;

  static const _locations = ['Ev · İstanbul', 'Ev (Kadıköy)', 'Yazlık · İzmir', 'Ofis · Ankara'];

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
    final amberAccent = const Color(0xFFF59E0B);

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
              Icon(day.icon, size: 24, color: selected ? Colors.white : skyAccent),
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
                        const Icon(Icons.wb_sunny_outlined, size: 17, color: Color(0xFFFBBF24)),
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
                                  Icon(h.icon, size: 18, color: skyAccent),
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
                        Icon(Icons.warning_amber_rounded, size: 18, color: amberAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr
                                    ? '3 Saatlik Bildirim & Akıllı Tedbir Sistemi Devrede'
                                    : '3-Hour Alert & Smart Precaution Active',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: amberAccent),
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

  const ReportScreen({
    super.key,
    required this.lang,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.subTabOrder,
    required this.palette,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _periodIndex = 0; // 0: day, 1: week, 2: month
  ReportSubTab? _selectedSubTab;

  ReportSubTab get _activeSubTab {
    if (_selectedSubTab != null && widget.subTabOrder.contains(_selectedSubTab)) {
      return _selectedSubTab!;
    }
    return widget.subTabOrder.first;
  }

  String _subTabLabel(ReportSubTab t, bool tr) {
    switch (t) {
      case ReportSubTab.heatMap:
        return tr ? 'Sıcaklık Haritası' : 'Heat Map';
      case ReportSubTab.usageBill:
        return tr ? 'Tüketim & Fatura' : 'Usage & Bill';
      case ReportSubTab.boilerSensors:
        return tr ? 'Kombi Sensörleri' : 'Boiler Sensors';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final multiplier = _periodIndex == 0 ? 1 : _periodIndex == 1 ? 7 : 30;
    final gasM3 = (widget.boiler.isHeating ? 1.85 : 1.12) * multiplier;
    final costTl = gasM3 * 10.25;
    final violet = p.isLight ? const Color(0xFF6D28D9) : const Color(0xFFA78BFA);

    final metricsGrid = GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: [
        _MetricCard(
          title: tr ? 'Sayaç Tüketimi' : 'Gas Usage',
          value: '${gasM3.toStringAsFixed(2)} m³',
          sub: tr ? 'Modülasyonlu' : 'Modulated',
          palette: p,
          accentTextColor: violet,
        ),
        _MetricCard(
          title: tr ? 'Tahmini Tutar' : 'Est. Cost',
          value: '${costTl.toStringAsFixed(2)} ₺',
          sub: tr ? '~%28 tasarruf' : '~28% saved',
          palette: p,
          accentTextColor: violet,
        ),
        _MetricCard(
          title: tr ? 'Alev Gücü' : 'Flame Power',
          value: '%${widget.boiler.flamePercent}',
          sub: widget.boiler.isHeating ? (tr ? 'Devrede' : 'Active') : (tr ? 'Bekleme' : 'Idle'),
          palette: p,
          accentTextColor: violet,
        ),
        _MetricCard(
          title: tr ? 'Pompa / Basınç' : 'Pump / Press',
          value: '${widget.boiler.waterPressureBar} Bar',
          sub: '${widget.boiler.pumpRpm} RPM',
          palette: p,
          accentTextColor: violet,
        ),
      ],
    );

    const blocks = [
      ('00:00', '19.2°', false),
      ('04:00', '18.8°', false),
      ('08:00', '21.0°', true),
      ('12:00', '21.4°', false),
      ('16:00', '21.6°', true),
      ('20:00', '21.8°', true),
    ];

    final heatMapCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr ? 'Saatlik Isı Dağılımı' : 'Hourly Heat Map',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
              ),
              Text(
                '${widget.roomTemp.toStringAsFixed(1)}° → ${widget.targetTemp.toStringAsFixed(1)}°',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.45,
            children: [
              for (final blk in blocks)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: blk.$3
                        ? const Color(0xFF8C66FF).withValues(alpha: 0.18)
                        : p.cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: blk.$3
                          ? const Color(0xFF8C66FF).withValues(alpha: 0.40)
                          : p.cardBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(blk.$1, style: TextStyle(fontSize: 10, color: p.textSecondary)),
                      Text(blk.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.textPrimary)),
                      Text(
                        blk.$3 ? (tr ? 'Aktif' : 'Active') : (tr ? 'Bekleme' : 'Idle'),
                        style: TextStyle(fontSize: 10, color: p.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final sensorsCard = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tr ? 'Kombi Sensörleri & Telemetri' : 'Boiler Sensors & Telemetry',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.textPrimary),
              ),
              Text(
                widget.boiler.modulationActive ? 'OpenTherm v4.2' : 'Standby',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: violet),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SensorRow(label: tr ? 'Gidiş Suyu Sıcaklığı' : 'Supply Water Temp', value: widget.boiler.isHeating ? '54.2°C' : '29.4°C', palette: p),
          _SensorRow(label: tr ? 'Dönüş Suyu Sıcaklığı' : 'Return Water Temp', value: widget.boiler.isHeating ? '42.6°C' : '26.8°C', palette: p),
          _SensorRow(label: tr ? 'Sirkülasyon Pompası' : 'Circulation Pump', value: '${widget.boiler.pumpRpm} RPM', palette: p),
          _SensorRow(label: tr ? 'Tesisat Basıncı' : 'Loop Water Pressure', value: '${widget.boiler.waterPressureBar} Bar (Normal)', palette: p),
          _SensorRow(label: tr ? 'İyonizasyon Alev Sensörü' : 'Ionization Flame Sensor', value: widget.boiler.isHeating ? '18.4 µA OK' : '0.0 µA', palette: p),
        ],
      ),
    );

    final activeView = switch (_activeSubTab) {
      ReportSubTab.heatMap => isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heatMapCard),
                const SizedBox(width: 12),
                Expanded(child: metricsGrid),
              ],
            )
          : Column(
              children: [
                heatMapCard,
                const SizedBox(height: 12),
                metricsGrid,
              ],
            ),
      ReportSubTab.usageBill => isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: metricsGrid),
                const SizedBox(width: 12),
                Expanded(child: heatMapCard),
              ],
            )
          : Column(
              children: [
                metricsGrid,
                const SizedBox(height: 12),
                heatMapCard,
              ],
            ),
      ReportSubTab.boilerSensors => isLandscape
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: sensorsCard),
                const SizedBox(width: 12),
                Expanded(child: metricsGrid),
              ],
            )
          : Column(
              children: [
                sensorsCard,
                const SizedBox(height: 12),
                metricsGrid,
              ],
            ),
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      tr ? '24s Sıcaklık & Tüketim Raporu' : '24h Heat & Usage Report',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, label: Text(tr ? 'Gün' : 'Day', style: const TextStyle(fontSize: 11))),
                      ButtonSegment(value: 1, label: Text(tr ? 'Hafta' : 'Week', style: const TextStyle(fontSize: 11))),
                      ButtonSegment(value: 2, label: Text(tr ? 'Ay' : 'Month', style: const TextStyle(fontSize: 11))),
                    ],
                    selected: {_periodIndex},
                    onSelectionChanged: (s) => setState(() => _periodIndex = s.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: WidgetStatePropertyAll(p.textPrimary),
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        return states.contains(WidgetState.selected)
                            ? const Color(0xFF8C66FF).withValues(alpha: 0.35)
                            : p.cardBg;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Ordered Sub-Tabs Strip (controlled by Ekran & Menü Sıralaması)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final sub in widget.subTabOrder) ...[
                      GestureDetector(
                        onTap: () => setState(() => _selectedSubTab = sub),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: _activeSubTab == sub
                                ? const Color(0xFF8C66FF).withValues(alpha: 0.24)
                                : p.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _activeSubTab == sub
                                  ? const Color(0xFF8C66FF)
                                  : p.cardBorder,
                            ),
                          ),
                          child: Text(
                            _subTabLabel(sub, tr),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              activeView,
            ],
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(sub, style: TextStyle(fontSize: 11, color: accentTextColor)),
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
  final void Function(String id, {bool? enabled, double? targetTemp}) onUpdateSlot;
  final VoidCallback onSaveSchedule;
  final bool savedNotice;

  const ScheduleScreen({
    super.key,
    required this.lang,
    required this.slots,
    required this.subTabOrder,
    required this.palette,
    required this.onUpdateSlot,
    required this.onSaveSchedule,
    required this.savedNotice,
  });

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  ScheduleSubTab? _selectedSubTab;

  ScheduleSubTab get _activeSubTab {
    if (_selectedSubTab != null && widget.subTabOrder.contains(_selectedSubTab)) {
      return _selectedSubTab!;
    }
    return widget.subTabOrder.first;
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final emerald = p.isLight ? const Color(0xFF059669) : const Color(0xFF34D399);

    const dailyBars = [
      ('Pzt', 'Mon', 0.62, '1.6 m³'),
      ('Sal', 'Tue', 0.54, '1.4 m³'),
      ('Çar', 'Wed', 0.78, '2.0 m³'),
      ('Per', 'Thu', 0.48, '1.2 m³'),
      ('Cum', 'Fri', 0.58, '1.5 m³'),
      ('Cmt', 'Sat', 0.84, '2.2 m³'),
      ('Paz', 'Sun', 0.70, '1.8 m³'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 440),
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
                        tr ? 'Akıllı Zamanlama & Tasarruf' : 'Smart Schedule & Savings',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.textPrimary),
                      ),
                      Text(
                        tr ? 'Cihaz hafızasına otomatik kaydedilir' : 'Saved locally to device',
                        style: TextStyle(fontSize: 11, color: p.textSecondary),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: widget.onSaveSchedule,
                    icon: Icon(widget.savedNotice ? Icons.check_rounded : Icons.save_outlined, size: 15),
                    label: Text(widget.savedNotice ? (tr ? 'Kaydedildi' : 'Saved') : (tr ? 'Kaydet' : 'Save')),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.25),
                      foregroundColor: emerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Ordered Schedule Sub-Tabs Strip
              Row(
                children: [
                  for (final sub in widget.subTabOrder) ...[
                    GestureDetector(
                      onTap: () => setState(() => _selectedSubTab = sub),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _activeSubTab == sub
                              ? const Color(0xFF10B981).withValues(alpha: 0.22)
                              : p.cardBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _activeSubTab == sub ? const Color(0xFF10B981) : p.cardBorder,
                          ),
                        ),
                        child: Text(
                          sub == ScheduleSubTab.smartSchedule
                              ? (tr ? 'Akıllı Zaman Programı' : 'Smart Schedule')
                              : (tr ? 'Günlük Tüketim & Tasarruf' : 'Daily Usage & Savings'),
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              if (_activeSubTab == ScheduleSubTab.smartSchedule)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isLandscape ? 2 : 1,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: isLandscape ? 4.4 : 4.6,
                  children: [
                    for (final slot in widget.slots)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: p.cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: p.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Switch(
                              value: slot.enabled,
                              activeThumbColor: const Color(0xFF10B981),
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
                )
              else
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: p.cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: p.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            tr ? 'Haftalık Modülasyon Tasarrufu' : 'Weekly Modulation Savings',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.textPrimary),
                          ),
                          Text(
                            tr ? '%28 Daha Verimli' : '28% More Efficient',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: emerald),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 120,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            for (final bar in dailyBars)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(bar.$4, style: TextStyle(fontSize: 9.5, color: p.textSecondary)),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                            heightFactor: bar.$3,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(8),
                                                gradient: const LinearGradient(
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                  colors: [Color(0xFF34D399), Color(0xFF059669)],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        tr ? bar.$1 : bar.$2,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.textPrimary),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
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
