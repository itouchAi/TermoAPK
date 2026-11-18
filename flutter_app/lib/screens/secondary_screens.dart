import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';

class WeatherScreen extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final ThemePaletteSpec palette;
  final VoidCallback onApplyEcoCompensation;

  const WeatherScreen({
    super.key,
    required this.lang,
    required this.locationName,
    required this.palette,
    required this.onApplyEcoCompensation,
  });

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  int _selectedDay = 0;
  bool _autoCompensate = true;

  static const _forecast = [
    ('Bugün', 'Today', '18 Kas', 'Parçalı Bulutlu', 'Partly Cloudy', 19, 12, '—', Icons.wb_cloudy_outlined),
    ('Yarın', 'Tomorrow', '19 Kas', 'Güneşli', 'Sunny', 21, 13, '—', Icons.wb_sunny_outlined),
    ('Cmt', 'Sat', '20 Kas', 'Sağanak Yağış', 'Showers', 15, 9, '%75', Icons.umbrella_outlined),
    ('Paz', 'Sun', '21 Kas', 'Çok Bulutlu', 'Cloudy', 14, 8, '%30', Icons.cloud_outlined),
    ('Pzt', 'Mon', '22 Kas', 'Açık & Serin', 'Clear', 17, 10, '—', Icons.wb_twilight_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).size.width > MediaQuery.of(context).size.height;
    final p = widget.palette;
    final skyAccent = p.isLight ? const Color(0xFF0284C7) : const Color(0xFF7DD3FC);

    final summaryCard = Container(
      padding: const EdgeInsets.all(16),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.locationName, style: TextStyle(fontSize: 12, color: skyAccent, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    widget.lang == LangCode.tr ? 'Dış Ortam & Hava Tahmini' : 'Outdoor Weather',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.textPrimary),
                  ),
                ],
              ),
              Text(
                '18.5°C',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.water_drop_outlined, size: 14, color: skyAccent),
              const SizedBox(width: 4),
              Text('%62', style: TextStyle(fontSize: 12, color: p.textSecondary)),
              const SizedBox(width: 12),
              Icon(Icons.air_rounded, size: 14, color: skyAccent),
              const SizedBox(width: 4),
              Text('14 km/s', style: TextStyle(fontSize: 12, color: p.textSecondary)),
            ],
          ),
          Divider(height: 22, color: p.cardBorder),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.lang == LangCode.tr ? 'Dış Isı Kompanzasyonu' : 'Weather Compensation',
                style: TextStyle(fontSize: 12, color: p.textSecondary),
              ),
              TextButton(
                onPressed: () {
                  setState(() => _autoCompensate = !_autoCompensate);
                  widget.onApplyEcoCompensation();
                },
                style: TextButton.styleFrom(
                  backgroundColor: _autoCompensate
                      ? const Color(0xFF0EA5E9).withValues(alpha: 0.22)
                      : p.cardBg,
                  foregroundColor: _autoCompensate ? skyAccent : p.textSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _autoCompensate
                      ? (widget.lang == LangCode.tr ? 'Aktif' : 'Active')
                      : (widget.lang == LangCode.tr ? 'Kapalı' : 'Off'),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final forecastCard = Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.cardBorder),
      ),
      child: Column(
        children: [
          for (int i = 0; i < _forecast.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.cardBorder),
            InkWell(
              onTap: () => setState(() => _selectedDay = i),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                color: _selectedDay == i ? const Color(0xFF38BDF8).withValues(alpha: 0.14) : Colors.transparent,
                child: Row(
                  children: [
                    Icon(_forecast[i].$9, size: 19, color: skyAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.lang == LangCode.tr ? _forecast[i].$1 : _forecast[i].$2} · ${_forecast[i].$3}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.textPrimary),
                          ),
                          Text(
                            widget.lang == LangCode.tr ? _forecast[i].$4 : _forecast[i].$5,
                            style: TextStyle(fontSize: 11, color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(_forecast[i].$8, style: TextStyle(fontSize: 12, color: skyAccent)),
                    const SizedBox(width: 12),
                    Text('${_forecast[i].$6}°', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textPrimary)),
                    const SizedBox(width: 8),
                    Text('${_forecast[i].$7}°', style: TextStyle(fontSize: 12, color: p.textSecondary)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isLandscape ? 920 : 440),
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: summaryCard),
                    const SizedBox(width: 14),
                    Expanded(flex: 7, child: forecastCard),
                  ],
                )
              : Column(
                  children: [
                    summaryCard,
                    const SizedBox(height: 12),
                    forecastCard,
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
                              activeColor: const Color(0xFF10B981),
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
