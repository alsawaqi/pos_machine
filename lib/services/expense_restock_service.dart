import 'expense_restock_payload.dart';
import 'pos_api_service.dart';

/// Thrown when the server rejects a device expense / restock event (e.g. an
/// unknown ingredient, a bad category). [message] is safe to show the cashier.
class DeviceActionException implements Exception {
  DeviceActionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Logs an expense / raises a restock request through the device sync pipeline
/// (`/device/sync/push`). Online-required (mirrors [ShiftService]): the event is
/// pushed immediately. It is idempotent on client_event_id, so a retry after a
/// flaky response is safe.
class ExpenseRestockService {
  ExpenseRestockService(this._api, {this.queue});

  final PosApiService _api;

  /// LAUNCH-P5 fix order 1 (F7) — keeps a pay-out whose reply was lost or
  /// unclear in the durable outbox under its own event id (so the retry is
  /// the same event and the shift close waits for it). Null = no outbox.
  final Future<void> Function(String key, Map<String, dynamic> event)? queue;

  /// Record a petty-cash expense. Throws [DeviceActionException] if the server
  /// rejects it (e.g. an invalid category).
  ///
  /// Returns true when the server recorded it, false when a pay-out was
  /// kept in the outbox to send later (LAUNCH-P5 F7: the cash is already
  /// out of the drawer, so an unclear reply never loses it).
  Future<bool> logExpense({
    required String category,
    required int amountBaisas,
    int? staffId,
    String? note,
    bool paidFromDrawer = false,
    Map<String, dynamic>? authorization,
    String? shiftUuid,
  }) async {
    final event = buildExpenseLogEvent(
      category: category,
      amountBaisas: amountBaisas,
      staffId: staffId,
      note: note,
      paidFromDrawer: paidFromDrawer,
      authorization: authorization,
      shiftUuid: shiftUuid,
    );
    final keep = paidFromDrawer ? queue : null;
    final Map<String, dynamic> data;
    try {
      data = await _api.pushSync([event]);
    } on ApiException catch (e) {
      // A structured refusal is final (nothing was recorded); a lost or
      // garbled reply may or may not have been: keep the same event.
      if (keep == null || (!e.isNetwork && e.hasStructuredErrorCode)) {
        rethrow;
      }
      await keep('payout:${event['client_event_id']}', event);
      return false;
    }
    final results = data['results'];
    if (keep != null && (results is! List || results.isEmpty)) {
      await keep('payout:${event['client_event_id']}', event);
      return false;
    }
    _settledResult(data); // throws on a failed ACK
    return true;
  }

  /// Submit a restock request and return the settled result (restock_request_id,
  /// status, lines). Throws [DeviceActionException] on a failed ACK (e.g. an
  /// unknown / cross-tenant ingredient).
  Future<Map<String, dynamic>> requestRestock({
    required List<RestockRequestLineInput> lines,
    String? note,
  }) async {
    final data = await _api.pushSync([
      buildRestockRequestEvent(lines: lines, note: note),
    ]);
    return _settledResult(data);
  }

  /// Submit a Phase A day-end stock count and return the settled result
  /// (stock_count_id, lines, lines_with_variance). Throws
  /// [DeviceActionException] on a failed ACK (unknown ingredient, fractional
  /// pieces on a whole-piece ingredient, missing ratio…).
  Future<Map<String, dynamic>> submitStockCount({
    required List<StockCountLineInput> lines,
    int? staffId,
    String? note,
  }) async {
    final data = await _api.pushSync([
      buildStockCountEvent(lines: lines, staffId: staffId, note: note),
    ]);
    return _settledResult(data);
  }

  /// Submit product wastage (cooked or bought-in items wasted at this branch)
  /// and return the settled result (wasted_lines, total_qty). Throws
  /// [DeviceActionException] on a failed ACK (unknown / ineligible product,
  /// over-waste beyond the shelf, missing note for an 'other' reason).
  Future<Map<String, dynamic>> submitProductWaste({
    required List<ProductWasteLineInput> lines,
    int? staffId,
    String? note,
  }) async {
    final data = await _api.pushSync([
      buildProductWasteEvent(lines: lines, staffId: staffId, note: note),
    ]);
    return _settledResult(data);
  }

  /// Extract the single event's settled result. A `processed` or `duplicate`
  /// ACK is success (a re-push echoes the original result); a `failed` ACK
  /// raises [DeviceActionException] carrying the server error.
  Map<String, dynamic> _settledResult(Map<String, dynamic> data) {
    final results = (data['results'] as List? ?? const []);
    if (results.isEmpty || results.first is! Map) {
      throw DeviceActionException('No response from the server. Please try again.');
    }
    final ack = (results.first as Map).cast<String, dynamic>();
    final result = (ack['result'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    if (ack['status'] == 'failed') {
      throw DeviceActionException(
        (result['error'] ?? 'The server rejected the request.').toString(),
      );
    }
    return result;
  }
}
