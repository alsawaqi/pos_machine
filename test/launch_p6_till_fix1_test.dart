import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
// Test-only: fake_async ships with flutter_test (already in the lock).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/order_attention/order_attention.dart';
import 'package:pos_machine/order_attention/order_attention_host.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LAUNCH-P6 Part C (till) — the handheld fix order 1 rules applied to the
/// till: H-1 points first, H-2 stable tree, M-1 taker rule on cash, and the
/// LOW items (poll generation, one list, no ring while stale, a visible
/// unreadable kitchen-row notice, no points on a paid dine-in, specific
/// refusal texts, Move to counter on `uncertain`).
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
  'phone_masked': '9xxx1234',
  'redeem': null,
  'taken_by': null,
  'charge': {'state': 'none'},
  'recovery_needed': false,
  ...?extra,
};

const requested = {
  'status': 'requested',
  'rule_id': 3,
  'kind': 'points',
  'blocks': 1,
  'units': 50,
  'amount_baisas': 500,
  'available': true,
};

class Gateway implements TabletOrdersGateway {
  Gateway(this.rows);
  List<Map<String, dynamic>> rows;
  final calls = <String>[];
  Completer<List<TabletOrderRow>>? listWait;

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async {
    calls.add('list');
    final wait = listWait;
    if (wait != null) {
      listWait = null;
      return wait.future;
    }
    return parseTabletOrderRows(rows);
  }

