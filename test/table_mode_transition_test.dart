import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/data/table_replay_configuration.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

import 'send_to_kitchen_test.dart' show B3Harness, b3Product;

DiningTableSession atTable(DiningTableSession source, String id) =>
    DiningTableSession.fromMap({...source.toMap(), 'tableId': id});

TableModeTransition transitionFor(B3Harness h) => TableModeTransition(
  h.bridge,
  loadConfiguration: () async => TableReplayConfiguration(
    scope: 'mock-company/branch/device',
    tableIds: {
      for (final table in h.controller.diningTableDefinitions) table.id,
    },
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'clear during the admission read never replays the captured draft',
    () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      var reads = 0;
      h.mode = 'live';
      await TableModeTransition(
        h.bridge,
        loadConfiguration: () async {
          if (++reads == 2) h.memory.tables.remove('5');
          return const TableReplayConfiguration(
            scope: 'scope',
            tableIds: {'5'},
          );
        },
      ).enterLive();
      expect(h.events, isEmpty);
      expect(await h.outbox.pendingRows(), isEmpty);
      expect(h.memory.tables, isEmpty);
      expect(h.memory.rounds, isEmpty);
      expect(h.tickets, isEmpty);
    },
  );

  for (final change in ['missing-config', 'scope-change', 'removed-table']) {
    test('replay admission $change preserves unverified draft', () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      final before = jsonEncode(h.memory.tables['5']!.toMap());
      var reads = 0;
      h.mode = 'live';
      final skipped = await TableModeTransition(
        h.bridge,
        loadConfiguration: () async {
          reads++;
          if (change == 'missing-config') return null;
          return TableReplayConfiguration(
            scope: change == 'scope-change' && reads > 1
                ? 'new-branch'
                : 'original',
            tableIds: change == 'removed-table' && reads > 1 ? {} : {'5'},
          );
        },
      ).enterLive();
      expect(skipped, {'5'});
      expect(h.events, isEmpty);
      expect(await h.outbox.pendingRows(), isEmpty);
      expect(h.memory.rounds, isEmpty);
      expect(h.tickets, isEmpty);
      expect(jsonEncode(h.memory.tables['5']!.toMap()), before);
    });
  }

  test('scope changed after open does not submit or print a round', () async {
    final h = B3Harness()..mode = 'shadow';
    await h.init();
    var reads = 0;
    h.mode = 'live';
    final skipped = await TableModeTransition(
      h.bridge,
      loadConfiguration: () async {
        reads++;
        return TableReplayConfiguration(
          scope: reads > 2 ? 'changed' : 'original',
          tableIds: {'5'},
        );
      },
    ).enterLive();
    expect(skipped, {'5'});
    expect(h.events.map((event) => event['event_type']), [
      'table.session.open',
    ]);
    expect(h.memory.rounds, isEmpty);
    expect(h.tickets, isEmpty);
    expect(h.memory.tables['5']!.status, DiningTableStatus.occupied);
  });

  test(
    'Live transition preserves an obsolete table without replay or print',
    () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      final obsolete = atTable(
        h.memory.tables['5']!,
        '1',
      ).copyWith(orderReference: 'OLD-1', occupiedAt: DateTime(2026, 9, 4));
      h.memory.tables['1'] = obsolete;
      final before = jsonEncode(obsolete.toMap());
      h.mode = 'live';
      final skipped = await transitionFor(h).enterLive();
      expect(skipped, {'1'});
      await h.outbox.flush();
      expect(h.events.map((event) => (event['payload'] as Map)['table_id']), [
        5,
        5,
      ]);
      expect(jsonEncode(h.memory.tables['1']!.toMap()), before);
      expect(
        h.memory.rounds.values.every((round) => round.tableId == '5'),
        true,
      );
      expect(h.tickets, hasLength(1));
      expect(await h.outbox.pendingRows(), isEmpty);
    },
  );

  test(
    'Live transition without a configured table list preserves every draft',
    () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      final before = jsonEncode(h.memory.tables['5']!.toMap());
      h.controller.diningTableDefinitions = [];
      h.mode = 'live';
      final skipped = await transitionFor(h).enterLive();
      expect(skipped, {'5'});
      expect(h.events, isEmpty);
      expect(await h.outbox.pendingRows(), isEmpty);
      expect(h.memory.rounds, isEmpty);
      expect(h.tickets, isEmpty);
      expect(jsonEncode(h.memory.tables['5']!.toMap()), before);
    },
  );

  for (final online in [true, false]) {
    test('flip into Live bursts each occupied cart; online=$online', () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      final original = h.memory.tables['5']!;
      // Both replayable carts belong to the mock branch's configured floor.
      // The old fixture supplied only a local session for 7, no catalogue row.
      h.controller.diningTableDefinitions = [
        ...h.controller.diningTableDefinitions,
        const DiningTableDefinition(
          id: '7',
          floorId: '1',
          name: 'Table 7',
          sizeLabel: 'square',
          seats: 4,
          sortOrder: 2,
        ),
      ];
      h.memory.tables['7'] = atTable(original, '7').copyWith(
        orderReference: 'LOCAL-7',
        draft: original.draft!.copyWith(
          orderReference: 'LOCAL-7',
          diningTableId: '7',
          items: [CartItem(product: b3Product, qty: 3)],
        ),
      );
      h.memory.tables['8'] = atTable(
        original,
        '8',
      ).copyWith(status: DiningTableStatus.paid);
      h.memory.tables['9'] = atTable(
        original,
        '9',
      ).copyWith(status: DiningTableStatus.available);
      // An already-shared occupancy is not re-opened by the burst.
      h.memory.tables['10'] = atTable(
        original,
        '10',
      ).copyWith(seatingKey: 'existing-seating');
      expect(await h.outbox.pendingRows(), isEmpty);
      h.online = online;
      h.mode = 'live';
      final transition = transitionFor(h);
      await Future.wait([transition.enterLive(), transition.enterLive()]);
      await h.outbox.flush();
      final events = online
          ? h.events
          : [
              for (final row in await h.outbox.pendingRows())
                ...((jsonDecode(row.eventsJson) as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                )),
            ];
      expect(events.map((e) => e['event_type']), [
        'table.session.open',
        'table.session.round',
        'table.session.open',
        'table.session.round',
      ]);
      for (final id in [5, 7]) {
        final table = events.where(
          (e) => (e['payload'] as Map)['table_id'] == id,
        );
        expect(table, hasLength(2));
        final round = table.last['payload'] as Map;
        expect((round['lines'] as List).single['qty'], id == 5 ? 2 : 3);
        expect(h.memory.tables['$id']!.seatingKey, isNotEmpty);
      }
      for (final event in events) {
        expect((event['payload'] as Map)['queued_offline'], !online);
        expect(event['event_type'], isNot('order.create'));
        expect((event['payload'] as Map).containsKey('gps'), false);
      }
      expect(h.memory.tables['8']!.status, DiningTableStatus.paid);
      expect(h.memory.tables['9']!.status, DiningTableStatus.available);
      expect(h.memory.tables['10']!.seatingKey, 'existing-seating');
      expect(h.memory.rounds.length, 2);
    });
  }

  test('out of Live stops hooks but pending rows flush and IDs stay', () async {
    final h = B3Harness()..mode = 'shadow';
    await h.init();
    h.mode = 'live';
    h.online = false;
    final transition = transitionFor(h);
    await transition.enterLive();
    expect(await h.outbox.pendingRows(), hasLength(2));
    final identity = h.memory.tables['5']!;
    final keys = (await h.outbox.pendingRows())
        .map((r) => r.orderUuid)
        .toList();
    h.mode = 'off';
    final modified = identity.copyWith(
      draft: identity.draft!.copyWith(
        items: [CartItem(product: b3Product, qty: 4)],
      ),
    );
    h.bridge.onTableOccupied(modified);
    h.bridge.onTableDraftPersisted(modified);
    h.bridge.onTableTransferred('5', atTable(modified, '7'));
    h.bridge.onTablesJoined(modified, atTable(modified, '8'));
    h.bridge.onTablesCleared({'5'}, modified);
    h.bridge.onTableLeft('5');
    await h.bridge.send(modified);
    await transition.enterLive();
    await h.coordinator.settled;
    expect((await h.outbox.pendingRows()).map((r) => r.orderUuid), keys);
    h.online = true;
    await h.outbox.flush();
    expect(await h.outbox.pendingRows(), isEmpty);
    expect(h.events.map((e) => e['event_type']), [
      'table.session.open',
      'table.session.round',
    ]);
    final after = h.memory.tables['5']!;
    expect(after.seatingKey, identity.seatingKey);
    expect(after.serverOrderUuid, identity.serverOrderUuid);
    expect(after.status, identity.status);
    expect(h.memory.rounds.length, 1);
  });

  test(
    'transition uses active unsaved cart, not stale persisted quantity',
    () async {
      final h = B3Harness()..mode = 'off';
      await h.init();
      h.controller.cart.single.qty = 4;
      h.mode = 'live';
      await transitionFor(h).enterLive();
      await h.outbox.flush();
      expect(h.memory.rounds.values.single.lines.single['qty'], 4);
      expect(h.memory.tables['5']!.status, DiningTableStatus.occupied);
    },
  );
}
