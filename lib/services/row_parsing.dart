import 'package:flutter/foundation.dart';

import '../core/sentry.dart';

/// LAUNCH-P6 Part C item 2 — one unknown or bad row in a server list is
/// skipped and logged; it never breaks the whole list. Applies to every QR
/// and tablet list the till reads (pending, quick inbox, active, accepted
/// rounds, board and tablet orders).
///
/// [list] names the list in the log line. Only the row's position and the
/// error's type go to the log, never the row itself (it can hold a phone).
typedef SkippedRowLogger = void Function(String list, int index, Object error);

/// Tests may replace the logger to see what was skipped.
SkippedRowLogger skippedRowLogger = _logSkippedRow;

void _logSkippedRow(String list, int index, Object error) {
  debugPrint('[$list] skipped row $index: ${error.runtimeType}');
  sentryBreadcrumb(
    'server-list',
    'Skipped an unreadable row',
    data: {'list': list, 'index': index, 'error': error.runtimeType.toString()},
  );
}

/// Parses every row of [rows] with [parse]; a row that is not a map, or that
/// [parse] refuses (throws), is skipped and logged. A [rows] that is not a
/// list at all is an empty list (logged once).
List<T> parseRowsSkippingBad<T>(
  Object? rows,
  T Function(Map<String, dynamic> row) parse, {
  required String list,
  void Function()? onSkip,
}) {
  if (rows == null) return <T>[];
  if (rows is! List) {
    skippedRowLogger(list, -1, const FormatException('Not a list'));
    return <T>[];
  }
  final out = <T>[];
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    try {
      if (row is! Map) throw const FormatException('Row is not an object');
      out.add(parse(Map<String, dynamic>.from(row)));
    } catch (error) {
      skippedRowLogger(list, index, error);
      onSkip?.call();
    }
  }
  return out;
}
