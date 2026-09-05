import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';

import 'support/fake_order_storage.dart';

const _table = DiningTableDefinition(
  id: '1',
  floorId: 'f1',
  name: 'Table 1',
  sizeLabel: 'square',
  seats: 4,
  sortOrder: 1,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 9, 6, 12);
  RemoteTableState remote({
    bool free = false,
    String status = 'open',
    String origin = 'station',
    int review = 0,
    bool payment = false,
    bool claim = false,
    int age = 12,
  }) => RemoteTableState(
    tableId: 1,
    fetchedAt: now.subtract(Duration(seconds: age)),
    seatingUuid: free ? null : 'seating',
    seatingStatus: free ? null : status,
    origin: free ? null : origin,
    tempReference: free ? null : 'T-0906-012',
    needsReviewCount: review,
    billStatus: payment ? 'awaiting_payment' : null,
    chargeClaimLive: claim,
  );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    String lang = 'en',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(lang),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(child: SizedBox(width: 500, height: 250, child: child)),
        ),
      ),
    );
  }

  for (final row in [
    (
      name: 'free',
      remote: remote(free: true),
      local: DiningTableStatus.available,
      reference: null,
      failures: 0,
      text: 'Server: free · 12s',
    ),
    (
      name: 'QR party on local free',
      remote: remote(),
      local: DiningTableStatus.available,
      reference: null,
      failures: 0,
      text: 'Server: QR party · T-0906-012 · 12s',
    ),
    (
      name: 'occupied and reference differs',
      remote: remote(origin: 'main_pos'),
      local: DiningTableStatus.occupied,
      reference: 'LOCAL',
      failures: 0,
      text: 'Server: occupied · 12s · reference differs',
    ),
    (
      name: 'needs review',
      remote: remote(review: 2),
      local: DiningTableStatus.available,
      reference: null,
      failures: 0,
      text: 'Server: QR party · T-0906-012 · 12s + needs review (2)',
    ),
    (
      name: 'awaiting payment',
      remote: remote(payment: true),
      local: DiningTableStatus.occupied,
      reference: 'T-0906-012',
      failures: 0,
      text: 'Server: payment in progress',
    ),
    (
      name: 'live charge claim',
      remote: remote(claim: true),
      local: DiningTableStatus.available,
      reference: null,
      failures: 0,
      text: 'Server: payment in progress',
    ),
    (
      name: 'stale age',
      remote: remote(age: 120),
      local: DiningTableStatus.available,
      reference: null,
      failures: 0,
      text: 'Server view stale (2 min)',
    ),
    (
      name: 'failed feed',
      remote: remote(),
      local: DiningTableStatus.available,
      reference: null,
      failures: 1,
      text: 'Server view stale (12s)',
    ),
  ]) {
    testWidgets('badge: ${row.name}', (tester) async {
      await pump(
        tester,
        DiningServerBadge(
          remote: row.remote,
          localStatus: row.local,
          localReference: row.reference,
          now: now,
          failures: row.failures,
        ),
      );
      expect(find.text(row.text), findsOneWidget);
      final text = tester.widget<Text>(find.text(row.text));
      if (row.remote.needsReviewCount > 0) {
        expect(text.style?.color, const Color(0xFFB42318));
      }
      if (row.failures > 0 ||
          row.remote.fetchedAt.isBefore(
            now.subtract(const Duration(seconds: 60)),
          )) {
        expect(text.style?.fontStyle, FontStyle.italic);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Arabic badge preserves the server reference and localizes the copy',
    (tester) async {
      await pump(
        tester,
        DiningServerBadge(
          remote: remote(),
          localStatus: DiningTableStatus.available,
          now: now,
        ),
        lang: 'ar',
      );
      expect(find.text('الخادم: ضيوف QR · T-0906-012 · 12 ث'), findsOneWidget);
    },
  );

  testWidgets(
    'server-occupied local-free tap opens only the fresh local table',
    (tester) async {
      final storage = FakeOrderStorage();
      final controller = PosController(orderStorage: storage);
      controller.applyCatalog(
        categories: const ['Coffee'],
        products: const [],
        floors: const [DiningFloor(id: 'f1', label: 'Main')],
        tables: const [_table],
      );
      final clock = ValueNotifier(now);
      addTearDown(clock.dispose);
      addTearDown(() async {
        await controller.shutdown();
        controller.dispose();
      });
      await pump(
        tester,
        buildDiningTableCardForTest(
          table: _table,
          status: DiningTableStatus.available,
          clock: clock,
          remote: remote(),
          onTap: () async {
            await controller.openDiningTable('1');
          },
        ),
      );
      expect(controller.activeDiningTableId, isNull);
      final decoration =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration
              as ShapeDecoration;
      expect(
        (decoration.gradient as LinearGradient).colors.first,
        Color.alphaBlend(
          const Color(0xFF808080).withValues(alpha: 0.08),
          Colors.white,
        ),
      );
      await tester.tap(find.text('Table 1'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.activeDiningTableId, '1');
      expect(controller.selectedOrderType, OrderType.dineIn);
      expect(controller.cart, isEmpty);
      expect(controller.currentOrderReference, isNot('T-0906-012'));
      expect(storage.history, isEmpty);
      expect(storage.held, isEmpty);
      expect(find.text('Server: QR party · T-0906-012 · 12s'), findsOneWidget);
    },
  );

  testWidgets(
    'remote null keeps the card widget keys, texts, colors and gestures identical',
    (tester) async {
      final clock = ValueNotifier(now);
      addTearDown(clock.dispose);
      var taps = 0;
      Widget card({RemoteTableState? remote}) => buildDiningTableCardForTest(
        table: _table,
        status: DiningTableStatus.available,
        clock: clock,
        onTap: () => taps++,
        remote: remote,
      );
      List<String> signature() => [
        for (final widget in tester.allWidgets)
          '${widget.runtimeType}|${widget.key is ValueKey ? widget.key : ''}|${widget is Text ? widget.data : ''}',
      ];
      await pump(tester, card());
      final before = signature();
      final decoration = tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer))
          .decoration;
      await pump(tester, card(remote: null));
      expect(signature(), before);
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .decoration,
        decoration,
      );
      expect(find.byType(DiningServerBadge), findsNothing);
      await tester.tap(find.text('Table 1'));
      expect(taps, 1);
    },
  );
}
