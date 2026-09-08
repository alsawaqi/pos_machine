import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/qr_pending_sheet.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_till_messages.dart';
import 'package:pos_machine/widgets/qr_pending_section.dart';
import 'package:pos_machine/widgets/qr_table_money_panel.dart';
import 'support/qr_pending_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final locale in ['en', 'ar']) {
    testWidgets(
      'pending section $locale: live expired declined in-flight rows and privacy',
      (tester) async {
        final gateway = PendingGateway([
          pendingOrder(
            uuid: 'live',
            status: 'awaiting_payment',
            session: 'live',
          ),
          pendingOrder(uuid: 'expired'),
          pendingOrder(uuid: 'declined', charge: 'declined'),
          pendingOrder(
            uuid: 'busy',
            status: 'awaiting_payment',
            charge: 'live_claim',
            refusal: 'charge_already_claimed',
          ),
        ]);
        await pumpPending(
          tester,
          gateway: gateway,
          locale: locale,
          child: const QrPendingSection(),
        );
        final l10n = L10n.of(tester.element(find.byType(QrPendingSection)));
        expect(find.text(l10n.qrPendingTitle), findsOneWidget);
        expect(find.text(l10n.qrPendingWaitingStation), findsOneWidget);
        expect(find.text(l10n.qrPendingSessionEnded), findsOneWidget);
        expect(find.text(l10n.qrPendingDeclined), findsOneWidget);
        expect(find.text(l10n.qrPendingCardInProgress), findsOneWidget);
        expect(find.text(l10n.qrPendingPhone('5555')), findsNWidgets(4));
        expect(find.text(l10n.qrPendingAge(130)), findsNWidgets(4));
        expect(find.text(l10n.qrPendingItems(1)), findsNWidgets(4));
        expect(find.text('OMR 4.750'), findsNWidgets(4));
        expect(
          find.text(
            qrTillMessageForCode(
              'charge_already_claimed',
              arabic: locale == 'ar',
            ),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('qr-pending-move-live')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('qr-pending-settle-live')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('qr-pending-settle-expired')),
              )
              .onPressed,
          isNotNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('qr-pending-move-busy')),
              )
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('qr-pending-settle-busy')),
              )
              .onPressed,
          isNull,
        );
        await screenshot(tester, 'pending-section-$locale');
        await disposePending(tester);
      },
    );

    testWidgets(
      'quick sheet $locale: standalone detail, only settle/void and unchanged tender',
      (tester) async {
        final gateway = PendingGateway();
        final flow = PendingFlow();
        await pumpPending(
          tester,
          gateway: gateway,
          flow: flow,
          locale: locale,
          child: QrPendingSheet(order: gateway.orders.single),
        );
        final panel = tester.widget<QrTableMoneyPanel>(
          find.byType(QrTableMoneyPanel),
        );
        expect(panel.host.row, isNull);
        expect(panel.host.active!.uuid, 'quick-expired');
        expect(panel.host.active!.grandTotalBaisas, 4750);
        expect(panel.standaloneOrder!.uuid, 'quick-expired');
        expect(
          find.byKey(const ValueKey('qr-detail-quick-quick-expired')),
          findsOneWidget,
        );
        expect(find.text('Server-priced meal'), findsOneWidget);
        expect(find.byKey(const ValueKey('qr-action-settle')), findsOneWidget);
        expect(find.byKey(const ValueKey('qr-action-void')), findsOneWidget);
        for (final key in [
          'qr-action-clear',
          'qr-action-reopen',
          'qr-action-fallback',
          'qr-action-settle-recovered',
        ]) {
          expect(find.byKey(ValueKey(key)), findsNothing);
        }
        expect(find.byType(TextField), findsNothing);
        expect(find.text('Free'), findsNothing);
        await screenshot(tester, 'pending-quick-sheet-$locale');
        await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
        await tester.pump();
        expect(flow.calls, ['claim:quick-expired']);
        expect(
          find.byKey(const ValueKey('qr-settlement-sheet')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('qr-frozen-amount')), findsOneWidget);
        await screenshot(tester, 'pending-quick-tender-$locale');
        await tester.tap(find.byKey(const ValueKey('qr-tender-cash')));
        await tester.pump();
        expect(flow.calls, ['claim:quick-expired', 'settle:cash']);
        expect(panel.host.row, isNull);
        expect(find.textContaining('Payment accepted'), findsOneWidget);
        await disposePending(tester);
      },
    );
  }

  testWidgets(
    'Send to counter is online then refreshes; refusal never queues or changes the row',
    (tester) async {
      final gateway = PendingGateway([
        pendingOrder(uuid: 'declined', charge: 'declined'),
      ]);
      await pumpPending(
        tester,
        gateway: gateway,
        child: const QrPendingSection(),
      );
      gateway.moveError = ApiException(
        message: 'refused',
        code: 'charge_outcome_uncertain',
        statusCode: 409,
      );
      await tester.tap(find.byKey(const ValueKey('qr-pending-move-declined')));
      await tester.pump();
      expect(gateway.calls, ['fetch', 'move:declined', 'fetch']);
      expect(gateway.orders.single.charge, 'declined');
      expect(
        find.text(qrTillMessageForCode('charge_outcome_uncertain')),
        findsOneWidget,
      );
      gateway.moveError = null;
      await tester.tap(find.byKey(const ValueKey('qr-pending-move-declined')));
      await tester.pump();
      expect(gateway.calls, [
        'fetch',
        'move:declined',
        'fetch',
        'move:declined',
        'fetch',
      ]);
      expect(gateway.orders.single.canSettle, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('qr-pending-settle-declined')),
            )
            .onPressed,
        isNotNull,
      );
      await disposePending(tester);
    },
  );

  testWidgets('visible section stops polling when hidden or backgrounded', (
    tester,
  ) async {
    final gateway = PendingGateway();
    final visible = ValueNotifier(true);
    await pumpPending(
      tester,
      gateway: gateway,
      child: ValueListenableBuilder<bool>(
        valueListenable: visible,
        builder: (_, value, _) => QrPendingSection(visible: value),
      ),
    );
    expect(gateway.calls, ['fetch']);
    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(gateway.calls, ['fetch']);
    visible.value = true;
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    expect(gateway.calls.length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await disposePending(tester);
    visible.dispose();
  });

  testWidgets(
    'offline retains last rows with timestamp and disables every entry action',
    (tester) async {
      final gateway = PendingGateway();
      await pumpPending(
        tester,
        gateway: gateway,
        child: const QrPendingSection(),
      );
      gateway.fetchError = ApiException(message: 'offline', isNetwork: true);
      await tester.tap(find.byKey(const ValueKey('qr-pending-refresh')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('qr-pending-quick-expired')),
        findsOneWidget,
      );
      expect(find.textContaining('Not updated since'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('qr-pending-settle-quick-expired')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('qr-pending-void-quick-expired')),
            )
            .onPressed,
        isNull,
      );
      await disposePending(tester);
    },
  );

  testWidgets('PopScope blocks route while the first claim is in flight', (
    tester,
  ) async {
    final gateway = PendingGateway();
    final flow = PendingFlow()..claimPending = Completer<QrSettlementClaim>();
    await pumpPending(
      tester,
      gateway: gateway,
      flow: flow,
      child: QrPendingSheet(order: gateway.orders.single),
    );
    await tester.tap(find.byKey(const ValueKey('qr-action-settle')));
    await tester.pump();
    final guard = tester.widget<PopScope>(
      find.byWidgetPredicate((widget) => widget is PopScope).first,
    );
    expect(guard.canPop, isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(QrPendingSheet), findsOneWidget);
    expect(flow.calls, ['claim:quick-expired']);
    flow.claimPending!.complete(pendingClaim('quick-expired'));
    await tester.pump();
    expect(find.byKey(const ValueKey('qr-settlement-sheet')), findsOneWidget);
    await disposePending(tester);
  });

  testWidgets(
    'terminal standalone order cannot show table clear/reopen actions',
    (tester) async {
      final gateway = PendingGateway([pendingOrder(status: 'paid')]);
      await pumpPending(
        tester,
        gateway: gateway,
        child: QrPendingSheet(order: gateway.orders.single),
      );
      for (final key in [
        'qr-action-clear',
        'qr-action-reopen',
        'qr-action-settle',
        'qr-action-void',
      ]) {
        expect(find.byKey(ValueKey(key)), findsNothing);
      }
      await disposePending(tester);
    },
  );

  testWidgets('all state chips and new refusal copy exist in both locales', (
    tester,
  ) async {
    for (final language in ['en', 'ar']) {
      final l10n = await L10n.delegate.load(Locale(language));
      expect(
        qrPendingStateLabel(pendingOrder(session: 'live'), l10n),
        l10n.qrPendingAtCounter,
      );
      expect(
        qrPendingStateLabel(pendingOrder(charge: 'cancelled'), l10n),
        l10n.qrPendingCancelled,
      );
      expect(
        qrPendingStateLabel(pendingOrder(charge: 'uncertain'), l10n),
        l10n.qrPendingRecovery,
      );
      for (final session in ['expired', 'closed', 'missing']) {
        expect(
          qrPendingStateLabel(pendingOrder(session: session), l10n),
          l10n.qrPendingSessionEnded,
        );
      }
      expect(
        qrTillMessageForCode('qr_claim_not_enabled', arabic: language == 'ar'),
        isNot('qr_claim_not_enabled'),
      );
      expect(
        qrTillMessageForCode('qr_claim_not_enabled', arabic: language == 'ar'),
        isNotEmpty,
      );
    }
  });
}

final screenshotKey = GlobalKey();

Future<void> pumpPending(
  WidgetTester tester, {
  required PendingGateway gateway,
  required Widget child,
  PendingFlow? flow,
  String locale = 'en',
}) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1200, 1120);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (Platform.environment['QR_PENDING_SCREENSHOT_DIR'] != null) {
    await tester.runAsync(() async {
      final bytes = await File('C:/Windows/Fonts/arial.ttf').readAsBytes();
      await (FontLoader(
        'PendingEvidence',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      final icons = await File(
        'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        qrTillServiceProvider.overrideWithValue(gateway),
        qrSettlementCoordinatorProvider.overrideWithValue(
          flow ?? PendingFlow(),
        ),
      ],
      child: RepaintBoundary(
        key: screenshotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(locale),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: 'PendingEvidence',
            colorSchemeSeed: const Color(0xFF12694F),
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> disposePending(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  await tester.pump();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['QR_PENDING_SCREENSHOT_DIR'];
  if (directory == null) return;
  await tester.pump(const Duration(milliseconds: 250));
  final boundary =
      screenshotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}
