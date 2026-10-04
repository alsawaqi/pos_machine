import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/services/shift_service.dart';

/// LAUNCH-P5 C5 — shift close: the paid sales of the shift must all have
/// reached the server; the close names its closer and its orders; its event
/// id is fixed per shift; `unsynced_sales` is understood.
class _Api implements PosApiService {
  final pushed = <List<Map<String, dynamic>>>[];
  Map<String, dynamic> Function(Map<String, dynamic> event)? ack;

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    pushed.add(events);
    return {
      'results': [for (final e in events) ack!(e)],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  group('the close event', () {
    test(
      'has the fixed id: UUID v5 (URL namespace) of shift-close:{uuid}:{reopen_count}',
      () {
        // Computed independently (Node crypto, RFC 4122 §4.3).
        expect(
          shiftCloseEventId('s-1'),
          '10264d97-d2df-570e-a996-bd8b15ba55d7',
        );
        expect(
          shiftCloseEventId('s-1', reopenCount: 2),
          '0c73299b-12b5-554a-a4ad-0e6d6901a1f5',
        );
        expect(
          buildShiftCloseEvent(
            shiftUuid: 's-1',
            closingCashBaisas: 1,
            reopenCount: 2,
          )['client_event_id'],
          '0c73299b-12b5-554a-a4ad-0e6d6901a1f5',
        );
        final a = buildShiftCloseEvent(shiftUuid: 's-1', closingCashBaisas: 1);
        final b = buildShiftCloseEvent(
          shiftUuid: 's-1',
          closingCashBaisas: 2,
          now: DateTime.utc(2030),
        );
        final c = buildShiftCloseEvent(shiftUuid: 's-2', closingCashBaisas: 1);
        expect(a['client_event_id'], b['client_event_id']);
        expect(a['client_event_id'], isNot(c['client_event_id']));
        expect(a['client_event_id'], shiftCloseEventId('s-1'));
        // A valid version-5 UUID.
        expect(
          a['client_event_id'],
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      },
    );

    test('names the closer, the orders and the close_other block', () {
      final e = buildShiftCloseEvent(
        shiftUuid: 's-1',
        closingCashBaisas: 5000,
        closedByStaffId: 9,
        orderUuids: const ['o-1', 'o-2'],
        authorization: const {
          'action': 'shift.close_other',
          'mode': 'position',
        },
      );
      expect(e['payload'], containsPair('closed_by_staff_id', 9));
      expect(e['payload'], containsPair('order_uuids', ['o-1', 'o-2']));
      expect(e['payload']['authorization'], {
        'action': 'shift.close_other',
        'mode': 'position',
      });
      expect(e['payload']['auth_v'], 1);
    });
  });

  group('unsynced_sales', () {
    test('is read wherever the server puts it', () {
      expect(
        ShiftService.unsyncedSales({
          'error': 'unsynced_sales',
          'missing': ['o-1'],
        }),
        ['o-1'],
      );
      expect(
        ShiftService.unsyncedSales({
          'refusal_code': 'unsynced_sales',
          'details': {
            'missing': ['o-2'],
          },
        }),
        ['o-2'],
      );
      expect(
        ShiftService.unsyncedSales({
          'unsynced_sales': {
            'missing': ['o-3'],
          },
        }),
        ['o-3'],
      );
      expect(ShiftService.unsyncedSales({'error': 'shift not found'}), isNull);
    });

    test(
      'a refused close raises a retryable error; a duplicate returns the Z',
      () async {
        final api = _Api();
        final service = ShiftService(api);
        final event = buildShiftCloseEvent(
          shiftUuid: 's-1',
          closingCashBaisas: 5000,
          orderUuids: const ['o-1'],
        );
        api.ack = (e) => {
          'client_event_id': e['client_event_id'],
          'status': 'failed',
          'result': {
            'error': 'unsynced_sales',
            'missing': ['o-1'],
          },
        };
        await expectLater(
          service.close(
            shiftUuid: 's-1',
            closingCashBaisas: 5000,
            event: event,
          ),
          throwsA(
            isA<ShiftUnsyncedSalesException>().having(
              (e) => e.missing,
              'missing',
              ['o-1'],
            ),
          ),
        );
        api.ack = (e) => {
          'client_event_id': e['client_event_id'],
          'status': 'processed',
          'duplicate': true,
          'result': {'expected_cash_baisas': 5100, 'variance_baisas': -100},
        };
        final z = await service.close(
          shiftUuid: 's-1',
          closingCashBaisas: 5000,
          event: event,
        );
        expect(z.expectedCashBaisas, 5100);
        // The retry is the same event, byte for byte.
        expect(jsonEncode(api.pushed[1].single), jsonEncode(event));
      },
    );
  });

  group('the paid sales of a shift on this device', () {
    late AppDatabase db;
    late OrderSyncRepository repo;
    final opened = DateTime.utc(2026, 10, 4, 6);

    Future<void> row(
      String key,
      List<Map<String, dynamic>> events,
      DateTime at, {
      bool synced = false,
      int rejections = 0,
    }) async {
      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: key,
          eventsJson: jsonEncode(events),
          createdAt: at,
        ),
      );
      if (synced) await db.markOutboxSynced(key, at);
      if (rejections > 0) {
        await (db.update(db.orderOutbox)..where((t) => t.orderUuid.equals(key)))
            .write(OrderOutboxCompanion(serverRejections: Value(rejections)));
      }
    }

    Map<String, dynamic> pay(String uuid) => {
      'client_event_id': 'pay-$uuid',
      'event_type': 'order.pay',
      'client_timestamp': '2026-10-04T07:00:00Z',
      'payload': {'order_uuid': uuid},
    };

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = OrderSyncRepository(_Api(), db);
    });
    tearDown(() => db.close());

    test('lists every paid order and blocks on the unsent ones', () async {
      await row('old', [
        pay('o-old'),
      ], opened.subtract(const Duration(hours: 3)));
      await row(
        'a',
        [pay('o-a')],
        opened.add(const Duration(minutes: 5)),
        synced: true,
      );
      await row('b', [pay('o-b')], opened.add(const Duration(minutes: 9)));
      await row(
        'stuck',
        [pay('o-stuck')],
        opened.add(const Duration(minutes: 11)),
        rejections: OrderSyncRepository.maxServerRejections,
      );
      await row('void', [
        {
          'client_event_id': 'v',
          'event_type': 'order.void',
          'client_timestamp': '2026-10-04T07:00:00Z',
          'payload': {'order_uuid': 'o-a'},
        },
      ], opened.add(const Duration(minutes: 20)));
      final sales = await repo.paidSalesSince(opened);
      expect(sales.orderUuids, ['o-a', 'o-b', 'o-stuck']);
      // A parked (repeatedly refused) sale does not block; the server marks
      // the shift for review.
      expect(sales.unsent.map((r) => r.orderUuid), ['b']);
    });
  });
}
