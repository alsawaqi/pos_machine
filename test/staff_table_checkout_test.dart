import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'qr_checkout_fakes.dart';
import 'qr_quick_gateway_test.dart' show QuickAdapter;
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;
import 'draft_recovery_test.dart' as recovery;

Map<String, dynamic> staffDetail(String source) {
  final value = tableFixture(source: source);
  (value['bill'] as Map).addAll(<String, Object>{
    'checkout_policy': 'staff_table_claim_v1',
    'order_type': 'dine_in',
    'table_id': 1,
  });
  return value;
}

class StaffCheckoutGateway extends CheckoutFakeGateway {
  StaffCheckoutGateway(this.source);
  final String source;
  @override
  Future<Map<String, dynamic>> snapshot(String uuid) async {
    final data = await super.snapshot(uuid);
    (data['order'] as Map).addAll(<String, Object>{
      'source': source,
      'order_type': 'dine_in',
      'table_id': 1,
      'checkout_policy': 'staff_table_claim_v1',
    });
    return data;
  }
}

QrCheckoutController staffController(
  StaffCheckoutGateway gateway,
  MemoryCheckoutStore store, {
  CheckoutCaptureState capture = CheckoutCaptureState.approved,
}) => QrCheckoutController(
  gateway: gateway,
  store: store,
  now: () => checkoutTime,
  authorizeGift: () async => true,
  captureCard: (_) async => CheckoutCapture(capture),
  captureBank: (_) async => CheckoutCapture(capture),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final source in ['main_pos', 'handheld']) {
    test(
      '$source explicit capability permits same-bill checkout without QR identity',
      () async {
        final api = TableFake()..value = staffDetail(source);
        final c = DineInController(api, TableMemory(), 2);
        addTearDown(c.dispose);
        await c.start();
        expect(c.detail!.qrBill, false);
        expect(c.detail!.protectedCheckout, true);
        expect(c.canPay, true);
        expect(c.detail!.bill!['source'], source);
        expect(c.detail!.coveredTableIds, {1, 2});
        await c.reopen();
        expect(api.calls, contains('reopen:bill-1'));
      },
    );

    for (final defect in [
      'old_server',
      'future_policy',
      'wrong_table',
      'missing_seat',
      'quick',
    ]) {
      test('$source/$defect cannot enable protected staff payment', () {
        final data = staffDetail(source);
        final bill = data['bill'] as Map;
        switch (defect) {
          case 'old_server':
            bill.remove('checkout_policy');
          case 'future_policy':
            bill['checkout_policy'] = 'staff_table_claim_v2';
          case 'wrong_table':
            bill['table_id'] = 99;
          case 'missing_seat':
            data['seating'] = null;
          case 'quick':
            bill['order_type'] = 'quick';
        }
        expect(DineInDetail(data).protectedCheckout, false);
      });
    }

    for (final block in ['pending', 'own_local', 'joined_local', 'offline']) {
      test('$source/$block retains the checkout gate', () async {
        final api = TableFake()..value = staffDetail(source);
        if (block == 'pending') {
          (api.value['rounds'] as List).first['status'] =
              'pending_confirmation';
        }
        final c = DineInController(
          api,
          TableMemory(),
          2,
          localDraftTables: () => {
            if (block == 'own_local') 1,
            if (block == 'joined_local') 2,
          },
        );
        addTearDown(c.dispose);
        await c.start();
        if (block == 'offline') {
          api.failRead = true;
          await c.refresh();
        }
        expect(c.canPay, false);
        expect(api.requests, isEmpty);
      });
    }

    test(
      '$source claimed snapshot is frozen; absent capability cannot be inferred',
      () async {
        final api = StaffCheckoutGateway(source);
        final json = await api.snapshot('qr-bill');
        final before = jsonEncode(json);
        final claim = CheckoutClaim(claimJson());
        final snapshot = CheckoutSnapshot(json, claim);
        expect(snapshot.order['source'], source);
        expect(snapshot.total, 4750);
        expect(snapshot.uuid, 'qr-bill');
        expect(jsonEncode(json), before);
        expect(
          () => (snapshot.order['items'] as List).clear(),
          throwsUnsupportedError,
        );
        for (final defect in ['policy', 'table', 'amount', 'source']) {
          final invalid = checkoutMap(jsonDecode(before));
          final order = invalid['order'] as Map;
          switch (defect) {
            case 'policy':
              order.remove('checkout_policy');
            case 'table':
              order['table_id'] = 0;
            case 'amount':
              order['grand_total_baisas'] = 4751;
            case 'source':
              order['source'] = 'unknown';
          }
          expect(() => CheckoutSnapshot(invalid, claim), throwsFormatException);
        }
      },
    );

    for (final method in ['cash', 'card', 'bank_pos', 'gift', 'split']) {
      test(
        '$source/$method uses reservation replay and one unchanged standalone payment',
        () async {
          final api = StaffCheckoutGateway(source);
          final store = MemoryCheckoutStore();
          final c = staffController(api, store);
          addTearDown(c.dispose);
          await c.open('qr-bill');
          expect(c.ready, true);
          final plan = method == 'split'
              ? [
                  const CheckoutTender('cash', 2000),
                  const CheckoutTender('bank_pos', 2750),
                ]
              : [CheckoutTender(method, 4750)];
          await c.pay(plan);
          expect(c.phase, CheckoutPhase.paid);
          // Initial claim + pre-tender replay + one extra replay for each
          // physical card/bank leg, exactly as in the unchanged coordinator.
          expect(
            api.claims,
            2 +
                plan
                    .where((t) => t.method == 'card' || t.method == 'bank_pos')
                    .length,
          );
          expect(api.commits, 1);
          expect(api.pushes, hasLength(1));
          final event = api.pushes.single;
          expect(event['event_type'], 'order.pay');
          final payload = event['payload'] as Map;
          expect(payload['order_uuid'], 'qr-bill');
          expect(payload.containsKey('items'), false);
          expect(payload.containsKey('gps'), false);
          expect(payload['payments'], plan.map((t) => t.json).toList());
          expect(c.snapshot!.order['source'], source);
          await c.pay(plan);
          expect(api.pushes, hasLength(1));
        },
      );
    }

    test(
      '$source lost payment ACK retries immutable event without new capture',
      () async {
        final api = StaffCheckoutGateway(source)..loseAck = true;
        final store = MemoryCheckoutStore();
        var c = staffController(api, store);
        await c.open('qr-bill');
        await c.pay([const CheckoutTender('cash', 4750)]);
        final event = jsonEncode(api.pushes.single);
        expect(c.phase, CheckoutPhase.pending);
        c.dispose();
        api.loseAck = false;
        c = staffController(api, store);
        addTearDown(c.dispose);
        await c.open(null);
        await c.retryAcknowledgement();
        expect(c.phase, CheckoutPhase.paid);
        expect(api.claims, 2);
        expect(api.commits, 1);
        expect(api.pushes.map(jsonEncode).toSet(), {event});
      },
    );

    test(
      '$source refused reservation replay starts no tender or pay',
      () async {
        final api = StaffCheckoutGateway(source)..refuseClaimAt = 2;
        final store = MemoryCheckoutStore();
        var captures = 0;
        final c = QrCheckoutController(
          gateway: api,
          store: store,
          now: () => checkoutTime,
          captureCard: (_) async {
            captures++;
            return const CheckoutCapture(CheckoutCaptureState.approved);
          },
          captureBank: (_) async {
            captures++;
            return const CheckoutCapture(CheckoutCaptureState.approved);
          },
          authorizeGift: () async => true,
        );
        addTearDown(c.dispose);
        await c.open('qr-bill');
        await c.pay([const CheckoutTender('card', 4750)]);
        expect(captures, 0);
        expect(api.pushes, isEmpty);
        expect(api.releases.single['outcome'], 'cancelled');
      },
    );

    test(
      '$source uncertain card stays retained without any payment retry',
      () async {
        final api = StaffCheckoutGateway(source);
        final store = MemoryCheckoutStore();
        final c = staffController(
          api,
          store,
          capture: CheckoutCaptureState.uncertain,
        );
        addTearDown(c.dispose);
        await c.open('qr-bill');
        await c.pay([const CheckoutTender('card', 4750)]);
        expect(api.pushes, isEmpty);
        expect(api.releases.single['outcome'], 'uncertain');
        expect(store.value!.captures, isNotEmpty);
        expect(c.canLeave, false);
      },
    );

    test('$source recovery requires the explicit server capability', () {
      final data = recovery.previewValue();
      final bill = (data['proof'] as Map)['bill'] as Map;
      bill['source'] = source;
      expect(() => RecoveryPreview(data), throwsStateError);
      bill['checkout_policy'] = 'staff_table_claim_v1';
      expect(RecoveryPreview(data).proof['bill']['source'], source);
      bill['source'] = 'unknown';
      expect(() => RecoveryPreview(data), throwsStateError);
    });

    testWidgets(
      '$source Dine-In Pay sends only canonical UUID to existing payment host',
      (tester) async {
        tester.view.physicalSize = const Size(600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = TableFake()..value = staffDetail(source);
        final before = jsonEncode(api.value);
        final paid = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: DineInScreen(
              label: 'T2',
              catalogue: () => [],
              createController: () async =>
                  DineInController(api, TableMemory(), 2),
              onPay: (uuid) async {
                paid.add(uuid);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const ValueKey('dine-pay')));
        await tester.tap(find.byKey(const ValueKey('dine-pay')));
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        expect(api.requests, isEmpty);
        expect(jsonEncode(api.value), before);
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final status in [409, 500]) {
    test(
      'owner-device refusal HTTP $status is classified without treating uncertainty as no-claim',
      () async {
        final adapter = QuickAdapter()..status = status;
        adapter.data = {
          'data': null,
          'errors': [
            {
              'code': 'staff_bill_owner_required',
              'message': 'Original device recovery required',
            },
          ],
        };
        final api = PosApiService(
          tokenGetter: () => 'test',
          dio: Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
            ..httpClientAdapter = adapter,
        );
        final gateway = ApiCheckoutGateway(
          api: api,
          currentScope: () => 'scope',
          location: () async => null,
          legacyGuard: (_) async {},
        );
        await expectLater(
          gateway.claim('qr-bill'),
          throwsA(status == 409 ? isA<CheckoutRefusal>() : isA<ApiException>()),
        );
        expect(adapter.requests, hasLength(1));
      },
    );
  }
}