  @override
  Future<TabletActionResult> take(String uuid, {bool takeOver = false}) async {
    calls.add('take:$uuid');
    final next = {
      ...rows.firstWhere((r) => r['tablet_order_uuid'] == uuid),
      'taken_by': {'staff_id': 7, 'name': 'Ali'},
    };
    rows = [next];
    return TabletActionResult({'outcome': 'taken', 'order': next});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class ErrorAdapter implements HttpClientAdapter {
  ErrorAdapter(this.code);
  final String code;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode({
      'data': null,
      'errors': [
        {'code': code, 'message': code},
      ],
    }),
    409,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

class FeedGateway implements QrRoundGateway {
  @override
  Future<QrAcceptedRoundsPage> fetchAcceptedRounds({
    String? after,
    int limit = 25,
  }) async => const QrAcceptedRoundsPage(
    rounds: [],
    skippedExpiredCount: 0,
    skippedUnreadableCount: 1,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class NoKitchen implements KitchenPrintGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class NoPrinter implements QrKitchenRoundPrinter {
  @override
  Future<bool> printRound(QrRoundEnvelope e, {required bool arabic}) async =>
      true;
}

class Ledger implements AttentionLedger {
  final values = <String, Set<String>>{'scope': {}};
  @override
  Future<Set<String>?> read(String scope) async => values[scope];
  @override
  Future<void> write(String scope, Set<String> keys) async =>
      values[scope] = {...keys};
}

class Probe extends StatefulWidget {
  const Probe({super.key, required this.events});
  final List<String> events;
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  @override
  void initState() {
    super.initState();
    widget.events.add('init');
  }

  @override
  void dispose() {
    widget.events.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('app-wide state');
}

void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});
  late Gateway gateway;
  late TabletOrdersController controller;
  late List<String> events;

  TabletOrderActions actions() => TabletOrderActions(
    myStaffId: 7,
    authorize: (action, {subtitle, alwaysApproval = false}) async => null,
    takeCash: (row) async {
      events.add('cash');
      return true;
    },
    openTable: (row) => events.add('table'),
    moveToCounter: (row) async {
      events.add('counter');
      return null;
    },
    paymentReview: (row) async => events.add('review'),
    checkPaymentResult: () async => events.add('check'),
  );

  Future<void> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> rows, {
    ValueNotifier<String?>? requests,
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
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
          actions: actions(),
          openRequests: requests,
          poll: const Duration(hours: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }

  testWidgets('H-1: open points request disables Take cash', (tester) async {
    await pump(tester, [
      base('a', extra: {'redeem': requested}),
    ]);
    await tap(tester, 'tablet-order-a');
    final cash = tester.widget<FilledButton>(
      find.byKey(const ValueKey('tablet-take-cash')),
    );
    expect(cash.onPressed, isNull);
    expect(find.byKey(const ValueKey('tablet-points-first')), findsOneWidget);
    expect(find.text('Answer the points request first'), findsOneWidget);
  });

  testWidgets('H-1: Open the table warns while points are open', (
    tester,
  ) async {
    await pump(tester, [
      base(
        'd',
        extra: {
          'order_type': 'dine_in',
          'state': 'sent',
          'order_number': null,
          'table': {'id': 6, 'uuid': 't6', 'name': '6'},
          'redeem': requested,
        },
      ),
    ]);
    await tap(tester, 'tablet-order-d');
    await tap(tester, 'tablet-cancel');
    expect(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('Answer the points request first'),
      ),
      findsOneWidget,
    );
    await tap(tester, 'tablet-confirm-no');
    expect(events, isEmpty);
    await tap(tester, 'tablet-cancel');
    await tap(tester, 'tablet-confirm-yes');
    expect(events, ['table']);
  });

  test('H-1 / M-1: the claim refusals redeem_pending and tablet_order_taken '
      'are final', () async {
    for (final code in ['redeem_pending', 'tablet_order_taken']) {
      final dio = Dio(
        BaseOptions(baseUrl: 'http://t.invalid', validateStatus: (_) => true),
      )..httpClientAdapter = ErrorAdapter(code);
      final checkout = ApiCheckoutGateway(
        api: PosApiService(tokenGetter: () => 'tok', dio: dio),
        currentScope: () => 's',
        location: () async => null,
        legacyGuard: (_) async {},
      );
      await expectLater(
        checkout.claim('order-a'),
        throwsA(isA<CheckoutRefusal>().having((r) => r.code, 'code', code)),
      );
    }
  });

  testWidgets('H-1 / M-1: their checkout texts are specific (EN/AR)', (
    tester,
  ) async {
    final texts = <String>[];
    for (final locale in const [Locale('en'), Locale('ar')]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) {
              texts
                ..add(checkoutText(context, 'redeem_pending'))
                ..add(checkoutText(context, 'tablet_order_taken'));
              return const SizedBox();
            },
          ),
        ),
      );
    }
    expect(texts, [
      'Answer the points request first',
      'Another staff member has this tablet order. Take it over first.',
      'أجب على طلب النقاط أولاً',
      'هذا الطلب مع موظف آخر. استلمه بدلاً منه أولاً.',
    ]);
  });

  testWidgets('M-1: taken by another — no Take cash, only Take over', (
    tester,
  ) async {
    await pump(tester, [
      base(
        'a',
        extra: {
          'taken_by': {'staff_id': 9, 'name': 'Sara'},
        },
      ),
    ]);
    await tap(tester, 'tablet-order-a');
    expect(find.byKey(const ValueKey('tablet-take-cash')), findsNothing);
    expect(find.byKey(const ValueKey('tablet-take-over')), findsOneWidget);
  });

  testWidgets('H-2: the tablet banner never recreates app-wide state', (
    tester,
  ) async {
    final probe = <String>[];
    var response = <String, dynamic>{
      'version': 1,
      'quick_order_keys': <String>[],
      'table_round_keys': <String>[],
    };
    late OrderAttentionController attention;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => OrderAttentionHost(
          showBanner: false,
          createController: () => attention = OrderAttentionController(
            identity: () => const AttentionIdentity('scope', 'tok|7'),
            fetch: () async => response,
            ledger: Ledger(),
            play: () async => true,
            stop: () async {},
          ),
          child: Probe(events: probe),
        ),
        home: const SizedBox(),
      ),
    );
    await tester.pump();
    for (final keys in [
      ['tablet:a'],
      <String>[],
      ['tablet:b'],
      <String>[],
    ]) {
      response = {...response, 'tablet_order_keys': keys};
      await attention.refresh();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('tablet-attention-banner')),
        keys.isEmpty ? findsNothing : findsOneWidget,
      );
    }
    expect(probe, ['init'], reason: 'created once, never disposed');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('LOW-1: a poll older than an action is dropped', (tester) async {
    await pump(tester, [base('a')]);
    final stale = Completer<List<TabletOrderRow>>();
    gateway.listWait = stale;
    final read = controller.refresh();
    await controller.take('a');
    expect(controller.find('a')!.takenBy?.name, 'Ali');
    stale.complete(parseTabletOrderRows([base('a')]));
    await read;
    expect(controller.find('a')!.takenBy?.name, 'Ali');
  });

  testWidgets('LOW-2: an Open request uses the open list, one sheet only', (
    tester,
  ) async {
    final requests = ValueNotifier<String?>(null);
    await pump(tester, [
      base('a'),
      base('b', extra: {'order_number': '28'}),
    ], requests: requests);
    requests.value = 'tablet:a';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-sheet-a')), findsOneWidget);
    requests.value = 'tablet:b';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-sheet-b')), findsNothing);
    expect(find.byType(TabletOrdersScreen), findsOneWidget);
  });

  test('LOW-3: no repeat ring while the attention reads fail', () {
    fakeAsync((async) {
      var plays = 0;
      Object? fail;
      final c = OrderAttentionController(
        identity: () => const AttentionIdentity('scope', 'tok|7'),
        fetch: () async {
          if (fail != null) throw fail;
          return {
            'version': 1,
            'quick_order_keys': <String>[],
            'table_round_keys': <String>[],
            'tablet_order_keys': ['tablet:a'],
          };
        },
        ledger: Ledger(),
        play: () async {
          plays++;
          return true;
        },
        stop: () async {},
      );
      c.refresh();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      final before = plays;
      expect(before, greaterThan(0));
      fail = StateError('offline');
      c.refresh();
      async.flushMicrotasks();
      expect(c.stale, isTrue);
      async.elapse(const Duration(seconds: 60));
      expect(plays, before);
      c.dispose();
    });
  });

  test(
    'LOW-4: an unreadable kitchen-feed row raises a visible notice',
    () async {
      SharedPreferences.setMockInitialValues({
        'qr_round_print_cursor_KIOSK-1': 'c-1',
      });
      final notices = <QrRoundPrintNotice>[];
      final printing = QrRoundAutoPrintController(
        gateway: FeedGateway(),
        kitchenGateway: NoKitchen(),
        preferences: await SharedPreferences.getInstance(),
        printer: NoPrinter(),
        deviceKey: () => 'KIOSK-1',
        arabic: () => false,
        onNotice: notices.add,
        onPollingStatus: (_) {},
        pollInterval: const Duration(days: 1),
      );
      await printing.setEnabled(true);
      expect(notices.single.kind, QrRoundPrintNoticeKind.unreadable);
      expect(notices.single.count, 1);
      printing.stop();
      expect(
        lookupL10n(const Locale('en')).tabletKitchenUnreadable(1),
        '1 kitchen ticket could not be read — check with the manager',
      );
      expect(
        lookupL10n(const Locale('ar')).tabletKitchenUnreadable(1),
        isNot(lookupL10n(const Locale('en')).tabletKitchenUnreadable(1)),
      );
    },
  );

  testWidgets('LOW-5: no points approve or reject on a paid dine-in order', (
    tester,
  ) async {
    await pump(tester, [
      base(
        'd',
        extra: {
          'order_type': 'dine_in',
          'state': 'sent',
          'paid': true,
          'unpaid': false,
          'order_number': null,
          'table': {'id': 6, 'uuid': 't6', 'name': '6'},
          'redeem': requested,
        },
      ),
    ]);
    // A paid order leaves the open list; open its sheet directly.
    await tester.tap(find.byKey(const ValueKey('tablet-order-d')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-redeem-approve')), findsNothing);
    expect(find.byKey(const ValueKey('tablet-redeem-reject')), findsNothing);
  });

  test('LOW-6: specific texts for rate limits, bill_reserved, update', () {
    for (final locale in const [Locale('en'), Locale('ar')]) {
      final l10n = lookupL10n(locale);
      final generic = l10n.tabletRefusedGeneric('x');
      for (final code in [
        'too_many_attempts',
        'rate_limited',
        'bill_reserved',
        'tablet_round_needs_update',
        'redeem_pending',
      ]) {
        final text = tabletNoticeText(l10n, code, null);
        expect(text, isNot(contains(code)));
        expect(text, isNot(generic));
      }
    }
    final en = lookupL10n(const Locale('en'));
    expect(
      tabletNoticeText(en, 'rate_limited', null),
      tabletNoticeText(en, 'too_many_attempts', null),
    );
  });

  testWidgets('LOW-7: Move to counter on uncertain as well as lapsed', (
    tester,
  ) async {
    await pump(tester, [
      base(
        'u',
        extra: {
          'charge': {'state': 'uncertain', 'device_id': 2},
          'recovery_needed': true,
        },
      ),
    ]);
    await tap(tester, 'tablet-order-u');
    await tap(tester, 'tablet-move-counter');
    expect(events, ['counter']);
  });

  test('QR quick review rows keep their shape', () {
    final order = QrQuickOrder.review(uuid: 'o', reference: 'T-1', total: 5);
    expect(order.total, 5);
  });
}
