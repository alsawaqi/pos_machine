import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart' show dineInText;
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/order_attention/order_attention.dart';
import 'package:pos_machine/order_attention/order_attention_host.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/services/live_sync.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';

import 'qr_checkout_fakes.dart';

/// LAUNCH-P6 Part C till fix order 1 — T-2 … T-8 and the three items
/// carried over from the handheld re-review (T-1 is in
/// `launch_p6_till_t1_probe_test.dart`).
Map<String, dynamic> base(String uuid, {Map<String, dynamic>? extra}) => {
  'tablet_order_uuid': uuid,
  'order_uuid': 'order-$uuid',
  'order_type': 'quick',
  'state': 'pending',
  'paid': false,
  'unpaid': true,
  'order_number': '27',
  'table': null,
  'lines': [
    {'product_id': 4, 'product_name': 'Burger', 'qty': 1},
  ],
  'total_baisas': 3000,
  'grand_total_baisas': 3000,
  'taken_by': null,
  'charge': {'state': 'none'},
  'recovery_needed': false,
  ...?extra,
};

class Gateway implements TabletOrdersGateway {
  Gateway(this.rows);
  List<Map<String, dynamic>> rows;
  final calls = <String>[];

  TabletActionResult _act(String uuid, Map<String, dynamic> change) {
    final next = {
      ...rows.firstWhere((r) => r['tablet_order_uuid'] == uuid),
      ...change,
    };
    rows = [
      for (final r in rows)
        if (r['tablet_order_uuid'] == uuid) next else r,
    ];
    return TabletActionResult({'outcome': 'ok', 'order': next});
  }

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async {
    calls.add('list');
    return parseTabletOrderRows(rows);
  }

  @override
  Future<TabletActionResult> take(String uuid, {bool takeOver = false}) async {
    calls.add('take:$uuid');
    return _act(uuid, {
      'taken_by': {'staff_id': 7, 'name': 'Ali'},
    });
  }

