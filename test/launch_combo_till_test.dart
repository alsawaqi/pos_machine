import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pricing_adapter.dart';
import 'package:pos_machine/services/receipt_layout.dart';
import 'package:pos_machine/services/transfer_claim.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH combo add-on, Part C (till) — combos and meals as LINES (owner
/// decisions 2026-10-07; pos_api combo handback §7, fix order A1; pricing
/// from mithqal_pricing v0.4.0):
///  1. a fixed-only combo is added with one tap;
///  2. a combo / meal with choices or upgrades opens the sheet: "Included"
///     items, "Upgrade?", choice questions that start empty with + / −
///     repeats and extra prices, per-item options; Add only when complete;
///     required add-on groups never auto-tick; the same item may be picked
///     more than once (the old defect);
///  3. "Make it a meal? +price" on an eligible main;
///  4. cart, receipt and kitchen ticket; 5. the §7.6 wire with the split;
///  6. the old slot model is gone; 7. AR / EN.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = AddonGroup(
    id: 5,
    name: 'Size',
    nameAr: 'الحجم',
    multiSelect: false,
    minSelections: 1,
    maxSelections: 1,
    options: [
      AddonOption(id: 51, label: 'Regular', priceDelta: 0, isDefault: true),
      AddonOption(id: 52, label: 'Large', priceDelta: 0.200),
    ],
  );
  const remove = AddonGroup(
    id: 6,
    name: 'Remove',
    multiSelect: true,
    options: [
      AddonOption(id: 61, label: 'No cheese', priceDelta: -0.100),
      AddonOption(id: 62, label: 'No onion', priceDelta: 0),
    ],
  );
  const ice = AddonGroup(
    id: 7,
    name: 'Ice',
    multiSelect: false,
    minSelections: 1,
    maxSelections: 1,
    options: [
      AddonOption(id: 71, label: 'Less ice', priceDelta: 0),
      AddonOption(id: 72, label: 'No ice', priceDelta: -0.500),
    ],
  );
  const regular = CartItemModifier(
    id: '51',
    group: 'Size',
    label: 'Regular',
    price: 0,
  );
  const noCheese = CartItemModifier(
    id: '61',
    group: 'Remove',
    label: 'No cheese',
    price: -0.100,
  );
  const noIce = CartItemModifier(
    id: '72',
    group: 'Ice',
    label: 'No ice',
    price: -0.500,
  );

  const burger = Product(
    id: '30',
    name: 'Beef burger',
    nameAr: 'برجر لحم',
    category: 'Menu',
    categoryId: 1,
    price: 2.000,
    deliveryPrice: 2.500,
    addonGroupIds: [6],
  );
  const chicken = Product(
    id: '33',
    name: 'Chicken burger',
    category: 'Menu',
    categoryId: 1,
    price: 1.800,
  );
  const fries = Product(
    id: '31',
    name: 'Fries',
    nameAr: 'بطاطس',
    category: 'Menu',
    categoryId: 2,
    price: 1.000,
  );
  const loaded = Product(
    id: '35',
    name: 'Loaded fries',
    nameAr: 'بطاطس محملة',
    category: 'Menu',
    categoryId: 2,
    price: 1.500,
  );
  const cola = Product(
    id: '32',
    name: 'Cola',
    category: 'Menu',
    categoryId: 3,
    price: 1.000,
    addonGroupIds: [5],
  );
  const juice = Product(
    id: '34',
    name: 'Fresh juice',
    category: 'Menu',
    categoryId: 3,
    price: 1.200,
  );
  const water = Product(
    id: '36',
    name: 'Water',
    category: 'Menu',
    categoryId: 3,
    price: 0.300,
    addonGroupIds: [7],
  );
  const familyBox = Product(
    id: '40',
    name: 'Family box',
    nameAr: 'صندوق العائلة',
    category: 'Menu',
    categoryId: 9,
    price: 5.000,
    deliveryPrice: 5.500,
    deliveryUnlistedProviderIds: {8},
    productType: 'combo',
    comboLines: [
      pricing.ComboLineDef.fixed(id: 1, productId: 30, quantity: 2),
      pricing.ComboLineDef.fixed(
        id: 2,
        productId: 31,
        sortOrder: 1,
        upgrades: [
          pricing.ComboUpgradeDef(productId: 35, upgradePriceBaisas: 800),
        ],
      ),
      pricing.ComboLineDef.choice(
        id: 3,
        name: 'Drink',
        nameAr: 'مشروب',
        sortOrder: 2,
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
        ],
      ),
    ],
  );
  const fixedBox = Product(
    id: '41',
    name: 'Fixed box',
    category: 'Menu',
    price: 3.000,
    productType: 'combo',
    comboLines: [
      pricing.ComboLineDef.fixed(id: 11, productId: 30),
      pricing.ComboLineDef.fixed(id: 12, productId: 31, sortOrder: 1),
    ],
  );
  const drinksBox = Product(
    id: '42',
    name: 'Drinks box',
    category: 'Menu',
    price: 2.000,
    productType: 'combo',
    comboLines: [
      pricing.ComboLineDef.choice(
        id: 21,
        name: 'Drinks',
        nameAr: 'مشروبات',
        pickCount: 4,
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
          pricing.ComboChoiceItemDef(productId: 36),
        ],
      ),
    ],
  );
  const meal = MealSetup(
    id: 5,
    name: 'meal',
    nameAr: 'وجبة',
    mealPriceBaisas: 1200,
    mains: {30, 33},
    lines: [
      pricing.ComboLineDef.fixed(
        id: 51,
        productId: 31,
        upgrades: [
          pricing.ComboUpgradeDef(productId: 35, upgradePriceBaisas: 800),
        ],
      ),
      pricing.ComboLineDef.choice(
        id: 52,
        name: 'Drink',
        sortOrder: 1,
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 34, extraPriceBaisas: 300),
        ],
      ),
    ],
  );
  const products = [
    familyBox,
    fixedBox,
    drinksBox,
    burger,
    chicken,
    fries,
    loaded,
    cola,
    juice,
    water,
  ];

  PosController build({List<MealSetup> meals = const [meal]}) {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Menu'],
      products: products,
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      addonGroups: const [size, remove, ice],
      deliveryProviders: const [
        DeliveryProvider(id: 7, name: 'Talabat'),
        DeliveryProvider(id: 8, name: 'Otlob'),
      ],
      branchId: 6,
      meals: meals,
    );
    addTearDown(c.dispose);
    return c;
  }

  List<ComboComponent> resolve(
    PosController c,
    List<pricing.ComboLineDef> lines,
    List<ComboSelection> picks,
  ) {
    final r = c.resolveCombo(lines, picks);
    return r.components;
  }

  const colaPick = ComboSelection(
    lineId: 3,
    productId: '32',
    modifiers: [regular],
  );

  Map<String, dynamic> firstLine(OrderSnapshot snapshot) =>
      (((buildOrderSyncPayload(snapshot).events.first['payload']
                          as Map)['order']
                      as Map)['lines']
                  as List)
              .first
          as Map<String, dynamic>;

  group('combos on the till cart', () {
    test('a fixed-only combo: every item served as is at one price', () {
      final c = build();
      final items = resolve(c, fixedBox.comboLines, const []);
      expect(items.map((i) => [i.productId, i.kind, i.filled]), [
        ['30', 'fixed', true],
        ['31', 'fixed', true],
      ]);
      expect(c.addCombo(fixedBox, items), isTrue);
      expect(c.cart.single.unitPrice, closeTo(3.000, 1e-9));
      expect(c.menuTenderRefusal(), isNull);
    });

    test('pick 4 with repeats (3 Cola + 1 juice) and an extra price', () {
      final c = build();
      final r = c.resolveCombo(drinksBox.comboLines, const [
        ComboSelection(
          lineId: 21,
          productId: '32',
          qty: 3,
          modifiers: [regular],
        ),
        ComboSelection(lineId: 21, productId: '34'),
      ]);
      expect(r.problems, isEmpty);
      expect(c.addCombo(drinksBox, r.components), isTrue);
      final line = c.cart.single;
      expect(line.components.map((i) => [i.productId, i.qty]), [
        ['32', 3],
        ['34', 1],
      ]);
      expect(line.unitPrice, closeTo(2.300, 1e-9)); // 2.000 + juice 0.300
      // Three is not pick 4: refused.
      final short = c.resolveCombo(drinksBox.comboLines, const [
        ComboSelection(
          lineId: 21,
          productId: '32',
          qty: 3,
          modifiers: [regular],
        ),
      ]);
      expect(short.problems.single.code, pricing.ComboProblemCode.wrongCount);
      expect(c.addCombo(drinksBox, short.components), isFalse);
    });

    test('an upgrade swaps to the real product at its upgrade price', () {
      final c = build();
      final items = resolve(c, familyBox.comboLines, const [
        ComboSelection(lineId: 2, productId: '35'),
        colaPick,
      ]);
      expect(items.map((i) => [i.productId, i.kind, i.extraPrice]), [
        ['30', 'fixed', 0.0],
        ['35', 'upgrade', 0.8],
        ['32', 'choice', 0.0],
      ]);
      expect(items[1].name, 'Loaded fries');
      expect(c.addCombo(familyBox, items), isTrue);
      expect(c.cart.single.unitPrice, closeTo(5.800, 1e-9));
    });

    test('items that do not fit the lines are refused', () {
      final c = build();
      // A choice line left empty (choices start empty).
      expect(
        c.addCombo(familyBox, resolve(c, familyBox.comboLines, const [])),
        isFalse,
      );
      // Not offered by the line.
      expect(
        c.addCombo(familyBox, [
          ...resolve(c, familyBox.comboLines, const [colaPick]).take(2),
          const ComboComponent(lineId: 3, productId: '31', name: 'Fries'),
        ]),
        isFalse,
      );
      // A wrong extra (the juice is +0.300).
      expect(
        c.addCombo(familyBox, [
          ...resolve(c, familyBox.comboLines, const [colaPick]).take(2),
          const ComboComponent(lineId: 3, productId: '34', name: 'Juice'),
        ]),
        isFalse,
      );
      // The cola's required size missing.
      expect(
        c.addCombo(
          familyBox,
          resolve(c, familyBox.comboLines, const [
            ComboSelection(lineId: 3, productId: '32'),
          ]),
        ),
        isFalse,
      );
      expect(c.cart, isEmpty);
    });

    test('a combo never takes its category\'s required add-on group', () {
      final c = PosController(orderStorage: FakeOrderStorage());
      c.applyCatalog(
        categories: const ['Menu'],
        products: products,
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [size, remove, ice],
        categoryAddonGroupIds: const {
          9: [5],
        },
        branchId: 6,
      );
      addTearDown(c.dispose);
      expect(c.addonGroupsForProduct(familyBox), isEmpty);
      expect(c.needsOptionsBeforeAdd(familyBox), isFalse);
      c.addCombo(familyBox, resolve(c, familyBox.comboLines, const [colaPick]));
      expect(c.firstMissingRequiredChoice(), isNull);
      expect(c.menuTenderRefusal(), isNull);
    });

    test('a combo is unavailable when a fixed item is sold out or a choice '
        'line has nothing left', () {
      final c = build();
      expect(c.isComboUnavailable(fixedBox), isFalse);
      c.markSoldOutLocally('31', true);
      expect(c.isComboUnavailable(fixedBox), isTrue);
      expect(c.isUnorderable(fixedBox), isTrue);
      c.markSoldOutLocally('32', true);
      c.markSoldOutLocally('34', true);
      expect(c.isComboUnavailable(drinksBox), isFalse); // water is left
      c.markSoldOutLocally('36', true);
      expect(c.isComboUnavailable(drinksBox), isTrue);
    });

    test('refused on a delivery app that does not list the combo; delivery '
        'prices weigh the split', () async {
      final c = build();
      final items = resolve(c, familyBox.comboLines, const [colaPick]);
      await c.selectOrderType(OrderType.delivery);
      c.selectDeliveryProvider(8);
      expect(c.addCombo(familyBox, items), isFalse);
      c.selectDeliveryProvider(7);
      expect(
        c.addCombo(
          familyBox,
          resolve(c, familyBox.comboLines, const [colaPick]),
        ),
        isTrue,
      );
      final line = c.cart.single;
      expect(line.unitPrice, closeTo(5.500, 1e-9));
      // Tester call 2: delivery orders weigh items by their delivery price.
      expect(line.components.first.weightBaisas, 2500);
      c.selectDeliveryProvider(8);
      expect(c.customerTenderRefusal(), contains('Family box'));
    });

    test('a combo restored without its items cannot be paid', () {
      final c = build();
      c.receiveTransferredOrder(
        orderUuid: 'u-9',
        orderType: OrderType.quickOrder,
        items: [CartItem(product: familyBox)],
      );
      expect(c.menuTenderRefusal(), contains('Family box'));
    });

    test('edits keep the quantity; the sheet reopens with the picks', () {
      final c = build();
      c.addCombo(familyBox, resolve(c, familyBox.comboLines, const [colaPick]));
      c.incrementCartItem(c.cart.single);
      expect(c.subtotal, closeTo(10.000, 1e-9));
      final line = c.cart.single;
      // Filled fixed lines are not selections; the cola is.
      expect(
        ComboSelection.fromComponents(
          line.components,
        ).map((s) => [s.lineId, s.productId]),
        [
          [3, '32'],
        ],
      );
      expect(
        c.updateComboComponents(
          line,
          resolve(c, familyBox.comboLines, const [
            ComboSelection(lineId: 2, productId: '35'),
            ComboSelection(lineId: 3, productId: '34'),
          ]),
        ),
        isTrue,
      );
      expect(c.cart.single.qty, 2);
      expect(c.subtotal, closeTo(12.200, 1e-9)); // (5 + 0.8 + 0.3) x 2
    });
  });

  group('"Make it a meal?"', () {
    test('Beef 2.000 → 3.200 and Chicken 1.800 → 3.000', () {
      final c = build();
      expect(c.mealFor(burger)?.id, 5);
      expect(c.mealFor(chicken)?.id, 5);
      expect(c.mealFor(fries), isNull);
      for (final (main, price) in [(burger, 3.200), (chicken, 3.000)]) {
        expect(
          c.addMeal(
            main,
            meal,
            components: resolve(c, meal.lines, const [
              ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
            ]),
          ),
          isTrue,
        );
        expect(c.cart.first.unitPrice, closeTo(price, 1e-9));
      }
      final beef = c.cart.last;
      expect(beef.isMeal, isTrue);
      expect(beef.displayName(false), 'Beef burger meal');
      expect(beef.displayName(true), 'برجر لحم وجبة');
      // A meal line is invisible to product / category discounts.
      final priced = pricingLineFromCartItem(beef);
      expect(priced.productId, isNull);
      expect(priced.categoryId, isNull);
    });

    test('an ended meal is not offered; a meal no longer offered cannot be '
        'paid', () {
      const ended = MealSetup(
        id: 6,
        name: 'meal',
        mealPriceBaisas: 1000,
        mains: {30},
        onSaleUntil: '2026-01-31',
      );
      final c = build(meals: const [ended]);
      expect(c.mealFor(burger, now: DateTime(2026, 10, 7)), isNull);
      expect(c.mealFor(burger, now: DateTime(2026, 1, 31)), isNotNull);
      c.receiveTransferredOrder(
        orderUuid: 'u-8',
        orderType: OrderType.quickOrder,
        items: [
          CartItem(
            product: burger,
            meal: const CartMeal(id: 6, name: 'meal', price: 1.0),
          ),
        ],
      );
      expect(c.menuTenderRefusal(), contains('Beef burger meal'));
    });

    test(
      'a minus remove lowers the price; every item and line floors at 0',
      () {
        final c = build();
        c.addMeal(
          burger,
          meal,
          modifiers: const [noCheese],
          components: resolve(c, meal.lines, const [
            ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
          ]),
        );
        expect(c.cart.single.unitPrice, closeTo(3.100, 1e-9));
        // A standard line: 2.000 - 0.100; water 0.300 - 0.500 floors at 0.
        expect(
          CartItem(product: burger, modifiers: const [noCheese]).unitPrice,
          closeTo(1.900, 1e-9),
        );
        expect(CartItem(product: water, modifiers: const [noIce]).unitPrice, 0);
        // C-9: inside a combo each item floors at 0 (4 x water, No ice).
        final waters = resolve(c, drinksBox.comboLines, const [
          ComboSelection(
            lineId: 21,
            productId: '36',
            qty: 4,
            modifiers: [noIce],
          ),
        ]);
        expect(
          CartItem(product: drinksBox, components: waters).unitPrice,
          closeTo(2.000, 1e-9),
        );
      },
    );
  });

  group('the wire (§7.6, via mithqal_pricing)', () {
    test('order.create: every item with its kind, line and split', () {
      final c = build();
      c.addCombo(familyBox, resolve(c, familyBox.comboLines, const [colaPick]));
      final line = firstLine(c.snapshot());
      expect(line['product_id'], 40);
      expect(line['unit_price_baisas'], 5000);
      expect(line['line_total_baisas'], 5000);
      expect(line.containsKey('line_discount_baisas'), isFalse);
      expect(line.containsKey('meal_id'), isFalse);
      // The work order's example: 1.667 + 1.667 + 0.833 + 0.833 = 5.000.
      expect(line['combo'], [
        {
          'line_id': 1,
          'kind': 'fixed',
          'product_id': 30,
          'qty': 2,
          'extra_price_baisas': 0,
          'allocated_revenue_baisas': 3334,
        },
        {
          'line_id': 2,
          'kind': 'fixed',
          'product_id': 31,
          'qty': 1,
          'extra_price_baisas': 0,
          'allocated_revenue_baisas': 833,
        },
        {
          'line_id': 3,
          'kind': 'choice',
          'product_id': 32,
          'qty': 1,
          'extra_price_baisas': 0,
          'allocated_revenue_baisas': 833,
          'addons': [
            {'add_on_id': 51, 'price_delta_baisas': 0},
          ],
        },
      ]);
    });

    test(
      'a line discount: the split is of what the line paid (C-8 / C-13)',
      () {
        final c = build();
        final item = CartItem(
          product: familyBox,
          components: resolve(c, familyBox.comboLines, const [colaPick]),
        );
        final fields = comboDeviceFields(
          item,
          lineTotalBaisas: 5000,
          lineDiscountBaisas: 500,
        );
        expect(
          (fields['combo'] as List).map((c) => c['allocated_revenue_baisas']),
          [3000, 750, 750],
        );
        expect(fields.containsKey('line_discount_baisas'), isFalse);
      },
    );

    test('a meal: the main is the product, with its add-ons and share', () {
      final c = build();
      c.addMeal(
        burger,
        meal,
        modifiers: const [noCheese],
        components: resolve(c, meal.lines, const [
          ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
        ]),
      );
      final line = firstLine(c.snapshot());
      expect(line['product_id'], 30);
      expect(line['meal_id'], 5);
      expect(line['unit_price_baisas'], 3100);
      expect(line['addons'], [
        {'add_on_id': 61, 'price_delta_baisas': -100},
      ]);
      // Weights 2.000 / 1.000 / 1.000 over the 3.100 paid.
      expect(line['main_allocated_revenue_baisas'], 1550);
      expect(
        (line['combo'] as List).map(
          (c) => [c['product_id'], c['kind'], c['allocated_revenue_baisas']],
        ),
        [
          [31, 'fixed', 775],
          [32, 'choice', 775],
        ],
      );
    });

    test('order.hold / order.transfer keep the items and the split', () {
      final c = build();
      final draft = OrderSessionDraft(
        orderReference: 'REF-1',
        orderType: OrderType.quickOrder,
        selectedCategory: 'Menu',
        customerReferenceNumber: '',
        items: [
          CartItem(
            product: familyBox,
            qty: 2,
            components: resolve(c, familyBox.comboLines, const [colaPick]),
          ),
        ],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      );
      final hold = buildOrderHoldEvent(draft, orderUuid: 'u-1')!;
      final line =
          ((hold['payload'] as Map)['order'] as Map)['lines'][0] as Map;
      expect(
        (line['combo'] as List).map((c) => c['allocated_revenue_baisas']),
        [6668, 1666, 1666],
      );
      final transfer = buildOrderTransferEvent(
        draft,
        orderUuid: 'u-1',
        targetDeviceId: 4,
      )!;
      final tLine =
          ((transfer['payload'] as Map)['order'] as Map)['lines'][0] as Map;
      expect(tLine['combo'], line['combo']);
    });

    test('table rounds send identity only; items and meals change the '
        'fingerprint', () {
      final c = build();
      final box = CartItem(
        product: familyBox,
        components: resolve(c, familyBox.comboLines, const [
          ComboSelection(lineId: 2, productId: '35'),
          colaPick,
        ]),
      );
      final round = buildTableRoundLines([box]).single;
      expect(round, {
        'product_id': 40,
        'qty': 1,
        'addon_ids': <int>[],
        'notes': '',
        // The burgers (served as is) are left out.
        'combo': [
          {
            'line_id': 2,
            'product_id': 35,
            'qty': 1,
            'addon_ids': <int>[],
            'notes': '',
          },
          {
            'line_id': 3,
            'product_id': 32,
            'qty': 1,
            'addon_ids': [51],
            'notes': '',
          },
        ],
      });
      final other = buildTableRoundLines([
        CartItem(
          product: familyBox,
          components: resolve(c, familyBox.comboLines, const [colaPick]),
        ),
      ]).single;
      expect(tableLineFingerprint(round), isNot(tableLineFingerprint(other)));
      final mealLine = buildTableRoundLines([
        CartItem(
          product: burger,
          meal: const CartMeal(id: 5, name: 'meal', price: 1.2),
        ),
      ]).single;
      expect(mealLine['meal_id'], 5);
      expect(
        tableLineFingerprint(mealLine),
        isNot(
          tableLineFingerprint(buildTableRoundLines([burgerItem()]).single),
        ),
      );
      expect(tableLineFingerprint({'product_id': 31, 'qty': 1}), '[31,[],""]');
    });
  });

  group('cart, receipt and kitchen ticket (§2.6-2.7)', () {
    CartItem mealLine(PosController c) => CartItem(
      product: burger,
      modifiers: const [noCheese],
      meal: const CartMeal(id: 5, name: 'meal', nameAr: 'وجبة', price: 1.2),
      components: resolve(c, meal.lines, const [
        ComboSelection(lineId: 51, productId: '35'),
        ComboSelection(lineId: 52, productId: '32', modifiers: [regular]),
      ]),
    );

    test('the cart line lists the main, the items and minus prices', () {
      final c = build();
      final line = mealLine(c);
      expect(line.unitPrice, closeTo(3.900, 1e-9)); // 1.9 + 1.2 + 0.8
      expect(line.detailLinesFor(false), [
        '• Beef burger',
        '   + No cheese (-0.100 OMR)',
        '• Loaded fries (+0.800 OMR)',
        '• Cola',
        '   + Regular',
      ]);
      // Storage keeps it all.
      final back = CartItem.fromMap(line.toMap());
      expect(back.isMeal, isTrue);
      expect(back.meal!.nameAr, 'وجبة');
      expect(back.components.map((i) => i.kind), ['upgrade', 'choice']);
      expect(back.unitPrice, closeTo(3.900, 1e-9));
      expect(back.mergeSignature, line.mergeSignature);
      expect(
        back.mergeSignature,
        isNot(
          CartItem(product: burger, modifiers: const [noCheese]).mergeSignature,
        ),
      );
    });

    test('the receipt: one meal line with its total, items indented', () {
      final c = build();
      final line = mealLine(c);
      final order = OrderSnapshot.initial().copyWith(
        items: [line.toMap()],
        rawSubtotal: 3.9,
        subtotal: 3.9,
        total: 3.9,
        activePaymentBaseTotal: 3.9,
      );
      final text = [
        for (final l in buildReceiptLines(
          order,
          header: const ReceiptHeader(),
          at: DateTime(2026, 10, 7, 12),
        ))
          stripIsolates(l.toString()),
      ];
      expect(
        text,
        containsAllInOrder([
          '1 x Beef burger meal  3.900',
          'برجر لحم وجبة',
          '> Beef burger / برجر لحم',
          '   + No cheese (-0.100)',
          '> Loaded fries / بطاطس محملة (+0.800)',
          '> Cola',
          '   + Regular',
        ]),
      );
    });

    test('the kitchen: every item with its quantity and options', () {
      final c = build();
      final box = CartItem(
        product: familyBox,
        qty: 2,
        components: resolve(c, familyBox.comboLines, const [
          ComboSelection(lineId: 2, productId: '35'),
          colaPick,
        ]),
      );
      final lines = buildKitchenTicketLines(
        KitchenTicketData(
          orderLabel: 'Order #1',
          orderTypeLabel: 'Quick Order',
          time: DateTime(2026, 10, 7, 12),
          items: [box.toMap(), mealLine(c).toMap()],
        ),
      ).map((l) => l.text).toList();
      expect(
        lines,
        containsAllInOrder([
          '2 x Family box',
          '  > 4 x Beef burger',
          '  > 2 x Loaded fries', // the upgrade by its real name
          '  > 2 x Cola',
          '      + Size: Regular',
          '1 x Beef burger meal',
          '  > 1 x Beef burger',
          '      + Remove: No cheese',
          '  > 1 x Loaded fries',
          '  > 1 x Cola',
        ]),
      );
      expect(lines.join('\n'), isNot(contains('OMR')));
    });

    test('QR round kitchen lines: a meal heads its main', () {
      final line = QrRoundDisplayLine.fromJson({
        'product_name': 'Beef burger',
        'meal_id': 5,
        'display_name': 'Beef burger meal',
        'qty': 1,
        'unit_price_baisas': 3200,
        'line_discount_baisas': 0,
        'line_total_baisas': 3200,
        'addons': [
          {'add_on_id': 61, 'name': 'No cheese'},
        ],
        'components': [
          {
            'line_id': 51,
            'kind': 'upgrade',
            'product_name': 'Loaded fries',
            'qty': 1,
          },
        ],
      });
      final text = buildKitchenTicketLines(
        KitchenTicketData(
          orderLabel: 'QR',
          orderTypeLabel: 'QR',
          time: DateTime(2026, 10, 7),
          items: [line.toKitchenItem(arabic: false)],
        ),
      ).map((l) => l.text).toList();
      expect(
        text,
        containsAllInOrder([
          '1 x Beef burger meal',
          '  > 1 x Beef burger',
          '      + No cheese',
          '  > 1 x Loaded fries',
        ]),
      );
    });
  });

  group('config, transfers and server-priced lines', () {
    test('device config meals[] are cached in full (absent = kept)', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'meals': [
          {
            'id': 5,
            'uuid': 'm-5',
            'name': 'meal',
            'name_ar': 'وجبة',
            'meal_price_baisas': 1200,
            'sort_order': 0,
            'on_sale_from': null,
            'on_sale_until': '2026-12-31',
            'categories': [1],
            'excluded': [],
            'mains': [30, 33],
            'lines': [
              {
                'id': 52,
                'kind': 'choice',
                'sort_order': 1,
                'name': 'Drink',
                'pick_count': 1,
                'items': [
                  {'product_id': 32, 'extra_price_baisas': 0},
                ],
              },
            ],
          },
        ],
      });
      final json = parsed.meta.mealsJson;
      expect(json.present, isTrue);
      final meals = MealSetup.listFromJson(jsonDecode(json.value!));
      expect(meals.single.mains, {30, 33});
      expect(meals.single.mealPrice, closeTo(1.2, 1e-9));
      expect(meals.single.lines.single.pickCount, 1);
      expect(meals.single.onSaleOn(DateTime(2027, 1, 1)), isFalse);
      expect(
        ConfigMapper.parse(const <String, dynamic>{}).meta.mealsJson,
        const Value<String?>.absent(),
      );
    });

    test(
      'Drift 30 to 31 keeps the sync metadata and adds meals_json',
      () async {
        final db = AppDatabase.forTesting(
          NativeDatabase.memory(
            setup: (raw) {
              raw.execute('''
              CREATE TABLE sync_meta (
                id INTEGER PRIMARY KEY DEFAULT 1, company_id INTEGER,
                branch_id INTEGER, last_config_sync_at INTEGER,
                config_schema_version TEXT, order_cancel_positions TEXT,
                reports_positions TEXT, kitchen_positions TEXT,
                order_numbering_json TEXT, table_sessions_mode TEXT,
                company_tax_json TEXT
              )
            ''');
              raw.execute(
                "INSERT INTO sync_meta (id, branch_id, company_tax_json) "
                "VALUES (1, 6, '{\"vat_registered\":true}')",
              );
              raw.execute('PRAGMA user_version = 30');
            },
          ),
        );
        addTearDown(db.close);
        expect(db.schemaVersion, 31);
        final before = await db.getSyncMeta();
        expect(before?.branchId, 6);
        expect(before?.companyTaxJson, '{"vat_registered":true}');
        expect(before?.mealsJson, isNull);
        await db
            .into(db.syncMeta)
            .insertOnConflictUpdate(
              const SyncMetaCompanion(id: Value(1), mealsJson: Value('[]')),
            );
        expect((await db.getSyncMeta())?.mealsJson, '[]');
      },
    );

    test('a dine-in round intent may carry a combo / meal line, never a '
        'price inside it', () {
      Map<String, dynamic> payload(Map<String, dynamic> line) => {
        'table_id': 2,
        'client_request_id': '0b0c0d0e-0000-4000-8000-000000000001',
        'seating_key': 'seat-1',
        'submitted_at': '2026-10-07T08:00:00.000Z',
        'queued_offline': false,
        'lines': [line],
      };
      DineInRequest request(Map<String, dynamic> line) => DineInRequest(
        tableId: 2,
        seatingUuid: 'seating-1',
        billUuid: null,
        payload: payload(line),
      );
      final meal = QrQuickLine(
        30,
        1,
        const [61],
        mealId: 5,
        combo: [QrQuickComboPick(52, 32)],
      ).toJson();
      expect(request(meal).payload['lines'], [meal]);
      expect(
        () => request({
          ...meal,
          'combo': [
            {
              'line_id': 52,
              'product_id': 32,
              'qty': 1,
              'extra_price_baisas': 0,
            },
          ],
        }),
        throwsFormatException,
      );
    });

    test('a claimed meal line resumes as a meal (§7.7)', () {
      final items = transferClaimCartItems(
        {
          'uuid': 'u-2',
          'items': [
            {
              'id': 700,
              'product_id': 30,
              'product_name': 'Beef burger',
              'meal_id': 5,
              'qty': 1,
              'unit_price_baisas': 3900,
              'line_total_baisas': 3900,
              'addons': [
                {
                  'add_on_id': 61,
                  'add_on_name': 'No cheese',
                  'price_delta_baisas': -100,
                },
              ],
              'main_allocated_revenue_baisas': 1700,
              'combo': [
                {
                  'id': 701,
                  'line_id': 51,
                  'kind': 'upgrade',
                  'product_id': 35,
                  'product_name': 'Loaded fries',
                  'qty': 1,
                  'extra_price_baisas': 800,
                  'allocated_revenue_baisas': 1300,
                },
                {
                  'id': 702,
                  'line_id': 52,
                  'kind': 'choice',
                  'product_id': 32,
                  'product_name': 'Cola',
                  'qty': 1,
                  'extra_price_baisas': 0,
                  'allocated_revenue_baisas': 900,
                },
              ],
            },
          ],
        },
        productForId: (id) => products.where((p) => p.id == id).firstOrNull,
        mealFor: (id) => id == 5 ? meal : null,
      );
      final line = items.single;
      expect(line.isMeal, isTrue);
      expect(line.product.id, '30');
      expect(line.product.price, closeTo(2.000, 1e-9)); // 3.9-1.2-0.8+0.1
      expect(line.unitPrice, closeTo(3.900, 1e-9));
      expect(line.displayName(false), 'Beef burger meal');
      expect(line.components.map((c) => c.kind), ['upgrade', 'choice']);
    });

    test('server-priced lines: line ids, meal ids; served-as-is items and '
        'a meal\'s main are never re-sent', () {
      final line = QrQuickLine(
        30,
        1,
        const [61],
        mealId: 5,
        combo: [
          QrQuickComboPick(52, 32, addons: const [51]),
        ],
      );
      expect(line.toJson(), {
        'product_id': 30,
        'qty': 1,
        'addon_ids': [61],
        'notes': null,
        'meal_id': 5,
        'combo': [
          {
            'line_id': 52,
            'product_id': 32,
            'qty': 1,
            'addon_ids': [51],
          },
        ],
      });
      expect(QrQuickLine.fromJson(line.toJson()).mealId, 5);
      expect(line.withQuantity(3).mealId, 5);
      expect(
        line.comboSignature,
        isNot(QrQuickLine(30, 1, const [61], combo: line.combo).comboSignature),
      );
      final server = {
        'product_id': 30,
        'meal_id': 5,
        'qty': 2,
        'addons': [
          {'add_on_id': 61},
        ],
        'components': [
          {'line_id': 51, 'kind': 'fixed', 'product_id': 31, 'filled': true},
          {'line_id': 52, 'kind': 'choice', 'product_id': 32, 'qty': 1},
        ],
      };
      expect(serverComboPicks(server).map((p) => p.toJson()), [
        {'line_id': 52, 'product_id': 32, 'qty': 1, 'addon_ids': <int>[]},
      ]);
      // Display lists every item, the main and a served-as-is one too.
      expect(serverComboLabels(server, arabic: false), [
        '> #30',
        '> #31',
        '> #32',
      ]);
      final row = TabletOrderRow({
        'uuid': 't-1',
        'tablet_order_uuid': 'tt-1',
        'order_type': 'quick',
        'state': 'pending',
        'total_baisas': 6400,
        'lines': [server],
      });
      expect(row.editLines.single.mealId, 5);
      expect(row.editLines.single.combo.single.lineId, 52);
    });

    test('draft rows estimate a meal with the floors', () {
      const main = QuickProduct(
        30,
        'Beef burger',
        priceBaisas: 2000,
        meal: QuickMeal(5, 'meal', mealPriceBaisas: 1200),
      );
      final line = QrQuickLine(30, 1, const [], mealId: 5);
      expect(quickDraftUnitBaisas(line, main, const [], const [-100]), 3100);
      expect(quickMealKeys(line, main)['display_name'], 'Beef burger meal');
      expect(
        quickDraftUnitBaisas(
          QrQuickLine(36, 1, const []),
          const QuickProduct(36, 'Water', priceBaisas: 300),
          const [],
          const [-500],
        ),
        0,
      );
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

    Future<PosController> pump(
      WidgetTester tester, {
      bool arabic = false,
    }) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        arabic: arabic,
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
    Finder price(String text) => find.descendant(
      of: key('combo-confirm'),
      matching: find.textContaining(text),
    );
    bool enabled(WidgetTester tester, String k) =>
        tester.widget<FilledButton>(key(k)).onPressed != null;

    testWidgets('a fixed-only combo is added with one tap (no dialog)', (
      tester,
    ) async {
      final controller = await pump(tester);
      await tester.tap(find.text('Fixed box').first);
      await tester.pumpAndSettle();
      expect(key('combo-sheet'), findsNothing);
      expect(controller.cart.single.product.id, '41');
      expect(controller.cart.single.components, hasLength(2));
      expect(controller.menuTenderRefusal(), isNull);
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('included items, an upgrade, a choice that starts empty', (
      tester,
    ) async {
      final controller = await pump(tester);
      await tester.tap(find.text('Family box').first);
      await tester.pumpAndSettle();
      expect(key('combo-sheet'), findsOneWidget);
      expect(find.text('Included'), findsOneWidget);
      expect(find.text('2 × Beef burger'), findsOneWidget);
      expect(find.text('Upgrade?'), findsOneWidget);
      expect(find.text('Drink — pick 1'), findsOneWidget);
      expect(find.text('0 of 1'), findsOneWidget);
      // Included items are not tappable: they have no + / −.
      expect(key('combo-choice-1-30-plus'), findsNothing);
      // Nothing is pre-picked: Add is off.
      expect(enabled(tester, 'combo-confirm'), isFalse);
      expect(price('5.000 OMR'), findsOneWidget);
      await tester.tap(key('combo-upgrade-2-35'));
      await tester.pumpAndSettle();
      expect(find.text('Loaded fries'), findsWidgets);
      expect(price('5.800 OMR'), findsOneWidget);
      await tester.tap(key('combo-choice-3-34-plus'));
      await tester.pumpAndSettle();
      expect(find.text('1 of 1'), findsOneWidget);
      expect(price('6.100 OMR'), findsOneWidget);
      // Full: no more picks on that line.
      expect(
        tester.widget<IconButton>(key('combo-choice-3-32-plus')).onPressed,
        isNull,
      );
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      final line = controller.cart.single;
      expect(line.components.map((c) => [c.productId, c.kind]), [
        ['30', 'fixed'],
        ['35', 'upgrade'],
        ['34', 'choice'],
      ]);
      expect(line.unitPrice, closeTo(6.100, 1e-9));
      // Edit reopens the sheet with the picks.
      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();
      expect(key('combo-sheet'), findsOneWidget);
      expect(find.text('1 of 1'), findsOneWidget);
      expect(tester.widget<Text>(key('combo-choice-3-34-qty')).data, '1');
      await tester.tap(key('combo-choice-3-34-minus'));
      await tester.pumpAndSettle();
      await tester.tap(key('combo-choice-3-32-plus'));
      await tester.pumpAndSettle();
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      expect(controller.cart.single.components.last.productId, '32');
      expect(controller.cart.single.unitPrice, closeTo(5.800, 1e-9));
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('the same item more than once (3 Cola + 1 juice)', (
      tester,
    ) async {
      final controller = await pump(tester);
      await tester.tap(find.text('Drinks box').first);
      await tester.pumpAndSettle();
      expect(find.text('Drinks — pick 4'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(key('combo-choice-21-32-plus'));
        await tester.pumpAndSettle();
      }
      await tester.tap(key('combo-choice-21-34-plus'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(key('combo-choice-21-32-qty')).data, '3');
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.text('+0.300'), findsOneWidget); // the juice's extra
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      final line = controller.cart.single;
      expect(line.components.map((c) => [c.productId, c.qty]), [
        ['32', 3],
        ['34', 1],
      ]);
      // The colas took their merchant default size (Regular).
      expect(line.components.first.modifiers.single.id, '51');
      expect(line.unitPrice, closeTo(2.300, 1e-9));
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('a required add-on group never auto-ticks; the item asks', (
      tester,
    ) async {
      final controller = await pump(tester);
      await tester.tap(find.text('Drinks box').first);
      await tester.pumpAndSettle();
      await tester.tap(key('combo-choice-21-36-plus'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(key('combo-choice-21-32-plus'));
        await tester.pumpAndSettle();
      }
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.text('Choose the options'), findsOneWidget);
      expect(enabled(tester, 'combo-confirm'), isFalse);
      await tester.tap(key('combo-options-21-36'));
      await tester.pumpAndSettle();
      // Nothing ticked for "Ice" (required, no default); the minus remove
      // price shows.
      expect(find.text('-0.500 OMR'), findsOneWidget);
      await tester.tap(find.text('No ice'));
      await tester.pumpAndSettle();
      await tester.tap(key('customize-confirm'));
      await tester.pumpAndSettle();
      expect(find.text('Choose the options'), findsNothing);
      expect(enabled(tester, 'combo-confirm'), isTrue);
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      final water = controller.cart.single.components.first;
      expect(water.productId, '36');
      expect(water.modifiers.single.id, '72');
      // An item never goes below 0: 2.000 stays.
      expect(controller.cart.single.unitPrice, closeTo(2.000, 1e-9));
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('"Make it a meal? +1.200": No keeps the main alone, Yes opens '
        'the meal', (tester) async {
      final controller = await pump(tester);
      await tester.tap(find.text('Beef burger').first);
      await tester.pumpAndSettle();
      expect(key('meal-offer'), findsOneWidget);
      expect(find.text('Make it a meal? +1.200'), findsOneWidget);
      await tester.tap(key('meal-offer-no'));
      await tester.pumpAndSettle();
      expect(controller.cart.single.isMeal, isFalse);
      expect(controller.cart.single.unitPrice, closeTo(2.000, 1e-9));

      await tester.tap(find.text('Beef burger').first);
      await tester.pumpAndSettle();
      await tester.tap(key('meal-offer-yes'));
      await tester.pumpAndSettle();
      expect(key('combo-sheet'), findsOneWidget);
      expect(key('combo-main'), findsOneWidget);
      expect(enabled(tester, 'combo-confirm'), isFalse); // drink not picked
      await tester.tap(key('combo-choice-52-32-plus'));
      await tester.pumpAndSettle();
      expect(price('3.200 OMR'), findsOneWidget);
      await tester.tap(key('combo-confirm'));
      await tester.pumpAndSettle();
      final line = controller.cart.first;
      expect(line.isMeal, isTrue);
      expect(line.displayName(false), 'Beef burger meal');
      expect(line.unitPrice, closeTo(3.200, 1e-9));
      expect(find.text('BEEF BURGER MEAL'), findsOneWidget);
      // A product that is no main is added at once.
      await tester.tap(find.text('Fries').first);
      await tester.pumpAndSettle();
      expect(key('meal-offer'), findsNothing);
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('Arabic: the sheet speaks the till\'s Arabic', (tester) async {
      await pump(tester, arabic: true);
      await tester.tap(find.text('صندوق العائلة').first);
      await tester.pumpAndSettle();
      expect(find.text('مشمول'), findsOneWidget);
      expect(find.text('ترقية؟'), findsOneWidget);
      expect(find.text('مشروب — اختر 1'), findsOneWidget);
      expect(find.text('0 من 1'), findsOneWidget);
      await disposeWorkspaceMachine(tester);
    });
  });
}

CartItem burgerItem() => CartItem(
  product: const Product(
    id: '30',
    name: 'Beef burger',
    category: 'Menu',
    price: 2.0,
  ),
);
