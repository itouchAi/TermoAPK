import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/schedule_engine.dart';
import '../widgets/blurred_depth_switcher.dart';
import '../widgets/tactile_button.dart';

class ReportScreen extends StatefulWidget {
  final LangCode lang;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final BoilerHardwareSensors sensors;
  final Map<String, DailyThermalLog> dailyLogs;
  final double gasUnitPriceTl;
  final ValueChanged<double>? onUpdateGasUnitPrice;
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
    this.sensors = const BoilerHardwareSensors.disconnected(),
    this.dailyLogs = const {},
    this.gasUnitPriceTl = 10.25,
    this.onUpdateGasUnitPrice,
    required this.subTabOrder,
    required this.palette,
    this.performanceMode = PerformanceMode.ultra60fps,
    this.onBoundaryPrevMainTab,
    this.onBoundaryNextMainTab,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  int _periodIndex = 0; // 0: Günlük, 1: Haftalık, 2: Aylık
  DateTime _selectedDate = DateTime.now();
  int _selectedHourIdx = 0;
  ReportSubTab? _selectedSubTab;
  DateTime? _lastSubSwitchAt;
  final ScrollController _scrollController = ScrollController();
  bool _canVertScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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
      setState(() {
        _selectedSubTab = order[nextIdx];
        _canVertScroll = false;
      });
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
    final useHorizontal = dx.abs() > dy.abs();
    if (!useHorizontal && _canVertScroll && _scrollController.hasClients) {
      final pos = _scrollController.position;
      final atTop = pos.pixels <= 1.0 && dy < 0;
      final atBottom = pos.pixels >= pos.maxScrollExtent - 1.0 && dy > 0;
      if (!atTop && !atBottom) return;
    }
    final dir = useHorizontal ? dx : dy;
    if (dir.abs() < 6.0) return;
    _stepSubTab(dir > 0 ? 1 : -1);
  }

  DateTime _cleanDate(DateTime d) => DateTime(d.year, d.month, d.day);

  String _formatDateButtonLabel(DateTime date, bool tr) {
    final clean = _cleanDate(date);
    final now = _cleanDate(DateTime.now());
    final yesterday = now.subtract(const Duration(days: 1));
    final iso = ThermalLogAggregator.formatDateIso(clean);
    if (_periodIndex == 2) {
      const monthsTr = [
        'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
        'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
      ];
      const monthsEn = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final mName = (tr ? monthsTr : monthsEn)[(clean.month - 1).clamp(0, 11)];
      return '$mName ${clean.year}';
    }
    if (_periodIndex == 1) {
      final start = clean.subtract(const Duration(days: 6));
      return '${start.day}.${start.month.toString().padLeft(2, '0')} – ${clean.day}.${clean.month.toString().padLeft(2, '0')}';
    }
    if (clean == now) return '$iso (${tr ? 'Bugün' : 'Today'})';
    if (clean == yesterday) return '$iso (${tr ? 'Dün' : 'Yesterday'})';
    return iso;
  }

  String _formatShortDayLabel(String iso, bool tr) {
    final parsed = ScheduleEngine.parseDateIso(iso);
    if (parsed == null) return iso;
    const monthsTr = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    const monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final m = (tr ? monthsTr : monthsEn)[(parsed.month - 1).clamp(0, 11)];
    return '${parsed.day} $m';
  }

  Future<void> _pickReportDate() async {
    final now = _cleanDate(DateTime.now());
    final first = DateTime(now.year - 2, 1, 1);
    final current = _cleanDate(_selectedDate);
    final initial = current.isAfter(now) ? now : (current.isBefore(first) ? first : current);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = _cleanDate(picked));
    }
  }

  void _stepSelectedDate(int deltaDays) {
    final now = _cleanDate(DateTime.now());
    final first = DateTime(now.year - 2, 1, 1);
    final candidate = _cleanDate(_selectedDate).add(Duration(days: deltaDays));
    if (candidate.isAfter(now) || candidate.isBefore(first)) return;
    setState(() => _selectedDate = candidate);
  }

  Future<void> _openGasRateEditor() async {
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final themeAccent = p.themeOverrideAccent?.toColor() ??
        (p.isLight ? const Color(0xFF6D28D9) : const Color(0xFFA78BFA));
    final ctrl = TextEditingController(text: widget.gasUnitPriceTl.toStringAsFixed(2));
    String? errorText;

    final updated = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: p.isLight ? const Color(0xFFF8FAFC) : const Color(0xFF10131C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: themeAccent.withValues(alpha: 0.45)),
          ),
          title: Text(
            tr ? 'Doğalgaz m³ Birim Fiyatı' : 'Natural Gas Unit Rate (m³)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr
                    ? 'Faturanızdaki güncel doğalgaz birim fiyatını girin. Tüm aylık tahminler bu değerle hesaplanır.'
                    : 'Enter your current natural gas m³ rate. Monthly bill estimates use this rate.',
                style: TextStyle(fontSize: 11.5, color: p.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                decoration: InputDecoration(
                  suffixText: '₺ / m³',
                  suffixStyle: TextStyle(color: themeAccent, fontWeight: FontWeight.w700),
                  errorText: errorText,
                  isDense: true,
                  filled: true,
                  fillColor: p.scaffoldBg.withValues(alpha: p.isLight ? 0.55 : 0.42),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: themeAccent, width: 1.4),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(
                tr ? 'İptal' : 'Cancel',
                style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                final raw = ctrl.text.trim().replaceAll(',', '.');
                final parsed = double.tryParse(raw);
                if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 500) {
                  setDialogState(() {
                    errorText = tr ? 'Geçerli bir fiyat girin (0.01 - 500)' : 'Enter valid rate (0.01 - 500)';
                  });
                  return;
                }
                Navigator.of(dialogCtx).pop(double.parse(parsed.toStringAsFixed(2)));
              },
              icon: const Icon(Icons.check_rounded, size: 16),
              label: Text(tr ? 'Kaydet' : 'Save', style: const TextStyle(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: themeAccent,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (updated != null && mounted) {
      widget.onUpdateGasUnitPrice?.call(updated);
    }
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
    final safeGasRate = widget.gasUnitPriceTl > 0 ? widget.gasUnitPriceTl : 10.25;
    final nowClean = _cleanDate(DateTime.now());
    final anchorDate = _cleanDate(_selectedDate).isAfter(nowClean) ? nowClean : _cleanDate(_selectedDate);
    final canStepForward = anchorDate.isBefore(nowClean);

    final periodSummary = ThermalLogAggregator.summarize(
      logs: widget.dailyLogs,
      anchorDate: anchorDate,
      periodIndex: _periodIndex,
      gasUnitPriceTl: safeGasRate,
    );
    final monthlySummary = ThermalLogAggregator.summarize(
      logs: widget.dailyLogs,
      anchorDate: anchorDate,
      periodIndex: 2,
      gasUnitPriceTl: safeGasRate,
    );

    final selectedIso = ThermalLogAggregator.formatDateIso(anchorDate);
    final dayLog = widget.dailyLogs[selectedIso] ?? DailyThermalLog.empty(selectedIso);
    final periodBurnLabel = ThermalLogAggregator.formatDuration(periodSummary.activeBurnSeconds, widget.lang);
    final periodStandbyLabel = ThermalLogAggregator.formatDuration(periodSummary.standbySeconds, widget.lang);
    const hours = DailyThermalLog.blockLabels;

    Widget buildHeatMapView() {
      Widget buildHourTile(int i) {
        final selected = i == _selectedHourIdx;
        final bucket = i < dayLog.buckets.length ? dayLog.buckets[i] : ThermalHourBucket(blockIndex: i);
        final hasData = bucket.hasData;
        final activeBurn = bucket.hadActiveBurn;
        final tVal = bucket.avgTemp;
        final tempStr = tVal != null ? '${tVal.toStringAsFixed(1)}°' : '--';
        return TactilePress.card(
          child: GestureDetector(
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
                        tempStr,
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
                      tempStr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasData ? p.textSecondary : p.textSecondary.withValues(alpha: 0.55),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  const SizedBox(height: 5),
                  Text(
                    !hasData
                        ? (tr ? 'Kayıt yok' : 'No log')
                        : (activeBurn ? (tr ? '🔥 Aktif' : '🔥 Active') : (tr ? '❄️ Bekleme' : '❄️ Idle')),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: !hasData
                          ? p.textSecondary.withValues(alpha: 0.65)
                          : (activeBurn ? themeAccent : p.textSecondary),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      Widget buildWeeklyBreakdown() {
        final days = periodSummary.dayBreakdown;
        final maxBurn = days.fold<int>(1, (m, d) => d.activeBurnSeconds > m ? d.activeBurnSeconds : m);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Haftalık Log Analizi' : 'Weekly Log Analytics',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                ),
                Text(
                  tr
                      ? '${periodSummary.daysWithData}/7 gün kayıtlı · ${periodSummary.gasM3.toStringAsFixed(2)} m³'
                      : '${periodSummary.daysWithData}/7 days logged · ${periodSummary.gasM3.toStringAsFixed(2)} m³',
                  style: TextStyle(fontSize: 10, color: themeAccent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final d in days) ...[
              TactilePress.card(
                child: GestureDetector(
                  onTap: () {
                    final parsed = ScheduleEngine.parseDateIso(d.dateIso);
                    if (parsed != null) {
                      setState(() => _selectedDate = parsed);
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: d.dateIso == selectedIso
                          ? themeAccent.withValues(alpha: 0.16)
                          : p.scaffoldBg.withValues(alpha: p.isLight ? 0.42 : 0.32),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: d.dateIso == selectedIso ? themeAccent.withValues(alpha: 0.65) : p.cardBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            _formatShortDayLabel(d.dateIso, tr),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: d.dateIso == selectedIso ? p.textPrimary : p.textSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              height: 6,
                              color: p.cardBorder.withValues(alpha: 0.45),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor: d.activeBurnSeconds > 0
                                      ? (d.activeBurnSeconds / maxBurn).clamp(0.08, 1.0)
                                      : 0.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: themeAccent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 58,
                          child: Text(
                            d.hasData
                                ? ThermalLogAggregator.formatDuration(d.activeBurnSeconds, widget.lang)
                                : '--',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: d.hasData ? p.textPrimary : p.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          child: Text(
                            d.hasData ? '${d.gasM3.toStringAsFixed(2)}m³' : '--',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: emerald,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 34,
                          child: Text(
                            d.avgTemp != null ? '${d.avgTemp!.toStringAsFixed(1)}°' : '--',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: p.textSecondary,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      }

      Widget buildMonthlyBreakdown() {
        final days = periodSummary.dayBreakdown;
        final weeks = <({String label, int burnSec, double gasM3, int activeDays})>[];
        for (int start = 0; start < days.length; start += 7) {
          final end = (start + 7).clamp(0, days.length);
          final slice = days.sublist(start, end);
          int burnSec = 0;
          double gas = 0.0;
          int logged = 0;
          for (final d in slice) {
            burnSec += d.activeBurnSeconds;
            gas += d.gasM3;
            if (d.hasData) logged++;
          }
          final firstDay = start + 1;
          final lastDay = end;
          weeks.add((
            label: tr ? '$firstDay–$lastDay. Gün' : 'Days $firstDay–$lastDay',
            burnSec: burnSec,
            gasM3: gas,
            activeDays: logged,
          ));
        }
        final maxWeekBurn = weeks.fold<int>(1, (m, w) => w.burnSec > m ? w.burnSec : m);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Aylık Hafta Dağılımı' : 'Monthly Week Breakdown',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                ),
                Text(
                  tr
                      ? '${periodSummary.daysWithData}/${periodSummary.totalDaysInPeriod} gün kayıtlı'
                      : '${periodSummary.daysWithData}/${periodSummary.totalDaysInPeriod} days logged',
                  style: TextStyle(fontSize: 10, color: themeAccent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final w in weeks)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.42 : 0.34),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        w.label,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.textPrimary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          height: 6,
                          color: p.cardBorder.withValues(alpha: 0.45),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: w.burnSec > 0 ? (w.burnSec / maxWeekBurn).clamp(0.08, 1.0) : 0.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: themeAccent,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      w.activeDays > 0
                          ? ThermalLogAggregator.formatDuration(w.burnSec, widget.lang)
                          : '--',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${w.gasM3.toStringAsFixed(2)} m³',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: emerald,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              periodSummary.hasAnyData
                  ? (tr
                      ? 'Ay ort. oda: ${periodSummary.avgTemp != null ? '${periodSummary.avgTemp!.toStringAsFixed(1)}°C' : '--'} · Toplam: ${periodSummary.gasM3.toStringAsFixed(2)} m³ (${periodSummary.costTl.toStringAsFixed(2)} ₺)'
                      : 'Month avg room: ${periodSummary.avgTemp != null ? '${periodSummary.avgTemp!.toStringAsFixed(1)}°C' : '--'} · Total: ${periodSummary.gasM3.toStringAsFixed(2)} m³ (${periodSummary.costTl.toStringAsFixed(2)} ₺)')
                  : (tr
                      ? 'Bu ay için henüz log kaydı yok — sistem çalıştıkça veriler otomatik yazılır.'
                      : 'No logs recorded for this month yet — telemetry logs automatically while running.'),
              style: TextStyle(fontSize: 10, color: p.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        );
      }

      final selectedBucket = _selectedHourIdx < dayLog.buckets.length
          ? dayLog.buckets[_selectedHourIdx]
          : ThermalHourBucket(blockIndex: _selectedHourIdx);

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

            // Segmented Günlük / Haftalık / Aylık bar
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
                      child: TactilePress(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _periodIndex = seg.$1;
                            _canVertScroll = false;
                          }),
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
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Examined Day Date Picker + Active Burn Summary Box
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
                            _periodIndex == 0
                                ? (tr ? 'İncelenen Gün:' : 'Selected Day:')
                                : _periodIndex == 1
                                    ? (tr ? 'Bitiş Tarihi:' : 'Week Ending:')
                                    : (tr ? 'İncelenen Ay:' : 'Selected Month:'),
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: p.textSecondary),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TactilePress(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _stepSelectedDate(_periodIndex == 2 ? -30 : -1),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(Icons.chevron_left_rounded, size: 17, color: p.textSecondary),
                              ),
                            ),
                          ),
                          TactilePress(
                            child: GestureDetector(
                              onTap: _pickReportDate,
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
                                      _formatDateButtonLabel(anchorDate, tr),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: p.textPrimary,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(Icons.calendar_month_rounded, size: 13, color: p.textPrimary),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          TactilePress(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: canStepForward
                                  ? () => _stepSelectedDate(_periodIndex == 2 ? 30 : 1)
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 17,
                                  color: canStepForward
                                      ? p.textSecondary
                                      : p.textSecondary.withValues(alpha: 0.28),
                                ),
                              ),
                            ),
                          ),
                        ],
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
                            periodBurnLabel,
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
                            periodStandbyLabel,
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

            if (_periodIndex == 1)
              buildWeeklyBreakdown()
            else if (_periodIndex == 2)
              buildMonthlyBreakdown()
            else ...[
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
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.36 : 0.28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Text(
                  selectedBucket.hasData
                      ? (tr
                          ? '${hours[_selectedHourIdx]} dilimi · Aktif yanma: ${ThermalLogAggregator.formatDuration(selectedBucket.activeBurnSeconds, widget.lang)} · Bekleme: ${ThermalLogAggregator.formatDuration(selectedBucket.standbySeconds, widget.lang)}'
                          : '${hours[_selectedHourIdx]} slot · Active burn: ${ThermalLogAggregator.formatDuration(selectedBucket.activeBurnSeconds, widget.lang)} · Standby: ${ThermalLogAggregator.formatDuration(selectedBucket.standbySeconds, widget.lang)}')
                      : (tr
                          ? '${hours[_selectedHourIdx]} dilimi için henüz log kaydedilmedi.'
                          : 'No log recorded for the ${hours[_selectedHourIdx]} slot yet.'),
                  style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget buildUsageBillView() {
      final monthlyBurnLabel = ThermalLogAggregator.formatDuration(monthlySummary.activeBurnSeconds, widget.lang);
      const monthsTr = [
        'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
        'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
      ];
      const monthsEn = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final monthTitle = '${(tr ? monthsTr : monthsEn)[(anchorDate.month - 1).clamp(0, 11)]} ${anchorDate.year}';

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
                    tr ? 'Aylık · $monthTitle' : 'Monthly · $monthTitle',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: themeAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.40 : 0.36),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr ? 'Doğalgaz m³ Birim Fiyatı' : 'Natural Gas Unit Rate',
                          style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${safeGasRate.toStringAsFixed(2)} ₺ / m³',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: themeAccent,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  TactilePress(
                    child: OutlinedButton.icon(
                      onPressed: _openGasRateEditor,
                      icon: Icon(Icons.edit_outlined, size: 14, color: themeAccent),
                      label: Text(
                        tr ? 'Düzenle' : 'Edit',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: themeAccent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: themeAccent.withValues(alpha: 0.55)),
                        backgroundColor: themeAccent.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
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
                    title: tr ? 'SAYAÇ TÜKETİMİ (AYLIK)' : 'MONTHLY GAS USAGE',
                    value: '${monthlySummary.gasM3.toStringAsFixed(2)} m³',
                    sub: tr
                        ? 'Aktif yanma: $monthlyBurnLabel (${monthlySummary.daysWithData} gün)'
                        : 'Active burn: $monthlyBurnLabel (${monthlySummary.daysWithData}d)',
                    palette: p,
                    accentTextColor: p.isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    title: tr ? 'TAHMİNİ TUTAR (AYLIK)' : 'MONTHLY EST. BILL',
                    value: '${monthlySummary.costTl.toStringAsFixed(2)} ₺',
                    sub: tr
                        ? '↘ ~${monthlySummary.savedTl.toStringAsFixed(2)} ₺ Modülasyon tasarrufu'
                        : '↘ ~${monthlySummary.savedTl.toStringAsFixed(2)} ₺ Modulated savings',
                    palette: p,
                    accentTextColor: emerald,
                  ),
                ),
              ],
            ),
            if (_periodIndex != 2) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.35 : 0.28),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Text(
                  tr
                      ? 'Seçili dönem (${_periodIndex == 0 ? 'Günlük' : 'Haftalık'}): ${periodSummary.gasM3.toStringAsFixed(2)} m³ · ${periodSummary.costTl.toStringAsFixed(2)} ₺ ($periodBurnLabel)'
                      : 'Selected (${_periodIndex == 0 ? 'Daily' : 'Weekly'}): ${periodSummary.gasM3.toStringAsFixed(2)} m³ · ${periodSummary.costTl.toStringAsFixed(2)} ₺ ($periodBurnLabel)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              tr
                  ? '💡 Değerler önceki sayfadaki kaydedilen termal loglardan ve girdiğiniz m³ birim fiyatından aylık olarak hesaplanır.'
                  : '💡 Figures are calculated monthly from persisted thermal logs and your configured m³ unit rate.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, color: p.textSecondary),
            ),
          ],
        ),
      );
    }

    Widget buildSensorsView() {
      final s = widget.sensors;
      final connected = s.isConnected;
      final supplyText = (connected && s.supplyTempC != null) ? '${s.supplyTempC!.toStringAsFixed(1)}°C' : '--';
      final returnText = (connected && s.returnTempC != null) ? '${s.returnTempC!.toStringAsFixed(1)}°C' : '--';
      final flameText = (connected && s.flamePercent != null) ? '%${s.flamePercent}' : '--';
      final pumpText = (connected && s.pumpRpm != null) ? '${s.pumpRpm} RPM' : '--';
      final pressureText = (connected && s.waterPressureBar != null)
          ? '${s.waterPressureBar!.toStringAsFixed(1)} Bar'
          : '--';
      final ionizationText = (connected && s.ionizationUa != null)
          ? '${s.ionizationUa!.toStringAsFixed(1)} µA'
          : '--';

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
                    color: (connected ? emerald : p.textSecondary).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: (connected ? emerald : p.textSecondary).withValues(alpha: 0.40)),
                  ),
                  child: Text(
                    connected
                        ? (s.protocolLabel.isNotEmpty ? s.protocolLabel : 'OpenTherm')
                        : (tr ? 'Sensör Bağlı Değil' : 'No Sensor'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: connected ? emerald : p.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (!connected) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.40 : 0.30),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: p.cardBorder),
                ),
                child: Text(
                  tr
                      ? 'Fiziksel kombi sensörü (ESP32 / OpenTherm) bağlı olmadığı için ölçümler boş gösterilir.'
                      : 'No physical boiler sensor bus connected; hardware readings remain empty (--).',
                  style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Divider(color: p.cardBorder, height: 1),
            const SizedBox(height: 8),
            _SensorRow(label: tr ? 'Gidiş Suyu Sıcaklığı' : 'Supply Water Temp', value: supplyText, palette: p),
            _SensorRow(label: tr ? 'Dönüş Suyu Sıcaklığı' : 'Return Water Temp', value: returnText, palette: p),
            _SensorRow(label: tr ? 'Alev Gücü' : 'Flame Power', value: flameText, palette: p),
            _SensorRow(label: tr ? 'Sirkülasyon Pompası' : 'Circulation Pump', value: pumpText, palette: p),
            _SensorRow(label: tr ? 'Tesisat Basıncı' : 'Loop Water Pressure', value: pressureText, palette: p),
            _SensorRow(label: tr ? 'İyonizasyon Alev Sensörü' : 'Ionization Flame Sensor', value: ionizationText, palette: p),
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
          if (_canVertScroll) return;
          final v = details.primaryVelocity ?? 0.0;
          if (v.abs() < 160) return;
          _stepSubTab(v < 0 ? 1 : -1);
        },
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              final nextCan = notification.metrics.maxScrollExtent > 4.0;
              if (nextCan != _canVertScroll) {
                _canVertScroll = nextCan;
              }
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const ClampingScrollPhysics(),
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

                    // Centered Floating Capsule Sub-Tab Switcher
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
                                TactilePress(
                                  child: GestureDetector(
                                    onTap: () => setState(() {
                                      _selectedSubTab = sub;
                                      _canVertScroll = false;
                                    }),
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
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    BlurredDepthSubTabSwitcher(
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
