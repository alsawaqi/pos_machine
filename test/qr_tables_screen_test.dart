import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/qr_tables_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'package:pos_machine/services/session_service.dart';

const _floors = [DiningFloor(id: '1', label: 'Main floor')];
const _tables = [
  DiningTableDefinition(
    id: '1',
    floorId: '1',
    name: 'Table 1',
    sizeLabel: '2 seats',
    seats: 2,
    sortOrder: 1,
  ),
  DiningTableDefinition(
    id: '2',
    floorId: '1',
    name: 'Table 2',
    sizeLabel: '2 seats',
    seats: 2,
    sortOrder: 2,
  ),
  DiningTableDefinition(
    id: '3',
    floorId: '1',
    name: 'Table 3',
    sizeLabel: '4 seats',
    seats: 4,
    sortOrder: 3,
  ),
  DiningTableDefinition(
    id: '4',
    floorId: '1',
    name: 'Table 4',
    sizeLabel: '4 seats',
    seats: 4,
    sortOrder: 4,
  ),
  DiningTableDefinition(
    id: '5',
    floorId: '1',
    name: 'Table 5',
    sizeLabel: '6 seats',
    seats: 6,
    sortOrder: 5,
  ),
  DiningTableDefinition(
    id: '6',
    floorId: '1',
    name: 'Table 6',
    sizeLabel: '6 seats',
    seats: 6,
    sortOrder: 6,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('temp-only QR references appear on the table card and detail badge', (tester) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open', numbered: false, tempReference: 'T-0905-012')],
      active: [_activeOrder(numbered: false, tempReference: 'T-0905-012')],
    );
    await _pumpBoard(tester, service: service);
    expect(find.text('T-0905-012'), findsOneWidget);
    await _selectTable(tester, '3');
    expect(find.text('T-0905-012'), findsNWidgets(2));
    expect(find.text('QR order'), findsNothing);
    expect(find.text('QR-0003'), findsNothing);
    await _disposeBoard(tester);
  });

  for (final references in [
    (receipt: null, temp: 'T-0905-012', expected: 'T-0905-012'),
    (receipt: 'QR-0001', temp: 'T-0905-012', expected: 'QR-0001'),
    (receipt: null, temp: null, expected: null),
  ]) {
    testWidgets('settlement claim reference is ${references.expected ?? 'hidden'}', (tester) async {
      final service = _FakeTillGateway(
        board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
        active: [_activeOrder()],
      );
      final flow = _FakeSettlementFlow(
        claimValue: _claim('order-3', receiptNumber: references.receipt, tempReference: references.temp),
      );
      await _pumpBoard(tester, service: service, flow: flow);
      await _selectTable(tester, '3');
      await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
      await tester.pump();
      final reference = find.byKey(const ValueKey('qr-claim-reference'));
      if (references.expected == null) {
        expect(reference, findsNothing);
      } else {
        expect(reference, findsOneWidget);
        expect(tester.widget<Text>(reference).data, references.expected);
      }
      expect(find.byKey(const ValueKey('qr-frozen-amount')), findsOneWidget);
      await _disposeBoard(tester);
    });
  }

  testWidgets('fallback merges the temporary reference before the delayed settlement claim', (tester) async {
    final service = _FakeTillGateway(
      board: [_row(id: 5, sessionStatus: 'expired', orderStatus: 'awaiting_payment', orphaned: true, numbered: false)],
      fallbackResult: const QrOrderActionResult(
        orderUuid: 'order-5',
        status: 'held',
        tempReference: 'T-0905-012',
      ),
    );
    final claim = Completer<QrSettlementClaim>();
    final flow = _FakeSettlementFlow(delayedClaim: claim);
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '5');
    await tester.tap(find.byKey(const ValueKey('qr-action-fallback')));
    await tester.pump();
    expect(find.text('T-0905-012'), findsNWidgets(2));
    expect(flow.calls, ['claim:order-5']);
    claim.complete(_claim('order-5', tempReference: 'T-0905-012'));
    await tester.pump();
    expect(find.byKey(const ValueKey('qr-claim-reference')), findsOneWidget);
    await _disposeBoard(tester);
  });

  test(
    'classifier does not mistake an archived active table for an orphan',
    () {
      final archivedActive = _row(
        id: 8,
        sessionStatus: 'active',
        tableDeleted: true,
        orderStatus: 'open',
      );

      expect(
        qrTableDisplayStateFor(archivedActive),
        QrTableDisplayState.active,
      );
    },
  );

  testWidgets('merges configured free tables and renders all six states', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(id: 2, sessionStatus: 'pending'),
        _row(id: 3, sessionStatus: 'active', orderStatus: 'open'),
        _row(id: 4, sessionStatus: 'ordered', orderStatus: 'awaiting_payment'),
        _row(
          id: 5,
          sessionStatus: 'expired',
          orderStatus: 'open',
          orphaned: true,
        ),
        _row(
          id: 6,
          sessionStatus: null,
          sessionUuid: null,
          orderStatus: 'open',
          orphaned: true,
          tableDeleted: true,
        ),
      ],
    );
    await _pumpBoard(tester, service: service);

    expect(find.byKey(const ValueKey('qr-state-free')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-state-awaitingFirstScan')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('qr-state-active')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-state-paymentRequested')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('qr-state-orphanedExpired')),
      findsOneWidget,
    );

    // The soft-deleted opener remains visible on the explicit archive floor.
    await tester.tap(
      find.byKey(const ValueKey('qr-floor-__archived_qr_tables__')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('qr-state-orphanedMissingSession')),
      findsOneWidget,
    );
    expect(find.text('Archived table'), findsOneWidget);
    await _disposeBoard(tester);
  });

  testWidgets('detail is read-only and claim precedes the frozen bare tender', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final flow = _FakeSettlementFlow();
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '3');

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
    await _disposeBoard(tester);
  });

  testWidgets('expired claim disables cash and card and never starts tender', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final flow = _FakeSettlementFlow(
      claimValue: QrSettlementClaim(
        orderUuid: 'order-3',
        frozenAmountBaisas: 4750,
        status: 'claimed',
        deadlineAt: DateTime.now().subtract(const Duration(seconds: 1)),
      ),
    );
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();

    expect(find.byKey(const ValueKey('qr-claim-expired')), findsOneWidget);
    final cash = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('qr-tender-cash')),
    );
    final card = tester.widget<FilledButton>(
      find.byKey(const ValueKey('qr-tender-card')),
    );
    expect(cash.onPressed, isNull);
    expect(card.onPressed, isNull);
    expect(flow.calls, ['claim:order-3']);

    await tester.tap(find.byKey(const ValueKey('qr-abandon-claim')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-confirm-abandon')));
    await tester.pump();
    expect(flow.calls, ['claim:order-3', 'release:cancelled']);
    await _disposeBoard(tester);
  });

  testWidgets('a refused competing claim exposes no tender', (tester) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final flow = _FakeSettlementFlow(
      claimError: ApiException(
        message: 'claimed',
        statusCode: 409,
        code: 'charge_already_claimed',
      ),
    );
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();

    expect(flow.calls, ['claim:order-3']);
    expect(find.byKey(const ValueKey('qr-settlement-sheet')), findsNothing);
    expect(find.byKey(const ValueKey('qr-tender-card')), findsNothing);
    await _disposeBoard(tester);
  });

  for (final missingSession in [false, true]) {
    testWidgets(
      '${missingSession ? 'missing-session' : 'expired'} orphan falls back before claim and tender',
      (tester) async {
        final service = _FakeTillGateway(
          board: [
            _row(
              id: 5,
              sessionStatus: missingSession ? null : 'expired',
              sessionUuid: missingSession ? null : 'session-5',
              orderStatus: 'awaiting_payment',
              orphaned: true,
            ),
          ],
        );
        final timeline = <String>[];
        service.timeline = timeline;
        final flow = _FakeSettlementFlow(timeline: timeline);
        await _pumpBoard(tester, service: service, flow: flow);
        await _selectTable(tester, '5');

        expect(find.byKey(const ValueKey('qr-action-settle')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('qr-action-fallback')));
        await tester.pump();
        expect(timeline, ['fallback:order-5', 'claim:order-5']);
        expect(
          find.byKey(const ValueKey('qr-settlement-sheet')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('qr-tender-cash')));
        await tester.pump();
        expect(timeline, ['fallback:order-5', 'claim:order-5', 'settle:cash']);
        await _disposeBoard(tester);
      },
    );
  }

  testWidgets('held orphan after restart claims without repeating fallback', (
    tester,
  ) async {
    final timeline = <String>[];
    final service = _FakeTillGateway(
      board: [
        _row(
          id: 5,
          sessionStatus: 'expired',
          orderStatus: 'held',
          orphaned: true,
        ),
      ],
    )..timeline = timeline;
    final flow = _FakeSettlementFlow(timeline: timeline);
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '5');

    expect(
      find.byKey(const ValueKey('qr-action-settle-recovered')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('qr-action-settle-recovered')));
    await tester.pump();
    expect(timeline, ['claim:order-5']);
    await tester.tap(find.byKey(const ValueKey('qr-tender-card')));
    await tester.pump();
    expect(timeline, ['claim:order-5', 'settle:card']);
    await _disposeBoard(tester);
  });

  testWidgets('fresh awaiting board status wins over stale active detail', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    await _pumpBoard(tester, service: service, clock: () => now);
    await _selectTable(tester, '3');
    expect(find.text('Long server-priced product name'), findsOneWidget);

    service.board = [
      _row(id: 3, sessionStatus: 'ordered', orderStatus: 'awaiting_payment'),
    ];
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(find.byKey(const ValueKey('qr-action-settle')), findsNothing);
    expect(find.byKey(const ValueKey('qr-action-void')), findsNothing);
    expect(find.byKey(const ValueKey('qr-action-reopen')), findsOneWidget);
    expect(find.text('Long server-priced product name'), findsNothing);
    expect(find.textContaining('Customer ID'), findsNothing);
    expect(find.text('QR-0003'), findsWidgets);
    expect(find.text('OMR 4.750'), findsWidgets);
    await _disposeBoard(tester);
  });

  testWidgets('void is standalone, terminal board then exposes clear', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final timeline = <String>[];
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    )..timeline = timeline;
    final flow = _FakeSettlementFlow(
      timeline: timeline,
      onVoid: () {
        service.board = [
          _row(id: 3, sessionStatus: 'ordered', orderStatus: 'voided'),
        ];
      },
    );
    await _pumpBoard(tester, service: service, flow: flow, clock: () => now);
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-action-void')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-confirm-void')));
    await tester.pump();
    expect(timeline, ['void:order-3']);

    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.byKey(const ValueKey('qr-action-clear')), findsOneWidget);
    // The void-success snackbar intentionally overlays the action rail for a
    // moment; wait for that operator feedback before pressing Clear.
    await tester.pump(const Duration(seconds: 5));
    final clearButton = find.descendant(
      of: find.byKey(const ValueKey('qr-action-clear')),
      matching: find.byType(FilledButton),
    );
    expect(clearButton, findsOneWidget);
    final renderedClear = tester.widget<FilledButton>(clearButton);
    expect(renderedClear.onPressed, isNotNull);
    renderedClear.onPressed!();
    await tester.pump();
    expect(timeline, ['void:order-3', 'clear:3']);
    await _disposeBoard(tester);
  });

  testWidgets('live awaiting order invokes only the reopen seam', (
    tester,
  ) async {
    final timeline = <String>[];
    final service = _FakeTillGateway(
      board: [
        _row(id: 4, sessionStatus: 'ordered', orderStatus: 'awaiting_payment'),
      ],
    )..timeline = timeline;
    await _pumpBoard(tester, service: service);
    await _selectTable(tester, '4');
    await tester.tap(find.byKey(const ValueKey('qr-action-reopen')));
    await tester.pump();
    expect(timeline, ['reopen:order-4']);
    await _disposeBoard(tester);
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
    await _pumpBoard(tester, service: service);
    await _selectTable(tester, '4');
    await tester.tap(find.byKey(const ValueKey('qr-action-reopen')));
    await tester.pump();

    expect(
      find.text('This order cannot be reopened for more rounds.'),
      findsOneWidget,
    );
    expect(find.text('raw server text'), findsNothing);
    await _disposeBoard(tester);
  });

  testWidgets('disposal after a delayed claim best-effort releases it', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final completer = Completer<QrSettlementClaim>();
    final flow = _FakeSettlementFlow(delayedClaim: completer);
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    completer.complete(_claim('order-3'));
    await tester.pump();
    expect(flow.calls, ['claim:order-3', 'release:cancelled']);
  });

  testWidgets('back during delayed settlement never releases the claim', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [_row(id: 3, sessionStatus: 'active', orderStatus: 'open')],
      active: [_activeOrder()],
    );
    final settle = Completer<QrSettlementResult>();
    final flow = _FakeSettlementFlow(delayedSettlement: settle);
    await _pumpBoard(tester, service: service, flow: flow);
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-tender-card')));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(flow.calls, ['claim:order-3', 'settle:card']);
    expect(find.byKey(const ValueKey('qr-tables-screen')), findsOneWidget);
    expect(find.textContaining('Payment is in progress'), findsOneWidget);

    settle.complete(_paid(_claim('order-3')));
    await tester.pump();
    expect(flow.calls.where((call) => call.startsWith('release:')), isEmpty);
    await _disposeBoard(tester);
  });

  testWidgets(
    'post-capture recovery survives disposal and surfaces on next entry',
    (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      final preferences = await SharedPreferences.getInstance();
      final service = _FakeTillGateway(
        board: [
          _row(id: 3, sessionStatus: 'active', orderStatus: 'open'),
          _row(id: 4, sessionStatus: 'active', orderStatus: 'open'),
        ],
        active: [_activeOrder(), _activeOrder(id: 4)],
      );
      final settle = Completer<QrSettlementResult>();
      final flow = _FakeSettlementFlow(delayedSettlement: settle);
      final showBoard = ValueNotifier<bool>(true);
      addTearDown(showBoard.dispose);
      tester.view.physicalSize = const Size(1500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            qrTillServiceProvider.overrideWithValue(service),
            qrSettlementCoordinatorProvider.overrideWithValue(flow),
            sessionServiceProvider.overrideWithValue(
              SessionService(const FlutterSecureStorage(), preferences),
            ),
          ],
          child: ValueListenableBuilder<bool>(
            valueListenable: showBoard,
            builder: (_, visible, _) => MaterialApp(
              home: visible
                  ? const QrTablesScreen(
                      key: ValueKey('recovery-board'),
                      floors: _floors,
                      tables: _tables,
                    )
                  : const SizedBox.shrink(key: ValueKey('board-disposed')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await _selectTable(tester, '3');
      await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('qr-tender-card')));
      await tester.pump();

      showBoard.value = false;
      await tester.pump();

      // A replacement route can appear before the first terminal call returns.
      // The app-scoped flow must stop that screen before a second tender.
      showBoard.value = true;
      await tester.pump();
      await tester.pump();
      await _selectTable(tester, '4');
      await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
      await tester.pump();
      expect(flow.calls.where((call) => call == 'settle:card'), hasLength(1));
      showBoard.value = false;
      await tester.pump();

      settle.complete(
        QrSettlementResult(
          kind: QrSettlementResultKind.cardUncertain,
          claim: _claim('order-3'),
          serverError: 'Payment app not responding.',
        ),
      );
      await tester.pump();
      expect(flow.pendingManagerRecoveries, hasLength(1));

      showBoard.value = true;
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Unknown card outcome — manager required'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Do not retry or take a second payment'),
        findsOneWidget,
      );

      await tester.tap(find.text('I understand'));
      await tester.pump();
      await _selectTable(tester, '4');
      final claimsBeforeDisabledTap = flow.calls
          .where((call) => call == 'claim:order-4')
          .length;
      await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
      await tester.pump();
      expect(
        flow.calls.where((call) => call == 'claim:order-4'),
        hasLength(claimsBeforeDisabledTap),
      );
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('qr-manager-takeover-warning')),
        findsOneWidget,
      );
      await tester.tap(find.text('Stay'));
      await tester.pump();
      expect(flow.pendingManagerRecoveries, hasLength(1));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('qr-manager-took-over')));
      await tester.pump();
      expect(flow.pendingManagerRecoveries, isEmpty);
      showBoard.value = false;
      await tester.pump();
    },
  );

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
      await _pumpBoard(tester, service: service, flow: flow);
      await _selectTable(tester, '3');
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
      await _disposeBoard(tester);
    });
  }

  testWidgets('polls only in foreground and honors Retry-After', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final service = _FakeTillGateway(board: const []);
    service.boardErrors.add(
      ApiException(
        message: 'slow down',
        statusCode: 429,
        code: 'rate_limited',
        retryAfter: const Duration(seconds: 30),
      ),
    );
    await _pumpBoard(tester, service: service, clock: () => now);
    expect(service.boardCalls, 1);

    now = now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    await tester.tap(find.byKey(const ValueKey('qr-board-refresh')));
    await tester.pump();
    expect(service.boardCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(service.boardCalls, 1);

    now = now.add(const Duration(seconds: 13));
    await tester.pump(const Duration(seconds: 13));
    expect(service.boardCalls, 1);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(service.boardCalls, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(service.boardCalls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(service.boardCalls, 3);
    await _disposeBoard(tester);
  });

  testWidgets('pending round detail confirms and prints from server response', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(
          id: 3,
          sessionStatus: 'active',
          orderStatus: 'open',
          pendingRounds: const [
            QrPendingRound(
              id: 41,
              roundNo: 2,
              subtotalBaisas: 4750,
              taxBaisas: 0,
              totalBaisas: 4750,
            ),
          ],
        ),
      ],
      active: [_activeOrder()],
    );
    final rounds = _FakeRoundGateway();
    final printer = _FakeRoundPrinter();
    await _pumpBoard(
      tester,
      service: service,
      roundGateway: rounds,
      roundPrinter: printer,
    );
    await _selectTable(tester, '3');

    await tester.tap(find.byKey(const ValueKey('qr-pending-round-41')));
    await tester.pump();
    expect(find.textContaining('No sugar'), findsOneWidget);
    expect(find.text('OMR 4.750'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('qr-round-confirm')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('qr-round-confirm-confirmation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('qr-round-confirm-proceed')));
    await tester.pump();
    await tester.pump();

    expect(rounds.calls, ['fetch:41', 'confirm:41']);
    expect(printer.ids, [41]);
    expect(
      find.text('Round confirmed and added to the order.'),
      findsOneWidget,
    );
    await _disposeBoard(tester);
  });

  testWidgets('confirm truth survives printer failure and retry', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(
          id: 3,
          sessionStatus: 'active',
          orderStatus: 'open',
          pendingRounds: const [
            QrPendingRound(
              id: 41,
              roundNo: 2,
              subtotalBaisas: 4750,
              taxBaisas: 0,
              totalBaisas: 4750,
            ),
          ],
        ),
      ],
      active: [_activeOrder()],
    );
    final rounds = _FakeRoundGateway();
    final printer = _FakeRoundPrinter(outcomes: [false, true]);
    await _pumpBoard(
      tester,
      service: service,
      roundGateway: rounds,
      roundPrinter: printer,
    );
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-pending-round-41')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-confirm')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-confirm-proceed')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('qr-round-print-failed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('qr-round-retry-print')));
    await tester.pump();
    await tester.pump();

    expect(rounds.calls.where((call) => call == 'confirm:41'), hasLength(1));
    expect(printer.ids, [41, 41]);
    await _disposeBoard(tester);
  });

  testWidgets('reject is confirmed, un-gated, and never prints', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(
          id: 3,
          sessionStatus: 'active',
          orderStatus: 'open',
          pendingRounds: const [
            QrPendingRound(
              id: 41,
              roundNo: 2,
              subtotalBaisas: 4750,
              taxBaisas: 0,
              totalBaisas: 4750,
            ),
          ],
        ),
      ],
      active: [_activeOrder()],
    );
    final rounds = _FakeRoundGateway();
    final printer = _FakeRoundPrinter();
    await _pumpBoard(
      tester,
      service: service,
      roundGateway: rounds,
      roundPrinter: printer,
    );
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-pending-round-41')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-reject')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-reject-proceed')));
    await tester.pump();
    await tester.pump();

    expect(rounds.calls, ['fetch:41', 'reject:41']);
    expect(printer.ids, isEmpty);
    expect(find.text('Round rejected. No items were added.'), findsOneWidget);
    await _disposeBoard(tester);
  });

  testWidgets('confirm race renders qr_round_not_pending and refreshes', (
    tester,
  ) async {
    final service = _FakeTillGateway(
      board: [
        _row(
          id: 3,
          sessionStatus: 'active',
          orderStatus: 'open',
          pendingRounds: const [
            QrPendingRound(
              id: 41,
              roundNo: 2,
              subtotalBaisas: 4750,
              taxBaisas: 0,
              totalBaisas: 4750,
            ),
          ],
        ),
      ],
      active: [_activeOrder()],
    );
    final rounds = _FakeRoundGateway(
      confirmError: ApiException(
        message: 'lost race',
        code: 'qr_round_not_pending',
        statusCode: 409,
      ),
    );
    await _pumpBoard(
      tester,
      service: service,
      roundGateway: rounds,
      roundPrinter: _FakeRoundPrinter(),
    );
    await _selectTable(tester, '3');
    await tester.tap(find.byKey(const ValueKey('qr-pending-round-41')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-confirm')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-round-confirm-proceed')));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('already confirmed'), findsOneWidget);
    expect(service.boardCalls, greaterThanOrEqualTo(2));
    await _disposeBoard(tester);
  });
}

