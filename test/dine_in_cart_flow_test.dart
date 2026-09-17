import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory;

void main() {
  testWidgets('dine-in uses normal cart additions, quantity and kitchen send', (
    tester,
  ) async {
    final gateway = TableFake(), journal = TableMemory();
    final controller = DineInController(gateway, journal, 2);
    var options = 0;
    final workspace = CurrentOrderWorkspace(
      mainCart: true,
      onExit: () {},
      editOptions: (row) async {
        options++;
        return QrQuickLine(8, (row['qty'] as num).toInt(), [10]);
      },
    );
    const product = QuickProduct(
      8,
      'Coffee',
      priceBaisas: 1000,
      groups: [
        QuickGroup('Milk', [QuickChoice(10, 'Oat')], max: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DineInScreen(
          workspace: workspace,
          label: 'T2',
          createController: () async => controller,
          catalogue: () => [product],
          onPay: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(workspace.cartControls, isNotNull);
    final reads = gateway.calls.length;
    await workspace.pick(product);
    await workspace.pick(product);
    await tester.pump();
    expect(options, 0);
    expect(
      gateway.calls.length,
      reads,
      reason: 'Local item taps must not wait for an HTTP refresh',
    );
    expect(workspace.cartControls!.draftRows, hasLength(1));
    expect(workspace.cartControls!.draftRows.single['qty'], 2);
    expect(workspace.cartBill!.total, 6750);
    expect(
      find.byKey(const ValueKey('dine-in-cart-controller')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('unified-dine-in')), findsNothing);
    await workspace.cartControls!.customize!(
      workspace.cartControls!.draftRows.single,
    );
    expect(options, 1);
    await workspace.cartControls!.quantity!(
      workspace.cartControls!.draftRows.single,
      1,
    );
    expect(workspace.cartControls!.draftRows.single['qty'], 1);
    await workspace.cartControls!.submit!();
    expect(gateway.requests, hasLength(1));
    expect(gateway.requests.single.payload['lines'], [
      {
        'product_id': 8,
        'qty': 1,
        'addon_ids': [10],
        'notes': null,
      },
    ]);
    expect(workspace.cartControls!.draftRows, isEmpty);
    expect(journal.request, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    workspace.dispose();
  });

  testWidgets('cash success leaves the closed QR table workspace', (
    tester,
  ) async {
    final gateway = TableFake();
    var exits = 0;
    final workspace = CurrentOrderWorkspace(
      mainCart: true,
      onExit: () => exits++,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DineInScreen(
          workspace: workspace,
          label: 'T2',
          createController: () async =>
              DineInController(gateway, TableMemory(), 2),
          catalogue: () => [],
          onPay: (_) async {
            (gateway.value['bill'] as Map)['status'] = 'paid';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await workspace.requestPay();
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    workspace.dispose();
  });
}
