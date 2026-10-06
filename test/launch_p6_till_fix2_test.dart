import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_order_models.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';

/// LAUNCH-P6 Part C till fix 2 — four LOW items: the T-1 hand-over from a
/// dead local page, the T-3 warning only when both print settings are off,
/// the T-4 "Finish this screen first" for in-place blockers, and the T-5
/// Open that waits for a read in flight (or says it was not found).
Map<String, dynamic> base(String uuid) => {
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
};

class Gateway implements TabletOrdersGateway {
  Gateway(this.rows);
  List<Map<String, dynamic>> rows;
  Completer<void>? hold;
  int reads = 0;

  @override
  Future<List<TabletOrderRow>> list({bool unpaidOnly = false}) async {
    reads++;
    final snapshot = [...rows];
    final wait = hold;
    if (wait != null) {
      hold = null;
      await wait.future;
    }
    return parseTabletOrderRows(snapshot);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});

  test(
    'T-1: a refused local tender closes the page, then opens the sheet',
    () async {
      final steps = <String>[];
      expect(
        await tabletTenderHandover(
          needsServerSheet: true,
          closeLocalPage: () => steps.add('close local'),
          openServerSheet: () async => steps.add('server sheet'),
        ),
        isTrue,
      );
      expect(steps, ['close local', 'server sheet']);
      steps.clear();
      expect(
        await tabletTenderHandover(
          needsServerSheet: false,
          closeLocalPage: () => steps.add('close local'),
          openServerSheet: () async => steps.add('server sheet'),
        ),
        isFalse,
      );
      expect(steps, isEmpty);
    },
  );

  test('T-3: the board warning only when both print settings are off', () {
    expect(
      tabletRoundPrintOff(
        printKitchenTickets: false,
        printQrKitchenRounds: false,
      ),
      isTrue,
    );
    expect(
      tabletRoundPrintOff(
        printKitchenTickets: true,
        printQrKitchenRounds: false,
      ),
      isFalse,
    );
    expect(
      tabletRoundPrintOff(
        printKitchenTickets: false,
        printQrKitchenRounds: true,
      ),
      isFalse,
    );
  });

  testWidgets('T-4: an in-place payment or workspace blocks Open with the '
      'same message', (tester) async {
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
    expect(tabletOrdersOpenBlock(pos, busy: true), 'Finish this screen first');
  });

  Future<(Gateway, TabletOrdersController, ValueNotifier<String?>)> pump(
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = Gateway([base('a')]);
    final controller = TabletOrdersController(gateway);
    final requests = ValueNotifier<String?>(null);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TabletOrdersScreen(
          controller: controller,
          openRequests: requests,
          poll: const Duration(hours: 1),
          actions: TabletOrderActions(
            authorize: (a, {subtitle, alwaysApproval = false}) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (gateway, controller, requests);
  }

  testWidgets('T-5: Open during a read in flight waits, reads again, opens', (
    tester,
  ) async {
    final (gateway, controller, requests) = await pump(tester);
    // A poll read starts before the new order exists…
    final hold = Completer<void>();
    gateway.hold = hold;
    unawaited(controller.refresh());
    await tester.pump();
    // …then the order arrives and staff tap Open on the banner.
    gateway.rows = [...gateway.rows, base('n')];
    requests.value = 'tablet:n';
    await tester.pump();
    hold.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tablet-sheet-n')), findsOneWidget);
  });

  testWidgets('T-5: an order still not listed says so', (tester) async {
    final (_, _, requests) = await pump(tester);
    requests.value = 'tablet:missing';
    await tester.pumpAndSettle();
    expect(find.text('Order not found yet — try again'), findsOneWidget);
    expect(
      lookupL10n(const Locale('ar')).tabletOrderNotFoundYet,
      'لم يُعثر على الطلب بعد — حاول مرة أخرى',
    );
  });
}
