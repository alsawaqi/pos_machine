import 'dart:convert';
import 'package:drift/native.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_receipt.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'f12_real_ack_retirement_test.dart' show realLocalDatabase, AckServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final path in ['snapshot-null', 'outbox-ack']) {
    test(
      'OBS12 $path confirmed receipt replaces persisted Pending status',
      () async {
        final db = await realLocalDatabase();
        addTearDown(db.close);
        final history = ServerReceiptHistory(
          LocalOrderStorageService.forTesting(db),
        );
        final pending = CheckoutAttempt(
          id: 'status-attempt',
          orderUuid: 'qr-bill',
          state: 'pending',
          createdAt: DateTime.utc(2026, 9, 19),
          captures: [],
        );
        await history.record(
          OrderSnapshot.initial().copyWith(
            serverOrderUuid: 'qr-bill',
            serverReceipt: true,
            serverReceiptConfirmed: false,
            paymentStatus: 'Pending',
          ),
        );
        final original = (await db.query('order_history')).single;
        // New projection service, no in-memory checkout snapshot after restart.
        if (path == 'snapshot-null') {
          await projectMachineCheckoutReceipt(
            ServerReceiptHistory(LocalOrderStorageService.forTesting(db)),
            null,
            pending.copy(state: 'paid', receiptNumber: 'TEST-121'),
          );
        } else {
          final outboxDb = AppDatabase.forTesting(NativeDatabase.memory());
          final server = AckServer();
          final outbox = OrderSyncRepository(
            PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
            outboxDb,
          );
          addTearDown(() async {
            await outbox.dispose();
            await outboxDb.close();
          });
          outbox.addAckListener(history.acknowledge);
          await outbox.enqueueEvent('qr-bill', {
            'client_event_id': 'obs12-ack',
            'event_type': 'order.pay',
            'payload': {'order_uuid': 'qr-bill'},
          });
          expect((await outbox.rowForKey('qr-bill'))!.syncedAt, isNotNull);
          expect(server.events, hasLength(1));
        }
        final rows = await db.query('order_history');
        expect(rows, hasLength(1));
        expect(rows.single['id'], original['id']);
        final record =
            jsonDecode(rows.single['snapshot_json'] as String) as Map;
        expect(
          record['receiptNumber'],
          path == 'snapshot-null' ? 'TEST-121' : 'TEST-FIX7-120',
        );
        expect(record['serverReceiptConfirmed'], true);
        expect(record['paymentStatus'], 'Paid');
      },
    );
  }
}
