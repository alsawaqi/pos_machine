import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const matrix = [
    (
      name: 'Off customer bill',
      mode: 'off',
      source: 'qr_web',
      customers: 1,
      known: true,
      keys: true,
      sheet: false,
    ),
    (
      name: 'Shadow customer bill',
      mode: 'shadow',
      source: 'qr_web',
      customers: 1,
      known: true,
      keys: true,
      sheet: false,
    ),
    (
      name: 'Live unknown bill',
      mode: 'live',
      source: null,
      customers: 0,
      known: false,
      keys: false,
      sheet: false,
    ),
    (
      name: 'Live qr_web credential before counted customer round',
      mode: 'live',
      source: 'qr_web',
      customers: 0,
      known: true,
      keys: true,
      sheet: true,
    ),
    (
      name: 'Live qr_web customer bill',
      mode: 'live',
      source: 'qr_web',
      customers: 1,
      known: true,
      keys: true,
      sheet: true,
    ),
    (
      name: 'Live main_pos staff-only bill',
      mode: 'live',
      source: 'main_pos',
      customers: 0,
      known: true,
      keys: true,
      sheet: false,
    ),
    (
      name: 'Live handheld staff-only bill',
      mode: 'live',
      source: 'handheld',
      customers: 0,
      known: true,
      keys: true,
      sheet: false,
    ),
    (
      name: 'Live defensive main_pos shared bill',
      mode: 'live',
      source: 'main_pos',
      customers: 2,
      known: true,
      keys: true,
      sheet: true,
    ),
    (
      name: 'Live defensive handheld shared bill',
      mode: 'live',
      source: 'handheld',
      customers: 2,
      known: true,
      keys: true,
      sheet: true,
    ),
    (
      name: 'Live old server without additive keys',
      mode: 'live',
      source: null,
      customers: 0,
      known: true,
      keys: false,
      sheet: false,
    ),
  ];
  for (final entry in matrix) {
    test('pay matrix: ${entry.name}', () async {
      final raw = _bill(
        source: entry.source,
        customers: entry.customers,
        keys: entry.keys,
      );
      final h = _RouterHarness(
        mode: entry.mode,
        board: entry.known ? _snapshot(raw) : const RemoteTableSnapshot(),
        rows: entry.known ? [raw] : [],
      );
      expect(tableBillNeedsSheet(entry.mode, h.board.tables[3]), entry.sheet);
      await h.route();
      expect(h.routes, [entry.sheet ? 'sheet' : 'local']);
      expect(h.fetches, entry.mode == 'live' ? 1 : 0);
      expect(h.router.busy, isFalse);
      expect(h.busyStates, entry.mode == 'live' ? [true, true, false] : []);
      debugPrint(
        'T7_PAY_MATRIX=${jsonEncode({'case': entry.name, 'mode': entry.mode, 'source': entry.source, 'customer_rounds': entry.customers, 'keys_present': entry.keys, 'fetches': h.fetches, 'outcome': h.routes.single})}',
      );
    });
  }

  test(
    'a source value without a known bill identity never routes to settlement',
    () {
      final row = RemoteTableState(
        tableId: 3,
        fetchedAt: DateTime.utc(2026, 9, 6),
        billSource: 'qr_web',
        billCustomerRounds: 1,
      );
      expect(tableBillNeedsSheet('live', row), isFalse);
    },
  );

  test('a non-table Live cart does not read the board', () async {
    final h = _RouterHarness(
      tableId: null,
      rows: [_bill(source: 'qr_web', customers: 1)],
    );
    await h.route();
    expect(h.fetches, 0);
    expect(h.routes, ['local']);
    expect(h.busyStates, isEmpty);
  });

  test('tender request force-reads the board and adopts a customer bill before any local tender', () async {
    final h = _RouterHarness(
      board: _snapshot(_bill(source: 'main_pos')),
      rows: [_bill(source: 'qr_web', customers: 1)],
    );
    expect(tableBillNeedsSheet('live', h.known), isFalse);
    await h.route();
    expect(h.timeline, ['fetch', 'sheet']);
    expect(h.routes, ['sheet']);
    expect(h.fetches, 1);
    expect(h.known?.billSource, 'qr_web');
    expect(h.known?.billCustomerRounds, 1);
  });

  for (final known in [true, false]) {
    test(
      'offline ${known ? 'known qr_web bill uses sheet' : 'unknown bill falls back to local Pay'}',
      () async {
        final h = _RouterHarness(
          board: known
              ? _snapshot(_bill(source: 'qr_web', customers: 1))
              : const RemoteTableSnapshot(),
          fetchError: StateError('Offline'),
        );
        await h.route();
        expect(h.fetches, 1);
        expect(h.routes, [known ? 'sheet' : 'local']);
        expect(h.router.busy, isFalse);
        debugPrint(
          'T7_PAY_MATRIX=${jsonEncode({'case': known ? 'offline known customer bill' : 'offline unknown bill', 'fetches': h.fetches, 'outcome': h.routes.single})}',
        );
      },
    );
  }

  test('a failed forced read retains the previous successful read identity and timestamp', () async {
    final h = _RouterHarness(
      board: _snapshot(_bill(source: 'main_pos')),
      rows: [_bill(source: 'qr_web', customers: 1)],
    );
    await h.route();
    final cached = h.known;
    expect(cached?.billSource, 'qr_web');
    h.fetchError = StateError('Offline on the next tender request');
    h.routes.clear();
    await h.route();
    expect(h.routes, ['sheet']);
    expect(h.known, same(cached));
    expect(h.fetches, 2);
  });

  test(
    'a successful absent-row response tombstones an older known customer bill',
    () async {
      final h = _RouterHarness(
        board: _snapshot(_bill(source: 'qr_web', customers: 1)),
        rows: [_bill(source: 'qr_web', customers: 1)],
      );
      await h.route();
      expect(h.known?.billSource, 'qr_web');
      h.rows = [];
      h.routes.clear();
      await h.route();
      expect(h.routes, ['local']);
      expect(h.known, isNull);
      h.fetchError = StateError('Offline after the empty successful read');
      h.routes.clear();
      await h.route();
      expect(h.routes, ['local']);
      expect(h.known, isNull);
    },
  );

  test(
    'another tables customer bill cannot redirect the selected staff table',
    () async {
      final h = _RouterHarness(
        board: _snapshot(_bill(source: 'main_pos')),
        rows: [
          _bill(id: 4, source: 'qr_web', customers: 2),
          _bill(source: 'main_pos'),
        ],
      );
      await h.route();
      expect(h.routes, ['local']);
      expect(h.known?.tableId, 3);
      expect(h.known?.billOrderUuid, 'bill-3');
      expect(h.known?.billSource, 'main_pos');
    },
  );

  test(
    'a cached identity never leaks into another table or session context',
    () async {
      final h = _RouterHarness(rows: [_bill(source: 'qr_web', customers: 1)]);
      await h.route();
      expect(h.known?.billSource, 'qr_web');
      final other = _snapshot(_bill(id: 4, source: 'main_pos'));
      expect(
        h.router.known(tableId: 4, contextKey: h.contextKey, board: other),
        same(other.tables[4]),
      );
      expect(
        h.router.known(
          tableId: 3,
          contextKey: 'another-device-session',
          board: const RemoteTableSnapshot(),
        ),
        isNull,
      );
    },
  );

  test('context invalidation while the forced read is pending neither caches nor routes', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final h = _RouterHarness(
      board: _snapshot(_bill(source: 'main_pos')),
      delayedRead: pending,
    );
    final original = h.known;
    final future = h.route();
    expect(h.router.busy, isTrue);
    expect(h.fetches, 1);
    h.current = false;
    pending.complete([_bill(source: 'qr_web', customers: 1)]);
    await future;
    expect(h.routes, isEmpty);
    expect(h.known, same(original));
    expect(h.router.busy, isFalse);
    expect(h.busyStates, [true, false]);
  });

  test('already-invalid table context performs no read or routing', () async {
    final h = _RouterHarness()..current = false;
    await h.route();
    expect(h.fetches, 0);
    expect(h.routes, isEmpty);
    expect(h.busyStates, isEmpty);
  });

  test(
    'double tapping a busy forced read issues one read and one route',
    () async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final h = _RouterHarness(delayedRead: pending);
      final first = h.route();
      await h.route();
      expect(h.fetches, 1);
      expect(h.router.busy, isTrue);
      expect(h.routes, isEmpty);
      pending.complete([_bill(source: 'qr_web', customers: 1)]);
      await first;
      expect(h.routes, ['sheet']);
      expect(h.router.busy, isFalse);
      expect(h.busyStates, [true, true, false]);
    },
  );

  test('a newer polling row overrides the earlier tender-read cache', () async {
    final h = _RouterHarness(rows: [_bill(source: 'qr_web', customers: 1)]);
    await h.route();
    final cached = h.known;
    final newer = _snapshot(
      _bill(source: 'main_pos'),
      at: DateTime.now().add(const Duration(minutes: 1)),
    );
    final known = h.router.known(
      tableId: 3,
      contextKey: h.contextKey,
      board: newer,
    );
    expect(cached?.billSource, 'qr_web');
    expect(known, same(newer.tables[3]));
    expect(known?.billSource, 'main_pos');
  });

  test(
    'a newer polling-board tombstone overrides the earlier tender-read cache',
    () async {
      final h = _RouterHarness(rows: [_bill(source: 'qr_web', customers: 1)]);
      await h.route();
      expect(h.known?.billSource, 'qr_web');
      final newer = RemoteTableSnapshot(
        meta: RemoteSyncMeta(
          boardFetchedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );
      expect(
        h.router.known(tableId: 3, contextKey: h.contextKey, board: newer),
        isNull,
      );
    },
  );

  test(
    'a failed in-flight read uses the latest polling customer identity',
    () async {
      final pending = Completer<List<Map<String, dynamic>>>();
      final h = _RouterHarness(
        board: _snapshot(_bill(source: 'main_pos')),
        delayedRead: pending,
      );
      final future = h.route();
      h.board = _snapshot(
        _bill(source: 'qr_web', customers: 1),
        at: DateTime.now().add(const Duration(minutes: 1)),
      );
      pending.completeError(StateError('Offline after a newer polling board'));
      await future;
      expect(h.routes, ['sheet']);
      expect(h.known?.billSource, 'qr_web');
      expect(h.fetches, 1);
    },
  );

  test('a successful stale forced read cannot override a newer polling customer bill', () async {
    final pending = Completer<List<Map<String, dynamic>>>();
    final h = _RouterHarness(
      board: _snapshot(_bill(source: 'main_pos')),
      delayedRead: pending,
    );
    final future = h.route();
    h.board = _snapshot(
      _bill(source: 'qr_web', customers: 1),
      at: DateTime.now().add(const Duration(minutes: 1)),
    );
    pending.complete([_bill(source: 'main_pos')]);
    await future;
    expect(h.routes, ['sheet']);
    expect(h.known, same(h.board.tables[3]));
    expect(h.known?.billSource, 'qr_web');
    expect(h.fetches, 1);
    debugPrint(
      'T7_PAY_MATRIX={"case":"newer customer board beats successful stale forced read","outcome":"sheet","local_dispatches":0}',
    );
  });

  test(
    'adoption after opening the local tender page is rechecked before dispatch',
    () async {
      final h = _RouterHarness(
        board: _snapshot(_bill(source: 'main_pos')),
        rows: [_bill(source: 'main_pos')],
      );
      await h.route();
      expect(h.routes, ['local']);
      h.routes.clear();
      h.rows = [_bill(source: 'qr_web', customers: 1)];
      await h.route();
      expect(h.routes, ['sheet']);
      expect(h.routes.where((route) => route == 'local'), isEmpty);
      expect(h.fetches, 2);
    },
  );

  for (final settleBill in [false, true]) {
    testWidgets(
      'actual cart button ${settleBill ? 'offers Settle bill without a local total' : 'keeps the local Pay label and total'}',
      (tester) async {
        var taps = 0;
        await _pumpButton(tester, settleBill: settleBill, onTap: () => taps++);
        expect(
          find.text(settleBill ? 'Settle bill' : 'Process to Pay'),
          findsOneWidget,
        );
        expect(
          find.textContaining('3.333 OMR'),
          settleBill ? findsNothing : findsOneWidget,
        );
        if (settleBill) {
          expect(find.text('Customer bill'), findsOneWidget);
        }
        await tester.tap(find.byType(InkWell));
        await tester.pump();
        expect(taps, 1);
      },
    );
  }

  testWidgets('the actual cart button is disabled while routing is busy', (
    tester,
  ) async {
    var taps = 0;
    await _pumpButton(
      tester,
      settleBill: true,
      busy: true,
      onTap: () => taps++,
    );
    expect(find.text('Processing Payment'), findsOneWidget);
    final button = tester.widget<InkWell>(find.byType(InkWell));
    expect(button.onTap, isNull);
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(taps, 0);
  });
}

