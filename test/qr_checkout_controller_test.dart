import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'qr_checkout_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'saved pending event rejects corrupt money, GPS and non-success tender',
    () async {
      final f = CheckoutFixture();
      final c = f.controller();
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      final original = jsonEncode(f.store.value!.json);
      expect(CheckoutAttempt.decode(original).state, 'pending');
      for (final key in ['amount', 'gps', 'status']) {
        final data = checkoutMap(jsonDecode(original));
        final payload = (data['event'] as Map)['payload'] as Map;
        if (key == 'gps') {
          payload['gps'] = {'lat': 1, 'lng': 2};
        }
        if (key == 'amount') {
          ((payload['payments'] as List).single as Map)['amount_baisas'] = 1;
        }
        if (key == 'status') {
          ((payload['payments'] as List).single as Map)['status'] =
              'pending_reconciliation';
        }
        expect(
          () => CheckoutAttempt.decode(jsonEncode(data)),
          throwsFormatException,
        );
      }
      c.dispose();
    },
  );
  late CheckoutFixture f;
  late QrCheckoutController c;
  setUp(() {
    f = CheckoutFixture();
    c = f.controller();
  });
  tearDown(() => c.dispose());
  test(
    'claim precedes snapshot; full customer stays memory-only; frozen nested data',
    () async {
      await c.open('qr-bill');
      expect(c.ready, true);
      expect(f.api.claims, 1);
      expect(f.api.snapshots, 1);
      expect(c.snapshot!.customerLabel, 'Test Customer · 00000000');
      expect(
        () => (c.snapshot!.order['items'] as List).clear(),
        throwsUnsupportedError,
      );
      expect(jsonEncode(f.store.value!.json), isNot(contains('00000000')));
      expect(jsonEncode(f.store.value!.json), isNot(contains('Test Customer')));
    },
  );
  for (final method in ['cash', 'card', 'bank_pos', 'gift']) {
    test(
      '$method uses frozen total and ONE standalone pay, never create/GPS',
      () async {
        await c.open('qr-bill');
        await c.pay([
          CheckoutTender(method, 4750, change: method == 'cash' ? 250 : 0),
        ]);
        expect(c.phase, CheckoutPhase.paid);
        expect(f.api.commits, 1);
        expect(f.api.pushes, hasLength(1));
        final event = f.api.pushes.single;
        expect(event.keys.toSet(), {
          'client_event_id',
          'event_type',
          'client_timestamp',
          'payload',
        });
        expect(event['event_type'], 'order.pay');
        expect((event['payload'] as Map).keys.toSet(), {
          'order_uuid',
          'paid_at',
          'payments',
          // LAUNCH-P5 C3 — the P5 wire marker.
          'auth_v',
        });
        expect((event['payload'] as Map)['payments'], [
          CheckoutTender(method, 4750, change: method == 'cash' ? 250 : 0).json
            ..addAll(method == 'card' ? {'softpos_reference': 'TEST-RRN'} : {}),
        ]);
        expect(c.attempt!.receiptNumber, 'R-009');
        expect(f.cards, method == 'card' ? 1 : 0);
        expect(f.banks, method == 'bank_pos' ? 1 : 0);
        expect(f.gifts, method == 'gift' ? 1 : 0);
        expect(
          f.store.history.map((r) => r.state),
          containsAllInOrder([
            'claiming',
            'reserved',
            'capturing',
            'pending',
            'paid',
          ]),
        );
      },
    );
  }
  test(
    'double tap and cancel during capture cannot create a second tender',
    () async {
      await c.open('qr-bill');
      f.captureWait = Completer();
      final pay = c.pay([const CheckoutTender('card', 4750)]);
      await Future<void>.delayed(Duration.zero);
      await c.pay([const CheckoutTender('cash', 4750)]);
      await c.cancel();
      expect(f.cards, 1);
      expect(f.api.releases, isEmpty);
      f.captureWait!.complete();
      await pay;
      expect(f.api.pushes, hasLength(1));
      expect(c.phase, CheckoutPhase.paid);
    },
  );
  test(
    'gift manager denial performs no tender or event and stays ready',
    () async {
      await c.open('qr-bill');
      f.giftAllowed = false;
      await c.pay([const CheckoutTender('gift', 4750)]);
      expect(c.ready, true);
      expect(f.api.pushes, isEmpty);
      expect(f.api.claims, 1);
    },
  );
  for (final plan in [
    <CheckoutTender>[],
    [const CheckoutTender('cash', 4749)],
    [const CheckoutTender('crypto', 4750)],
    [const CheckoutTender('cash', -1), const CheckoutTender('card', 4751)],
    [const CheckoutTender('gift', 2000), const CheckoutTender('cash', 2750)],
    [const CheckoutTender('card', 4750, change: 1)],
  ]) {
    test(
      'invalid tender plan ${plan.map((v) => '${v.method}:${v.amount}:${v.change}').join(',')} fails before capture',
      () async {
        await c.open('qr-bill');
        await expectLater(c.pay(plan), throwsFormatException);
        expect(c.ready, true);
        expect(f.cards + f.banks, 0);
        expect(f.api.pushes, isEmpty);
      },
    );
  }
  test(
    'competing claim/replay refuses before tender and releases safely',
    () async {
      await c.open('qr-bill');
      f.api.refuseClaimAt = 2;
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(f.cards, 0);
      expect(f.api.pushes, isEmpty);
      expect(f.api.releases.single['outcome'], 'cancelled');
      expect(c.canLeave, true);
    },
  );
  test('changed frozen amount refuses replay without a tender', () async {
    await c.open('qr-bill');
    f.api.changedClaimAt = 2;
    await c.pay([const CheckoutTender('cash', 4750)]);
    expect(f.api.pushes, isEmpty);
    expect(c.phase, CheckoutPhase.released);
  });
  test('claim deadline moved past before pay blocks card', () async {
    await c.open('qr-bill');
    f.now = f.now.add(const Duration(minutes: 5));
    await c.pay([const CheckoutTender('card', 4750)]);
    expect(f.cards, 0);
    expect(f.api.pushes, isEmpty);
    expect(f.api.claims, 1);
  });
  test(
    'first replay without saved provenance fails closed without snapshot',
    () async {
      f.api.firstReplay = true;
      await c.open('qr-bill');
      expect(c.phase, CheckoutPhase.attention);
      expect(f.api.snapshots, 0);
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(f.cards, 0);
    },
  );
  test(
    'bad snapshot cancels reservation, never displays or takes money',
    () async {
      f.api.badSnapshot = true;
      await c.open('qr-bill');
      expect(c.phase, CheckoutPhase.released);
      expect(c.snapshot, isNull);
      expect(f.api.releases.single['outcome'], 'cancelled');
    },
  );
  test('initial authoritative refusal archives only no-claim intent', () async {
    f.api.refuseClaimAt = 1;
    await c.open('qr-bill');
    expect(c.phase, CheckoutPhase.released);
    expect(f.api.releases, isEmpty);
  });
  test('lost claim reply leaves durable intent and no payment', () async {
    f.api.failClaim = true;
    await c.open('qr-bill');
    expect(c.phase, CheckoutPhase.attention);
    expect(f.store.value!.state, 'claiming');
    expect(f.api.pushes, isEmpty);
    expect(f.api.releases, isEmpty);
  });
  test('preflight scope/storage failure does not claim', () async {
    f.api.failPreflight = true;
    await c.open('qr-bill');
    expect(f.api.claims, 0);
    expect(f.store.value, isNull);
    expect(c.ready, false);
    expect(c.canLeave, true);
  });
  test(
    'lost ACK after commit survives restart and replays exact event only',
    () async {
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('card', 4750)]);
      final first = jsonEncode(f.api.pushes.single);
      final claims = f.api.claims;
      expect(c.phase, CheckoutPhase.pending);
      expect(f.api.commits, 1);
      final resumed = f.controller();
      await resumed.open(null);
      expect(resumed.reference, 'Q-007');
      expect(resumed.phase, CheckoutPhase.pending);
      f.api.loseAck = false;
      await resumed.retryAcknowledgement();
      expect(resumed.phase, CheckoutPhase.paid);
      expect(f.cards, 1);
      expect(f.api.claims, claims);
      expect(f.api.commits, 1);
      expect(jsonEncode(f.api.pushes.last), first);
      resumed.dispose();
    },
  );
  for (final ack in ['wrong-id', 'wrong-order', 'wrong-status', 'orphan']) {
    test('non-authoritative $ack ACK stays pending, never paid', () async {
      await c.open('qr-bill');
      f.api.ack = ack;
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.pending);
      expect(c.attempt!.receiptNumber, isNull);
    });
  }
  test(
    'explicit failed pay stops automatic retry and requires manager',
    () async {
      await c.open('qr-bill');
      f.api.ack = 'failed';
      await c.pay([const CheckoutTender('card', 4750)]);
      await c.retryAcknowledgement();
      expect(c.phase, CheckoutPhase.attention);
      expect(f.api.pushes, hasLength(1));
      expect(f.api.releases.single['outcome'], 'uncertain');
      expect(f.cards, 1);
    },
  );
  test('pending manager exit never discards immutable event', () async {
    await c.open('qr-bill');
    f.api.loseAck = true;
    await c.pay([const CheckoutTender('cash', 4750)]);
    expect(await c.managerTakeover(() async => false), false);
    expect(await c.managerTakeover(() async => true), true);
    expect(f.store.value!.state, 'pending');
    expect(await f.store.active(), isNotNull);
  });
  test(
    'restart during capture blocks any tender and requires manager',
    () async {
      await c.open('qr-bill');
      f.store.value = f.store.value!.copy(state: 'capturing');
      final resumed = f.controller();
      await resumed.open('another-bill');
      expect(resumed.reference, 'Q-007');
      expect(resumed.ready, false);
      await resumed.pay([const CheckoutTender('card', 4750)]);
      expect(f.cards, 0);
      expect(f.api.claims, 1);
      expect(await resumed.managerTakeover(() async => true), true);
      expect(f.api.releases.single['outcome'], 'uncertain');
      expect(f.store.value!.state, 'managed');
      resumed.dispose();
    },
  );
  test(
    'restart before tender reuses the SAME reserved bill, not requested other bill',
    () async {
      await c.open('qr-bill');
      final resumed = f.controller();
      await resumed.open('another-bill');
      expect(resumed.ready, true);
      expect(resumed.snapshot!.uuid, 'qr-bill');
      expect(f.api.claims, 2);
      resumed.dispose();
    },
  );
  test('storage failure before capture prevents physical tender', () async {
    await c.open('qr-bill');
    f.store.failState = 'capturing';
    await c.pay([const CheckoutTender('card', 4750)]);
    expect(f.cards, 0);
    expect(f.api.pushes, isEmpty);
    expect(c.ready, false);
  });
  test(
    'storage failure after capture retains capturing marker, no cancelled release',
    () async {
      await c.open('qr-bill');
      f.store.failState = 'pending';
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(f.cards, 1);
      expect(f.store.value!.state, 'capturing');
      expect(f.api.pushes, isEmpty);
      expect(f.api.releases, isEmpty);
      expect(c.ready, false);
    },
  );
  for (final state in [
    CheckoutCaptureState.uncertain,
    CheckoutCaptureState.cancelled,
    CheckoutCaptureState.notDispatched,
  ]) {
    test('terminal $state cannot create a successful pay', () async {
      await c.open('qr-bill');
      f.cardState = state;
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(f.api.pushes, isEmpty);
      expect(f.cards, 1);
      expect(
        f.api.releases.single['outcome'],
        state == CheckoutCaptureState.uncertain ? 'uncertain' : 'cancelled',
      );
      expect(c.ready, false);
    });
  }
  test('split cash plus card uses exact legs and frozen sum', () async {
    await c.open('qr-bill');
    await c.pay([
      const CheckoutTender('cash', 2000),
      const CheckoutTender('card', 2750),
    ]);
    expect(c.phase, CheckoutPhase.paid);
    expect(f.cards, 1);
    final legs = (f.api.pushes.single['payload'] as Map)['payments'] as List;
    expect(legs.map((v) => (v as Map)['amount_baisas']), [2000, 2750]);
  });
  test(
    'cancelled second leg after bank approval is uncertain, not cancelled',
    () async {
      await c.open('qr-bill');
      f.cardState = CheckoutCaptureState.cancelled;
      await c.pay([
        const CheckoutTender('bank_pos', 2000),
        const CheckoutTender('card', 2750),
      ]);
      expect(f.api.pushes, isEmpty);
      expect(f.api.releases.single['outcome'], 'uncertain');
      expect(f.store.value!.captures.single['method'], 'bank_pos');
      expect(c.ready, false);
    },
  );
  test('cancelled second leg after cash asks to return cash', () async {
    await c.open('qr-bill');
    f.cardState = CheckoutCaptureState.cancelled;
    await c.pay([
      const CheckoutTender('cash', 2000),
      const CheckoutTender('card', 2750),
    ]);
    expect(c.notice, 'return_cash');
    expect(f.api.releases.single['outcome'], 'cancelled');
  });
  test(
    'release failure keeps reservation and disallows another tender',
    () async {
      await c.open('qr-bill');
      f.api.failRelease = true;
      await c.cancel();
      expect(c.phase, CheckoutPhase.attention);
      expect(f.store.value!.state, 'releasing');
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(f.api.pushes, isEmpty);
      f.api.failRelease = false;
      await c.cancel();
      expect(c.canLeave, true);
    },
  );
  test('empty recovery never contacts server', () async {
    await c.open(null);
    expect(c.phase, CheckoutPhase.empty);
    expect(f.api.claims, 0);
  });
  test('keypad is baisa precise and ignored while not ready', () async {
    c.cashKey('9');
    expect(c.cashBaisas, 0);
    await c.open('qr-bill');
    for (final key in ['5', '.', '1', '2', '3', '4']) {
      c.cashKey(key);
    }
    expect(c.cashBaisas, 5123);
    expect(c.changeBaisas, 373);
    c.cashKey('back');
    expect(c.cashBaisas, 5120);
  });
  test(
    'SQLite journal scope, one-active constraint, immutable event and terminal retention',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await SqliteCheckoutStore.createSchema(db);
      final a = SqliteCheckoutStore(db, 'server/company/branch/till');
      final b = SqliteCheckoutStore(db, 'server/company/other-branch/till');
      final row = CheckoutAttempt(
        id: '1',
        orderUuid: 'qr-bill',
        state: 'claiming',
        createdAt: checkoutTime,
      );
      await a.create(row);
      expect(await b.active(), isNull);
      await expectLater(
        a.create(
          CheckoutAttempt(
            id: '2',
            orderUuid: 'another',
            state: 'claiming',
            createdAt: checkoutTime,
          ),
        ),
        throwsA(anything),
      );
      final reserved = row.copy(state: 'reserved', claim: claimJson());
      await a.replace(row, reserved);
      await expectLater(
        a.replace(row, row.copy(state: 'released')),
        throwsStateError,
      );
      final event = {
        'client_event_id': '1',
        'event_type': 'order.pay',
        'payload': {'order_uuid': 'qr-bill'},
      };
      final pending = reserved.copy(state: 'pending', event: event);
      await a.replace(reserved, pending);
      event['event_type'] = 'order.create';
      expect(pending.event!['event_type'], 'order.pay');
      await expectLater(
        a.replace(pending, pending.copy(event: event)),
        throwsStateError,
      );
      final paid = pending.copy(state: 'paid');
      await a.replace(pending, paid);
      expect(await a.active(), isNull);
      expect(await db.query('qr_checkout_attempts'), hasLength(1));
      await expectLater(
        a.replace(paid, paid.copy(state: 'pending')),
        throwsStateError,
      );
      await db.close();
    },
  );
}
