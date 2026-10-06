import 'package:flutter/foundation.dart';

import '../core/authorization.dart';
import '../qr_quick/qr_quick_models.dart';
import '../services/pos_api_service.dart';
import 'tablet_order_models.dart';

/// A tablet staff action's answer: `{outcome, order: Row}`.
class TabletActionResult {
  TabletActionResult(Map<String, dynamic> data)
    : outcome = data['outcome'] as String? ?? '',
      order = TabletOrderRow(Map<String, dynamic>.from(data['order'] as Map));
  final String outcome;
  final TabletOrderRow order;
}

/// A structured refusal of a tablet staff action (no write happened).
class TabletOrderFailure implements Exception {
  const TabletOrderFailure(this.code, {this.takenBy, this.reason});
  final String code;

  /// 409 `tablet_order_taken`: who holds it.
  final String? takenBy;
  final String? reason;
}

abstract interface class TabletOrdersGateway {
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false});
  Future<TabletActionResult> take(String uuid, {bool takeOver = false});
  Future<TabletActionResult> send(String uuid);
  Future<TabletActionResult> approve(
    String uuid, {
    required String requestId,
    required Map<String, dynamic> authorization,
  });
  Future<TabletActionResult> reject(String uuid);
  Future<TabletActionResult> edit(
    String uuid, {
    required String requestId,
    required List<QrQuickLine> lines,
  });

  /// A dine-in round not sent yet: the table round reject (tester call 12).
  Future<void> rejectRound(String seatingUuid, int roundId);

  /// The other active devices at this branch, by id (for "Being paid on").
  Future<Map<int, String>> deviceNames();
}

/// The till's API client for the tablet staff routes.
class ApiTabletOrdersGateway implements TabletOrdersGateway {
  ApiTabletOrdersGateway(this.api);
  final PosApiService api;

  Future<TabletActionResult> _act(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return TabletActionResult(await call());
    } on ApiException catch (error) {
      final status = error.statusCode ?? 0;
      if (!error.isNetwork && status >= 400 && status < 500) {
        final taken = error.data?['taken_by'];
        throw TabletOrderFailure(
          error.code ?? 'refused',
          takenBy: taken is Map ? taken['name']?.toString() : null,
          reason: error.reason,
        );
      }
      rethrow;
    }
  }

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async =>
      parseTabletOrderRows(await api.fetchTabletOrders(unpaidOnly: unpaidOnly));

  @override
  Future<TabletActionResult> take(String uuid, {bool takeOver = false}) =>
      _act(() => api.takeTabletOrder(uuid, takeOver: takeOver));

  @override
  Future<TabletActionResult> send(String uuid) =>
      _act(() => api.sendTabletOrder(uuid));

  @override
  Future<TabletActionResult> approve(
    String uuid, {
    required String requestId,
    required Map<String, dynamic> authorization,
  }) => _act(
    () => api.approveTabletRedeem(
      uuid,
      clientRequestId: requestId,
      authorization: authorization,
    ),
  );

  @override
  Future<TabletActionResult> reject(String uuid) =>
      _act(() => api.rejectTabletRedeem(uuid));

  @override
  Future<TabletActionResult> edit(
    String uuid, {
    required String requestId,
    required List<QrQuickLine> lines,
  }) => _act(
    () => api.editTabletOrderLines(
      uuid,
      clientRequestId: requestId,
      lines: [for (final line in lines) line.toJson()..remove('notes')],
    ),
  );

  @override
  Future<void> rejectRound(String seatingUuid, int roundId) async {
    try {
      await api.dineInReview(seatingUuid, roundId, staff: true, accept: false);
    } on ApiException catch (error) {
      final status = error.statusCode ?? 0;
      if (!error.isNetwork && status >= 400 && status < 500) {
        throw TabletOrderFailure(error.code ?? 'refused');
      }
      rethrow;
    }
  }

  @override
  Future<Map<int, String>> deviceNames() async => {
    for (final device in await api.listBranchDevices())
      if ((device['id'] as num?) != null)
        (device['id'] as num).toInt():
            device['name']?.toString() ?? '#${device['id']}',
  };
}

/// The tablet orders list and its staff actions (Part C item 4). Every
/// action answers with the server's fresh Row, which replaces the old one.
class TabletOrdersController extends ChangeNotifier {
  TabletOrdersController(this.gateway);
  final TabletOrdersGateway gateway;

