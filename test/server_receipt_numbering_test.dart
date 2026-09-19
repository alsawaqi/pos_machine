import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('shared table cash must not reserve a second receipt number', () async {
    final storage = FakeOrderStorage();
    final c = PosController(orderStorage: storage);
    addTearDown(c.dispose);
    c.printReceipts = false;
    c.printKitchenTickets = false;
    c.isLiveSharedTable = () => true;
    c.verifyDiningTableTender = () async => null;
    c.prepareDiningTableTender =
        null; // External claim is outside this existing regression.
    c.onDiningTableFinalRound = (_) async => true;
    c.orderNumbering = const OrderNumberingConfig(
      enabled: true,
      prefix: 'KLD-',
      pad: 4,
      scope: 'branch',
    );
    var reservations = 0;
    c.allocateReceiptNumber = () async {
      reservations++;
      return (number: 105, formatted: 'KLD-0105');
    };
    c.diningTableDefinitions = const [
      DiningTableDefinition(
        id: '1',
        floorId: '1',
        name: 'Table 1',
        sizeLabel: '2',
        seats: 2,
        sortOrder: 1,
      ),
    ];
    c.addProduct(
      const Product(id: '7', name: 'Coffee', category: 'Coffee', price: 1),
    );
    c.selectedOrderType = OrderType.dineIn;
    c.activeDiningTableId = '1';
    c.diningTableSessions = [
      DiningTableSession(
        tableId: '1',
        floorId: '1',
        status: DiningTableStatus.occupied,
        updatedAt: DateTime.now(),
        serverOrderUuid: 'canonical-bill',
        seatingUuid: 'canonical-seat',
        draft: c.createDraft(),
      ),
    ];
    c.selectPaymentMethod('Cash');
    await c.payAndPrint(cashTenderedAmount: 1);
    expect(
      reservations,
      0,
      reason: 'The server allocates once while settling the canonical bill.',
    );
    expect(storage.history, hasLength(1));
    expect(storage.history.single.snapshot.serverOrderUuid, 'canonical-bill');
    expect(storage.history.single.snapshot.receiptNumber, isEmpty);
  });
  test('unacknowledged server receipt displays temporary reference only', () {
    final pending = OrderSnapshot.fromMap({
      ...OrderSnapshot.initial().toMap(),
      'serverReceipt': true,
      'orderNumber': 1453,
      'serverOrderUuid': 'canonical-bill',
      'tempReference': 'T-TEST-001',
      'receiptNumber': '',
    });
    expect(pending.displayOrderNumber, 'T-TEST-001');
    expect(pending.toMap()['serverReceipt'], true);
    final confirmed = pending.copyWith(receiptNumber: 'KLD-0106');
    expect(confirmed.displayOrderNumber, 'KLD-0106');
    expect(confirmed.serverOrderUuid, 'canonical-bill');
    expect(OrderSnapshot.fromMap(confirmed.toMap()).receiptNumber, 'KLD-0106');
  });
}
