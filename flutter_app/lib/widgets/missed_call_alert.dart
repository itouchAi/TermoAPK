import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ai_call_service.dart';
import 'termo_bot.dart';

class _AlertVisualSpec {
  final Color accent;
  final IconData icon;
  final String badgeTitle;
  final bool hasSchedule;

  const _AlertVisualSpec({
    required this.accent,
    required this.icon,
    required this.badgeTitle,
    required this.hasSchedule,
  });

  factory _AlertVisualSpec.fromEntry(AiCallLogEntry entry, LangCode lang) {
    final tr = lang == LangCode.tr;
    final hasSchedule = (tr ? entry.scheduleInfoTr : entry.scheduleInfoEn)
        .trim()
        .isNotEmpty;

    if (!entry.isSystemAlert) {
      final isDeclined = entry.status == AiCallStatus.declined;
      final isAnswered = entry.status == AiCallStatus.answered;
      final accent = isAnswered
          ? const Color(0xFF10B981)
          : (isDeclined || entry.urgent
              ? const Color(0xFFEF4444)
              : const Color(0xFFF59E0B));
      final icon = isAnswered
          ? Icons.call_received_rounded
          : (isDeclined
              ? Icons.phone_disabled_rounded
              : Icons.phone_missed_rounded);
      return _AlertVisualSpec(
        accent: accent,
        icon: icon,
        badgeTitle: entry.statusLabel(lang),
        hasSchedule: hasSchedule,
      );
    }

    final Color accent;
    if (entry.urgent || entry.reason == AiCallReason.safetyAlert) {
      accent = const Color(0xFFEF4444);
    } else if (entry.reason == AiCallReason.hotRoom ||
        entry.reason == AiCallReason.coldRoom) {
      accent = const Color(0xFFF59E0B);
    } else if (hasSchedule) {
      accent = const Color(0xFF38BDF8);
    } else if (entry.reason == AiCallReason.ignition) {
      accent = const Color(0xFFFB923C);
    } else {
      accent = const Color(0xFF10B981);
    }

    final IconData icon;
    if (hasSchedule) {
      icon = Icons.event_available_rounded;
    } else if (entry.urgent || entry.reason == AiCallReason.safetyAlert) {
      icon = Icons.warning_amber_rounded;
    } else if (entry.reason == AiCallReason.ignition) {
      icon = Icons.local_fire_department_rounded;
    } else if (entry.reason == AiCallReason.boilerLowered) {
      icon = Icons.trending_down_rounded;
    } else if (entry.reason == AiCallReason.boilerOff) {
      icon = Icons.power_settings_new_rounded;
    } else if (entry.reason == AiCallReason.coldRoom) {
      icon = Icons.ac_unit_rounded;
    } else if (entry.reason == AiCallReason.hotRoom) {
      icon = Icons.wb_sunny_rounded;
    } else {
      icon = Icons.notifications_active_rounded;
    }

    return _AlertVisualSpec(
      accent: accent,
      icon: icon,
      badgeTitle: entry.statusLabel(lang),
      hasSchedule: hasSchedule,
    );
  }
}

class TopCallNotificationBanner extends StatelessWidget {
  final AiCallLogEntry entry;
  final LangCode lang;
  final VoidCallback onTapBanner;
  final VoidCallback onDismiss;
  final int stackExtraCount;
  final bool compactInList;

  const TopCallNotificationBanner({
    super.key,
    required this.entry,
    required this.lang,
    required this.onTapBanner,
    required this.onDismiss,
    this.stackExtraCount = 0,
    this.compactInList = false,
  });

