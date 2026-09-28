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
import 't12_fix9_qr_cancel_test.dart' show CancelHttp;

// Fix 10 (O-20): the real QR screen, controller, gateway, PosApiService/Dio and
// file-backed SQLite journal. Only HTTP is supplied (the Q-1 synthetic server;
// PIN 5555 additionally answers a definitive non-PIN refusal).
class _RefusingCancelHttp extends CancelHttp {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.path.endsWith('/cancel') &&
        (options.data as Map)['pin'] == '5555') {
      requests.add(options);
      return ResponseBody.fromString(
        jsonEncode({
          'data': null,
          'errors': [
            {'code': 'void_preview_changed', 'message': 'Synthetic change'},
          ],
        }),
        409,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return super.fetch(options, stream, cancel);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final arabic in [false, true]) {
    for (final refusal in ['wrong PIN', 'bill changed']) {
      testWidgets(
        'O20 real QR bulk cancel after $refusal ${arabic ? 'AR' : 'EN'}',
        (tester) async {
          final adapter = _RefusingCancelHttp();
          final dir = (await tester.runAsync(
            () => Directory.systemTemp.createTemp('o20-screen-'),
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
          final dio = Dio(
            BaseOptions(baseUrl: 'http://synthetic.invalid/api/v1'),
          )..httpClientAdapter = adapter;
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
          Future<void> tap(String key) async {
            final f = find.byKey(ValueKey(key));
            await tester.ensureVisible(f);
            await tester.tap(f);
            await tester.pump();
          }

          bool pinEnabled() => tester
              .widget<TextField>(find.byKey(const ValueKey('quick-cancel-pin')))
              .enabled!;
          bool reasonEnabled() => tester
              .widget<TextField>(
                find.byKey(const ValueKey('quick-cancel-reason')),
              )
              .enabled!;
          bool confirmEnabled() =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('quick-cancel-confirm')),
                  )
                  .onPressed !=
              null;
          bool preparedEditable() =>
              tester
                  .widget<CheckboxListTile>(
                    find.byKey(const ValueKey('quick-prepared-two')),
                  )
                  .onChanged !=
              null;

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
          expect(preparedEditable(), isTrue);
          await tester.enterText(
            find.byKey(const ValueKey('quick-cancel-reason')),
            'Synthetic cancelled by manager',
          );
          await tester.enterText(
            find.byKey(const ValueKey('quick-cancel-pin')),
            refusal == 'wrong PIN' ? '9999' : '5555',
          );
          await tap('quick-cancel-confirm');
          final message = refusal == 'wrong PIN'
              ? (arabic
                    ? 'لم يتم قبول رمز المشرف.'
                    : 'Manager PIN not accepted.')
              : (arabic
                    ? 'تغيرت الفاتورة. أغلق المراجعة وحدّثها قبل الإلغاء.'
                    : 'The bill changed. Close this review and refresh before cancelling.');
          await pumpUntilRealCondition(
            tester,
            () => find.text(message).evaluate().isNotEmpty,
            reason: 'refusal visible',
            timeout: const Duration(seconds: 20),
          );
          expect(adapter.orders.length, 3, reason: 'nothing was cancelled');
          // The review itself is fixed after the first submission.
          expect(reasonEnabled(), isFalse);
          expect(preparedEditable(), isFalse);
          final firstPost = adapter.requests.lastWhere(
            (r) => r.method == 'POST',
          );

          if (refusal == 'bill changed') {
            // Not a PIN problem: the review stays locked; close and refresh.
            expect(pinEnabled(), isFalse);
            await tester.enterText(
              find.byKey(const ValueKey('quick-cancel-pin')),
              '4321',
            );
            await tester.pump();
            expect(confirmEnabled(), isFalse);
            await tap('quick-cancel-close');
            await pumpUntilRealCondition(
              tester,
              () => find.byType(AlertDialog).evaluate().isEmpty,
              reason: 'locked review can still be closed',
              timeout: const Duration(seconds: 20),
            );
            expect(adapter.requests.where((r) => r.method == 'POST').length, 1);
            expect(adapter.completed, isEmpty);
            expect(adapter.orders.length, 3);
            return;
          }

          // A refused PIN is definitive: the manager may re-enter it here.
          expect(pinEnabled(), isTrue);
          expect(confirmEnabled(), isTrue);
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
          final posts = adapter.requests
              .where((r) => r.method == 'POST')
              .toList();
          expect(posts.length, 2);
          final first = Map<String, dynamic>.from(firstPost.data as Map);
          final second = Map<String, dynamic>.from(posts.last.data as Map);
          expect(first['pin'], '9999');
          expect(second['pin'], '4321');
          // Same request identity and the identical reviewed payload.
          first.remove('pin');
          second.remove('pin');
          expect(jsonEncode(second), jsonEncode(first));
          expect(adapter.completed.length, 1);
          expect(adapter.completed.keys.single, first['client_request_id']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
