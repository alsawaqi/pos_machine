import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:pos_machine/state/card_reversal_controller.dart';

void main() {
  for (final muscat in [false, true]) {
    for (final kind in ['void', 'refund']) {
      for (final verdict in ['approved', 'declined', 'uncertain']) {
        test(
          '$kind $verdict uses reserved money and one bank operation (Muscat=$muscat)',
          () async {
            final bankCalls = <String>[];
            final requests = <Map<String, dynamic>>[];
            final slips = <List<SlipLine>>[];
            final reserved = <String, dynamic>{
              'reversal_uuid': 'REV',
              'kind': kind,
              'status': 'pending',
              'amount_baisas': 4750,
              'currency': '0512',
              'original_transaction_id': 'ORIGINAL',
              'description': 'Order O-1',
              'softpos': {
                'package': muscat
                    ? 'com.mosambee.muscat.softpos'
                    : 'com.mosambee.dhofar.softpos',
                'needs_session': muscat,
                'needs_transaction_id': !muscat,
              },
            };
            final c = CardReversalController(
              profile: SoftPosProfile.fromJson(null),
              header: ['Merchant'],
              orderReference: 'O-1',
              originalReceipt: 'R-1',
              originalCard: '433662XXXXXX5819',
              originalAuth: 'ORIG',
              verifyManager: (pin) async {
                expect(pin, 'MANAGER');
                return 'Approver';
              },
              request: (method, path, body) async {
                if (method == 'GET') return {'payments': []};
                requests.add(Map.of(body!));
                return path.endsWith('/result')
                    ? {...reserved, 'status': body['status']}
                    : reserved;
              },
              bank: (method, args) async {
                bankCalls.add(method);
                expect(
                  args['packageName'],
                  reserved['softpos'] is Map
                      ? (reserved['softpos'] as Map)['package']
                      : null,
                );
                expect(args.containsKey('manager_pin'), isFalse);
                if (method == 'prepareLogin') {
                  return SoftPosOutcome.fromPayload({
                    'stage': 'login',
                    'responseCode': '00',
                    'sessionId': 'SESSION',
                  });
                }
                expect(args['amountBaisas'], 4750);
                expect(args['currency'], '0512');
                if (muscat) expect(args['sessionId'], 'SESSION');
                if (kind == 'void' || !muscat) {
                  expect(args['transactionId'], 'ORIGINAL');
                }
                return SoftPosOutcome.fromPayload({
                  'stage': kind,
                  'responseCode': verdict == 'approved'
                      ? '00'
                      : verdict == 'declined'
                      ? '51'
                      : 'NA',
                  'resultCode': -1,
                  'receiptResponse': {
                    'transactionId': 'NEW',
                    'rrn': 'RRN',
                    'authCode': 'AUTH',
                  },
                });
              },
              printSlip: (lines) async {
                slips.add(lines);
                return true;
              },
            );
            await c.execute(
              payment: {
                'payment_uuid': 'PAY',
                'can_void': true,
                'can_refund': true,
              },
              kind: kind,
              managerPin: 'MANAGER',
              voidReasonId: kind == 'void' ? 7 : null,
              customAmountBaisas: kind == 'refund' ? 4999 : null,
              confirmAmount: (amount, currency) async {
                expect(amount, 4750);
                expect(currency, '0512');
                return true;
              },
            );
            expect(bankCalls, [
              if (muscat) 'prepareLogin',
              kind == 'void' ? 'voidTransaction' : 'refundTransaction',
            ]);
            expect(requests.first['manager_pin'], 'MANAGER');
            expect(
              requests.first['client_request_id'],
              matches(RegExp(r'^[0-9a-f-]{36}$')),
            );
            if (kind == 'void') expect(requests.first['void_reason_id'], 7);
            expect(requests.last['status'], verdict);
            expect(requests.last['reversal_transaction_id'], 'NEW');
            expect(requests.last['rrn'], 'RRN');
            expect(requests.last['auth_code'], 'AUTH');
            if (verdict == 'uncertain') {
              expect(slips, isEmpty);
              expect(c.slip, isEmpty);
              await c.reprint();
              expect(slips, isEmpty);
            } else {
              expect(slips, hasLength(1));
              expect(
                slips.single.where((line) => line.text == 'Customer copy'),
                hasLength(1),
              );
              expect(
                slips.single.map((line) => line.text),
                containsAllInOrder([
                  'Merchant',
                  kind.toUpperCase(),
                  'Order: O-1',
                  'Original receipt: R-1',
                  'Card: 433662XXXXXX5819',
                  'Original auth: ORIG',
                  'Amount: 4.750 OMR',
                  'Auth: AUTH',
                  'Transaction: NEW',
                  'RRN: RRN',
                ]),
              );
            }
            expect(c.needsRecovery, verdict == 'uncertain');
            c.dispose();
          },
        );
      }
    }
  }

  test(
    'remaining quantities are enforced before reservation or bank launch',
    () async {
      var calls = 0;
      final c = CardReversalController(
        request: (_, _, _) async {
          calls++;
          return {};
        },
        bank: (_, _) async {
          calls++;
          return SoftPosOutcome.fromRaw(null);
        },
        printSlip: (_) async => true,
        verifyManager: (_) async => 'M',
        profile: const SoftPosProfile(),
      );
      await expectLater(
        c.execute(
          payment: {
            'payment_uuid': 'P',
            'can_refund': true,
            'refundable_lines': [
              {'order_item_id': 3, 'remaining_qty': '1.500'},
            ],
          },
          kind: 'refund',
          managerPin: 'PIN',
          lines: [
            {'order_item_id': 3, 'qty': '1.501'},
          ],
          confirmAmount: (_, _) async => true,
        ),
        throwsStateError,
      );
      expect(calls, 0);
      c.dispose();
    },
  );

  test(
    'restart recovery only reads server reservations; it cannot relaunch the bank',
    () async {
      var launches = 0;
      final c = CardReversalController(
        request: (method, path, _) async {
          expect(method, 'GET');
          expect(path, contains('status=pending,uncertain'));
          return {
            'reversals': [
              {'reversal_uuid': 'R', 'status': 'pending'},
            ],
          };
        },
        bank: (_, _) async {
          launches++;
          throw StateError('must not launch');
        },
        printSlip: (_) async => true,
        verifyManager: (_) async => 'M',
        profile: const SoftPosProfile(),
      );
      await c.recover();
      expect(c.pending, hasLength(1));
      expect(launches, 0);
      c.dispose();
    },
  );

  test(
    'failed result report retries the same key and never repeats the bank or slip',
    () async {
      final reports = <Map<String, dynamic>>[];
      var launches = 0, prints = 0;
      final reserved = <String, dynamic>{
        'reversal_uuid': 'R',
        'kind': 'void',
        'amount_baisas': 1000,
        'currency': '0512',
        'softpos': {
          'package': 'com.mosambee.dhofar.softpos',
          'needs_session': false,
        },
        'original_transaction_id': 'T',
      };
      final c = CardReversalController(
        request: (_, path, body) async {
          if (!path.endsWith('/result')) return reserved;
          reports.add(Map.of(body!));
          if (reports.length == 1) throw StateError('offline');
          return {...reserved, 'status': 'approved'};
        },
        bank: (_, _) async {
          launches++;
          return SoftPosOutcome.fromRaw('{"responseCode":"00","rrn":"R"}');
        },
        printSlip: (_) async {
          prints++;
          return true;
        },
        verifyManager: (_) async => 'M',
        profile: const SoftPosProfile(),
      );
      await expectLater(
        c.execute(
          payment: {'payment_uuid': 'P', 'can_void': true},
          kind: 'void',
          managerPin: 'PIN',
          voidReasonId: 1,
          confirmAmount: (_, _) async => true,
        ),
        throwsStateError,
      );
      expect(c.needsRecovery, isTrue);
      await c.retryReport();
      expect(reports[0], reports[1]);
      expect(launches, 1);
      expect(prints, 1);
      await c.retryReport();
      expect(launches, 1);
      expect(prints, 1);
      c.dispose();
    },
  );
  test(
    'server receipt projection wins on recovered reversal and prints once',
    () async {
      var bankCalls = 0, prints = 0;
      final c = CardReversalController(
        profile: const SoftPosProfile(),
        orderReference: 'STALE',
        originalReceipt: 'STALE',
        originalAuth: 'STALE',
        verifyManager: (_) async => 'M',
        bank: (_, _) async {
          bankCalls++;
          throw StateError('no bank');
        },
        request: (method, path, body) async =>
            method == 'GET' ? {'reversals': []} : {'status': 'approved'},
        printSlip: (lines) async {
          prints++;
          expect(
            lines.map((r) => r.text),
            containsAll([
              'Order: O-SERVER',
              'Original receipt: R-SERVER',
              'Original auth: A-SERVER',
              'Approved by: Original approver',
            ]),
          );
          return true;
        },
      );
      await c.reportObserved(
        {
          'reversal_uuid': 'R',
          'kind': 'refund',
          'amount_baisas': 4750,
          'currency': '0512',
          'order_reference': 'O-SERVER',
          'original_receipt_number': 'R-SERVER',
          'original_auth_code': 'A-SERVER',
          'approver_name': 'Original approver',
        },
        SoftPosOutcome.fromRaw('{"responseCode":"00","rrn":"RRN"}'),
        operatorName: 'Current operator',
      );
      expect(bankCalls, 0);
      expect(prints, 1);
      c.dispose();
    },
  );
  test(
    'server refusal is visible and cannot launch a Dhofar refund without original id',
    () async {
      var bankCalls = 0;
      final c = CardReversalController(
        profile: const SoftPosProfile(),
        verifyManager: (_) async => 'M',
        printSlip: (_) async => true,
        request: (_, _, _) async =>
            throw StateError('original_transaction_id_required'),
        bank: (_, _) async {
          bankCalls++;
          throw StateError('no bank');
        },
      );
      await expectLater(
        c.execute(
          payment: {'payment_uuid': 'P', 'can_refund': true},
          kind: 'refund',
          managerPin: 'PIN',
          customAmountBaisas: 4750,
          confirmAmount: (_, _) async => true,
        ),
        throwsStateError,
      );
      expect(c.error, contains('original_transaction_id_required'));
      expect(bankCalls, 0);
      c.dispose();
    },
  );
}
