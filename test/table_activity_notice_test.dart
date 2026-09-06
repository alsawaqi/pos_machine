import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/l10n/l10n_ar.dart';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/table_shadow_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'table_ledger_store_test.dart' show createV5;

Map<String, dynamic> b5Board({int count = 3, bool pending = true}) => {
  'table_id': 5,
  'table_label': 'Table 5',
  'floor_id': 1,
  'seating': {
    'uuid': 'seat-5',
    'status': 'open',
    'origin': 'station',
    'temp_reference': 'T-0906-012',
    'pending_rounds': [
      if (pending)
        {
          'round_id': 71,
          'priced_lines': [
            {'qty': 2},
            {'qty': 3},
          ],
        },
    ],
  },
  'bill': {
    'pending_rounds': count,
    'grand_total_baisas': 4700,
    'order_uuid': 'bill-5',
    'status': 'open',
  },
};

TableShadowEvent arrival(
  int id, {
  String type = 'customer_order_arrived',
  int? device,
  int? round = 71,
}) => TableShadowEvent(
  id: id,
  tableId: 5,
  eventType: type,
  deviceId: device,
  payload: {'order_uuid': 'bill-5', 'round_id': ?round},
);

class ActivityGateway implements TableShadowGateway {
  final calls = <String>[];
  List<TableShadowEvent> events = [];
  List<Map<String, dynamic>> board = [b5Board()];
  int latest = 10;
  Object? boardError;
  Completer<TableShadowFeed>? delay;
  @override
  Future<List<Map<String, dynamic>>> fetchBoard() async {
    calls.add('board');
    if (boardError != null) throw boardError!;
    return board;
  }

  @override
  Future<TableShadowFeed> fetchFeed({
    required int after,
    int limit = 100,
  }) async {
    calls.add('feed:$after');
    if (delay != null) return delay!.future;
    final pending = events.where((e) => e.id > after).toList();
    return TableShadowFeed(
      events: pending.take(limit).toList(),
      latestId: latest,
      hasMore: pending.length > limit,
    );
  }
}

