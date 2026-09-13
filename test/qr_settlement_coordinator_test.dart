import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/services/qr_till_service.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30, 12);

  QrSettlementClaim claim({DateTime? deadline}) => QrSettlementClaim(
    orderUuid: '11111111-1111-4111-8111-111111111111',
    frozenAmountBaisas: 4750,
    status: 'awaiting_payment',
    deadlineAt: deadline ?? now.add(const Duration(minutes: 5)),
  );

  QrSettlementCoordinator coordinator({
    required _Till till,
    required _Outbox outbox,
    required _Terminal terminal,
    DateTime Function()? clock,
  }) => QrSettlementCoordinator(
    till: till,
    outbox: outbox,
    terminal: terminal,
    location: const _Location((lat: 23.588, lng: 58.383)),
    now: clock ?? () => now,
  );

  test(
    'card settle is claim-first, revalidates, and preserves exact baisas',
    () async {
      final log = <String>[];
      final till = _Till(claim(), log: log);
      final outbox = _Outbox(log: log);
      final terminal = _Terminal(_success(), log: log);
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      final result = await flow.settleClaim(held, QrTender.card);

      expect(result.kind, QrSettlementResultKind.paid);
      expect(log, ['claim', 'claim', 'terminal', 'outbox']);
      expect(till.claimGps, everyElement((lat: 23.588, lng: 58.383)));
      expect(terminal.amounts, [4750]);
      expect(outbox.amounts, [4750]);
      expect(outbox.gps, [(lat: 23.588, lng: 58.383)]);
      expect(outbox.tenders, [QrTender.card]);
    },
  );

  test('an expired claim cannot touch the terminal or outbox', () async {
    final expired = claim(deadline: now.add(const Duration(seconds: 4)));
    final till = _Till(expired);
    final outbox = _Outbox();
    final terminal = _Terminal(_success());
    final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

    final held = await flow.claim(expired.orderUuid);
    await expectLater(
      flow.settleClaim(held, QrTender.card),
      throwsA(isA<QrSettlementClaimExpired>()),
    );

    expect(
      till.claimCalls,
      1,
      reason: 'expiry fails before server revalidation',
    );
    expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
    expect(terminal.amounts, isEmpty);
    expect(outbox.amounts, isEmpty);
  });

  test('a changed frozen amount fails before capture', () async {
    final initial = claim();
    final changed = QrSettlementClaim(
      orderUuid: initial.orderUuid,
      frozenAmountBaisas: initial.frozenAmountBaisas + 1,
      status: initial.status,
      deadlineAt: initial.deadlineAt,
      alreadyClaimedByThisDevice: true,
    );
    final till = _Till(initial, replayClaim: changed);
    final outbox = _Outbox();
    final terminal = _Terminal(_success());
    final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

    final held = await flow.claim(initial.orderUuid);
    await expectLater(
      flow.settleClaim(held, QrTender.card),
      throwsA(isA<QrSettlementClaimChanged>()),
    );
    expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
    expect(terminal.amounts, isEmpty);
    expect(outbox.amounts, isEmpty);
  });

  test(
    'a slow replay that consumes the deadline margin moves no money',
    () async {
      final initial = claim(deadline: now.add(const Duration(seconds: 6)));
      var clockReads = 0;
      final till = _Till(initial);
      final outbox = _Outbox();
      final terminal = _Terminal(_success());
      final flow = coordinator(
        till: till,
        outbox: outbox,
        terminal: terminal,
        clock: () =>
            clockReads++ == 0 ? now : now.add(const Duration(seconds: 2)),
      );

      final held = await flow.claim(initial.orderUuid);
      await expectLater(
        flow.settleClaim(held, QrTender.card),
        throwsA(isA<QrSettlementClaimExpired>()),
      );

      expect(till.claimCalls, 2);
      expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
      expect(terminal.amounts, isEmpty);
      expect(outbox.amounts, isEmpty);
    },
  );

  test(
    'failed claim replay is explicit pre-tender and releases cancelled',
    () async {
      final till = _Till(claim(), replayError: StateError('offline'));
      final outbox = _Outbox();
      final terminal = _Terminal(_success());
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      await expectLater(
        flow.settleClaim(held, QrTender.card),
        throwsA(
          isA<QrSettlementRevalidationFailed>().having(
            (error) => error.cause,
            'cause',
            isA<StateError>(),
          ),
        ),
      );

      expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
      expect(terminal.amounts, isEmpty);
      expect(outbox.amounts, isEmpty);
    },
  );

  test('an unresolved durable pay blocks a second claim and tender', () async {
    final till = _Till(claim());
    final outbox = _Outbox(unresolved: true);
    final terminal = _Terminal(_success());
    final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

    await expectLater(
      flow.claim(claim().orderUuid),
      throwsA(isA<QrPaymentAttemptUnresolved>()),
    );
    expect(till.claimCalls, 0);
    expect(terminal.amounts, isEmpty);
  });

  test(
    'explicit card cancel releases cancelled and never queues pay',
    () async {
      final till = _Till(claim());
      final outbox = _Outbox();
      final terminal = _Terminal(_cancelled());
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      final result = await flow.settleClaim(held, QrTender.card);

      expect(result.kind, QrSettlementResultKind.cardCancelledBeforeCapture);
      expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
      expect(outbox.amounts, isEmpty);
    },
  );

  test('unknown card fate releases uncertain and requires manager', () async {
    final till = _Till(claim());
    final outbox = _Outbox();
    final terminal = _Terminal(_uncertain());
    final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

    final held = await flow.claim(claim().orderUuid);
    final result = await flow.settleClaim(held, QrTender.card);

    expect(result.kind, QrSettlementResultKind.cardUncertain);
    expect(result.managerRequired, isTrue);
    expect(result.mustNotRetryTender, isTrue);
    expect(till.releases.single.outcome, QrReleaseOutcome.uncertain);
    expect(till.releases.single.bankResponse?['message'], 'NFC timeout');
    expect(outbox.amounts, isEmpty);
  });

  test(
    'post-dispatch watchdog cannot reach a second tender before manager recovery',
    () async {
      final outbox = _Outbox();
      final watchdog = Completer<MosambeePaymentResult>();
      final terminal = _Terminal.delayed(watchdog);
      final secondClaim = QrSettlementClaim(
        orderUuid: '33333333-3333-4333-8333-333333333333',
        frozenAmountBaisas: 2750,
        status: 'awaiting_payment',
        deadlineAt: now.add(const Duration(minutes: 5)),
      );
      final verifiedFirst = QrSettlementClaim(
        orderUuid: claim().orderUuid,
        frozenAmountBaisas: claim().frozenAmountBaisas,
        status: 'awaiting_payment',
        deadlineAt: claim().deadlineAt,
        alreadyClaimedByThisDevice: true,
      );
      final verifiedSecond = QrSettlementClaim(
        orderUuid: secondClaim.orderUuid,
        frozenAmountBaisas: secondClaim.frozenAmountBaisas,
        status: secondClaim.status,
        deadlineAt: secondClaim.deadlineAt,
        alreadyClaimedByThisDevice: true,
      );
      final scriptedTill = _Till(
        claim(),
        scriptedClaims: [claim(), secondClaim, verifiedFirst, verifiedSecond],
      );
      final flow = coordinator(
        till: scriptedTill,
        outbox: outbox,
        terminal: terminal,
      );

      final held = await flow.claim(claim().orderUuid);
      final heldSecond = await flow.claim(secondClaim.orderUuid);
      final settlement = flow.settleClaim(held, QrTender.card);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        flow.settleClaim(heldSecond, QrTender.card),
        throwsA(isA<QrPaymentAttemptUnresolved>()),
      );
      expect(terminal.amounts, [4750]);
      expect(
        scriptedTill.claimCalls,
        3,
        reason: 'the pre-held second claim cannot start a terminal capture',
      );

      watchdog.complete(_watchdogUnknown());
      final result = await settlement;

      expect(result.kind, QrSettlementResultKind.cardUncertain);
      expect(result.managerRequired, isTrue);
      expect(result.mustNotRetryTender, isTrue);
      expect(scriptedTill.releases.single.outcome, QrReleaseOutcome.uncertain);
      expect(
        scriptedTill.releases.single.bankResponse?['code'],
        'SOFTPOS_NOT_RESPONDING',
      );
      expect(outbox.amounts, isEmpty);
      expect(flow.pendingManagerRecoveries, [same(result)]);

      await expectLater(
        flow.claim(held.orderUuid),
        throwsA(isA<QrPaymentAttemptUnresolved>()),
      );
      await expectLater(
        flow.settleClaim(heldSecond, QrTender.card),
        throwsA(isA<QrPaymentAttemptUnresolved>()),
      );
      expect(terminal.amounts, [4750]);
      expect(
        scriptedTill.claimCalls,
        3,
        reason: 'pending manager recovery still blocks the pre-held claim',
      );

      flow.acknowledgeManagerRecovery(held.orderUuid);
      expect(flow.pendingManagerRecoveries, isEmpty);
      final secondResult = await flow.settleClaim(heldSecond, QrTender.card);
      expect(secondResult.kind, QrSettlementResultKind.cardUncertain);
      expect(
        scriptedTill.claimCalls,
        4,
        reason: 'only a manager can clear the second-tender gate',
      );
      expect(terminal.amounts, [4750, 2750]);
    },
  );

  for (final code in ['NO_SESSION', 'BUSY']) {
    test('$code stays a pre-dispatch cancelled failure', () async {
      final till = _Till(claim());
      final outbox = _Outbox();
      final terminalResult = _preDispatchFailure(code);
      final terminal = _Terminal(terminalResult);
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      final result = await flow.settleClaim(held, QrTender.card);

      expect(result.kind, code == 'BUSY' ? QrSettlementResultKind.cardUncertain : QrSettlementResultKind.cardFailedBeforeCapture);
      expect(terminalResult.failurePhase, code == 'BUSY' ? MosambeeFailurePhase.postDispatchUnknown : MosambeeFailurePhase.preDispatch);
      expect(result.managerRequired, code == 'BUSY' ? isTrue : isFalse);
      expect(result.mustNotRetryTender, code == 'BUSY' ? isTrue : isFalse);
      expect(till.releases.single.outcome, code == 'BUSY' ? QrReleaseOutcome.uncertain : QrReleaseOutcome.cancelled);
      expect(outbox.amounts, isEmpty);
      expect(flow.pendingManagerRecoveries, code == 'BUSY' ? hasLength(1) : isEmpty);
    });
  }

  test('a thrown terminal call is uncertain and never escapes raw', () async {
    final till = _Till(claim());
    final outbox = _Outbox();
    final terminal = _Terminal.throwing(StateError('plugin disconnected'));
    final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

    final held = await flow.claim(claim().orderUuid);
    final result = await flow.settleClaim(held, QrTender.card);

    expect(result.kind, QrSettlementResultKind.cardUncertain);
    expect(result.managerRequired, isTrue);
    expect(result.mustNotRetryTender, isTrue);
    expect(result.serverError, contains('plugin disconnected'));
    expect(till.releases.single.outcome, QrReleaseOutcome.uncertain);
    expect(outbox.amounts, isEmpty);
  });

  test('cash refusal tells staff to return cash and retires replay', () async {
    final till = _Till(claim());
    final outbox = _Outbox(state: StandaloneQrPayState.refused);
    final flow = coordinator(
      till: till,
      outbox: outbox,
      terminal: _Terminal(_success()),
    );

    final held = await flow.claim(claim().orderUuid);
    final result = await flow.settleClaim(held, QrTender.cash);

    expect(result.kind, QrSettlementResultKind.cashRefusedAfterTender);
    expect(result.returnCash, isTrue);
    expect(till.releases.single.outcome, QrReleaseOutcome.cancelled);
    expect(outbox.retired, [held.orderUuid]);
  });

  test(
    'card refusal after approval releases uncertain and never retries tap',
    () async {
      final till = _Till(claim());
      final outbox = _Outbox(state: StandaloneQrPayState.refused);
      final terminal = _Terminal(_success());
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      final result = await flow.settleClaim(held, QrTender.card);

      expect(result.kind, QrSettlementResultKind.cardRefusedAfterCapture);
      expect(result.managerRequired, isTrue);
      expect(result.mustNotRetryTender, isTrue);
      expect(till.releases.single.outcome, QrReleaseOutcome.uncertain);
      expect(outbox.retired, [held.orderUuid]);
      expect(terminal.amounts, hasLength(1));
    },
  );

  test(
    'missing ACK keeps durable attempt unresolved and blocks another claim',
    () async {
      final till = _Till(claim());
      final outbox = _Outbox(state: StandaloneQrPayState.pending);
      final terminal = _Terminal(_success());
      final flow = coordinator(till: till, outbox: outbox, terminal: terminal);

      final held = await flow.claim(claim().orderUuid);
      final result = await flow.settleClaim(held, QrTender.card);
      outbox.unresolved = true;

      expect(result.kind, QrSettlementResultKind.awaitingServerAcknowledgement);
      expect(result.managerRequired, isTrue);
      expect(till.releases, isEmpty);
      expect(outbox.retired, isEmpty);
      expect(flow.pendingManagerRecoveries, [same(result)]);

      flow.acknowledgeManagerRecovery(held.orderUuid);
      expect(flow.pendingManagerRecoveries, isEmpty);
      await expectLater(
        flow.settleClaim(held, QrTender.card),
        throwsA(isA<QrSettlementClaimNotHeld>()),
      );
      await expectLater(
        flow.claim(held.orderUuid),
        throwsA(isA<QrPaymentAttemptUnresolved>()),
      );
      expect(terminal.amounts, hasLength(1));
    },
  );

  test('standalone void uses only the QR outbox seam', () async {
    final outbox = _Outbox();
    final flow = coordinator(
      till: _Till(claim()),
      outbox: outbox,
      terminal: _Terminal(_success()),
    );

    await flow.voidOrder(
      claim().orderUuid,
      reason: 'customer request',
      staffId: 7,
    );

    expect(outbox.voided, [claim().orderUuid]);
  });
}

