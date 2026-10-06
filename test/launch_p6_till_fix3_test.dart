import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';

/// LAUNCH-P6 Part C till fix order 3 (device run 1) — T-9 "Open the table
/// to pay", T-10 no spurious "already closed" after our own pay + send,
/// T-11 the till's look, T-12 "This order X · Table bill Y" (F-22).
Map<String, dynamic> base(String uuid, {Map<String, dynamic>? extra}) => {
  'tablet_order_uuid': uuid,
  'order_uuid': 'order-$uuid',
  'order_type': 'quick',
  'state': 'pending',
  'paid': false,
  'unpaid': true,
  'order_number': '27',
  'table': null,
  'lines': [
    {'product_id': 4, 'product_name': 'Burger', 'qty': 1},
  ],
  'total_baisas': 3000,
  'grand_total_baisas': 3000,
  'taken_by': {'staff_id': 7, 'name': 'Ali'},
  'charge': {'state': 'none'},
  ...?extra,
};

Map<String, dynamic> dineIn(String uuid, {Map<String, dynamic>? extra}) => base(
  uuid,
  extra: {
    'order_type': 'dine_in',
    'state': 'sent',
    'order_number': null,
    'table': {'id': 6, 'uuid': 't6', 'name': 'RV test'},
    'grand_total_baisas': 3330,
    ...?extra,
  },
);

class Gateway implements TabletOrdersGateway {
  Gateway(this.rows);
  List<Map<String, dynamic>> rows;
  final calls = <String>[];

  /// The server's answer to a send after the pay ('closed' / 'sent').
  String? sendRefusal;

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async {
    calls.add('list');
    return parseTabletOrderRows(rows);
  }

  @override
  Future<TabletActionResult> send(String uuid) async {
    calls.add('send:$uuid');
    final refusal = sendRefusal;
    if (refusal != null) throw TabletOrderFailure(refusal);
    final next = {
      ...rows.firstWhere((r) => r['tablet_order_uuid'] == uuid),
      'state': 'sent',
    };
    rows = [
      for (final r in rows)
        if (r['tablet_order_uuid'] == uuid) next else r,
    ];
    return TabletActionResult({'outcome': 'sent', 'order': next});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});
  late Gateway gateway;
  late List<String> events;

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    Future<bool?> Function(TabletOrderRow)? takeCash,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    events = [];
    gateway = Gateway(rows);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TabletOrdersScreen(
          controller: TabletOrdersController(gateway),
          poll: const Duration(hours: 1),
          actions: TabletOrderActions(
            myStaffId: 7,
            authorize: (a, {subtitle, alwaysApproval = false}) async => null,
            takeCash: takeCash,
            openTable: (row) => events.add('cancel at table ${row.tableId}'),
            openTableToPay: (row) => events.add('pay at table ${row.tableId}'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('T-9: a sent unpaid dine-in order opens the table to pay', (
    tester,
  ) async {
    await pump(tester, [dineIn('d')]);
    await tap(tester, 'tablet-order-d');
    expect(find.text('Open the table to pay'), findsOneWidget);
    expect(find.text('Open the table to cancel'), findsOneWidget);
    await tap(tester, 'tablet-open-table-pay');
    expect(events, ['pay at table 6']);
  });

  testWidgets('T-9: points still open — confirm before the table', (
    tester,
  ) async {
    await pump(tester, [
      dineIn(
        'd',
        extra: {
          'redeem': {
            'status': 'requested',
            'units': 100,
            'amount_baisas': 500,
            'blocks': 1,
          },
        },
      ),
    ]);
    await tap(tester, 'tablet-order-d');
    await tap(tester, 'tablet-open-table-pay');
    expect(events, isEmpty);
    await tap(tester, 'tablet-confirm-yes');
    expect(events, ['pay at table 6']);
  });

  test('T-9: Pay runs once the table bill is payable', () async {
    final ready = ValueNotifier(false);
    var paid = 0;
    final run = runWhenReady(ready, () => ready.value, () async => paid++);
    await Future<void>.delayed(Duration.zero);
    expect(paid, 0);
    ready.value = true;
    expect(await run, isTrue);
    expect(paid, 1);
    expect(
      await runWhenReady(
        ValueNotifier(false),
        () => false,
        () async => paid++,
        timeout: const Duration(milliseconds: 10),
      ),
      isFalse,
    );
    expect(paid, 1);
  });

  testWidgets('T-10: the pay already sent it (it left the list): success, '
      'no "already closed"', (tester) async {
    await pump(
      tester,
      [base('a')],
      takeCash: (row) async {
        gateway.rows = [];
        gateway.sendRefusal = 'tablet_order_closed';
        return true;
      },
    );
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-take-cash');
    expect(find.textContaining('already closed'), findsNothing);
    expect(find.text('Paid and sent to the kitchen.'), findsOneWidget);
  });

  testWidgets('T-10: a send answered "already sent" after our pay is '
      'success', (tester) async {
    await pump(
      tester,
      [base('a')],
      takeCash: (row) async {
        gateway.rows = [
          base('a', extra: {'paid': true, 'unpaid': false}),
        ];
        gateway.sendRefusal = 'tablet_order_sent';
        return true;
      },
    );
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-take-cash');
    expect(gateway.calls, contains('send:a'));
    expect(find.byKey(const ValueKey('tablet-sheet-notice')), findsNothing);
    expect(find.textContaining('already closed'), findsNothing);
  });

  testWidgets('T-11: the list and its sheet use the till look', (tester) async {
    await pump(tester, [base('a')]);
    final scaffold = tester.widget<Scaffold>(
      find.byKey(const ValueKey('tablet-orders-scaffold')),
    );
    expect(scaffold.backgroundColor, const Color(0xFF102028));
    final theme = Theme.of(tester.element(find.byType(TabletOrderCard)));
    expect(theme.colorScheme.primary, const Color(0xFF35C28B));
    expect(theme.cardTheme.color, const Color(0xFF16313B));
    await tap(tester, 'tablet-order-a');
    final sheet = Theme.of(
      tester.element(find.byKey(const ValueKey('tablet-sheet-a'))),
    );
    expect(sheet.colorScheme.primary, const Color(0xFF35C28B));
    expect(sheet.dialogTheme.backgroundColor, const Color(0xFF16313B));
  });

  testWidgets('T-12: dine in shows "This order" and "Table bill" (F-22)', (
    tester,
  ) async {
    await pump(tester, [
      dineIn('d', extra: {'order_total_baisas': 1530}),
      dineIn(
        'old',
        extra: {
          'table': {'id': 7, 'uuid': 't7', 'name': '7'},
        },
      ),
    ]);
    expect(find.text('This order 1.530 OMR'), findsOneWidget);
    expect(find.text('Table bill 3.330 OMR'), findsOneWidget);
    // An older server (no order_total_baisas): the one total, as before.
    expect(find.text('Total 3.330 OMR'), findsOneWidget);
    await tap(tester, 'tablet-order-d');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('tablet-sheet-order-total')))
          .data,
      'This order 1.530 OMR',
    );
    expect(
      lookupL10n(const Locale('ar')).tabletTableBillLine('3.330'),
      'فاتورة الطاولة 3.330 ر.ع',
    );
  });
}
