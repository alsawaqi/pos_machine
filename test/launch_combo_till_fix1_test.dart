import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'send_to_kitchen_test.dart' show B3Harness, b3Product;
import 'support/combo_fixtures.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH combo add-on — till client fix order 1 (behaviour; every test here
/// uses only APIs that existed at 67d9d45, so each one fails there by
/// behaviour, not by compilation):
///  T-C1 offer rows are part of a combo's split base;
///  T-C2 a cancelled sent meal never comes back as a phantom plain main;
///  T-C4 no "Make it a meal?" when the meal's items cannot be sold;
///  T-C5 a server meal line whose meal is gone is never edited into its main;
///  T-C6 a meal edit whose meal left the config says so;
///  H-C1 stale extra / upgrade / meal prices are refreshed;
///  H-C2 meal sale dates hold offline;
///  H-C3 an edit can repair a pick its line no longer offers.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const colaPick = ComboSelection(
    lineId: 3,
    productId: '32',
    modifiers: [regular],
  );

  PosController build({
    List<Product> menu = products,
    List<Offer> offers = const [],
    List<MealSetup> meals = const [meal],
  }) {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Menu'],
      products: menu,
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      addonGroups: const [size, remove, ice],
      offers: offers,
      branchId: 6,
      meals: meals,
    );
    addTearDown(c.dispose);
    return c;
  }

  Map<String, dynamic> order(PosController c) =>
      (buildOrderSyncPayload(c.snapshot()).events.first['payload']
              as Map)['order']
          as Map<String, dynamic>;

  /// The Family box with the juice at [juiceExtra] baisas.
  Product boxWithJuiceAt(int juiceExtra) => Product(
    id: familyBox.id,
    name: familyBox.name,
    nameAr: familyBox.nameAr,
    category: familyBox.category,
    categoryId: familyBox.categoryId,
    price: familyBox.price,
    productType: 'combo',
    comboLines: [
      familyBox.comboLines[0],
      familyBox.comboLines[1],
      pricing.ComboLineDef.choice(
        id: 3,
        name: 'Drink',
        sortOrder: 2,
        items: [
          const pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(
            productId: 34,
            extraPriceBaisas: juiceExtra,
          ),
        ],
      ),
    ],
  );

  group('T-C1 — the split base takes the offer rows aimed at the line', () {
    test('Family box x2 at "2 for 9.000": the items add up to 9.000', () {
      final c = build(
        offers: const [
          Offer(
            id: 70,
            name: 'Two boxes for 9.000',
            type: 'multi_buy',
            config: {
              'category_ids': [9],
              'qty': 2,
              'price_baisas': 9000,
            },
          ),
        ],
      );
      c.addCombo(
        familyBox,
        c.resolveCombo(familyBox.comboLines, const [colaPick]).components,
      );
      c.incrementCartItem(c.cart.single);
      final o = order(c);
      final line = (o['lines'] as List).single as Map;
      expect(line['line_total_baisas'], 10000);
      expect(o['discounts'], [
        {
          'name': 'Two boxes for 9.000',
          'amount_baisas': 1000,
          'offer_id': 70,
          'line_index': 0,
        },
      ]);
      final shares = [
        for (final c in line['combo'] as List)
          c['allocated_revenue_baisas'] as int,
      ];
      // 10% off: 4.500 a box, split 3.000 / 0.750 / 0.750 per box.
      expect(shares, [6000, 1500, 1500]);
      expect(shares.fold<int>(0, (a, b) => a + b), 9000);
    });
  });

  group('T-C2 — cancelling a sent meal on a live table', () {
    test('only the new drink is sent after the meal is cancelled', () async {
      final mealLine = CartItem(
        product: b3Product,
        meal: const CartMeal(id: 5, name: 'meal', price: 1.2),
      );
      final h = B3Harness();
      await h.init(items: [mealLine]);
      await h.bridge.send(h.bridge.activeSession()!);
      final wire = buildTableRoundLines([mealLine]).single;
      expect(wire['meal_id'], 5);
      await h.coordinator.cancelLine(
        h.bridge.activeSession()!,
        line: wire,
        qty: 1,
        prepared: false,
        authorizedBy: 'Manager',
      );
      await h.coordinator.settled;
      final session = h.bridge.activeSession()!;
      final tea = CartItem(
        product: const Product(
          id: '11',
          name: 'Tea',
          category: 'Drinks',
          price: 1,
        ),
      );
      final delta = await h.coordinator.delta(
        session.copyWith(draft: session.draft!.copyWith(items: [tea])),
      );
      expect(delta, [
        {'product_id': 11, 'qty': 1},
      ]);
      final cancel = h.events.singleWhere(
        (e) => e['event_type'] == 'table.session.cancel_line',
      );
      // The server is told which line: the meal, not the plain main.
      expect((cancel['payload'] as Map)['meal_id'], 5);
    });
  });

  group('the sheet on the till', () {
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      messenger.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      messenger.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    Future<PosController> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: ['Menu'],
          products: products,
          floors: [],
          tables: [],
          taxes: [],
          addonGroups: [size, remove, ice],
          meals: [meal],
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      return state.controller as PosController;
    }

    Finder key(String k) => find.byKey(ValueKey(k));

    testWidgets('T-C4: the meal\'s fixed item sold out — no offer, the main '
        'alone', (tester) async {
      final controller = await pump(tester);
      controller.markSoldOutLocally('31', true); // the meal's fries
      await tester.pumpAndSettle();
      await tester.tap(find.text('Beef burger').first);
      await tester.pumpAndSettle();
      expect(key('meal-offer'), findsNothing);
      expect(controller.cart.single.product.id, '30');
      expect(controller.cart.single.isMeal, isFalse);
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('T-C6: a meal edit whose meal left the config says so', (
      tester,
    ) async {
      final controller = await pump(tester);
      expect(
        controller.addMeal(
          burger,
          meal,
          components: controller.resolveCombo(meal.lines, const [
            ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
          ]).components,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      controller.meals = const [];
      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This meal is no longer available — cancel it and add it again.',
        ),
        findsOneWidget,
      );
      expect(key('combo-sheet'), findsNothing);
      expect(key('customize-confirm'), findsNothing);
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('H-C3: an edit shows a pick the line no longer offers, '
        'blocks Add and lets it be removed', (tester) async {
      final controller = await pump(tester);
      expect(
        controller.addCombo(
          familyBox,
          controller.resolveCombo(familyBox.comboLines, const [
            ComboSelection(lineId: 3, productId: '34'),
          ]).components,
        ),
        isTrue,
      );
      // The merchant unticks the juice from the drink line.
      final noJuice = Product(
        id: familyBox.id,
        name: familyBox.name,
        category: familyBox.category,
        categoryId: familyBox.categoryId,
        price: familyBox.price,
        productType: 'combo',
        comboLines: [
          familyBox.comboLines[0],
          familyBox.comboLines[1],
          const pricing.ComboLineDef.choice(
            id: 3,
            name: 'Drink',
            sortOrder: 2,
            items: [pricing.ComboChoiceItemDef(productId: 32)],
          ),
        ],
      );
      controller.applyCatalog(
        categories: const ['Menu'],
        products: [noJuice, ...products.where((p) => p.id != '40')],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [size, remove, ice],
        branchId: 6,
        meals: const [meal],
      );
      expect(controller.menuTenderRefusal(), isNotNull);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();
      expect(key('combo-sheet'), findsOneWidget);
      expect(key('combo-choice-3-34'), findsOneWidget);
      expect(key('combo-stale-pick'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('combo-confirm')).onPressed,
        isNull,
      );
      await tester.tap(key('combo-choice-3-34-minus'));
      await tester.pumpAndSettle();
      expect(key('combo-stale-pick'), findsNothing);
      await tester.tap(key('combo-choice-3-32-plus'));
      await tester.pumpAndSettle();
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      expect(controller.cart.single.components.last.productId, '32');
      expect(controller.menuTenderRefusal(), isNull);
      await disposeWorkspaceMachine(tester);
    });
  });

  testWidgets('T-C5: a server meal line whose meal is gone is refused, not '
      'turned into its plain main', (tester) async {
    const main = QuickProduct(30, 'Beef burger', priceBaisas: 2000);
    (String, QrQuickLine)? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await pickStaffRoundProduct(
                context,
                main,
                arabic: false,
                catalogue: const [main],
                initial: const {
                  'product_id': 30,
                  'meal_id': 5,
                  'qty': 1,
                  'addons': <Map<String, dynamic>>[],
                },
              );
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('meal-edit-unavailable')), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(result, isNull);
  });

  group('H-C1 — stale extra / meal prices are refreshed', () {
    test('a claimed or held combo takes today\'s extra price', () async {
      final old = build(menu: [boxWithJuiceAt(300), ...products.skip(1)]);
      old.addCombo(
        boxWithJuiceAt(300),
        old.resolveCombo(familyBox.comboLines, const [
          ComboSelection(lineId: 3, productId: '34'),
        ]).components,
      );
      final stale = old.cart.single;
      expect(stale.components.last.extraPrice, closeTo(0.3, 1e-9));

      // The merchant moved the juice to +0.400.
      final c = build(menu: [boxWithJuiceAt(400), ...products.skip(1)]);
      c.receiveTransferredOrder(
        orderUuid: 'u-1',
        orderType: OrderType.quickOrder,
        items: [CartItem.fromMap(stale.toMap())],
      );
      expect(c.cart.single.components.last.extraPrice, closeTo(0.4, 1e-9));
      expect(c.cart.single.unitPrice, closeTo(5.400, 1e-9));
      expect(c.menuTenderRefusal(), isNull);
      final line = (order(c)['lines'] as List).single as Map;
      expect((line['combo'] as List).last['extra_price_baisas'], 400);

      // A held one resumes at today's price too.
      final held = build(menu: [boxWithJuiceAt(400), ...products.skip(1)]);
      held.receiveTransferredOrder(
        orderUuid: 'u-2',
        orderType: OrderType.quickOrder,
        items: [CartItem.fromMap(stale.toMap())],
      );
      await held.holdCurrentOrder();
      await held.refreshHeldOrders();
      held.applyCatalog(
        categories: const ['Menu'],
        products: [boxWithJuiceAt(500), ...products.skip(1)],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [size, remove, ice],
        branchId: 6,
        meals: const [meal],
      );
      await held.resumeHeldOrder(held.heldOrders.single);
      expect(held.cart.single.components.last.extraPrice, closeTo(0.5, 1e-9));
    });

    test('a catalog refresh re-prices a combo already in the cart; a meal '
        'takes its new meal price', () {
      final c = build(menu: [boxWithJuiceAt(300), ...products.skip(1)]);
      c.addCombo(
        boxWithJuiceAt(300),
        c.resolveCombo(familyBox.comboLines, const [
          ComboSelection(lineId: 3, productId: '34'),
        ]).components,
      );
      c.addMeal(
        burger,
        meal,
        components: c.resolveCombo(meal.lines, const [
          ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
        ]).components,
      );
      const dearer = MealSetup(
        id: 5,
        name: 'meal',
        mealPriceBaisas: 1500,
        mains: {30, 33},
        lines: [],
      );
      c.applyCatalog(
        categories: const ['Menu'],
        products: [boxWithJuiceAt(400), ...products.skip(1)],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [size, remove, ice],
        branchId: 6,
        meals: [
          MealSetup(
            id: dearer.id,
            name: dearer.name,
            mealPriceBaisas: dearer.mealPriceBaisas,
            mains: dearer.mains,
            lines: meal.lines,
          ),
        ],
      );
      final box = c.cart.firstWhere((i) => !i.isMeal);
      final mealLine = c.cart.firstWhere((i) => i.isMeal);
      expect(box.components.last.extraPrice, closeTo(0.4, 1e-9));
      expect(mealLine.meal!.price, closeTo(1.5, 1e-9));
      expect(mealLine.unitPrice, closeTo(3.500, 1e-9));
      expect(c.menuTenderRefusal(), isNull);
    });
  });

  test('H-C2: a meal whose sale dates ended cannot be paid offline', () {
    const ended = MealSetup(
      id: 5,
      name: 'meal',
      mealPriceBaisas: 1200,
      mains: {30, 33},
      onSaleUntil: '2020-01-31',
    );
    final c = build(meals: const [ended]);
    expect(c.mealFor(burger), isNull);
    c.receiveTransferredOrder(
      orderUuid: 'u-3',
      orderType: OrderType.quickOrder,
      items: [
        CartItem(
          product: burger,
          meal: const CartMeal(id: 5, name: 'meal', price: 1.2),
        ),
      ],
    );
    expect(c.menuTenderRefusal(), contains('Beef burger meal'));
  });
}
