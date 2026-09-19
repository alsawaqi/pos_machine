import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';

const seat = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const bill = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

// Only HTTP is simulated. No controller, gateway, journal or SQLite fake.
class AdjustmentServer {
  int manual = 0, comp = 0;
  bool reserved = false, review = false, loseAck = false, badAck = false;
  int applies = 0;
  final requests = <Map<String, dynamic>>[];
  final replay = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? customer;
  late Database db;
  Map<String, dynamic> detail() => {
    'table': {'id': 1, 'label': 'T65 table'},
    'occupied': true,
    'orphaned': false,
    'seating': {
      'uuid': seat,
      'table_id': 1,
      'status': 'open',
      'joined_table_ids': [],
    },
    'bill': {
      'id': 1,
      'uuid': bill,
      'status': reserved ? 'awaiting_payment' : 'open',
      'source': 'qr_web',
      'order_type': 'dine_in',
      'table_id': 1,
      'charge': reserved ? 'claimed' : 'none',
      'subtotal_baisas': 5000,
      'discount_total_baisas': manual,
      'manual_discount_baisas': manual,
      'comp_total_baisas': comp,
      'tax_total_baisas': 0,
      'grand_total_baisas': 5000 - manual - comp,
      'customer': customer,
      'items': [
        {
          'id': 1,
          'product_id': 10,
          'product_name': 'Frozen coffee',
          'qty': 3,
          'unit_price_baisas': 1000,
          'line_discount_baisas': 0,
          'line_total_baisas': 3000,
          'status': 'open',
          'addons': [],
        },
      ],
    },
    'rounds': [
      {
        'id': 1,
        'round_no': 1,
        'entered_by': 'staff',
        'status': review ? 'pending_confirmation' : 'accepted',
        'priced_lines': [],
        'subtotal_baisas': 5000,
        'tax_baisas': 0,
        'total_baisas': 5000,
      },
    ],
  };
  Dio dio() => Dio()
    ..interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          if (o.path.endsWith('/detail')) {
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {'data': detail()},
              ),
            );
            return;
          }
          if (!o.path.endsWith('/adjust')) {
            throw StateError('Unexpected external request ${o.path}');
          }
          final p = Map<String, dynamic>.from(o.data as Map);
          requests.add(jsonDecode(jsonEncode(p)) as Map<String, dynamic>);
          final saved = (await db.query('dine_in_requests')).single;
          expect(saved['request_id'], p['client_request_id']);
          expect(
            jsonDecode(saved['payload'] as String),
            p,
            reason: 'Exact intent must precede HTTP',
          );
          final a = Map<String, dynamic>.from(p['adjustment'] as Map);
          final old = replay[p['client_request_id']];
          if (old == null) {
            applies++;
            switch (a['kind']) {
              case 'discount':
                manual = a['mode'] == 'clear'
                    ? 0
                    : a['mode'] == 'fixed'
                    ? a['amount_baisas'] as int
                    : 500;
              case 'comp':
                comp = a['mode'] == 'clear' ? 0 : 1000;
              case 'customer':
                customer = a['mode'] == 'detach'
                    ? null
                    : {
                        'id': a['customer_id'],
                        'name': 'Synthetic customer',
                        'phone': '90000000',
                      };
            }
          }
          final result =
              old ??
              <String, dynamic>{
                'outcome': 'adjusted',
                'table_session_uuid': seat,
                'winner_table_session_uuid': null,
                'order_uuid': bill,
                'table_id': 1,
                'seating_key': p['seating_key'],
                'client_request_id': p['client_request_id'],
                'kind': a['kind'],
                'mode': a['mode'],
                'grand_total_baisas': 5000 - manual - comp,
              };
          replay[p['client_request_id'] as String] = result;
          if (loseAck) {
            loseAck = false;
            h.reject(
              DioException(
                requestOptions: o,
                type: DioExceptionType.receiveTimeout,
              ),
            );
            return;
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'data': {
                  ...result,
                  if (old != null) 'outcome': 'replayed',
                  if (badAck) 'client_request_id': 'wrong',
                },
              },
            ),
          );
        },
      ),
    );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late AdjustmentServer server;
  late SqliteDineInStore journal;
  late DineInController controller;
  Future<bool> apply(Map<String, dynamic>? intent) =>
      (controller as dynamic).adjust((DineInDetail _) async => intent)
          as Future<bool>;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await SqliteDineInStore.createSchema(db);
    journal = SqliteDineInStore(db, 't65-scope');
    server = AdjustmentServer()..db = db;
    final api = PosApiService(
      tokenGetter: () => 'synthetic-token',
      dio: server.dio(),
    );
    controller = DineInController(
      ApiDineInGateway(api, () => 't65-scope'),
      journal,
      1,
      staffId: 7,
    );
    await controller.start();
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
  });
  test(
    'T65 real gateway and SQLite apply replace clear all adjustment slots without changing drafts or rounds',
    () async {
      final drafts = {
        'seating_uuid': seat,
        'bill_uuid': bill,
        'items': [
          {'product_id': 12, 'qty': 1},
        ],
      };
      await journal.saveDraft(1, drafts);
      final rounds = jsonEncode(controller.detail!.rounds);
      final intents = [
        {
          'kind': 'discount',
          'mode': 'percent',
          'percent_bp': 1000,
          'label': 'Ten',
        },
        {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 300,
          'label': 'Three hundred',
        },
        {
          'kind': 'discount',
          'mode': 'rule',
          'discount_id': 3,
          'authorized_by': 'Manager',
        },
        {'kind': 'discount', 'mode': 'clear'},
        {
          'kind': 'comp',
          'mode': 'apply',
          'comp_reason_id': 2,
          'target': {'order_item_id': 1, 'qty': 1},
          'authorized_by': 'Manager',
        },
        {
          'kind': 'comp',
          'mode': 'apply',
          'comp_reason_id': 4,
          'target': {'order_item_id': 1, 'qty': 2},
          'authorized_by': 'Manager',
        },
        {'kind': 'comp', 'mode': 'clear'},
        {'kind': 'customer', 'mode': 'attach', 'customer_id': 5},
        {'kind': 'customer', 'mode': 'attach', 'customer_id': 6},
        {'kind': 'customer', 'mode': 'detach'},
      ];
      for (final intent in intents) {
        expect(
          await apply(intent),
          true,
          reason: '$intent ${controller.notice}',
        );
        expect(await db.query('dine_in_requests'), isEmpty);
        expect(await journal.loadDraft(1), drafts);
        expect(jsonEncode(controller.detail!.rounds), rounds);
        expect(
          controller.detail!.bill!['grand_total_baisas'],
          5000 - server.manual - server.comp,
        );
      }
      expect(server.applies, 10);
      expect(server.manual, 0);
      expect(server.comp, 0);
      expect(server.customer, null);
    },
  );
  test(
    'T65 lost acknowledgement reloads real SQLite and retries identical identity only once',
    () async {
      server.loseAck = true;
      expect(
        await apply({
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 500,
          'label': 'Service',
        }),
        false,
      );
      expect(controller.notice, 'uncertain');
      final first = (await journal.load())!;
      controller.dispose();
      final api = PosApiService(
        tokenGetter: () => 'synthetic-token',
        dio: server.dio(),
      );
      controller = DineInController(
        ApiDineInGateway(api, () => 't65-scope'),
        journal,
        1,
      );
      await controller.start();
      expect(await controller.retry(), true);
      expect(server.requests, hasLength(2));
      expect(server.requests.first, server.requests.last);
      expect(first.id, server.requests.last['client_request_id']);
      expect(server.applies, 1);
      expect(server.manual, 500);
      expect(await journal.load(), null);
    },
  );
  test(
    'T65 denied picker and changed bill during approval never send or journal',
    () async {
      expect(await apply(null), false);
      expect(server.requests, isEmpty);
      expect(await journal.load(), null);
      final dynamic real = controller;
      expect(
        await real.adjust((DineInDetail _) async {
          server.manual = 1;
          return {
            'kind': 'discount',
            'mode': 'fixed',
            'amount_baisas': 500,
            'label': 'Service',
          };
        }),
        false,
      );
      expect(controller.notice, 'changed');
      expect(server.requests, isEmpty);
      expect(await journal.load(), null);
    },
  );
  test(
    'T65 malformed ACK retains the immutable intent and blocks another adjustment or payment',
    () async {
      server.badAck = true;
      expect(
        await apply({'kind': 'customer', 'mode': 'attach', 'customer_id': 5}),
        false,
      );
      final pending = (await journal.load())!;
      expect(controller.canPay, false);
      expect(await apply({'kind': 'customer', 'mode': 'detach'}), false);
      expect((await journal.load())!.encoded, pending.encoded);
      expect(server.requests, hasLength(1));
      server.badAck = false;
      expect(await controller.retry(), true);
      expect(server.applies, 1);
    },
  );
  test(
    'T65 reserved and review bills refuse adjustment before opening the picker',
    () async {
      for (final review in [false, true]) {
        server.reserved = !review;
        server.review = review;
        await controller.refresh();
        var called = false;
        final dynamic real = controller;
        expect(
          await real.adjust((DineInDetail _) async {
            called = true;
            return {'kind': 'customer', 'mode': 'detach'};
          }),
          false,
        );
        expect(called, false);
        expect(server.requests, isEmpty);
        expect(await journal.load(), null);
      }
    },
  );
  test(
    'T65 adjustment whitelist accepts intent and rejects hidden client prices',
    () {
      Map<String, dynamic> intent() => {
        'table_id': 1,
        'seating_key': seat,
        'client_request_id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
        'queued_offline': false,
        'adjustment': {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 100,
          'label': 'Service',
        },
      };
      expect(
        () => DineInRequest(
          tableId: 1,
          seatingUuid: seat,
          billUuid: bill,
          payload: intent(),
        ),
        returnsNormally,
      );
      for (final field in ['grand_total_baisas', 'price', 'order_uuid']) {
        final p = intent();
        (p['adjustment'] as Map)[field] = 1;
        expect(
          () => DineInRequest(
            tableId: 1,
            seatingUuid: seat,
            billUuid: bill,
            payload: p,
          ),
          throwsFormatException,
        );
      }
    },
  );
}