  @override
  Future<TabletActionResult> send(String uuid) async {
    calls.add('send:$uuid');
    return _act(uuid, {'state': 'sent'});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class StatusAdapter implements HttpClientAdapter {
  StatusAdapter(this.status, this.code);
  final int status;
  final String code;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'data': {'reason': 'token_invalid'},
      'errors': [
        {'code': code, 'message': code},
      ],
    }),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

class DineGateway implements DineInGateway {
  DineGateway(this.json);
  Map<String, dynamic> json;
  final reviews = <String>[];
  @override
  Future<DineInDetail> detail(int tableId) async => DineInDetail(json);
  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) async {
    reviews.add('${round['id']}:$accept');
    json = {
      ...json,
      'rounds': [
        for (final r in json['rounds'] as List)
          if ((r as Map)['id'] == round['id'])
            {...r, 'status': accept ? 'accepted' : 'rejected'}
          else
            r,
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class NoStore implements DineInStore {
  @override
  Future<DineInRequest?> load() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class Ledger implements AttentionLedger {
  final values = <String, Set<String>>{'scope': {}};
  @override
  Future<Set<String>?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, Set<String> keys) async =>
      values[scope] = {...keys};
}

void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});
  late Gateway gateway;
  late TabletOrdersController controller;
  late List<String> events;

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    Future<bool?> Function(TabletOrderRow)? takeCash,
    bool? prints,
    Future<String?> Function(TabletOrderRow)? moveToCounter,
    ValueNotifier<String?>? requests,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const SizedBox());
    addTearDown(tester.view.reset);
    events = [];
    gateway = Gateway(rows);
    controller = TabletOrdersController(gateway);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TabletOrdersScreen(
          controller: controller,
          openRequests: requests,
          poll: const Duration(hours: 1),
          actions: TabletOrderActions(
            myStaffId: 7,
            authorize: (a, {subtitle, alwaysApproval = false}) async => null,
            takeCash: takeCash,
            printsKitchenTickets: prints == null ? null : () => prints,
            moveToCounter: moveToCounter,
            checkPaymentResult: () async => events.add('check'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  String? notice(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('tablet-sheet-notice')))
      .data;

  test(
    'T-2: a resumed checkout of another order is not this order paid',
    () async {
      final f = CheckoutFixture();
      QrCheckoutController make() => QrCheckoutController(
        gateway: f.api,
        store: f.store,
        now: () => f.now,
        authorizeGift: () async => false,
        captureCard: (_) async =>
            const CheckoutCapture(CheckoutCaptureState.approved),
        captureBank: (_) async =>
            const CheckoutCapture(CheckoutCaptureState.approved),
        staffId: () => 7,
      );
      // A checkout of order "qr-bill" was left reserved on this till.
      final first = make();
      await first.open('qr-bill');
      expect(first.phase, CheckoutPhase.ready);
      first.dispose();
      // Take cash on tablet order #27 resumes it and pays "qr-bill".
      final second = make();
      addTearDown(second.dispose);
      await second.open('order-27');
      await second.pay([const CheckoutTender('cash', 4750)]);
      expect(second.phase, CheckoutPhase.paid);
      expect(second.attempt?.orderUuid, 'qr-bill');
      expect(checkoutPaidFor(second, 'order-27'), isFalse);
      expect(checkoutPaidFor(second, 'qr-bill'), isTrue);
    },
  );

  testWidgets('T-2: then #27 is neither sent nor shown as paid', (
    tester,
  ) async {
    await pump(tester, [base('a')], takeCash: (row) async => null);
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-take-cash');
    expect(gateway.calls, isNot(contains('send:a')));
    expect(notice(tester), contains('another order'));
  });

  testWidgets('T-3: send warns when this till does not print tablet tickets', (
    tester,
  ) async {
    await pump(tester, [base('a'), base('b')], prints: false);
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-send');
    expect(gateway.calls, contains('send:a'));
    expect(notice(tester), startsWith('This till does not print kitchen'));
    await tap(tester, 'tablet-sheet-close');
    // Cash first then send warns too.
    await pump(tester, [base('b')], prints: false, takeCash: (_) async => true);
    await tap(tester, 'tablet-order-b');
    await tap(tester, 'tablet-take-cash');
    expect(gateway.calls, contains('send:b'));
    expect(notice(tester), startsWith('This till does not print kitchen'));
  });

  testWidgets('T-3: no warning when this till prints them', (tester) async {
    await pump(tester, [base('a')], prints: true);
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-send');
    expect(find.byKey(const ValueKey('tablet-sheet-notice')), findsNothing);
  });

  test('T-3: confirming a tablet round on the board warns too', () async {
    Map<String, dynamic> detail(String by) => {
      'table': {'id': 3, 'label': '3'},
      'occupied': true,
      'orphaned': false,
      'seating': {'uuid': 'seat-3', 'table_id': 3, 'status': 'open'},
      'bill': null,
      'rounds': [
        {
          'id': 9,
          'round_no': 1,
          'status': 'pending_confirmation',
          'entered_by': by,
          'priced_lines': <Object>[],
        },
      ],
    };
    for (final (by, off, expected) in [
      ('tablet', true, 'tablet_print_off'),
      ('tablet', false, null),
      ('customer', true, null),
    ]) {
      final c = DineInController(
        DineGateway(detail(by)),
        NoStore(),
        3,
        tabletPrintOff: () => off,
      );
      await c.start();
      await c.review(9, true);
      expect(c.notice, expected, reason: '$by/$off');
      c.dispose();
    }
    expect(
      dineInText(false, 'tablet_print_off'),
      startsWith('This till does not print kitchen tickets'),
    );
    expect(dineInText(true, 'tablet_print_off'), startsWith('هذا الجهاز'));
    expect(
      lookupL10n(const Locale('en')).settingsPrintQrKitchenRounds,
      contains('tablet'),
    );
  });

  testWidgets('T-4: the tablet list never opens over another screen', (
    tester,
  ) async {
    late BuildContext pos;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            pos = context;
            return const Scaffold(body: Text('POS'));
          },
        ),
      ),
    );
    expect(tabletOrdersOpenBlock(pos), isNull);
    Navigator.of(pos).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Shift close')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tabletOrdersOpenBlock(pos), 'Finish this screen first');
  });

  testWidgets('T-5: Open while the list is up reads it, then opens', (
    tester,
  ) async {
    final requests = ValueNotifier<String?>(null);
    await pump(tester, [base('a')], requests: requests);
    // A new order arrives after the list was read.
    gateway.rows = [
      ...gateway.rows,
      base('n', extra: {'order_number': '30'}),
    ];
    requests.value = 'tablet:n';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-sheet-n')), findsOneWidget);
  });

  testWidgets('T-6: a refused Move to counter is shown', (tester) async {
    await pump(tester, [
      base(
        'a',
        extra: {
          'charge': {'state': 'lapsed', 'device_id': 2},
          'recovery_needed': true,
        },
      ),
    ], moveToCounter: (_) async => 'charge_outcome_uncertain');
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-move-counter');
    expect(notice(tester), contains('charge_outcome_uncertain'));
  });

  testWidgets('T-7: a live claim held here offers Check payment result', (
    tester,
  ) async {
    await pump(tester, [
      base(
        'a',
        extra: {
          'charge': {
            'state': 'claimed',
            'device_id': 1,
            'held_by_this_device': true,
          },
        },
      ),
    ]);
    await tap(tester, 'tablet-order-a');
    await tap(tester, 'tablet-check-payment');
    expect(events, ['check']);
  });

  test('T-8: the websocket connect sends X-Pos-Capabilities', () async {
    final seen = Completer<Map<String, dynamic>>();
    final live = LiveSyncService(
      endpointGetter: () => const WebsocketEndpoint(
        appKey: 'key',
        host: 'ws.invalid',
        port: 6001,
        scheme: 'ws',
      ),
      apiBaseUrlGetter: () => 'http://ws.invalid/api/v1',
      channelGetter: () => 'private-branch.1',
      authorize: ({required socketId, required channelName}) async => 'a',
      onLiveEvent: (_) {},
      connectSocket: (url, headers) async {
        if (!seen.isCompleted) seen.complete(headers);
        throw const SocketException('test');
      },
    );
    live.start();
    final headers = await seen.future;
    await live.stop();
    expect(headers['X-Pos-Capabilities'], 'tablet-orders');
  });

  testWidgets('offline: the banner stays, saying alerts are not updating', (
    tester,
  ) async {
    var fail = false;
    late OrderAttentionController attention;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => OrderAttentionHost(
          showBanner: false,
          createController: () => attention = OrderAttentionController(
            identity: () => const AttentionIdentity('scope', 'tok|7'),
            fetch: () async {
              if (fail) throw StateError('offline');
              return {
                'version': 1,
                'quick_order_keys': <String>[],
                'table_round_keys': <String>[],
                'tablet_order_keys': ['tablet:a'],
              };
            },
            ledger: Ledger(),
            play: () async => true,
            stop: () async {},
          ),
          child: child!,
        ),
        home: const SizedBox(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('New tablet order — Tablet'), findsOneWidget);
    fail = true;
    await attention.refresh();
    await tester.pump();
    expect(
      find.text('New tablet order — Tablet · alerts not updating'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test('a later kitchen notice keeps the unreadable count until OK', () {
    final l10n = lookupL10n(const Locale('en'));
    final tally = KitchenUnreadableTally();
    expect(
      tally.compose(
        const QrRoundPrintNotice(QrRoundPrintNoticeKind.unreadable, count: 1),
        '',
        l10n,
      ),
      '1 kitchen ticket could not be read — check with the manager',
    );
    // Another notice replaces the SnackBar: the count stays on it.
    expect(
      tally.compose(
        const QrRoundPrintNotice(QrRoundPrintNoticeKind.printerFailed),
        'Printer failed',
        l10n,
      ),
      'Printer failed\n1 kitchen ticket could not be read — check with the manager',
    );
    tally.compose(
      const QrRoundPrintNotice(QrRoundPrintNoticeKind.unreadable, count: 2),
      '',
      l10n,
    );
    expect(tally.count, 3);
    tally.acknowledge();
    expect(
      tally.compose(
        const QrRoundPrintNotice(QrRoundPrintNoticeKind.printerFailed),
        'Printer failed',
        l10n,
      ),
      'Printer failed',
    );
  });

  test('a claim refused staff_unverified: "Log in again", nothing left '
      '"claiming"', () async {
    final dio = Dio(
      BaseOptions(baseUrl: 'http://t.invalid', validateStatus: (_) => true),
    )..httpClientAdapter = StatusAdapter(403, 'staff_unverified');
    final store = MemoryCheckoutStore();
    final checkout = QrCheckoutController(
      gateway: ApiCheckoutGateway(
        api: PosApiService(tokenGetter: () => 'tok', dio: dio),
        currentScope: () => 's',
        location: () async => null,
        legacyGuard: (_) async {},
      ),
      store: store,
      authorizeGift: () async => false,
      captureCard: (_) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
      captureBank: (_) async =>
          const CheckoutCapture(CheckoutCaptureState.approved),
    );
    addTearDown(checkout.dispose);
    await checkout.open('order-a');
    expect(checkout.notice, 'staff_unverified');
    expect(store.value?.state, 'released');
    expect(await store.active(), isNull);
  });

  testWidgets('"Log in again" in EN and AR', (tester) async {
    final texts = <String>[];
    for (final locale in const [Locale('en'), Locale('ar')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              texts.add(checkoutText(context, 'staff_unverified'));
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(texts, ['Log in again', 'سجّل الدخول مرة أخرى']);
  });
}
