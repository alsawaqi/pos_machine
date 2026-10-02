import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P2 P2-7 "sell, but warn" on the till: cached branch stock — low,
/// zero, negative, missing or stale — never blocks a sale, for recipe, unit
/// and cooked products alike. Explicit availability still does: the
/// product's daily window, an add-on whose linked product is not in this
/// branch's catalog, and an unknown add-on group in the QR/table workspace.

// Branch ingredient balances: 1 holds less than one portion, 2 is empty,
// 3 is negative, 4 has no balance row at all.
const _balances = <int, double>{1: 0.05, 2: 0.0, 3: -1.5};

const _belowRecipe = Product(
  id: '11',
  name: 'Shawarma',
  category: 'Food',
  price: 1.2,
  stockMode: 'ingredient',
  recipe: [RecipeLine(ingredientId: 1, quantity: 0.2)],
);
const _zeroRecipe = Product(
  id: '12',
  name: 'Falafel',
  category: 'Food',
  price: 0.8,
  stockMode: 'ingredient',
  recipe: [RecipeLine(ingredientId: 2, quantity: 0.1)],
);
const _negativeRecipe = Product(
  id: '13',
  name: 'Hummus',
  category: 'Food',
  price: 0.9,
  stockMode: 'ingredient',
  recipe: [RecipeLine(ingredientId: 3, quantity: 0.1)],
);
const _missingRecipe = Product(
  id: '14',
  name: 'Fattoush',
  category: 'Food',
  price: 1.1,
  stockMode: 'ingredient',
  recipe: [RecipeLine(ingredientId: 4, quantity: 0.1)],
);
const _unitZero = Product(
  id: '21',
  name: 'Cola',
  category: 'Food',
  price: 0.3,
  stockMode: 'unit',
  branchStockQty: 0,
);
const _unitNegative = Product(
  id: '22',
  name: 'Water',
  category: 'Food',
  price: 0.2,
  stockMode: 'unit',
  branchStockQty: -2,
);
const _unitOne = Product(
  id: '23',
  name: 'Juice',
  category: 'Food',
  price: 0.6,
  stockMode: 'unit',
  branchStockQty: 1,
);
// Cooked, never produced at this branch (no shelf count yet).
const _cookedNever = Product(
  id: '31',
  name: 'Biryani',
  category: 'Food',
  price: 2.5,
  stockMode: 'cooked',
);
const _cookedZero = Product(
  id: '32',
  name: 'Harees',
  category: 'Food',
  price: 1.9,
  stockMode: 'cooked',
  branchStockQty: 0,
);
// Explicitly unavailable outside 06:00–11:00 (with plenty of stock).
const _breakfast = Product(
  id: '51',
  name: 'Breakfast',
  category: 'Food',
  price: 1.5,
  stockMode: 'unit',
  branchStockQty: 5,
  availableFrom: '06:00:00',
  availableUntil: '11:00:00',
);

