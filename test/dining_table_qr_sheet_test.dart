import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/dining_table_qr_sheet.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:pos_machine/widgets/qr_table_money_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // These are the four expanded cases from the untouched panel-host test,
  // mounted through the real sheet and retaining every original assertion.
  testWidgets(
    'sheet detail is read-only and claim precedes the frozen bare tender',
    (tester) async {
      final service = T7SheetGateway(
        board: [
          t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
        ],
        active: [t7SheetActiveOrder()],
      );
      final flow = T7SheetFlow();
      final controller = await pumpT7Sheet(
        tester,
        service: service,
        flow: flow,
      );
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
      expect(controller.calls, isEmpty);
      expect(controller.cart, isEmpty);
      await disposeT7Sheet(tester);
    },
  );

  testWidgets('sheet staff action refusal uses mapped actionable copy', (
    tester,
  ) async {
    final service = T7SheetGateway(
      board: [
        t7SheetRow(
          id: 4,
          sessionStatus: 'ordered',
          orderStatus: 'awaiting_payment',
        ),
      ],
      reopenError: ApiException(
        message: 'raw server text',
        statusCode: 409,
        code: 'qr_order_not_reopenable',
      ),
    );
    await pumpT7Sheet(tester, service: service, tableId: 4);
    await tester.tap(find.byKey(const ValueKey('qr-action-reopen')));
    await tester.pump();
    expect(
      find.text('This order cannot be reopened for more rounds.'),
      findsOneWidget,
    );
    expect(find.text('raw server text'), findsNothing);
    await disposeT7Sheet(tester);
  });

  for (final scenario in ['awaiting acknowledgement', 'release failure']) {
    testWidgets('sheet $scenario keeps route locked for manager takeover', (
      tester,
    ) async {
      final service = T7SheetGateway(
        board: [
          t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
        ],
        active: [t7SheetActiveOrder()],
      );
      final flow = T7SheetFlow(
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
      final controller = await pumpT7Sheet(
        tester,
        service: service,
        flow: flow,
      );
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
      expect(controller.calls, isEmpty);
      expect(controller.cart, isEmpty);
      await disposeT7Sheet(tester);
    });
  }

  for (final action in [
    'confirm',
    'reject',
    'cash',
    'card',
    'void',
    'clear',
    'reopen',
    'fallback',
  ]) {
    testWidgets(
      'G5 sheet $action leaves every controller method untouched and cart empty',
      (tester) async {
        final service = T7SheetGateway(
          board: [
            t7SheetRow(
              id: 3,
              sessionStatus: action == 'reopen' ? 'ordered' : 'active',
              orderStatus: action == 'clear'
                  ? 'paid'
                  : action == 'reopen'
                  ? 'awaiting_payment'
                  : 'open',
              orphaned: action == 'fallback',
              pendingRounds: action == 'confirm' || action == 'reject'
                  ? const [
                      QrPendingRound(
                        id: 41,
                        roundNo: 2,
                        subtotalBaisas: 4750,
                        taxBaisas: 0,
                        totalBaisas: 4750,
                      ),
                    ]
                  : const [],
            ),
          ],
          active: [t7SheetActiveOrder()],
        );
        final flow = T7SheetFlow();
        final controller = await pumpT7Sheet(
          tester,
          service: service,
          flow: flow,
        );
        if (action == 'confirm' || action == 'reject') {
          await _tap(tester, 'qr-pending-round-41');
          await _tap(tester, 'qr-round-$action');
          await _tap(tester, 'qr-round-$action-proceed');
          expect(service.calls, containsAllInOrder(['fetch:41', '$action:41']));
        } else if (action == 'cash' || action == 'card') {
          await _tap(tester, 'qr-action-settle');
          expect(flow.calls, ['claim:order-3']);
          await _tap(tester, 'qr-tender-$action');
          expect(flow.calls, ['claim:order-3', 'settle:$action']);
        } else if (action == 'void') {
          await _tap(tester, 'qr-action-void');
          await _tap(tester, 'qr-confirm-void');
          expect(flow.calls, ['void:order-3']);
        } else if (action == 'fallback') {
          await _tap(tester, 'qr-action-fallback');
          expect(service.calls, contains('fallback:order-3'));
          expect(flow.calls, ['claim:order-3']);
          await _tap(tester, 'qr-tender-cash');
          expect(flow.calls, ['claim:order-3', 'settle:cash']);
        } else {
          await _tap(tester, 'qr-action-$action');
          expect(
            service.calls,
            contains(action == 'clear' ? 'clear:3' : 'reopen:order-3'),
          );
        }
        expect(
          controller.calls,
          isEmpty,
          reason: 'G5: $action must never call the till controller.',
        );
        expect(
          controller.cart,
          isEmpty,
          reason: 'G5: $action must never import server-priced lines.',
        );
        debugPrint(
          'T7_G5_$action controller_calls=${controller.calls} cart_items=${controller.cart.length}',
        );
        await disposeT7Sheet(tester);
      },
    );
  }

  testWidgets('sheet selects only the tapped table and never another bill', (
    tester,
  ) async {
    final service = T7SheetGateway(
      board: [
        t7SheetRow(id: 4, sessionStatus: 'active', orderStatus: 'open'),
        t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
      ],
      active: [
        t7SheetActiveOrder(id: 4, productName: 'Other table private line'),
        t7SheetActiveOrder(),
      ],
    );
    final flow = T7SheetFlow();
    await pumpT7Sheet(tester, service: service, flow: flow);
    expect(find.byKey(const ValueKey('qr-detail-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('qr-detail-4')), findsNothing);
    expect(find.text('Other table private line'), findsNothing);
    expect(find.text('Long server-priced product name'), findsOneWidget);
    await _tap(tester, 'qr-action-settle');
    expect(flow.calls, ['claim:order-3']);
    await _tap(tester, 'qr-tender-cash');
    await disposeT7Sheet(tester);
  });

  testWidgets('empty selected table never borrows the other tables actions', (
    tester,
  ) async {
    final service = T7SheetGateway(
      board: [t7SheetRow(id: 4, sessionStatus: 'active', orderStatus: 'open')],
      active: [t7SheetActiveOrder(id: 4)],
    );
    await pumpT7Sheet(tester, service: service);
    expect(find.byKey(const ValueKey('qr-action-settle')), findsNothing);
    expect(find.byKey(const ValueKey('qr-detail-4')), findsNothing);
    expect(service.calls, ['board']);
    await disposeT7Sheet(tester);
  });

  testWidgets(
    'Live Add items pops the sheet before opening the same local table once',
    (tester) async {
      final controller = T7SpyController();
      var poppedBeforeOpen = false;
      late ModalRoute<dynamic> sheetRoute;
      controller.onOpen = (_) {
        poppedBeforeOpen = !sheetRoute.isActive;
      };
      await pumpT7Sheet(
        tester,
        service: T7SheetGateway(board: []),
        controller: controller,
      );
      sheetRoute = ModalRoute.of(
        tester.element(find.byType(DiningTableQrSheet)),
      )!;
      await _tap(tester, 'table-sheet-add-items');
      expect(controller.calls, ['open:3']);
      expect(controller.cart, isEmpty);
      expect(poppedBeforeOpen, isTrue);
      expect(find.byType(DiningTableQrSheet), findsNothing);
      await disposeT7Sheet(tester);
    },
  );

  testWidgets(
    'Shadow separate local requires the warning and cancellation does not open',
    (tester) async {
      final controller = await pumpT7Sheet(
        tester,
        service: T7SheetGateway(board: []),
        mode: 'shadow',
      );
      await _tap(tester, 'table-sheet-add-items');
      expect(
        find.byKey(const ValueKey('table-separate-local-warning')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Opening a local table starts a separate bill'),
        findsOneWidget,
      );
      expect(controller.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.calls, isEmpty);
      expect(find.byType(DiningTableQrSheet), findsOneWidget);
      await _tap(tester, 'table-sheet-add-items');
      await _tap(tester, 'table-separate-local-confirm');
      expect(controller.calls, ['open:3']);
      expect(find.byType(DiningTableQrSheet), findsNothing);
      await disposeT7Sheet(tester);
    },
  );

  testWidgets('Close and Add items cannot bypass an in-flight claim', (
    tester,
  ) async {
    final claim = Completer<QrSettlementClaim>();
    final flow = T7SheetFlow(delayedClaim: claim);
    final controller = await pumpT7Sheet(
      tester,
      service: T7SheetGateway(
        board: [
          t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
        ],
        active: [t7SheetActiveOrder()],
      ),
      flow: flow,
    );
    await _tap(tester, 'qr-action-settle');
    await _tap(tester, 'table-sheet-close');
    expect(
      find.textContaining('server claim is still in progress'),
      findsOneWidget,
    );
    await _tap(tester, 'table-sheet-add-items');
    expect(controller.calls, isEmpty);
    expect(find.byType(DiningTableQrSheet), findsOneWidget);
    claim.complete(t7SheetClaim('order-3'));
    await tester.pumpAndSettle();
    await _tap(tester, 'qr-tender-cash');
    await disposeT7Sheet(tester);
  });

  testWidgets('settlement hides the footer and Close keeps the sheet open', (
    tester,
  ) async {
    final settlement = Completer<QrSettlementResult>();
    final flow = T7SheetFlow(delayedSettlement: settlement);
    final controller = await pumpT7Sheet(
      tester,
      service: T7SheetGateway(
        board: [
          t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
        ],
        active: [t7SheetActiveOrder()],
      ),
      flow: flow,
    );
    await _tap(tester, 'qr-action-settle');
    await _tap(tester, 'qr-tender-cash');
    expect(find.byKey(const ValueKey('table-sheet-footer')), findsNothing);
    await _tap(tester, 'table-sheet-close');
    expect(find.textContaining('Payment is in progress'), findsOneWidget);
    expect(find.byType(DiningTableQrSheet), findsOneWidget);
    expect(controller.calls, isEmpty);
    settlement.complete(t7SheetPaid(t7SheetClaim('order-3')));
    await tester.pumpAndSettle();
    await disposeT7Sheet(tester);
  });

  testWidgets(
    'Add items respects manager takeover refusal instead of opening a cart',
    (tester) async {
      final flow = T7SheetFlow(
        settleResult: (claim, _) => QrSettlementResult(
          kind: QrSettlementResultKind.awaitingServerAcknowledgement,
          claim: claim,
          clientEventId: 'durable-event',
        ),
      );
      final controller = await pumpT7Sheet(
        tester,
        service: T7SheetGateway(
          board: [
            t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
          ],
          active: [t7SheetActiveOrder()],
        ),
        flow: flow,
      );
      await _tap(tester, 'qr-action-settle');
      await _tap(tester, 'qr-tender-cash');
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await _tap(tester, 'table-sheet-add-items');
      expect(
        find.byKey(const ValueKey('qr-manager-takeover-warning')),
        findsOneWidget,
      );
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(controller.calls, isEmpty);
      expect(controller.cart, isEmpty);
      expect(find.byType(DiningTableQrSheet), findsOneWidget);
      expect(flow.calls.where((call) => call.startsWith('release:')), isEmpty);
      await disposeT7Sheet(tester);
    },
  );
  testWidgets('a mode change during the Shadow warning cancels local opening', (
    tester,
  ) async {
    final mode = ValueNotifier('shadow');
    addTearDown(mode.dispose);
    final controller = await pumpT7Sheet(
      tester,
      service: T7SheetGateway(board: []),
      modeChanges: mode,
    );
    await _tap(tester, 'table-sheet-add-items');
    mode.value = 'live';
    await tester.pump();
    await _tap(tester, 'table-separate-local-confirm');
    expect(controller.calls, isEmpty);
    expect(find.byType(DiningTableQrSheet), findsOneWidget);
    await disposeT7Sheet(tester);
  });

  testWidgets(
    'a mode change during manager takeover never opens an unwarned local table',
    (tester) async {
      final mode = ValueNotifier('live');
      addTearDown(mode.dispose);
      final flow = T7SheetFlow(
        settleResult: (claim, _) => QrSettlementResult(
          kind: QrSettlementResultKind.awaitingServerAcknowledgement,
          claim: claim,
          clientEventId: 'durable-event',
        ),
      );
      final controller = await pumpT7Sheet(
        tester,
        service: T7SheetGateway(
          board: [
            t7SheetRow(id: 3, sessionStatus: 'active', orderStatus: 'open'),
          ],
          active: [t7SheetActiveOrder()],
        ),
        flow: flow,
        modeChanges: mode,
      );
      await _tap(tester, 'qr-action-settle');
      await _tap(tester, 'qr-tender-cash');
      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      await _tap(tester, 'table-sheet-add-items');
      mode.value = 'shadow';
      await tester.pump();
      await _tap(tester, 'qr-manager-took-over');
      expect(controller.calls, isEmpty);
      expect(flow.calls, contains('acknowledge:order-3'));
      expect(find.byType(DiningTableQrSheet), findsNothing);
      await disposeT7Sheet(tester);
    },
  );
  testWidgets(
    'sheet polling needs both non-Off mode and foreground, without closing the route',
    (tester) async {
      final mode = ValueNotifier('live');
      addTearDown(mode.dispose);
      final service = T7SheetGateway(board: []);
      await pumpT7Sheet(tester, service: service, modeChanges: mode);
      expect(service.calls, ['board']);
      mode.value = 'off';
      await tester.pumpAndSettle();
      final panel = tester.widget<QrTableMoneyPanel>(
        find.byType(QrTableMoneyPanel),
      );
      await panel.forceRefresh!();
      await tester.pump(const Duration(seconds: 30));
      expect(service.calls, ['board']);
      expect(find.byType(DiningTableQrSheet), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      mode.value = 'live';
      await tester.pumpAndSettle();
      expect(service.calls, ['board']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(service.calls, ['board', 'board']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await panel.forceRefresh!();
      mode.value = 'off';
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 30));
      expect(service.calls, ['board', 'board']);
      mode.value = 'live';
      await tester.pumpAndSettle();
      expect(service.calls, ['board', 'board', 'board']);
      expect(find.byType(DiningTableQrSheet), findsOneWidget);
      await disposeT7Sheet(tester);
    },
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<T7SpyController> pumpT7Sheet(
  WidgetTester tester, {
  required T7SheetGateway service,
  T7SheetFlow? flow,
  T7SpyController? controller,
  int tableId = 3,
  String mode = 'live',
  ValueNotifier<String>? modeChanges,
}) async {
  SharedPreferences.setMockInitialValues({
    'print_kitchen_tickets': false,
    // LAUNCH-P5 — the board's void is gated by order.void_unpaid; a
    // supervisor holds that tick, so this sheet test needs no approver.
    'staff_session_json':
        '{"id":7,"name":"Test Supervisor","position":"supervisor"}',
  });
  final preferences = await SharedPreferences.getInstance();
  final spy = controller ?? T7SpyController();
  tester.view.physicalSize = const Size(1500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        if (modeChanges == null)
          tableSessionsModeProvider.overrideWithValue(mode)
        else
          tableSessionsModeProvider.overrideWith((ref) {
            void changed() => ref.invalidateSelf();
            modeChanges.addListener(changed);
            ref.onDispose(() => modeChanges.removeListener(changed));
            return modeChanges.value;
          }),
        qrTillServiceProvider.overrideWithValue(service),
        qrRoundGatewayProvider.overrideWithValue(service),
        qrSettlementCoordinatorProvider.overrideWithValue(
          flow ?? T7SheetFlow(),
        ),
        sessionServiceProvider.overrideWithValue(
          SessionService(const FlutterSecureStorage(), preferences),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('t7-sheet-launch'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DiningTableQrSheet(
                    controller: spy,
                    tableId: tableId,
                    tableLabel: 'Table $tableId',
                    floorLabel: 'Main floor',
                  ),
                ),
              ),
              child: const Text('Launch sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await _tap(tester, 't7-sheet-launch');
  return spy;
}

Future<void> disposeT7Sheet(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

class T7SpyController implements PosController {
  final List<String> calls = [];
  void Function(String tableId)? onOpen;

  @override
  List<CartItem> get cart => const [];

  @override
  Future<void> openDiningTable(String tableId) async {
    calls.add('open:$tableId');
    onOpen?.call(tableId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    throw StateError('Unexpected controller call: ${invocation.memberName}');
  }
}

QrTableBoardRow t7SheetRow({
  required int id,
  required String sessionStatus,
  required String orderStatus,
  bool orphaned = false,
  List<QrPendingRound> pendingRounds = const [],
}) => QrTableBoardRow(
  tableId: id,
  tableLabel: 'Table $id',
  tableStatus: 'available',
  tableDeleted: false,
  orphaned: orphaned,
  pendingRounds: pendingRounds,
  sessionUuid: 'session-$id',
  sessionStatus: sessionStatus,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  order: QrBoardOrder(
    uuid: 'order-$id',
    status: orderStatus,
    receiptNumber: 'QR-${id.toString().padLeft(4, '0')}',
    tempReference: 'T-0906-012',
    acceptedTotalBaisas: 4750,
  ),
);

QrActiveOrder t7SheetActiveOrder({
  int id = 3,
  String productName = 'Long server-priced product name',
}) => QrActiveOrder(
  uuid: 'order-$id',
  status: 'open',
  source: 'qr_web',
  tableId: id,
  customerId: 42,
  plateNumber: 'OM 1234',
  receiptNumber: 'QR-${id.toString().padLeft(4, '0')}',
  subtotalBaisas: 4500,
  discountTotalBaisas: 0,
  compTotalBaisas: 0,
  taxTotalBaisas: 250,
  grandTotalBaisas: 4750,
  items: [
    QrOrderItem(
      id: 1,
      productId: 11,
      name: productName,
      quantity: 1,
      unitPriceBaisas: 4750,
      lineDiscountBaisas: 0,
      lineTotalBaisas: 4750,
      status: 'accepted',
      addons: const [],
    ),
  ],
);

QrSettlementClaim t7SheetClaim(String orderUuid) => QrSettlementClaim(
  orderUuid: orderUuid,
  frozenAmountBaisas: 4750,
  status: 'claimed',
  deadlineAt: DateTime.now().add(const Duration(minutes: 2)),
);

QrSettlementResult t7SheetPaid(QrSettlementClaim claim) => QrSettlementResult(
  kind: QrSettlementResultKind.paid,
  claim: claim,
  clientEventId: 'event-1',
);

class T7SheetGateway implements QrTillGateway, QrRoundGateway {
  T7SheetGateway({
    required this.board,
    this.active = const [],
    this.reopenError,
    this.boardError,
  });

  List<QrTableBoardRow> board;
  List<QrActiveOrder> active;
  Object? reopenError;
  Object? boardError;
  final List<String> calls = [];

  @override
  Future<List<QrTableBoardRow>> fetchTableBoard() async {
    calls.add('board');
    if (boardError != null) throw boardError!;
    return board;
  }

  @override
  Future<List<QrActiveOrder>> fetchActiveQrOrders() async {
    calls.add('active');
    return active;
  }

  @override
  Future<QrOrderActionResult> reopenPayment(String orderUuid) async {
    calls.add('reopen:$orderUuid');
    if (reopenError != null) throw reopenError!;
    return QrOrderActionResult(orderUuid: orderUuid, status: 'open');
  }

  @override
  Future<QrOrderActionResult> fallbackToCounter(String orderUuid) async {
    calls.add('fallback:$orderUuid');
    return QrOrderActionResult(orderUuid: orderUuid, status: 'held');
  }

  @override
  Future<void> clearTable(int tableId) async {
    calls.add('clear:$tableId');
  }

  @override
  Future<QrRoundEnvelope> fetchRound(int roundId) async {
    calls.add('fetch:$roundId');
    return _t7RoundEnvelope(roundId, 'pending_confirmation');
  }

  @override
  Future<QrRoundEnvelope> confirmRound(int roundId) async {
    calls.add('confirm:$roundId');
    return _t7RoundEnvelope(roundId, 'accepted');
  }

  @override
  Future<QrRoundEnvelope> rejectRound(int roundId) async {
    calls.add('reject:$roundId');
    return _t7RoundEnvelope(roundId, 'rejected');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected gateway call: ${invocation.memberName}');
}

QrRoundEnvelope _t7RoundEnvelope(int id, String status) => QrRoundEnvelope(
  round: QrDeviceRound(
    id: id,
    roundNo: 2,
    status: status,
    lines: const [
      QrRoundDisplayLine(
        name: 'Frozen coffee',
        quantity: 1,
        unitPriceBaisas: 4750,
        lineDiscountBaisas: 0,
        lineTotalBaisas: 4750,
        addons: [],
      ),
    ],
    subtotalBaisas: 4750,
    taxBaisas: 0,
    totalBaisas: 4750,
  ),
  orderUuid: 'order-3',
  sessionUuid: 'session-3',
  tableLabel: 'Table 3',
);

class T7SheetFlow implements QrSettlementFlow {
  T7SheetFlow({this.settleResult, this.delayedClaim, this.delayedSettlement});

  final QrSettlementResult Function(QrSettlementClaim, QrTender)? settleResult;
  final Completer<QrSettlementClaim>? delayedClaim;
  final Completer<QrSettlementResult>? delayedSettlement;
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
    return delayedClaim?.future ?? t7SheetClaim(orderUuid);
  }

  @override
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    calls.add('settle:${tender.name}');
    final result = delayedSettlement != null
        ? await delayedSettlement!.future
        : settleResult?.call(claim, tender) ?? t7SheetPaid(claim);
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
