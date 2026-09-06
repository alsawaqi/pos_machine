import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/widgets/table_degraded_banner.dart';

class SignalsOutbox extends OrderSyncRepository {
  SignalsOutbox(AppDatabase db)
    : super(PosApiService(tokenGetter: () => null), db);
  final pending = StreamController<List<OrderOutboxRow>>.broadcast();
  final flushes = StreamController<bool>.broadcast();
  @override
  Stream<List<OrderOutboxRow>> watchPending() => pending.stream;
  @override
  Stream<bool> get flushCompletions => flushes.stream;
  @override
  Future<void> dispose() async {
    await pending.close();
    await flushes.close();
    await super.dispose();
  }
}

class DegradedHarness {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  late final outbox = SignalsOutbox(db);
  final network = StreamController<bool>.broadcast();
  final board = StreamController<RemoteTableSnapshot>.broadcast();
  late ProviderContainer container;
  String mode = 'live';

  Future<void> init() async {
    container = ProviderContainer(
      overrides: [
        orderSyncRepositoryProvider.overrideWithValue(outbox),
        connectivityProvider.overrideWith((_) => network.stream),
        remoteBoardProvider.overrideWith((_) => board.stream),
        tableSessionsModeProvider.overrideWith((_) => mode),
      ],
    );
    // Resolve connectivity first so loading is not mistaken for our trigger.
    container.listen(connectivityProvider, (_, _) {});
    network.add(true);
    await tick();
    container.listen(degradedStateProvider, (_, _) {});
    outbox.pending.add([]);
    board.add(const RemoteTableSnapshot());
    await tick();
    expect(state.degraded, false);
    addTearDown(() async {
      container.dispose();
      await outbox.dispose();
      await network.close();
      await board.close();
      await db.close();
    });
  }

  TableDegradedState get state => container.read(degradedStateProvider);
  Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));
  void poll({int failures = 0, DateTime? success}) => board.add(
    RemoteTableSnapshot(
      meta: RemoteSyncMeta(
        consecutiveFailures: failures,
        lastFeedOkAt: success,
      ),
    ),
  );
  OrderOutboxRow row(String key, int age) => OrderOutboxRow(
    orderUuid: key,
    eventsJson: '[]',
    createdAt: DateTime.now().subtract(Duration(seconds: age)),
    attempts: 0,
    serverRejections: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final trigger in ['network', 'polls', 'old-row']) {
    for (final recoveryOrder in ['flush-first', 'poll-first']) {
      test(
        '$trigger degrades; recovery requires both ($recoveryOrder)',
        () async {
          final h = DegradedHarness();
          await h.init();
          if (trigger == 'network') h.network.add(false);
          if (trigger == 'polls') h.poll(failures: 2);
          if (trigger == 'old-row') {
            h.outbox.pending.add([h.row('tbl:1:open', 21)]);
          }
          await h.tick();
          expect(h.state.degraded, true);
          expect(h.state.since, isNotNull);
          final since = h.state.since;
          h.network.add(true);
          h.poll(success: since!.subtract(const Duration(seconds: 1)));
          h.outbox.pending.add([]);
          h.outbox.flushes.add(false);
          await h.tick();
          expect(h.state.degraded, true);
          expect(h.state.since, since);
          if (recoveryOrder == 'flush-first') {
            h.outbox.flushes.add(true);
          } else {
            h.poll(success: DateTime.now());
          }
          await h.tick();
          expect(h.state.degraded, true);
          if (recoveryOrder == 'flush-first') {
            h.poll(success: DateTime.now());
          } else {
            h.outbox.flushes.add(true);
          }
          await h.tick();
          expect(h.state.degraded, false);
          expect(h.state.since, isNull);
        },
      );
    }
  }

  test('one failed poll, young rows and old sales do not trigger; queue counts tables', () async {
    final h = DegradedHarness();
    await h.init();
    h.poll(failures: 1);
    h.outbox.pending.add([
      h.row('sale', 90),
      h.row('tbl:1:open', 19),
      h.row('tbl:2:round:1', 1),
    ]);
    await h.tick();
    expect(h.state.degraded, false);
    expect(h.state.queuedActions, 2);
    h.mode = 'shadow';
    h.container.invalidate(tableSessionsModeProvider);
    h.network.add(false);
    h.poll(failures: 9);
    await h.tick();
    expect(h.state.degraded, false);
    expect(h.state.queuedActions, 0);
  });

  for (final locale in ['en', 'ar']) {
    testWidgets(
      'banner $locale is Live-only, dated, counted and ignores taps',
      (tester) async {
        var taps = 0;
        Future<void> render(String mode, {bool degraded = true}) =>
            tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                home: Scaffold(
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => taps++,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      TableDegradedBanner(
                        mode: mode,
                        state: TableDegradedState(
                          degraded: degraded,
                          since: DateTime(2026, 9, 6, 19, 2),
                          queuedActions: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        for (final mode in ['off', 'shadow']) {
          await render(mode);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('table-degraded-banner')),
            findsNothing,
          );
        }
        await render('live', degraded: false);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('table-degraded-banner')),
          findsNothing,
        );
        await render('live');
        await tester.pumpAndSettle();
        final banner = find.byKey(const ValueKey('table-degraded-banner'));
        expect(banner, findsOneWidget);
        expect(find.textContaining('19:02'), findsOneWidget);
        expect(
          find.textContaining(
            locale == 'en' ? 'Queued: 3 table actions' : '3 إجراء للطاولات',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            locale == 'en' ? 'QR card settlement' : 'تسوية بطاقة QR',
          ),
          findsOneWidget,
        );
        await tester.tapAt(tester.getCenter(banner));
        expect(taps, 1);
      },
    );
  }
}