Future<void> _pumpBoard(
  WidgetTester tester, {
  required _FakeTillGateway service,
  _FakeSettlementFlow? flow,
  _FakeRoundGateway? roundGateway,
  _FakeRoundPrinter? roundPrinter,
  DateTime Function()? clock,
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
        kitchenPrintGatewayProvider.overrideWithValue(_FakeKitchenClaims()),
        qrSettlementCoordinatorProvider.overrideWithValue(
          flow ?? _FakeSettlementFlow(),
        ),
        if (roundGateway != null)
          qrRoundGatewayProvider.overrideWithValue(roundGateway),
        if (roundPrinter != null)
          qrKitchenRoundPrinterProvider.overrideWithValue(roundPrinter),
        sessionServiceProvider.overrideWithValue(
          SessionService(const FlutterSecureStorage(), preferences),
        ),
      ],
      child: MaterialApp(
        home: QrTablesScreen(floors: _floors, tables: _tables, clock: clock),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _selectTable(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('qr-table-$id')));
  await tester.pump();
  await tester.pump();
}

Future<void> _disposeBoard(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  await tester.pump();
}

QrTableBoardRow _row({
  required int id,
  String? sessionStatus,
  String? sessionUuid = 'session',
  String? orderStatus,
  bool orphaned = false,
  bool tableDeleted = false,
  bool numbered = true,
  String? tempReference,
  List<QrPendingRound> pendingRounds = const [],
}) => QrTableBoardRow(
  tableId: id,
  tableLabel: 'Table $id',
  tableStatus: 'available',
  tableDeleted: tableDeleted,
  orphaned: orphaned,
  pendingRounds: pendingRounds,
  sessionUuid: sessionUuid,
  sessionStatus: sessionStatus,
  expiresAt: sessionStatus == 'expired'
      ? DateTime.now().subtract(const Duration(minutes: 1))
      : DateTime.now().add(const Duration(hours: 1)),
  order: orderStatus == null
      ? null
      : QrBoardOrder(
          uuid: 'order-$id',
          status: orderStatus,
          receiptNumber: numbered ? 'QR-${id.toString().padLeft(4, '0')}' : null,
          tempReference: tempReference,
          acceptedTotalBaisas: 4750,
        ),
);

