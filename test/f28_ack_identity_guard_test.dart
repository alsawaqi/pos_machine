import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_controller.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_gateway.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_receipt.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 't65_real_screen_payment_test.dart' show realLocalDatabase;

import 'f27_saved_gps_recovery_test.dart' show oldPending;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'F28 unrelated ACK never validates another order against active claim; matching malformed identity remains pending',
    () async {
      databaseFactory = databaseFactoryFfi;
      final db = await realLocalDatabase();
      await SqliteCheckoutStore.createSchema(db);
      final store = SqliteCheckoutStore(db, 'scope');
      final pending = oldPending();
      await store.create(pending);
      final history = ServerReceiptHistory(
        LocalOrderStorageService.forTesting(db),
      );
      final api = PosApiService(tokenGetter: () => 'fixture', dio: Dio());
      final checkout = QrCheckoutController(
        gateway: ApiCheckoutGateway(
          api: api,
          currentScope: () => 'scope',
          location: () async => null,
          legacyGuard: (_) async {},
        ),
        store: store,
        captureCard: (_) async => throw StateError('No bank'),
        captureBank: (_) async => throw StateError('No bank'),
        authorizeGift: () async => false,
        projectReceipt: (s, a) => projectMachineCheckoutReceipt(history, s, a),
      );
      addTearDown(() async {
        checkout.dispose();
        await db.close();
      });
      final unrelated = {
        'client_event_id': 'unrelated',
        'event_type': 'order.pay',
        'payload': {
          'order_uuid': 'other',
          'gps': {'lat': 'invalid'},
          'payments': [],
        },
      };
      await checkout.acceptTablePayAck(unrelated, {
        'client_event_id': 'unrelated',
        'status': 'processed',
        'result': {'status': 'paid', 'order_id': 88, 'receipt_number': 'OTHER'},
      });
      expect((await store.active())!.id, pending.id);
      expect(await db.query('order_history'), isEmpty);
      for (final extra in [
        {'unrecognized': true},
        {
          'gps': {'lat': 'invalid', 'lng': 58},
        },
      ]) {
        final wire =
            jsonDecode(jsonEncode(pending.event)) as Map<String, dynamic>;
        (wire['payload'] as Map).addAll(extra);
        await expectLater(
          checkout.acceptTablePayAck(wire, {
            'client_event_id': pending.id,
            'status': 'processed',
            'result': {
              'status': 'paid',
              'order_id': 12,
              'receipt_number': 'INVALID',
            },
          }),
          throwsFormatException,
        );
        expect((await store.active())!.state, 'pending');
        expect(await db.query('order_history'), isEmpty);
      }
      final differentAmount =
          jsonDecode(jsonEncode(pending.event)) as Map<String, dynamic>;
      ((differentAmount['payload'] as Map)['payments'] as List)
              .single['amount_baisas'] =
          1;
      await expectLater(
        checkout.acceptTablePayAck(differentAmount, {
          'client_event_id': pending.id,
          'status': 'processed',
          'result': {
            'status': 'paid',
            'order_id': 12,
            'receipt_number': 'INVALID',
          },
        }),
        throwsFormatException,
      );
      expect((await store.active())!.state, 'pending');
    },
  );
}
