import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Gateway gateway;
  late _Store store;
  late TableShadowRepository repository;
  late DateTime now;
  String? scope;

  void configure({
    String mode = 'shadow',
    String device = 'branch:device',
    String token = 'token',
  }) {
    repository.configure(
      mode: mode,
      scope: device,
      sessionEpoch: token,
      authenticated: true,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 9, 6, 12);
    scope = 'branch:device';
    gateway = _Gateway();
    store = _Store();
    repository = TableShadowRepository(
      gateway: gateway,
      store: store,
      clock: () => now,
      readScope: () => scope,
      writeScope: (value) async {
        scope = value;
      },
      log: (_) {},
    );
    configure();
  });
  tearDown(() => repository.dispose());

  test(
    'off never calls the gateway, including foreground transitions',
    () async {
      configure(mode: 'off');
      await repository.pollNow();
      repository.setFloorPlanVisible(true);
      repository.didChangeAppLifecycleState(AppLifecycleState.paused);
      repository.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await repository.pollNow();
      expect(gateway.calls, isEmpty);
      expect(repository.snapshot.tables, isEmpty);
      expect(store.boardWrites, 0);
    },
  );

  test('first board samples an empty latest probe and closes its race without history', () async {
    store.meta = const RemoteSyncMeta();
    gateway.latest = 40;
    await repository.pollNow();
    expect(gateway.calls, [
      'board',
      'feed:${TableShadowRepository.emptyFeedAfter}',
      'board',
      'feed:40',
    ]);
    expect(store.meta.feedCursor, 40);
    expect(store.meta.lastFeedOkAt, now);
    expect(store.boardWrites, 2);
    expect(repository.snapshot.tables.keys, [1]);
  });

  test('feed hints refresh once after a batch and persist max id', () async {
    gateway.pages = [
      const TableShadowFeed(
        events: [
          TableShadowEvent(id: 11, tableId: 1),
          TableShadowEvent(id: 12, tableId: 999),
        ],
        latestId: 13,
        hasMore: true,
      ),
      const TableShadowFeed(
        events: [TableShadowEvent(id: 13, tableId: 2)],
        latestId: 13,
        hasMore: false,
      ),
    ];
    await repository.pollNow();
    expect(gateway.calls, ['feed:10', 'feed:12', 'board']);
    expect(store.boardWrites, 1);
    expect(store.meta.feedCursor, 13);
  });

  test('has_more is bounded to five pages before one board write', () async {
    gateway.pages = [
      for (var id = 11; id <= 16; id++)
        TableShadowFeed(
          events: [TableShadowEvent(id: id, tableId: 1)],
          latestId: 16,
          hasMore: true,
        ),
    ];
    await repository.pollNow();
    expect(
      gateway.calls.where((call) => call.startsWith('feed:')),
      hasLength(5),
    );
    expect(gateway.calls.last, 'board');
    expect(store.meta.feedCursor, 15);
    await repository.pollNow();
    expect(store.meta.feedCursor, 16);
  });

  test('failed board does not acknowledge feed hints', () async {
    gateway.pages = [
      const TableShadowFeed(
        events: [TableShadowEvent(id: 11, tableId: 1)],
        latestId: 11,
        hasMore: false,
      ),
    ];
    gateway.boardError = StateError('offline');
    await repository.pollNow();
    expect(store.meta.feedCursor, 10);
    expect(store.meta.consecutiveFailures, 1);
    expect(store.boardWrites, 0);
  });

  test('429 Retry-After cannot be bypassed by refresh or visibility', () async {
    gateway.feedError = ApiException(
      message: 'slow',
      statusCode: 429,
      retryAfter: const Duration(seconds: 30),
    );
    await repository.pollNow();
    expect(repository.retryNotBefore, now.add(const Duration(seconds: 30)));
    gateway.feedError = null;
    repository.setFloorPlanVisible(true);
    now = now.add(const Duration(seconds: 29));
    await repository.pollNow();
    expect(gateway.calls, ['feed:10']);
    now = now.add(const Duration(seconds: 1));
    await repository.pollNow();
    expect(gateway.calls, ['feed:10', 'feed:10']);
    expect(store.meta.consecutiveFailures, 0);
  });

  test('network failures back off 5 10 20 40 60 and persist health', () async {
    gateway.feedError = StateError('offline');
    for (final seconds in [5, 10, 20, 40, 60, 60]) {
      await repository.pollNow();
      expect(repository.retryNotBefore, now.add(Duration(seconds: seconds)));
      now = repository.retryNotBefore!;
    }
    expect(store.meta.consecutiveFailures, 6);
    expect(store.meta.lastError, 'shadow_unavailable');
  });

  test('401 stops until the device session is re-established', () async {
    gateway.feedError = ApiException(message: 'revoked', statusCode: 401);
    await repository.pollNow();
    expect(repository.unauthorized, isTrue);
    gateway.feedError = null;
    now = now.add(const Duration(hours: 1));
    configure(mode: 'live');
    await repository.pollNow();
    expect(gateway.calls, ['feed:10']);
    configure(token: 'replacement');
    await repository.pollNow();
    expect(gateway.calls, ['feed:10', 'feed:10']);
    expect(repository.unauthorized, isFalse);
  });

  for (final mode in ['shadow', 'live']) {
    test(
      '$mode stores unknown ids but only configured ids are rendered',
      () async {
        configure(mode: mode);
        gateway.board = [_row(1), _row(999)];
        gateway.pages = [
          const TableShadowFeed(
            events: [TableShadowEvent(id: 11, tableId: 999)],
            latestId: 11,
            hasMore: false,
          ),
        ];
        await repository.pollNow();
        expect(repository.snapshot.tables.keys, [1, 999]);
        expect(repository.snapshot.forTableIds(['1', '2']).keys, ['1']);
        expect(store.boardWrites, 1);
      },
    );
  }

  test('background polling does nothing and foreground resumes', () async {
    repository.didChangeAppLifecycleState(AppLifecycleState.paused);
    await repository.pollNow();
    expect(gateway.calls, isEmpty);
    repository.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await repository.pollNow();
    expect(gateway.calls, ['feed:10']);
  });

  test('failed remote read gives an empty shadow and logged error', () async {
    store.readError = StateError('corrupt remote table');
    await repository.pollNow();
    expect(repository.snapshot.tables, isEmpty);
    expect(repository.snapshot.meta.lastError, 'shadow_unavailable');
    expect(gateway.calls, isEmpty);
    expect(store.boardWrites, 0);
    expect(store.clears, 0);
  });

  test(
    're-pair discards an in-flight old-branch response and clears remote scope',
    () async {
      gateway.delayedFeed = Completer<TableShadowFeed>();
      final pending = repository.pollNow();
      await Future<void>.delayed(Duration.zero);
      configure(device: 'other:device', token: 'other');
      gateway.delayedFeed!.complete(
        const TableShadowFeed(
          events: [TableShadowEvent(id: 99, tableId: 1)],
          latestId: 99,
          hasMore: false,
        ),
      );
      await pending;
      expect(store.boardWrites, 0);
      expect(repository.snapshot.tables, isEmpty);
      gateway.delayedFeed = null;
      await repository.pollNow();
      expect(store.clears, 1);
      expect(scope, 'other:device');
      expect(store.meta.feedCursor, 10);
    },
  );

  testWidgets('visible cadence is five seconds, elsewhere sixty, off none', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    repository.start();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(gateway.calls, ['feed:10']);
    repository.setFloorPlanVisible(true);
    await tester.pump(const Duration(seconds: 4));
    expect(gateway.calls, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(gateway.calls, hasLength(2));
    repository.setFloorPlanVisible(false);
    await tester.pump(const Duration(seconds: 59));
    expect(gateway.calls, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(gateway.calls, hasLength(3));
    configure(mode: 'off');
    await tester.pump(const Duration(minutes: 2));
    expect(gateway.calls, hasLength(3));
    repository.dispose();
  });
}

