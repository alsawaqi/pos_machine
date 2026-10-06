import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart' show dineInText;
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart'
    show DiningTableActivityBadge, tableBillNeedsSheet;
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

import 'qr_checkout_fakes.dart';

/// LAUNCH-P6 Part C items 2, 6, 7 and 8 (till) — `customer_tablet` in the
/// QR checkout and table models, the tablet round labelled "Tablet" and
/// confirmed through the staff table route, `staff_id` on every order.pay,
/// and tablet kitchen rounds printed from the accepted-round feed.
class TabletCheckoutGateway extends CheckoutFakeGateway {
  TabletCheckoutGateway(this.orderType);
  final String orderType;
  @override
  Future<Map<String, dynamic>> snapshot(String uuid) async {
    final data = await super.snapshot(uuid);
    final order = Map<String, dynamic>.from(data['order'] as Map)
      ..['source'] = 'customer_tablet'
      ..['order_type'] = orderType;
    return {...data, 'order': order};
  }
}

class PathAdapter implements HttpClientAdapter {
  PathAdapter(this.routes);
  final Map<String, Object> routes;
  final seen = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'data': routes[options.path] ?? <String, dynamic>{},
        'meta': <String, dynamic>{},
        'errors': [],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

(PosApiService, PathAdapter) api(Map<String, Object> routes) {
  final adapter = PathAdapter(routes);
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://till.invalid/api/v1',
      validateStatus: (_) => true,
    ),
  )..httpClientAdapter = adapter;
  return (PosApiService(tokenGetter: () => 'tok', dio: dio), adapter);
}

Map<String, dynamic> detailJson(String enteredBy) => {
  'table': {'id': 5, 'label': '5'},
  'occupied': true,
  'orphaned': false,
  'seating': {'uuid': 'seat-1', 'table_id': 5},
  'bill': null,
  'rounds': [
    {
      'id': 44,
      'round_no': 2,
      'status': 'pending_confirmation',
      'entered_by': enteredBy,
      'priced_lines': <Object>[],
      'tablet_order_uuid': 't-1',
    },
  ],
};

