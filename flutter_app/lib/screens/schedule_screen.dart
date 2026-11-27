import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/schedule_engine.dart';
import '../widgets/blurred_depth_switcher.dart';
import '../widgets/tactile_button.dart';

class ScheduleScreen extends StatefulWidget {
  final LangCode lang;
  final List<ScheduleSlot> slots;
  final List<CustomScheduleRule> customRules;
  final List<ScheduleSubTab> subTabOrder;
  final ThemePaletteSpec palette;
  final BoilerTelemetry? boiler;
  final BoilerHardwareSensors sensors;
  final DailyThermalLog? todayLog;
  final double gasUnitPriceTl;
  final PerformanceMode performanceMode;
  final void Function(String id, {String? time, bool? enabled, double? targetTemp}) onUpdateSlot;
  final ValueChanged<CustomScheduleRule>? onAddCustomRule;
  final ValueChanged<CustomScheduleRule>? onUpdateCustomRule;
  final ValueChanged<String>? onDeleteCustomRule;
  final VoidCallback onSaveSchedule;
  final bool savedNotice;
  final VoidCallback? onBoundaryPrevMainTab;
  final VoidCallback? onBoundaryNextMainTab;

  const ScheduleScreen({
    super.key,
    required this.lang,
    required this.slots,
    this.customRules = const [],
    required this.subTabOrder,
    required this.palette,
    this.boiler,
    this.sensors = const BoilerHardwareSensors.disconnected(),
    this.todayLog,
    this.gasUnitPriceTl = 10.25,
    this.performanceMode = PerformanceMode.ultra60fps,
    required this.onUpdateSlot,
    this.onAddCustomRule,
    this.onUpdateCustomRule,
    this.onDeleteCustomRule,
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
  final ScrollController _scrollController = ScrollController();
  bool _canVertScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  TimeOfDay _parseTimeOfDay(String hhmm, TimeOfDay fallback) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTimeOfDay(TimeOfDay tod) {
    return '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDefaultSlotTime(ScheduleSlot slot) async {
    final initial = _parseTimeOfDay(slot.time, const TimeOfDay(hour: 8, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (picked == null || !mounted) return;
    widget.onUpdateSlot(slot.id, time: _formatTimeOfDay(picked));
  }

  Future<void> _openCustomRuleEditor({CustomScheduleRule? existing}) async {
    final tr = widget.lang == LangCode.tr;
    final p = widget.palette;
    final emerald = p.isLight ? const Color(0xFF059669) : const Color(0xFF34D399);
    final themeAccent = p.themeOverrideAccent?.toColor() ?? emerald;
    final now = DateTime.now();
    final todayIso = ScheduleEngine.formatDateIso(now);
    final tomorrowIso = ScheduleEngine.formatDateIso(now.add(const Duration(days: 1)));

    var actionType = existing?.actionType ?? ScheduleActionType.openOnly;
    var openTime = existing?.openTime ?? '08:00';
    var openTargetTemp = existing?.openTargetTemp ?? 22.5;
    var closeTime = existing?.closeTime ?? '23:00';
    var repeatMode = existing?.repeatMode ?? ScheduleRepeatMode.specificDate;
    var specificDateIso = existing?.specificDateIso ?? todayIso;
    var repeatWeekdays = List<int>.from(existing?.repeatWeekdays ?? const [1, 2, 3, 4, 5]);

    String defaultTitleFor(ScheduleActionType t) {
      if (tr) {
        return switch (t) {
          ScheduleActionType.openOnly => 'Planlı Açma',
          ScheduleActionType.closeOnly => 'Planlı Kapatma',
          ScheduleActionType.openAndClose => 'Zamanlı Aç & Kapat',
        };
      }
      return switch (t) {
        ScheduleActionType.openOnly => 'Scheduled Open',
        ScheduleActionType.closeOnly => 'Scheduled Close',
        ScheduleActionType.openAndClose => 'Timed Open & Close',
      };
    }

    var titleEdited = existing != null;
    final titleCtrl = TextEditingController(
      text: existing?.title ?? defaultTitleFor(actionType),
    );

    final result = await showDialog<CustomScheduleRule>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final hasOpen = actionType == ScheduleActionType.openOnly ||
                actionType == ScheduleActionType.openAndClose;
            final hasClose = actionType == ScheduleActionType.closeOnly ||
                actionType == ScheduleActionType.openAndClose;
            final openMin = ScheduleEngine.parseHhMmMinutes(openTime) ?? 480;
            final closeMin = ScheduleEngine.parseHhMmMinutes(closeTime) ?? 1380;
            final isOvernight = hasOpen && hasClose && closeMin < openMin;

            const dayItems = <(int, String, String)>[
              (1, 'Pzt', 'Mon'),
              (2, 'Sal', 'Tue'),
              (3, 'Çar', 'Wed'),
              (4, 'Per', 'Thu'),
              (5, 'Cum', 'Fri'),
              (6, 'Cmt', 'Sat'),
              (7, 'Paz', 'Sun'),
            ];

            Widget sectionTitle(String text) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: themeAccent,
                    ),
                  ),
                );

            Widget actionCard(ScheduleActionType type, IconData icon, String title, String sub) {
              final selected = actionType == type;
              return Expanded(
                child: TactilePress.card(
                  child: GestureDetector(
                    onTap: () {
                      setDialogState(() {
                        actionType = type;
                        if (!titleEdited) {
                          titleCtrl.text = defaultTitleFor(type);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      decoration: BoxDecoration(
                        color: selected
                            ? themeAccent.withValues(alpha: 0.22)
                            : p.scaffoldBg.withValues(alpha: p.isLight ? 0.55 : 0.45),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? themeAccent : p.cardBorder,
                          width: selected ? 1.4 : 1.0,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(icon, size: 17, color: selected ? themeAccent : p.textSecondary),
                          const SizedBox(height: 4),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: selected ? p.textPrimary : p.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, color: p.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return Dialog(
              backgroundColor: p.isLight ? const Color(0xFFF8FAFC) : const Color(0xFF10131C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: themeAccent.withValues(alpha: 0.42)),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.event_available_rounded, size: 20, color: themeAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              existing == null
                                  ? (tr ? 'Yeni Akıllı Zamanlama Planı' : 'New Smart Schedule Plan')
                                  : (tr ? 'Zamanlama Planını Düzenle' : 'Edit Schedule Plan'),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                          ),
                          TactilePress(
                            child: IconButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              icon: Icon(Icons.close_rounded, size: 18, color: p.textSecondary),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Plan Title
                      TextField(
                        controller: titleCtrl,
                        onChanged: (_) => titleEdited = true,
                        style: TextStyle(fontSize: 13, color: p.textPrimary, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: tr ? 'Plan Adı' : 'Plan Name',
                          labelStyle: TextStyle(fontSize: 11.5, color: p.textSecondary),
                          isDense: true,
                          filled: true,
                          fillColor: p.scaffoldBg.withValues(alpha: p.isLight ? 0.50 : 0.40),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: p.cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: themeAccent, width: 1.4),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Flight-style Independent Open / Close Action Selector
                      sectionTitle(
                        tr
                            ? 'Aksiyon Tipi (Bağımsız Aç / Kapat Seçimi)'
                            : 'Action Mode (Independent Open / Close)',
                      ),
                      Row(
                        children: [
                          actionCard(
                            ScheduleActionType.openOnly,
                            Icons.power_settings_new_rounded,
                            tr ? 'Sadece Aç' : 'Open Only',
                            tr ? 'Tek yön açılış' : 'Open only',
                          ),
                          const SizedBox(width: 8),
                          actionCard(
                            ScheduleActionType.closeOnly,
                            Icons.power_off_rounded,
                            tr ? 'Sadece Kapat' : 'Close Only',
                            tr ? 'Tek yön kapanış' : 'Close only',
                          ),
                          const SizedBox(width: 8),
                          actionCard(
                            ScheduleActionType.openAndClose,
                            Icons.swap_horiz_rounded,
                            tr ? 'Aç & Kapat' : 'Open & Close',
                            tr ? 'Başlat & bitir' : 'Start & stop',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Open Time & Target Temp
                      if (hasOpen) ...[
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: emerald.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: emerald.withValues(alpha: 0.32)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    tr ? '🔥 Kombi Açılış Saati' : '🔥 Boiler Open Time',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textPrimary),
                                  ),
                                  TactilePress(
                                    child: GestureDetector(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: dialogCtx,
                                          initialTime: _parseTimeOfDay(openTime, const TimeOfDay(hour: 8, minute: 0)),
                                          builder: (c, child) => MediaQuery(
                                            data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                                            child: child ?? const SizedBox.shrink(),
                                          ),
                                        );
                                        if (picked != null) {
                                          setDialogState(() => openTime = _formatTimeOfDay(picked));
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: emerald.withValues(alpha: 0.22),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: emerald.withValues(alpha: 0.55)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.access_time_rounded, size: 14, color: emerald),
                                            const SizedBox(width: 5),
                                            Text(
                                              openTime,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: p.textPrimary,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    tr ? 'Hedef Sıcaklık:' : 'Target Temperature:',
                                    style: TextStyle(fontSize: 11.5, color: p.textSecondary),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TactilePress(
                                        child: IconButton(
                                          onPressed: () => setDialogState(() {
                                            openTargetTemp = ThermostatMath.snapTemperature(openTargetTemp - 0.5);
                                          }),
                                          icon: Icon(Icons.remove_circle_outline_rounded, size: 20, color: p.textPrimary),
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6),
                                        child: Text(
                                          '${openTargetTemp.toStringAsFixed(1)}°C',
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w800,
                                            color: emerald,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ),
                                      TactilePress(
                                        child: IconButton(
                                          onPressed: () => setDialogState(() {
                                            openTargetTemp = ThermostatMath.snapTemperature(openTargetTemp + 0.5);
                                          }),
                                          icon: Icon(Icons.add_circle_outline_rounded, size: 20, color: p.textPrimary),
                                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          padding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Close Time
                      if (hasClose) ...[
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF43F5E).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.30)),
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
                                      Text(
                                        tr ? '⏸ Kombi Kapanış Saati' : '⏸ Boiler Close Time',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.textPrimary),
                                      ),
                                      Text(
                                        tr
                                            ? 'Bekleme modu (${ThermostatMath.minTemp.toStringAsFixed(0)}°C)'
                                            : 'Standby off (${ThermostatMath.minTemp.toStringAsFixed(0)}°C)',
                                        style: TextStyle(fontSize: 10, color: p.textSecondary),
                                      ),
                                    ],
                                  ),
                                  TactilePress(
                                    child: GestureDetector(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: dialogCtx,
                                          initialTime: _parseTimeOfDay(closeTime, const TimeOfDay(hour: 23, minute: 0)),
                                          builder: (c, child) => MediaQuery(
                                            data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                                            child: child ?? const SizedBox.shrink(),
                                          ),
                                        );
                                        if (picked != null) {
                                          setDialogState(() => closeTime = _formatTimeOfDay(picked));
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF43F5E).withValues(alpha: 0.20),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFF43F5E).withValues(alpha: 0.50)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFFFDA4AF)),
                                            const SizedBox(width: 5),
                                            Text(
                                              closeTime,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: p.textPrimary,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (isOvernight) ...[
                                const SizedBox(height: 6),
                                Text(
                                  tr
                                      ? 'ℹ️ Kapanış saati açılıştan önce olduğu için ertesi gün uygulanır.'
                                      : 'ℹ️ Close time is earlier than open time, so it executes the next day.',
                                  style: TextStyle(fontSize: 10, color: p.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Calendar Date or Periodic Frequency Selector
                      sectionTitle(tr ? 'Takvim / Periyodik Tekrar' : 'Calendar / Periodic Repeat'),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final opt in <(ScheduleRepeatMode, String)>[
                            (ScheduleRepeatMode.specificDate, tr ? '📅 Belirli Tarih' : '📅 Specific Date'),
                            (ScheduleRepeatMode.daily, tr ? '🔁 Her Gün' : '🔁 Every Day'),
                            (ScheduleRepeatMode.weekdays, tr ? '💼 Hafta İçi' : '💼 Weekdays'),
                            (ScheduleRepeatMode.weekends, tr ? '🏠 Hafta Sonu' : '🏠 Weekends'),
                            (ScheduleRepeatMode.customDays, tr ? '🗓️ Özel Günler' : '🗓️ Custom Days'),
                          ])
                            TactilePress(
                              child: GestureDetector(
                                onTap: () => setDialogState(() => repeatMode = opt.$1),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: repeatMode == opt.$1
                                        ? themeAccent.withValues(alpha: 0.22)
                                        : p.scaffoldBg.withValues(alpha: p.isLight ? 0.50 : 0.38),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: repeatMode == opt.$1 ? themeAccent : p.cardBorder,
                                    ),
                                  ),
                                  child: Text(
                                    opt.$2,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: repeatMode == opt.$1 ? p.textPrimary : p.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (repeatMode == ScheduleRepeatMode.specificDate)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                          decoration: BoxDecoration(
                            color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.50 : 0.40),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: p.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 16, color: themeAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TactilePress(
                                  child: GestureDetector(
                                    onTap: () async {
                                      final parsed = ScheduleEngine.parseDateIso(specificDateIso) ?? now;
                                      final first = DateTime(now.year - 1, 1, 1);
                                      final last = DateTime(now.year + 3, 12, 31);
                                      final picked = await showDatePicker(
                                        context: dialogCtx,
                                        initialDate: parsed.isBefore(first) ? now : parsed,
                                        firstDate: first,
                                        lastDate: last,
                                      );
                                      if (picked != null) {
                                        setDialogState(() {
                                          specificDateIso = ScheduleEngine.formatDateIso(picked);
                                        });
                                      }
                                    },
                                    child: Text(
                                      ScheduleEngine.formatShortDateTr(
                                        ScheduleEngine.parseDateIso(specificDateIso) ?? now,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: p.textPrimary,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              TactilePress(
                                child: TextButton(
                                  onPressed: () => setDialogState(() => specificDateIso = todayIso),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    tr ? 'Bugün' : 'Today',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: specificDateIso == todayIso ? themeAccent : p.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              TactilePress(
                                child: TextButton(
                                  onPressed: () => setDialogState(() => specificDateIso = tomorrowIso),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(
                                    tr ? 'Yarın' : 'Tomorrow',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: specificDateIso == tomorrowIso ? themeAccent : p.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (repeatMode == ScheduleRepeatMode.customDays)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final d in dayItems)
                              TactilePress(
                                child: GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      if (repeatWeekdays.contains(d.$1)) {
                                        if (repeatWeekdays.length > 1) {
                                          repeatWeekdays.remove(d.$1);
                                        }
                                      } else {
                                        repeatWeekdays.add(d.$1);
                                        repeatWeekdays.sort();
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: repeatWeekdays.contains(d.$1)
                                          ? themeAccent.withValues(alpha: 0.25)
                                          : p.scaffoldBg.withValues(alpha: p.isLight ? 0.50 : 0.38),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: repeatWeekdays.contains(d.$1) ? themeAccent : p.cardBorder,
                                      ),
                                    ),
                                    child: Text(
                                      tr ? d.$2 : d.$3,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: repeatWeekdays.contains(d.$1) ? p.textPrimary : p.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),

                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TactilePress(
                            child: TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: Text(
                                tr ? 'İptal' : 'Cancel',
                                style: TextStyle(color: p.textSecondary, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TactilePress(
                            child: FilledButton.icon(
                              onPressed: () {
                                final cleanTitle = titleCtrl.text.trim().isEmpty
                                    ? defaultTitleFor(actionType)
                                    : titleCtrl.text.trim();
                                final rule = CustomScheduleRule(
                                  id: existing?.id ?? 'rule_${DateTime.now().microsecondsSinceEpoch}',
                                  title: cleanTitle,
                                  enabled: existing?.enabled ?? true,
                                  actionType: actionType,
                                  openTime: openTime,
                                  openTargetTemp: ThermostatMath.snapTemperature(openTargetTemp),
                                  closeTime: closeTime,
                                  repeatMode: repeatMode,
                                  specificDateIso: specificDateIso,
                                  repeatWeekdays: List<int>.from(repeatWeekdays),
                                );
                                Navigator.of(dialogCtx).pop(rule);
                              },
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: Text(
                                existing == null
                                    ? (tr ? 'Plan Ekle' : 'Add Plan')
                                    : (tr ? 'Güncelle' : 'Update'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: themeAccent,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    if (result == null || !mounted) return;
    if (existing == null) {
      widget.onAddCustomRule?.call(result);
    } else {
      widget.onUpdateCustomRule?.call(result);
    }
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
    final liveBoiler = widget.boiler ?? const BoilerTelemetry.disconnected();
    final burnSeconds = widget.todayLog?.activeBurnSeconds ?? 0;
    final burnDurationText = ThermalLogAggregator.formatDuration(burnSeconds, widget.lang);
    final gasEstimate = widget.todayLog?.gasM3 ?? 0.0;
    final safeGasRate = widget.gasUnitPriceTl > 0 ? widget.gasUnitPriceTl : 10.25;
    final tlEstimate = gasEstimate * safeGasRate;
    final savedTl = (widget.todayLog?.modulatedSavingsM3 ?? 0.0) * safeGasRate;
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr ? 'AKILLI ZAMANLAMA' : 'SMART SCHEDULE',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: p.textPrimary),
                      ),
                      Text(
                        tr
                            ? 'Otomatik çalışır · Saat geldiğinde hedef dereceyi uygular'
                            : 'Active engine · Automatically applies target on time',
                        style: TextStyle(fontSize: 10.5, color: p.textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TactilePress(
                      child: FilledButton.icon(
                        onPressed: () => _openCustomRuleEditor(),
                        icon: const Icon(Icons.add_alarm_rounded, size: 15),
                        label: Text(
                          tr ? 'Yeni Plan' : 'New Plan',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: themeAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    TactilePress(
                      child: FilledButton.icon(
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
                    ),
                  ],
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
                              TactilePress(
                                child: GestureDetector(
                                  onTap: () => _pickDefaultSlotTime(slot),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        slot.time,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: slot.enabled ? themeAccent : p.textSecondary,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.edit_outlined, size: 11, color: p.textSecondary),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TactilePress(
                          child: IconButton(
                            onPressed: () => widget.onUpdateSlot(
                              slot.id,
                              targetTemp: ThermostatMath.snapTemperature(slot.targetTemp - 0.5),
                            ),
                            icon: Icon(Icons.remove_rounded, size: 16, color: p.textPrimary),
                          ),
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
                        TactilePress(
                          child: IconButton(
                            onPressed: () => widget.onUpdateSlot(
                              slot.id,
                              targetTemp: ThermostatMath.snapTemperature(slot.targetTemp + 0.5),
                            ),
                            icon: Icon(Icons.add_rounded, size: 16, color: p.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Custom Calendar & Periodic Plans Section (independent Open / Close / Both)
            const SizedBox(height: 12),
            Divider(color: p.cardBorder, height: 1),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr
                      ? 'ÖZEL TAKVİM & PERİYODİK PLANLAR (${widget.customRules.length})'
                      : 'CUSTOM CALENDAR & PERIODIC PLANS (${widget.customRules.length})',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: themeAccent,
                  ),
                ),
                Text(
                  tr ? 'Bağımsız Aç / Kapat' : 'Independent Open / Close',
                  style: TextStyle(fontSize: 10, color: p.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.customRules.isEmpty)
              TactilePress.card(
                child: GestureDetector(
                  onTap: () => _openCustomRuleEditor(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.35 : 0.28),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: p.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_rounded, size: 16, color: themeAccent),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            tr
                                ? 'Belirli bir tarih veya haftanın günleri için tek yön "Sadece Aç", "Sadece Kapat" ya da "Aç & Kapat" planı eklemek için dokunun.'
                                : 'Tap to add a calendar date or periodic rule with independent "Open Only", "Close Only", or "Open & Close" actions.',
                            style: TextStyle(fontSize: 11, color: p.textSecondary, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Column(
                children: [
                  for (final rule in widget.customRules) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: p.scaffoldBg.withValues(alpha: p.isLight ? 0.42 : 0.36),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: rule.enabled ? themeAccent.withValues(alpha: 0.40) : p.cardBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: rule.enabled,
                            activeThumbColor: emerald,
                            onChanged: (v) => widget.onUpdateCustomRule?.call(rule.copyWith(enabled: v)),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TactilePress.card(
                              child: GestureDetector(
                                onTap: () => _openCustomRuleEditor(existing: rule),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            rule.title,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: rule.enabled ? p.textPrimary : p.textSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: (rule.actionType == ScheduleActionType.closeOnly
                                                    ? const Color(0xFFF43F5E)
                                                    : themeAccent)
                                                .withValues(alpha: 0.18),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            ScheduleEngine.describeScheduleFrequency(rule, widget.lang),
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: rule.actionType == ScheduleActionType.closeOnly
                                                  ? const Color(0xFFFDA4AF)
                                                  : themeAccent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      ScheduleEngine.describeActionSummary(rule, widget.lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.textSecondary,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          TactilePress(
                            child: IconButton(
                              onPressed: () => _openCustomRuleEditor(existing: rule),
                              icon: Icon(Icons.edit_outlined, size: 16, color: p.textSecondary),
                              tooltip: tr ? 'Düzenle' : 'Edit',
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          TactilePress(
                            child: IconButton(
                              onPressed: () => widget.onDeleteCustomRule?.call(rule.id),
                              icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFF87171)),
                              tooltip: tr ? 'Sil' : 'Delete',
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                burnDurationText,
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
                      text: '${gasEstimate.toStringAsFixed(2)} ',
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
              Text(tr ? '24 kW modülasyon' : '24 kW modulated', style: TextStyle(fontSize: 10.5, color: p.textSecondary)),
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
                      text: '${tlEstimate.toStringAsFixed(2)} ',
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
                tr ? '↘ ${savedTl.toStringAsFixed(2)} TL tasarruf' : '↘ ${savedTl.toStringAsFixed(2)} TL saved',
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
                        liveBoiler.hasSensorReading ? '%${liveBoiler.flamePercent}' : '--',
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
                          (widget.sensors.isConnected && widget.sensors.waterPressureBar != null)
                              ? '${widget.sensors.waterPressureBar!.toStringAsFixed(1)} Bar'
                              : '--',
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
                          (widget.sensors.isConnected && widget.sensors.pumpRpm != null)
                              ? '${widget.sensors.pumpRpm} RPM'
                              : '--',
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
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _scrollController,
              physics: (constraints.maxHeight < 480 || widget.customRules.isNotEmpty)
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
                                  TactilePress(
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        _selectedSubTab = sub;
                                        _canVertScroll = false;
                                      }),
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
      ),
    );
  }
}
