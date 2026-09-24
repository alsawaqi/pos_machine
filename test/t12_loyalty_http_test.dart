import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'real_io_wait.dart';
import 'dart:io';
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
  final coded = <String, dynamic>{
    'errors': [
      {'code': 'bill_reserved', 'message': 'External answer'},
    ],
  };
  final cases = <(String, int?, Object?, bool)>[
    for (final status in [401, 403, 408, 419, 429, 500, 502])
      ('$status structured', status, coded, false),
    ('401 bare', 401, {'message': 'Unauthenticated.'}, false),
    ('401 HTML', 401, '<html>Login required</html>', false),
    ('404 HTML', 404, '<html>Not found</html>', false),
    (
      '404 code-less',
      404,
      {
        'errors': [
          {'message': 'No code'},
        ],
      },
      false,
    ),
    (
      '409 numeric code',
      409,
      {
        'errors': [
          {'code': 123},
        ],
      },
      false,
    ),
    (
      '422 empty code',
      422,
      {
        'errors': [
          {'code': ''},
        ],
      },
      false,
    ),
    (
      '404 whitespace code',
      404,
      {
        'errors': [
          {'code': '  '},
        ],
      },
      false,
    ),
    (
      '422 string error',
      422,
      {
        'errors': ['broken'],
      },
      false,
    ),
    ('409 empty envelope', 409, {}, false),
    ('network', null, null, false),
    (
      'malformed ACK',
      200,
      {
        'data': {'outcome': 'replayed'},
      },
      false,
    ),
    for (final status in [404, 409, 422])
      ('$status business refusal', status, coded, true),
    (
      '422 unknown refusal',
      422,
      {
        'errors': [
          {'code': 'future_policy'},
        ],
      },
      true,
    ),
  ];
  for (final (name, status, body, finalRefusal) in cases) {
    test('T12 real HTTP and file SQLite: $name', () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        '${(await Directory.systemTemp.createTemp('t12-http-')).path}/journal.sqlite',
      );
      addTearDown(db.close);
      await SqliteDineInStore.createSchema(db);
      final store = SqliteDineInStore(db, 'f23');
      final requests = <String>[];
      final routes = <String>[];
      var unauthorized = 0;
      String? persisted;
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (o.path.endsWith('/detail')) {
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {'data': AdjustmentServer().detail()},
                ),
              );
              return;
            }
            expect(o.path, endsWith('/adjust'));
            routes.add(o.path);
            requests.add(jsonEncode(o.data));
            final row = (await db.query('dine_in_requests')).single;
            persisted ??= row['payload'] as String;
            expect(row['payload'], persisted);
            expect(requests.last, persisted);
            if (requests.length == 1 ||
                (requests.length == 2 && status == null)) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
              return;
            }
            if (requests.length == 2) {
              final response = Response<dynamic>(
                requestOptions: o,
                statusCode: status,
                data: body,
              );
              if (status == 200) {
                h.resolve(response);
              } else {
                h.reject(
                  DioException(
                    requestOptions: o,
                    type: DioExceptionType.badResponse,
                    response: response,
                  ),
                );
              }
              return;
            }
            final p = o.data as Map;
            final a = p['adjustment'] as Map;
            h.resolve(
              Response(
                requestOptions: o,
                statusCode: 200,
                data: {
                  'data': {
                    'outcome': 'replayed',
                    'table_session_uuid': row['seating_uuid'],
                    'order_uuid': row['bill_uuid'],
                    'table_id': p['table_id'],
                    'seating_key': p['seating_key'],
                    'client_request_id': p['client_request_id'],
                    'kind': a['kind'],
                    'mode': a['mode'],
                    'grand_total_baisas': 4900,
                  },
                },
              ),
            );
          },
        ),
      );
      final api = PosApiService(
        tokenGetter: () => 'synthetic',
        dio: dio,
        onUnauthorized: () {
          unauthorized++;
        },
      );
      final c = DineInController(
        ApiDineInGateway(api, () => 'f23'),
        store,
        1,
        staffId: 7,
      );
      addTearDown(c.dispose);
      await c.start();
      expect(
        await c.adjust(
          (_) async => {
            'kind': 'loyalty',
            'mode': 'redeem',
            'rule_id': 11,
            'blocks': 2,
            'authorized_by': 'Verified Approver',
            'approved_by_staff_id': 19,
          },
        ),
        false,
      );
      expect(c.pending, isNotNull);
      expect(await c.retry(), false);
      expect(requests, hasLength(2));
      expect(requests[1], requests[0]);
      expect(routes[1], routes[0]);
      if (finalRefusal) {
        expect(c.pending, isNull);
        expect(await store.load(), isNull);
        expect(c.notice, startsWith('adjust_refused:'));
      } else {
        expect(
          c.pending,
          isNotNull,
          reason: '$name is not a final business refusal',
        );
        expect(c.pending!.encoded, persisted);
        expect((await store.load())!.encoded, persisted);
        expect(c.notice, 'uncertain');
        expect(await c.retry(), true);
        expect(requests, hasLength(3));
        expect(requests[2], persisted);
        expect(routes[2], routes[0]);
        expect(c.pending, isNull);
        expect(await store.load(), isNull);
      }
      expect(unauthorized, name == '401 bare' || name == '401 HTML' ? 1 : 0);
    });
  }
  for (final ar in [false, true]) {
    for (final code in [
      'loyalty_no_customer',
      'loyalty_insufficient',
      'loyalty_customer_limit',
      'loyalty_staff_limit',
      'loyalty_rule_unsupported',
      'approval_required',
      'adjustment_exceeds_bill',
      'bill_reserved',
      'validation_failed',
    ]) {
      testWidgets('T12 real table screen refusal $code ${ar ? 'AR' : 'EN'}', (
        t,
      ) async {
        final db = (await t.runAsync(
          () async => databaseFactoryFfiNoIsolate.openDatabase(
            '${(await Directory.systemTemp.createTemp('t12-visible-')).path}/journal.sqlite',
          ),
        ))!;
        await t.runAsync(() => SqliteDineInStore.createSchema(db));
        final store = SqliteDineInStore(db, 'visible');
        final dio = Dio();
        var requests = 0;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) async {
              if (o.path.endsWith('/detail')) {
                h.resolve(
                  Response(
                    requestOptions: o,
                    statusCode: 200,
                    data: {
                      'data':
                          (AdjustmentServer()
                                ..customer = {'id': 5, 'name': 'Customer'})
                              .detail(),
                    },
                  ),
                );
              } else {
                requests++;
                expectSync((await store.load())!.encoded, jsonEncode(o.data));
                h.reject(
                  DioException(
                    requestOptions: o,
                    type: DioExceptionType.badResponse,
                    response: Response(
                      requestOptions: o,
                      statusCode: 409,
                      data: {
                        'errors': [
                          {'code': code},
                        ],
                      },
                    ),
                  ),
                );
              }
            },
          ),
        );
        final c = DineInController(
          ApiDineInGateway(
            PosApiService(tokenGetter: () => 'fixture', dio: dio),
            () => 'visible',
          ),
          store,
          1,
          staffId: 7,
        );
        await t.pumpWidget(
          MaterialApp(
            home: DineInScreen(
              createController: () async => c,
              catalogue: () => [],
              label: 'Test table',
              onPay: (_) async {},
              arabic: ar,
              pickAdjustment: (_, kind) async => {
                'kind': kind,
                'mode': 'redeem',
                'rule_id': 11,
                'blocks': 2,
                'authorized_by': 'Verified Approver',
                'approved_by_staff_id': 19,
              },
            ),
          ),
        );
        await pumpUntilRealCondition(
          t,
          () => c.available,
          reason: 'real table detail loaded',
          timeout: const Duration(seconds: 20),
        );
        final button = find.byKey(const ValueKey('dine-adjust-loyalty'));
        expect(button, findsOneWidget);
        await t.ensureVisible(button);
        await t.tap(button);
        await pumpUntilRealCondition(
          t,
          () =>
              c.notice == 'adjust_refused:$code' &&
              find
                  .text(dineInText(ar, 'adjust_refused:$code'))
                  .evaluate()
                  .isNotEmpty,
          reason: 'structured refusal rendered',
          timeout: const Duration(seconds: 20),
        );
        expect(c.pending, isNull);
        expect(requests, 1);
        final text = dineInText(ar, 'adjust_refused:$code');
        expect(text, isNot(contains(code)));
        expect(find.text(text), findsOneWidget);
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(db.close);
      });
    }
  }
}