  List<TabletOrderRow> orders = const [];
  Map<int, String> devices = const {};
  bool loaded = false;
  bool stale = false;
  bool _fetching = false;
  bool _disposed = false;

  /// The order an action is running on.
  String? busy;

  /// The last action's refusal code (`tablet_order_taken`, …), or `network`.
  String? notice;

  /// `tablet_order_taken`: who holds it.
  String? noticeName;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  TabletOrderRow? find(String uuid) {
    for (final row in orders) {
      if (row.uuid == uuid) return row;
    }
    return null;
  }

  Future<void> refresh() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    try {
      final next = await gateway.list();
      orders = List.unmodifiable(next);
      stale = false;
      loaded = true;
      if (devices.isEmpty && next.any((r) => r.charge.deviceId != null)) {
        try {
          devices = await gateway.deviceNames();
        } catch (_) {
          // The device name is a nicety: "another device" is shown instead.
        }
      }
    } catch (_) {
      stale = true;
    } finally {
      _fetching = false;
      _notify();
    }
  }

  void clearNotice() {
    notice = null;
    noticeName = null;
    _notify();
  }

  void _replace(TabletOrderRow row) {
    orders = List.unmodifiable([
      for (final old in orders)
        if (old.uuid == row.uuid) row else old,
      if (!orders.any((old) => old.uuid == row.uuid)) row,
    ]);
  }

  Future<TabletActionResult?> _run(
    String uuid,
    Future<TabletActionResult> Function() action,
  ) async {
    if (busy != null) return null;
    busy = uuid;
    notice = null;
    noticeName = null;
    _notify();
    try {
      final result = await action();
      _replace(result.order);
      return result;
    } on TabletOrderFailure catch (failure) {
      notice = failure.code;
      noticeName = failure.takenBy;
      // The refusal names what changed elsewhere: read the truth again.
      busy = null;
      await refresh();
      return null;
    } catch (_) {
      notice = 'network';
      return null;
    } finally {
      busy = null;
      _notify();
    }
  }

  /// Take, or take over an order another staff member holds (the caller
  /// confirms a take-over first).
  Future<bool> take(String uuid, {bool takeOver = false}) async =>
      await _run(uuid, () => gateway.take(uuid, takeOver: takeOver)) != null;

  /// Send to the kitchen (cash may come later).
  Future<bool> send(String uuid) async =>
      await _run(uuid, () => gateway.send(uuid)) != null;

  /// Approve the points request with [authorization] (the loyalty.redeem
  /// tick, or an approver's PIN). The block is signed over this tablet
  /// order, the amount approving takes now and a fresh request id.
  Future<bool> approve(String uuid, ActionAuthorization authorization) async {
    final row = find(uuid);
    final redeem = row?.redeem;
    if (row == null || redeem == null || !row.redeemWaiting) return false;
    final requestId = tabletRequestId();
    final block = authorization.block(
      subjectUuid: uuid,
      amountBaisas: redeem.amountBaisas,
      ref: requestId,
    );
    authorization.grant?.forget();
    return await _run(
          uuid,
          () =>
              gateway.approve(uuid, requestId: requestId, authorization: block),
        ) !=
        null;
  }

  Future<bool> reject(String uuid) async =>
      await _run(uuid, () => gateway.reject(uuid)) != null;

  /// Staff change the lines before the order is sent (F-8).
  Future<bool> editLines(String uuid, List<QrQuickLine> lines) async {
    if (lines.isEmpty) return false;
    final requestId = tabletRequestId();
    return await _run(
          uuid,
          () => gateway.edit(uuid, requestId: requestId, lines: lines),
        ) !=
        null;
  }

  /// A dine-in round that was not sent: reject it at the table.
  Future<bool> rejectRound(String uuid) async {
    final row = find(uuid);
    final seating = row?.tableSessionUuid;
    final round = row?.roundId;
    if (row == null || !row.dineIn || seating == null || round == null) {
      return false;
    }
    if (busy != null) return false;
    busy = uuid;
    notice = null;
    _notify();
    try {
      await gateway.rejectRound(seating, round);
      return true;
    } on TabletOrderFailure catch (failure) {
      notice = failure.code;
      return false;
    } catch (_) {
      notice = 'network';
      return false;
    } finally {
      busy = null;
      _notify();
      await refresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
