// Test-only: fake_async ships with flutter_test (already in the lock).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/order_attention/order_attention.dart';
import 'package:pos_machine/order_attention/order_attention_host.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';

/// LAUNCH-P6 Part C item 3 (till) — tablet attention keys, the visible
/// "New tablet order — Table 5" / "#27" banner, and a ring that repeats
/// every 10 s until the order is opened here or taken on any device.
class MemoryLedger implements AttentionLedger {
  final values = <String, Set<String>>{};
  @override
  Future<Set<String>?> read(String scope) async =>
      values[scope] == null ? null : {...values[scope]!};
  @override
  Future<void> write(String scope, Set<String> keys) async =>
      values[scope] = {...keys};
}

Map<String, dynamic> snapshot({
  List<String> quick = const [],
  List<Object?>? tablet,
}) => {
  'version': 1,
  'quick_order_keys': quick,
  'table_round_keys': const <String>[],
  'tablet_order_keys': ?tablet,
};

TabletOrderRow row(String uuid, {String type = 'quick', String? table}) =>
    TabletOrderRow({
      'tablet_order_uuid': uuid,
      'order_uuid': 'o-$uuid',
      'order_type': type,
      'state': 'pending',
      'paid': false,
      'unpaid': true,
      'order_number': type == 'dine_in' ? null : '27',
      'table': table == null ? null : {'id': 5, 'uuid': 'tb', 'name': table},
      'lines': const <Object>[],
      'total_baisas': 1000,
      'grand_total_baisas': 1000,
    });

