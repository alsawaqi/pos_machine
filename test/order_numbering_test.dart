import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F8 — merchant-defined order numbering: the config flows from
/// /device/config to the controller; payment allocates the server number
/// once (offline falls back to the local counter); the formatted number
/// rides the snapshot, receipts, and order.create.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('config parse → meta JSON → catalog → controller', () {
    final parsed = ConfigMapper.parse(<String, dynamic>{
      'settings': {
        'order_numbering': {
          'enabled': true,
          'prefix': 'KLD-',
          'pad': 4,
          'scope': 'company',
          'daily_reset': true,
        },
      },
    });
    expect(parsed.meta.orderNumberingJson.value, isNotNull);

    final config = OrderNumberingConfig.fromJson(<String, dynamic>{
      'enabled': true,
      'prefix': 'KLD-',
      'pad': 4,
      'scope': 'company',
      'daily_reset': true,
    });
    expect(config.enabled, isTrue);
    expect(config.prefix, 'KLD-');
    expect(config.scope, 'company');
    expect(config.dailyReset, isTrue);

    // Absent/disabled config decodes to disabled.
    expect(OrderNumberingConfig.fromJson(const {}).enabled, isFalse);
  });

  test('snapshot + display: merchant number wins, local number stands alone',
      () {
    final withNumber = OrderSnapshot.initial()
        .copyWith(orderNumber: 1451, receiptNumber: 'KLD-0042');
    expect(withNumber.displayOrderNumber, 'KLD-0042');
    // Round-trips the local-store map.
    expect(OrderSnapshot.fromMap(withNumber.toMap()).receiptNumber, 'KLD-0042');

    final withoutNumber = OrderSnapshot.initial().copyWith(orderNumber: 1451);
    expect(withoutNumber.displayOrderNumber, '#1451');
  });

  test('order.create carries receipt_number only when allocated', () {
    String Function() seq() {
      var n = 0;
      return () => 'uuid-${n++}';
    }

    final allocated = OrderSnapshot.initial().copyWith(
      items: [
        {'id': '1', 'name': 'Latte', 'qty': 1, 'unitPrice': 2.0, 'lineTotal': 2.0},
      ],
      rawSubtotal: 2.0,
      total: 2.0,
      paymentMethod: 'Cash',
      receiptNumber: 'KLD-0042',
    );
    final payload = buildOrderSyncPayload(allocated, newUuid: seq());
    final order = payload.events[0]['payload']['order'] as Map;
    expect(order['receipt_number'], 'KLD-0042');

    final local = OrderSnapshot.initial().copyWith(
      items: [
        {'id': '1', 'name': 'Latte', 'qty': 1, 'unitPrice': 2.0, 'lineTotal': 2.0},
      ],
      rawSubtotal: 2.0,
      total: 2.0,
      paymentMethod: 'Cash',
    );
    final offline = buildOrderSyncPayload(local, newUuid: seq());
    final offlineOrder = offline.events[0]['payload']['order'] as Map;
    expect(offlineOrder.containsKey('receipt_number'), isFalse);
  });

  test('payment allocates ONCE when enabled; offline falls back silently',
      () async {
    const latte = Product(id: '1', name: 'Latte', category: 'X', price: 2.0);
    final c = PosController();
    addTearDown(c.dispose);
    c.applyCatalog(
      categories: const ['X'],
      products: const [latte],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      orderNumbering: const OrderNumberingConfig(
        enabled: true,
        prefix: 'KLD-',
        pad: 4,
        scope: 'branch',
      ),
    );

    var calls = 0;
    c.allocateReceiptNumber = () async {
      calls++;
      return (number: 42, formatted: 'KLD-0042');
    };

    c.addProduct(latte);
    c.selectPaymentMethod('Cash');
    await c.payAndPrint(cashTenderedAmount: 5.0);
    expect(calls, 1);

    // The next order allocates fresh (the per-order number was reset).
    expect(c.receiptNumber, '');
    c.addProduct(latte);
    c.allocateReceiptNumber = () async => throw Exception('offline');
    await c.payAndPrint(cashTenderedAmount: 5.0);
    // Fallback: no merchant number, the sale still completed.
    expect(c.receiptNumber, '');
  });

  test('fromServerJson maps receipt_number into history', () {
    final record = OrderHistoryRecord.fromServerJson(<String, dynamic>{
      'id': 9,
      'uuid': 'u-9',
      'status': 'paid',
      'order_type': 'quick_order',
      'opened_at': '2026-06-12T10:00:00Z',
      'grand_total_baisas': 2000,
      'receipt_number': 'KLD-0042',
      'items': const [],
    });
    expect(record.snapshot.receiptNumber, 'KLD-0042');
    expect(record.snapshot.displayOrderNumber, 'KLD-0042');
  });
}
