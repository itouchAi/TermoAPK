import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ai_call_service.dart';
import 'termo_bot.dart';

class TopCallNotificationBanner extends StatelessWidget {
  final AiCallLogEntry entry;
  final LangCode lang;
  final VoidCallback onTapBanner;
  final VoidCallback onDismiss;

  const TopCallNotificationBanner({
    super.key,
    required this.entry,
    required this.lang,
    required this.onTapBanner,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final tr = lang == LangCode.tr;
    final meta = MascotMeta.of(entry.character);
    final isDeclined = entry.status == AiCallStatus.declined;
    final accent = isDeclined || entry.urgent
        ? const Color(0xFFEF4444)
        : const Color(0xFFF59E0B);
    final badgeTitle = isDeclined
        ? (tr ? 'Meşgule Atıldı' : 'Call Declined')
        : (tr ? 'Cevapsız Arama' : 'Missed Call');
    final summary = tr ? entry.summaryTr : entry.summaryEn;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Material(
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
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
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
                        isDeclined
                            ? Icons.phone_disabled_rounded
                            : Icons.phone_missed_rounded,
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
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  badgeTitle,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
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
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr
                                ? 'Mesajı okumak ve aksiyon almak için dokunun →'
                                : 'Tap to read details & take action →',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: accent.withValues(alpha: 0.92),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
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
          ),
        ),
      ),
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
  final statusColor = entry.status == AiCallStatus.answered
      ? const Color(0xFF10B981)
      : (entry.status == AiCallStatus.declined
          ? const Color(0xFFEF4444)
          : const Color(0xFFF59E0B));

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
                              '${meta.name} · ${tr ? 'Çağrı Özeti' : 'Call Summary'}',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Container(
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
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
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
                        Text(
                          tr ? 'Aksiyon / Sistem Mesajı' : 'System Event Message',
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
