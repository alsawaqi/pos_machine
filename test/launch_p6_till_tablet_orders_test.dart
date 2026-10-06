import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/authorization.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart' show VoidReasonRef;
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';

/// LAUNCH-P6 Part C items 4 and 5 (till) — the tablet orders list and
/// sheet: Take / Take over, "Taken by", send to the kitchen with cash later,
/// cash first then the kitchen, edit before send, cancel, the Unpaid badge,
/// the masked phone and points line, the charge state, and the points
/// approval through the till's `_authorizeAction('loyalty.redeem')`.
Map<String, dynamic> base(String uuid, {Map<String, dynamic>? extra}) => {
  'tablet_order_uuid': uuid,
  'order_uuid': 'order-$uuid',
  'order_type': 'quick',
  'source': 'customer_tablet',
  'order_status': 'held',
  'state': 'pending',
  'paid': false,
  'unpaid': true,
  'order_number': '27',
  'temp_reference': 'T-1006-27',
  'table': null,
  'table_session_uuid': null,
  'round_id': null,
  'lines': [
    {
      'product_id': 4,
      'product_name': 'Burger',
      'product_name_ar': 'برجر',
      'qty': 2,
      'addons': [
        {'add_on_id': 11, 'name': 'No onion', 'name_ar': 'بدون بصل'},
      ],
    },
  ],
  'total_baisas': 3000,
  'grand_total_baisas': 3000,
  'phone_masked': '9xxx1234',
  'payment': 'cash',
  'redeem': null,
  'taken_by': null,
  'sent_to_kitchen': null,
  'ready_in_minutes': 12,
  'charge': {
    'state': 'none',
    'device_id': null,
    'deadline_at': null,
    'held_by_this_device': false,
  },
  'recovery_needed': false,
  ...?extra,
};

const requested = {
  'status': 'requested',
  'rule_id': 3,
  'rule_name': 'Points',
  'kind': 'points',
  'blocks': 1,
  'units': 50,
  'amount_baisas': 500,
  'approved_units': null,
  'approved_amount_baisas': null,
  'available': true,
};

class FakeGateway implements TabletOrdersGateway {
  FakeGateway(this.rows);
  List<Map<String, dynamic>> rows;
  final calls = <String>[];
  Map<String, dynamic>? approvedBlock;
  String? approvedRequest;
  List<QrQuickLine>? editedLines;
  TabletOrderFailure? refuse;

  Map<String, dynamic> _row(String uuid) =>
      rows.firstWhere((r) => r['tablet_order_uuid'] == uuid);

  TabletActionResult _answer(
    String outcome,
    String uuid,
    Map<String, dynamic> change,
  ) {
    final failure = refuse;
    if (failure != null) {
      refuse = null;
      throw failure;
    }
    final next = {..._row(uuid), ...change};
    rows = [
      for (final r in rows)
        if (r['tablet_order_uuid'] == uuid) next else r,
    ];
    return TabletActionResult({'outcome': outcome, 'order': next});
  }

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async {
    calls.add('list');
    return parseTabletOrderRows(rows);
  }

  @override
  Future<TabletActionResult> take(String uuid, {bool takeOver = false}) async {
    calls.add(takeOver ? 'take_over:$uuid' : 'take:$uuid');
    return _answer(takeOver ? 'taken_over' : 'taken', uuid, {
      'taken_by': {'staff_id': 7, 'name': 'Ali', 'device_id': 1, 'at': null},
    });
  }

  @override
  Future<TabletActionResult> send(String uuid) async {
    calls.add('send:$uuid');
    return _answer('sent', uuid, {
      'state': 'sent',
      'sent_to_kitchen': {'staff_id': 7, 'name': 'Ali'},
    });
  }

  @override
  Future<TabletActionResult> approve(
    String uuid, {
    required String requestId,
    required Map<String, dynamic> authorization,
  }) async {
    calls.add('approve:$uuid');
    approvedBlock = authorization;
    approvedRequest = requestId;
    return _answer('approved', uuid, {
      'redeem': {
        ...requested,
        'status': 'approved',
        'approved_units': 50,
        'approved_amount_baisas': 500,
      },
      'grand_total_baisas': 2500,
    });
  }