QrActiveOrder _activeOrder({
  int id = 3,
  bool numbered = true,
  String? tempReference,
}) => QrActiveOrder(
  uuid: 'order-$id',
  status: 'open',
  source: 'qr_web',
  tableId: id,
  customerId: 42,
  plateNumber: 'OM 1234',
  receiptNumber: numbered ? 'QR-${id.toString().padLeft(4, '0')}' : null,
  tempReference: tempReference,
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

QrSettlementClaim _claim(
  String orderUuid, {
  String? receiptNumber,
  String? tempReference,
}) => QrSettlementClaim(
  orderUuid: orderUuid,
  frozenAmountBaisas: 4750,
  status: 'claimed',
  receiptNumber: receiptNumber,
  tempReference: tempReference,
  deadlineAt: DateTime.now().add(const Duration(minutes: 2)),
);

QrSettlementResult _paid(QrSettlementClaim claim) => QrSettlementResult(
  kind: QrSettlementResultKind.paid,
  claim: claim,
  clientEventId: 'event-1',
);

class _FakeTillGateway implements QrTillGateway {
  _FakeTillGateway({
    this.board = const [],
    this.active = const [],
    this.reopenError,
    this.fallbackResult,
  });

  List<QrTableBoardRow> board;
  List<QrActiveOrder> active;
  int boardCalls = 0;
  final List<Object> boardErrors = [];
  final Object? reopenError;
  final QrOrderActionResult? fallbackResult;
  List<String>? timeline;

  @override
  Future<List<QrTableBoardRow>> fetchTableBoard() async {
    boardCalls += 1;
    if (boardErrors.isNotEmpty) throw boardErrors.removeAt(0);
    return board;
  }

  @override
  Future<List<QrActiveOrder>> fetchActiveQrOrders() async => active;

  @override
  Future<QrActiveOrder?> activeQrOrder(String orderUuid) async {
    for (final order in active) {
      if (order.uuid == orderUuid) return order;
    }
    return null;
  }

  @override
  Future<QrSettlementClaim> claimSettlement(
    String orderUuid, {
    double? lat,
    double? lng,
  }) async => _claim(orderUuid);

  @override
  Future<void> releaseSettlement(
    String orderUuid,
    QrReleaseOutcome outcome, {
    String? softposReference,
    String? softposAuthCode,
    Map<String, dynamic>? bankResponse,
  }) async {}

  @override
  Future<QrOrderActionResult> reopenPayment(String orderUuid) async {
    timeline?.add('reopen:$orderUuid');
    if (reopenError != null) throw reopenError!;
    return QrOrderActionResult(orderUuid: orderUuid, status: 'open');
  }

  @override
  Future<QrOrderActionResult> fallbackToCounter(String orderUuid) async {
    timeline?.add('fallback:$orderUuid');
    return fallbackResult ?? QrOrderActionResult(orderUuid: orderUuid, status: 'held');
  }

  @override
  Future<void> clearTable(int tableId) async {
    timeline?.add('clear:$tableId');
  }
}

class _FakeRoundGateway implements QrRoundGateway {
  _FakeRoundGateway({this.confirmError});

  final Object? confirmError;
  final List<String> calls = [];

  @override
  Future<QrRoundEnvelope> fetchRound(int roundId) async {
    calls.add('fetch:$roundId');
    return _roundEnvelope(roundId, status: 'pending_confirmation');
  }

  @override
  Future<QrRoundEnvelope> confirmRound(int roundId) async {
    calls.add('confirm:$roundId');
    if (confirmError != null) throw confirmError!;
    return _roundEnvelope(roundId, status: 'accepted');
  }

  @override
  Future<QrRoundEnvelope> rejectRound(int roundId) async {
    calls.add('reject:$roundId');
    return _roundEnvelope(roundId, status: 'rejected');
  }

  @override
  Future<QrAcceptedRoundsPage> fetchAcceptedRounds({
    String? after,
    int limit = 25,
  }) async => const QrAcceptedRoundsPage(rounds: [], skippedExpiredCount: 0);
}

class _FakeKitchenClaims implements KitchenPrintGateway {
  @override
  Future<QrKitchenTicket> claim(String ticketKey) async => QrKitchenTicket(
    ticketKey: ticketKey, roundId: int.parse(ticketKey.split(':').last),
    orderUuid: 'order-3', replayed: false, pricedLines: const [],
  );

  @override
  Future<void> recordResult({
    required String ticketKey,
    required String printResult,
    required DateTime? printedAt,
  }) async {}
}

class _FakeRoundPrinter implements QrKitchenRoundPrinter {
  _FakeRoundPrinter({List<bool>? outcomes}) : _outcomes = outcomes ?? [];

  final List<bool> _outcomes;
  final List<int> ids = [];

  @override
  Future<bool> printRound(
    QrRoundEnvelope envelope, {
    required bool arabic,
  }) async {
    ids.add(envelope.round.id);
    return _outcomes.isEmpty ? true : _outcomes.removeAt(0);
  }
}

QrRoundEnvelope _roundEnvelope(int id, {required String status}) =>
    QrRoundEnvelope(
      round: QrDeviceRound(
        id: id,
        roundNo: 2,
        status: status,
        lines: const [
          QrRoundDisplayLine(
            name: 'Frozen coffee',
            nameAr: 'قهوة مجمدة',
            quantity: 1,
            unitPriceBaisas: 4750,
            lineDiscountBaisas: 0,
            lineTotalBaisas: 4750,
            notes: 'No sugar',
            addons: [],
          ),
        ],
        subtotalBaisas: 4750,
        taxBaisas: 0,
        totalBaisas: 4750,
        resolvedAt: DateTime.utc(2026, 8, 31, 12),
      ),
      orderUuid: 'order-3',
      sessionUuid: 'session',
      tableLabel: 'Table 3',
      receiptNumber: 'QR-0003',
    );

class _FakeSettlementFlow implements QrSettlementFlow {
  _FakeSettlementFlow({
    this.claimValue,
    this.claimError,
    this.delayedClaim,
    this.delayedSettlement,
    this.timeline,
    this.onVoid,
    this.settleResult,
  });

  final QrSettlementClaim? claimValue;
  final Object? claimError;
  final Completer<QrSettlementClaim>? delayedClaim;
  final Completer<QrSettlementResult>? delayedSettlement;
  final List<String>? timeline;
  final VoidCallback? onVoid;
  final QrSettlementResult Function(QrSettlementClaim, QrTender)? settleResult;
  final List<String> calls = [];
  final Map<String, QrSettlementResult> _pendingManagerRecoveries = {};
  bool _settlementInFlight = false;

  @override
  List<QrSettlementResult> get pendingManagerRecoveries =>
      List.unmodifiable(_pendingManagerRecoveries.values);

  @override
  void acknowledgeManagerRecovery(String orderUuid) {
    calls.add('acknowledge:$orderUuid');
    _pendingManagerRecoveries.remove(orderUuid);
  }

  @override
  Future<QrSettlementClaim> claim(String orderUuid) async {
    calls.add('claim:$orderUuid');
    timeline?.add('claim:$orderUuid');
    if (_settlementInFlight || _pendingManagerRecoveries.isNotEmpty) {
      throw QrPaymentAttemptUnresolved(orderUuid);
    }
    if (claimError != null) throw claimError!;
    if (delayedClaim != null) return delayedClaim!.future;
    return claimValue ?? _claim(orderUuid);
  }

  @override
  Future<QrSettlementResult> settleClaim(
    QrSettlementClaim claim,
    QrTender tender,
  ) async {
    calls.add('settle:${tender.name}');
    timeline?.add('settle:${tender.name}');
    _settlementInFlight = true;
    try {
      final result = delayedSettlement != null
          ? await delayedSettlement!.future
          : settleResult?.call(claim, tender) ?? _paid(claim);
      if (result.managerRequired || result.releaseError != null) {
        _pendingManagerRecoveries[claim.orderUuid] = result;
      }
      return result;
    } finally {
      _settlementInFlight = false;
    }
  }

  @override
  Future<void> releaseClaim(
    QrSettlementClaim claim,
    QrReleaseOutcome outcome, {
    Object? terminalResult,
  }) async {
    calls.add('release:${outcome.name}');
    timeline?.add('release:${outcome.name}');
  }

  @override
  Future<void> voidOrder(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  }) async {
    calls.add('void:$orderUuid');
    timeline?.add('void:$orderUuid');
    onVoid?.call();
  }
}
