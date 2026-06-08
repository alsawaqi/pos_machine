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
  });

  /// opening + cash sales rung on this device during the shift.
  final int expectedCashBaisas;

  /// counted closing cash − expected (negative = drawer short).
  final int varianceBaisas;

  factory ShiftCloseResult.fromResult(Map<String, dynamic> result) {
    return ShiftCloseResult(
      expectedCashBaisas: (result['expected_cash_baisas'] as num?)?.toInt() ?? 0,
      varianceBaisas: (result['variance_baisas'] as num?)?.toInt() ?? 0,
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
    },
  };
}

/// Build the `shift.close` event for the open shift [shiftUuid].
Map<String, dynamic> buildShiftCloseEvent({
  required String shiftUuid,
  required int closingCashBaisas,
  DateTime? now,
  String Function()? newUuid,
}) {
  final gen = newUuid ?? uuidV4;
  final ts = (now ?? DateTime.now()).toUtc().toIso8601String();
  return <String, dynamic>{
    'client_event_id': gen(),
    'event_type': 'shift.close',
    'client_timestamp': ts,
    'payload': <String, dynamic>{
      'shift_uuid': shiftUuid,
      'closing_cash_baisas': closingCashBaisas,
      'closed_at': ts,
    },
  };
}
