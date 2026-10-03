import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P4 C7 — combos on the till: a set price plus choice slots, extra
/// prices, each chosen item's own add-ons, the cart line's components, the
/// device wire (order.create / hold / transfer / table rounds), kitchen
/// tickets, and the delivery-provider refusal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = AddonGroup(
    id: 5,
    name: 'Size',
    multiSelect: false,
    minSelections: 1,
    maxSelections: 1,
    options: [
      AddonOption(id: 51, label: 'Regular', priceDelta: 0, isDefault: true),
      AddonOption(id: 52, label: 'Large', priceDelta: 0.200),
    ],
  );
  const burger = Product(id: '30', name: 'Burger', category: 'Food', price: 2.5);
  const chicken = Product(id: '33', name: 'Chicken burger', category: 'Food', price: 2.7);
  const fries = Product(id: '31', name: 'Fries', category: 'Food', price: 0.8);
  const cola = Product(
    id: '32',
    name: 'Cola',
    category: 'Drinks',
    price: 0.5,
    addonGroupIds: [5],
  );
  const meal = Product(
    id: '20',
    name: 'Burger meal',
    nameAr: 'وجبة برجر',
    category: 'Food',
    price: 3.500,
    productType: 'combo',
    deliveryPrice: 4.000,
    deliveryUnlistedProviderIds: {8},
    comboSlots: [
      ComboSlot(
        id: 6,
        name: 'Main',
        options: [
          ComboOption(productId: 30, isDefault: true),
          ComboOption(productId: 33, extraPrice: 0.300, sortOrder: 1),
        ],
      ),
      ComboSlot(
        id: 7,
        name: 'Side',
        sortOrder: 1,
        options: [ComboOption(productId: 31, isDefault: true)],
      ),
      ComboSlot(
        id: 8,
        name: 'Drink',
        sortOrder: 2,
        options: [ComboOption(productId: 32, isDefault: true)],
      ),
    ],
  );

  const largeCola = ComboComponent(
    slotId: 8,
    productId: '32',
    name: 'Cola',
    modifiers: [
      CartItemModifier(id: '52', group: 'Size', label: 'Large', price: 0.200),
    ],
  );
  const chickenMain = ComboComponent(
    slotId: 6,
    productId: '33',
    name: 'Chicken burger',
    extraPrice: 0.300,
  );
  const friesSide = ComboComponent(slotId: 7, productId: '31', name: 'Fries');
  const choices = [chickenMain, friesSide, largeCola];

  PosController build() {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Food', 'Drinks'],
      products: const [meal, burger, chicken, fries, cola],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      addonGroups: const [size],
      deliveryProviders: const [
        DeliveryProvider(id: 7, name: 'Talabat'),
        DeliveryProvider(id: 8, name: 'Otlob'),
      ],
      branchId: 6,
    );
    addTearDown(c.dispose);
    return c;
  }

  group('the cart line', () {
    test('unit price = combo price + qty x (extra + add-ons)', () {
      final line = CartItem(product: meal, qty: 2, components: choices);
      expect(line.componentTotal, closeTo(0.500, 1e-9));
      expect(line.unitPrice, closeTo(4.000, 1e-9));
      expect(line.lineTotal, closeTo(8.000, 1e-9));
    });

    test('components survive storage, re-price and merge rules', () {
      final line = CartItem(product: meal, components: choices);
      final back = CartItem.fromMap(line.toMap());
      expect(back.product.isCombo, isTrue);
      expect(back.components.map((c) => c.productId), ['33', '31', '32']);
      expect(back.components.last.modifiers.single.id, '52');
      expect(back.unitPrice, closeTo(line.unitPrice, 1e-9));
      final repriced = line.withProduct(meal.copyWith(price: 4.0));
      expect(repriced.components, hasLength(3));
      expect(
        CartItem(product: meal, components: const [friesSide]).mergeSignature,
        isNot(line.mergeSignature),
      );
      expect(
        line.detailLinesFor(false),
        containsAll(['• Chicken burger (+0.300 OMR)', '   + Large (+0.200 OMR)']),
      );
    });
  });

  group('the controller', () {
    test('a valid combo is added; quantity and edits work', () {
      final c = build();
      expect(c.addCombo(meal, choices), isTrue);
      expect(c.cart.single.components, hasLength(3));
      expect(c.subtotal, closeTo(4.000, 1e-9));
      c.incrementCartItem(c.cart.single);
      expect(c.subtotal, closeTo(8.000, 1e-9));
      expect(
        c.updateComboComponents(c.cart.single, const [
          ComboComponent(slotId: 6, productId: '30', name: 'Burger'),
          friesSide,
          ComboComponent(
            slotId: 8,
            productId: '32',
            name: 'Cola',
            modifiers: [
              CartItemModifier(id: '51', group: 'Size', label: 'Regular', price: 0),
            ],
          ),
        ]),
        isTrue,
      );
      expect(c.subtotal, closeTo(7.000, 1e-9));
    });

    test('invalid choices are refused', () {
      final c = build();
      // Missing the drink slot.
      expect(c.addCombo(meal, const [chickenMain, friesSide]), isFalse);
      // An option that is not in the slot.
      expect(
        c.addCombo(meal, const [
          ComboComponent(slotId: 6, productId: '31', name: 'Fries'),
          friesSide,
          largeCola,
        ]),
        isFalse,
      );
      // A wrong extra price.
      expect(
        c.addCombo(meal, const [
          ComboComponent(slotId: 6, productId: '33', name: 'Chicken burger'),
          friesSide,
          largeCola,
        ]),
        isFalse,
      );
      // The drink's required size missing.
      expect(
        c.addCombo(meal, const [
          chickenMain,
          friesSide,
          ComboComponent(slotId: 8, productId: '32', name: 'Cola'),
        ]),
        isFalse,
      );
      expect(c.cart, isEmpty);
    });

    test('refused on a delivery app that does not list the combo', () async {
      final c = build();
      await c.selectOrderType(OrderType.delivery);
      c.selectDeliveryProvider(8);
      expect(c.addCombo(meal, choices), isFalse);
      c.selectDeliveryProvider(7);
      expect(c.addCombo(meal, choices), isTrue);
      expect(c.cart.single.unitPrice, closeTo(4.500, 1e-9)); // 4.000 + 0.500
      c.selectDeliveryProvider(8);
      expect(c.customerTenderRefusal(), contains('Burger meal'));
    });

    test('a combo restored without its choices cannot be paid', () {
      final c = build();
      c.receiveTransferredOrder(
        orderUuid: 'u-9',
        orderType: OrderType.quickOrder,
        items: [CartItem(product: meal)],
      );
      expect(c.menuTenderRefusal(), contains('Burger meal'));
    });
  });

  group('the wire', () {
    test('order.create carries the combo per ONE combo', () {
      final c = build();
      c.addCombo(meal, choices);
      c.incrementCartItem(c.cart.single);
      final event = buildOrderSyncPayload(c.snapshot()).events.first;
      final line = ((event['payload'] as Map)['order'] as Map)['lines'][0] as Map;
      expect(line['product_id'], 20);
      expect(line['qty'], 2);
      expect(line['unit_price_baisas'], 4000);
      expect(line['line_total_baisas'], 8000);
      expect(line['combo'], [
        {'slot_id': 6, 'product_id': 33, 'qty': 1, 'extra_price_baisas': 300},
        {'slot_id': 7, 'product_id': 31, 'qty': 1, 'extra_price_baisas': 0},
        {
          'slot_id': 8,
          'product_id': 32,
          'qty': 1,
          'extra_price_baisas': 0,
          'addons': [
            {'add_on_id': 52, 'price_delta_baisas': 200},
          ],
        },
      ]);
    });

    test('order.hold / order.transfer keep the components', () {
      final draft = OrderSessionDraft(
        orderReference: 'REF-1',
        orderType: OrderType.quickOrder,
        selectedCategory: 'Food',
        customerReferenceNumber: '',
        items: [CartItem(product: meal, components: choices)],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      );
      final hold = buildOrderHoldEvent(draft, orderUuid: 'u-1')!;
      final line = ((hold['payload'] as Map)['order'] as Map)['lines'][0] as Map;
      expect((line['combo'] as List), hasLength(3));
      expect(line['unit_price_baisas'], 4000);
      final transfer = buildOrderTransferEvent(
        draft,
        orderUuid: 'u-1',
        targetDeviceId: 4,
      )!;
      final tLine =
          ((transfer['payload'] as Map)['order'] as Map)['lines'][0] as Map;
      expect(tLine['combo'], line['combo']);
    });

    test('table rounds carry the combo; choices change the fingerprint', () {
      final round = buildTableRoundLines([
        CartItem(product: meal, components: choices),
      ]).single;
      expect((round['combo'] as List).first['product_id'], 33);
      final other = buildTableRoundLines([
        CartItem(product: meal, components: const [
          ComboComponent(slotId: 6, productId: '30', name: 'Burger'),
          friesSide,
          largeCola,
        ]),
      ]).single;
      expect(tableLineFingerprint(round), isNot(tableLineFingerprint(other)));
      expect(
        tableLineFingerprint(round),
        tableLineFingerprint(
          buildTableRoundLines([
            CartItem(product: meal, components: choices),
          ]).single,
        ),
      );
      // A standard line's fingerprint is unchanged by P4.
      expect(
        tableLineFingerprint({'product_id': 31, 'qty': 1}),
        '[31,[],""]',
      );
    });
  });

  test('kitchen tickets print each chosen item with its add-ons', () {
    final item = CartItem(product: meal, qty: 2, components: choices).toMap();
    final lines = buildKitchenTicketLines(
      KitchenTicketData(
        orderLabel: 'Order #1',
        orderTypeLabel: 'Quick Order',
        time: DateTime(2026, 10, 3, 12),
        items: [item],
      ),
    ).map((l) => l.text).toList();
    expect(lines, contains('2 x Burger meal'));
    expect(lines, contains('  > 2 x Chicken burger'));
    expect(lines, contains('  > 2 x Fries'));
    expect(lines, contains('  > 2 x Cola'));
    expect(lines, contains('      + Size: Large'));
    expect(lines.join('\n'), isNot(contains('OMR')));
  });

  test('QR kitchen lines print server combo components', () {
    final line = QrRoundDisplayLine.fromJson({
      'product_name': 'Burger meal',
      'qty': 1,
      'unit_price_baisas': 4000,
      'line_discount_baisas': 0,
      'line_total_baisas': 4000,
      'components': [
        {
          'product_name': 'Cola',
          'qty': 1,
          'addons': [
            {'name': 'Large'},
          ],
        },
      ],
    });
    final item = line.toKitchenItem(arabic: false);
    final text = buildKitchenTicketLines(
      KitchenTicketData(
        orderLabel: 'QR',
        orderTypeLabel: 'QR',
        time: DateTime(2026, 10, 3),
        items: [item],
      ),
    ).map((l) => l.text);
    expect(text, contains('  > 1 x Cola'));
    expect(text, contains('      + Large'));
  });

  group('the combo sheet', () {
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

    testWidgets('tap opens the sheet with defaults; a pick changes the price', (
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
          categories: ['Food', 'Drinks'],
          products: [meal, burger, chicken, fries, cola],
          floors: [],
          tables: [],
          taxes: [],
          addonGroups: [size],
        ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final PosController controller = state.controller as PosController;
      await tester.tap(find.text('Burger meal').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('combo-builder')), findsOneWidget);
      expect(find.textContaining('3.500'), findsWidgets); // defaults: no extra
      await tester.tap(find.byKey(const ValueKey('combo-option-6-33')));
      await tester.pumpAndSettle();
      expect(find.textContaining('3.800'), findsWidgets); // + chicken 0.300
      await tester.tap(find.byKey(const ValueKey('combo-confirm')));
      await tester.pumpAndSettle();
      final line = controller.cart.single;
      expect(line.product.id, '20');
      expect(line.components.map((c) => c.productId), ['33', '31', '32']);
      // The drink's required size was pre-filled with its default.
      expect(line.components.last.modifiers.single.id, '51');
      expect(controller.menuTenderRefusal(), isNull);
      expect(line.unitPrice, closeTo(3.800, 1e-9));
      await disposeWorkspaceMachine(tester);
    });
  });
}
