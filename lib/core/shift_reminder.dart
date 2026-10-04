/// LAUNCH-P5 C8 — the shift-end reminder.
///
/// `settings.shift_end_reminder_at` is "HH:MM" in Muscat time (UTC+4, no
/// daylight saving; `pos.business_timezone`). While the logged-in person's
/// own shift is open and the reminder time has passed since the shift
/// opened, the till shows a banner and plays a sound, again every 15
/// minutes, until the shift is closed.
class ShiftEndReminder {
  ShiftEndReminder._();

  static const muscatOffset = Duration(hours: 4);
  static const repeat = Duration(minutes: 15);

  /// The parsed time of day, or null for blank / malformed values.
  static ({int hour, int minute})? parse(String? hhmm) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(hhmm?.trim() ?? '');
    if (m == null) return null;
    final hour = int.parse(m.group(1)!), minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  /// The latest reminder instant at or before [now] (UTC), or null when
  /// there is no reminder or it fell before the shift opened.
  static DateTime? dueSince({
    required String? hhmm,
    required DateTime openedAt,
    required DateTime now,
  }) {
    final time = parse(hhmm);
    if (time == null) return null;
    final muscatNow = now.toUtc().add(muscatOffset);
    var muscatAt = DateTime.utc(
      muscatNow.year,
      muscatNow.month,
      muscatNow.day,
      time.hour,
      time.minute,
    );
    if (muscatAt.isAfter(muscatNow)) {
      muscatAt = muscatAt.subtract(const Duration(days: 1));
    }
    final at = muscatAt.subtract(muscatOffset);
    return at.isBefore(openedAt.toUtc()) ? null : at;
  }

  /// Whether to alert now: the reminder is due and the last alert (if any)
  /// is at least 15 minutes old.
  static bool shouldAlert({
    required DateTime? dueSince,
    required DateTime? lastAlert,
    required DateTime now,
  }) {
    if (dueSince == null) return false;
    if (lastAlert == null || lastAlert.isBefore(dueSince)) return true;
    return now.difference(lastAlert) >= repeat;
  }
}
