import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/qr_quick/qr_quick_controller.dart';
import 'package:pos_machine/qr_quick/qr_quick_gateway.dart';
import 'package:pos_machine/qr_quick/qr_quick_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'real_io_wait.dart';

class CancelHttp implements HttpClientAdapter {
  final orders = <Map<String, dynamic>>[
    for (final (id, session, tail) in [
      ('one', 'expired', '1234'),
      ('two', 'closed', '5678'),
      ('live', 'live', '9012'),
    ])
      {
        'uuid': id,
        'source': 'qr_web',
        'order_type': 'quick',
        'table_id': null,
        'status': 'held',
        'charge': 'none',
        'session': session,
        'temp_reference': 'T-0918-$id',
        'grand_total_baisas': id == 'one' ? 1000 : 2000,
        'items': <dynamic>[],
        'phone_tail': tail,
        'actions': {'settle': true, 'to_counter': false},
      },
  ];
  final requests = <RequestOptions>[];
  List<Map<String, dynamic>> review = [];
  final completed = <String, Map<String, dynamic>>{};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    dynamic data;
    String? code;
    var status = 200;
    if (options.path.endsWith('/cancel-preview')) {
      final uuid = options.queryParameters['order_uuid'];
      review = orders
          .where(
            (o) =>
                o['session'] != 'live' && (uuid == null || o['uuid'] == uuid),
          )
          .toList();
      data = {
        'orders': review
            .map(
              (o) => {
                'uuid': o['uuid'],
                'reference': o['temp_reference'],
                'total_baisas': o['grand_total_baisas'],
                'prepared': o['uuid'] == 'one',
                'items': [
                  {'name': 'Synthetic tea', 'qty': 1},
                ],
              },
            )
            .toList(),
        'count': review.length,
        'total_baisas': review.fold<int>(
          0,
          (s, o) => s + (o['grand_total_baisas'] as int),
        ),
        'preview_token': 'synthetic-review',
      };
    } else if (options.path.endsWith('/cancel')) {
      final input = options.data as Map;
      if (input['pin'] != '4321') {
        code = 'invalid_pin';
        status = 401;
      } else {
        final id = input['client_request_id'] as String;
        data = completed[id];
        if (data == null) {
          data = {
            'count': review.length,
            'orders': review
                .map((o) => {'order_uuid': o['uuid'], 'status': 'void'})
                .toList(),
            'replayed': false,
          };
          completed[id] = data as Map<String, dynamic>;
          final ids = review.map((o) => o['uuid']).toSet();
          orders.removeWhere((o) => ids.contains(o['uuid']));
        } else {
          data = {...data as Map, 'replayed': true};
        }
      }
    } else if (options.path == '/device/qr/pending-orders') {
      data = {'orders': orders};
    } else {
      throw StateError('Unexpected HTTP ${options.path}');
    }
    return ResponseBody.fromString(
      jsonEncode({
        'data': data,
        'errors': code == null
            ? []
            : [
                {'code': code, 'message': 'Synthetic refusal'},
              ],
      }),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final arabic in [false, true]) {
    testWidgets(
      'Q1 real QR list search cancellation approval and refresh ${arabic ? 'AR' : 'EN'}',
      (tester) async {
        final adapter = CancelHttp();
        final dir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('q1-screen-'),
        ))!;
        final db = await tester.runAsync(
          () => databaseFactoryFfi.openDatabase(
            '${dir.path}/journal.db',
            options: OpenDatabaseOptions(
              version: 1,
              onCreate: (db, _) => SqliteQrQuickStore.createSchema(db),
            ),
          ),
        );
        final dio = Dio(BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'))
          ..httpClientAdapter = adapter;
        final api = PosApiService(
          tokenGetter: () => 'synthetic-device',
          dio: dio,
        );
        final gateway = ApiQrQuickGateway(api, () => 'synthetic-scope');
        final store = SqliteQrQuickStore(db!, 'synthetic-scope');
        final controller = QrQuickController(gateway, store);
        addTearDown(() async {
          dio.close(force: true);
          await db.close();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: QrQuickScreen(
              createController: () async => controller,
              catalogue: () => [],
              arabic: arabic,
            ),
          ),
        );
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-order-one'))
              .evaluate()
              .isNotEmpty,
          reason: 'real SQLite journal and HTTP list loaded',
          timeout: const Duration(seconds: 20),
        );
        expect(find.byKey(const ValueKey('quick-cancel-one')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick-cancel-two')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick-cancel-live')), findsNothing);
        Future<void> tap(String key) async {
          final f = find.byKey(ValueKey(key));
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pump();
        }

