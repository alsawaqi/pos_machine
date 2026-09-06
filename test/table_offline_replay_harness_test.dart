import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/qr_till_service.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

import 'support/fake_table_server.dart';
import 'table_ledger_store_test.dart' show createV5;

/// Real coordinator + durable Drift outbox + actual SQLite local store.
/// Only HTTP, the printer and the coordinator clock are replaced.
class ReplayDevice {
  ReplayDevice(this.server, this.id);
  final FakeTableServer server;
  final int id;
  late Database sqlite;
  late LocalOrderStorageService store;
  late AppDatabase drift;
  late OrderSyncRepository outbox;
  late TableSyncCoordinator coordinator;
  late FakeTableTransport transport;
  late PosApiService api;
  late Dio dio;
  late SharedPreferences preferences;
  int next = 0, printed = 0;
  bool printLocally = false;
  DateTime get now => server.now;

  Future<void> init() async {
    sqlite = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false, // Each simulated till owns a separate :memory: DB.
        version: 6,
        onCreate: (db, _) async {
          await createV5(db);
          await LocalOrderStorageService.createTableLedger(db);
        },
      ),
    );
    store = LocalOrderStorageService.forTesting(sqlite);
    drift = AppDatabase.forTesting(NativeDatabase.memory());
    preferences = await SharedPreferences.getInstance();
    transport = FakeTableTransport(server, id);
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))
      ..httpClientAdapter = transport;
    api = PosApiService(tokenGetter: () => 'fixture-$id', dio: dio);
    outbox = OrderSyncRepository(api, drift);
    await restartCoordinator();
    addTearDown(() async {
      await coordinator.settled;
      await coordinator.dispose();
      await outbox.dispose();
      dio.close(force: true);
      await drift.close();
      await sqlite.close();
    });
  }

  Future<void> restartCoordinator() async {
    coordinator = TableSyncCoordinator(
      outbox: outbox,
      store: store,
      loadSessions: store.loadDiningTableSessions,
      mode: () => 'live',
      degraded: () => !transport.online,
      staffId: () => id,
      clock: () => now,
      newUuid: () =>
          '00000000-0000-4000-8000-${(id * 1000 + ++next).toString().padLeft(12, '0')}',
      markPrinted: (roundId) async {
        final key = 'qr_round_printed_set_device-$id';
        final set = {...?preferences.getStringList(key), roundId};
        await preferences.setStringList(key, set.toList()..sort());
      },
    );
    coordinator.printRound = (_, _) async {
      if (!printLocally) return false;
      printed++;
      return true;
    };
    await coordinator.hydrate();
  }

  DiningTableSession draft({
    String table = '5',
    int qty = 2,
    int generation = 0,
  }) {
    final at = now.add(Duration(seconds: generation));
    return DiningTableSession(
      tableId: table,
      floorId: '1',
      status: DiningTableStatus.occupied,
      occupiedAt: at,
      updatedAt: at,
      orderReference: 'LOCAL-$id-$table-$generation',
      draft: OrderSessionDraft(
        orderReference: 'LOCAL-$id-$table-$generation',
        orderType: OrderType.dineIn,
        selectedCategory: 'Drinks',
        customerReferenceNumber: '',
        diningFloorId: '1',
        diningFloorLabel: 'Main',
        diningTableId: table,
        diningTableName: 'Table $table',
        items: [
          CartItem(
            product: const Product(
              id: '10',
              name: 'Coffee',
              category: 'Drinks',
              price: 2,
            ),
            qty: qty,
          ),
        ],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      ),
    );
  }

  Future<DiningTableSession> table([String id = '5']) async =>
      (await store.loadDiningTableSessions()).singleWhere(
        (s) => s.tableId == id,
      );
  Future<void> settle() async {
    await coordinator.settled;
    if (coordinator.lastError case final Object error) throw error;
  }

  Future<void> open({
    String tableId = '5',
    int qty = 2,
    int generation = 0,
  }) async {
    final s = draft(table: tableId, qty: qty, generation: generation);
    await store.saveDiningTableSession(s);
    coordinator.onTableOccupied(s);
    await settle();
  }

  Future<void> round([String id = '5']) async {
    await coordinator.sendRound(await table(id));
  }

  Future<void> flush() async {
    transport.online = true;
    await outbox.flush();
    await settle();
  }

  Future<List<String>> sheet() async => (await store.readTableSyncVerdicts())
      .reversed
      .map((v) => v.outcome)
      .toList();
  Future<void> clear({DiningTableSession? source}) async {
    final s = source ?? await table();
    await store.clearDiningTable(s.tableId);
    coordinator.onTablesCleared({s.tableId}, s);
    await settle();
  }

  Future<void> pay(double amount) async {
    final s = await table();
    final paid = s.copyWith(status: DiningTableStatus.paid, paidAt: now);
    await store.saveDiningTableSession(paid);
    coordinator.onTablePaid(
      paid,
      OrderSnapshot.initial().copyWith(
        serverOrderUuid: s.serverOrderUuid!,
        orderType: 'dine_in',
        paymentMethod: 'Cash',
        total: amount,
        subtotal: amount,
        rawSubtotal: amount,
      ),
    );
    await settle();
  }

  List<Json> get received => server.transcript
      .where((entry) => entry['device'] == id && entry['events'] != null)
      .expand((entry) => (entry['events'] as List).cast<Json>())
      .toList();
  List<Json> get answers => server.transcript
      .where((entry) => entry['device'] == id && entry['results'] != null)
      .expand((entry) => (entry['results'] as List).cast<Json>())
      .toList();
  List<String> get outcomes => answers
      .map(
        (a) => a['status'] == 'failed'
            ? 'failed'
            : (a['result'] as Map)['outcome']?.toString() ?? 'processed',
      )
      .toList();
  Future<Json> state() async => {
    'device': id,
    'tables': [
      for (final s in await store.loadDiningTableSessions())
        {
          'table_id': s.tableId,
          'status': s.status.storageValue,
          'seating_key': s.seatingKey,
          'seating_state': s.seatingState,
          'server_order_uuid': s.serverOrderUuid,
          'temp_reference': s.tempReference,
          'local_qty': s.draft?.items.fold<int>(0, (sum, i) => sum + i.qty),
        },
    ],
    'rounds': [
      for (final r in await store.readLocalTableRounds())
        {
          'request': r.clientRequestId,
          'status': r.status,
          'server_round_id': r.serverRoundId,
          'printed_at': r.printedAt?.toIso8601String(),
        },
    ],
    'sheet': await sheet(),
    'pending': (await outbox.pendingRows()).length,
    'parked': (await outbox.stuckBatches()).length,
    'local_prints': printed,
    'printed_set':
        preferences.getStringList('qr_round_printed_set_device-$id') ??
        <String>[],
  };
}

