import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

/// LAUNCH-P4 C5 — channels on the till: in-store order types show only
/// `sold_in_store` products; on delivery, after choosing a provider, only
/// products with `sold_on_delivery` that the provider lists, at provider →
/// delivery → base price; and a delivery re-price keeps gifts and bundles.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(
    id: '1',
    name: 'Latte',
    category: 'Coffee',
    price: 1.500,
    deliveryPrice: 1.800,
    deliveryPriceByProvider: {7: 2.000},
  );
  const counterOnly = Product(
    id: '2',
    name: 'Refill',
    category: 'Coffee',
    price: 0.500,
    soldOnDelivery: false,
  );
  const appOnly = Product(
    id: '3',
    name: 'Family box',
    category: 'Coffee',
    price: 6.000,
    soldInStore: false,
    deliveryUnlistedProviderIds: {8},
  );

  PosController build() {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [latte, counterOnly, appOnly],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      deliveryProviders: const [
        DeliveryProvider(id: 7, name: 'Talabat'),
        DeliveryProvider(id: 8, name: 'Otlob'),
      ],
      branchId: 6,
    );
    c.selectCategory('Coffee');
    addTearDown(c.dispose);
    return c;
  }

  List<String> visible(PosController c) =>
      [for (final p in c.visibleProducts) p.id];

  test('in-store order types show only sold_in_store products', () async {
    final c = build();
    for (final type in [OrderType.quickOrder, OrderType.toGo]) {
      await c.selectOrderType(type);
      expect(visible(c), ['1', '2'], reason: type.name);
    }
    c.addProduct(appOnly);
    expect(c.cart, isEmpty, reason: 'not sold in store: never added');
  });

  test('delivery shows what the chosen provider lists, at its price', () async {
    final c = build();
    await c.selectOrderType(OrderType.delivery);
    expect(visible(c), ['1', '3']); // no provider picked yet
    c.selectDeliveryProvider(8);
    expect(visible(c), ['1']); // Otlob does not list the family box
    c.selectDeliveryProvider(7);
    expect(visible(c), ['1', '3']);
    c.addProduct(c.allProducts.firstWhere((p) => p.id == '1'));
    expect(c.cart.single.product.price, 2.000); // provider price
    c.selectDeliveryProvider(8);
    expect(c.cart.single.product.price, 1.800); // delivery price
  });

  test('payment is refused for a line the channel does not sell', () async {
    final c = build();
    await c.selectOrderType(OrderType.delivery);
    c.selectDeliveryProvider(7);
    c.addProduct(c.allProducts.firstWhere((p) => p.id == '3'));
    expect(c.menuTenderRefusal(), isNull);
    c.selectDeliveryProvider(8); // moved to an app that does not list it
    final refusal = c.customerTenderRefusal();
    expect(refusal, contains('Family box'));
  });

  test('the delivery re-price keeps the gift flag and the bundle', () async {
    final c = build();
    c.addProduct(latte);
    final line = c.cart.single;
    expect(c.toggleGiftItem(line), isTrue);
    line.bundleKey = '41:0';
    await c.selectOrderType(OrderType.delivery);
    c.selectDeliveryProvider(7);
    final repriced = c.cart.single;
    expect(repriced.product.price, 2.000);
    expect(repriced.gifted, isTrue);
    expect(repriced.bundleKey, '41:0');
    await c.selectOrderType(OrderType.quickOrder);
    expect(c.cart.single.product.price, 1.500);
    expect(c.cart.single.gifted, isTrue);
    expect(c.cart.single.bundleKey, '41:0');
  });
}
