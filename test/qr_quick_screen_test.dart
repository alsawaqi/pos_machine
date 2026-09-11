import 'package:flutter/material.dart';
import 'dart:async';
import 'qr_quick_evidence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'qr_quick_controller_test.dart'
    show FakeQuickGateway, MemoryQuickStore, quickJson;

void main() {
  late FakeQuickGateway api;
  late MemoryQuickStore store;
  late QrQuickController controller;
  final products = [
    const QuickProduct(
      7,
      'Water',
      nameAr: 'ماء',
      groups: [
        QuickGroup(
          'Size',
          [
            QuickChoice(9, 'Small', nameAr: 'صغير'),
            QuickChoice(10, 'Large', nameAr: 'كبير'),
          ],
          nameAr: 'الحجم',
          min: 1,
          max: 1,
        ),
      ],
    ),
  ];
  setUp(() {
    api = FakeQuickGateway();
    store = MemoryQuickStore();
    controller = QrQuickController(api, store);
  });
  Future<void> mount(
    WidgetTester tester, {
    bool arabic = false,
    Future<void> Function(BuildContext, QrQuickOrder)? pay,
  }) async {
    await loadQuickEvidenceFonts(tester);
    await tester.pumpWidget(
      RepaintBoundary(
        key: quickEvidenceKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'QuickEvidence',
            colorSchemeSeed: const Color(0xFF0B6D8A),
          ),
          home: QrQuickScreen(
            createController: () async => controller,
            catalogue: () => products,
            arabic: arabic,
            onPay: pay,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) => tap(tester, 'quick-review-bill-1');
  Future<void> addLine(WidgetTester tester) async {
    await tap(tester, 'quick-add-items');
    await tap(tester, 'quick-product-7');
    final add = tester.widget<FilledButton>(
      find.byKey(const ValueKey('quick-option-add')),
    );
    expect(
      add.onPressed,
      null,
    ); // Required choices are enforced, not clamped away.
    await tester.tap(find.text('Small'));
    await tester.pump();
    await tap(tester, 'quick-qty-plus');
    await tap(tester, 'quick-option-add');
  }

  testWidgets('inbox shows server reference, total, age and phone TAIL only', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('QR Quick Orders'), findsOneWidget);
    expect(find.text('Q-007'), findsOneWidget);
    expect(find.textContaining('1.000 OMR'), findsOneWidget);
    expect(find.textContaining('•••• 1234'), findsOneWidget);
    expect(find.text('Held Orders'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'review/add/pay preserves original bill; server lines never become editable cart lines',
    (tester) async {
      final payments = <String>[];
      await mount(
        tester,
        pay: (_, order) async {
          payments.add(order.uuid);
        },
      );
      await open(tester);
      expect(find.text('1.0 × Coffee'), findsOneWidget);
      await addLine(tester);
      expect(find.text('2 × Water'), findsOneWidget);
      expect(find.text('1.0 × Coffee'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('quick-pay')))
            .onPressed,
        null,
      );
      await tap(tester, 'quick-submit');
      expect(api.requests.single.payload['lines'], [
        {
          'product_id': 7,
          'qty': 2,
          'addon_ids': [9],
          'notes': null,
        },
      ]);
      expect(api.requests.single.orderUuid, 'bill-1');
      expect(find.textContaining('1.200 OMR'), findsOneWidget);
      await tap(tester, 'quick-pay');
      expect(payments, ['bill-1']);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('direct pay uses the SAME order without additions', (
    tester,
  ) async {
    final payments = <String>[];
    await mount(tester, pay: (_, order) async => payments.add(order.uuid));
    await open(tester);
    await tap(tester, 'quick-pay');
    expect(payments, ['bill-1']);
    expect(api.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'lost response disables further edits/pay and exposes original-request retry',
    (tester) async {
      api.lostResponse = true;
      await mount(
        tester,
        pay: (_, _) async {
          fail('Must not pay uncertain addition');
        },
      );
      await open(tester);
      await addLine(tester);
      await tap(tester, 'quick-submit');
      expect(find.byKey(const ValueKey('quick-retry')), findsOneWidget);
      expect(find.byKey(const ValueKey('quick-add-items')), findsNothing);
      expect(find.byKey(const ValueKey('quick-pay')), findsNothing);
      api.lostResponse = false;
      await tap(tester, 'quick-retry');
      expect(api.mutations, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'closing unsent additions offers discard and leaves original bill unchanged',
    (tester) async {
      await mount(tester);
      await open(tester);
      await addLine(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsent additions?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('QR Quick Orders'), findsOneWidget);
      expect(api.requests, isEmpty);
      expect(api.orders.single.total, 1000);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'poll every five seconds only on visible foreground inbox, never posts',
    (tester) async {
      await mount(tester);
      final start = api.fetches;
      await tester.pump(const Duration(seconds: 5));
      expect(api.fetches, start + 1);
      await open(tester);
      final covered = api.fetches;
      await tester.pump(const Duration(seconds: 15));
      expect(api.fetches, covered);
      await tester.pageBack();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = api.fetches;
      await tester.pump(const Duration(seconds: 15));
      expect(api.fetches, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(api.fetches, paused + 1);
      expect(api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'handheld without guarded payment host cannot call an ordinary checkout',
    (tester) async {
      await mount(tester);
      await open(tester);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('quick-pay')))
            .onPressed,
        null,
      );
      expect(
        find.textContaining('settle this bill on the till'),
        findsOneWidget,
      );
      expect(api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('station routed quick order moves explicitly before additions', (
    tester,
  ) async {
    api.orders = [QrQuickOrder(quickJson(status: 'awaiting_payment'))];
    await mount(tester);
    await open(tester);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('quick-add-items')))
          .onPressed,
      null,
    );
    expect(api.moves, 0);
    await tap(tester, 'quick-move');
    expect(api.moves, 1);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('quick-add-items')))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('repeated Pay taps open only one guarded payment host', (
    tester,
  ) async {
    final wait = Completer<void>();
    var calls = 0;
    await mount(
      tester,
      pay: (_, order) async {
        expect(order.uuid, 'bill-1');
        calls++;
        await wait.future;
      },
    );
    await open(tester);
    await tap(tester, 'quick-pay');
    await tap(tester, 'quick-pay');
    expect(calls, 1);
    expect(api.requests, isEmpty);
    wait.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  for (final width in [360.0, 1200.0]) {
    for (final arabic in [false, true]) {
      testWidgets('EN/AR inbox and review fit width $width Arabic=$arabic', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        api.orders = [
          for (final charge in ['none', 'live_claim', 'declined', 'uncertain'])
            QrQuickOrder(
              quickJson(
                uuid: charge == 'none' ? 'bill-1' : charge,
                charge: charge,
              ),
            ),
        ];
        await mount(
          tester,
          arabic: arabic,
          pay: width > 1000 ? (_, _) async {} : null,
        );
        final label = 'quick-${width.toInt()}-${arabic ? 'ar' : 'en'}';
        await captureQuickEvidence(tester, '$label-inbox');
        expect(
          find.text(arabic ? 'طلبات QR السريعة' : 'QR Quick Orders'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
        await open(tester);
        await captureQuickEvidence(tester, '$label-review');
        expect(tester.takeException(), null);
        await tap(tester, 'quick-add-items');
        await tap(tester, 'quick-product-7');
        await captureQuickEvidence(tester, '$label-options');
        expect(tester.takeException(), null);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
