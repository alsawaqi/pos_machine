import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/draft_recovery/recovery_controller.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'draft_recovery_test.dart' as fixture;

class StaffRecoveryFake extends fixture.RecoveryFake {
  StaffRecoveryFake(this.source);
  final String source;
  bool checkoutSupported = true;
  @override
  Future<DineInDetail> detail(int tableId) async {
    final data = (await super.detail(tableId)).json;
    (data['bill'] as Map).addAll(<String, Object>{
      'source': source,
      'order_type': 'dine_in',
      'table_id': 1,
      if (checkoutSupported) 'checkout_policy': 'staff_table_claim_v1',
    });
    return DineInDetail(data);
  }
}

void main() {
  sqfliteFfiInit();
  for (final source in ['main_pos', 'handheld']) {
    for (final kind in ['legacy', 'zero', 'delta']) {
      test(
        '$source/$kind retires exact copies only after ACK and sends only proven additions',
        () async {
          final h = fixture.RecoveryHarness();
          await h.init(qty: kind == 'delta' ? 3 : 2, legacy: kind == 'legacy');
          addTearDown(h.close);
          final api = StaffRecoveryFake(source)
            ..previewJson = fixture.previewValue(legacy: kind == 'legacy');
          (api.previewJson['proof'] as Map)['bill'].addAll({
            'source': source,
            'checkout_policy': 'staff_table_claim_v1',
          });
          h.controller.dispose();
          h.controller = RecoveryController(
            store: h.store,
            gateway: api,
            dineIn: api,
            tableId: 1,
            loadLocal: h.local,
            checkIdle: () async {},
            admit: (operation) => operation(),
            onRetired: (_) async {},
          );
          final raw = await h.local(1);
          final outbox = h.outbox.map(
            (key, row) => MapEntry(key, row.eventsJson),
          );
          await h.controller.start();
          expect(h.controller.error, null);
          expect(await h.db.query('held_orders'), hasLength(1));
          api.reply = (payload) async {
            expect((await h.store.active())!.payload, payload);
            expect(await h.db.query('held_orders'), hasLength(1));
            return api.ack(payload);
          };
          await h.controller.confirm();
          expect(h.controller.error, null);
          expect(h.controller.attempt!.local.encoded, raw.encoded);
          expect(await h.db.query('held_orders'), isEmpty);
          expect(await h.db.query('dining_tables'), isEmpty);
          expect(
            h.outbox.map((key, row) => MapEntry(key, row.eventsJson)),
            outbox,
          );
          expect(api.sent, isEmpty);
          await expectLater(
            RecoveryStore.assertNotRetired(h.db, uuid: fixture.billId),
            throwsStateError,
          );
          if (kind == 'delta') {
            expect(h.controller.attempt!.state, 'delta_ready');
            expect(
              h.controller.attempt!.delta.single['original'],
              fixture.originalItem(),
            );
            await h.controller.sendSavedAdditions();
            expect(h.controller.error, null);
            expect(api.sent, hasLength(1));
            expect(api.sent.single.billUuid, fixture.billId);
            expect(api.sent.single.seatingUuid, fixture.seatId);
            expect(api.sent.single.payload['lines'], [
              {
                'product_id': 7,
                'qty': 1,
                'addon_ids': [],
                'notes': 'Keep Exactly',
              },
            ]);
            final request = api.sent.single.encoded;
            await h.controller.sendSavedAdditions();
            expect(api.sent.map((r) => r.encoded).toList(), [request]);
          }
          expect(h.controller.attempt!.state, 'done');
          expect(h.controller.attempt!.local.encoded, raw.encoded);
          await RecoveryStore.assertNonePending(h.db);
        },
      );
    }
  }

  test(
    'staff-only recovery lost ACK retains exact intent across restart and then retires once',
    () async {
      final h = fixture.RecoveryHarness();
      await h.init(qty: 2);
      addTearDown(h.close);
      (h.api.previewJson['proof'] as Map)['bill'].addAll({
        'source': 'main_pos',
        'checkout_policy': 'staff_table_claim_v1',
      });
      h.api.reply = (_) async => throw StateError('lost reply');
      await h.controller.start();
      await h.controller.confirm();
      final first = jsonEncode(h.api.confirmations.single);
      expect(await h.db.query('held_orders'), hasLength(1));
      await expectLater(
        RecoveryStore.assertNonePending(h.db),
        throwsStateError,
      );
      h.controller.dispose();
      h.controller = h.create();
      await h.controller.start();
      h.api.reply = (payload) async => h.api.ack(payload);
      await h.controller.confirm();
      expect(h.api.confirmations.map(jsonEncode).toList(), [first, first]);
      expect(h.controller.attempt!.state, 'done');
      expect(await h.db.query('held_orders'), isEmpty);
      expect(h.outbox, hasLength(1));
    },
  );

  test(
    'staff-only unacknowledged legacy quantity never becomes a guessed addition',
    () async {
      final h = fixture.RecoveryHarness();
      await h.init(qty: 3, legacy: true);
      addTearDown(h.close);
      (h.api.previewJson['proof'] as Map)['bill'].addAll({
        'source': 'main_pos',
        'checkout_policy': 'staff_table_claim_v1',
      });
      final before = await h.db.query('held_orders');
      await h.controller.start();
      await h.controller.confirm();
      expect(h.controller.error, isNotNull);
      expect(h.api.confirmations, isEmpty);
      expect(h.api.sent, isEmpty);
      expect(await h.db.query('held_orders'), before);
    },
  );
}
