import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'package:pos_machine/widgets/qr_table_money_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('detail is read-only and claim precedes the frozen bare tender', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final flow = _FakeSettlementFlow();
    await _pumpPanel(tester, service: service, flow: flow);

    expect(find.text('Long server-priced product name'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const ValueKey('qr-action-settle')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();
    expect(flow.calls, ['claim:order-3']);
    expect(find.byKey(const ValueKey('qr-settlement-sheet')), findsOneWidget);
    expect(find.text('OMR 4.750'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('qr-tender-card')));
    await tester.pump();
    expect(flow.calls, ['claim:order-3', 'settle:card']);
    expect(find.textContaining('Payment accepted'), findsOneWidget);
    await _disposePanel(tester);
  });

  testWidgets('staff action refusal uses mapped actionable copy', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(id: 4, sessionStatus: 'ordered', orderStatus: 'awaiting_payment'),
      ],
      reopenError: ApiException(
        message: 'raw server text',
        statusCode: 409,
        code: 'qr_order_not_reopenable',
      ),
    );
    await _pumpPanel(tester, service: service);
    await tester.tap(find.byKey(const ValueKey('qr-action-reopen')));
    await tester.pump();

    expect(
      find.text('This order cannot be reopened for more rounds.'),
      findsOneWidget,
    );
    expect(find.text('raw server text'), findsNothing);
    await _disposePanel(tester);
  });

  for (final scenario in ['awaiting acknowledgement', 'release failure']) {
    testWidgets('$scenario keeps route locked for manager takeover', (
      tester,
    ) async {
      final service = _FakeTillGateway(
        board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
        active: [_activeOrder()],
      );
      final flow = _FakeSettlementFlow(
        settleResult: (claim, _) => QrSettlementResult(
          kind: scenario == 'awaiting acknowledgement'
              ? QrSettlementResultKind.awaitingServerAcknowledgement
              : QrSettlementResultKind.cardCancelledBeforeCapture,
          claim: claim,
          clientEventId: 'durable-event',
          releaseError: scenario == 'release failure'
              ? StateError('release refused')
              : null,
        ),
      );
      await _pumpPanel(tester, service: service, flow: flow);
        await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
      await tester.pump();
      await tester.tap(
        find.byKey(
          ValueKey(
            scenario == 'release failure' ? 'qr-tender-card' : 'qr-tender-cash',
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('qr-settlement-procedure')),
        findsOneWidget,
      );
      await tester.tap(find.text('I understand'));
      await tester.pump();

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('qr-manager-takeover-warning')),
        findsOneWidget,
      );
      expect(flow.calls.where((call) => call.startsWith('release:')), isEmpty);
      await _disposePanel(tester);
    });
  }


}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required _FakeTillGateway service,
  _FakeSettlementFlow? flow,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        qrTillServiceProvider.overrideWithValue(service),
        qrSettlementCoordinatorProvider.overrideWithValue(
          flow ?? _FakeSettlementFlow(),
        ),
      ],
      child: MaterialApp(home: _FakeHost(service: service)),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _disposePanel(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

class _FakeHost extends StatefulWidget {
  const _FakeHost({required this.service});
  final _FakeTillGateway service;
  @override
  State<_FakeHost> createState() => _FakeHostState();
}

class _FakeHostState extends State<_FakeHost> implements QrTableMoneyHost {
  @override
  QrTableBoardRow? get row => widget.service.board.firstOrNull;
  @override
  QrActiveOrder? get active => widget.service.active.firstOrNull;
  @override
  bool get arabic => false;
  @override
  Future<void> refresh() async {}
  @override
  void applyOrderAction(QrOrderActionResult result) {}
  @override
  void notice(String text, {bool success = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => QrTableMoneyPanel(
    host: this,
    builder: (context, detail, requestExit, settling) => Scaffold(
      key: const ValueKey('fake-money-host'),
      body: detail,
    ),
  );
}

QrTableBoardRow _row({
  required int id,
  required String sessionStatus,
  required String orderStatus,
}) => QrTableBoardRow(
  tableId: id,
  tableLabel: 'Table $id',
  tableStatus: 'available',
  tableDeleted: false,
  orphaned: false,
  pendingRounds: const [],
  sessionUuid: 'session',
  sessionStatus: sessionStatus,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  order: QrBoardOrder(
    uuid: 'order-$id',
    status: orderStatus,
    receiptNumber: 'QR-${id.toString().padLeft(4, '0')}',
    acceptedTotalBaisas: 4750,
  ),
);

QrActiveOrder _activeOrder() => QrActiveOrder(
  uuid: 'order-3',
  status: 'open',
  source: 'qr_web',
  tableId: 3,
  customerId: 42,
  plateNumber: 'OM 1234',
  receiptNumber: 'QR-0003',
  subtotalBaisas: 4500,
  discountTotalBaisas: 0,
  compTotalBaisas: 0,
  taxTotalBaisas: 250,
  grandTotalBaisas: 4750,
  items: const [
    QrOrderItem(
      id: 1,
      productId: 11,
      name: 'Long server-priced product name',
      quantity: 1,
      unitPriceBaisas: 4750,
      lineDiscountBaisas: 0,
      lineTotalBaisas: 4750,
      status: 'accepted',
      addons: [],
    ),
  ],
);


QrSettlementClaim _claim(String orderUuid) => QrSettlementClaim(
  orderUuid: orderUuid,
  frozenAmountBaisas: 4750,
  status: 'claimed',
  deadlineAt: DateTime.now().add(const Duration(minutes: 2)),
);

QrSettlementResult _paid(QrSettlementClaim claim) => QrSettlementResult(
  kind: QrSettlementResultKind.paid,
  claim: claim,
  clientEventId: 'event-1',
);

class _FakeTillGateway implements QrTillGateway {
  _FakeTillGateway({
    required this.board,
    this.active = const [],
    this.reopenError,
  });
  final List<QrTableBoardRow> board;
  final List<QrActiveOrder> active;
  final Object? reopenError;

  @override
  Future<QrOrderActionResult> reopenPayment(String orderUuid) async {
    if (reopenError != null) throw reopenError!;
    return QrOrderActionResult(orderUuid: orderUuid, status: 'open');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected gateway call: ${invocation.memberName}');
}

class _FakeSettlementFlow implements QrSettlementFlow {
  _FakeSettlementFlow({this.settleResult});
  final QrSettlementResult Function(QrSettlementClaim, QrTender)? settleResult;
  final List<String> calls = [];
  final Map<String, QrSettlementResult> _pending = {};

  @override
  List<QrSettlementResult> get pendingManagerRecoveries =>
      List.unmodifiable(_pending.values);
  @override
  void acknowledgeManagerRecovery(String orderUuid) {
    calls.add('acknowledge:$orderUuid');
    _pending.remove(orderUuid);
  }
  @override
  Future<QrSettlementClaim> claim(String orderUuid) async {
    calls.add('claim:$orderUuid');
    return _claim(orderUuid);
  }
  @override
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    calls.add('settle:${tender.name}');
    final result = settleResult?.call(claim, tender) ?? _paid(claim);
    if (result.managerRequired || result.releaseError != null) {
      _pending[claim.orderUuid] = result;
    }
    return result;
  }
  @override
  Future<void> releaseClaim(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome, {
    Object? terminalResult,
  }) async {
    calls.add('release:${outcome.name}');
  }
  @override
  Future<void> voidOrder(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
    Map<String, dynamic>? authorization,
  }) async {
    calls.add('void:$orderUuid');
  }
}