class _Till implements QrTillGateway {
  _Till(
    this.initialClaim, {
    this.replayClaim,
    this.replayError,
    this.log,
    this.scriptedClaims,
  });

  final QrSettlementClaim initialClaim;
  final QrSettlementClaim? replayClaim;
  final Object? replayError;
  final List<String>? log;
  final List<QrSettlementClaim>? scriptedClaims;
  int claimCalls = 0;
  final List<QrGeoFix?> claimGps = [];
  final List<({QrReleaseOutcome outcome, Map<String, dynamic>? bankResponse})>
  releases = [];

  @override
  Future<QrSettlementClaim> claimSettlement(
    String orderUuid, {
    double? lat,
    double? lng,
  }) async {
    log?.add('claim');
    claimCalls++;
    claimGps.add(lat == null || lng == null ? null : (lat: lat, lng: lng));
    if (scriptedClaims != null) return scriptedClaims![claimCalls - 1];
    if (claimCalls == 1) return initialClaim;
    if (replayError != null) throw replayError!;
    return replayClaim ??
        QrSettlementClaim(
          orderUuid: initialClaim.orderUuid,
          frozenAmountBaisas: initialClaim.frozenAmountBaisas,
          status: initialClaim.status,
          deadlineAt: initialClaim.deadlineAt,
          claimedAt: initialClaim.claimedAt,
          alreadyClaimedByThisDevice: true,
        );
  }