void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});

  test('tablet keys are read; a bad tablet key never breaks QR alerts', () {
    final parsed = AttentionSnapshot.parse(
      snapshot(quick: ['quick:a'], tablet: ['tablet:t1', 9, 'other:x']),
    );
    expect(parsed.quick, {'quick:a'});
    expect(parsed.tablet, {'tablet:t1'});
    expect(parsed.keys, {'quick:a', 'tablet:t1'});
    // An older server (no tablet list) is still a valid snapshot.
    expect(AttentionSnapshot.parse(snapshot()).tablet, isEmpty);
  });

  group('ring', () {
    late MemoryLedger ledger;
    late Map<String, dynamic> response;
    late int plays, stops;
    OrderAttentionController make() => OrderAttentionController(
      identity: () => const AttentionIdentity('scope', 'tok|7'),
      fetch: () async => response,
      ledger: ledger,
      play: () async {
        plays++;
        return true;
      },
      stop: () async {
        stops++;
      },
    );
    setUp(() {
      ledger = MemoryLedger();
      response = snapshot();
      plays = stops = 0;
    });

    test('repeats every 10 s until the order is opened here', () {
      fakeAsync((async) {
        final c = make();
        c.refresh();
        async.flushMicrotasks();
        response = snapshot(tablet: ['tablet:t1']);
        c.refresh();
        async.flushMicrotasks();
        expect(plays, 1, reason: 'a new tablet order rings at once');
        async.elapse(const Duration(seconds: 10));
        expect(plays, 2);
        async.elapse(const Duration(seconds: 20));
        expect(plays, 4);
        expect(c.ringing, {'tablet:t1'});
        c.opened('tablet:t1');
        expect(c.ringing, isEmpty);
        expect(stops, greaterThan(0));
        async.elapse(const Duration(seconds: 60));
        expect(plays, 4, reason: 'opened here: no more rings');
        c.dispose();
      });
    });

    test('stops on every device once taken (the key leaves the list)', () {
      fakeAsync((async) {
        final c = make();
        response = snapshot(tablet: ['tablet:t1']);
        c.refresh(); // first use: baseline silently, then repeat
        async.flushMicrotasks();
        expect(plays, 0);
        async.elapse(const Duration(seconds: 10));
        expect(plays, 1, reason: 'a waiting tablet order rings until taken');
        response = snapshot(); // taken on another device
        c.refresh();
        async.flushMicrotasks();
        expect(c.ringing, isEmpty);
        async.elapse(const Duration(seconds: 60));
        expect(plays, 1);
        c.dispose();
      });
    });

    test('a QR quick order still rings once only', () {
      fakeAsync((async) {
        final c = make();
        c.refresh();
        async.flushMicrotasks();
        response = snapshot(quick: ['quick:a']);
        c.refresh();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 60));
        expect(plays, 1);
        c.dispose();
      });
    });
  });

  testWidgets('the till shows "New tablet order — Table 5" and Open', (
    tester,
  ) async {
    final ledger = MemoryLedger()..values['scope'] = {};
    var response = snapshot(tablet: ['tablet:d1', 'tablet:q1']);
    final opened = <String?>[];
    tabletOrdersOpener.value = opened.add;
    addTearDown(() => tabletOrdersOpener.value = null);
    late OrderAttentionController controller;
    Future<void> pump(Locale locale) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => OrderAttentionHost(
            showBanner: false,
            createController: () => controller = OrderAttentionController(
              identity: () => const AttentionIdentity('scope', 'tok|7'),
              fetch: () async => response,
              ledger: ledger,
              play: () async => true,
              stop: () async {},
              fetchTablet: () async => [
                row('d1', type: 'dine_in', table: '5'),
                row('q1'),
              ],
            ),
            child: child!,
          ),
          home: const Scaffold(body: Text('POS')),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    await pump(const Locale('en'));
    expect(
      find.text('New tablet order — Table 5 · and 1 more'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('tablet-attention-open')));
    expect(opened, ['tablet:d1']);
    controller.opened('tablet:d1');
    await tester.pump();
    expect(find.text('New tablet order — #27'), findsOneWidget);
    response = snapshot();
    await controller.refresh();
    await tester.pump();
    expect(find.byKey(const ValueKey('tablet-attention-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox());

    response = snapshot(tablet: ['tablet:q1']);
    await pump(const Locale('ar'));
    expect(find.text('طلب جديد من الجهاز اللوحي — #27'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bell lists tablet orders and opens them', (tester) async {
    var opened = 0;
    final controller = OrderAttentionController(
      identity: () => const AttentionIdentity('scope', 'tok|7'),
      fetch: () async => snapshot(tablet: ['tablet:a', 'tablet:b']),
      ledger: MemoryLedger()..values['scope'] = {'tablet:a', 'tablet:b'},
      play: () async => true,
      stop: () async {},
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: OrderAttentionScope(
            controller: controller,
            child: OrderAttentionBell(
              onQuickOrders: null,
              onTables: null,
              onTabletOrders: () => opened++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('order-attention-bell')));
    await tester.pumpAndSettle();
    expect(find.text('Tablet orders'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('order-attention-tablet')));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  test('every new tablet text has English and a different Arabic', () {
    final en = lookupL10n(const Locale('en'));
    final ar = lookupL10n(const Locale('ar'));
    final pairs = [
      (en.tabletOrdersTitle, ar.tabletOrdersTitle),
      (en.tabletTake, ar.tabletTake),
      (en.tabletTakeOver, ar.tabletTakeOver),
      (en.tabletTakenBy('X'), ar.tabletTakenBy('X')),
      (en.tabletSendLater, ar.tabletSendLater),
      (en.tabletTakeCash, ar.tabletTakeCash),
      (en.tabletUnpaid, ar.tabletUnpaid),
      (en.tabletBadge, ar.tabletBadge),
      (en.tabletNeedsRecovery, ar.tabletNeedsRecovery),
      (en.tabletBeingPaidOn('T'), ar.tabletBeingPaidOn('T')),
      (
        en.tabletRedeemQuestion(50, '0.500', '9xxx1234'),
        ar.tabletRedeemQuestion(50, '0.500', '9xxx1234'),
      ),
      (en.tabletShiftCloseWarning(2), ar.tabletShiftCloseWarning(2)),
      (en.tabletNewOrderBanner('#27'), ar.tabletNewOrderBanner('#27')),
    ];
    for (final (e, a) in pairs) {
      expect(e, isNotEmpty);
      expect(a, isNotEmpty);
      expect(a, isNot(e));
    }
    expect(
      en.tabletRedeemQuestion(50, '0.500', '9xxx1234'),
      'Use 50 points (0.500 OMR) for 9xxx1234?',
    );
  });
}