  @override
  Future<TabletActionResult> reject(String uuid) async {
    calls.add('reject:$uuid');
    return _answer('rejected', uuid, {
      'redeem': {
        ...requested,
        'status': 'rejected',
        'units': 0,
        'amount_baisas': 0,
      },
    });
  }

  @override
  Future<TabletActionResult> edit(
    String uuid, {
    required String requestId,
    required List<QrQuickLine> lines,
  }) async {
    calls.add('edit:$uuid');
    editedLines = lines;
    return _answer('edited', uuid, {
      'lines': [
        for (final l in lines)
          {
            'product_id': l.productId,
            'product_name': 'Burger',
            'qty': l.quantity,
          },
      ],
      'grand_total_baisas': 1500,
    });
  }

  @override
  Future<void> rejectRound(String seatingUuid, int roundId) async {
    calls.add('reject_round:$seatingUuid:$roundId');
    rows = [
      for (final r in rows)
        if (r['round_id'] == roundId) {...r, 'state': 'closed'} else r,
    ];
  }

  @override
  Future<Map<int, String>> deviceNames() async => {2: 'Till 2'};
}

void main() {
  late FakeGateway gateway;
  late TabletOrdersController controller;
  late List<String> events;
  ActionAuthorization? gate;
  late List<String> gates;
  bool paid = true;

  ActionAuthorization position(String action) => ActionAuthorization.position(
    action: action,
    actorStaffId: 7,
    actorName: 'Ali',
  );

  setUp(() {
    events = [];
    gates = [];
    paid = true;
  });

  TabletOrderActions actions({List<VoidReasonRef> reasons = const []}) =>
      TabletOrderActions(
        myStaffId: 7,
        authorize: (action, {subtitle, alwaysApproval = false}) async {
          gates.add('$action|${subtitle ?? ''}|$alwaysApproval');
          return gate;
        },
        takeCash: (row) async {
          events.add('cash:${row.orderUuid}:${row.payableBaisas}');
          if (paid) {
            gateway.rows = [
              for (final r in gateway.rows)
                if (r['tablet_order_uuid'] == row.uuid)
                  {...r, 'paid': true, 'unpaid': false}
                else
                  r,
            ];
          }
          return paid;
        },
        voidOrder: (row, {reason, required authorization}) async {
          events.add(
            'void:${row.orderUuid}:${reason?.id}:${authorization.action}',
          );
        },
        voidReasons: reasons,
        openTable: (row) => events.add('table:${row.tableId}'),
        moveToCounter: (row) async => events.add('counter:${row.orderUuid}'),
        paymentReview: (row) async => events.add('review:${row.orderUuid}'),
        checkPaymentResult: () async => events.add('check'),
        onOpened: (key) => events.add('opened:$key'),
      );

  Future<void> pumpScreen(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    Locale locale = const Locale('en'),
    List<VoidReasonRef> reasons = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    gateway = FakeGateway(rows);
    controller = TabletOrdersController(gateway);
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TabletOrdersScreen(
          controller: controller,
          actions: actions(reasons: reasons),
          poll: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, String uuid) async {
    await tester.tap(find.byKey(ValueKey('tablet-order-$uuid')));
    await tester.pumpAndSettle();
  }

  String? sheetText(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data;

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('Taken by another; take over needs a confirm and is sent', (
    tester,
  ) async {
    await pumpScreen(tester, [
      base(
        'a',
        extra: {
          'taken_by': {'staff_id': 9, 'name': 'Sara', 'device_id': 2},
        },
      ),
    ]);
    expect(find.text('Taken by Sara'), findsOneWidget);
    await open(tester, 'a');
    expect(events, ['opened:tablet:a']);
    // Not yours: no send, cash or cancel — only take over.
    expect(find.byKey(const ValueKey('tablet-send')), findsNothing);
    expect(find.byKey(const ValueKey('tablet-take-cash')), findsNothing);
    await tapKey(tester, 'tablet-take-over');
    expect(find.textContaining('Sara has this order'), findsOneWidget);
    await tapKey(tester, 'tablet-confirm-no');
    expect(gateway.calls.where((c) => c.startsWith('take')), isEmpty);
    await tapKey(tester, 'tablet-take-over');
    await tapKey(tester, 'tablet-confirm-yes');
    expect(gateway.calls, contains('take_over:a'));
    expect(find.byKey(const ValueKey('tablet-sheet-taken')), findsOneWidget);
    expect(find.text('Taken by you'), findsWidgets);
  });

  testWidgets('a lost take race shows who took it', (tester) async {
    await pumpScreen(tester, [base('a')]);
    await open(tester, 'a');
    gateway.refuse = const TabletOrderFailure(
      'tablet_order_taken',
      takenBy: 'Sara',
    );
    await tapKey(tester, 'tablet-take');
    expect(find.text('Sara already took this order.'), findsOneWidget);
  });

  testWidgets('send to the kitchen first; cash later shows Unpaid', (
    tester,
  ) async {
    await pumpScreen(tester, [base('a')]);
    expect(find.text('9xxx1234', findRichText: true), findsNothing);
    expect(find.text('Customer 9xxx1234'), findsOneWidget);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-send');
    expect(gateway.calls, contains('send:a'));
    expect(find.byKey(const ValueKey('tablet-sheet-unpaid')), findsOneWidget);
    // Cash later: the existing pay of the order's frozen total; already
    // sent, so it is not sent again.
    await tapKey(tester, 'tablet-take-cash');
    expect(events.last, 'cash:order-a:3000');
    expect(gateway.calls.where((c) => c == 'send:a'), hasLength(1));
    await tapKey(tester, 'tablet-sheet-close');
    expect(find.byKey(const ValueKey('tablet-unpaid-a')), findsNothing);
  });

  testWidgets('cash first, then the kitchen (taken first)', (tester) async {
    await pumpScreen(tester, [base('a')]);
    await open(tester, 'a');
    expect(find.text('Take cash, then send to kitchen'), findsOneWidget);
    await tapKey(tester, 'tablet-take-cash');
    expect(gateway.calls.where((c) => c != 'list'), ['take:a', 'send:a']);
    expect(events, ['opened:tablet:a', 'cash:order-a:3000']);
  });

  testWidgets('no payment confirmed: nothing is sent to the kitchen', (
    tester,
  ) async {
    paid = false;
    await pumpScreen(tester, [base('a')]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-take-cash');
    expect(gateway.calls, isNot(contains('send:a')));
  });

  testWidgets('points: approve with the loyalty.redeem tick', (tester) async {
    gate = position('loyalty.redeem');
    await pumpScreen(tester, [
      base('a', extra: {'redeem': requested}),
    ]);
    expect(find.text('Asks to use 50 points (0.500 OMR)'), findsOneWidget);
    await open(tester, 'a');
    expect(
      find.text('Use 50 points (0.500 OMR) for 9xxx1234?'),
      findsOneWidget,
    );
    // Cash waits until the points are decided.
    expect(find.byKey(const ValueKey('tablet-take-cash')), findsNothing);
    expect(
      find.text('Approve or reject the points request first.'),
      findsOneWidget,
    );
    await tapKey(tester, 'tablet-redeem-approve');
    expect(gates.single, startsWith('loyalty.redeem|Use 50 points'));
    expect(gateway.approvedBlock!['action'], 'loyalty.redeem');
    expect(gateway.approvedBlock!['mode'], 'position');
    expect(gateway.approvedBlock!['ref'], gateway.approvedRequest);
    expect(
      sheetText(tester, 'tablet-sheet-points'),
      'Points used: 50 (0.500 OMR)',
    );
    expect(sheetText(tester, 'tablet-sheet-total'), 'Total 2.500 OMR');
  });

  testWidgets('points: an approver PIN signs this order, amount and ref', (
    tester,
  ) async {
    gate = ActionAuthorization.approval(
      action: 'loyalty.redeem',
      actorStaffId: 7,
      actorName: 'Ali',
      deviceUuid: 'device-1',
      grant: ApprovalGrant(
        approverStaffId: 2,
        name: 'Manager',
        approvedAt: DateTime.utc(2026, 10, 6, 9),
        method: 'online',
        key: Uint8List.fromList(List.filled(32, 7)),
      ),
    );
    await pumpScreen(tester, [
      base('a', extra: {'redeem': requested}),
    ]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-redeem-approve');
    final block = gateway.approvedBlock!;
    expect(block['mode'], 'approval');
    expect(block['subject_uuid'], 'a');
    expect(block['amount_baisas'], 500);
    expect(block['ref'], gateway.approvedRequest);
    expect(block['proof'], isA<String>());
  });

  testWidgets('points: no permission and no approver = nothing sent', (
    tester,
  ) async {
    gate = null;
    await pumpScreen(tester, [
      base('a', extra: {'redeem': requested}),
    ]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-redeem-approve');
    expect(gates, hasLength(1));
    expect(gateway.calls.where((c) => c.startsWith('approve')), isEmpty);
  });

  testWidgets('points: reject shows 0 points and the full amount', (
    tester,
  ) async {
    await pumpScreen(tester, [
      base('a', extra: {'redeem': requested}),
    ]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-redeem-reject');
    expect(gateway.calls, contains('reject:a'));
    expect(
      sheetText(tester, 'tablet-sheet-points'),
      'Points rejected — 0 points, full amount in cash',
    );
    expect(sheetText(tester, 'tablet-sheet-total'), 'Total 3.000 OMR');
  });

  testWidgets('charge state: being paid elsewhere, needs recovery', (
    tester,
  ) async {
    await pumpScreen(tester, [
      base(
        'a',
        extra: {
          'charge': {
            'state': 'claimed',
            'device_id': 2,
            'deadline_at': null,
            'held_by_this_device': false,
          },
        },
      ),
      base(
        'b',
        extra: {
          'order_number': '28',
          'charge': {
            'state': 'lapsed',
            'device_id': 2,
            'held_by_this_device': false,
          },
          'recovery_needed': true,
        },
      ),
      base(
        'c',
        extra: {
          'order_number': '29',
          'charge': {
            'state': 'lapsed',
            'device_id': 1,
            'held_by_this_device': true,
          },
          'recovery_needed': true,
        },
      ),
    ]);
    expect(find.text('Being paid on Till 2'), findsOneWidget);
    await open(tester, 'a');
    expect(find.byKey(const ValueKey('tablet-take-cash')), findsNothing);
    expect(find.byKey(const ValueKey('tablet-cancel')), findsNothing);
    await tapKey(tester, 'tablet-sheet-close');
    await open(tester, 'b');
    expect(find.byKey(const ValueKey('tablet-sheet-charge')), findsOneWidget);
    expect(
      find.text('Needs recovery — the cash result is not known.'),
      findsWidgets,
    );
    await tapKey(tester, 'tablet-move-counter');
    await tapKey(tester, 'tablet-payment-review');
    expect(events, containsAll(['counter:order-b', 'review:order-b']));
    expect(find.byKey(const ValueKey('tablet-check-payment')), findsNothing);
    await tapKey(tester, 'tablet-sheet-close');
    await open(tester, 'c');
    await tapKey(tester, 'tablet-check-payment');
    expect(events, contains('check'));
    expect(find.byKey(const ValueKey('tablet-move-counter')), findsNothing);
  });

  testWidgets('edit before send: change qty, remove, save (F-8)', (
    tester,
  ) async {
    await pumpScreen(tester, [base('a')]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-edit');
    await tapKey(tester, 'tablet-edit-minus-0');
    await tapKey(tester, 'tablet-edit-save');
    expect(gateway.calls, contains('edit:a'));
    final line = gateway.editedLines!.single;
    expect(line.productId, 4);
    expect(line.quantity, 1);
    expect(line.addonIds, [11]);
    // The sheet shows the server's new Row (refresh on `edited`).
    expect(sheetText(tester, 'tablet-sheet-total'), 'Total 1.500 OMR');
  });

  testWidgets('cancel: unsent quick = order.void with void_unpaid', (
    tester,
  ) async {
    gate = position('order.void_unpaid');
    await pumpScreen(tester, [base('a')]);
    await open(tester, 'a');
    await tapKey(tester, 'tablet-cancel');
    await tapKey(tester, 'tablet-confirm-yes');
    expect(gates.single, startsWith('order.void_unpaid|'));
    expect(events.last, 'void:order-a:null:order.void_unpaid');
  });

  testWidgets('cancel: sent quick = void with a "food was made" reason', (
    tester,
  ) async {
    gate = position('order.void_unpaid');
    await pumpScreen(
      tester,
      [
        base('a', extra: {'state': 'sent'}),
      ],
      reasons: const [
        VoidReasonRef(id: 1, code: 'mistake', name: 'Mistake'),
        VoidReasonRef(
          id: 2,
          code: 'made',
          name: 'Customer left',
          affectsInventory: true,
          requiresManager: false,
        ),
      ],
    );
    await open(tester, 'a');
    await tapKey(tester, 'tablet-cancel');
    expect(find.byKey(const ValueKey('tablet-void-reason-1')), findsNothing);
    await tapKey(tester, 'tablet-void-reason-2');
    expect(events.last, 'void:order-a:2:order.void_unpaid');
  });

  testWidgets('cancel: unsent dine-in rejects the round; sent opens table', (
    tester,
  ) async {
    await pumpScreen(tester, [
      base(
        'd',
        extra: {
          'order_type': 'dine_in',
          'order_number': null,
          'table': {'id': 5, 'uuid': 'tb-5', 'name': '5'},
          'table_session_uuid': 'seat-1',
          'round_id': 44,
        },
      ),
      base(
        'e',
        extra: {
          'order_type': 'dine_in',
          'state': 'sent',
          'order_number': null,
          'table': {'id': 6, 'uuid': 'tb-6', 'name': '6'},
        },
      ),
    ]);
    expect(find.text('Table 5'), findsOneWidget);
    await open(tester, 'd');
    expect(find.text('Send to kitchen (joins the table bill)'), findsOneWidget);
    expect(find.byKey(const ValueKey('tablet-take-cash')), findsNothing);
    await tapKey(tester, 'tablet-cancel');
    await tapKey(tester, 'tablet-confirm-yes');
    expect(gateway.calls, contains('reject_round:seat-1:44'));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    if (find
        .byKey(const ValueKey('tablet-sheet-close'))
        .evaluate()
        .isNotEmpty) {
      await tapKey(tester, 'tablet-sheet-close');
    }
    await open(tester, 'e');
    expect(find.text('Open the table to cancel'), findsOneWidget);
    await tapKey(tester, 'tablet-cancel');
    expect(events.last, 'table:6');
  });

  testWidgets('Arabic: the list and sheet are in Arabic', (tester) async {
    await pumpScreen(tester, [
      base('a', extra: {'state': 'sent', 'redeem': requested}),
    ], locale: const Locale('ar'));
    expect(find.text('طلبات الجهاز اللوحي'), findsOneWidget);
    expect(find.text('غير مدفوع'), findsOneWidget);
    expect(find.text('العميل 9xxx1234'), findsOneWidget);
    await open(tester, 'a');
    expect(find.text('2 × برجر'), findsOneWidget);
    expect(find.text('   + بدون بصل'), findsOneWidget);
    expect(
      find.text('استخدام 50 نقطة (0.500 ر.ع) للعميل 9xxx1234؟'),
      findsOneWidget,
    );
  });
}