  @override
  Widget build(BuildContext context) {
    final tr = lang == LangCode.tr;
    final meta = MascotMeta.of(entry.character);
    final spec = _AlertVisualSpec.fromEntry(entry, lang);
    final accent = spec.accent;
    final summary = tr ? entry.summaryTr : entry.summaryEn;
    final totalCount = stackExtraCount + 1;

    final card = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapBanner,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1422).withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.65), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.18),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: Icon(
                  spec.icon,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              spec.badgeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${meta.name} · ${entry.timestamp}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white70,
                          ),
                        ),
                        if (stackExtraCount > 0) ...[
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Text(
                              '+$stackExtraCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: stackExtraCount > 0 ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.32,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stackExtraCount > 0
                          ? (tr
                              ? '$totalCount okunmamış mesajı açmak için dokunun ▾'
                              : 'Tap to open $totalCount unread messages ▾')
                          : (tr
                              ? 'Mesajı okumak ve aksiyon almak için dokunun →'
                              : 'Tap to read details & take action →'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: accent.withValues(alpha: 0.92),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: onDismiss,
                tooltip: tr ? 'Bildirimi Kapat' : 'Dismiss Alert',
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white60,
                  size: 19,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );

    if (compactInList) return card;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: card,
        ),
      ),
    );
  }
}

class TopAlertStack extends StatelessWidget {
  final List<AiCallLogEntry> alerts;
  final bool expanded;
  final LangCode lang;
  final VoidCallback onToggleExpand;
  final ValueChanged<AiCallLogEntry> onTapAlert;
  final ValueChanged<String> onDismissAlert;
  final VoidCallback onDismissAll;

  const TopAlertStack({
    super.key,
    required this.alerts,
    required this.expanded,
    required this.lang,
    required this.onToggleExpand,
    required this.onTapAlert,
    required this.onDismissAlert,
    required this.onDismissAll,
  });

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    final tr = lang == LangCode.tr;

    if (alerts.length == 1) {
      final only = alerts.first;
      return TopCallNotificationBanner(
        entry: only,
        lang: lang,
        onTapBanner: () => onTapAlert(only),
        onDismiss: () => onDismissAlert(only.id),
      );
    }

