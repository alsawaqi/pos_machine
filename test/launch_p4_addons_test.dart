import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P4 C3 — add-ons: H3 anything that is not 'single' is multi-choice
/// (the portal stores 'multi'); H4 a tap on a product with a required group
/// opens the options sheet, and payment is refused while a line misses a
/// required choice.
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
      AddonOption(id: 52, label: 'Large', priceDelta: 0.300),
    ],
  );
  const latte = Product(
    id: '10',
    name: 'Latte',
    category: 'Coffee',
    price: 1.500,
    addonGroupIds: [5],
  );
  const water = Product(id: '11', name: 'Water', category: 'Coffee', price: 0.300);

  group('H3 — multi-choice groups', () {
    test("the portal's 'multi' maps to a multi-choice group", () {
      final groups = ConfigMapper.toCatalog(
        null,
        const [],
        const [],
        const [],
        const [],
        const [],
        const [
          AddonGroupRow(id: 6, name: 'Extras', selectionMode: 'multi', minSelections: 2),
          AddonGroupRow(id: 7, name: 'Milk', selectionMode: 'single'),
          AddonGroupRow(id: 8, name: 'Legacy', selectionMode: 'multiple'),
        ],
        const [
          AddonRow(id: 61, addOnGroupId: 6, name: 'Shot', priceDeltaBaisas: 200, isDefault: false, consumptionJson: '[]'),
          AddonRow(id: 62, addOnGroupId: 6, name: 'Syrup', priceDeltaBaisas: 150, isDefault: false, consumptionJson: '[]'),
          AddonRow(id: 63, addOnGroupId: 6, name: 'Cream', priceDeltaBaisas: 100, isDefault: false, consumptionJson: '[]'),
        ],
      ).addonGroups;
      final extras = groups.firstWhere((g) => g.id == 6);
      expect(extras.multiSelect, isTrue);
      // "choose 2" can now be completed (it was capped at 1 pick before).
      expect(extras.effectiveMax, 3);
      expect(extras.effectiveMin, 2);
      expect(groups.firstWhere((g) => g.id == 7).multiSelect, isFalse);
      expect(groups.firstWhere((g) => g.id == 8).multiSelect, isTrue);
    });
  });

  group('H4 — required choices on the controller', () {
    PosController build() {
      final c = PosController(orderStorage: FakeOrderStorage());
      c.applyCatalog(
        categories: const ['Coffee'],
        products: const [latte, water],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        addonGroups: const [size],
        branchId: 6,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a product with a required group needs the options sheet', () {
      final c = build();
      expect(c.needsOptionsBeforeAdd(latte), isTrue);
      expect(c.needsOptionsBeforeAdd(water), isFalse);
    });

    test('payment is refused while a line misses the required size', () {
      final c = build();
      c.addProduct(latte); // e.g. restored or added before this rule
      c.addProduct(water);
      final missing = c.firstMissingRequiredChoice();
      expect(missing?.item.product.id, '10');
      expect(missing?.group.id, 5);
      final refusal = c.customerTenderRefusal();
      expect(refusal, contains('Latte'));
      expect(refusal, contains('Size'));
    });

    test('a line with its size picked is payable', () {
      final c = build();
      c.addCustomizedProduct(
        latte,
        modifiers: const [
          CartItemModifier(id: '52', group: 'Size', label: 'Large', price: 0.300),
        ],
      );
      expect(c.firstMissingRequiredChoice(), isNull);
      expect(c.menuTenderRefusal(), isNull);
      expect(c.cart.single.unitPrice, closeTo(1.800, 1e-9));
      // The same choice again merges into the line.
      c.addCustomizedProduct(
        latte,
        modifiers: const [
          CartItemModifier(id: '52', group: 'Size', label: 'Large', price: 0.300),
        ],
      );
      expect(c.cart.single.qty, 2);
    });
  });

  group('H4 — tapping the product opens the options sheet', () {
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

    testWidgets('required size: tap opens the sheet, Apply adds the line', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [latte, water],
          floors: [],
          tables: [],
          taxes: [],
          addonGroups: [size],
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final PosController controller = state.controller as PosController;

      await tester.tap(find.text('Latte').first);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_CustomizeCartItemDialog',
        ),
        findsOneWidget,
      );
      expect(controller.cart, isEmpty, reason: 'no plain line on tap');

      await tester.tap(find.byKey(const ValueKey('customize-confirm')));
      await tester.pumpAndSettle();
      expect(controller.cart, hasLength(1));
      expect(controller.cart.single.product.id, '10');
      expect(controller.cart.single.modifiers.single.id, '51'); // default
      expect(controller.firstMissingRequiredChoice(), isNull);

      // A product without a required group still adds on tap.
      await tester.tap(find.text('Water').first);
      await tester.pumpAndSettle();
      expect(controller.cart, hasLength(2));
      await disposeWorkspaceMachine(tester);
    });
  });
}
