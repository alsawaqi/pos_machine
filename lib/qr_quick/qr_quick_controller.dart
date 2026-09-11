import 'package:flutter/foundation.dart';
import 'qr_quick_models.dart';
import 'qr_quick_store.dart';

abstract interface class QrQuickGateway {
  Future<List<QrQuickOrder>> fetch();
  Future<void> move(String uuid);
  Future<Map<String, dynamic>> append(QrQuickRequest request);
}

class QrQuickController extends ChangeNotifier {
  QrQuickController(this.gateway, this.store);
  final QrQuickGateway gateway;
  final QrQuickStore store;
  List<QrQuickOrder> orders = [];
  Map<String, QrQuickRequest> pending = {};
  bool ready = false;
  bool stale = true;
  bool busy = false;
  bool _fetching = false;
  bool _disposed = false;
  int _revision = 0;
  String? notice;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    try {
      pending = {
        for (final request in await store.load()) request.orderUuid: request,
      };
      ready = true;
      await refresh();
    } catch (_) {
      ready = false;
      notice = 'storage';
    }
    _notify();
  }

  Future<void> refresh() async {
    if (!ready || busy || _fetching || _disposed) return;
    _fetching = true;
    final revision = _revision;
    try {
      final result = await gateway.fetch();
      if (revision == _revision) {
        orders = result;
        stale = false;
      }
    } catch (_) {
      if (revision == _revision) stale = true;
    } finally {
      _fetching = false;
      _notify();
    }
  }

  void invalidate() {
    stale = true;
    _revision++;
    _notify();
  }

  QrQuickOrder? find(String uuid) {
    for (final order in orders) {
      if (order.uuid == uuid) return order;
    }
    return null;
  }

  bool canAdd(String uuid) =>
      ready &&
      !stale &&
      !busy &&
      !pending.containsKey(uuid) &&
      find(uuid)?.canAdd == true;
  bool canPay(String uuid) =>
      ready &&
      !stale &&
      !busy &&
      !pending.containsKey(uuid) &&
      find(uuid)?.canPay == true;

  Future<bool> add(String uuid, List<QrQuickLine> lines) async {
    if (!canAdd(uuid)) return false;
    final request = QrQuickRequest(uuid, QrQuickRequest.newId(), lines);
    busy = true;
    _revision++;
    notice = null;
    _notify();
    try {
      // COMMIT the identity before any POST. A failed write prevents the send.
      await store.save(request);
      pending[uuid] = request;
    } catch (_) {
      ready = false;
      notice = 'storage';
      busy = false;
      _notify();
      return false;
    }
    return _send(request, fresh: true);
  }

  Future<bool> retry(String uuid) async {
    final request = pending[uuid];
    if (!ready || busy || request == null) return false;
    busy = true;
    _revision++;
    notice = null;
    _notify();
    // Same UUID and exact original lines, even if the bill left the inbox.
    return _send(request, fresh: false);
  }

  Future<bool> _send(QrQuickRequest request, {required bool fresh}) async {
    var success = false;
    try {
      final result = await gateway.append(request);
      final order = QrQuickOrder(qrMap(result['order']));
      final addition = qrMap(result['addition']);
      if (order.uuid != request.orderUuid ||
          addition['id'] is! int ||
          (addition['id'] as int) < 1 ||
          addition['priced_lines'] is! List ||
          (addition['priced_lines'] as List).length != request.lines.length ||
          addition['round_no'] is! int ||
          (addition['round_no'] as int) < 1 ||
          addition['subtotal_baisas'] is! int ||
          addition['tax_baisas'] is! int ||
          addition['total_baisas'] is! int ||
          result['replayed'] is! bool) {
        throw const FormatException('Invalid addition acknowledgement');
      }
      final frozen = (addition['priced_lines'] as List).map(qrMap).toList();
      for (var index = 0; index < request.lines.length; index++) {
        final line = frozen[index];
        if (line['product_id'] != request.lines[index].productId ||
            line['qty'] != request.lines[index].quantity ||
            line['order_item_id'] is! int ||
            (line['order_item_id'] as int) < 1) {
          throw const FormatException('Mismatched addition acknowledgement');
        }
      }
      await store.remove(request);
      pending.remove(request.orderUuid);
      orders = [
        for (final old in orders)
          if (old.uuid != order.uuid) old,
        order,
      ];
      notice = 'added';
      success = true;
    } on QrQuickFailure catch (error) {
      // Once a response was lost, only a valid acknowledgement can unlock.
      // A later auth/refusal response does not prove the original POST failed.
      if (fresh && error.refused && error.code != 'idempotency_conflict') {
        try {
          await store.remove(request);
          pending.remove(request.orderUuid);
          notice = error.code;
        } catch (_) {
          notice = 'uncertain';
        }
      } else {
        notice = 'uncertain';
      }
    } catch (_) {
      notice = 'uncertain';
    } finally {
      busy = false;
      stale = true;
      _notify();
    }
    await refresh();
    return success;
  }

  Future<void> move(String uuid) async {
    if (!ready ||
        stale ||
        busy ||
        pending.containsKey(uuid) ||
        find(uuid)?.canMove != true) {
      return;
    }
    busy = true;
    _revision++;
    notice = null;
    _notify();
    try {
      await gateway.move(uuid);
    } on QrQuickFailure catch (error) {
      notice = error.code;
    } catch (_) {
      notice = 'refresh';
    } finally {
      busy = false;
      stale = true;
      _notify();
    }
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
