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
  Future<ShiftCloseResult> close({
    required String shiftUuid,
    required int closingCashBaisas,
  }) async {
    final data = await _api.pushSync([
      buildShiftCloseEvent(
        shiftUuid: shiftUuid,
        closingCashBaisas: closingCashBaisas,
      ),
    ]);
    return ShiftCloseResult.fromResult(_settledResult(data));
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
      throw ShiftException(
        (result['error'] ?? 'The server rejected the shift.').toString(),
      );
    }
    return result;
  }
}