void main() {
  for (final type in ['quick', 'to_go']) {
    test(
      'a tablet $type order is claimed and paid in cash with staff_id',
      () async {
        final f = CheckoutFixture();
        final gateway = TabletCheckoutGateway(type);
        final c = QrCheckoutController(
          gateway: gateway,
          store: f.store,
          now: () => f.now,
          newId: () => 'payment-attempt-1',
          authorizeGift: () async => false,
          captureCard: (_) async =>
              const CheckoutCapture(CheckoutCaptureState.approved),
          captureBank: (_) async =>
              const CheckoutCapture(CheckoutCaptureState.approved),
          staffId: () => 7,
        );
        addTearDown(c.dispose);
        await c.open('qr-bill');
        expect(c.phase, CheckoutPhase.ready);
        expect(c.total, 4750);
        await c.pay([const CheckoutTender('cash', 4750)]);
        expect(c.phase, CheckoutPhase.paid);
        final payload = gateway.pushes.single['payload'] as Map;
        expect(payload['staff_id'], 7);
        expect(payload['payments'], [
          {'method': 'cash', 'amount_baisas': 4750, 'status': 'success'},
        ]);
      },
    );
  }

  test('the existing QR checkout order.pay also names the payer', () async {
    final f = CheckoutFixture();
    final c = QrCheckoutController(
      gateway: f.api,
      store: f.store,
      now: () => f.now,
      newId: () => 'payment-attempt-1',
      authorizeGift: () async => false,
      captureCard: (_) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
      captureBank: (_) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
      staffId: () => 9,
    );
    addTearDown(c.dispose);
    await c.open('qr-bill');
    await c.pay([const CheckoutTender('cash', 4750)]);
    expect((f.api.pushes.single['payload'] as Map)['staff_id'], 9);
  });

  test('tablet table bills use the staff table checkout policy', () {
    expect(
      hasStaffTableCheckoutPolicy({
        'source': 'customer_tablet',
        'checkout_policy': 'staff_table_claim_v1',
      }),
      isTrue,
    );
    expect(
      isTabletCounterCheckout({
        'source': 'customer_tablet',
        'order_type': 'dine_in',
        'table_id': 5,
      }),
      isFalse,
    );
    expect(
      tableBillNeedsSheet(
        'live',
        RemoteTableState(
          tableId: 5,
          fetchedAt: DateTime.utc(2026, 10, 6),
          billOrderUuid: 'b-1',
          billSource: 'customer_tablet',
        ),
      ),
      isTrue,
    );
  });

  test(
    'Back on a claimed tablet order releases it with cancel-settlement',
    () async {
      final (service, adapter) = api({
        '/device/qr/claim-settlement': claimJson(),
        '/device/qr/orders/qr-bill/checkout': {
          ...snapshotJson(),
          'order': {
            ...(snapshotJson()['order'] as Map),
            'source': 'customer_tablet',
            'order_type': 'to_go',
          },
        },
      });
      final gateway = ApiCheckoutGateway(
        api: service,
        currentScope: () => 'scope',
        location: () async => null,
        legacyGuard: (_) async {},
      );
      await gateway.claim('qr-bill');
      await gateway.snapshot('qr-bill');
      await gateway.release('qr-bill', 'cancelled', const []);
      expect(adapter.seen.last.path, '/device/qr/cancel-settlement');
    },
  );

  test('a tablet round is read, labelled and confirmed by staff', () async {
    // Before: one tablet round made the whole table detail unreadable.
    final detail = DineInDetail(detailJson('tablet'));
    expect(detail.pendingReview, isTrue);
    expect(dineInText(false, 'tablet'), 'Tablet');
    expect(dineInText(true, 'tablet'), 'الجهاز اللوحي');
    final (service, adapter) = api({
      '/device/tables/seat-1/rounds/44/confirm': {'outcome': 'accepted'},
    });
    final gateway = ApiDineInGateway(service, () => 'scope');
    await gateway.review(detail, detail.rounds.single, true);
    expect(adapter.seen.single.path, '/device/tables/seat-1/rounds/44/confirm');
    expect(adapter.seen.single.headers['X-Pos-Capabilities'], 'tablet-orders');
  });

  testWidgets('the floor plan says how many rounds a tablet sent', (
    tester,
  ) async {
    final row = TableActivityBoardRow.fromBoard({
      'table_id': 5,
      'table_label': '5',
      'bill': {'pending_rounds': 2},
      'seating': {
        'pending_rounds': [
          {'round_id': 1, 'origin': 'customer_tablet', 'priced_lines': []},
          {'round_id': 2, 'origin': null, 'priced_lines': []},
        ],
      },
    });
    expect(row.tabletPendingCount, 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(
          body: DiningTableActivityBadge(
            mode: 'live',
            pendingRounds: 2,
            tabletRounds: 1,
          ),
        ),
      ),
    );
    expect(find.textContaining('Tablet: 1 waiting'), findsOneWidget);
  });

  test('a tablet kitchen round prints from the feed like a QR round', () {
    final quick = QrRoundEnvelope.fromFeedJson({
      'id': 70,
      'round_no': 1,
      'order_uuid': 'o-1',
      'order_type': 'to_go',
      'origin': 'customer_tablet',
      'tablet_order_uuid': 't-1',
      'order_number': '27',
      'temp_reference': 'T-1006-27',
      'ticket_key': 'round:70',
      'priced_lines': [
        {'product_id': 4, 'product_name': 'Burger', 'qty': 2},
      ],
    });
    expect(quick.fromTablet, isTrue);
    final en = buildQrKitchenTicket(quick, arabic: false);
    expect(en.orderLabel, '#27');
    expect(en.orderTypeLabel, 'TABLET · TO GO');
    expect(en.items, hasLength(1));
    final ar = buildQrKitchenTicket(quick, arabic: true);
    expect(ar.orderTypeLabel, 'جهاز لوحي · سفري');
    final dineIn = QrRoundEnvelope.fromFeedJson({
      'id': 71,
      'round_no': 3,
      'order_uuid': 'o-2',
      'order_type': 'dine_in',
      'origin': 'customer_tablet',
      'table_label': '5',
      'priced_lines': const [],
    });
    final ticket = buildQrKitchenTicket(dineIn, arabic: false);
    expect(ticket.orderTypeLabel, 'TABLET DINE-IN · ROUND 3');
    expect(ticket.tableLabel, '5');
    // QR rounds keep their ticket.
    final qr = QrRoundEnvelope.fromFeedJson({
      'id': 72,
      'round_no': 1,
      'order_uuid': 'o-3',
      'priced_lines': const [],
    });
    expect(
      buildQrKitchenTicket(qr, arabic: false).orderTypeLabel,
      'QR DINE-IN · ROUND 1',
    );
  });
}