Map<String, dynamic> _bill({
  int id = 3,
  String? source = 'main_pos',
  int customers = 0,
  bool keys = true,
}) => {
  'table_id': id,
  'table_label': 'Table $id',
  'seating': {'uuid': 'seat-$id', 'status': 'open'},
  'bill': {
    'order_uuid': 'bill-$id',
    'status': 'open',
    'grand_total_baisas': 9876,
    if (keys) ...{
      'source': source,
      'customer_rounds': customers,
      'staff_rounds': 1,
    },
  },
};

RemoteTableSnapshot _snapshot(Map<String, dynamic> raw, {DateTime? at}) {
  final timestamp = at ?? DateTime.utc(2020);
  final row = RemoteTableState.fromBoard(raw, timestamp);
  return RemoteTableSnapshot(
    tables: {row.tableId: row},
    meta: RemoteSyncMeta(boardFetchedAt: timestamp),
  );
}

class _RouterHarness {
  _RouterHarness({
    this.mode = 'live',
    this.tableId = 3,
    this.board = const RemoteTableSnapshot(),
    this.rows = const [],
    this.fetchError,
    this.delayedRead,
  });

  final router = TableCartPayRouter();
  final String contextKey = 'branch-1:device-2:staff-3';
  String mode;
  int? tableId;
  RemoteTableSnapshot board;
  List<Map<String, dynamic>> rows;
  Object? fetchError;
  final Completer<List<Map<String, dynamic>>>? delayedRead;
  bool current = true;
  int fetches = 0;
  final List<String> routes = [];
  final List<String> timeline = [];
  final List<bool> busyStates = [];

  RemoteTableState? get known =>
      router.known(tableId: tableId!, contextKey: contextKey, board: board);

  Future<void> route() => router.route(
    mode: mode,
    tableId: tableId,
    contextKey: contextKey,
    board: board,
    latestBoard: () => board,
    fetchBoard: () async {
      fetches++;
      timeline.add('fetch');
      if (fetchError != null) throw fetchError!;
      return delayedRead?.future ?? rows;
    },
    isCurrent: () => current,
    changed: () => busyStates.add(router.busy),
    openSheet: () async {
      routes.add('sheet');
      timeline.add('sheet');
    },
    openLocal: () async {
      routes.add('local');
      timeline.add('local');
    },
  );
}

Future<void> _pumpButton(
  WidgetTester tester, {
  required bool settleBill,
  required VoidCallback onTap,
  bool busy = false,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 450,
          height: 110,
          child: buildTableCartPayButtonForTest(
            total: 3.333,
            busy: busy,
            settleBill: settleBill,
            onTap: onTap,
          ),
        ),
      ),
    ),
  ),
);
