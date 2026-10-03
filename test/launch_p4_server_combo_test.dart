import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_copy.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/display_strings.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/transfer_claim.dart';

/// LAUNCH-P4 C7 follow-up (Part A shapes at api 73be87b):
///  (a) the till's server-priced quick-QR / staff-round picker builds combos
///      as `combo: [{slot_id, product_id, qty, addon_ids}]` — no prices;
///  (b) every server-bill reader shows the nested `combo` items and keeps
///      them through edits (more of the same, options changed) and payment;
///  (c) the customer display shows one row per tax;
///  kitchen components are per ONE combo and print × the combo quantity.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    category: 'Food',
    price: 3.5,
    productType: 'combo',
    comboSlots: [
      ComboSlot(
        id: 6,
        name: 'Main',
        options: [
          ComboOption(productId: 30, isDefault: true),
          ComboOption(productId: 33, extraPrice: 0.3, sortOrder: 1),
        ],
      ),
      ComboSlot(
        id: 8,
        name: 'Drink',
        sortOrder: 1,
        options: [ComboOption(productId: 32, isDefault: true)],
      ),
    ],
  );
  const catalog = CatalogSnapshot(
    categories: ['Food', 'Drinks'],
    products: [
      meal,
      Product(id: '30', name: 'Burger', category: 'Food', price: 2.5),
      Product(id: '33', name: 'Chicken burger', category: 'Food', price: 2.7),
      cola,
    ],
    floors: [],
    tables: [],
    taxes: [],
    addonGroups: [
      AddonGroup(
        id: 5,
        name: 'Size',
        multiSelect: false,
        minSelections: 1,
        maxSelections: 1,
        options: [
          AddonOption(id: 51, label: 'Regular', priceDelta: 0, isDefault: true),
          AddonOption(id: 52, label: 'Large', priceDelta: 0.2),
        ],
      ),
    ],
  );

  /// A combo line as Part A's DeviceOrderItems::present nests it.
  Map<String, dynamic> serverComboLine({int qty = 2}) => {
    'id': 900,
    'product_id': 20,
    'product_name': 'Burger meal',
    'qty': qty,
    'unit_price_baisas': 4000,
    'line_discount_baisas': 0,
    'line_total_baisas': 4000 * qty,
    'status': 'open',
    'notes': null,
    'addons': <Map<String, dynamic>>[],
    'combo': [
      {
        'id': 901,
        'slot_id': 6,
        'product_id': 33,
        'product_name': 'Chicken burger',
        'qty': 1.0,
        'extra_price_baisas': 300,
        'notes': null,
        'addons': <Map<String, dynamic>>[],
      },
      {
        'id': 902,
        'slot_id': 8,
        'product_id': 32,
        'product_name': 'Cola',
        'qty': 1.0,
        'extra_price_baisas': 0,
        'notes': 'no ice',
        'addons': [
          {'add_on_id': 52, 'add_on_name': 'Large', 'price_delta_baisas': 200},
        ],
      },
    ],
  };

  group('(a) the server-priced picker', () {
    test('a combo pick is identity only: slot, product, qty, add-on ids', () {
      final line = QrQuickLine(
        20,
        2,
        const [],
        combo: [
          QrQuickComboPick(6, 33),
          QrQuickComboPick(8, 32, addons: const [52], notes: 'no ice'),
        ],
      );
      expect(line.toJson(), {
        'product_id': 20,
        'qty': 2,
        'addon_ids': <int>[],
        'notes': null,
        'combo': [
          {'slot_id': 6, 'product_id': 33, 'qty': 1, 'addon_ids': <int>[]},
          {
            'slot_id': 8,
            'product_id': 32,
            'qty': 1,
            'addon_ids': [52],
            'notes': 'no ice',
          },
        ],
      });
      expect(line.toJson().toString(), isNot(contains('price')));
      // Persisted drafts / uncertain journals round-trip.
      final back = QrQuickLine.fromJson(line.toJson());
      expect(back.comboSignature, line.comboSignature);
      // A client price inside a choice is refused, never sent.
      expect(
        () => QrQuickLine.fromJson({
          ...line.toJson(),
          'combo': [
            {'slot_id': 6, 'product_id': 33, 'qty': 1, 'extra_price_baisas': 300},
          ],
        }),
        throwsFormatException,
      );
    });

    test('the till catalogue offers combos with their slots', () {
      final quick = machineQuickCatalogue(catalog);
      final combo = quick.firstWhere((p) => p.id == 20);
      expect(combo.available, isTrue);
      expect(combo.isCombo, isTrue);
      expect(combo.comboSlots.map((s) => s.id), [6, 8]);
      expect(combo.comboSlots.first.options.last.extraPriceBaisas, 300);
      expect(combo.comboSlots.first.options.first.isDefault, isTrue);
    });

    testWidgets('the combo picker returns the choices (defaults, a swap)', (
      tester,
    ) async {
      final quick = machineQuickCatalogue(catalog);
      final combo = quick.firstWhere((p) => p.id == 20);
      QrQuickLine? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<QrQuickLine>(
                  context: context,
                  builder: (_) => quickOptionsDialog(
                    combo,
                    const QuickCopy(false),
                    catalogue: quick,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('quick-combo-options')), findsOneWidget);
      expect(find.text('3.500'), findsOneWidget); // defaults, no extra
      await tester.tap(find.byKey(const ValueKey('quick-combo-option-6-33')));
      await tester.pumpAndSettle();
      expect(find.text('3.800'), findsOneWidget); // + chicken 0.300
      await tester.tap(find.byKey(const ValueKey('quick-combo-add')));
      await tester.pumpAndSettle();
      expect(result?.productId, 20);
      expect(result!.combo.map((c) => [c.slotId, c.productId]), [
        [6, 33],
        [8, 32],
      ]);
      // The drink's required size was pre-filled with its default.
      expect(result!.combo.last.addonIds, [51]);
      expect(result!.toJson().toString(), isNot(contains('price')));
    });

    test('draft rows estimate the combo and show its items', () {
      final quick = machineQuickCatalogue(catalog);
      final combo = quick.firstWhere((p) => p.id == 20);
      final rows = quickComboRows(
        QrQuickLine(
          20,
          1,
          const [],
          combo: [
            QrQuickComboPick(6, 33),
            QrQuickComboPick(8, 32, addons: const [52]),
          ],
        ),
        combo,
        (id) => quick.where((p) => p.id == id).firstOrNull,
      );
      expect(rows.map((r) => r['unit_delta_baisas']), [300, 200]);
      expect(rows.last['addons'], [
        {
          'add_on_id': 52,
          'add_on_name': 'Large',
          'add_on_name_ar': '',
          'price_delta_baisas': 200,
        },
      ]);
    });
  });

  group('(b) server-bill readers', () {
    test('edits send the same choices back (more of the same)', () {
      final picks = serverComboPicks(serverComboLine());
      expect(picks.map((p) => p.toJson()), [
        {'slot_id': 6, 'product_id': 33, 'qty': 1, 'addon_ids': <int>[]},
        {
          'slot_id': 8,
          'product_id': 32,
          'qty': 1,
          'addon_ids': [52],
          'notes': 'no ice',
        },
      ]);
    });

    test('labels read bills (combo) and frozen rounds (components)', () {
      expect(serverComboLabels(serverComboLine(), arabic: false), [
        '> Chicken burger (+0.300)',
        '> Cola',
        '   + Large',
        '   no ice',
      ]);
      final round = {
        'components': [
          {
            'slot_id': 8,
            'product_id': 32,
            'name': 'Cola',
            'name_ar': 'كولا',
            'qty': 2,
            'extra_price_baisas': 0,
            'addons': [
              {'add_on_id': 52, 'name': 'Large', 'name_ar': 'كبير'},
            ],
          },
        ],
      };
      expect(serverComboLabels(round, arabic: true), ['> 2 x كولا', '   + كبير']);
    });

    test('active, pending and quick bills show the items on the line', () {
      final bill = WorkspaceBill({
        'uuid': 'bill-1',
        'grand_total_baisas': 8000,
        'items': [serverComboLine()],
      });
      final item = bill.cartItems.single;
      expect(item.lineTotal, 8.0); // the server's frozen total
      expect(item.isCombo, isTrue);
      expect(item.detailLinesFor(false), contains('> Chicken burger (+0.300)'));
      expect(item.detailLinesFor(false), contains('   + Large'));
      final shown = bill.display(stale: false)['items'] as List;
      expect((shown.single as Map)['addons'], contains('> Cola'));
      expect(
        (bill.cartDisplay(stale: false)['items'] as List).single['detailLines'],
        contains('> Cola'),
      );
      // Different choices never group into one row.
      final other = serverComboLine()
        ..['id'] = 950
        ..['combo'] = [
          {
            'slot_id': 6,
            'product_id': 30,
            'product_name': 'Burger',
            'qty': 1.0,
            'extra_price_baisas': 0,
            'addons': <Map<String, dynamic>>[],
          },
          (serverComboLine()['combo'] as List)[1],
        ];
      final two = WorkspaceBill({
        'uuid': 'bill-2',
        'grand_total_baisas': 16000,
        'items': [serverComboLine(), other],
      });
      expect(two.groupedItems, hasLength(2));
      final same = WorkspaceBill({
        'uuid': 'bill-3',
        'grand_total_baisas': 16000,
        'items': [serverComboLine(), serverComboLine()..['id'] = 951],
      });
      expect(same.groupedItems, hasLength(1));
    });

    test('active / pending order items parse the nested combo', () {
      final item = QrOrderItem.fromJson(serverComboLine());
      expect(item.combo, hasLength(2));
      expect(serverComboLabels({'combo': item.combo}, arabic: false).first,
          '> Chicken burger (+0.300)');
    });

    test('a transfer claim keeps the combo through to payment', () {
      final items = transferClaimCartItems(
        {
          'uuid': 'u-1',
          'items': [serverComboLine()],
        },
        productForId: (id) =>
            catalog.products.where((p) => p.id == id).firstOrNull,
      );
      final line = items.single;
      expect(line.product.isCombo, isTrue);
      expect(line.product.price, closeTo(3.5, 1e-9)); // 4.000 - 0.300 - 0.200
      expect(line.components.map((c) => c.productId), ['33', '32']);
      expect(line.unitPrice, closeTo(4.0, 1e-9));
      final snapshot = OrderSnapshot.initial().copyWith(
        items: [line.toMap()],
        rawSubtotal: line.lineTotal,
        subtotal: line.lineTotal,
        total: line.lineTotal,
      );
      final order =
          (buildOrderSyncPayload(snapshot).events.first['payload'] as Map)['order']
              as Map;
      final wire = (order['lines'] as List).single as Map;
      expect(wire['unit_price_baisas'], 4000);
      expect(wire['combo'], [
        {'slot_id': 6, 'product_id': 33, 'qty': 1, 'extra_price_baisas': 300},
        {
          'slot_id': 8,
          'product_id': 32,
          'qty': 1,
          'extra_price_baisas': 0,
          'notes': 'no ice',
          'addons': [
            {'add_on_id': 52, 'price_delta_baisas': 200},
          ],
        },
      ]);
    });
  });

  test('kitchen: frozen components are per ONE combo, printed x combo qty', () {
    final line = QrRoundDisplayLine.fromJson({
      'product_name': 'Burger meal',
      'qty': 3,
      'cancelled_qty': 1,
      'unit_price_baisas': 4000,
      'line_discount_baisas': 0,
      'line_total_baisas': 12000,
      'components': [
        {
          'slot_id': 8,
          'product_id': 32,
          'name': 'Cola',
          'product_name': 'Cola',
          'qty': 1,
          'extra_price_baisas': 0,
          'addons': [
            {'add_on_id': 52, 'name': 'Large', 'price_delta_baisas': 200},
          ],
        },
      ],
    });
    final text = buildKitchenTicketLines(
      KitchenTicketData(
        orderLabel: 'QR',
        orderTypeLabel: 'QR',
        time: DateTime(2026, 10, 3),
        items: [line.toKitchenItem(arabic: false)],
      ),
    ).map((l) => l.text).toList();
    expect(text, contains('2 x Burger meal')); // 3 ordered - 1 cancelled
    expect(text, contains('  > 2 x Cola'));
    expect(text, contains('      + Large'));
  });

  group('(c) customer display taxes', () {
    test('one row per tax with its rate, Arabic names in Arabic', () {
      final order = OrderSnapshot.initial().copyWith(
        tax: 0.18,
        taxLines: const [
          {
            'name': 'VAT',
            'nameAr': 'ضريبة القيمة المضافة',
            'ratePercent': 5.0,
            'amount': 0.1,
          },
          {'name': 'Tourism', 'ratePercent': 4.0, 'amount': 0.08},
        ],
      );
      final en = customerTaxRows(order, arabic: false, fallbackLabel: 'Tax');
      expect(en.map((r) => r.label), ['VAT (5%)', 'Tourism (4%)']);
      expect(en.map((r) => r.amount), [0.1, 0.08]);
      final ar = customerTaxRows(order, arabic: true, fallbackLabel: 'الضريبة');
      expect(ar.first.label, 'ضريبة القيمة المضافة (5%)');
    });

    test('a bill without tax lines keeps one Tax row', () {
      final rows = customerTaxRows(
        OrderSnapshot.initial().copyWith(tax: 0.05),
        arabic: false,
        fallbackLabel: 'Tax',
      );
      expect(rows.single.label, 'Tax');
      expect(rows.single.amount, 0.05);
    });
  });
}