  @override
  Future<void> releaseSettlement(
    String orderUuid,
    QrReleaseOutcome outcome, {
    String? softposReference,
    String? softposAuthCode,
    Map<String, dynamic>? bankResponse,
  }) async {
    releases.add((outcome: outcome, bankResponse: bankResponse));
  }

  @override
  Future<QrActiveOrder?> activeQrOrder(String orderUuid) async => null;

  @override
  Future<void> clearTable(int tableId) async {}

  @override
  Future<QrOrderActionResult> fallbackToCounter(String orderUuid) =>
      throw UnimplementedError();

  @override
  Future<List<QrActiveOrder>> fetchActiveQrOrders() async => const [];

  @override
  Future<List<QrTableBoardRow>> fetchTableBoard() async => const [];

  @override
  Future<QrOrderActionResult> reopenPayment(String orderUuid) =>
      throw UnimplementedError();
}

class _Outbox implements QrSettlementOutbox {
  _Outbox({
    this.state = StandaloneQrPayState.processed,
    this.unresolved = false,
    this.log,
  });

  final StandaloneQrPayState state;
  bool unresolved;
  final List<String>? log;
  final List<int> amounts = [];
  final List<QrTender> tenders = [];
  final List<QrGeoFix?> gps = [];
  final List<String> retired = [];
  final List<String> voided = [];

