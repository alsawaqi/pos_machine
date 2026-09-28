import 'dart:async';

import 'package:flutter/foundation.dart';

/// A single budget for a staff table action, shared by its nested phases.
/// Expiry also fences work which was already waiting on SQLite: a timed-out
/// Future alone does not cancel its underlying transaction.
class TableActionDeadline {
  TableActionDeadline(this.action) : _clock = Stopwatch()..start();

  static final Object _zoneKey = Object();
  static TableActionDeadline? get current =>
      Zone.current[_zoneKey] as TableActionDeadline?;
  static const bound = Duration(seconds: 8);
  final String action;
  final Stopwatch _clock;
  String phase = 'start';

  void check() {
    if (_clock.elapsed >= bound) {
      throw TimeoutException('Table action deadline: $phase', bound);
    }
  }

  Future<T> run<T>(Future<T> Function() operation) =>
      runZoned(operation, zoneValues: {_zoneKey: this});

  Future<T> step<T>(String name, Future<T> Function() operation) async {
    phase = name;
    check();
    final started = _clock.elapsedMilliseconds;
    var outcome = 'complete';
    try {
      final value = await run(operation).timeout(bound - _clock.elapsed);
      check();
      return value;
    } on TimeoutException {
      outcome = 'timeout';
      rethrow;
    } catch (_) {
      outcome = 'failed';
      rethrow;
    } finally {
      debugPrint(
        'table_action action=$action phase=$name outcome=$outcome '
        'phase_ms=${_clock.elapsedMilliseconds - started} '
        'elapsed_ms=${_clock.elapsedMilliseconds}',
      );
    }
  }
}
