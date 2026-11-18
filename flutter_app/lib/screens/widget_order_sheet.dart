import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';

Future<void> showWidgetOrderSheet({
  required BuildContext context,
  required LangCode lang,
  required Color accentColor,
  required bool hapticEnabled,
  required VisualCustomizationState initialVisual,
  required ValueChanged<VisualCustomizationState> onUpdateVisual,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WidgetOrderModal(
      lang: lang,
      accentColor: accentColor,
      hapticEnabled: hapticEnabled,
      initialVisual: initialVisual,
      onUpdateVisual: onUpdateVisual,
    ),
  );
}

class _WidgetOrderModal extends StatefulWidget {
  final LangCode lang;
  final Color accentColor;
  final bool hapticEnabled;
  final VisualCustomizationState initialVisual;
  final ValueChanged<VisualCustomizationState> onUpdateVisual;

  const _WidgetOrderModal({
    required this.lang,
    required this.accentColor,
    required this.hapticEnabled,
    required this.initialVisual,
    required this.onUpdateVisual,
  });

  @override
  State<_WidgetOrderModal> createState() => _WidgetOrderModalState();
}

class _WidgetOrderModalState extends State<_WidgetOrderModal> {
  late VisualCustomizationState _visual;

  @override
  void initState() {
    super.initState();
    _visual = widget.initialVisual;
  }

  void _apply(VisualCustomizationState next) {
    if (widget.hapticEnabled) HapticFeedback.selectionClick();
    setState(() => _visual = next);
    widget.onUpdateVisual(next);
  }

