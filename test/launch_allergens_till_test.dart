import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH costs & allergens add-on, Part D (till): staff see a product's
/// allergens (Contains / May contain) in the item details (long-press), the
/// options sheet (each option shows what it adds) and the combo / meal sheet
/// (a meal = its main's plus its lines'); names from the config catalogue in
/// English / Arabic; the Drift cache keeps them; orders, prices, receipts
/// and kitchen tickets do not change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The server's catalogue (pos_api Allergens::catalogue, costs §6.1).
  const names = {
    'gluten': ['Gluten', 'الغلوتين'],
    'crustaceans': ['Crustaceans', 'القشريات'],
    'eggs': ['Eggs', 'البيض'],
    'fish': ['Fish', 'الأسماك'],
    'peanuts': ['Peanuts', 'الفول السوداني'],
    'soy': ['Soy', 'الصويا'],
    'milk': ['Milk', 'الحليب'],
    'tree_nuts': ['Tree nuts', 'المكسرات'],
    'celery': ['Celery', 'الكرفس'],
    'mustard': ['Mustard', 'الخردل'],
    'sesame': ['Sesame', 'السمسم'],
    'sulphites': ['Sulphites', 'الكبريتيت'],
    'lupin': ['Lupin', 'الترمس'],
    'molluscs': ['Molluscs', 'الرخويات'],
  };
  final catalogueJson = [
    for (final e in names.entries)
      {'code': e.key, 'name': e.value[0], 'name_ar': e.value[1]},
  ];
  final catalogue = AllergenInfo.listFromJson(catalogueJson);

  const cheese = AddonGroup(
    id: 6,
    name: 'Extras',
    multiSelect: true,
    options: [
      AddonOption(
        id: 61,
        label: 'Extra cheese',
        priceDelta: 0.2,
        allergens: ['milk'],
      ),
      AddonOption(id: 62, label: 'No onion', priceDelta: 0),
    ],
  );
  const size = AddonGroup(
    id: 5,
    name: 'Size',
    multiSelect: false,
    options: [AddonOption(id: 51, label: 'Large', priceDelta: 0.2)],
  );
  const burger = Product(
    id: '30',
    name: 'Beef burger',
    nameAr: 'برجر لحم',
    category: 'Menu',
    price: 2.0,
    addonGroupIds: [6],
    allergens: ['gluten', 'milk'],
    mayContain: ['sesame'],
  );
  const fries = Product(id: '31', name: 'Fries', category: 'Menu', price: 1.0);
  const shake = Product(
    id: '32',
    name: 'Milkshake',
    category: 'Menu',
    price: 1.0,
    allergens: ['milk'],
    mayContain: ['tree_nuts'],
  );
  const water = Product(id: '36', name: 'Water', category: 'Menu', price: 0.3);
  const box = Product(
    id: '40',
    name: 'Family box',
    category: 'Menu',
    price: 5.0,
    productType: 'combo',
    allergens: ['gluten', 'milk'],
    mayContain: ['sesame', 'tree_nuts'],
    comboLines: [
      pricing.ComboLineDef.fixed(id: 1, productId: 30),
      pricing.ComboLineDef.choice(
        id: 3,
        name: 'Drink',
        sortOrder: 1,
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 36),
        ],
      ),
    ],
  );
  const meal = MealSetup(
    id: 5,
    name: 'meal',
    mealPriceBaisas: 1200,
    mains: {30},
    allergens: ['milk'],
    mayContain: ['tree_nuts'],
    lines: [
      pricing.ComboLineDef.fixed(id: 51, productId: 31),
      pricing.ComboLineDef.choice(
        id: 52,
        name: 'Drink',
        sortOrder: 1,
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 36),
        ],
      ),
    ],
  );
  const products = [box, burger, fries, shake, water];

  group('the config and its cache', () {
    test('products, combos, options, meals and the catalogue parse; the '
        'cache maps them back', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'allergens': catalogueJson,
        'products': [
          {
            'id': 30,
            'name': 'Beef burger',
            'base_price_baisas': 2000,
            'allergens': ['gluten', 'milk'],
            'may_contain': ['sesame'],
          },
          {'id': 36, 'name': 'Water', 'base_price_baisas': 300},
        ],
        'addon_groups': [
          {
            'id': 6,
            'name': 'Extras',
            'addons': [
              {
                'id': 61,
                'name': 'Extra cheese',
                'price_delta_baisas': 200,
                'allergens': ['milk'],
              },
              {'id': 62, 'name': 'No onion', 'allergens': []},
            ],
          },
        ],
        'meals': [
          {
            'id': 5,
            'name': 'meal',
            'meal_price_baisas': 1200,
            'mains': [30],
            'lines': [],
            'allergens': ['milk'],
            'may_contain': ['tree_nuts'],
          },
        ],
      });
      final p = parsed.products.first;
      expect(p.allergensJson.value, '["gluten","milk"]');
      expect(p.mayContainJson.value, '["sesame"]');
      // A server without allergens sends nothing: null, not "none".
      expect(parsed.products.last.allergensJson.value, isNull);
      expect(parsed.addons.first.allergensJson.value, '["milk"]');
      expect(parsed.addons.last.allergensJson.value, '[]');
      expect(parsed.meta.allergenCatalogJson.present, isTrue);
      expect(
        ConfigMapper.parse(const {}).meta.allergenCatalogJson,
        const Value<String?>.absent(),
      );

      final snapshot = ConfigMapper.toCatalog(
        null,
        const [],
        [
          ProductRow(
            id: 30,
            name: 'Beef burger',
            basePriceBaisas: 2000,
            addonGroupIds: '',
            deliveryPricesJson: '{}',
            recipeJson: '[]',
            allergensJson: p.allergensJson.value,
            mayContainJson: p.mayContainJson.value,
          ),
        ],
        const [],
        const [],
        const [],
        [const AddonGroupRow(id: 6, name: 'Extras')],
        [
          AddonRow(
            id: 61,
            addOnGroupId: 6,
            name: 'Extra cheese',
            priceDeltaBaisas: 200,
            isDefault: false,
            consumptionJson: '[]',
            allergensJson: parsed.addons.first.allergensJson.value,
          ),
        ],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        SyncMetaRow(
          id: 1,
          mealsJson: parsed.meta.mealsJson.value,
          allergenCatalogJson: parsed.meta.allergenCatalogJson.value,
        ),
      );
      final product = snapshot.products.single;
      expect(product.allergens, ['gluten', 'milk']);
      expect(product.mayContain, ['sesame']);
      expect(snapshot.addonGroups.single.options.single.allergens, ['milk']);
      expect(snapshot.meals.single.allergens, ['milk']);
      expect(snapshot.meals.single.mayContain, ['tree_nuts']);
      expect(snapshot.allergenCatalog, hasLength(14));
      expect(snapshot.allergenCatalog[6].nameAr, 'الحليب');
    });

    test(
      'Drift 29 to head keeps cached rows and adds the allergen columns',
      () async {
        final db = AppDatabase.forTesting(
          NativeDatabase.memory(
            setup: (raw) {
              raw.execute('''
              CREATE TABLE products (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
                name_ar TEXT, category_id INTEGER,
                base_price_baisas INTEGER NOT NULL DEFAULT 0,
                branch_stock_qty REAL, image_url TEXT, status TEXT,
                addon_group_ids TEXT NOT NULL DEFAULT '',
                delivery_price_baisas INTEGER,
                delivery_prices_json TEXT NOT NULL DEFAULT '{}',
                stock_mode TEXT, recipe_json TEXT NOT NULL DEFAULT '[]',
                available_from TEXT, available_until TEXT
              )
            ''');
              raw.execute('''
              CREATE TABLE categories (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
                name_ar TEXT, display_order INTEGER NOT NULL DEFAULT 0,
                status TEXT, addon_group_ids_json TEXT NOT NULL DEFAULT '[]'
              )
            ''');
              raw.execute('''
              CREATE TABLE addon_groups (
                id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
                name_ar TEXT, selection_mode TEXT, min_selections INTEGER,
                max_selections INTEGER, status TEXT
              )
            ''');
              raw.execute('''
              CREATE TABLE addons (
                id INTEGER PRIMARY KEY, add_on_group_id INTEGER NOT NULL,
                name TEXT NOT NULL DEFAULT '', name_ar TEXT,
                price_delta_baisas INTEGER NOT NULL DEFAULT 0,
                is_default INTEGER NOT NULL DEFAULT 0, ingredient_id INTEGER,
                linked_product_id INTEGER,
                consumption_json TEXT NOT NULL DEFAULT '[]', status TEXT
              )
            ''');
              raw.execute('''
              CREATE TABLE sync_meta (
                id INTEGER PRIMARY KEY DEFAULT 1, company_id INTEGER,
                branch_id INTEGER, last_config_sync_at INTEGER,
                config_schema_version TEXT, order_cancel_positions TEXT,
                reports_positions TEXT, kitchen_positions TEXT,
                order_numbering_json TEXT, table_sessions_mode TEXT
              )
            ''');
              raw.execute(
                "INSERT INTO products (id, name, base_price_baisas) VALUES (5, 'Tea', 700)",
              );
              raw.execute(
                "INSERT INTO addons (id, add_on_group_id, name) VALUES (61, 6, 'Extra cheese')",
              );
              raw.execute('PRAGMA user_version = 29');
            },
          ),
        );
        addTearDown(db.close);
        expect(db.schemaVersion, 33);
        final product = (await db.select(db.products).get()).single;
        expect(product.name, 'Tea');
        expect(product.allergensJson, isNull);
        expect(product.mayContainJson, isNull);
        expect((await db.select(db.addons).get()).single.allergensJson, isNull);
        await db
            .into(db.syncMeta)
            .insertOnConflictUpdate(
              SyncMetaCompanion(
                id: const Value(1),
                allergenCatalogJson: Value(jsonEncode(catalogueJson)),
              ),
            );
        expect(
          AllergenInfo.listFromJson(
            jsonDecode((await db.getSyncMeta())!.allergenCatalogJson!),
          ),
          hasLength(14),
        );
      },
    );
  });

  group('the controller', () {
    PosController build() {
      final c = PosController(orderStorage: FakeOrderStorage());
      c.applyCatalog(
        categories: const ['Menu'],
        products: products,
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [cheese, size],
        branchId: 6,
        meals: const [meal],
        allergenCatalog: catalogue,
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'a meal shows its main\'s allergens with its own; names in EN / AR',
      () {
        final c = build();
        final all = c.mealAllergens(burger, meal);
        expect(all.contains, ['gluten', 'milk']);
        // "May contain" never repeats a "contains" code.
        expect(all.mayContain, ['sesame', 'tree_nuts']);
        expect(allergenNames(all.contains, c.allergenCatalog, arabic: false), [
          'Gluten',
          'Milk',
        ]);
        expect(allergenNames(all.mayContain, c.allergenCatalog, arabic: true), [
          'المكسرات', // catalogue order: tree nuts before sesame
          'السمسم',
        ]);
        expect(c.allergensOf(fries).isEmpty, isTrue);
      },
    );

    test('orders, prices, receipts and kitchen tickets do not change', () {
      final c = build();
      c.addCustomizedProduct(
        burger,
        modifiers: const [
          CartItemModifier(
            id: '61',
            group: 'Extras',
            label: 'Extra cheese',
            price: 0.2,
          ),
        ],
      );
      expect(c.cart.single.unitPrice, closeTo(2.2, 1e-9));
      final snapshot = c.snapshot();
      final wire = jsonEncode(buildOrderSyncPayload(snapshot).events);
      expect(wire, isNot(contains('allergen')));
      expect(wire, isNot(contains('may_contain')));
      expect(jsonEncode(snapshot.items), isNot(contains('gluten')));
      final ticket = buildKitchenTicketLines(
        KitchenTicketData(
          orderLabel: 'Order #1',
          orderTypeLabel: 'Quick',
          time: DateTime(2026, 10, 7),
          items: snapshot.items,
        ),
      ).map((l) => l.text).join('\n');
      expect(ticket, isNot(contains('Gluten')));
      expect(ticket, isNot(contains('Contains')));
    });
  });

  group('the till screens', () {
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
        catalog: CatalogSnapshot(
          categories: const ['Menu'],
          products: products,
          floors: const [],
          tables: const [],
          taxes: const [],
          addonGroups: const [cheese, size],
          meals: const [meal],
          allergenCatalog: catalogue,
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      return state.controller as PosController;
    }

    Finder key(String k) => find.byKey(ValueKey(k));
    String text(WidgetTester tester, String k) =>
        tester.widget<Text>(key(k)).data!;

    testWidgets('long-press: the item details show Contains / May contain', (
      tester,
    ) async {
      await pump(tester);
      await tester.longPress(find.text('Beef burger').first);
      await tester.pumpAndSettle();
      expect(text(tester, 'allergens-contains'), 'Contains: Gluten, Milk');
      expect(text(tester, 'allergens-may-contain'), 'May contain: Sesame');
      await tester.tap(key('item-details-close'));
      await tester.pumpAndSettle();
      // An item with none says so (never a silent blank).
      await tester.longPress(find.text('Fries').first);
      await tester.pumpAndSettle();
      expect(
        text(tester, 'allergens-none'),
        'No allergens recorded for this item.',
      );
      await tester.tap(key('item-details-close'));
      await tester.pumpAndSettle();
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('Arabic: the names come from the catalogue', (tester) async {
      await pump(tester, arabic: true);
      await tester.longPress(find.text('برجر لحم').first);
      await tester.pumpAndSettle();
      expect(text(tester, 'allergens-contains'), 'يحتوي على: الغلوتين، الحليب');
      expect(text(tester, 'allergens-may-contain'), 'قد يحتوي على: السمسم');
      await tester.tap(key('item-details-close'));
      await tester.pumpAndSettle();
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('the options sheet shows the item\'s allergens and what each '
        'option adds', (tester) async {
      final controller = await pump(tester);
      controller.addProduct(burger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();
      expect(text(tester, 'allergens-contains'), 'Contains: Gluten, Milk');
      expect(text(tester, 'option-allergens-61'), 'Adds: Milk');
      expect(key('option-allergens-62'), findsNothing);
      await tester.tap(find.text('Extra cheese'));
      await tester.pump();
      await tester.tap(key('customize-confirm'));
      await tester.pumpAndSettle();
      // Display only: the price is the option's price, nothing else.
      expect(controller.cart.single.unitPrice, closeTo(2.2, 1e-9));
      await disposeWorkspaceMachine(tester);
    });

    testWidgets('the combo and meal sheets show the whole and each item', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Family box').first);
      await tester.pumpAndSettle();
      final header = find.descendant(
        of: key('combo-allergens'),
        matching: key('allergens-contains'),
      );
      expect(tester.widget<Text>(header).data, 'Contains: Gluten, Milk');
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: key('combo-allergens'),
                matching: key('allergens-may-contain'),
              ),
            )
            .data,
        'May contain: Tree nuts, Sesame',
      );
      // Each item its own: the shake says milk, the water nothing.
      expect(key('combo-item-allergens-32'), findsOneWidget);
      expect(key('combo-item-allergens-36'), findsNothing);
      await tester.tap(key('combo-cancel'));
      await tester.pumpAndSettle();

      // A meal: the main's allergens together with the meal's.
      await tester.tap(find.text('Beef burger').first);
      await tester.pumpAndSettle();
      await tester.tap(key('meal-offer-yes'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: key('combo-allergens'),
                matching: key('allergens-may-contain'),
              ),
            )
            .data,
        'May contain: Tree nuts, Sesame',
      );
      expect(key('combo-item-allergens-30'), findsOneWidget); // the main
      await tester.tap(key('combo-cancel'));
      await tester.pumpAndSettle();
      await disposeWorkspaceMachine(tester);
    });
  });
}
