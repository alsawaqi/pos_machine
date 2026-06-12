import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-G7 — no-tender delivery-provider orders on the device.
///
/// The payload builder emits order.create + order.deliver (never order.pay)
/// for a pending delivery snapshot, and the controller exempts delivery
/// orders from offers / discounts / loyalty / round-up (the provider's
/// listed price is final — only tax was gated before this feature).
String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

OrderSnapshot _deliverySnapshot() {
  return OrderSnapshot.initial().copyWith(
    orderType: 'delivery',
    items: [
      {'id': '10', 'name': 'Latte', 'qty': 2, 'unitPrice': 1.5, 'lineTotal': 3.0},
    ],
    rawSubtotal: 3.0,
    tax: 0,
    total: 3.0,
    paymentStatus: 'Pending verification',
    paymentMethod: 'Delivery',
    customerReferenceNumber: '91234567',
    deliveryProviderId: 4,
    deliveryProviderName: 'Talabat',
    deliveryReference: 'TLB-88421',
    deliveryDriverPhone: '99887766',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildOrderSyncPayload — pending delivery', () {
    test('emits order.create + order.deliver with the proceed-popup facts', () {
      final payload = buildOrderSyncPayload(
        _deliverySnapshot(),
        lat: 23.588,
        lng: 58.3829,
        staffId: 7,
        deliveryProviderName: 'Talabat',
        newUuid: _seqUuid(),
      );

      expect(payload.events.length, 2);
      expect(payload.events[0]['event_type'], 'order.create');
      expect(payload.events[1]['event_type'], 'order.deliver');

      final deliver = payload.events[1]['payload'] as Map<String, dynamic>;
      expect(deliver['order_uuid'], payload.orderUuid);
      final delivery = deliver['delivery'] as Map<String, dynamic>;
      expect(delivery['provider_id'], 4);
      expect(delivery['reference'], 'TLB-88421');
      expect(delivery['customer_phone'], '91234567');
      expect(delivery['driver_phone'], '99887766');
      expect(deliver['gps'], {'lat': 23.588, 'lng': 58.3829});

      // No tender, no donation event — the money waits for the provider.
      expect(
        payload.events.where((e) => e['event_type'] == 'order.pay'),
        isEmpty,
      );
      expect(
        payload.events.where((e) => e['event_type'] == 'donation.record'),
        isEmpty,
      );
    });

    test('a delivery order WITHOUT a reference still pays normally', () {
      // Legacy path (pre-F7 tendered delivery, e.g. an old queued order):
      // no deliveryReference → the builder keeps the create+pay pair.
      final snap = _deliverySnapshot().copyWith(
        deliveryReference: '',
        paymentStatus: 'Paid',
        paymentMethod: 'Cash',
      );
      final payload = buildOrderSyncPayload(snap, newUuid: _seqUuid());

      expect(payload.events[1]['event_type'], 'order.pay');
    });
  });

  group('PosController — delivery exemptions', () {
    PosController seeded() {
      final c = PosController();
      c.applyCatalog(
        categories: const ['Coffee'],
        products: const [
          Product(id: '10', name: 'Latte', nameAr: '', category: 'Coffee', price: 1.5),
        ],
        floors: const [],
        tables: const [],
        discounts: [
          MerchantDiscount(
            id: 1,
            name: 'Happy hour',
            scope: 'order',
            amountType: 'percent',
            percent: 10,
            autoApply: true,
            isActive: true,
          ),
        ],
        offers: const [
          Offer(id: 1, name: 'BOGO', type: 'bogo', config: {'buy_product_id': 10, 'buy_qty': 1, 'get_product_id': 10, 'get_qty': 1}),
        ],
        branchId: 6,
      );
      return c;
    }

    test('offers and auto-discounts stop applying on a delivery order', () async {
      final c = seeded();
      c.addProduct(c.allProducts.first);
      c.addProduct(c.allProducts.first);

      await c.selectOrderType(OrderType.delivery);
      expect(c.appliedOffers, isEmpty);

      c.maybeAutoApplyOrderDiscount();
      expect(c.discount.isActive, isFalse);

      // Manual application is refused too.
      c.applyDiscount(const DiscountConfiguration(
        kind: DiscountKind.percentage,
        value: 10,
        label: 'Manual',
      ));
      expect(c.discount.isActive, isFalse);

      // And the line-discount probe yields nothing.
      expect(c.lineDiscountFor(c.cart.first).amount, 0);
    });

    test('switching INTO delivery clears a discount picked up before', () async {
      final c = seeded();
      c.addProduct(c.allProducts.first);
      c.applyDiscount(const DiscountConfiguration(
        kind: DiscountKind.fixedAmount,
        value: 0.5,
        label: 'Pre-switch',
      ));
      expect(c.discount.isActive, isTrue);

      await c.selectOrderType(OrderType.delivery);
      expect(c.discount.isActive, isFalse);
      expect(c.loyaltyRedeemRuleId, isNull);
    });

    test('no charity round-up on delivery orders', () async {
      final c = seeded();
      c.addProduct(c.allProducts.first);
      c.selectPaymentMethod('Credit Card');
      await c.selectOrderType(OrderType.delivery);
      expect(c.canOfferCharityRoundUp, isFalse);
    });

    test('completeDeliveryOrder guards: no provider / no reference / no cart', () async {
      final c = seeded();
      // Empty cart → null.
      expect(await c.completeDeliveryOrder(reference: 'X-1'), isNull);

      c.addProduct(c.allProducts.first);
      // Wrong order type → null.
      expect(await c.completeDeliveryOrder(reference: 'X-1'), isNull);

      await c.selectOrderType(OrderType.delivery);
      // No provider picked → null.
      expect(await c.completeDeliveryOrder(reference: 'X-1'), isNull);
      // Blank reference → null.
      c.selectDeliveryProvider(4);
      expect(await c.completeDeliveryOrder(reference: '   '), isNull);
    });
  });
}