class ActivityHarness {
  late Database db;
  late LocalOrderStorageService store;
  late TableShadowRepository repository;
  final gateway = ActivityGateway();
  final notices = <TableActivityNotice>[];
  final feeds = <List<int>>[];
  var now = DateTime.utc(2026, 9, 6, 12);
  String? scope = 'branch:device';
  Future<void> init({int? watermark = 10, String mode = 'live'}) async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, _) async {
          await createV5(db);
          await LocalOrderStorageService.createTableLedger(db);
        },
      ),
    );
    store = LocalOrderStorageService.forTesting(db);
    await store.saveRemoteMeta(
      RemoteSyncMeta(feedCursor: 10, lastNotifiedEventId: watermark),
    );
    restart(mode: mode);
    addTearDown(() async {
      repository.dispose();
      await db.close();
    });
  }

  void restart({String mode = 'live'}) {
    repository = TableShadowRepository(
      gateway: gateway,
      store: store,
      clock: () => now,
      readScope: () => scope,
      writeScope: (v) async {
        scope = v;
      },
      log: (_) {},
    );
    repository.configure(
      mode: mode,
      scope: 'branch:device',
      sessionEpoch: 'token',
      authenticated: true,
    );
    repository.activityNotices.listen(notices.addAll);
    repository.feedEvents.listen((events) {
      expect(
        repository.snapshot.meta.feedCursor,
        events.isEmpty ? isNotNull : greaterThanOrEqualTo(events.last.id),
      );
      feeds.add(events.map((e) => e.id).toList());
    });
  }

  Future<void> poll(List<TableShadowEvent> events, {int? latest}) async {
    gateway.events = events;
    gateway.latest =
        latest ?? (events.isEmpty ? gateway.latest : events.last.id);
    await repository.pollNow();
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('only customer_order_arrived with device_id null notifies; cursor precedes feed emission', () async {
    final h = ActivityHarness();
    await h.init();
    await h.poll([
      arrival(11, type: 'round_pending'),
      arrival(12, type: 'round_appended'),
      arrival(13, type: 'round_accepted'),
      arrival(14, device: 4),
      arrival(15, device: 0),
      arrival(16),
    ]);
    expect(h.notices.map((n) => n.eventId), [16]);
    expect(h.feeds, [
      [11, 12, 13, 14, 15, 16],
    ]);
    expect(h.gateway.calls, ['feed:10', 'board']);
    expect((await h.store.readRemoteMeta()).lastNotifiedEventId, 16);
  });

  test(
    'first B5 run initializes latest_id without historical notification burst',
    () async {
      final h = ActivityHarness();
      await h.init(watermark: null);
      await h.poll([arrival(11)], latest: 120);
      expect(h.notices, isEmpty);
      expect((await h.store.readRemoteMeta()).lastNotifiedEventId, 120);
      await h.poll([arrival(12), arrival(120)]);
      expect(h.notices, isEmpty);
      await h.poll([arrival(121)]);
      expect(h.notices.map((n) => n.eventId), [121]);
    },
  );

  test(
    'notification watermark survives repository restart in real memory SQLite',
    () async {
      final h = ActivityHarness();
      await h.init();
      await h.poll([arrival(11)]);
      h.repository.dispose();
      h.restart();
      await h.poll([arrival(11), arrival(12)]);
      expect(h.notices.map((n) => n.eventId), [11, 12]);
      expect(
        (await h.db.query('remote_sync_meta')).single['last_notified_event_id'],
        12,
      );
      expect(h.gateway.calls, ['feed:10', 'board', 'feed:11', 'board']);
    },
  );

  test('Live restart restores the board bell even with no new feed event', () async {
    final h = ActivityHarness();
    await h.init();
    await h.poll([arrival(11)]);
    expect(h.repository.activityBoard[5]?.pendingCount, 3);
    h.repository.dispose();
    h.restart();
    await h.poll([]);
    final restored = h.repository.activityBoard[5]?.pendingCount ?? 0;
    // The old remote-table cache does not persist bill.pending_rounds.
    // The owner-approved Live startup refresh restores the real count without
    // fabricating a cached count or replaying a notification.
    expect(restored, 3);
    expect(h.notices.map((n) => n.eventId), [11]);
    expect((await h.store.readRemoteMeta()).lastNotifiedEventId, 11);
    expect(h.gateway.calls, ['feed:10', 'board', 'feed:11', 'board']);
    await h.poll([]);
    expect(h.gateway.calls, ['feed:10', 'board', 'feed:11', 'board', 'feed:11']);
  });

  test('Live quiet startup retries a failed board using existing backoff', () async {
    final h = ActivityHarness();
    await h.init();
    h.gateway.boardError = StateError('offline');
    await h.poll([]);
    expect(h.repository.activityBoard, isEmpty);
    expect(h.gateway.calls, ['feed:10', 'board']);
    expect((await h.store.readRemoteMeta()).lastNotifiedEventId, 10);
    await h.poll([]);
    expect(h.gateway.calls, ['feed:10', 'board']);
    h.now = h.now.add(const Duration(seconds: 5));
    h.gateway.boardError = null;
    await h.poll([]);
    expect(h.repository.activityBoard[5]?.pendingCount, 3);
    expect(h.gateway.calls, ['feed:10', 'board', 'feed:10', 'board']);
    expect(h.notices, isEmpty);
  });

  test('pending notice counts priced_lines quantities and bell uses bill.pending_rounds', () async {
    final h = ActivityHarness();
    await h.init();
    await h.poll([arrival(11)]);
    final notice = h.notices.single;
    expect(notice.kind, TableActivityKind.pending);
    expect(notice.itemCount, 5);
    expect(h.repository.activityBoard[5]!.pendingCount, 3);
    expect(
      tableActivityMessage(L10nEn(), notice),
      'Table 5 · T-0906-012: customer order (5 items) — confirm on the QR tab.',
    );
    expect(
      tableActivityMessage(L10nAr(), notice),
      'Table 5 · T-0906-012: طلب عميل (5 صنف) — أكّده من تبويب QR.',
    );
    h.gateway.board = [b5Board(count: 0, pending: false)];
    await h.poll([arrival(12, type: 'round_resolved')]);
    expect(h.repository.activityBoard[5]!.pendingCount, 0);
    expect(h.notices, hasLength(1));
  });

  test(
    'kitchen-direct omits item count; finish asks for bill in EN and AR',
    () async {
      final h = ActivityHarness();
      await h.init();
      h.gateway.board = [b5Board(count: 0, pending: false)];
      await h.poll([arrival(11), arrival(12, round: null)]);
      expect(h.notices.map((n) => n.kind), [
        TableActivityKind.kitchen,
        TableActivityKind.bill,
      ]);
      expect(h.notices.map((n) => n.itemCount), [null, null]);
      expect(
        tableActivityMessage(L10nEn(), h.notices.first),
        'Table 5 · T-0906-012: customer order sent to the kitchen.',
      );
      expect(
        tableActivityMessage(L10nAr(), h.notices.first),
        'Table 5 · T-0906-012: أُرسل طلب العميل إلى المطبخ.',
      );
      expect(
        tableActivityMessage(L10nEn(), h.notices.last),
        'Table 5 · T-0906-012: customer asked for the bill.',
      );
      expect(
        tableActivityMessage(L10nAr(), h.notices.last),
        'Table 5 · T-0906-012: طلب العميل الفاتورة.',
      );
    },
  );

  test('failed board emits neither notices nor applied feed, retry keeps the event', () async {
    final h = ActivityHarness();
    await h.init();
    h.gateway.boardError = StateError('offline');
    await h.poll([arrival(11)]);
    expect(h.notices, isEmpty);
    expect(h.feeds, isEmpty);
    final before = await h.store.readRemoteMeta();
    expect(before.feedCursor, 10);
    expect(before.lastNotifiedEventId, 10);
    h.now = h.now.add(const Duration(seconds: 5));
    h.gateway.boardError = null;
    await h.poll([arrival(11)]);
    expect(h.notices.map((n) => n.eventId), [11]);
  });

  test('Off makes no request; Shadow suppresses notices without changing T5 cadence', () async {
    final h = ActivityHarness();
    await h.init(mode: 'off');
    await h.poll([arrival(11)]);
    expect(h.gateway.calls, isEmpty);
    h.repository.configure(
      mode: 'shadow',
      scope: 'branch:device',
      sessionEpoch: 'token',
      authenticated: true,
    );
    await h.poll([arrival(11)]);
    expect(h.notices, isEmpty);
    expect(h.repository.activityBoard, isEmpty);
    h.repository.configure(
      mode: 'live',
      scope: 'branch:device',
      sessionEpoch: 'token',
      authenticated: true,
    );
    await h.poll([arrival(12)]);
    expect(h.notices.map((n) => n.eventId), [12]);
  });

  test('scope change discards an in-flight feed without notifications or board writes', () async {
    final h = ActivityHarness();
    await h.init();
    h.gateway.delay = Completer<TableShadowFeed>();
    final poll = h.repository.pollNow();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    h.repository.configure(
      mode: 'live',
      scope: 'other:device',
      sessionEpoch: 'other',
      authenticated: true,
    );
    h.gateway.delay!.complete(
      TableShadowFeed(events: [arrival(11)], latestId: 11, hasMore: false),
    );
    await poll;
    expect(h.notices, isEmpty);
    expect(h.repository.activityBoard, isEmpty);
    expect(h.gateway.calls.where((c) => c == 'board'), isEmpty);
  });

  test('notice provider projects the committed stream; feed never writes dining_tables', () async {
    final h = ActivityHarness();
    await h.init();
    await h.db.insert('dining_tables', {
      'table_id': '5',
      'floor_id': '1',
      'status': 'occupied',
      'order_reference': 'LOCAL-5',
      'updated_at': h.now.toIso8601String(),
      'draft_json': '{"keep":true}',
    });
    final before = jsonEncode(await h.db.query('dining_tables'));
    final container = ProviderContainer(
      overrides: [
        tableShadowRepositoryProvider.overrideWithValue(h.repository),
      ],
    );
    addTearDown(container.dispose);
    final seen = <int>[];
    container.listen(tableActivityNoticeProvider, (_, next) {
      seen.addAll(next.asData?.value.map((n) => n.eventId) ?? []);
    });
    await h.poll([arrival(11)]);
    expect(seen, [11]);
    expect(jsonEncode(await h.db.query('dining_tables')), before);
  });
}