Map<String, dynamic> _row(int id) => {
  'table_id': id,
  'seating': null,
  'bill': null,
};

class _Gateway implements TableShadowGateway {
  final List<String> calls = [];
  List<Map<String, dynamic>> board = [_row(1)];
  List<TableShadowFeed> pages = [];
  int latest = 10;
  Object? feedError, boardError;
  Completer<TableShadowFeed>? delayedFeed;
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
    expectSync(limit, 100);
    if (feedError != null) throw feedError!;
    if (delayedFeed != null) return delayedFeed!.future;
    if (after == TableShadowRepository.emptyFeedAfter || pages.isEmpty) {
      return TableShadowFeed(events: [], latestId: latest, hasMore: false);
    }
    return pages.removeAt(0);
  }
}

class _Store implements RemoteTableStore {
  List<RemoteTableState> rows = [];
  RemoteSyncMeta meta = const RemoteSyncMeta(feedCursor: 10);
  int boardWrites = 0, clears = 0;
  Object? readError;
  @override
  Future<List<RemoteTableState>> readRemoteTables() async {
    if (readError != null) throw readError!;
    return rows;
  }

  @override
  Future<RemoteSyncMeta> readRemoteMeta() async => meta;
  @override
  Future<void> replaceRemoteBoard(
    List<RemoteTableState> rows,
    DateTime at,
  ) async {
    boardWrites++;
    this.rows = rows;
  }

  @override
  Future<void> saveRemoteMeta(RemoteSyncMeta meta) async {
    this.meta = meta;
  }

  @override
  Future<void> clearRemoteScope() async {
    clears++;
    rows = [];
    meta = const RemoteSyncMeta();
  }

  @override
  Future<List<Map<String, Object?>>> readRemoteDisagreements({
    int limit = 200,
  }) async => [];
  @override
  Future<void> addRemoteDisagreement(Map<String, Object?> row) async {}
}
