import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';
import 'draft_recovery_test.dart';

void main() {
  sqfliteFfiInit();
  for (final kind in [
    'confirmed',
    'legacy',
    'pending',
    'wrong-identity',
    'unsent',
    'changed-during-archive',
  ]) {
    test('F12 real SQLite closed-copy safety: $kind', () async {
      final h = RecoveryHarness();
      await h.init(qty: kind == 'unsent' ? 3 : 2);
      addTearDown(h.close);
      await h.db.execute(
        'ALTER TABLE local_line_cancellations ADD COLUMN seating_key TEXT',
      );
      final receipt = <String, dynamic>{
        'serverOrderUuid': billId,
        if (kind != 'legacy') 'serverReceipt': true,
        'serverReceiptConfirmed': kind != 'pending',
      };
      if (kind == 'wrong-identity') {
        await h.db.update('dining_tables', {
          'server_order_uuid': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        });
      }
      await h.db.insert('order_history', {
        'snapshot_json': jsonEncode(receipt),
      });
      final originals = await h.db.query('dining_tables');
      final history = await h.db.query('order_history');
      Future<dynamic> read() => loadRecoveryLocal(
        h.db,
        1,
        outboxRow: (key) async => h.outbox[key],
        currentGenerationOnly: true,
      );
      if (['legacy', 'pending', 'wrong-identity'].contains(kind)) {
        await expectLater(read(), throwsStateError);
      } else {
        final local = await read();
        final bill = <String, dynamic>{
          'uuid': billId,
          'table_id': 1,
          'order_type': 'dine_in',
          'status': 'paid',
        };
        final table = <String, dynamic>{
          'table': {'id': 1},
          'occupied': false,
          'orphaned': false,
          'seating': null,
          'bill': null,
        };
        if (kind == 'changed-during-archive') {
          await h.db.insert('order_history', {
            'snapshot_json': jsonEncode({'serverOrderUuid': billId}),
          });
          await expectLater(
            h.store.retireClosed(local, bill: bill, table: table),
            throwsStateError,
          );
        } else {
          expect(
            await h.store.retireClosed(local, bill: bill, table: table),
            kind != 'unsent',
          );
          if (kind == 'confirmed') {
            expect(await h.db.query('dining_tables'), isEmpty);
            expect(
              await h.db.query('draft_recovery_closed_archive'),
              hasLength(1),
            );
            expect(await h.db.query('order_history'), history);
            expect(h.outbox, hasLength(1));
            return;
          }
        }
      }
      expect(await h.db.query('dining_tables'), originals);
      expect(await h.db.query('draft_recovery_closed_archive'), isEmpty);
    });
  }
}