        await tester.enterText(
          find.byKey(const ValueKey('quick-order-search')),
          '5678',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('quick-order-one')), findsNothing);
        expect(find.byKey(const ValueKey('quick-order-two')), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('quick-order-search')),
          'T-0918-one',
        );
        await tester.pump();
        expect(find.byKey(const ValueKey('quick-order-one')), findsOneWidget);
        expect(find.byKey(const ValueKey('quick-order-two')), findsNothing);
        await tap('quick-cancel-one');
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-cancel-summary'))
              .evaluate()
              .isNotEmpty,
          reason: 'single order server preview',
          timeout: const Duration(seconds: 20),
        );
        expect(find.textContaining('1.000 OMR'), findsWidgets);
        await tap('quick-cancel-close');
        await pumpUntilRealCondition(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
          reason: 'closed cancellation review leaves the screen',
          timeout: const Duration(seconds: 20),
        );
        expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
        await tester.enterText(
          find.byKey(const ValueKey('quick-order-search')),
          '',
        );
        await tester.pump();
        await tap('quick-clear-expired');
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-cancel-summary'))
              .evaluate()
              .isNotEmpty,
          reason: 'bulk server preview',
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.text(arabic ? '2 طلبات · 3.000 OMR' : '2 orders · 3.000 OMR'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-reason')),
          'Synthetic cancelled by manager',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-pin')),
          '9999',
        );
        await tap('quick-cancel-confirm');
        await pumpUntilRealCondition(
          tester,
          () => find
              .text(
                arabic
                    ? 'لم يتم قبول رمز المشرف.'
                    : 'Manager PIN not accepted.',
              )
              .evaluate()
              .isNotEmpty,
          reason: 'manager refusal visible',
          timeout: const Duration(seconds: 20),
        );
        expect(adapter.orders.length, 3);
        await tap('quick-cancel-close');
        await pumpUntilRealCondition(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
          reason: 'closed cancellation review leaves the screen',
          timeout: const Duration(seconds: 20),
        );
        await tap('quick-clear-expired');
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-cancel-summary'))
              .evaluate()
              .isNotEmpty,
          reason: 'fresh bulk review after refusal',
          timeout: const Duration(seconds: 20),
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-reason')),
          'Synthetic cancelled by manager',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-pin')),
          '4321',
        );
        await tap('quick-cancel-confirm');
        await pumpUntilRealCondition(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isEmpty &&
              controller.orders.length == 1,
          reason: 'approved cancellation refreshes live-only list',
          timeout: const Duration(seconds: 20),
        );
        expect(controller.orders.single.uuid, 'live');
        expect(adapter.requests.where((r) => r.method == 'POST').length, 2);
        expect(adapter.completed.length, 1);

        expect(
          (adapter.requests.lastWhere((r) => r.method == 'POST').data
              as Map)['prepared_order_uuids'],
          isEmpty,
          reason: 'forced kitchen evidence never marks unsent lines prepared',
        );
        expect(await tester.runAsync(store.load), isEmpty);
        expect(
          adapter.requests.where(
            (r) => r.path.contains('sync') || r.path.contains('pay'),
          ),
          isEmpty,
        );
        // A later independent expiry is cancelled on its own, with one fresh
        // confirmation. The healthy phone session still survives.
        adapter.orders.add({
          ...adapter.orders.single,
          'uuid': 'single',
          'session': 'expired',
          'temp_reference': 'T-0918-single',
          'grand_total_baisas': 500,
        });
        await tester.runAsync(controller.refresh);
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-cancel-single'))
              .evaluate()
              .isNotEmpty,
          reason: 'new expired order is listed',
          timeout: const Duration(seconds: 20),
        );
        await tap('quick-cancel-single');
        await pumpUntilRealCondition(
          tester,
          () => find
              .byKey(const ValueKey('quick-cancel-summary'))
              .evaluate()
              .isNotEmpty,
          reason: 'single cancellation review',
          timeout: const Duration(seconds: 20),
        );
        expect(
          find.text(arabic ? '1 طلبات · 0.500 OMR' : '1 orders · 0.500 OMR'),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-reason')),
          'Synthetic one-order cancellation',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quick-cancel-pin')),
          '4321',
        );
        await tap('quick-prepared-single');
        await tap('quick-cancel-confirm');
        await pumpUntilRealCondition(
          tester,
          () =>
              find.byType(AlertDialog).evaluate().isEmpty &&
              controller.orders.length == 1,
          reason: 'one cancellation refreshes independently',
          timeout: const Duration(seconds: 20),
        );
        expect(controller.orders.single.uuid, 'live');
        expect(adapter.completed.length, 2);
        expect(
          (adapter.requests.lastWhere((r) => r.method == 'POST').data
              as Map)['prepared_order_uuids'],
          ['single'],
        );
        expect(
          adapter.requests
              .lastWhere((r) => r.path.endsWith('/cancel-preview'))
              .queryParameters['order_uuid'],
          'single',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
