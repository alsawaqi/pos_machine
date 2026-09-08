import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/qr_pending_order.dart';
import '../models/qr_till_models.dart';
import '../services/pos_api_service.dart';
import '../services/qr_till_messages.dart';
import '../services/qr_till_service.dart';

/// The QR board's ten-second visibility/backoff policy, for quick orders.
/// Constructing the feed does not start it; only a visible foreground host does.
class QrPendingFeed extends ChangeNotifier {
  QrPendingFeed(
    this.service, {
    this.clock,
    this.arabic,
    List<QrPendingOrder> initial = const [],
  }) : _orders = List.unmodifiable(initial);

  final QrTillGateway service;
  final DateTime Function()? clock;
  final bool Function()? arabic;
  static const interval = Duration(seconds: 10);
  List<QrPendingOrder> _orders;
  Timer? _timer;
  bool _foreground = false;
  bool _disposed = false;
  bool _backingOff = false;
  bool _refreshing = false;
  DateTime? _attemptedAt;
  DateTime? _updatedAt;
  String? _error;

  List<QrPendingOrder> get orders => _orders;
  DateTime? get updatedAt => _updatedAt;
  String? get error => _error;
  bool get refreshing => _refreshing;
  bool get readOnly => _error != null || _updatedAt == null;
  DateTime _now() => clock?.call() ?? DateTime.now();

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      unawaited(refresh());
    } else if (!_backingOff) {
      _timer?.cancel();
    }
  }

  Future<void> forceRefresh() {
    _attemptedAt = null;
    return refresh();
  }

  Future<void> refresh() async {
    if (_disposed || !_foreground || _refreshing || _backingOff) return;
    _timer?.cancel();
    if (_attemptedAt != null && _now().difference(_attemptedAt!) < interval) {
      _schedule(interval - _now().difference(_attemptedAt!));
      return;
    }
    _attemptedAt = _now();
    _refreshing = true;
    notifyListeners();
    Duration? retryAfter;
    try {
      final orders = await service.fetchQrPendingOrders();
      if (_disposed) return;
      _orders = List.unmodifiable(orders);
      _updatedAt = _now();
      _error = null;
    } on ApiException catch (error) {
      if (error.statusCode == 429) {
        retryAfter = error.retryAfter ?? interval;
      }
      if (!_disposed) {
        _error = qrTillMessageForCode(
          error.code,
          arabic: arabic?.call() ?? false,
        );
      }
    } catch (_) {
      if (!_disposed) {
        _error = qrTillMessageForCode(null, arabic: arabic?.call() ?? false);
      }
    } finally {
      if (!_disposed) {
        _refreshing = false;
        notifyListeners();
        if (retryAfter != null) {
          _backingOff = true;
          _timer = Timer(retryAfter < interval ? interval : retryAfter, () {
            _backingOff = false;
            // Retry-After remains a clock while hidden, never a background poll.
            unawaited(refresh());
          });
        } else {
          _schedule(interval);
        }
      }
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_disposed && _foreground) _timer = Timer(delay, refresh);
  }

  void applyOrderAction(QrOrderActionResult result) {
    _orders = [
      for (final order in _orders)
        if (order.uuid != result.orderUuid)
          order
        else if (!const {'paid', 'voided', 'cancelled'}.contains(result.status))
          QrPendingOrder.fromJson({
            ...order.json,
            'status': result.status,
            'receipt_number':
                result.receiptNumber ?? order.active.receiptNumber,
            'temp_reference':
                result.tempReference ?? order.active.tempReference,
            // An action result is not a fresh A1 admission verdict.
            'actions': {'settle': false, 'to_counter': false},
          }),
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