Future<void> fixture(
  String name,
  FakeTableServer server,
  List<ReplayDevice> devices, {
  Json assertions = const {},
}) async {
  for (final d in devices) {
    for (final event in d.received) {
      expect(event['event_type'], isNot('order.create'));
      if ((event['event_type'] as String).startsWith('table.session.')) {
        expect((event['payload'] as Map).containsKey('gps'), false);
        expect(
          jsonEncode(event),
          isNot(matches(r'"(?:unit_price|price_baisas|discount_baisas)"')),
        );
      }
    }
  }
  final value = {
    'case': name,
    'server_pin': '3ea99241dee704da7ab953cd59928f5b6a43a12e',
    'clock_epoch': '2099-09-06T12:00:00.000Z',
    'replay_note': 'Isolated virtual clock. Shift all client/received timestamps together at replay; preserve offsets and queued_offline. Bind setup identities, seeded device/staff/product/table IDs and server-generated IDs from actual responses. Never change outcome expectations. Only print-result wall-clock timestamps are omitted; device outbox events are verbatim.',
    'script': server.transcript,
    'local': [for (final d in devices) await d.state()],
    'assertions': assertions,
  };
  final encoded = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  final file = File('test/fixtures/t6_outbox/$name.json');
  if (Platform.environment['QR003_RECORD_FIXTURES'] == '1') {
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded);
  } else {
    expect(
      file.existsSync(),
      true,
      reason: 'Generate explicitly; never adapt the fake to a fixture.',
    );
    expect(
      encoded,
      file.readAsStringSync(),
      reason: 'Recorded batches and final states must be deterministic.',
    );
  }
  stdout.writeln('T6_REPLAY $name ${jsonEncode(assertions)}');
}

class ReplayShadow implements TableShadowGateway {
  ReplayShadow(this.server);
  final FakeTableServer server;
  @override
  Future<List<Json>> fetchBoard() async =>
      server.seats.values.where(server.live).map(server.boardRow).toList();
  @override
  Future<TableShadowFeed> fetchFeed({
    required int after,
    int limit = 100,
  }) async {
    final pending = server.journal.where((e) => e.id > after).toList();
    return TableShadowFeed(
      events: pending.take(limit).toList(),
      latestId: server.journal.length,
      hasMore: pending.length > limit,
    );
  }
}

