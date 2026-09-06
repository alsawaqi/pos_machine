import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/remote_table_state.dart';
import '../services/pos_api_service.dart';
import '../services/table_shadow_service.dart';

/// The only persistence capability here is RemoteTableStore. This repository
/// cannot update a local order, dining-table row, or the cashier's controller.
class TableShadowRepository with WidgetsBindingObserver {
  TableShadowRepository({
    required this.gateway,
    required this.store,
    required this.readScope,
    required this.writeScope,
    DateTime Function()? clock,
    void Function(String)? log,
  }) : _clock = clock ?? DateTime.now,
       _log = log ?? debugPrint;

  // Asking beyond the sequence returns an empty page plus the branch high-water
  // mark. Never persist this sentinel as the cursor or replay historical events.
  static const emptyFeedAfter = 9223372036854775807;
  final TableShadowGateway gateway;
  final RemoteTableStore store;
  final String? Function() readScope;
  final Future<void> Function(String) writeScope;
  final DateTime Function() _clock;
  final void Function(String) _log;
  final _changes = StreamController<RemoteTableSnapshot>.broadcast();
  final _feedEvents = StreamController<List<TableShadowEvent>>.broadcast();
  final _activityNotices = StreamController<List<TableActivityNotice>>.broadcast();
  Map<int, TableActivityBoardRow> _activityBoard = const {};
  bool _activityBoardLoaded = false;
  Stream<List<TableShadowEvent>> get feedEvents => _feedEvents.stream;
  Stream<List<TableActivityNotice>> get activityNotices => _activityNotices.stream;
  Map<int, TableActivityBoardRow> get activityBoard =>
      _mode == 'live' ? _activityBoard : const {};
  /// Display-only T7 bell; does not enable Shadow notifications or new reads.
  Map<int, TableActivityBoardRow> get displayActivityBoard =>
      _mode == 'off' ? const {} : _activityBoard;
  late final _disagreements = TableDisagreementLog(store, clock: _clock);
  List<LocalTableShadowView> Function()? localTables;

  RemoteTableSnapshot _snapshot = const RemoteTableSnapshot();
  RemoteTableSnapshot get snapshot =>
      _mode == 'off' ? const RemoteTableSnapshot() : _snapshot;
  Stream<RemoteTableSnapshot> get changes => _changes.stream;
  String get mode => _mode;
  DateTime? get retryNotBefore => _retryNotBefore;
  bool get unauthorized => _blockedEpoch != null && _blockedEpoch == _epoch;

  Timer? _timer;
  bool _started = false, _disposed = false, _foreground = true;
  bool _visible = false, _busy = false, _authenticated = false;
  String _mode = 'off', _scope = '';
  String? _loadedScope;
  Object? _epoch, _blockedEpoch;
  int _generation = 0;
  DateTime? _retryNotBefore;

  void configure({
    required String mode,
    required String scope,
    required Object? sessionEpoch,
    required bool authenticated,
  }) {
    final nextMode = tableSessionsMode(mode);
    final changed =
        _mode != nextMode ||
        _scope != scope ||
        _epoch != sessionEpoch ||
        _authenticated != authenticated;
    if (_scope != scope || _epoch != sessionEpoch) {
      _generation++;
      _snapshot = const RemoteTableSnapshot();
      _activityBoard = const {};
      _activityBoardLoaded = false;
      _loadedScope = null;
      _disagreements.reset();
      _retryNotBefore = null;
    }
    _mode = nextMode;
    _scope = scope;
    _epoch = sessionEpoch;
    _authenticated = authenticated;
    if (changed) {
      _emit();
      _schedule(Duration.zero);
    }
  }

  void start() {
    if (_started || _disposed) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _schedule(Duration.zero);
  }

