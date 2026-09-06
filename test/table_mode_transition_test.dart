import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

import 'send_to_kitchen_test.dart' show B3Harness, b3Product;

DiningTableSession atTable(DiningTableSession source, String id) =>
    DiningTableSession.fromMap({...source.toMap(), 'tableId': id});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final online in [true, false]) {
    test('flip into Live bursts each occupied cart; online=$online', () async {
      final h = B3Harness()..mode = 'shadow';
      await h.init();
      final original = h.memory.tables['5']!;
      h.memory.tables['7'] = atTable(original, '7').copyWith(
        orderReference: 'LOCAL-7',
        draft: original.draft!.copyWith(
          orderReference: 'LOCAL-7',
          diningTableId: '7',
          items: [CartItem(product: b3Product, qty: 3)],
        ),
      );
      h.memory.tables['8'] = atTable(original, '8').copyWith(
        status: DiningTableStatus.paid,
      );
      h.memory.tables['9'] = atTable(original, '9').copyWith(
        status: DiningTableStatus.available,
      );
      // An already-shared occupancy is not re-opened by the burst.
      h.memory.tables['10'] = atTable(original, '10').copyWith(
        seatingKey: 'existing-seating',
      );
      expect(await h.outbox.pendingRows(), isEmpty);
      h.online = online;
      h.mode = 'live';
      final transition = TableModeTransition(h.bridge);
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
    final transition = TableModeTransition(h.bridge);
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
      await TableModeTransition(h.bridge).enterLive();
      await h.outbox.flush();
      expect(h.memory.rounds.values.single.lines.single['qty'], 4);
      expect(h.memory.tables['5']!.status, DiningTableStatus.occupied);
    },
  );
}
