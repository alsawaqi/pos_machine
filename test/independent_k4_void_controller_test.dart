import 'dart:async';
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
  @override
  Future<void> assertNoPendingCombine() async {}
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

void main(){TestWidgetsFlutterBinding.ensureInitialized();
 test('managed controller preserves active history through delayed or failed void ACK',()async{
  final storage=_FakeStorage();final c=PosController(orderStorage:storage)..managedKitchen=()=>true;addTearDown(c.dispose);final record=_serverRecord();c.applyServerOrderHistory([record]);
  final entered=Completer<void>(),finish=Completer<void>();c.onOrderVoided=(uuid,{orderNumber,reason,voidReasonId,authorization})async{entered.complete();await finish.future;throw StateError('not confirmed');};
  final future=c.cancelCompletedOrder(record,cancelFullOrder:true,itemIndexes:{});await entered.future;expect(c.orderHistory.single.snapshot.isFullyCanceled,isFalse);expect(storage.updateCalled,isFalse);finish.complete();final message=await future;expect(message.toLowerCase(),contains('not confirmed'));expect(c.orderHistory.single.snapshot.isFullyCanceled,isFalse);
  c.onOrderVoided=(uuid,{orderNumber,reason,voidReasonId,authorization})async{};await c.cancelCompletedOrder(record,cancelFullOrder:true,itemIndexes:{});expect(c.orderHistory.single.snapshot.isFullyCanceled,isTrue);
 });
 test('managed controller refuses local partial cancel without mutating history',()async{final storage=_FakeStorage();final c=PosController(orderStorage:storage)..managedKitchen=()=>true;addTearDown(c.dispose);var calls=0;c.onOrderVoided=(uuid,{orderNumber,reason,voidReasonId,authorization})async{calls++;};final record=_serverRecord();c.applyServerOrderHistory([record]);final message=await c.cancelCompletedOrder(record,cancelFullOrder:false,itemIndexes:{0});expect(message,contains('Local partial cancellation is unavailable'));expect(calls,0);expect(c.orderHistory.single.snapshot.isFullyCanceled,isFalse);expect(storage.updateCalled,isFalse);});
}
