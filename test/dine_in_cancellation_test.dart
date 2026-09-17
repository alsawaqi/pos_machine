import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory;

class CancellationGateway extends TableFake {
  bool lost = false;
  final replies = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> append(DineInRequest request) async {
    requests.add(request);
    expect(journal!.request!.id, request.id);
    final result = replies.putIfAbsent(
      request.id,
      () => {
        'outcome': 'cancelled',
        'table_session_uuid': request.seatingUuid,
        'seating_key': request.payload['seating_key'],
        'table_id': request.payload['table_id'],
        'order_uuid': request.billUuid,
        'cancelled_qty': request.cancellation['qty'],
        'grand_total_baisas': 0,
      },
    );
    if (lost) throw StateError('Reply lost after commit');
    return result;
  }
}

void main() {
  late CancellationGateway api;
  late TableMemory store;
  late DineInController controller;
  late Map<String, dynamic> row;
  setUp(() async {
    api = CancellationGateway();
    store = TableMemory();
    api.journal = store;
    row = Map<String, dynamic>.from(
      (api.value['bill'] as Map)['items'][0] as Map,
    )..['product_id'] = 8;
    (api.value['bill'] as Map)['items'] = [row];
    controller = DineInController(api, store, 2);
    await controller.start();
  });
  tearDown(() => controller.dispose());

  test(
    'a stale selector cannot cancel a different item with the same price',
    () async {
      final stale = {...row, 'notes': 'different options'};
      expect(
        await controller.cancelLine(
          stale,
          1,
          approve: () async => {'prepared': false, 'reason': 'mistake'},
        ),
        isFalse,
      );
      expect(api.requests, isEmpty);
      expect(controller.notice, 'changed');
    },
  );

  test(
    'merged sent quantities above 99 follow the normal cancellation contract',
    () async {
      row['qty'] = 120;
      await controller.refresh();
      expect(
        await controller.cancelLine(
          row,
          120,
          approve: () async => {'prepared': false, 'reason': 'mistake'},
        ),
        isTrue,
      );
      expect(api.requests.single.cancellation['qty'], 120);
      expect(store.request, isNull);
    },
  );

  test(
    'manager refusal sends no cancellation and preserves the bill',
    () async {
      expect(
        await controller.cancelLine(row, 1, approve: () async => null),
        isFalse,
      );
      expect(api.requests, isEmpty);
      expect(store.request, isNull);
      expect(controller.detail!.bill!['grand_total_baisas'], 4750);
    },
  );

  test(
    'bill changed during manager approval cannot cancel a newer bill',
    () async {
      expect(
        await controller.cancelLine(
          row,
          1,
          approve: () async {
            (api.value['bill'] as Map)['grand_total_baisas'] = 5000;
            return {'prepared': false, 'reason': 'mistake'};
          },
        ),
        isFalse,
      );
      expect(api.requests, isEmpty);
      expect(controller.notice, 'changed');
    },
  );

  test(
    'lost cancellation response keeps immutable intent across reopening and retry',
    () async {
      api.lost = true;
      expect(
        await controller.cancelLine(
          row,
          1,
          approve: () async => {'prepared': false, 'reason': 'mistake'},
        ),
        isFalse,
      );
      final saved = store.request!;
      expect(controller.canPay, isFalse);
      expect(saved.cancellationPayload.keys, isNot(contains('waste_event_id')));
      expect(saved.cancellationPayload.keys, isNot(contains('cancellation')));
      expect(
        saved.cancellationPayload.keys,
        isNot(contains('line_total_baisas')),
      );
      final reloaded = DineInRequest(
        tableId: saved.tableId,
        seatingUuid: saved.seatingUuid,
        billUuid: saved.billUuid,
        payload: saved.payload,
      );
      store.request = reloaded;
      controller.dispose();
      controller = DineInController(api, store, 2);
      await controller.start();
      api.lost = false;
      expect(await controller.retry(), isTrue);
      expect(api.requests.map((r) => r.encoded).toSet(), {saved.encoded});
      expect(api.replies, hasLength(1));
      expect(store.request, isNull);
    },
  );

  test(
    'prepared cancellation records waste only after confirmed reply with stable identity',
    () async {
      final wasteIds = <String>{};
      var failWasteOnce = true;
      controller.dispose();
      controller = DineInController(
        api,
        store,
        2,
        recordCancellationWaste: (request, count) async {
          expect(count, 1);
          wasteIds.add(request.cancellation['waste_event_id'] as String);
          if (failWasteOnce) {
            failWasteOnce = false;
            throw StateError('After durable enqueue');
          }
        },
      );
      await controller.start();
      expect(
        await controller.cancelLine(
          row,
          1,
          approve: () async => {
            'prepared': true,
            'reason': 'customer cancelled',
          },
        ),
        isFalse,
      );
      expect(store.request, isNotNull);
      expect(await controller.retry(), isTrue);
      expect(wasteIds, hasLength(1));
      expect(api.replies, hasLength(1));
      expect(store.request, isNull);
    },
  );
}
