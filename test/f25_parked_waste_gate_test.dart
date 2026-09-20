import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  for (final kind in [
    'waste',
    'payment',
    'mixed',
    'corrupt',
    'retryable-waste',
  ]) {
    test('F25 real outbox admission preserves $kind safety', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final repository = OrderSyncRepository(
        PosApiService(tokenGetter: () => 'fixture', dio: Dio()),
        db,
      );
      addTearDown(() async {
        await repository.dispose();
        await db.close();
      });
      final waste = {
        'client_event_id': 'waste-id',
        'event_type': 'product.waste',
        'payload': {'lines': []},
      };
      final pay = {
        'client_event_id': 'pay-id',
        'event_type': 'order.pay',
        'payload': {'order_uuid': 'bill'},
      };
      await db.enqueueOutbox(
        OrderOutboxCompanion(
          orderUuid: const Value('tbl:seat:fixture'),
          orderNumber: const Value(0),
          createdAt: Value(DateTime.now()),
          eventsJson: Value(
            kind == 'corrupt'
                ? 'invalid'
                : jsonEncode(
                    kind == 'mixed'
                        ? [waste, pay]
                        : [kind == 'payment' ? pay : waste],
                  ),
          ),
          serverRejections: Value(
            kind == 'retryable-waste'
                ? 1
                : OrderSyncRepository.maxServerRejections,
          ),
        ),
      );
      final before = await repository.pendingRows();
      var admitted = false;
      if (kind == 'waste') {
        await repository.assertIdleForCombine();
        await repository.admitDraftRecovery(() async {
          admitted = true;
        });
        expect(admitted, true);
      } else {
        await expectLater(repository.assertIdleForCombine(), throwsStateError);
        await expectLater(
          repository.admitDraftRecovery(() async {
            admitted = true;
          }),
          throwsStateError,
        );
        expect(admitted, false);
      }
      expect(await repository.pendingRows(), before);
    });
  }
}