  @override
  Future<StandaloneQrPayResult> enqueuePayment({
    required String orderUuid,
    required int frozenAmountBaisas,
    required QrTender tender,
    CardCharge? cardCharge,
    double? lat,
    double? lng,
  }) async {
    log?.add('outbox');
    amounts.add(frozenAmountBaisas);
    tenders.add(tender);
    gps.add(lat == null || lng == null ? null : (lat: lat, lng: lng));
    return StandaloneQrPayResult(
      state: state,
      outboxKey: '$orderUuid:pay',
      clientEventId: '22222222-2222-4222-8222-222222222222',
      error: state == StandaloneQrPayState.refused ? 'refused' : null,
    );
  }

  @override
  Future<void> enqueueVoid(
    String orderUuid, {
    String? reason,
    int? voidReasonId,
    int? staffId,
    String? authorizedBy,
  }) async {
    voided.add(orderUuid);
  }

  @override
  Future<bool> hasUnresolvedPayment(String orderUuid) async => unresolved;

  @override
  Future<void> retirePayment(String orderUuid, {required String reason}) async {
    retired.add(orderUuid);
  }
}

class _Terminal implements QrCardTerminalGateway {
  _Terminal(this.result, {this.log}) : error = null, delayedResult = null;

  _Terminal.throwing(this.error)
    : result = null,
      log = null,
      delayedResult = null;