  void setFloorPlanVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _schedule(_cadence);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule(_foreground ? Duration.zero : _cadence);
  }

  bool get _enabled =>
      !_disposed &&
      _foreground &&
      _authenticated &&
      _mode != 'off' &&
      _scope.isNotEmpty &&
      !unauthorized;
  bool _current(int generation) => _enabled && _generation == generation;
  Duration get _cadence => Duration(seconds: _visible ? 5 : 60);

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_enabled) return;
    final remaining = _retryNotBefore?.difference(_clock());
    if (remaining != null && remaining > delay) delay = remaining;
    _timer = Timer(delay, () => unawaited(pollNow()));
  }

  Future<void> pollNow() async {
    if (!_enabled || _busy) return;
    final remaining = _retryNotBefore?.difference(_clock());
    if (remaining != null && remaining > Duration.zero) {
      _schedule(remaining);
      return;
    }
    _timer?.cancel();
    _busy = true;
    final generation = _generation;
    try {
      await _loadScope(generation);
      if (!_current(generation)) return;
      var cursor = _snapshot.meta.feedCursor;
      final priorNoticeId = _snapshot.meta.lastNotifiedEventId;
      var latestId = cursor ?? 0;
      final applied = <TableShadowEvent>[];
      if (cursor == null) {
        await _refreshBoard(generation);
        if (!_current(generation)) return;
        final latest = await gateway.fetchFeed(after: emptyFeedAfter);
        if (!_current(generation)) return;
        if (latest.events.isNotEmpty) {
          throw const FormatException('Initial high-water probe was not empty');
        }
        cursor = latest.latestId;
        latestId = latest.latestId;
        // Close the board-before-watermark race: anything included in the
        // sampled cursor must also be represented in our initial board.
        await _refreshBoard(generation);
        if (!_current(generation)) return;
      }
      var dirty = false;
      for (var page = 0; page < 5; page++) {
        if (!_current(generation)) return;
        final feed = await gateway.fetchFeed(after: cursor!);
        if (!_current(generation)) return;
        latestId = math.max(latestId, feed.latestId);
        for (final event in feed.events) {
          if (event.id <= cursor!) {
            throw const FormatException('Table feed is not strictly ascending');
          }
          cursor = event.id;
          applied.add(event);
          dirty = true;
        }
        if (!feed.hasMore || feed.events.isEmpty) break;
      }
      // Owner-approved B5 exception: the T5 cache has no pending-round count.
      // Hydrate it once in Live after startup/scope change, even on a quiet
      // feed. A dirty-feed refresh satisfies this too; failed loads retry under
      // the existing backoff. Off/Shadow and the poll cadence are unchanged.
      if (dirty || (_mode == 'live' && !_activityBoardLoaded)) {
        await _refreshBoard(generation);
      }
      if (!_current(generation)) return;
      final meta = RemoteSyncMeta(
        feedCursor: cursor,
        boardFetchedAt: _snapshot.meta.boardFetchedAt,
        lastFeedOkAt: _clock(),
        // Persist notification dedup with the applied cursor, before emitting
        // either stream. A failed board/store write emits neither, so retry is
        // safe. Initial upgrade suppresses all history through latest_id.
        lastNotifiedEventId: priorNoticeId == null
            ? latestId : math.max(priorNoticeId, cursor ?? 0),
      );
      await store.saveRemoteMeta(meta);
      if (!_current(generation)) return;
      _snapshot = RemoteTableSnapshot(tables: _snapshot.tables, meta: meta);
      _retryNotBefore = null;
      _emit();
      _feedEvents.add(List.unmodifiable(applied));
      if (_mode == 'live' && priorNoticeId != null) {
        final notices = [
          for (final event in applied)
            if (event.id > priorNoticeId)
              TableActivityNotice.fromEvent(event, _activityBoard[event.tableId]),
        ].whereType<TableActivityNotice>().toList(growable: false);
        if (notices.isNotEmpty) _activityNotices.add(List.unmodifiable(notices));
      }
    } catch (error) {
      if (_current(generation)) await _recordFailure(error);
    } finally {
      _busy = false;
      _schedule(_cadence);
    }
  }

  Future<void> _loadScope(int generation) async {
    if (_loadedScope == _scope) return;
    final scope = _scope;
    if (readScope() != scope) {
      await store.clearRemoteScope();
      if (!_current(generation)) return;
      await writeScope(scope);
    }
    if (!_current(generation)) return;
    try {
      final rows = await store.readRemoteTables();
      final meta = await store.readRemoteMeta();
      if (!_current(generation)) return;
      _snapshot = RemoteTableSnapshot(
        tables: {for (final row in rows) row.tableId: row},
        meta: meta,
      );
      _loadedScope = scope;
      _emit();
    } catch (_) {
      // Never call any local-order/table fallback on a failed shadow read.
      _snapshot = const RemoteTableSnapshot();
      rethrow;
    }
  }

  Future<void> _refreshBoard(int generation) async {
    final json = await gateway.fetchBoard();
    if (!_current(generation)) return;
    final now = _clock();
    final rows = [for (final row in json) RemoteTableState.fromBoard(row, now)];
    await store.replaceRemoteBoard(rows, now);
    if (!_current(generation)) return;
    try {
      await _disagreements.observe(localTables?.call() ?? const [], {
        for (final row in rows) row.tableId: row,
      });
    } catch (_) {
      // A failed remote journal read/write must not leave a seemingly usable
      // shadow. Keep the old cursor so the next successful poll retries it.
      _snapshot = RemoteTableSnapshot(meta: _snapshot.meta);
      rethrow;
    }
    if (!_current(generation)) return;
    final old = _snapshot.meta;
    _activityBoard = Map.unmodifiable({
      for (final row in json)
        (row['table_id'] as num).toInt(): TableActivityBoardRow.fromBoard(row),
    });
    _activityBoardLoaded = true;
    _snapshot = RemoteTableSnapshot(
      tables: {for (final row in rows) row.tableId: row},
      meta: RemoteSyncMeta(
        feedCursor: old.feedCursor,
        boardFetchedAt: now,
        lastFeedOkAt: old.lastFeedOkAt,
        lastError: old.lastError,
        consecutiveFailures: old.consecutiveFailures,
        lastNotifiedEventId: old.lastNotifiedEventId,
      ),
    );
    _emit();
  }

  Future<void> _recordFailure(Object error) async {
    final count = _snapshot.meta.consecutiveFailures + 1;
    final api = error is ApiException ? error : null;
    final delay = api?.statusCode == 429
        ? api?.retryAfter ?? const Duration(seconds: 5)
        : Duration(
            seconds: math
                .min(60, 5 * math.pow(2, math.min(count - 1, 4)))
                .toInt(),
          );
    _retryNotBefore = _clock().add(delay);
    if (api?.statusCode == 401) _blockedEpoch = _epoch;
    final meta = RemoteSyncMeta(
      feedCursor: _snapshot.meta.feedCursor,
      boardFetchedAt: _snapshot.meta.boardFetchedAt,
      lastFeedOkAt: _snapshot.meta.lastFeedOkAt,
      lastError: api == null
          ? 'shadow_unavailable'
          : 'http_${api.statusCode ?? 0}',
      consecutiveFailures: count,
      lastNotifiedEventId: _snapshot.meta.lastNotifiedEventId,
    );
    _snapshot = RemoteTableSnapshot(tables: _snapshot.tables, meta: meta);
    _log('Table shadow unavailable: ${meta.lastError}');
    try {
      await store.saveRemoteMeta(meta);
    } catch (_) {
      _log('Table shadow error metadata could not be persisted');
    }
    _emit();
  }

  void _emit() {
    if (!_disposed) _changes.add(snapshot);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    unawaited(_changes.close());
    unawaited(_feedEvents.close());
    unawaited(_activityNotices.close());
  }
}

