import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'qr_checkout_fakes.dart';

CheckoutAttempt _attempt({bool? tender, String state = 'claiming'}) =>
    CheckoutAttempt(
      id: 'evidence-attempt',
      orderUuid: 'qr-bill',
      state: state,
      createdAt: checkoutTime,
      claim: state == 'claiming' ? null : claimJson(),
      tenderMayHaveStarted: tender,
    );

/// Failure injected at the real journal boundary, before any capture callback.
class _FailCapturing implements CheckoutStore {
  _FailCapturing(this.inner);
  final CheckoutStore inner;
  @override
  Future<CheckoutAttempt?> active() => inner.active();
  @override
  Future<void> create(CheckoutAttempt attempt) => inner.create(attempt);
  @override
  Future<void> replace(CheckoutAttempt previous, CheckoutAttempt next) {
    if (next.state == 'capturing') throw StateError('disk unavailable');
    return inner.replace(previous, next);
  }
}

void main() {
  late Database db;
  late SqliteCheckoutStore store;
  late CheckoutFakeGateway api;

  QrCheckoutController controller({
    CheckoutStore? journal,
    CheckoutCaptureFn? card,
    CheckoutCaptureFn? bank,
  }) => QrCheckoutController(
    gateway: api,
    store: journal ?? store,
    now: () => checkoutTime,
    newId: () => 'evidence-attempt',
    authorizeGift: () async => true,
    captureCard: card ?? (_) async => throw StateError('unexpected card'),
    captureBank: bank ?? (_) async => throw StateError('unexpected bank'),
  );

  Future<Map<String, Object?>> rawRow() async =>
      (await db.query('qr_checkout_attempts')).single;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteCheckoutStore.createSchema(db);
    store = SqliteCheckoutStore(db, 'evidence/server/branch/till');
    api = CheckoutFakeGateway();
  });
  tearDown(() async => db.close());

  test(
    'legacy JSON stays byte-identical and its tender evidence is unknown',
    () {
      final original = jsonEncode(_attempt(state: 'releasing').json);
      final decoded = CheckoutAttempt.decode(original);
      expect(decoded.tenderMayHaveStarted, isNull);
      expect(decoded.json.containsKey('tender_may_have_started'), false);
      expect(jsonEncode(decoded.json), original);
    },
  );

  for (final value in [null, 0, 'false']) {
    test('explicit malformed tender evidence is refused: $value', () {
      final json = {..._attempt().json, 'tender_may_have_started': value};
      expect(
        () => CheckoutAttempt.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });
  }

  for (final value in [false, true]) {
    test('explicit tender evidence round-trips and copies: $value', () {
      final original = _attempt(tender: value);
      final decoded = CheckoutAttempt.decode(jsonEncode(original.json));
      expect(decoded.tenderMayHaveStarted, value);
      expect(decoded.copy(reference: 'Q-007').tenderMayHaveStarted, value);
      expect(decoded.json, original.json);
    });
  }

  test('entering capture always conservatively marks possible tender', () {
    final reserved = _attempt(tender: false, state: 'reserved');
    final capturing = reserved.copy(state: 'capturing');
    expect(capturing.tenderMayHaveStarted, true);
    expect(capturing.copy(state: 'releasing').tenderMayHaveStarted, true);
    expect(
      _attempt(state: 'reserved').copy(state: 'capturing').tenderMayHaveStarted,
      true,
    );
  });

  test(
    'new local no-tender marker does not authorize an older server claim',
    () async {
      api.firstReplay = true;
      final c = controller();
      addTearDown(c.dispose);
      await c.open('qr-bill');
      expect(c.phase, CheckoutPhase.attention);
      expect(c.ready, false);
      expect((await store.active())!.state, 'uncertain');
      expect((await store.active())!.claim, isNull);
      expect((await store.active())!.tenderMayHaveStarted, false);
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(api.pushes, isEmpty);
      expect(api.releases, isEmpty);
      expect(api.snapshots, 0);
    },
  );

  test(
    'legacy reserved replay remains unknown until a new tender intent',
    () async {
      await store.create(_attempt(state: 'reserved'));
      api.firstReplay = true;
      final c = controller();
      addTearDown(c.dispose);
      await c.open('qr-bill');
      expect(c.ready, true);
      expect((await store.active())!.tenderMayHaveStarted, isNull);
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.paid);
      final saved = CheckoutAttempt.decode(
        (await rawRow())['payload'] as String,
      );
      expect(saved.tenderMayHaveStarted, true);
      expect(api.commits, 1);
    },
  );

  final contradictions = <String, Map<String, dynamic>>{
    'capturing': {'state': 'capturing', 'claim': claimJson()},
    'pending': {'state': 'pending', 'claim': claimJson()},
    'refused': {'state': 'refused'},
    'paid': {'state': 'paid'},
    'event': {'event': <String, dynamic>{}},
    'capture': {
      'captures': [
        {'method': 'cash', 'amount_baisas': 4750, 'status': 'success'},
      ],
    },
    'receipt': {'receipt_number': 'R-009'},
  };
  for (final entry in contradictions.entries) {
    test('no-tender marker cannot contradict ${entry.key} evidence', () {
      expect(
        () => CheckoutAttempt.decode(
          jsonEncode({..._attempt(tender: false).json, ...entry.value}),
        ),
        throwsFormatException,
      );
    });
  }

  for (final pair in <(bool?, bool?)>[
    (null, false),
    (true, false),
    (true, null),
    (false, null),
  ]) {
    test(
      'SQLite refuses evidence downgrade ${pair.$1} -> ${pair.$2}',
      () async {
        final previous = _attempt(tender: pair.$1);
        await store.create(previous);
        final before = await rawRow();
        await expectLater(
          store.replace(previous, _attempt(tender: pair.$2)),
          throwsStateError,
        );
        expect(await rawRow(), before);
        expect((await store.active())!.tenderMayHaveStarted, pair.$1);
      },
    );
  }

  test(
    'SQLite cannot attach a new no-tender marker to an adopted claim',
    () async {
      await expectLater(
        store.create(_attempt(tender: false, state: 'reserved')),
        throwsStateError,
      );
      expect(await db.query('qr_checkout_attempts'), isEmpty);
    },
  );

  test('stale journal writer cannot replace or reset newer evidence', () async {
    final first = _attempt(tender: false);
    await store.create(first);
    final started = first.copy(tenderMayHaveStarted: true);
    await store.replace(first, started);
    final before = await rawRow();
    await expectLater(
      store.replace(first, first.copy(reference: 'stale')),
      throwsStateError,
    );
    expect(await rawRow(), before);
    expect((await store.active())!.tenderMayHaveStarted, true);
  });

  test(
    'fresh Back retains no-tender evidence through failed release and handover',
    () async {
      final c = controller();
      addTearDown(c.dispose);
      await c.open('qr-bill');
      expect((await store.active())!.tenderMayHaveStarted, false);
      api.failRelease = true;
      await c.cancel();
      final before = (await store.active())!.json;
      expect(before['tender_may_have_started'], false);
      expect(await c.managerTakeover(() async => true), true);
      expect(jsonDecode((await rawRow())['payload'] as String), {
        ...before,
        'state': 'managed',
      });
      expect(api.releases, hasLength(1));
      expect(api.pushes, isEmpty);
    },
  );

  for (final method in ['card', 'bank_pos']) {
    test(
      '$method callback sees committed tender evidence before dispatch',
      () async {
        var calls = 0;
        Future<CheckoutCapture> capture(int amount) async {
          calls++;
          final reopened = SqliteCheckoutStore(db, store.scope);
          final saved = (await reopened.active())!;
          expect(saved.state, 'capturing');
          expect(saved.tenderMayHaveStarted, true);
          expect(saved.event, isNull);
          expect(saved.captures, isEmpty);
          expect(amount, 4750);
          return const CheckoutCapture(CheckoutCaptureState.approved);
        }

        final c = controller(card: capture, bank: capture);
        addTearDown(c.dispose);
        await c.open('qr-bill');
        await c.pay([CheckoutTender(method, 4750)]);
        expect(calls, 1);
        expect(c.phase, CheckoutPhase.paid);
        final saved = CheckoutAttempt.decode(
          (await rawRow())['payload'] as String,
        );
        expect(saved.tenderMayHaveStarted, true);
        expect(saved.receiptNumber, 'R-009');
        expect(api.commits, 1);
      },
    );
  }

  test(
    'failed durable capture marker prevents every terminal call and pay',
    () async {
      var captures = 0;
      final c = controller(
        journal: _FailCapturing(store),
        card: (_) async {
          captures++;
          return const CheckoutCapture(CheckoutCaptureState.approved);
        },
      );
      addTearDown(c.dispose);
      await c.open('qr-bill');
      await c.pay([const CheckoutTender('card', 4750)]);
      expect(captures, 0);
      expect(c.phase, CheckoutPhase.attention);
      expect((await store.active())!.state, 'reserved');
      expect((await store.active())!.tenderMayHaveStarted, false);
      expect(api.pushes, isEmpty);
      expect(api.releases, isEmpty);
    },
  );

  for (final result in [
    CheckoutCaptureState.cancelled,
    CheckoutCaptureState.notDispatched,
  ]) {
    test(
      'empty captures after $result never resets the started marker',
      () async {
        final c = controller(card: (_) async => CheckoutCapture(result));
        addTearDown(c.dispose);
        await c.open('qr-bill');
        api.failRelease = true;
        await c.pay([const CheckoutTender('card', 4750)]);
        final saved = (await store.active())!;
        expect(saved.state, 'releasing');
        expect(saved.captures, isEmpty);
        expect(saved.event, isNull);
        expect(saved.tenderMayHaveStarted, true);
        expect(await c.managerTakeover(() async => true), true);
        final managed = CheckoutAttempt.decode(
          (await rawRow())['payload'] as String,
        );
        expect(managed.tenderMayHaveStarted, true);
        expect(managed.json, {...saved.json, 'state': 'managed'});
      },
    );
  }

  test(
    'unknown terminal reply retains started evidence across restart and handover',
    () async {
      final c = controller(
        bank: (_) async => throw StateError('reply lost after dispatch'),
      );
      await c.open('qr-bill');
      await c.pay([const CheckoutTender('bank_pos', 4750)]);
      c.dispose();
      final saved = (await store.active())!;
      expect(saved.state, 'uncertain');
      expect(saved.captures, isEmpty);
      expect(saved.tenderMayHaveStarted, true);
      final resumed = controller();
      addTearDown(resumed.dispose);
      await resumed.open(null);
      expect(resumed.phase, CheckoutPhase.attention);
      expect(await resumed.managerTakeover(() async => true), true);
      expect(jsonDecode((await rawRow())['payload'] as String), {
        ...saved.json,
        'state': 'managed',
      });
      expect(api.pushes, isEmpty);
      expect(api.releases.single['outcome'], 'uncertain');
    },
  );

  test(
    'lost pay ACK retains evidence and replays only the same immutable event',
    () async {
      final c = controller();
      await c.open('qr-bill');
      api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      c.dispose();
      final pending = (await store.active())!;
      expect(pending.state, 'pending');
      expect(pending.tenderMayHaveStarted, true);
      final before = await rawRow();
      final resumed = controller();
      addTearDown(resumed.dispose);
      await resumed.open(null);
      expect(await resumed.managerTakeover(() async => true), true);
      expect(await rawRow(), before);
      api.loseAck = false;
      await resumed.retryAcknowledgement();
      expect(api.pushes, hasLength(2));
      expect(api.pushes[0], pending.event);
      expect(api.pushes[1], pending.event);
      expect(api.commits, 1);
      expect(resumed.phase, CheckoutPhase.paid);
      expect(
        CheckoutAttempt.decode(
          (await rawRow())['payload'] as String,
        ).tenderMayHaveStarted,
        true,
      );
    },
  );

  test(
    'legacy failed-release restart and handover never invent no-tender evidence',
    () async {
      await store.create(_attempt(state: 'releasing'));
      final before = (await store.active())!.json;
      final c = controller();
      addTearDown(c.dispose);
      await c.open(null);
      expect(c.attempt!.tenderMayHaveStarted, isNull);
      expect(await c.managerTakeover(() async => true), true);
      expect(jsonDecode((await rawRow())['payload'] as String), {
        ...before,
        'state': 'managed',
      });
      expect(api.claims, 0);
      expect(api.releases, isEmpty);
      expect(api.pushes, isEmpty);
    },
  );
}
