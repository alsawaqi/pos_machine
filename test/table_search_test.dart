import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

import 'table_activity_notice_test.dart' show b5Board;

const hit = TableSearchResult(
  tableId: 5,
  floorId: 1,
  label: 'Table 5',
  reference: 'T-0906-012',
  totalBaisas: 4700,
);

void main() {
  test(
    'eligibility is reference prefix or at least four digits, within 2–32',
    () {
      for (final q in [
        'T-',
        't-0906',
        ' 1234 ',
        'T-${List.filled(30, 'a').join()}',
      ]) {
        expect(TableSearchController.eligible(q), true, reason: q);
      }
      for (final q in [
        '',
        'T',
        '123',
        'abc1234',
        'Table 5',
        'T-${List.filled(31, 'a').join()}',
      ]) {
        expect(TableSearchController.eligible(q), false, reason: q);
      }
    },
  );

  test(
    'API search is GET q only; response money and reference stay server-owned',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              requests.add(o);
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'data': {
                      'tables': [b5Board()],
                    },
                    'meta': {'money_unit': 'baisas'},
                  },
                ),
              );
            },
          ),
        );
      final api = PosApiService(tokenGetter: () => 'mock', dio: dio);
      final rows = await api.searchTables(' T-0906 ');
      expect(requests.single.method, 'GET');
      expect(requests.single.path, '/device/tables/search');
      expect(requests.single.queryParameters, {'q': 'T-0906'});
      expect(requests.single.data, isNull);
      expect(rows.single.tableId, 5);
      expect(rows.single.reference, 'T-0906-012');
      expect(rows.single.totalBaisas, 4700);
      await expectLater(api.searchTables('x'), throwsFormatException);
      await expectLater(
        api.searchTables('T-${List.filled(31, 'a').join()}'),
        throwsFormatException,
      );
      expect(requests, hasLength(1));
    },
  );

  test('feed parser carries every B5 field and keeps legacy missing fields tolerant', () async {
    final at = DateTime.utc(2026, 9, 6, 12);
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'data': {
                    'events': [
                      {
                        'id': 11,
                        'table_id': 5,
                        'event_type': 'customer_order_arrived',
                        'payload': {'round_id': 71},
                        'device_id': null,
                        'order_uuid': 'bill',
                        'created_at': at.toIso8601String(),
                      },
                      {
                        'id': 12,
                        'table_id': 5,
                        'event_type': 'round_appended',
                        'payload': {},
                        'device_id': 4,
                      },
                      {'id': 13, 'table_id': 5},
                    ],
                  },
                  'meta': {'latest_id': 13, 'has_more': false},
                },
              ),
            );
          },
        ),
      );
    final feed = await PosApiService(
      tokenGetter: () => 'mock',
      dio: dio,
    ).fetchTableFeed(after: 10);
    final first = feed.events.first;
    expect(first.eventType, 'customer_order_arrived');
    expect(first.payload, {'round_id': 71});
    expect(first.deviceId, isNull);
    expect(first.orderUuid, 'bill');
    expect(first.createdAt, at);
    expect(feed.events[1].deviceId, 4);
    expect(feed.events.last.eventType, '');
    expect(feed.events.last.payload, isEmpty);
    expect(feed.events.last.createdAt, isNull);
  });

  testWidgets('400 ms debounce sends only latest eligible query', (
    tester,
  ) async {
    final calls = <String>[];
    final search = TableSearchController((q) async {
      calls.add(q);
      return [hit];
    });
    addTearDown(search.dispose);
    search.update('T-0', enabled: true, degraded: false);
    await tester.pump(const Duration(milliseconds: 300));
    search.update('T-09', enabled: true, degraded: false);
    await tester.pump(const Duration(milliseconds: 399));
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['T-09']);
    expect(search.results.single.totalBaisas, 4700);
    expect(search.searching, false);
  });

  testWidgets(
    'degraded is local-only; recovery schedules once; mode Off cancels pending',
    (tester) async {
      final calls = <String>[];
      final search = TableSearchController((q) async {
        calls.add(q);
        return [hit];
      });
      addTearDown(search.dispose);
      search.update('1234', enabled: true, degraded: true);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, isEmpty);
      expect(search.offline, true);
      search.update('1234', enabled: true, degraded: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls, ['1234']);
      search.update('T-09', enabled: true, degraded: false);
      search.update('T-09', enabled: false, degraded: false);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, ['1234']);
      expect(search.results, isEmpty);
      expect(search.offline, false);
    },
  );

  for (final reason in ['query', 'offline', 'mode', 'scope', 'dispose']) {
    testWidgets('stale search response discarded after $reason change', (
      tester,
    ) async {
      final response = Completer<List<TableSearchResult>>();
      final search = TableSearchController((_) => response.future);
      search.update('T-09', enabled: true, degraded: false, scope: 'a');
      await tester.pump(const Duration(milliseconds: 400));
      if (reason == 'dispose') {
        search.dispose();
      } else {
        addTearDown(search.dispose);
        search.update(
          reason == 'query' ? 'local-name' : 'T-09',
          enabled: reason != 'mode',
          degraded: reason == 'offline',
          scope: reason == 'scope' ? 'b' : 'a',
        );
      }
      response.complete([hit]);
      await tester.pump();
      expect(search.results, isEmpty);
      if (reason != 'dispose') {
        search.update('', enabled: false, degraded: false);
      }
    });
  }

  testWidgets(
    'failed search leaves local matches, does not fabricate server rows',
    (tester) async {
      final search = TableSearchController(
        (_) async => throw StateError('offline'),
      );
      addTearDown(search.dispose);
      search.update('T-09', enabled: true, degraded: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(search.failed, true);
      expect(search.results, isEmpty);
    },
  );

  test('search merges local matches with known current-floor matches only; no table mutation', () {
    const a = DiningTableDefinition(
      id: '1',
      floorId: '1',
      name: 'Local',
      sizeLabel: 'square',
      seats: 4,
      sortOrder: 2,
    );
    const b = DiningTableDefinition(
      id: '5',
      floorId: '1',
      name: 'Table 5',
      sizeLabel: 'square',
      seats: 4,
      sortOrder: 1,
    );
    const other = DiningTableDefinition(
      id: '9',
      floorId: '2',
      name: 'Other floor',
      sizeLabel: 'square',
      seats: 4,
      sortOrder: 0,
    );
    final matches = tableSearchMatches(
      local: [a],
      definitions: [a, b, other],
      floorId: '1',
      results: [
        hit,
        const TableSearchResult(tableId: 9, floorId: 2, label: 'Other floor'),
        const TableSearchResult(
          tableId: 99,
          floorId: 1,
          label: 'Not configured',
        ),
      ],
    );
    expect(matches, [b, a]);
    expect(identical(matches.first, b), true);
    expect(
      tableSearchMatches(
        local: [a],
        definitions: [a, b],
        floorId: '1',
        results: [],
      ),
      [a],
    );
  });

  for (final locale in ['en', 'ar']) {
    testWidgets(
      'search $locale shows actual reference/total and offline copy without an open action',
      (tester) async {
        final search = TableSearchController((_) async => [hit]);
        addTearDown(search.dispose);
        Future<void> render() => tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(body: TableSearchSummary(search: search)),
          ),
        );
        search.update('T-09', enabled: true, degraded: false);
        await tester.pump(const Duration(milliseconds: 400));
        await render();
        await tester.pumpAndSettle();
        expect(find.textContaining('T-0906-012'), findsOneWidget);
        expect(find.textContaining('4.700'), findsOneWidget);
        expect(find.byType(ActionChip), findsNothing);
        expect(find.byType(InkWell), findsNothing);
        search.update('T-09', enabled: true, degraded: true);
        await render();
        await tester.pumpAndSettle();
        expect(
          find.text(
            locale == 'en'
                ? 'Server search unavailable offline — local matches only.'
                : 'بحث الخادم غير متاح دون اتصال — النتائج المحلية فقط.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('4.700'), findsNothing);
      },
    );
  }

  testWidgets(
    'Live search keyboard accepts hyphen, sends draft changes, clear and cancel',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final changes = <String>[];
      String? confirmed;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await showTableSearchKeyboard(
                    context,
                    initialValue: 'T',
                    onChanged: changes.add,
                  );
                },
                child: const Text('search'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('-'));
      await tester.pump();
      expect(changes.last, 'T-');
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(changes.last, '');
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(confirmed, isNull);
    },
  );
}
