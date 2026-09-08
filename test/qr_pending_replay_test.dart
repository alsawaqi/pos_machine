import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/mosambee_payment_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'support/qr_pending_fakes.dart';

void main() {
  for (final tender in QrTender.values) {
    for (final refused in [false, true]) {
      test(
        'expired quick session: fresh claim then replay ${refused ? '409 cancels without pay' : 'pays once'} (${tender.name})',
        () async {
          final now = DateTime.utc(2026, 9, 8, 12);
          final log = <String>[];
          final till = _Claims(now, log, refused);
          final outbox = _Outbox(log);
          final terminal = _Terminal(log);
          final coordinator = QrSettlementCoordinator(
            till: till,
            outbox: outbox,
            terminal: terminal,
            location: _Location(),
            now: () => now,
          );
          expect(till.orders.single.session, 'expired');
          final first = await coordinator.claim(till.orders.single.uuid);
          expect(first.alreadyClaimedByThisDevice, isFalse);
          if (refused) {
            await expectLater(
              coordinator.settleClaim(first, tender),
              throwsA(
                isA<QrSettlementRevalidationFailed>().having(
                  (error) => (error.cause as ApiException).code,
                  'server replay refusal',
                  'charge_already_claimed',
                ),
              ),
            );
            expect(log, ['claim:fresh', 'claim:replay', 'release:cancelled']);
            expect(outbox.payments, isEmpty);
            expect(terminal.captures, 0);
          } else {
            final result = await coordinator.settleClaim(first, tender);
            expect(result.kind, QrSettlementResultKind.paid);
            expect(log, [
              'claim:fresh',
              'claim:replay',
              if (tender == QrTender.card) 'terminal:4750',
              'order.pay',
            ]);
            expect(outbox.payments, [('quick-expired', 4750, tender)]);
            expect(terminal.captures, tender == QrTender.card ? 1 : 0);
            expect(till.replayed!.alreadyClaimedByThisDevice, isTrue);
            expect(till.replayed!.frozenAmountBaisas, first.frozenAmountBaisas);
            expect(till.replayed!.deadlineAt, first.deadlineAt);
          }
          expect(till.claims, 2);
        },
      );
    }
  }
}

class _Claims extends PendingGateway {
  _Claims(this.now, this.log, this.refused);
  final DateTime now;
  final List<String> log;
  final bool refused;
  int claims = 0;
  QrSettlementClaim? replayed;
  @override
  Future<QrSettlementClaim> claimSettlement(
    String uuid, {
    double? lat,
    double? lng,
  }) async {
    claims++;
    log.add(claims == 1 ? 'claim:fresh' : 'claim:replay');
    if (claims > 1 && refused) {
      throw ApiException(
        message: 'refused',
        statusCode: 409,
        code: 'charge_already_claimed',
      );
    }
    final claim = pendingClaim(uuid, replay: claims > 1, now: now);
    if (claims > 1) replayed = claim;
    return claim;
  }

  @override
  Future<void> releaseSettlement(
    String uuid,
    QrReleaseOutcome outcome, {
    String? softposReference,
    String? softposAuthCode,
    Map<String, dynamic>? bankResponse,
  }) async => log.add('release:${outcome.name}');
}

class _Outbox implements QrSettlementOutbox {
  _Outbox(this.log);
  final List<String> log;
  final payments = <(String, int, QrTender)>[];
  @override
  Future<bool> hasUnresolvedPayment(String uuid) async => false;
  @override
  Future<StandaloneQrPayResult> enqueuePayment({
    required String orderUuid,
    required int frozenAmountBaisas,
    required QrTender tender,
    CardCharge? cardCharge,
    double? lat,
    double? lng,
  }) async {
    log.add('order.pay');
    payments.add((orderUuid, frozenAmountBaisas, tender));
    return StandaloneQrPayResult(
      state: StandaloneQrPayState.processed,
      outboxKey: '$orderUuid:pay',
      clientEventId: 'pending-test-pay',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected outbox call');
}

class _Terminal implements QrCardTerminalGateway {
  _Terminal(this.log);
  final List<String> log;
  int captures = 0;
  @override
  Future<MosambeePaymentResult> captureBaisas(int amountBaisas) async {
    captures++;
    log.add('terminal:$amountBaisas');
    return MosambeePaymentResult.fromRaw(
      '{"status":"success","rrn":"TEST-ONLY"}',
    );
  }
}

class _Location implements QrLocationGateway {
  @override
  Future<QrGeoFix?> currentFix() async => null;
}
