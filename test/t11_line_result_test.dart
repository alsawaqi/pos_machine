import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'unified_dine_in_test.dart' show tableFixture;
import 'real_io_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final ar in [false, true]) {
    for (final result in ['reserved', 'ingredient', 'unprepared']) {
      testWidgets(
        'T11 real HTTP controller SQLite line $result ${ar ? 'AR' : 'EN'}',
        (t) async {
          late Database db;
          late SqliteDineInStore store;
          late DineInController c;
          final remote = tableFixture();
          remote['bill']['items'][0]['product_id'] = 8;
          final wire = <Map<String, dynamic>>[];
          final dio = Dio(
            BaseOptions(baseUrl: 'http://t11-line.invalid/api/v1'),
          );
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (o, h) async {
                if (o.path.endsWith('/detail')) {
                  h.resolve(
                    Response(
                      requestOptions: o,
                      statusCode: 200,
                      data: {'data': remote},
                    ),
                  );
                  return;
                }
                expectSync(o.path, endsWith('/cancel-line'));
                final p = Map<String, dynamic>.from(o.data as Map);
                wire.add(p);
                expectSync(
                  (await store.forTable(2).load())?.id,
                  p['client_request_id'],
                );
                if (result == 'reserved') {
                  h.reject(
                    DioException(
                      requestOptions: o,
                      type: DioExceptionType.badResponse,
                      response: Response(
                        requestOptions: o,
                        statusCode: 409,
                        data: {
                          'errors': [
                            {
                              'code': 'bill_reserved',
                              'message': 'Synthetic guard',
                            },
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
                        'outcome': 'cancelled',
                        'table_session_uuid': remote['seating']['uuid'],
                        'order_uuid': 'bill-1',
                        'seating_key': p['seating_key'],
                        'table_id': p['table_id'],
                        'cancelled_qty': 1,
                        'grand_total_baisas': 0,
                        'waste': {
                          'booked': result == 'ingredient',
                          'cost_baisas': 321,
                          'ingredients': [],
                        },
                      },
                    },
                  ),
                );
              },
            ),
          );
          await t.runAsync(() async {
            databaseFactory = databaseFactoryFfiNoIsolate;
            final dir = await Directory.systemTemp.createTemp('t11-line-');
            db = await databaseFactory.openDatabase('${dir.path}/requests.db');
            await SqliteDineInStore.createSchema(db);
            store = SqliteDineInStore(db, 'test-scope');
            c = DineInController(
              ApiDineInGateway(
                PosApiService(tokenGetter: () => 'synthetic', dio: dio),
                () => 'test-scope',
              ),
              store,
              2,
              staffId: 7,
              recordCancellationWaste: (_, qty) async {
                expect(qty, 1);
              },
            );
          });
          try {
            await t.pumpWidget(
              MaterialApp(
                home: DineInScreen(
                  createController: () async => c,
                  catalogue: () => [],
                  label: 'T2',
                  arabic: ar,
                  onPay: (_) async => fail('Cancellation cannot pay'),
                ),
              ),
            );
            await pumpUntilRealCondition(
              t,
              () => c.canAdd,
              timeout: const Duration(seconds: 20),
              reason: 'real line screen ready',
            );
            // The already-approved, unpriced user choice enters the real existing
            // cancellation controller. The manager widget is covered by the whole-bill test.
            await t.runAsync(
              () => c.cancelLine(
                Map<String, dynamic>.from(remote['bill']['items'][0] as Map),
                1,
                approve: () async => {
                  'prepared': result == 'ingredient',
                  'reason': 'Synthetic',
                },
              ),
            );
            await t.pump();
            expect(wire, hasLength(1));
            expect(await t.runAsync(() => store.forTable(2).load()), isNull);
            if (result == 'reserved') {
              expect(
                find.text(
                  ar
                      ? 'تحقق من نتيجة الدفع وأعد فتح الفاتورة قبل الإلغاء.'
                      : 'Resolve the payment result and reopen the bill before cancelling.',
                ),
                findsWidgets,
              );
              expect(c.pending, isNull);
            }
            if (result == 'ingredient') {
              expect(
                find.text(
                  ar
                      ? 'تم تسجيل الهدر: 0.321 ر.ع.'
                      : 'Waste recorded: OMR 0.321',
                ),
                findsWidgets,
              );
            }
            if (result == 'unprepared') {
              expect(find.textContaining('Waste recorded:'), findsNothing);
            }
            expect(jsonEncode(wire.single), isNot(contains('price')));
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await t.pump();
            await t.runAsync(db.close);
          }
        },
      );
    }
  }
}
