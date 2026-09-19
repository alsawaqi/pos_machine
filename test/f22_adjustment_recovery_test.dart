import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 't65_adjustment_journal_test.dart' show AdjustmentServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final scenario in [
    'lost closed',
    '422',
    '404',
    'unknown',
    'conflict',
    'other table',
    'discard',
  ]) {
    test('F22 real till gateway SQLite recovery $scenario', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(db.close);
      await SqliteDineInStore.createSchema(db);
      final store = SqliteDineInStore(db, 'f22');
      var closed = false, lost = false;
      final requests = <Map<String, dynamic>>[];
      final replies = <String, Map<String, dynamic>>{};
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (o.path.endsWith('/detail')) {
              final d = AdjustmentServer().detail();
              final id = o.path.contains('/2/') ? 2 : 1;
              d['table']['id'] = id;
              d['bill']['table_id'] = id;
              d['bill']['uuid'] = 'bill-$id';
              d['seating']['table_id'] = id;
              d['seating']['uuid'] = 'seat-$id';
              if (closed && id == 1) {
                d['bill'] = null;
                d['seating'] = null;
                d['occupied'] = false;
                d['rounds'] = [];
              }
              h.resolve(
                Response(requestOptions: o, statusCode: 200, data: {'data': d}),
              );
              return;
            }
            expectSync(o.path, endsWith('/adjust'));
            final p = Map<String, dynamic>.from(o.data as Map);
            requests.add(jsonDecode(jsonEncode(p)));
            final saved = (await db.query(
              'dine_in_requests',
            )).singleWhere((r) => r['request_id'] == p['client_request_id']);
            expectSync(jsonDecode(saved['payload'] as String), p);
            final id = p['table_id'];
            final a = p['adjustment'] as Map;
            replies.putIfAbsent(
              p['client_request_id'],
              () => {
                'outcome': 'adjusted',
                'table_session_uuid': 'seat-$id',
                'order_uuid': 'bill-$id',
                'table_id': id,
                'seating_key': p['seating_key'],
                'client_request_id': p['client_request_id'],
                'kind': a['kind'],
                'mode': a['mode'],
                'grand_total_baisas': 4900,
              },
            );
            if ((scenario == 'lost closed' && !lost) ||
                scenario == 'discard' ||
                (scenario == 'other table' && id == 1)) {
              lost = true;
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            if (['422', '404', 'unknown', 'conflict'].contains(scenario)) {
              final status = scenario == '404'
                  ? 404
                  : scenario == 'conflict'
                  ? 409
                  : 422;
              final code = scenario == 'unknown'
                  ? 'new_policy_refusal'
                  : scenario == 'conflict'
                  ? 'adjust_request_conflict'
                  : scenario == '404'
                  ? 'not_found'
                  : 'validation_failed';
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: o,
                    statusCode: status,
                    data: {
                      'errors': [
                        {'code': code, 'message': 'External refusal'},
                      ],
                    },
                  ),
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
                    ...replies[p['client_request_id']]!,
                    'outcome': closed ? 'replayed' : 'adjusted',
                  },
                },
              ),
            );
          },
        ),
      );
      final api = PosApiService(tokenGetter: () => 'synthetic', dio: dio);
      DineInController make(int id) => DineInController(
        ApiDineInGateway(api, () => 'f22'),
        store,
        id,
        staffId: 7,
      );
      var c = make(1);
      addTearDown(() => c.dispose());
      await c.start();
      Future<bool> apply(DineInController x) => x.adjust(
        (_) async => {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 100,
          'label': 'Test',
        },
      );
      final ok = await apply(c);
      if (scenario == 'lost closed') {
        expect(ok, false);
        final original = c.pending!.encoded;
        closed = true;
        c.dispose();
        c = make(1);
        await c.start();
        expect(await c.retry(), true);
        expect(c.pending, isNull);
        expect(requests, hasLength(2));
        expect(jsonEncode(requests.last), original);
        expect(replies, hasLength(1));
      } else if (scenario == 'other table') {
        expect(ok, false);
        final original = c.pending!.encoded;
        final second = make(2);
        addTearDown(second.dispose);
        await second.start();
        expect(
          second.canPay,
          true,
          reason:
              'A saved adjustment on table 1 must not block table 2 payment',
        );
        expect(await (store as dynamic).blocksBill('bill-2'), false);
        expect(await (store as dynamic).blocksBill('bill-1'), true);
        expect(await apply(second), true);
        expect(second.pending, isNull);
        expect((await store.load())!.encoded, original);
      } else if (scenario == 'discard') {
        expect(ok, false);
        final original = c.pending!.encoded;
        expect(
          await (c as dynamic).discardPendingAdjustment(() async => false),
          false,
        );
        expect((await store.load())!.encoded, original);
        expect(
          await (c as dynamic).discardPendingAdjustment(() async => true),
          true,
        );
        expect(c.pending, isNull);
        expect(await store.load(), isNull);
        final archive = (await db.query('dine_in_drafts')).single;
        final audit = jsonDecode(archive['payload'] as String);
        expect(audit['action'], 'adjustment_discarded');
        expect(audit['request']['payload'], jsonDecode(original));
        expect(audit['requesting_staff_id'], 7);
        expect(audit['payment_result'], isNull);
      } else {
        expect(ok, false);
        expect(
          c.pending,
          isNull,
          reason: 'Final business refusals cannot remain pending',
        );
        expect(await store.load(), isNull);
        expect(
          c.notice,
          contains(
            scenario == 'unknown'
                ? 'new_policy_refusal'
                : scenario == 'conflict'
                ? 'adjust_request_conflict'
                : scenario == '404'
                ? 'not_found'
                : 'validation_failed',
          ),
        );
      }
    });
  }
}
