import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/screens/settings_screen.dart';

void main() {
  late _LogStore store;
  late TableDisagreementLog log;
  late DateTime now;
  setUp(() {
    now = DateTime.utc(2026, 9, 6);
    store = _LogStore();
    log = TableDisagreementLog(store, clock: () => now);
  });

  RemoteTableState remote({bool occupied = true, String reference = 'T-1'}) =>
      RemoteTableState(
        tableId: 1,
        fetchedAt: now,
        seatingUuid: occupied ? 'seating' : null,
        seatingStatus: occupied ? 'open' : null,
        origin: occupied ? 'station' : null,
        tempReference: occupied ? reference : null,
      );

  Future<void> observe(
    String status, {
    bool occupied = true,
    String? reference,
  }) => log.observe(
    [LocalTableShadowView(tableId: '1', status: status, reference: reference)],
    {1: remote(occupied: occupied)},
  );

  test('records all three classes and the resolved transition', () async {
    await observe('available');
    await observe('occupied', occupied: false);
    await observe('occupied', reference: 'LOCAL');
    await observe('occupied', reference: 'T-1');
    expect(store.rows.map((row) => row['kind']).toList(), [
      'server_occupied_local_free',
      'local_occupied_server_free',
      'reference_mismatch',
      'resolved',
    ]);
    expect(store.rows.first['server_origin'], 'station');
    expect(store.rows.first['server_reference'], 'T-1');
    expect(store.rows.last['local_reference'], 'T-1');
  });

  test(
    'same class does not spam and each class has a five-minute fence',
    () async {
      await observe('available');
      await observe('available');
      await observe('occupied', reference: 'T-1');
      now = now.add(const Duration(minutes: 1));
      await observe('available');
      await observe('occupied', reference: 'T-1');
      expect(store.rows, hasLength(2));
      now = now.add(const Duration(minutes: 4));
      await observe('available');
      await observe('occupied', reference: 'T-1');
      expect(store.rows, hasLength(4));
      expect(store.rows.map((row) => row['kind']).toList(), [
        'server_occupied_local_free',
        'resolved',
        'server_occupied_local_free',
        'resolved',
      ]);
    },
  );

  test('restart recovers the last class and throttle timestamps', () async {
    await observe('available');
    log = TableDisagreementLog(store, clock: () => now);
    await observe('available');
    expect(store.rows, hasLength(1));
    await observe('occupied', reference: 'T-1');
    expect(store.rows.last['kind'], 'resolved');
    log = TableDisagreementLog(store, clock: () => now);
    await observe('available');
    expect(store.rows, hasLength(2));
  });

  test('absent server rows and paid local free server are not invented disagreements', () async {
    await log.observe(
      [const LocalTableShadowView(tableId: '999', status: 'occupied')],
      {1: remote()},
    );
    await observe('paid', occupied: false);
    expect(store.rows, isEmpty);
  });

  test(
    'failed log writes are retried, not marked as already observed',
    () async {
      store.fail = true;
      await expectLater(observe('available'), throwsStateError);
      store.fail = false;
      await observe('available');
      expect(store.rows, hasLength(1));
    },
  );

  for (final language in ['en', 'ar']) {
    testWidgets(
      'Settings Table soak renders and copies last 200 rows in $language',
      (tester) async {
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final rows = [
          for (var id = 0; id < 205; id++)
            <String, Object?>{
              'observed_at': '2026-09-06T12:00:00Z',
              'table_id': 'row-$id',
              'local_status': 'available',
              'server_status': 'open',
              'server_origin': 'station',
              'server_reference': 'T-0906-012',
              'local_reference': null,
              'kind': 'server_occupied_local_free',
            },
        ];
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 550,
                child: TableSoakPanel(
                  mode: 'shadow',
                  meta: RemoteSyncMeta(
                    feedCursor: 77,
                    lastFeedOkAt: DateTime.utc(2026, 9, 6),
                    consecutiveFailures: 2,
                    lastError: 'http_429',
                  ),
                  rows: rows,
                ),
              ),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('table-soak-section')),
          findsOneWidget,
        );
        expect(
          find.text(language == 'en' ? 'Cursor: 77' : 'المؤشر: 77'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ListView>(find.byKey(const ValueKey('table-soak-rows')))
              .childrenDelegate
              .estimatedChildCount,
          200,
        );
        await tester.tap(find.byKey(const ValueKey('table-soak-copy')));
        await tester.pump();
        expect(copied, contains('row-199\t'));
        expect(copied, isNot(contains('row-200\t')));
        expect(
          copied!
              .split('\n')
              .where((line) => line.startsWith('2026-09-06T12:00:00Z')),
          hasLength(200),
        );
        expect(copied, contains('server_occupied_local_free'));
        expect(copied, contains('http_429'));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _LogStore implements RemoteTableStore {
  final List<Map<String, Object?>> rows = [];
  bool fail = false;
  @override
  Future<List<Map<String, Object?>>> readRemoteDisagreements({
    int limit = 200,
  }) async => rows.reversed.take(limit < 0 ? rows.length : limit).toList();
  @override
  Future<void> addRemoteDisagreement(Map<String, Object?> row) async {
    if (fail) throw StateError('disk full');
    rows.add(Map.of(row));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('No local-order capabilities: ${invocation.memberName}');
}