  _Terminal.delayed(this.delayedResult)
    : result = null,
      error = null,
      log = null;

  final MosambeePaymentResult? result;
  final Object? error;
  final Completer<MosambeePaymentResult>? delayedResult;
  final List<String>? log;
  final List<int> amounts = [];

  @override
  Future<MosambeePaymentResult> captureBaisas(int amountBaisas) async {
    log?.add('terminal');
    amounts.add(amountBaisas);
    if (error != null) throw error!;
    if (delayedResult != null) return delayedResult!.future;
    return result!;
  }
}

class _Location implements QrLocationGateway {
  const _Location(this.fix);
  final QrGeoFix? fix;

  @override
  Future<QrGeoFix?> currentFix() async => fix;
}

MosambeePaymentResult _success() => MosambeePaymentResult.fromRaw(
  jsonEncode({'status': 'success', 'responseCode':'00', 'rrn': 'RRN-1'}),
);

MosambeePaymentResult _cancelled() =>
    MosambeePaymentResult.fromRaw(jsonEncode({'status': 'cancelled'}));

MosambeePaymentResult _uncertain() => MosambeePaymentResult.fromRaw(
  jsonEncode({
    'status': 'failed',
    'stage': 'payment',
    'message': 'NFC timeout',
  }),
);

MosambeePaymentResult _watchdogUnknown() => MosambeePaymentResult.fromRaw(
  jsonEncode({
    'status': 'failed',
    'stage': 'watchdog',
    'code': 'SOFTPOS_NOT_RESPONDING',
    'message': 'Payment app not responding.',
  }),
);

MosambeePaymentResult _preDispatchFailure(String code) =>
    MosambeePaymentResult.fromRaw(
      jsonEncode({
        'status': 'failed',
        'stage': code == 'NO_SESSION' ? 'payment' : 'flutter_platform',
        if (code == 'BUSY') 'dispatch_failed': true,
        'code': code,
        'message': 'Payment was not dispatched.',
      }),
    );
