import '../models/qr_till_models.dart';
import 'pos_api_service.dart';

abstract interface class QrTillGateway {
  Future<List<QrTableBoardRow>> fetchTableBoard();
  Future<List<QrActiveOrder>> fetchActiveQrOrders();
  Future<QrActiveOrder?> activeQrOrder(String orderUuid);
  Future<QrSettlementClaim> claimSettlement(
    String orderUuid, {
    double? lat,
    double? lng,
  });
  Future<void> releaseSettlement(
    String orderUuid,
    QrReleaseOutcome outcome, {
    String? softposReference,
    String? softposAuthCode,
    Map<String, dynamic>? bankResponse,
  });
  Future<QrOrderActionResult> reopenPayment(String orderUuid);
  Future<QrOrderActionResult> fallbackToCounter(String orderUuid);
  Future<void> clearTable(int tableId);
}

/// Narrow server facade for QR table staff surfaces. No cart, draft, held, or
/// local-history API exists on this type, which makes the QR money boundary
/// straightforward to fake and audit.
class QrTillService implements QrTillGateway {
  QrTillService(this._api);

  final PosApiService _api;

  @override
  Future<List<QrTableBoardRow>> fetchTableBoard() => _api.fetchQrTableBoard();

  @override
  Future<List<QrActiveOrder>> fetchActiveQrOrders() =>
      _api.fetchActiveQrOrders();

  @override
  Future<QrActiveOrder?> activeQrOrder(String orderUuid) async {
    final orders = await fetchActiveQrOrders();
    for (final order in orders) {
      if (order.uuid == orderUuid && order.isSettleable) return order;
    }
    return null;
  }

  @override
  Future<QrSettlementClaim> claimSettlement(
    String orderUuid, {
    double? lat,
    double? lng,
  }) => _api.claimQrSettlement(orderUuid, lat: lat, lng: lng);

  @override
  Future<void> releaseSettlement(
    String orderUuid,
    QrReleaseOutcome outcome, {
    String? softposReference,
    String? softposAuthCode,
    Map<String, dynamic>? bankResponse,
  }) async {
    await _api.releaseQrSettlement(
      orderUuid: orderUuid,
      outcome: outcome,
      softposReference: softposReference,
      softposAuthCode: softposAuthCode,
      bankResponse: bankResponse,
    );
  }

  @override
  Future<QrOrderActionResult> reopenPayment(String orderUuid) =>
      _api.reopenQrPayment(orderUuid);

  @override
  Future<QrOrderActionResult> fallbackToCounter(String orderUuid) =>
      _api.fallbackQrToCounter(orderUuid);

  @override
  Future<void> clearTable(int tableId) => _api.clearQrTable(tableId);
}

/// D5's one place for cadence/backoff arithmetic. Screens still own lifecycle
/// start/stop so a backgrounded app has no timer at all.
class QrPollingPolicy {
  const QrPollingPolicy();

  static const Duration normalInterval = Duration(seconds: 10);

  Duration delayAfter(Object error) {
    if (error is ApiException && error.statusCode == 429) {
      final server = error.retryAfter;
      if (server != null && server > normalInterval) return server;
    }
    return normalInterval;
  }

  /// Board + open detail, each at most once per ten seconds. Count both ends of
  /// a conservative 60-second observation (t=0..60): seven of each, not six.
  static const int qrRequestsPerWorstRollingMinute = 14;

  /// The existing Staff POS transfer inbox fetches immediately, then every ten
  /// seconds: seven requests on the same conservative inclusive boundary.
  static const int existingSteadyRequestsPerWorstRollingMinute = 7;
  static const int combinedWorstRollingMinute =
      qrRequestsPerWorstRollingMinute +
      existingSteadyRequestsPerWorstRollingMinute;
}