  List<T> _swapAt<T>(List<T> src, int idx, int delta) {
    final target = idx + delta;
    if (target < 0 || target >= src.length) return src;
    final copy = List<T>.from(src);
    final item = copy.removeAt(idx);
    copy.insert(target, item);
    return copy;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final tr = widget.lang == LangCode.tr;
    final palette = _visual.resolvePalette();

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.88),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 660 : 480),
        child: Container(
          decoration: BoxDecoration(
            color: palette.sheetBg.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: palette.cardBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 36, offset: const Offset(0, -10)),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: widget.accentColor.withValues(alpha: 0.16),
                        border: Border.all(color: widget.accentColor.withValues(alpha: 0.40)),
                      ),
                      child: Icon(Icons.dashboard_customize_outlined, color: widget.accentColor, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr ? 'Ekran & Menü Sıralaması' : 'Screen & Menu Order',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: palette.textPrimary),
                          ),
                          Text(
                            tr
                                ? 'Ana sayfaları ve alt sekmeleri oklarla taşıyın'
                                : 'Reorder main tabs and inner sub-tabs',
                            style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: palette.cardBg,
                        side: BorderSide(color: palette.cardBorder),
                      ),
                      icon: Icon(Icons.close_rounded, color: palette.textPrimary, size: 19),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: palette.cardBorder),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  children: [
                    _SectionTitle(
                      title: tr ? 'ANA EKRAN SIRALAMASI (KARUSEL & ALT ÇUBUK)' : 'MAIN SCREEN ORDER (FLOW BAR & PAGES)',
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _visual.orderedTabs.length; i++)
                      _OrderTile(
                        title: tr ? _visual.orderedTabs[i].labelTr : _visual.orderedTabs[i].labelEn,
                        subtitle: '${tr ? 'Sıra' : 'Slot'} ${i + 1}',
                        icon: _iconForTab(_visual.orderedTabs[i].id),
                        color: _visual.orderedTabs[i].color,
                        index: i,
                        total: _visual.orderedTabs.length,
                        palette: palette,
                        onMoveUp: () => _apply(
                          _visual.copyWith(tabOrder: _swapAt(_visual.tabOrder, i, -1)),
                        ),
                        onMoveDown: () => _apply(
                          _visual.copyWith(tabOrder: _swapAt(_visual.tabOrder, i, 1)),
                        ),
                      ),

                    const SizedBox(height: 14),
                    _SectionTitle(
                      title: tr ? 'RAPOR ALT SEKMELERİ (İÇ SIRALAMA)' : 'REPORT SUB-TABS (INNER ORDER)',
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _visual.reportSubTabOrder.length; i++)
                      _OrderTile(
                        title: _labelForReportSub(_visual.reportSubTabOrder[i], tr),
                        subtitle: '${tr ? 'Sıra' : 'Order'} ${i + 1}',
                        icon: _iconForReportSub(_visual.reportSubTabOrder[i]),
                        color: const Color(0xFF8C66FF),
                        index: i,
                        total: _visual.reportSubTabOrder.length,
                        palette: palette,
                        onMoveUp: () => _apply(
                          _visual.copyWith(reportSubTabOrder: _swapAt(_visual.reportSubTabOrder, i, -1)),
                        ),
                        onMoveDown: () => _apply(
                          _visual.copyWith(reportSubTabOrder: _swapAt(_visual.reportSubTabOrder, i, 1)),
                        ),
                      ),

                    const SizedBox(height: 14),
                    _SectionTitle(
                      title: tr ? 'PROGRAM ALT SEKMELERİ (İÇ SIRALAMA)' : 'SCHEDULE SUB-TABS (INNER ORDER)',
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _visual.scheduleSubTabOrder.length; i++)
                      _OrderTile(
                        title: _labelForScheduleSub(_visual.scheduleSubTabOrder[i], tr),
                        subtitle: '${tr ? 'Sıra' : 'Order'} ${i + 1}',
                        icon: _visual.scheduleSubTabOrder[i] == ScheduleSubTab.smartSchedule
                            ? Icons.schedule_rounded
                            : Icons.savings_outlined,
                        color: const Color(0xFF10B981),
                        index: i,
                        total: _visual.scheduleSubTabOrder.length,
                        palette: palette,
                        onMoveUp: () => _apply(
                          _visual.copyWith(scheduleSubTabOrder: _swapAt(_visual.scheduleSubTabOrder, i, -1)),
                        ),
                        onMoveDown: () => _apply(
                          _visual.copyWith(scheduleSubTabOrder: _swapAt(_visual.scheduleSubTabOrder, i, 1)),
                        ),
                      ),
                  ],
                ),
              ),

              // Footer
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: palette.sheetBg,
                  border: Border(top: BorderSide(color: palette.cardBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () => _apply(
                        _visual.copyWith(
                          tabOrder: VisualCustomizationState.defaultTabOrder,
                          reportSubTabOrder: VisualCustomizationState.defaultReportSubOrder,
                          scheduleSubTabOrder: VisualCustomizationState.defaultScheduleSubOrder,
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(tr ? 'Varsayılan Düzene Dön' : 'Reset Default Order'),
                      style: TextButton.styleFrom(foregroundColor: palette.textSecondary),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                      ),
                      child: Text(tr ? 'Tamam' : 'Done', style: const TextStyle(fontWeight: FontWeight.w700)),
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

  IconData _iconForTab(TabId id) {
    switch (id) {
      case TabId.termo:
        return Icons.thermostat_rounded;
      case TabId.hava:
        return Icons.wb_cloudy_outlined;
      case TabId.rapor:
        return Icons.pie_chart_outline_rounded;
      case TabId.prog:
        return Icons.schedule_rounded;
    }
  }

  String _labelForReportSub(ReportSubTab id, bool tr) {
    switch (id) {
      case ReportSubTab.heatMap:
        return tr ? 'Sıcaklık Haritası' : 'Heat Map';
      case ReportSubTab.usageBill:
        return tr ? 'Tüketim & Fatura' : 'Usage & Bill';
      case ReportSubTab.boilerSensors:
        return tr ? 'Kombi Sensörleri & Telemetri' : 'Boiler Sensors & Telemetry';
    }
  }

  IconData _iconForReportSub(ReportSubTab id) {
    switch (id) {
      case ReportSubTab.heatMap:
        return Icons.grid_view_rounded;
      case ReportSubTab.usageBill:
        return Icons.receipt_long_outlined;
      case ReportSubTab.boilerSensors:
        return Icons.sensors_rounded;
    }
  }

  String _labelForScheduleSub(ScheduleSubTab id, bool tr) {
    switch (id) {
      case ScheduleSubTab.smartSchedule:
        return tr ? 'Akıllı Zaman Programı' : 'Smart Time Schedule';
      case ScheduleSubTab.dailySavings:
        return tr ? 'Günlük Tüketim & Tasarruf' : 'Daily Usage & Savings';
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final ThemePaletteSpec palette;

  const _SectionTitle({required this.title, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.9, color: palette.textSecondary),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int index;
  final int total;
  final ThemePaletteSpec palette;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _OrderTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.index,
    required this.total,
    required this.palette,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: palette.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.16),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textPrimary),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: palette.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: index > 0 ? onMoveUp : null,
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 22),
            color: palette.textPrimary,
            disabledColor: palette.textSecondary.withValues(alpha: 0.25),
            tooltip: 'Yukarı taşı',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            onPressed: index < total - 1 ? onMoveDown : null,
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
            color: palette.textPrimary,
            disabledColor: palette.textSecondary.withValues(alpha: 0.25),
            tooltip: 'Aşağı taşı',
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
