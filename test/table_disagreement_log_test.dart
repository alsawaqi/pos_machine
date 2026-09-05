import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/models/remote_table_state.dart';

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
