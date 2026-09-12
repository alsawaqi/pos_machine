import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

/// CORE-001 Step 2 §4.4 — the controller may expose many pricing-derived
/// getters during one frame, but the pure pricing core must run only once for
/// an unchanged order. The nonce, broadcasts, and the 60-second time-window
/// boundary are the three cache invalidators required by the adoption handoff.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late int priceOrderCalls;
  late PosController controller;

  setUp(() {
    now = DateTime.utc(2026, 8, 17, 8);
    priceOrderCalls = 0;
    controller = PosController(
      orderStorage: FakeOrderStorage(),
      priceOrderOverride: (input) {
        priceOrderCalls++;
        return pricing.priceOrder(input);
      },
    );
    controller.clock = () => now;
    controller.applyCatalog(
      categories: const <String>['Coffee'],
      products: const <Product>[
        Product(
          id: '10',
          name: 'Latte',
          category: 'Coffee',
          price: 1.500,
        ),
      ],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      discounts: const <MerchantDiscount>[],
      offers: const <Offer>[],
      branchId: 6,
    );
    controller.addProduct(controller.allProducts.single);
    addTearDown(controller.dispose);
  });

  test('multiple derived reads at the same nonce price exactly once', () {
    expect(controller.rawSubtotal, 1.500);
    expect(controller.discountAmount, 0);
    expect(controller.subtotal, 1.500);
    expect(controller.tax, 0);
    expect(controller.total, 1.500);
    expect(controller.appliedOffers, isEmpty);

    expect(priceOrderCalls, 1);
  });

  test('a direct order nonce bump forces the next read to reprice', () {
    expect(controller.total, 1.500);
    expect(priceOrderCalls, 1);

    controller.orderUpdateNonce++;

    expect(controller.total, 1.500);
    expect(priceOrderCalls, 2);
    expect(controller.rawSubtotal, 1.500);
    expect(priceOrderCalls, 2);
  });

  test('the cached price expires at the 60-second boundary', () {
    expect(controller.total, 1.500);
    expect(priceOrderCalls, 1);

    now = now.add(const Duration(seconds: 59));
    expect(controller.total, 1.500);
    expect(priceOrderCalls, 1);

    now = now.add(const Duration(seconds: 1));
    expect(controller.total, 1.500);
    expect(priceOrderCalls, 2);
  });

  test('a broadcast invalidates even when the nonce is unchanged', () {
    expect(controller.total, 1.500);
    expect(priceOrderCalls, 1);
    final nonce = controller.orderUpdateNonce;

    // Removal deliberately does not increment orderUpdateNonce; _broadcast()
    // is therefore the only reason this stale cached result cannot survive.
    controller.removeCartItem(controller.cart.single);
    expect(controller.orderUpdateNonce, nonce);

    expect(controller.total, 0);
    expect(priceOrderCalls, 2);
  });
}