PosController _controllerWith(List<Product> products) {
  final c = PosController(orderStorage: FakeOrderStorage())
    ..printReceipts = false
    ..printKitchenTickets = false;
  c.applyCatalog(
    categories: const ['Food'],
    products: products,
    floors: const <DiningFloor>[],
    tables: const <DiningTableDefinition>[],
  );
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('controller', () {
    test('recipe, unit and cooked products stay orderable whatever the '
        'cached stock says', () {
      const products = [
        _belowRecipe,
        _zeroRecipe,
        _negativeRecipe,
        _missingRecipe,
        _unitZero,
        _unitNegative,
        _unitOne,
        _cookedNever,
        _cookedZero,
      ];
      final c = _controllerWith(products);
      addTearDown(c.dispose);
      for (final p in products) {
        expect(c.isUnorderable(p), isFalse, reason: '${p.name} is orderable');
      }
    });

    test('the cart is never capped at the cached shelf count', () {
      final c = _controllerWith(const [_unitOne, _unitZero, _cookedZero]);
      addTearDown(c.dispose);

      c.addProduct(_unitOne);
      c.addProduct(_unitOne); // one on the shelf, second sale still allowed
      c.incrementCartItem(
        c.cart.firstWhere((item) => item.product.id == _unitOne.id),
      );
      expect(c.cartQuantityForProduct(_unitOne.id), 3);

      c.addProduct(_unitZero);
      expect(c.cartQuantityForProduct(_unitZero.id), 1);

      c.addProduct(_cookedZero);
      c.addProduct(_cookedZero);
      expect(c.cartQuantityForProduct(_cookedZero.id), 2);
    });

    test('a bundle is never refused for stock', () {
      const offer = Offer(id: 5, name: 'Meal deal', type: 'bundle');
      final c = _controllerWith(const [_unitOne, _cookedNever]);
      addTearDown(c.dispose);

      c.addBundle(offer, const [_unitOne, _unitOne, _cookedNever]);

      expect(c.cartQuantityForProduct(_unitOne.id), 2);
      expect(c.cartQuantityForProduct(_cookedNever.id), 1);
    });

    test('a sale past zero stock is paid like any other', () async {
      final c = _controllerWith(const [_missingRecipe, _unitZero]);
      addTearDown(c.dispose);
      final completed = <OrderSnapshot>[];
      c.onOrderCompleted = completed.add;
      c.addListener(() {
        if (c.showCharityRoundUpPrompt) c.confirmCharityRoundUp(false);
      });

      expect(c.isUnorderable(_missingRecipe), isFalse);
      expect(c.isUnorderable(_unitZero), isFalse);
      c.addProduct(_missingRecipe);
      c.addProduct(_unitZero);
      await c.payAndPrint(cashTenderedAmount: 5);

      expect(completed, hasLength(1));
      expect(
        completed.single.items.map((line) => line['id']),
        unorderedEquals([_missingRecipe.id, _unitZero.id]),
      );
      expect(c.cart, isEmpty);
    });

    test('add-on options never grey for stock; an option whose linked '
        'product is not sold here still does', () {
      const cake = Product(
        id: '41',
        name: 'Cake',
        category: 'Food',
        price: 2,
        stockMode: 'cooked',
        branchStockQty: 0,
      );
      const patty = Product(
        id: '42',
        name: 'Patty',
        category: 'Food',
        price: 0.5,
        stockMode: 'cooked',
        branchStockQty: 1,
      );
      final c = _controllerWith(const [cake, patty]);
      addTearDown(c.dispose);

      // Linked product on the menu with an empty shelf.
      const cakeSlice = AddonOption(
        id: 1,
        label: 'Cake slice',
        priceDelta: 1,
        linkedProductId: 41,
      );
      // 'add' ingredient line with no cached balance.
      const extraSalad = AddonOption(
        id: 2,
        label: 'Extra salad',
        priceDelta: 0.1,
        consumption: [AddonConsumptionLine(ingredientId: 11, qty: 0.05)],
      );
      // 'add' product line needing more than the shelf holds.
      const doublePatty = AddonOption(
        id: 3,
        label: 'Double patty',
        priceDelta: 1,
        consumption: [AddonConsumptionLine(productId: 42, qty: 2)],
      );
      // Explicit: the linked product is not in this branch's catalog.
      const notSoldHere = AddonOption(
        id: 4,
        label: 'Ghost',
        priceDelta: 1,
        linkedProductId: 999,
      );

      expect(c.isAddonOptionUnavailable(cakeSlice), isFalse);
      expect(c.isAddonOptionUnavailable(extraSalad), isFalse);
      expect(c.isAddonOptionUnavailable(doublePatty), isFalse);
      expect(c.isAddonOptionUnavailable(notSoldHere), isTrue);
    });

    test('the daily window still blocks (explicit availability)', () {
      final c = _controllerWith(const [_breakfast]);
      addTearDown(c.dispose);

      c.clock = () => DateTime(2026, 10, 2, 15);
      expect(c.isUnorderable(_breakfast), isTrue);
      c.clock = () => DateTime(2026, 10, 2, 9);
      expect(c.isUnorderable(_breakfast), isFalse);
    });
  });

  test('QR/table workspace catalogue never disables a product for stock; '
      'the window and an unknown add-on group still do', () {
    final now = DateTime.now();
    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:00';
    // A window that opens two hours from now: closed right now.
    final later = Product(
      id: '61',
      name: 'Later',
      category: 'Food',
      price: 1,
      availableFrom: hhmm(now.add(const Duration(hours: 2))),
      availableUntil: hhmm(now.add(const Duration(hours: 3))),
    );
    const unknownGroup = Product(
      id: '62',
      name: 'Odd',
      category: 'Food',
      price: 1,
      addonGroupIds: [99],
    );

    final result = machineQuickCatalogue(
      CatalogSnapshot(
        categories: const ['Food'],
        products: [
          _belowRecipe,
          _zeroRecipe,
          _negativeRecipe,
          _missingRecipe,
          _unitZero,
          _unitNegative,
          _cookedNever,
          _cookedZero,
          later,
          unknownGroup,
        ],
        floors: const [],
        tables: const [],
        taxes: const [],
        ingredientBalances: _balances,
      ),
    );

    final available = {for (final q in result) q.id: q.available};
    for (final id in [11, 12, 13, 14, 21, 22, 31, 32]) {
      expect(available[id], isTrue, reason: 'product $id is sellable');
    }
    expect(available[61], isFalse);
    expect(available[62], isFalse);
  });

  group('menu screen', () {
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final m =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      m.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      m.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      m.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      for (final c in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(c, null);
      }
    });

    testWidgets('stock-short tiles show no SOLD OUT badge and a tap adds '
        'them; an out-of-hours tile still refuses', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const shortOnStock = [
        _belowRecipe,
        _zeroRecipe,
        _negativeRecipe,
        _missingRecipe,
        _unitZero,
        _cookedNever,
      ];
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: ['Food'],
          products: [...shortOnStock, _breakfast],
          floors: [],
          tables: [],
          taxes: [],
          ingredientBalances: _balances,
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final PosController controller = state.controller;
      controller.clock = () => DateTime(2026, 10, 2, 15); // breakfast closed
      controller.onMinuteTick();
      await tester.pumpAndSettle();

      expect(find.text('SOLD OUT'), findsNothing);
      expect(find.text('NOT AVAILABLE NOW'), findsOneWidget);

      Finder tile(String id) => find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString() == '_ProductTile' &&
            (w as dynamic).product.id == id,
      );
      for (final p in shortOnStock) {
        await tester.ensureVisible(tile(p.id));
        await tester.pumpAndSettle();
        await tester.tap(tile(p.id));
        await tester.pumpAndSettle();
        expect(
          controller.cartQuantityForProduct(p.id),
          1,
          reason: '${p.name} goes into the cart',
        );
      }

      await tester.ensureVisible(tile(_breakfast.id));
      await tester.pumpAndSettle();
      await tester.tap(tile(_breakfast.id), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(controller.cartQuantityForProduct(_breakfast.id), 0);

      await disposeWorkspaceMachine(tester);
    });
  });
}
