import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/l10n/l10n_ar.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/settings_screen.dart';
import 'package:pos_machine/widgets/table_reconciliation_sheet.dart';

import 'send_to_kitchen_test.dart' show B3Memory;

TableSyncVerdict verdict(
  int id, {
  String kind = 'open',
  String outcome = 'merged',
  Map<String, dynamic> detail = const {},
  bool seen = false,
}) => TableSyncVerdict(
  id: id,
  observedAt: DateTime(2026, 9, 6, 19, 2),
  tableId: '5',
  eventKind: kind,
  outcome: outcome,
  detail: detail,
  seen: seen,
);

class HistoryStore extends B3Memory {
  int reads = 0;
  int? requestedLimit;
  final marked = <int>[];
  @override
  Future<List<TableSyncVerdict>> readTableSyncVerdicts({
    bool unseenOnly = false,
    int limit = 200,
  }) async {
    reads++;
    requestedLimit = limit;
    return verdicts
        .where((v) => !unseenOnly || !marked.contains(v.id))
        .take(limit)
        .toList();
  }

  @override
  Future<void> markTableSyncVerdictsSeen(List<int> ids) async {
    marked.addAll(ids);
  }
}

void main() {
  test('one sheet per pass, repeated unseen IDs deduped while open; seen only on dismissal', () async {
    final shown = <List<TableSyncVerdict>>[];
    final dismissed = <Completer<bool>>[];
    final store = HistoryStore()
      ..verdicts.addAll([verdict(1), verdict(2), verdict(3)]);
    final presenter = TableReconciliationPresenter(
      show: (rows) {
        shown.add(rows);
        final done = Completer<bool>();
        dismissed.add(done);
        return done.future;
      },
      markSeen: (rows) =>
          store.markTableSyncVerdictsSeen(rows.map((r) => r.id!).toList()),
    );
    final first = presenter.present([verdict(1), verdict(2)]);
    await Future<void>.delayed(Duration.zero);
    expect(shown.map((b) => b.map((r) => r.id)), [
      [1, 2],
    ]);
    expect(store.marked, isEmpty);
    final duplicate = presenter.present([verdict(1), verdict(2)]);
    final second = presenter.present([verdict(1), verdict(2), verdict(3)]);
    expect(shown, hasLength(1));
    dismissed.first.complete(true);
    await first;
    await duplicate;
    await Future<void>.delayed(Duration.zero);
    expect(store.marked, [1, 2]);
    expect(shown.map((b) => b.map((r) => r.id)), [
      [1, 2],
      [3],
    ]);
    dismissed.last.complete(true);
    await second;
    expect(store.marked, [1, 2, 3]);
    expect(await store.readTableSyncVerdicts(unseenOnly: true), isEmpty);
    expect(await store.readTableSyncVerdicts(), hasLength(3));
    await presenter.present([verdict(1), verdict(4, seen: true)]);
    expect(shown, hasLength(2));
    presenter.dispose();
  });

  test(
    'no actual presentation or a failed mark does not lose durable verdicts',
    () async {
      var shown = 0, marked = 0;
      final presenter = TableReconciliationPresenter(
        show: (_) async => ++shown != 1,
        markSeen: (_) async {
          marked++;
          if (marked == 1) throw StateError('storage unavailable');
        },
      );
      await presenter.present([verdict(1)]);
      expect(marked, 0);
      await expectLater(presenter.present([verdict(1)]), throwsStateError);
      await presenter.present([verdict(1)]);
      expect(shown, 3);
      expect(marked, 2);
      presenter.dispose();
      await presenter.present([verdict(2)]);
      expect(shown, 3);
    },
  );

  test(
    'held quantities use unique original request indexes and actual reasons',
    () {
      final row = verdict(
        1,
        kind: 'round',
        outcome: 'held',
        detail: {
          'request': {
            'lines': [
              {'qty': 9},
              {'qty': 2},
            ],
          },
          'held_lines': [
            {'line_index': 1, 'reason': 'product_missing'},
            {'line_index': 1, 'reason': 'product_missing'},
          ],
          'review_reasons': ['catalogue'],
        },
      );
      expect(
        tableReconciliationCopy(L10nEn(), row),
        'Table 5: 2 items could not be priced (product_missing, catalogue) — review on the QR tab.',
      );
      expect(
        tableReconciliationCopy(L10nAr(), row),
        'الطاولة 5: تعذر تسعير 2 صنف (product_missing, catalogue) — راجع تبويب QR.',
      );
    },
  );

  test('exception copy distinguishes occupied move, dead seating, refused seats and short cancellation', () {
    final en = L10nEn();
    expect(
      tableReconciliationCopy(en, verdict(1, outcome: 'attached')),
      "Table 5 joined the server's existing session.",
    );
    expect(
      tableReconciliationCopy(en, verdict(1, outcome: 'already_closed')),
      'Table 5 was closed on the server before your open arrived.',
    );
    for (final outcome in ['bill_terminal', 'bill_unpaid']) {
      expect(
        tableReconciliationCopy(
          en,
          verdict(1, kind: 'round', outcome: outcome),
        ),
        'Table 5: the server bill is closed or awaiting payment; these items were not added. Review on the QR tab.',
      );
    }
    final move = {
      'request': {'from_table_id': 5, 'to_table_id': 7},
    };
    expect(
      tableReconciliationCopy(
        en,
        verdict(1, kind: 'move', outcome: 'target_occupied', detail: move),
      ),
      'Table 7 was already taken on the server; the server still shows your bill on Table 5.',
    );
    for (final outcome in ['stale_generation', 'unknown_seating']) {
      final copy = tableReconciliationCopy(
        en,
        verdict(1, kind: 'move', outcome: outcome, detail: move),
      );
      expect(copy, contains('Move from Table 5 to Table 7 was not applied'));
      expect(copy, isNot(contains('already taken')));
    }
    expect(
      tableReconciliationCopy(
        en,
        verdict(
          1,
          kind: 'join',
          outcome: 'joined',
          detail: {
            'refused': [7, 9],
          },
        ),
      ),
      'Table 5: these seats could not be joined on the server: 7, 9. Check the floor; local tables were not changed.',
    );
    expect(
      tableReconciliationCopy(
        en,
        verdict(1, kind: 'close', outcome: 'bill_unpaid'),
      ),
      'Table 5 still has an unpaid bill on the server — clear it from the QR tab or pay it.',
    );
    for (final outcome in ['cancelled', 'nothing_to_cancel', 'bill_terminal']) {
      final cancelled = outcome == 'cancelled' ? 2 : 0;
      expect(
        tableReconciliationCopy(
          en,
          verdict(
            1,
            kind: 'cancel_line',
            outcome: outcome,
            detail: {
              'request': {'qty': 3},
              'cancelled_qty': cancelled,
            },
          ),
        ),
        'Table 5: ${3 - cancelled} requested items were not found for cancellation on the server. Review the bill on the QR tab.',
      );
    }
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('sheet $locale dismisses once and preserves Settings history', (
      tester,
    ) async {
      final store = HistoryStore()..verdicts.add(verdict(1));
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                host = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      final presenter = TableReconciliationPresenter(
        show: (rows) async {
          await showModalBottomSheet<void>(
            context: host,
            isScrollControlled: true,
            builder: (_) => TableReconciliationSheet(rows: rows),
          );
          return true;
        },
        markSeen: (rows) =>
            store.markTableSyncVerdictsSeen(rows.map((r) => r.id!).toList()),
      );
      final pass = presenter.present(store.verdicts);
      await tester.pumpAndSettle();
      expect(
        find.text(locale == 'en' ? 'Tables reconciled' : 'تمت مزامنة الطاولات'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          locale == 'en' ? 'need review' : 'تحتاج إلى مراجعة',
        ),
        findsOneWidget,
      );
      expect(store.marked, isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('table-reconciliation-dismiss')),
      );
      await tester.pumpAndSettle();
      await pass;
      expect(store.marked, [1]);
      expect(await store.readTableSyncVerdicts(), hasLength(1));
      presenter.dispose();
    });
  }

  testWidgets(
    'Settings lazily reads last 200 in Off, shows seen rows, never marks or polls',
    (tester) async {
      final store = HistoryStore()
        ..verdicts.addAll(
          List.generate(205, (i) => verdict(i + 1, seen: true)),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tableLedgerStoreProvider.overrideWithValue(store),
            tableSessionsModeProvider.overrideWithValue('off'),
            remoteBoardProvider.overrideWith(
              (_) => throw StateError('must not poll'),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: const Scaffold(body: TableReconciliationSettingsSection()),
          ),
        ),
      );
      expect(store.reads, 0);
      await tester.tap(find.text('Tables'));
      await tester.pumpAndSettle();
      expect(store.reads, 1);
      expect(store.requestedLimit, 200);
      final list = tester.widget<ListView>(
        find.byKey(const ValueKey('table-reconciliation-rows')),
      );
      expect(list.childrenDelegate.estimatedChildCount, 200);
      expect(find.byKey(const ValueKey('table-verdict-1')), findsOneWidget);
      expect(store.marked, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
