import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

/// In-memory [OrderStorageService] for widget tests: the real service is
/// sqflite-backed and its I/O cannot complete inside testWidgets' FakeAsync
/// zone. Parked on [debugOrderStorageOverride] in setUp.
class FakeOrderStorage implements OrderStorageService {
  int _nextOrderNumber = 1450;
  final List<OrderHistoryRecord> history = <OrderHistoryRecord>[];
  final List<HeldOrderRecord> held = <HeldOrderRecord>[];
  final List<DiningTableSession> dining = <DiningTableSession>[];

  @override
  Future<void> clearAllData() async {
    _nextOrderNumber = 1450;
    history.clear();
    held.clear();
    dining.clear();
  }

  @override
  Future<void> clearHeldOrders() async => held.clear();

  @override
  Future<void> clearDiningTable(String tableId) async =>
      dining.removeWhere((record) => record.tableId == tableId);

  @override
  Future<void> deleteHeldOrder(String id) async =>
      held.removeWhere((record) => record.id == id);

  @override
  Future<int> fetchNextOrderNumber() async => _nextOrderNumber;

  @override
  Future<List<HeldOrderRecord>> loadHeldOrders() async => List.of(held);

  @override
  Future<List<DiningTableSession>> loadDiningTableSessions() async =>
      List.of(dining);

  @override
  Future<List<OrderHistoryRecord>> loadOrderHistory() async => List.of(history);

  @override
  Future<void> saveCompletedOrder(OrderSnapshot snapshot) async {
    history.insert(
      0,
      OrderHistoryRecord(
        id: 'history_${snapshot.orderNumber}',
        orderNumber: snapshot.orderNumber,
        orderType: OrderTypeLabel.fromStorage(snapshot.orderType),
        createdAt: DateTime.now(),
        snapshot: snapshot,
      ),
    );
    _nextOrderNumber = snapshot.orderNumber + 1;
  }

  @override
  Future<void> updateCompletedOrder(OrderHistoryRecord record) async {
    final index = history.indexWhere((entry) => entry.id == record.id);
    if (index != -1) history[index] = record;
  }

  @override
  Future<void> saveHeldOrder(OrderSessionDraft draft) async {
    held.insert(
      0,
      HeldOrderRecord(
        id: 'held_${draft.orderReference}',
        orderNumber: draft.orderNumber,
        orderReference: draft.orderReference,
        orderType: draft.orderType,
        heldAt: DateTime.now(),
        draft: draft,
      ),
    );
  }

  @override
  Future<void> saveDiningTableSession(DiningTableSession session) async {
    dining
      ..removeWhere((record) => record.tableId == session.tableId)
      ..add(session);
  }
}
