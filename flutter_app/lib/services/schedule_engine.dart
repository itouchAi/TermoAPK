import '../models/thermostat_state.dart';

class ScheduleEvaluationResult {
  final double? nextTargetTemp;
  final String? triggeredTitleTr;
  final String? triggeredTitleEn;
  final bool isCloseAction;
  final List<String> completedOnceRuleIds;

  const ScheduleEvaluationResult({
    this.nextTargetTemp,
    this.triggeredTitleTr,
    this.triggeredTitleEn,
    this.isCloseAction = false,
    this.completedOnceRuleIds = const [],
  });

  bool get hasTriggered => nextTargetTemp != null;
}

class ScheduleEngine {
  ScheduleEngine._();

  static String formatHhMm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String formatDateIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String formatShortDateTr(DateTime dt) {
    const months = [
      'Oca',
      'Şub',
      'Mar',
      'Nis',
      'May',
      'Haz',
      'Tem',
      'Ağu',
      'Eyl',
      'Eki',
      'Kas',
      'Ara',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static DateTime? parseDateIso(String iso) {
    final parts = iso.trim().split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  static String minuteKey(DateTime dt) => '${formatDateIso(dt)} ${formatHhMm(dt)}';

  static int? parseHhMmMinutes(String hhmm) {
    final parts = hhmm.trim().split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  static bool matchesCalendarDay(CustomScheduleRule rule, DateTime day) {
    switch (rule.repeatMode) {
      case ScheduleRepeatMode.specificDate:
        return rule.specificDateIso.trim() == formatDateIso(day);
      case ScheduleRepeatMode.daily:
        return true;
      case ScheduleRepeatMode.weekdays:
        return day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
      case ScheduleRepeatMode.weekends:
        return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      case ScheduleRepeatMode.customDays:
        return rule.repeatWeekdays.contains(day.weekday);
    }
  }

  static String describeScheduleFrequency(CustomScheduleRule rule, LangCode lang) {
    final tr = lang == LangCode.tr;
    switch (rule.repeatMode) {
      case ScheduleRepeatMode.specificDate:
        final parsed = parseDateIso(rule.specificDateIso);
        if (parsed != null) {
          return tr ? formatShortDateTr(parsed) : rule.specificDateIso;
        }
        return rule.specificDateIso;
      case ScheduleRepeatMode.daily:
        return tr ? 'Her Gün' : 'Every Day';
      case ScheduleRepeatMode.weekdays:
        return tr ? 'Hafta İçi (Pzt–Cum)' : 'Weekdays (Mon–Fri)';
      case ScheduleRepeatMode.weekends:
        return tr ? 'Hafta Sonu (Cmt–Paz)' : 'Weekends (Sat–Sun)';
      case ScheduleRepeatMode.customDays:
        const labelsTr = <int, String>{
          1: 'Pzt',
          2: 'Sal',
          3: 'Çar',
          4: 'Per',
          5: 'Cum',
          6: 'Cmt',
          7: 'Paz',
        };
        const labelsEn = <int, String>{
          1: 'Mon',
          2: 'Tue',
          3: 'Wed',
          4: 'Thu',
          5: 'Fri',
          6: 'Sat',
          7: 'Sun',
        };
        final map = tr ? labelsTr : labelsEn;
        final parts = [
          for (final d in rule.repeatWeekdays)
            if (map.containsKey(d)) map[d]!,
        ];
        if (parts.isEmpty) return tr ? 'Gün seçilmedi' : 'No days selected';
        return parts.join(', ');
    }
  }

  static String describeActionSummary(CustomScheduleRule rule, LangCode lang) {
    final tr = lang == LangCode.tr;
    final openTemp = '${rule.openTargetTemp.toStringAsFixed(1)}°C';
    switch (rule.actionType) {
      case ScheduleActionType.openOnly:
        return tr
            ? 'Sadece Aç: ${rule.openTime} · $openTemp'
            : 'Open Only: ${rule.openTime} · $openTemp';
      case ScheduleActionType.closeOnly:
        return tr
            ? 'Sadece Kapat: ${rule.closeTime} · Bekleme'
            : 'Close Only: ${rule.closeTime} · Off';
      case ScheduleActionType.openAndClose:
        return tr
            ? 'Aç ${rule.openTime} ($openTemp) → Kapat ${rule.closeTime}'
            : 'Open ${rule.openTime} ($openTemp) → Close ${rule.closeTime}';
    }
  }

  /// Evaluates enabled default [slots] and [customRules] at [now]'s `HH:mm`.
  /// Custom rules take precedence over default preset slots if both fall on the same minute.
  static ScheduleEvaluationResult evaluateAtMinute({
    required DateTime now,
    required List<ScheduleSlot> slots,
    required List<CustomScheduleRule> customRules,
  }) {
    final hhmm = formatHhMm(now);
    double? nextTemp;
    String? titleTr;
    String? titleEn;
    bool isCloseAction = false;
    final completedOnceIds = <String>[];

    // 1) Default repeating daily mode slots (Gece / Sabah / Dışarıda / Akşam)
    for (final slot in slots) {
      if (!slot.enabled) continue;
      if (slot.time.trim() == hhmm) {
        nextTemp = ThermostatMath.snapTemperature(slot.targetTemp);
        titleTr = '${slot.labelTr} (${slot.time})';
        titleEn = '${slot.labelEn} (${slot.time})';
        isCloseAction = nextTemp <= ThermostatMath.minTemp + 0.05;
      }
    }

    // 2) Custom calendar / periodic plans with independent Open & Close
    for (final rule in customRules) {
      if (!rule.enabled) continue;
      final openMin = parseHhMmMinutes(rule.openTime);
      final closeMin = parseHhMmMinutes(rule.closeTime);
      final isOvernightClose = rule.hasOpenAction &&
          rule.hasCloseAction &&
          openMin != null &&
          closeMin != null &&
          closeMin < openMin;

      bool matchedClose = false;
      bool matchedOpen = false;

      if (rule.hasCloseAction && rule.closeTime.trim() == hhmm) {
        final effectiveCloseDay =
            isOvernightClose ? now.subtract(const Duration(days: 1)) : now;
        if (matchesCalendarDay(rule, effectiveCloseDay)) {
          matchedClose = true;
        }
      }

      if (rule.hasOpenAction && rule.openTime.trim() == hhmm) {
        if (matchesCalendarDay(rule, now)) {
          matchedOpen = true;
        }
      }

      // If openTime and closeTime are identical on openAndClose, Open wins unless user made closeOnly.
      if (matchedClose && !matchedOpen) {
        nextTemp = ThermostatMath.minTemp;
        titleTr = '${rule.title} · Kapatma (${rule.closeTime})';
        titleEn = '${rule.title} · Close (${rule.closeTime})';
        isCloseAction = true;
        if (rule.repeatMode == ScheduleRepeatMode.specificDate) {
          completedOnceIds.add(rule.id);
        }
      } else if (matchedOpen) {
        nextTemp = ThermostatMath.snapTemperature(rule.openTargetTemp);
        titleTr = '${rule.title} · Açma (${rule.openTime})';
        titleEn = '${rule.title} · Open (${rule.openTime})';
        isCloseAction = false;
        if (rule.repeatMode == ScheduleRepeatMode.specificDate &&
            rule.actionType == ScheduleActionType.openOnly) {
          completedOnceIds.add(rule.id);
        }
      }
    }

    return ScheduleEvaluationResult(
      nextTargetTemp: nextTemp,
      triggeredTitleTr: titleTr,
      triggeredTitleEn: titleEn,
      isCloseAction: isCloseAction,
      completedOnceRuleIds: completedOnceIds,
    );
  }
}
