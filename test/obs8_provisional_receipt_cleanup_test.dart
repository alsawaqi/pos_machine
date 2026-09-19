import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_receipt.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'draft_recovery_test.dart';
import 'qr_checkout_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final end in [
    'refused',
    'released',
    'managed',
    'confirmed-preserved',
    'restart-refused',
    'restart-released',
    'restart-managed',
    'restart-newer-pending',
  ]) {
    test('OBS8 provisional receipt cleanup: $end', () async {
      final h = RecoveryHarness();
      await h.init();
      addTearDown(h.close);
      await h.db.execute('DROP TABLE order_history');
      await h.db.execute(
        'CREATE TABLE order_history (id TEXT PRIMARY KEY, order_number INTEGER, order_type TEXT, created_at TEXT, snapshot_json TEXT)',
      );
      final history = ServerReceiptHistory(
        LocalOrderStorageService.forTesting(h.db),
      );
      final f = CheckoutFixture();
      final c = QrCheckoutController(
        gateway: f.api,
        store: f.store,
        now: () => f.now,
        newId: () => 'receipt-attempt',
        captureCard: (_) async => throw StateError('No bank'),
        captureBank: (_) async => throw StateError('No bank'),
        authorizeGift: () async => false,
        projectReceipt: (snapshot, attempt) =>
            projectMachineCheckoutReceipt(history, snapshot, attempt),
      );
      addTearDown(c.dispose);
      await c.open('qr-bill');
      f.api.loseAck = true;
      await c.pay([const CheckoutTender('cash', 4750)]);
      expect(c.phase, CheckoutPhase.pending);
      expect(await history.find('qr-bill'), isNotNull);
      final event = jsonEncode(f.store.value!.event);
      if (end == 'refused') {
        f.api.loseAck = false;
        f.api.ack = 'failed';
        await c.retryAcknowledgement();
        expect(f.store.value!.state, 'refused');
        expect(await history.find('qr-bill'), isNull);
        expect(await c.managerTakeover(() async => false), false);
        expect(f.store.value!.state, 'refused');
        expect(await c.managerTakeover(() async => true), true);
        expect(f.store.value!.state, 'managed');
      } else if (end.startsWith('restart-')) {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        await SqliteCheckoutStore.createSchema(db);
        final attempt = f.store.value!.copy(
          state: end == 'restart-newer-pending' ? 'managed' : end.substring(8),
        );
        await db.insert('qr_checkout_attempts', {
          'id': attempt.id,
          'scope': 'scope',
          'state': attempt.state,
          'payload': jsonEncode(attempt.json),
        });
        if (end == 'restart-newer-pending') {
          final active = CheckoutAttempt.decode(
            jsonEncode({
              ...f.store.value!.json,
              'id': 'newer-attempt',
              'event': {
                ...f.store.value!.event!,
                'client_event_id': 'newer-attempt',
              },
            }),
          );
          await db.insert('qr_checkout_attempts', {
            'id': active.id,
            'scope': 'scope',
            'state': active.state,
            'payload': jsonEncode(active.json),
          });
        }
        final rows = await db.query('qr_checkout_attempts');
        final reopened = QrCheckoutController(
          gateway: f.api,
          store: SqliteCheckoutStore(db, 'scope'),
          captureCard: (_) async => throw StateError('No bank'),
          captureBank: (_) async => throw StateError('No bank'),
          authorizeGift: () async => false,
          projectReceipt: (snapshot, attempt) =>
              projectMachineCheckoutReceipt(history, snapshot, attempt),
        );
        addTearDown(reopened.dispose);
        await reopened.open(null);
        if (end == 'restart-newer-pending') {
          expect(await history.find('qr-bill'), isNotNull);
        } else {
          expect(await history.find('qr-bill'), isNull);
        }
        expect(await db.query('qr_checkout_attempts'), rows);
      } else if (end == 'confirmed-preserved') {
        final confirmed = f.store.value!.copy(
          state: 'paid',
          receiptNumber: 'TEST-42',
        );
        await projectMachineCheckoutReceipt(history, c.snapshot, confirmed);
        final before = await history.find('qr-bill');
        await projectMachineCheckoutReceipt(
          history,
          null,
          confirmed.copy(state: 'refused'),
        );
        expect(await history.find('qr-bill'), isNotNull);
        expect(
          jsonEncode((await history.find('qr-bill'))!.toMap()),
          jsonEncode(before!.toMap()),
        );
      } else {
        await projectMachineCheckoutReceipt(
          history,
          null,
          f.store.value!.copy(state: end),
        );
        expect(await history.find('qr-bill'), isNull);
        await projectMachineCheckoutReceipt(
          history,
          null,
          f.store.value!.copy(state: end),
        );
        expect(await history.find('qr-bill'), isNull);
      }
      expect(jsonEncode(f.store.value!.event), event);
    });
  }
}
