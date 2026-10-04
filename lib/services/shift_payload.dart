import 'package:uuid/uuid.dart';

import '../core/auth_wire.dart';
import 'order_sync_payload.dart' show uuidV4;

/// Builds the pos_api `/device/sync/push` events for a cash-drawer shift.
///
/// The wire contract (pos_api OpenShiftHandler / CloseShiftHandler, money =
/// integer BAISAS):
///   shift.open  { uuid, staff_id, opening_cash_baisas, opened_at }
///               → result { status: 'open' }
///   shift.close { shift_uuid, closing_cash_baisas, closed_at }
///               → result { status: 'closed', expected_cash_baisas, variance_baisas }
///
/// expected_cash = opening + Σ(cash taken on THIS device during the window);
/// variance = closing − expected (computed server-side). Events carry a stable
/// client_event_id so a re-push (offline replay) settles exactly once. Pure —
/// no I/O — so unit-testable.

/// The reconciliation outcome returned by a settled shift.close.
class ShiftCloseResult {
  const ShiftCloseResult({
    required this.expectedCashBaisas,
    required this.varianceBaisas,
    this.summaryJson,
  });

  /// opening + cash sales rung on this device during the shift.
  final int expectedCashBaisas;

  /// counted closing cash − expected (negative = drawer short).
  final int varianceBaisas;

  /// Phase C6 — the server's shift sales summary (Z-report numbers), parsed
  /// by ShiftSalesSummary.fromServerResult. Null from an older API → the
  /// device falls back to its local calculator.
  final Map<String, dynamic>? summaryJson;

  factory ShiftCloseResult.fromResult(Map<String, dynamic> result) {
    return ShiftCloseResult(
      expectedCashBaisas: (result['expected_cash_baisas'] as num?)?.toInt() ?? 0,
      varianceBaisas: (result['variance_baisas'] as num?)?.toInt() ?? 0,
      summaryJson: (result['summary'] as Map?)?.cast<String, dynamic>(),
    );
  }
}

/// Build the `shift.open` event. [openedAt] defaults to now.
Map<String, dynamic> buildShiftOpenEvent({
  required String shiftUuid,
  required int openingCashBaisas,
  required int staffId,
  DateTime? openedAt,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  final opened = (openedAt ?? now ?? DateTime.now()).toUtc().toIso8601String();
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'shift.open',
    'client_timestamp': ts,
    'payload': <String, dynamic>{
      'uuid': shiftUuid,
      'staff_id': staffId,
      'opening_cash_baisas': openingCashBaisas,
      'opened_at': opened,
      // HH-2 — opt into the STAFF-shared shift model: one open shift per
      // staff per branch, adopted by every terminal they log into (probe
      // GET /device/shift/current?staff_id), close attributed by staff.
      // Builds that predate this flag keep pure per-device semantics.
      'shared_shift': true,
      ...authStamp(staffId: staffId),
    },
  };
}

/// LAUNCH-P5 C5 — the FIXED client_event_id of a shift's close: UUID v5
/// (RFC 4122 URL namespace `6ba7b811-9dad-11d1-80b4-00c04fd430c8`) of
/// `shift-close:{shift_uuid}:{reopen_count}`. A retry after a lost reply is
/// the same event (the server returns the original Z instead of "already
/// closed"); a refused close re-sent under it replaces the stored payload;
/// after a portal re-open the count moves on, so the shift can close again.
String shiftCloseEventId(String shiftUuid, {int reopenCount = 0}) =>
    const Uuid().v5(
      Namespace.url.value,
      'shift-close:$shiftUuid:$reopenCount',
    );

/// Build the `shift.close` event for the open shift [shiftUuid].
///
/// LAUNCH-P5 C5 — it names who closed it ([closedByStaffId]), lists the
/// paid orders of this shift on this device ([orderUuids]; the server
/// refuses with `unsynced_sales` while one has not arrived), and carries
/// the `shift.close_other` [authorization] when closing another cashier's
/// drawer.
Map<String, dynamic> buildShiftCloseEvent({
  required String shiftUuid,
  required int closingCashBaisas,
  int? closedByStaffId,
  List<String> orderUuids = const <String>[],
  Map<String, dynamic>? authorization,
  int reopenCount = 0,
  DateTime? now,
  // Kept for older callers; the event id is fixed per shift.
  String Function()? newUuid,
}) {
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  return <String, dynamic>{
    'client_event_id': shiftCloseEventId(shiftUuid, reopenCount: reopenCount),
    'event_type': 'shift.close',
    'client_timestamp': ts,
    'payload': <String, dynamic>{
      'shift_uuid': shiftUuid,
      'closing_cash_baisas': closingCashBaisas,
      'closed_at': ts,
      'closed_by_staff_id': ?closedByStaffId,
      'order_uuids': orderUuids,
      'authorization': ?authorization,
      ...authStamp(staffId: closedByStaffId),
    },
  };
}
