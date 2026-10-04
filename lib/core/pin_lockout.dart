import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P5 / PHASE-1A D-9 — a persisted PIN-pad lock.
///
/// Two uses on the till:
///  * the approval sheet's own local counter ([recordFailure]): 5 wrong PINs
///    lock the sheet for 60 s; every further wrong PIN after that doubles the
///    window, capped at 15 minutes. A correct PIN clears it. Failures more
///    than 15 minutes apart do not add up.
///  * a server lock ([lockFor]) from a 423 `pin_locked` / 429
///    `too_many_attempts` reply's `retry_after_seconds`.
///
/// The lock survives an app restart (SharedPreferences). Honest limit:
/// clearing the app's data clears it — which also deletes the device token
/// and un-pairs the till, so it is not a quiet bypass.
class PinLockout {
  PinLockout(this._prefs, this.key, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SharedPreferences _prefs;
  final String key;
  final DateTime Function() _clock;

  static const threshold = 5;
  static const baseLock = Duration(seconds: 60);
  static const maxLock = Duration(minutes: 15);
  static const failureMemory = Duration(minutes: 15);

  Map<String, dynamic> _read() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(Map<String, dynamic> state) =>
      _prefs.setString(key, jsonEncode(state));

  /// When the pad unlocks, or null when it is not locked now. A stored time
  /// in the past is not a lock.
  DateTime? get lockedUntil {
    final ms = _read()['locked_until_ms'];
    if (ms is! num) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
    return until.isAfter(_clock()) ? until : null;
  }

  Duration? get remaining {
    final until = lockedUntil;
    return until?.difference(_clock());
  }

  int get failures {
    final state = _read();
    final last = state['last_failure_ms'];
    if (last is num &&
        _clock().difference(DateTime.fromMillisecondsSinceEpoch(last.toInt())) >
            failureMemory) {
      return 0;
    }
    final count = state['failures'];
    return count is num ? count.toInt() : 0;
  }

  /// Count one wrong PIN. Returns the new lock end, if this one locks.
  Future<DateTime?> recordFailure() async {
    final now = _clock();
    final count = failures + 1;
    final state = <String, dynamic>{
      'failures': count,
      'last_failure_ms': now.millisecondsSinceEpoch,
    };
    DateTime? until;
    if (count >= threshold) {
      final doublings = math.min(count - threshold, 10);
      var window = baseLock * math.pow(2, doublings).toInt();
      if (window > maxLock) window = maxLock;
      until = now.add(window);
      state['locked_until_ms'] = until.millisecondsSinceEpoch;
    }
    await _write(state);
    return until;
  }

  /// A server-imposed lock (D-6 `retry_after_seconds`).
  Future<DateTime> lockFor(Duration duration) async {
    final until = _clock().add(duration);
    final state = _read()..['locked_until_ms'] = until.millisecondsSinceEpoch;
    await _write(state);
    return until;
  }

  /// A correct PIN (or a manager unlock) clears the counter and the lock.
  Future<void> clear() => _prefs.remove(key);
}
