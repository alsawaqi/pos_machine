import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as pricing;
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH costs & allergens add-on, Part D (till) follow-ups:
///  1. K-6 (pos_api 7157bb3) — an add-on option's `may_contain` (from a
///     linked product) is cached and shown on the option ("May contain: …");
///  2. the server-priced pickers (quick QR, staff table rounds, tablet
///     edits) show the same Contains / May contain as the till's own
///     sheets: the item list, the options sheet, each option, the combo /
///     meal sheet (a meal: the main's plus the meal's) and an item inside it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final catalogue = AllergenInfo.listFromJson([
    for (final e in const {
      'gluten': ['Gluten', 'الغلوتين'],
      'eggs': ['Eggs', 'البيض'],
      'milk': ['Milk', 'الحليب'],
      'tree_nuts': ['Tree nuts', 'المكسرات'],
      'sesame': ['Sesame', 'السمسم'],
    }.entries)
      {'code': e.key, 'name': e.value[0], 'name_ar': e.value[1]},
  ]);

  const extras = AddonGroup(
    id: 6,
    name: 'Extras',
    multiSelect: true,
    options: [
      AddonOption(
        id: 61,
        label: 'Brownie bite',
        priceDelta: 0.3,
        allergens: ['gluten', 'eggs'],
        mayContain: ['tree_nuts'],
      ),
      AddonOption(id: 62, label: 'No onion', priceDelta: 0),
    ],
  );
  const burger = Product(
    id: '30',
    name: 'Beef burger',
    category: 'Menu',
    price: 2.0,
    addonGroupIds: [6],
    allergens: ['gluten', 'milk'],
    mayContain: ['sesame'],
  );
  const shake = Product(
    id: '32',
    name: 'Milkshake',
    category: 'Menu',
    price: 1.0,
    allergens: ['milk'],
  );
  const water = Product(id: '36', name: 'Water', category: 'Menu', price: 0.3);
  const box = Product(
    id: '40',
    name: 'Family box',
    category: 'Menu',
    price: 5.0,
    productType: 'combo',
    allergens: ['gluten', 'milk'],
    mayContain: ['sesame'],
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
    allergens: ['milk', 'eggs'],
    mayContain: ['tree_nuts'],
    lines: [
      pricing.ComboLineDef.choice(
        id: 52,
        name: 'Drink',
        items: [
          pricing.ComboChoiceItemDef(productId: 32),
          pricing.ComboChoiceItemDef(productId: 36),
        ],
      ),
    ],
  );
  const products = [box, burger, shake, water];
  final snapshot = CatalogSnapshot(
    categories: const ['Menu'],
    products: products,
    floors: const [],
    tables: const [],
    taxes: const [],
    addonGroups: const [extras],
    meals: const [meal],
    allergenCatalog: catalogue,
  );

  group('1. K-6 — an option\'s "may contain"', () {
    test('parsed, cached and mapped back', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'addon_groups': [
          {
            'id': 6,
            'name': 'Extras',
            'addons': [
              {
                'id': 61,
                'name': 'Brownie bite',
                'price_delta_baisas': 300,
                'allergens': ['gluten', 'eggs'],
                'may_contain': ['tree_nuts'],
              },
              {'id': 62, 'name': 'No onion'},
            ],
          },
        ],
      });
      expect(parsed.addons.first.mayContainJson.value, '["tree_nuts"]');
      // An older server sends none: null, not "none".
      expect(parsed.addons.last.mayContainJson.value, isNull);
      final options = ConfigMapper.toCatalog(
        null,
        const [],
        const [],
        const [],
        const [],
        const [],
        [const AddonGroupRow(id: 6, name: 'Extras')],
        [
          AddonRow(
            id: 61,
            addOnGroupId: 6,
            name: 'Brownie bite',
            priceDeltaBaisas: 300,
            isDefault: false,
            consumptionJson: '[]',
            allergensJson: '["gluten","eggs"]',
            mayContainJson: parsed.addons.first.mayContainJson.value,
          ),
        ],
      ).addonGroups.single.options;
      expect(options.single.mayContain, ['tree_nuts']);
    });

    test(
      'Drift 32 to 33 keeps cached options and adds may_contain_json',
      () async {
        final db = AppDatabase.forTesting(
          NativeDatabase.memory(
            setup: (raw) {
              raw.execute('''
              CREATE TABLE addons (
                id INTEGER PRIMARY KEY, add_on_group_id INTEGER NOT NULL,
                name TEXT NOT NULL DEFAULT '', name_ar TEXT,
                price_delta_baisas INTEGER NOT NULL DEFAULT 0,
                is_default INTEGER NOT NULL DEFAULT 0, ingredient_id INTEGER,
                linked_product_id INTEGER,
                consumption_json TEXT NOT NULL DEFAULT '[]', status TEXT,
                allergens_json TEXT
              )
            ''');
              raw.execute(
                "INSERT INTO addons (id, add_on_group_id, name, allergens_json) "
                "VALUES (61, 6, 'Brownie bite', '[\"gluten\"]')",
              );
              raw.execute('PRAGMA user_version = 32');
            },
          ),
        );
        addTearDown(db.close);
        expect(db.schemaVersion, 33);
        final row = (await db.select(db.addons).get()).single;
        expect(row.name, 'Brownie bite');
        expect(row.allergensJson, '["gluten"]');
        expect(row.mayContainJson, isNull);
      },
    );
  });

  group('the till options sheet', () {
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

    testWidgets('an option shows what it adds and what it may contain', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: snapshot,
      );
      final dynamic screen = tester.state(find.byType(StaffPosScreen));
      (screen.controller as PosController).addProduct(burger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add On').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('option-allergens-61')))
            .data,
        'Adds: Gluten, Eggs',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('option-may-contain-61')))
            .data,
        'May contain: Tree nuts',
      );
      expect(find.byKey(const ValueKey('option-may-contain-62')), findsNothing);
      await disposeWorkspaceMachine(tester);
    });
  });

  group('2. the server-priced pickers', () {
    final quick = machineQuickCatalogue(snapshot);
    QuickProduct quickOf(int id) => quick.firstWhere((p) => p.id == id);

    test('the quick catalogue carries the allergens and their names', () {
      final main = quickOf(30);
      expect(main.allergens.contains, ['gluten', 'milk']);
      expect(main.allergens.mayContain, ['sesame']);
      expect(main.allergenCatalog, hasLength(5));
      final option = main.groups.single.choices.first;
      expect(option.allergens.contains, ['gluten', 'eggs']);
      expect(option.allergens.mayContain, ['tree_nuts']);
      expect(main.meal?.allergens.contains, ['milk', 'eggs']);
      expect(quickOf(36).allergens.isEmpty, isTrue);
    });

    Future<void> open(
      WidgetTester tester,
      Future<void> Function(BuildContext context) action,
    ) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => action(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    String text(WidgetTester tester, Finder f) => tester.widget<Text>(f).data!;
    Finder inside(String parent, String child) => find.descendant(
      of: find.byKey(ValueKey(parent)),
      matching: find.byKey(ValueKey(child)),
    );

    testWidgets('the item list (table rounds, tablet edits)', (tester) async {
      await open(
        tester,
        (context) => pickStaffRoundItem(context, quick, arabic: false),
      );
      expect(
        text(
          tester,
          inside('quick-product-allergens-30', 'allergens-contains'),
        ),
        'Contains: Gluten, Milk',
      );
      expect(
        find.byKey(const ValueKey('quick-product-allergens-36')),
        findsNothing,
      );
    });

    testWidgets('the options sheet and each option (quick QR)', (tester) async {
      await open(
        tester,
        (context) => pickStaffRoundProduct(
          context,
          quickOf(30),
          arabic: false,
          catalogue: quick,
          initial: const {
            'product_id': 30,
            'qty': 1,
            'addons': <Map<String, dynamic>>[],
          },
        ),
      );
      expect(
        text(tester, inside('quick-product-allergens', 'allergens-contains')),
        'Contains: Gluten, Milk',
      );
      expect(
        text(
          tester,
          inside('quick-product-allergens', 'allergens-may-contain'),
        ),
        'May contain: Sesame',
      );
      expect(
        text(tester, find.byKey(const ValueKey('quick-choice-adds-61'))),
        'Adds: Gluten, Eggs',
      );
      expect(
        text(tester, find.byKey(const ValueKey('quick-choice-may-contain-61'))),
        'May contain: Tree nuts',
      );
      expect(find.byKey(const ValueKey('quick-choice-adds-62')), findsNothing);
    });

    testWidgets('the combo sheet: the whole and each item', (tester) async {
      await open(
        tester,
        (context) => pickStaffRoundProduct(
          context,
          quickOf(40),
          arabic: false,
          catalogue: quick,
        ),
      );
      expect(
        text(tester, inside('combo-allergens', 'allergens-contains')),
        'Contains: Gluten, Milk',
      );
      expect(
        find.byKey(const ValueKey('combo-item-allergens-32')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('combo-item-allergens-36')),
        findsNothing,
      );
      // An item's own options sheet inside the combo.
      await tester.tap(find.byKey(const ValueKey('combo-options-1-30')));
      await tester.pumpAndSettle();
      expect(
        text(tester, inside('quick-item-allergens', 'allergens-contains')),
        'Contains: Gluten, Milk',
      );
      expect(
        text(
          tester,
          find.byKey(const ValueKey('quick-item-choice-may-contain-61')),
        ),
        'May contain: Tree nuts',
      );
    });

    testWidgets('a meal: the main\'s allergens with the meal\'s', (
      tester,
    ) async {
      await open(
        tester,
        (context) => pickStaffRoundProduct(
          context,
          quickOf(30),
          arabic: false,
          catalogue: quick,
          initial: const {
            'product_id': 30,
            'meal_id': 5,
            'qty': 1,
            'addons': <Map<String, dynamic>>[],
          },
        ),
      );
      expect(
        text(tester, inside('combo-allergens', 'allergens-contains')),
        'Contains: Gluten, Eggs, Milk',
      );
      expect(
        text(tester, inside('combo-allergens', 'allergens-may-contain')),
        'May contain: Tree nuts, Sesame',
      );
    });
  });
}
