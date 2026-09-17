import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'qr_quick_controller_test.dart';
import 'qr_quick_evidence.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

class CartParityGateway extends FakeQuickGateway
    implements QrQuickWorkspaceGateway {
  CartParityGateway() {
    orders = [
      QrQuickOrder({
        ...quickJson(),
        'items': [],
        'grand_total_baisas': 0,
        'edit_revision': '1',
      }),
    ];
  }
  final changes = <QrQuickRequest>[];
  final results = <String, Map<String, dynamic>>{};
  int nextId = 1;
  Map<String, dynamic> row(QrQuickLine line) => {
    'id': nextId++,
    'product_id': line.productId,
    'product_name': line.productId == 7 ? 'Water' : 'Coffee',
    'qty': line.quantity,
    'notes': line.notes,
    'status': 'active',
    'line_total_baisas': (line.productId == 7 ? 1000 : 2000) * line.quantity,
    'addons': [
      for (final id in line.addonIds)
        {
          'add_on_id': id,
          'add_on_name': id == 10 ? 'Small' : 'Large',
          'price_delta_baisas': 0,
        },
    ],
  };
  void update(List<Map<String, dynamic>> rows) {
    final total = rows.fold<int>(
      0,
      (sum, r) => sum + (r['line_total_baisas'] as int),
    );
    orders = [
      QrQuickOrder({
        ...quickJson(total: total),
        'items': rows,
        'edit_revision': '$nextId-${changes.length}',
      }),
    ];
  }

  @override
  Future<Map<String, dynamic>> append(QrQuickRequest request) async {
    requests.add(request);
    if (results.containsKey(request.id)) {
      return {...results[request.id]!, 'replayed': true};
    }
    final added = request.lines.map(row).toList();
    update([...orders.single.items, ...added]);
    final response = {
      'order': orders.single.json,
      'replayed': false,
      'addition': {
        'id': nextId,
        'round_no': nextId,
        'subtotal_baisas': 0,
        'tax_baisas': 0,
        'total_baisas': 0,
        'priced_lines': [
          for (var i = 0; i < request.lines.length; i++)
            {...request.lines[i].toJson(), 'order_item_id': added[i]['id']},
        ],
      },
    };
    results[request.id] = response;
    return response;
  }

  @override
  Future<Map<String, dynamic>> change(QrQuickRequest request) async {
    changes.add(request);
    if (results.containsKey(request.id)) {
      return {...results[request.id]!, 'replayed': true};
    }
    final op = request.change!;
    final ids = op['item_ids'] as List? ?? [op['item_id']];
    var remaining = op['operation'] == 'quantity' ? op['qty'] as int : 0;
    final rows = orders.single.items
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    for (final r in rows) {
      if (!ids.contains(r['id']) && op['operation'] != 'clear') continue;
      final old = (r['qty'] as num).toInt();
      final keep = remaining.clamp(0, old);
      remaining -= keep;
      if (old > 0) {
        r['line_total_baisas'] = (r['line_total_baisas'] as int) ~/ old * keep;
      }
      r['qty'] = keep;
      if (keep == 0) r['status'] = 'void';
    }
    if (op['operation'] == 'replace') rows.addAll(request.lines.map(row));
    update(rows);
    final response = {'order': orders.single.json, 'replayed': false};
    results[request.id] = response;
    if (lostResponse) throw TimeoutException('Reply lost after commit');
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    debugOrderStorageOverride = FakeOrderStorage();
    for (final name in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'pos_machine/rear_display_host',
      'sunmi_printer_plus',
    ]) {
      final channel = MethodChannel(name);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'read'
            ? 'test-token'
            : call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : null,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
  });
  tearDown(() => debugOrderStorageOverride = null);
  const catalogue = CatalogSnapshot(
    categories: ['Drinks'],
    products: [
      Product(id: '7', name: 'Water', category: 'Drinks', price: 1),
      Product(
        id: '8',
        name: 'Coffee',
        category: 'Drinks',
        price: 2,
        addonGroupIds: [1],
      ),
    ],
    floors: [],
    tables: [],
    taxes: [],
    addonGroups: [
      AddonGroup(
        id: 1,
        name: 'Size',
        multiSelect: false,
        minSelections: 1,
        maxSelections: 1,
        options: [
          AddonOption(id: 10, label: 'Small', priceDelta: 0),
          AddonOption(id: 11, label: 'Large', priceDelta: 0),
        ],
      ),
    ],
  );
  Finder named(String name) =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
  for (final arabic in [false, true]) {
    testWidgets(
      'normal QR cart add, merge, plus, minus, addon and delete ${arabic ? "AR" : "EN"}',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await loadQuickEvidenceFonts(tester);
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          arabic: arabic,
          catalog: catalogue,
        );
        final dynamic staff = tester.state(find.byType(StaffPosScreen));
        final original = jsonEncode(staff.controller.snapshot().toMap());
        final api = CartParityGateway();
        final store = MemoryQuickStore();
        final c = QrQuickController(api, store);
        dynamic workspace;
        staff.openServerWorkspace((CurrentOrderWorkspace w) {
          workspace = w;
          return QrQuickScreen(
            workspace: w,
            workspaceUuid: 'bill-1',
            arabic: arabic,
            createController: () async => c,
            catalogue: () => machineQuickCatalogue(catalogue),
            onPay: (_, order) async {},
          );
        }, quick: true);
        await tester.pumpAndSettle();
        Future<void> product(String name) async {
          await tester.tap(
            find.byWidgetPredicate(
              (w) =>
                  w.runtimeType.toString() == '_ProductTile' &&
                  (w as dynamic).product.name == name,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
        }

        await product('Water');
        await product('Water');
        expect(named('_OrderItemCard'), findsOneWidget);
        expect(workspace.cartBill!.items.single['qty'], 2);
        final dynamic card = tester.widget(named('_OrderItemCard'));
        card.onAdd();
        await tester.pumpAndSettle();
        expect(workspace.cartBill!.items.single['qty'], 3);
        final dynamic three = tester.widget(named('_OrderItemCard'));
        three.onRemove();
        await tester.pumpAndSettle();
        expect(workspace.cartBill!.items.single['qty'], 2);
        expect(api.changes.last.payload['item_ids'], hasLength(3));
        final dynamic two = tester.widget(named('_OrderItemCard'));
        two.onDelete();
        await tester.pumpAndSettle();
        expect(workspace.cartBill!.items, isEmpty);
        await product('Coffee');
        await product('Coffee');
        expect(named('_OrderItemCard'), findsOneWidget);
        expect(workspace.cartBill!.items.single['qty'], 2);
        expect(workspace.cartControls!.drafts, hasLength(1));
        expect(workspace.canPay, false);
        expect(workspace.cartControls!.transfer, isNull);
        expect(find.byKey(const ValueKey('workspace-submit')), findsNothing);
        expect(find.byKey(const ValueKey('workspace-refresh')), findsNothing);
        expect(api.requests, hasLength(3));
        final dynamic draft = tester.widget(named('_OrderItemCard'));
        draft.onCustomize();
        await tester.pumpAndSettle();
        expect(named('_CustomizeCartItemDialog'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('customize-confirm')));
        await tester.pumpAndSettle();
        expect(workspace.cartControls!.drafts, isEmpty);
        expect(api.requests.last.lines.single.addonIds, [10]);
        expect(api.requests.last.lines.single.quantity, 2);
        expect(workspace.canPay, true);
        final dynamic customized = tester.widget(named('_OrderItemCard'));
        customized.onAdd();
        await tester.pumpAndSettle();
        expect(named('_OrderItemCard'), findsOneWidget);
        expect(workspace.cartBill!.items.single['qty'], 3);
        final dynamic grouped = tester.widget(named('_OrderItemCard'));
        grouped.onCustomize();
        await tester.pumpAndSettle();
        expect(named('_CustomizeCartItemDialog'), findsOneWidget);
        final beforeEdit = api.changes.length;
        api.orders = [
          QrQuickOrder({
            ...api.orders.single.json,
            'edit_revision': 'another-cashier',
          }),
        ];
        await c.refresh();
        await tester.tap(find.byKey(const ValueKey('customize-confirm')));
        await tester.pumpAndSettle();
        expect(api.changes.length, beforeEdit);
        expect(c.notice, 'order_changed');
        final dynamic refreshed = tester.widget(named('_OrderItemCard'));
        refreshed.onCustomize();
        await tester.pumpAndSettle();
        expect(named('_CustomizeCartItemDialog'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('customize-option-11')));
        await tester.tap(find.byKey(const ValueKey('customize-confirm')));
        await tester.pumpAndSettle();
        expect(api.changes.last.payload['item_ids'], hasLength(2));
        expect(api.changes.last.lines.single.addonIds, [11]);
        expect(workspace.cartBill!.items.single['qty'], 3);
        api.lostResponse = true;
        final dynamic edited = tester.widget(named('_OrderItemCard'));
        edited.onDelete();
        await tester.pumpAndSettle();
        expect(workspace.canPay, false);
        final event = jsonEncode(api.changes.last.payload);
        expect(store.data, hasLength(1));
        api.lostResponse = false;
        await workspace.cartControls!.retry!();
        await tester.pumpAndSettle();
        expect(jsonEncode(api.changes.last.payload), event);
        expect(workspace.cartBill!.items, isEmpty);
        expect(store.data, isEmpty);
        expect(jsonEncode(staff.controller.snapshot().toMap()), original);
        expect(tester.takeException(), isNull);
        await disposeWorkspaceMachine(tester);
      },
    );
  }
  test('grouping retains different prices, discounts, notes and add-ons', () {
    final api = CartParityGateway();
    final base = api.row(QrQuickLine(7, 1, []));
    final dynamic bill = WorkspaceBill({
      ...quickJson(),
      'items': [
        base,
        {...base, 'id': 2},
        {...base, 'id': 3, 'notes': 'Cold'},
        {...base, 'id': 4, 'line_total_baisas': 1500},
        {...base, 'id': 5, 'line_discount_baisas': 100},
        {
          ...base,
          'id': 6,
          'addons': [
            {'add_on_id': 10},
          ],
        },
      ],
    });
    expect(bill.groupedItems, hasLength(5));
    expect(bill.groupedItems.first['qty'], 2);
    expect(bill.groupedItems.first['item_ids'], [base['id'], 2]);
    expect(bill.items, hasLength(6));
  });
}
