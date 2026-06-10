import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F1 — canceling a server-synced (cross-device) history order. Before this
/// fix `canCancel` hard-excluded every fromServer record, so an ONLINE device
/// (whose history list is replaced by server records) could never cancel
/// anything. Now a PAID server record cancels full-order: the in-memory list
/// updates and an order.void is mirrored on the server uuid; void/refunded
/// records stay locked; per-item cancel stays local-only.
class _FakeStorage implements OrderStorageService {
  bool updateCalled = false;

  @override
  Future<int> fetchNextOrderNumber() async => 1001;
  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {}
  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    updateCalled = true;
  }

  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async => const [];
  @override
  Future<void> saveHeldOrder(OrderSessionDraft draft) async {}
  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => const [];
  @override
  Future<void> saveDiningTableSession(DiningTableSession session) async {}
  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async => const [];
  @override
  Future<void> clearDiningTable(String tableId) async {}
  @override
  Future<void> deleteHeldOrder(String id) async {}
  @override
  Future<void> clearHeldOrders() async {}
  @override
  Future<void> clearAllData() async {}
}

OrderHistoryRecord _serverRecord({
  String status = 'paid',
  String uuid = 'uuid-100',
}) {
  return OrderHistoryRecord.fromServerJson(<String, dynamic>{
    'id': 100,
    'uuid': uuid,
    'status': status,
    'order_type': 'quick_order',
    'opened_at': '2026-06-11T10:00:00Z',
    'subtotal_baisas': 2500,
    'grand_total_baisas': 2688,
    'tax_total_baisas': 188,
    'items': [
      {'product_name': 'White Mocha', 'qty': 1, 'line_total_baisas': 2500},
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fromServerJson carries the server uuid + paid is not terminal', () {
    final record = _serverRecord();
    expect(record.fromServer, isTrue);
    expect(record.snapshot.serverOrderUuid, 'uuid-100');
    expect(record.isServerTerminal, isFalse);
    expect(_serverRecord(status: 'void').isServerTerminal, isTrue);
    expect(_serverRecord(status: 'refunded').isServerTerminal, isTrue);
  });

  test('full cancel of a paid server record voids by uuid, in memory only',
      () async {
    final storage = _FakeStorage();
    final controller = PosController(orderStorage: storage);
    addTearDown(controller.dispose);
    final voided = <String>[];
    int? voidedReasonId;
    controller.onOrderVoided = (uuid, {orderNumber, reason, voidReasonId}) {
      voided.add(uuid);
      voidedReasonId = voidReasonId;
    };

    final record = _serverRecord();
    controller.applyServerOrderHistory([record]);

    final message = await controller.cancelCompletedOrder(
      record,
      cancelFullOrder: true,
      itemIndexes: const <int>{},
      voidReason: const VoidReasonRef(
        id: 75,
        code: 'quality_issue',
        name: 'Quality Issue',
        affectsInventory: true,
        requiresManager: true,
      ),
    );

    expect(message, isNotEmpty);
    expect(voided, ['uuid-100']);
    expect(voidedReasonId, 75);
    // The in-memory record flips to canceled, stays a server record, and the
    // local store is untouched (the record never lived there).
    final updated = controller.orderHistory.single;
    expect(updated.snapshot.isFullyCanceled, isTrue);
    expect(updated.fromServer, isTrue);
    expect(storage.updateCalled, isFalse);

    // Idempotence: a second cancel reports already-canceled, no second void.
    await controller.cancelCompletedOrder(
      controller.orderHistory.single,
      cancelFullOrder: true,
      itemIndexes: const <int>{},
    );
    expect(voided, hasLength(1));
  });

  test('void/refunded server records and per-item requests are refused',
      () async {
    final storage = _FakeStorage();
    final controller = PosController(orderStorage: storage);
    addTearDown(controller.dispose);
    final voided = <String>[];
    controller.onOrderVoided =
        (uuid, {orderNumber, reason, voidReasonId}) => voided.add(uuid);

    final voidRecord = _serverRecord(status: 'void');
    controller.applyServerOrderHistory([voidRecord]);
    await controller.cancelCompletedOrder(
      voidRecord,
      cancelFullOrder: true,
      itemIndexes: const <int>{},
    );
    expect(voided, isEmpty);

    // Per-item cancel has no cross-device wire — refused for server records.
    final paid = _serverRecord();
    controller.applyServerOrderHistory([paid]);
    await controller.cancelCompletedOrder(
      paid,
      cancelFullOrder: false,
      itemIndexes: const <int>{0},
    );
    expect(voided, isEmpty);
    expect(controller.orderHistory.single.snapshot.isFullyCanceled, isFalse);
  });
}
