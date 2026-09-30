import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'package:pos_machine/tenancy/device_heartbeat.dart';
import 'package:pos_machine/tenancy/tenant_sqlite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'B12c pending inventory includes table events, checkout attempts and a tender; unreadable is unknown',
    () async {
      BusinessBoundary.resetForTest();
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final previous = await getDatabasesPath();
      final dir = await Directory.systemTemp.createTemp('fix1-inventory-');
      await databaseFactory.setDatabasesPath(dir.path);
      SharedPreferences.setMockInitialValues({
        BusinessBoundary.identityKey: const BusinessIdentity(1, 2, 'd').encoded,
      });
      await BusinessBoundary.initialize(await SharedPreferences.getInstance());
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '2',
        buildSignature: 'test',
      );
      final db = await openBusinessDatabase(
        dir.path + '/qr_checkout_attempts.db',
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE qr_checkout_attempts(id TEXT PRIMARY KEY,state TEXT)',
          );
          await db.execute(
            'CREATE TABLE local_table_events(event_id TEXT PRIMARY KEY,event_json TEXT,ack_json TEXT)',
          );
        },
      );
      try {
        await db.insert('qr_checkout_attempts', {
          'id': 'a',
          'state': 'pending',
        });
        await db.insert('qr_checkout_attempts', {
          'id': 'b',
          'state': 'capturing',
        });
        await db.insert('qr_checkout_attempts', {'id': 'c', 'state': 'paid'});
        await db.insert('local_table_events', {
          'event_id': 'event',
          'event_json': '{"event_type":"table.session.open"}',
        });
        expect(await pendingSqliteBusinessWork(), 3);
        DeviceHeartbeat.pendingCount = pendingSqliteBusinessWork;
        final tender = Completer<void>();
        final flight = DeviceHeartbeat.trackTender(() => tender.future);
        expect((await DeviceHeartbeat.metadata())['pending_outbox_count'], 4);
        tender.complete();
        await flight;
        expect((await DeviceHeartbeat.metadata())['pending_outbox_count'], 3);
        await File(
          dir.path + '/dine_in_requests.db',
        ).writeAsString('corrupt store');
        expect(
          (await DeviceHeartbeat.metadata()).containsKey(
            'pending_outbox_count',
          ),
          false,
        );
      } finally {
        DeviceHeartbeat.pendingCount = null;
        await db.close();
        await databaseFactory.setDatabasesPath(previous);
        await dir.delete(recursive: true);
        BusinessBoundary.resetForTest();
      }
    },
  );
}