/// Device-only comparison journal. No outbox or API dependency.
class TableDisagreementLog {
  TableDisagreementLog(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final RemoteTableStore store;
  final DateTime Function() _clock;
  final Map<String, String?> _lastClass = {};
  final Map<String, DateTime> _lastWritten = {};
  bool _loaded = false;

  void reset() {
    _loaded = false;
    _lastClass.clear();
    _lastWritten.clear();
  }

  Future<void> observe(
    Iterable<LocalTableShadowView> local,
    Map<int, RemoteTableState> remote,
  ) async {
    if (!_loaded) {
      final history = await store.readRemoteDisagreements(limit: -1);
      // Storage returns newest first. The most recent class survives restart.
      for (final row in history) {
        final table = row['table_id'] as String;
        final kind = row['kind'] as String;
        _lastClass.putIfAbsent(table, () => kind == 'resolved' ? null : kind);
        _lastWritten.putIfAbsent(
          '$table|$kind',
          () => DateTime.parse(row['observed_at'] as String),
        );
      }
      _loaded = true;
    }
    for (final table in local) {
      final server = remote[int.tryParse(table.tableId)];
      if (server == null) {
        continue; // Unknown/absent config is not an agreement.
      }
      final kind = classify(table, server);
      final previous = _lastClass[table.tableId];
      if (kind == previous) continue;
      final event = kind ?? (previous == null ? null : 'resolved');
      if (event == null) continue;
      final key = '${table.tableId}|$event';
      final now = _clock();
      final last = _lastWritten[key];
      if (last != null && now.difference(last) < const Duration(minutes: 5)) {
        _lastClass[table.tableId] = kind;
        continue;
      }
      await store.addRemoteDisagreement({
        'observed_at': now.toIso8601String(),
        'table_id': table.tableId,
        'local_status': table.status,
        'server_status': server.serverStatus,
        'server_origin': server.origin,
        'server_reference': server.reference,
        'local_reference': table.reference,
        'kind': event,
      });
      _lastWritten[key] = now;
      _lastClass[table.tableId] = kind;
    }
  }

  static String? classify(LocalTableShadowView local, RemoteTableState server) {
    if (server.occupied && local.status == 'available') {
      return 'server_occupied_local_free';
    }
    if (!server.occupied && local.status == 'occupied') {
      return 'local_occupied_server_free';
    }
    if (server.occupied &&
        local.status == 'occupied' &&
        server.reference != local.reference) {
      return 'reference_mismatch';
    }
    return null;
  }
}
