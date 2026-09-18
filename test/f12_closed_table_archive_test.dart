import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'draft_recovery_test.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';

void main() {
  sqfliteFfiInit();
  test(
    'F12 reused table archives current copy and preserves older ledger',
    () async {
      final h = RecoveryHarness();
      await h.init(qty: 2);
      addTearDown(h.close);
      await h.db.execute(
        'ALTER TABLE local_line_cancellations ADD COLUMN seating_key TEXT',
      );
      final oldRound = {
        ...(await h.db.query('local_table_rounds')).single,
        'client_request_id': '66666666-6666-4666-8666-666666666666',
        'seating_key': '77777777-7777-4777-8777-777777777777',
        'order_uuid': '88888888-8888-4888-8888-888888888888',
      };
      await h.db.insert('local_table_rounds', oldRound);
      final oldCancellation = {
        'client_request_id': 'old-cancellation',
        'table_id': '1',
        'seating_key': oldRound['seating_key'],
        'cancelled_at': at.toIso8601String(),
      };
      await h.db.insert('local_line_cancellations', oldCancellation);
      final local = await loadRecoveryLocal(
        h.db,
        1,
        outboxRow: (key) async => h.outbox[key],
        currentGenerationOnly: true,
      );
      expect(local.rounds, hasLength(1));
      expect(
        await h.store.retireClosed(
          local,
          bill: {
            'uuid': billId,
            'table_id': 1,
            'order_type': 'dine_in',
            'status': 'paid',
          },
          table: {
            'table': {'id': 1},
            'occupied': false,
            'orphaned': false,
            'seating': null,
            'bill': null,
          },
        ),
        isTrue,
      );
      expect(await h.db.query('dining_tables'), isEmpty);
      expect(
        await h.db.query('local_table_rounds'),
        contains(equals(oldRound)),
      );
      expect(await h.db.query('local_line_cancellations'), [oldCancellation]);
      await RecoveryStore.assertNotRetired(
        h.db,
        uuid: oldRound['order_uuid'] as String,
        tableId: '1',
        seatingKey: oldRound['seating_key'] as String,
      );
    },
  );
  for (final variant in [
    'paid',
    'void',
    'unsent',
    'wrong bill',
    'occupied',
    'changed copy',
  ]) {
    test('F12 closed archive $variant', () async {
      final h = RecoveryHarness();
      await h.init(qty: variant == 'unsent' ? 3 : 2);
      addTearDown(h.close);
      final local = await h.local(1);
      final original = await h.db.query('dining_tables');
      final bill = {
        'uuid': variant == 'wrong bill' ? 'different' : billId,
        'table_id': 1,
        'order_type': 'dine_in',
        'status': variant == 'void' ? 'void' : 'paid',
      };
      final table = {
        'table': {'id': 1},
        'occupied': variant == 'occupied',
        'orphaned': false,
        'seating': null,
        'bill': null,
      };
      if (variant == 'changed copy') {
        await h.db.update('dining_tables', {'occupied_at': 'different'});
      }
      final result = h.store.retireClosed(local, bill: bill, table: table);
      if (variant == 'changed copy') {
        await expectLater(result, throwsStateError);
      } else if (variant == 'paid' || variant == 'void') {
        expect(await result, isTrue);
        expect(await h.db.query('dining_tables'), isEmpty);
        expect(await h.db.query('held_orders'), isEmpty);
        final archive = (await h.db.query(
          'draft_recovery_closed_archive',
        )).single;
        expect(jsonDecode(archive['local_json'] as String), local.json);
        await expectLater(
          RecoveryStore.assertNotRetired(h.db, uuid: billId),
          throwsStateError,
        );
        // Losing the auxiliary fence must not resurrect the archived original.
        await h.db.delete('draft_recovery_retired');
        await expectLater(
          RecoveryStore.assertNotRetired(h.db, uuid: billId),
          throwsStateError,
        );
      } else {
        expect(await result, isFalse);
        expect(await h.db.query('dining_tables'), original);
      }
      expect(await h.db.query('order_history'), isEmpty);
      expect(await h.db.query('local_table_rounds'), hasLength(1));
      expect(h.api.confirmations, isEmpty);
      expect(h.api.sent, isEmpty);
    });
  }
}