    if (!expanded) {
      final depth = alerts.length >= 3 ? 2 : 1;
      final backSpec2 = _AlertVisualSpec.fromEntry(alerts[1], lang);
      final backSpec3 =
          alerts.length >= 3 ? _AlertVisualSpec.fromEntry(alerts[2], lang) : null;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: GestureDetector(
              onTap: onToggleExpand,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (depth >= 2 && backSpec3 != null)
                    Positioned(
                      top: 16,
                      bottom: 0,
                      left: 22,
                      right: 22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0F1B).withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: backSpec3.accent.withValues(alpha: 0.34),
                            width: 1.1,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    bottom: depth >= 2 ? 8 : 0,
                    left: 11,
                    right: 11,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0C1220).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: backSpec2.accent.withValues(alpha: 0.48),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.40),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(bottom: depth * 8.0),
                    child: TopCallNotificationBanner(
                      entry: alerts.first,
                      lang: lang,
                      stackExtraCount: alerts.length - 1,
                      compactInList: true,
                      onTapBanner: onToggleExpand,
                      onDismiss: () => onDismissAlert(alerts.first.id),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Expanded Telegram-style vertical capsule list
    final media = MediaQuery.of(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleExpand,
            child: Container(
              color: Colors.black.withValues(alpha: 0.48),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 460,
                  maxHeight: media.size.height * 0.70,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B111E).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.mark_chat_unread_rounded,
                            size: 16,
                            color: Color(0xFF38BDF8),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              tr
                                  ? 'Okunmamış Mesajlar (${alerts.length})'
                                  : 'Unread Messages (${alerts.length})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: onDismissAll,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFFCA5A5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              tr ? 'Tümünü Kapat' : 'Clear All',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: onToggleExpand,
                            borderRadius: BorderRadius.circular(9),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    tr ? 'Daralt' : 'Collapse',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 16,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 6),
                        itemCount: alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = alerts[index];
                          return TopCallNotificationBanner(
                            key: ValueKey('alert_capsule_${item.id}'),
                            entry: item,
                            lang: lang,
                            compactInList: true,
                            onTapBanner: () => onTapAlert(item),
                            onDismiss: () => onDismissAlert(item.id),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> showMissedCallActionDialog({
  required BuildContext context,
  required AiCallLogEntry entry,
  required LangCode lang,
  required ValueChanged<AiCallQuickAction> onApplyAction,
  VoidCallback? onDismissWithoutAction,
}) {
  final tr = lang == LangCode.tr;
  final meta = MascotMeta.of(entry.character);
  final actions = AiCallService.suggestedActionsForEntry(entry);
  final spec = _AlertVisualSpec.fromEntry(entry, lang);
  final statusColor = spec.accent;
  final scheduleInfo = tr ? entry.scheduleInfoTr : entry.scheduleInfoEn;

  final dialogSubtitle = entry.isSystemAlert
      ? (spec.hasSchedule
          ? (tr ? 'Takvim Bildirimi' : 'Schedule Alert')
          : (tr ? 'Asistan Mesajı' : 'Assistant Alert'))
      : (tr ? 'Çağrı Özeti' : 'Call Summary');

  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF0C1220),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.45),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.65),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      MascotAvatar(
                        character: entry.character,
                        size: 46,
                        happy: false,
                        showBehaviorOverlay: false,
                        frameless: false,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${meta.name} · $dialogSubtitle',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: statusColor.withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Text(
                                      entry.statusLabel(lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  entry.timestamp,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white60,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (scheduleInfo.isNotEmpty) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.40),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.event_available_rounded,
                                  size: 15,
                                  color: Color(0xFF38BDF8),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    scheduleInfo,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFBAE6FD),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Text(
                          tr ? 'Aksiyon / Sistem Mesajı' : 'Action / System Message',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          tr ? entry.summaryTr : entry.summaryEn,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _DialogMetricChip(
                              label: tr ? 'Oda' : 'Room',
                              value: '${AiCallService.formatSpokenNumber(entry.roomTemp)}°C',
                            ),
                            const SizedBox(width: 6),
                            _DialogMetricChip(
                              label: tr ? 'Hedef' : 'Target',
                              value: '${AiCallService.formatSpokenNumber(entry.targetTemp)}°C',
                            ),
                            const SizedBox(width: 6),
                            _DialogMetricChip(
                              label: tr ? 'Kombi' : 'Boiler',
                              value: entry.boilerHeating
                                  ? (tr ? 'Aktif' : 'Active')
                                  : (tr ? 'Kapalı' : 'Off'),
                            ),
                          ],
                        ),
                        if ((tr ? entry.actionTakenTr : entry.actionTakenEn).isNotEmpty) ...[
                          const SizedBox(height: 9),
                          Text(
                            '${tr ? 'Son İşlem' : 'Recorded Action'}: ${tr ? entry.actionTakenTr : entry.actionTakenEn}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF93C5FD),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    tr ? 'Alınabilecek Hızlı Aksiyonlar:' : 'Suggested Quick Actions:',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final act in actions) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onApplyAction(act);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: act.isDanger
                              ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                              : const Color(0xFF10B981).withValues(alpha: 0.20),
                          foregroundColor: act.isDanger
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF6EE7B7),
                          side: BorderSide(
                            color: act.isDanger
                                ? const Color(0xFFEF4444).withValues(alpha: 0.55)
                                : const Color(0xFF10B981).withValues(alpha: 0.55),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: Icon(
                          act.isDanger
                              ? Icons.power_settings_new_rounded
                              : Icons.bolt_rounded,
                          size: 18,
                        ),
                        label: Text(
                          tr ? act.labelTr : act.labelEn,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      onDismissWithoutAction?.call();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      tr ? 'Hiçbir Şey Yapmadan Kapat' : 'Close Without Action',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DialogMetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _DialogMetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 9.5, color: Colors.white54),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
