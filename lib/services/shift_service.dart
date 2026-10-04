import 'pos_api_service.dart';
import 'shift_payload.dart';

/// Thrown when the server rejects a shift event (e.g. "already has an open
/// shift", "shift not found"). [message] is safe to show the cashier.
class ShiftException implements Exception {
  ShiftException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// LAUNCH-P5 C5 — the server refused the close because some of the
/// shift's paid sales have not reached it yet (retryable).
class ShiftUnsyncedSalesException implements Exception {
  ShiftUnsyncedSalesException(this.missing);
  final List<String> missing;
  @override
  String toString() => 'unsynced_sales: ${missing.length}';
}

/// LAUNCH-P5 C5 — closing another cashier's drawer was refused
/// (`approval_required` / `approval_invalid`); retryable with a new
/// approval under the same event id.
class ShiftApprovalRefusedException implements Exception {
  ShiftApprovalRefusedException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// LAUNCH-P5 fix order 1 (L8) — the close went under an old fixed id: the
/// portal re-opened the shift since. Retryable under the id rebuilt with
/// the server's current [reopenCount].
class ShiftReopenedException implements Exception {
  ShiftReopenedException(this.reopenCount);
  final int reopenCount;
  @override
  String toString() => 'shift_reopened: $reopenCount';
}

/// Opens / closes a cash-drawer shift through the device sync pipeline
/// (`/device/sync/push`). Online-required: open and close both need the server
/// (close computes expected cash from the device's sales). The events are
/// idempotent on client_event_id, so a retry after a flaky response is safe.
class ShiftService {
  ShiftService(this._api);

  final PosApiService _api;

  /// Open a drawer session. Throws [ShiftException] if the server rejects it
  /// (e.g. the device already has an open shift).
  Future<void> open({
    required String shiftUuid,
    required int openingCashBaisas,
    required int staffId,
  }) async {
    final data = await _api.pushSync([
      buildShiftOpenEvent(
        shiftUuid: shiftUuid,
        openingCashBaisas: openingCashBaisas,
        staffId: staffId,
      ),
    ]);
    _settledResult(data); // throws on a failed ACK
  }

  /// Close the drawer session and return the reconciliation outcome.
  /// LAUNCH-P5 C5 — [event] is the close the screen built (fixed id);
  /// otherwise one is built here.
  Future<ShiftCloseResult> close({
    required String shiftUuid,
    required int closingCashBaisas,
    int? closedByStaffId,
    List<String> orderUuids = const <String>[],
    Map<String, dynamic>? authorization,
    int reopenCount = 0,
    Map<String, dynamic>? event,
  }) async {
    final data = await _api.pushSync([
      event ??
          buildShiftCloseEvent(
            shiftUuid: shiftUuid,
            closingCashBaisas: closingCashBaisas,
            closedByStaffId: closedByStaffId,
            orderUuids: orderUuids,
            authorization: authorization,
            reopenCount: reopenCount,
          ),
    ]);
    return ShiftCloseResult.fromResult(_settledResult(data));
  }

  /// The `unsynced_sales` refusal, wherever the server puts the code and
  /// the missing uuids.
  static List<String>? unsyncedSales(Map<String, dynamic> result) {
    final details = result['details'];
    final nested = result['unsynced_sales'];
    final isUnsynced = [
      result['code'],
      result['refusal_code'],
      result['error'],
      if (details is Map) details['code'],
    ].any((v) => v == 'unsynced_sales') ||
        nested is Map ||
        (result['error']?.toString().contains('unsynced_sales') ?? false);
    if (!isUnsynced) return null;
    final raw = result['missing'] ??
        (details is Map ? details['missing'] : null) ??
        (nested is Map ? nested['missing'] : null);
    return [
      for (final uuid in raw is List ? raw : const []) uuid.toString(),
    ];
  }

  /// The `shift_reopened` refusal's current re-open count (at the top of
  /// the result or under `details`); null when it is another refusal.
  static int? reopenedCount(Map<String, dynamic> result) {
    final details = result['details'];
    final isReopened = [
      result['code'],
      result['refusal_code'],
      result['error'],
      if (details is Map) details['code'],
    ].any((v) => v == 'shift_reopened');
    if (!isReopened) return null;
    final raw =
        result['reopen_count'] ??
        (details is Map ? details['reopen_count'] : null);
    if (raw is num && raw >= 0) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  /// Extract the single event's settled result. A `processed` or `duplicate`
  /// ACK is success (a re-push echoes the original result); a `failed` ACK
  /// raises [ShiftException] carrying the server error.
  Map<String, dynamic> _settledResult(Map<String, dynamic> data) {
    final results = (data['results'] as List? ?? const []);
    if (results.isEmpty || results.first is! Map) {
      throw ShiftException('No response from the server. Please try again.');
    }
    final ack = (results.first as Map).cast<String, dynamic>();
    final result = (ack['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (ack['status'] == 'failed') {
      final missing = unsyncedSales(result);
      if (missing != null) throw ShiftUnsyncedSalesException(missing);
      final code = result['code'];
      if (code == 'approval_required' || code == 'approval_invalid') {
        throw ShiftApprovalRefusedException(code as String);
      }
      final reopened = reopenedCount(result);
      if (reopened != null) throw ShiftReopenedException(reopened);
      throw ShiftException(
        (result['error'] ?? 'The server rejected the shift.').toString(),
      );
    }
    return result;
  }
}