class ReplayPrinter implements QrKitchenRoundPrinter {
  final ids = <int>[];
  @override
  Future<bool> printRound(
    QrRoundEnvelope envelope, {
    required bool arabic,
  }) async {
    ids.add(envelope.round.id);
    return true;
  }
}

class NoRoundPolling implements QrRoundGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('B6 explicit-claim test must not poll QR endpoints.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ReplayDevice> device(FakeTableServer s, int id) async {
    final d = ReplayDevice(s, id);
    await d.init();
    return d;
  }

  test(
    'B6 01 two offline devices: one bill, loser merged pending review',
    () async {
      final s = FakeTableServer(),
          a = await device(s, 1),
          b = await device(s, 2);
      await a.open();
      await a.round();
      await b.open();
      await b.round();
      expect(identical(a.sqlite, b.sqlite), false);
      expect((await a.table()).seatingKey, isNot((await b.table()).seatingKey));
      expect(await a.outbox.pendingRows(), hasLength(2));
      expect(await b.outbox.pendingRows(), hasLength(2));
      await a.flush();
      await b.flush();
      expect(a.outcomes, ['opened', 'appended']);
      expect(b.outcomes, ['merged', 'merged']);
      expect(s.bills, hasLength(1));
      expect(s.rounds.values.map((r) => r['status']), [
        'accepted',
        'pending_confirmation',
      ]);
      expect((await b.table()).status, DiningTableStatus.occupied);
      expect(await b.sheet(), ['merged', 'merged']);
      expect(
        (await a.table()).serverOrderUuid,
        (await b.table()).serverOrderUuid,
      );
      await fixture(
        '01_two_offline',
        s,
        [a, b],
        assertions: {
          'outcomes': [a.outcomes, b.outcomes],
          'bills': 1,
        },
      );
    },
  );
  test('B6 02 offline open reaches a now-free table', () async {
    final s = FakeTableServer(), d = await device(s, 1);
    final old = s.seedCustomer(5);
    await d.open();
    s.retireSeed(old);
    await d.flush();
    expect(d.outcomes, ['opened']);
    expect(await d.sheet(), isEmpty);
    expect((await d.table()).seatingState, 'open');
    await fixture('02_now_free', s, [d], assertions: {'outcomes': d.outcomes});
  });
  test('B6 03 offline open reaches an occupied table', () async {
    final s = FakeTableServer(), d = await device(s, 1);
    s.seedCustomer(5);
    await d.open();
    await d.flush();
    expect(d.outcomes, ['merged']);
    expect((await d.table()).seatingState, 'merged');
    expect((await d.table()).status, DiningTableStatus.occupied);
    expect(await d.sheet(), ['merged']);
    await fixture('03_occupied', s, [d], assertions: {'outcomes': d.outcomes});
  });
  test('B6 04 close precedes its open; new occupancy gets a new key', () async {
    final s = FakeTableServer(), a = await device(s, 1), b = await device(s, 2);
    await a.open();
    final old = await a.table();
    // A recovered copy closes on another device before the original offline
    // outbox arrives. Both events come from real coordinator hooks; no durable
    // row is edited or reordered.
    await b.store.saveDiningTableSession(old);
    await b.coordinator.hydrate();
    await b.clear(source: old);
    await b.flush();
    await a.flush();
    expect(b.outcomes, ['tombstoned']);
    expect(a.outcomes, ['already_closed']);
    expect(await a.sheet(), ['already_closed']);
    expect((await a.table()).status, DiningTableStatus.occupied);
    await a.store.clearDiningTable('5');
    await a.open(generation: 1);
    expect((await a.table()).seatingKey, isNot(old.seatingKey));
    expect(a.outcomes, ['already_closed', 'opened']);
    await fixture(
      '04_close_before_open',
      s,
      [a, b],
      assertions: {
        'outcomes': [a.outcomes, b.outcomes],
      },
    );
  });
  test(
    'B6 05 stale merged alias close cannot clear the new generation',
    () async {
      final s = FakeTableServer(), d = await device(s, 1);
      const key = '00000000-0000-4000-8000-000000009005';
      s.seedDeadAlias(key, 5);
      final current = s.seedCustomer(5);
      final old = d.draft().copyWith(seatingKey: key, seatingState: 'opening');
      await d.store.saveDiningTableSession(old);
      await d.coordinator.hydrate();
      await d.clear(source: old);
      await d.flush();
      expect(d.outcomes, ['stale_generation']);
      expect(s.seats[current]!['status'], 'open');
      expect(await d.store.loadDiningTableSessions(), isEmpty);
      expect(await d.sheet(), isEmpty);
      await fixture(
        '05_stale_close',
        s,
        [d],
        assertions: {'outcomes': d.outcomes, 'current_status': 'open'},
      );
    },
  );
  test(
    'B6 06 occupied move leaves the cashier local table unchanged',
    () async {
      final s = FakeTableServer(), d = await device(s, 1);
      d.transport.online = true;
      await d.open();
      s.seedCustomer(7);
      d.transport.online = false;
      final old = await d.table();
      final moved = DiningTableSession.fromMap({...old.toMap(), 'tableId': '7'});
      await d.store.clearDiningTable('5');
      await d.store.saveDiningTableSession(moved);
      d.coordinator.onTableTransferred('5', moved);
      await d.settle();
      await d.flush();
      expect(d.outcomes.last, 'target_occupied');
      expect((await d.table('7')).status, DiningTableStatus.occupied);
      expect(s.seats[old.seatingKey]!['table_id'], 5);
      expect(await d.sheet(), ['target_occupied']);
      await fixture(
        '06_move_occupied',
        s,
        [d],
        assertions: {
          'outcomes': d.outcomes,
          'local_table': 7,
          'server_table': 5,
        },
      );
    },
  );
  for (final onlineOpen in [false, true]) {
    test(
      'B6 07${onlineOpen ? 'b' : 'a'} customer occupancy: ${onlineOpen ? 'attached' : 'merged'}',
      () async {
        final s = FakeTableServer(), d = await device(s, 1);
        await d.store.saveRemoteMeta(
          const RemoteSyncMeta(feedCursor: 0, lastNotifiedEventId: 0),
        );
        final notices = <TableActivityNotice>[];
        final shadow = TableShadowRepository(
          gateway: ReplayShadow(s),
          store: d.store,
          readScope: () => 'one',
          writeScope: (_) async {},
          clock: () => s.now,
        );
        shadow.configure(
          mode: 'live',
          scope: 'one',
          sessionEpoch: 'one',
          authenticated: true,
        );
        shadow.activityNotices.listen(notices.addAll);
        addTearDown(shadow.dispose);
        s.seedCustomer(5);
        d.transport.online = onlineOpen;
        await d.open();
        await d.round();
        await d.flush();
        await shadow.pollNow();
        await Future<void>.delayed(Duration.zero);
        expect(
          d.outcomes,
          onlineOpen ? ['attached', 'appended'] : ['merged', 'merged'],
        );
        expect(
          d.received.map((e) => (e['payload'] as Map)['queued_offline']),
          everyElement(!onlineOpen),
        );
        expect(s.bills, hasLength(1));
        expect(notices, hasLength(1));
        expect(notices.single.kind, TableActivityKind.pending);
        expect(notices.single.itemCount, 1);
        expect(shadow.activityBoard[5]?.pendingCount, onlineOpen ? 1 : 2);
        expect(
          await d.sheet(),
          onlineOpen ? ['attached'] : ['merged', 'merged'],
        );
        expect((await d.table()).status, DiningTableStatus.occupied);
        await fixture(
          onlineOpen ? '07b_attached' : '07a_merged',
          s,
          [d],
          assertions: {
            'outcomes': d.outcomes,
            'notices': 1,
            'bell': onlineOpen ? 1 : 2,
          },
        );
      },
    );
  }
  test(
    'B6 08 two real print controllers claim one round, one printer runs',
    () async {
      final s = FakeTableServer(),
          a = await device(s, 1),
          b = await device(s, 2);
      a.transport.online = true;
      b.transport.online = true;
      await a.open();
      await a.round();
      final printers = [ReplayPrinter(), ReplayPrinter()];
      final controllers = [
        for (final (i, d) in [a, b].indexed)
          QrRoundAutoPrintController(
            gateway: NoRoundPolling(),
            kitchenGateway: ApiKitchenPrintGateway(d.api),
            preferences: d.preferences,
            printer: printers[i],
            deviceKey: () => 'device-${d.id}',
            arabic: () => false,
            onNotice: (_) {},
            onPollingStatus: (_) {},
          ),
      ];
      addTearDown(() {
        for (final c in controllers) {
          c.stop();
        }
      });
      final accepted = s.envelope(s.rounds.keys.single);
      final printed = await Future.wait(
        controllers.map((c) => c.printConfirmedRound(accepted)),
      );
      expect(printed.where((v) => v), hasLength(1));
      expect(printers.expand((p) => p.ids), hasLength(1));
      expect(s.transcript.where((r) => r['http_status'] == 409), hasLength(1));
      expect(s.tickets.values.single['print_result'], 'printed');
      expect(await a.sheet(), isEmpty);
      expect(await b.sheet(), isEmpty);
      await fixture(
        '08_print_claim',
        s,
        [a, b],
        assertions: {'printers_run': 1, 'conflicts': 1},
      );
    },
  );
  test(
    'B6 09 merged offline pay mismatch is failed, parked, attention only',
    () async {
      final s = FakeTableServer(), d = await device(s, 1);
      s.seedCustomer(5, qty: 3, pending: false);
      await d.open();
      await d.round();
      await d.pay(4);
      expect(await d.outbox.pendingRows(), hasLength(3));
      await d.flush();
      for (var i = 0; i < 4; i++) {
        await d.outbox.flush();
      }
      final stuck = (await d.outbox.stuckBatches()).single;
      expect(stuck.serverRejections, 5);
      expect(stuck.lastError, contains('payment total mismatch'));
      final attention = await d.outbox.watchAttention().first;
      expect(attention.single.reason, OrderSyncAttentionReason.serverRejected);
      expect((await d.table()).status, DiningTableStatus.paid);
      expect(await d.sheet(), ['merged', 'merged']);
      expect(d.outcomes, [
        'merged',
        'merged',
        'failed',
        'failed',
        'failed',
        'failed',
        'failed',
      ]);
      expect(s.bills.values.single['status'], 'open');
      await fixture(
        '09_payment_attention',
        s,
        [d],
        assertions: {
          'outcomes': d.outcomes,
          'rejections': 5,
          'attention': 'serverRejected',
        },
      );
    },
  );
  test(
    'B6 10 offline cancellation precedes waste and uses frozen baisa',
    () async {
      final s = FakeTableServer(), d = await device(s, 1);
      final seed = s.seedCustomer(5, pending: false);
      s.seedAccounting(seed);
      d.transport.online = true;
      await d.open(qty: 3);
      d.transport.online = false;
      await d.coordinator.cancelLine(
        await d.table(),
        line: {'product_id': 10, 'addon_ids': <int>[], 'notes': null},
        qty: 1,
        prepared: true,
        authorizedBy: 'Manager',
        reason: 'Prepared cancellation',
      );
      expect(await d.outbox.pendingRows(), hasLength(2));
      await d.flush();
      expect(d.received.map((e) => e['event_type']), [
        'table.session.open',
        'table.session.cancel_line',
        'product.waste',
      ]);
      expect(d.outcomes, ['attached', 'cancelled', 'processed']);
      final round = s.rounds.values.single;
      expect(
        [round['subtotal'], round['tax'], round['total']],
        [4000, 180, 3778],
      );
      expect((round['lines'] as List<Json>).first['cancelled_qty'], 1);
      expect(
        (round['lines'] as List<Json>).first['cancelled_discount_baisas'],
        100,
      );
      expect(s.total(s.seats[seed]), 3778);
      expect(s.waste.single['lines'], [
        {'product_id': 10, 'qty': 1, 'reason': 'other'},
      ]);
      expect(
        (await d.store.readLocalLineCancellations()).single.cancelledQty,
        1,
      );
      expect(await d.sheet(), ['attached']);
      expect((await d.table()).status, DiningTableStatus.occupied);
      await fixture(
        '10_cancel_waste',
        s,
        [d],
        assertions: {
          'outcomes': d.outcomes,
          'round': [4000, 180, 3778],
          'cancelled_qty': 1,
        },
      );
    },
  );
  test('B6 11 process dies after print/server commit before ACK, replay never prints twice', () async {
    final s = FakeTableServer(), d = await device(s, 1);
    d.transport.online = true;
    d.printLocally = true;
    await d.open();
    d.transport.loseAckForType = 'table.session.round';
    await d.round();
    expect(d.printed, 1);
    final pending = (await d.outbox.pendingRows()).single;
    final first = jsonDecode(pending.eventsJson) as List;
    expect((first.single['payload'] as Map)['printed_at'], isNotNull);
    await d.coordinator.dispose();
    await d.restartCoordinator();
    await d.flush();
    final delivered = d.received
        .where((e) => e['event_type'] == 'table.session.round')
        .toList();
    expect(delivered, hasLength(2));
    expect(delivered[0], delivered[1]);
    expect(d.printed, 1);
    expect(s.rounds, hasLength(1));
    expect(await d.outbox.pendingRows(), isEmpty);
    expect((await d.store.readLocalTableRounds()).single.status, 'appended');
    expect(d.preferences.getStringList('qr_round_printed_set_device-1'), ['1']);
    expect(await d.sheet(), isEmpty);
    await fixture(
      '11_print_ack_crash',
      s,
      [d],
      assertions: {
        'outcomes': d.outcomes,
        'local_prints': 1,
        'server_rounds': 1,
        'identical_replay': true,
      },
    );
  });
}
