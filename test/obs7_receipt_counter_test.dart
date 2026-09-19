import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

void main() {
  sqfliteFfiInit();
  test(
    'OBS7 confirmed and provisional server receipts never advance the local counter',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE order_history (order_number INTEGER, snapshot_json TEXT)',
      );
      final storage = LocalOrderStorageService.forTesting(db);
      expect(await storage.fetchNextOrderNumber(), 1450);
      await db.insert('order_history', {
        'order_number': 1500,
        'snapshot_json': jsonEncode({'orderNumber': 1500}),
      });
      for (final confirmed in [false, true]) {
        await db.insert('order_history', {
          'order_number': 99000,
          'snapshot_json': jsonEncode({
            'orderNumber': 99000,
            'serverReceipt': true,
            'serverReceiptConfirmed': confirmed,
          }),
        });
      }
      expect(await storage.fetchNextOrderNumber(), 1501);
      expect(await db.query('order_history'), hasLength(3));
      // Unreadable legacy records must not reset or reuse local numbers.
      await db.insert('order_history', {
        'order_number': 1600,
        'snapshot_json': 'unreadable legacy',
      });
      expect(await storage.fetchNextOrderNumber(), 1601);
    },
  );
}
