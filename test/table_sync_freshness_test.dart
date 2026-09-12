import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12, 18, 21);
  final fetched = now.subtract(const Duration(minutes: 11));
  final remote = RemoteTableState(tableId: 1001, fetchedAt: fetched);
  for (final locale in ['en', 'ar']) {
    for (final condition in ['healthy-quiet-feed', 'old-feed', 'failed-feed']) {
      testWidgets(
        'card freshness $condition $locale never mutates a local table',
        (tester) async {
          final clock = ValueNotifier(now);
          addTearDown(clock.dispose);
          var taps = 0;
          await tester.pumpWidget(
            MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: SizedBox(
                  width: 500,
                  height: 350,
                  child: buildDiningTableCardForTest(
                    table: const DiningTableDefinition(
                      id: '1001',
                      floorId: '601',
                      name: 'T1',
                      sizeLabel: 'square',
                      seats: 4,
                      sortOrder: 1,
                    ),
                    status: DiningTableStatus.available,
                    clock: clock,
                    onTap: () => taps++,
                    remote: remote,
                    failures: condition == 'failed-feed' ? 1 : 0,
                    lastFeedOkAt: now.subtract(
                      Duration(seconds: condition == 'old-feed' ? 120 : 2),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final l10n = L10n.of(tester.element(find.byType(DiningServerBadge)));
          if (condition == 'healthy-quiet-feed') {
            expect(
              find.text(l10n.tableServerFree(l10n.tableServerAgeSeconds(2))),
              findsOneWidget,
            );
          } else {
            final age = condition == 'old-feed'
                ? l10n.tableServerAgeMinutes(2)
                : l10n.tableServerAgeSeconds(2);
            expect(find.text(l10n.tableServerStale(age)), findsOneWidget);
          }
          expect(remote.fetchedAt, fetched);
          expect(taps, 0);
          await tester.tap(find.text('T1'));
          expect(taps, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
