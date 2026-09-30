import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/tenancy/business_identity.dart';

import 'launch_p0_fix2_release_upgrade_test.dart' show ReleaseAckApi;
import 'support/fix2_release_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(BusinessBoundary.resetForTest);

  test(
    'F11 delayed enrichment cannot use storage replaced by activation',
    () async {
      final dir = await loadFix2ReleaseStorage();
      final db = AppDatabase.forTesting(
        NativeDatabase(File('${dir.path}/pos_machine_cache.sqlite')),
      );
      final sync = OrderSyncRepository(ReleaseAckApi()..offline = true, db);
      final snapshots =
          jsonDecode(
                File(
                  'test/fixtures/release_01d17de/snapshots.json',
                ).readAsStringSync(),
              )
              as List;
      final wire =
          jsonDecode(
                File(
                  'test/fixtures/release_01d17de/payloads.json',
                ).readAsStringSync(),
              )
              as List;
      final snapshot = OrderSnapshot.fromMap(
        Map<String, dynamic>.from(snapshots.first),
      ).copyWith(serverOrderUuid: wire.first['payload']['order']['uuid']);
      final customer = Completer<int?>();
      await sync.enqueue(
        snapshot,
        staffId: 7,
        lat: wire.first['payload']['order']['gps']['lat'],
        lng: wire.first['payload']['order']['gps']['lng'],
        resolveCustomer: () => customer.future,
      );
      expect(await db.getOutbox(snapshot.serverOrderUuid), isNotNull);
      final identity = BusinessBoundary.current!;
      await BusinessBoundary.accept(
        BusinessIdentity(
          identity.companyId,
          identity.branchId,
          'identity-from-server',
        ),
      );
      await sync.dispose();
      await db.close();
      customer.complete(7);
      await sync.settled;
      expect(BusinessBoundary.quarantinedCount, 0);
      final reopened = AppDatabase.forTesting(
        NativeDatabase(File('${dir.path}/pos_machine_cache.sqlite')),
      );
      expect(await reopened.getOutbox(snapshot.serverOrderUuid), isNotNull);
      await reopened.close();
    },
  );
}
