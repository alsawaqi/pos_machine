import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F5 — the bank-terminal tender + per-item gifts.
String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mapPaymentMethod', () {
    test('bank labels map to bank_pos, checked before card', () {
      expect(mapPaymentMethod('Bank POS'), 'bank_pos');
      expect(mapPaymentMethod('Bank Card POS'), 'bank_pos');
      expect(mapPaymentMethod('Credit Card'), 'card');
      expect(mapPaymentMethod('Cash'), 'cash');
    });
  });

  group('per-item gift', () {
    const latte = Product(id: '1', name: 'Latte', category: 'X', price: 2.0);
    const cake = Product(id: '2', name: 'Cake', category: 'X', price: 3.0);

    PosController build() {
      final c = PosController();
      c.applyCatalog(
        categories: const ['X'],
        products: const [latte, cake],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        taxes: const [CompanyTax(name: 'VAT', ratePercent: 5)],
      );
      return c;
    }

    test('gifting a line writes it off: comp total, tax base, grand total',
        () {
      final c = build();
      addTearDown(c.dispose);
      c.addProduct(latte); // 2.000
      c.addProduct(cake); // 3.000

      expect(c.total, closeTo(5.25, 1e-9)); // 5.000 + 5% VAT

      final cakeLine = c.cart.firstWhere((i) => i.product.id == '2');
      expect(c.toggleGiftItem(cakeLine), isTrue);

      expect(c.giftedLinesTotal, closeTo(3.0, 1e-9));
      expect(c.compAmount, closeTo(3.0, 1e-9));
      expect(c.tax, closeTo(0.100, 1e-9)); // 5% of the remaining 2.000
      expect(c.total, closeTo(2.100, 1e-9));

      // Un-gift restores the full charge.
      expect(c.toggleGiftItem(cakeLine), isTrue);
      expect(c.compAmount, 0);
      expect(c.total, closeTo(5.25, 1e-9));
    });

    test('a FULL-ORDER comp blocks gifting; a gift shrinks a full comp', () {
      final c = build();
      addTearDown(c.dispose);
      c.addProduct(latte);
      c.addProduct(cake);

      final cakeLine = c.cart.firstWhere((i) => i.product.id == '2');
      expect(c.toggleGiftItem(cakeLine), isTrue);

      // Full-order comp now covers only the non-gifted remainder.
      c.applyComp(const AppliedComp(reasonId: 49, reasonName: 'Long Wait'));
      expect(c.compAmount, closeTo(5.0, 1e-9)); // gift 3.0 + comp 2.0
      expect(c.managerCompAmount, closeTo(2.0, 1e-9));
      expect(c.total, 0);

      // With a full-order comp applied, gifting another line is refused.
      final latteLine = c.cart.firstWhere((i) => i.product.id == '1');
      expect(c.toggleGiftItem(latteLine), isFalse);
      expect(latteLine.gifted, isFalse);
    });

    test('gifted flag survives the cart-item map round-trip and splits the '
        'merge signature', () {
      final item = CartItem(product: latte, gifted: true);
      expect(CartItem.fromMap(item.toMap()).gifted, isTrue);
      expect(item.mergeSignature, isNot(CartItem(product: latte).mergeSignature));
    });
  });

  group('payload comps rows', () {
    test('a gifted line emits an is_gift row; tender method is bank_pos', () {
      final snap = OrderSnapshot.initial().copyWith(
        orderType: 'quick_order',
        items: [
          {'id': '1', 'name': 'Latte', 'qty': 1, 'unitPrice': 2.0, 'lineTotal': 2.0},
          {
            'id': '2',
            'name': 'Cake',
            'qty': 1,
            'unitPrice': 3.0,
            'lineTotal': 3.0,
            'gifted': true,
            'giftAmount': 3.0,
          },
        ],
        rawSubtotal: 5.0,
        compAmount: 3.0,
        tax: 0.1,
        total: 2.1,
        paymentMethod: 'Bank POS',
      );

      final payload = buildOrderSyncPayload(
        snap,
        staffId: 7,
        newUuid: _seqUuid(),
      );
      final order = payload.events[0]['payload']['order'] as Map;
      final comps = (order['comps'] as List).cast<Map>();
      expect(comps, hasLength(1));
      expect(comps.single['is_gift'], isTrue);
      expect(comps.single['line_index'], 1);
      expect(comps.single['amount_baisas'], 3000);
      expect(comps.single.containsKey('comp_reason_id'), isFalse);
      expect(order['comp_total_baisas'], 3000);

      final pay = payload.events[1]['payload'] as Map;
      final tenders = (pay['payments'] as List).cast<Map>();
      expect(tenders.single['method'], 'bank_pos');
    });

    test('manager comp + gift rows sum EXACTLY to comp_total_baisas', () {
      final snap = OrderSnapshot.initial().copyWith(
        items: [
          {'id': '1', 'name': 'Latte', 'qty': 1, 'unitPrice': 2.0, 'lineTotal': 2.0},
          {
            'id': '2',
            'name': 'Cake',
            'qty': 1,
            'unitPrice': 3.0,
            'lineTotal': 3.0,
            'gifted': true,
            'giftAmount': 3.0,
          },
        ],
        rawSubtotal: 5.0,
        compAmount: 5.0, // gift 3.0 + full-order comp of the remaining 2.0
        compReasonId: 49,
        total: 0,
        paymentMethod: 'Cash',
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final order = payload.events[0]['payload']['order'] as Map;
      final comps = (order['comps'] as List).cast<Map>();
      expect(comps, hasLength(2));
      final reasoned = comps.firstWhere((c) => c['comp_reason_id'] == 49);
      final gift = comps.firstWhere((c) => c['is_gift'] == true);
      expect(reasoned['amount_baisas'], 2000);
      expect(gift['amount_baisas'], 3000);
      expect(order['comp_total_baisas'], 5000);
    });

    test('gift rows are capped to the write-off budget (order discount)', () {
      // A 1.000 order discount shrank the write-off: compAmount 2.5 while the
      // gifted line's face value is 3.0 — the row caps so the sum stays exact.
      final snap = OrderSnapshot.initial().copyWith(
        items: [
          {
            'id': '2',
            'name': 'Cake',
            'qty': 1,
            'unitPrice': 3.0,
            'lineTotal': 3.0,
            'gifted': true,
            'giftAmount': 3.0,
          },
        ],
        rawSubtotal: 3.0,
        discountAmount: 0.5,
        compAmount: 2.5,
        total: 0,
        paymentMethod: 'Cash',
      );

      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());
      final order = payload.events[0]['payload']['order'] as Map;
      final comps = (order['comps'] as List).cast<Map>();
      expect(comps.single['amount_baisas'], 2500);
      expect(order['comp_total_baisas'], 2500);
    });
  });
}
