import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/sunmi_receipt_service.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';
import 't65_real_screen_payment_test.dart' show AckServer, realLocalDatabase;

Future<Database> fileBackedLocalDatabase(Directory dir) async {
  final schema = await realLocalDatabase();
  final file = File('${dir.path}/orders.sqlite');
  await schema.execute("VACUUM INTO '${file.path.replaceAll("'", "''")}'");
  await schema.close();
  return databaseFactoryFfi.openDatabase(file.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final ar in [false, true]) {
    for (final kind in [
      'order+product',
      'order+offer',
      'product',
      'order',
      'manual+product',
    ]) {
      testWidgets('D1 real till and printed receipt $kind ar=$ar', (
        tester,
      ) async {
        Future<T?> drive<T>(Future<T> Function() action) async {
          var done = false;
          T? result;
          Object? error;
          StackTrace? trace;
          await tester.runAsync(() async {
            unawaited(
              action().then(
                (v) {
                  result = v;
                  done = true;
                },
                onError: (Object e, StackTrace st) {
                  error = e;
                  trace = st;
                  done = true;
                },
              ),
            );
          });
          await pumpUntilRealCondition(
            tester,
            () => done,
            reason: 'D1 actual SQLite operation',
            timeout: const Duration(seconds: 20),
          );
          if (error != null) Error.throwWithStackTrace(error!, trace!);
          return result;
        }

        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final printed = <String>[];
        var startupDisplayQueried = false;
        for (final name in [
          'plugins.it_nomads.com/flutter_secure_storage',
          'pos_machine/rear_display_host',
          'sunmi_printer_plus',
        ]) {
          final channel = MethodChannel(name);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
                if (name == 'pos_machine/rear_display_host') {
                  startupDisplayQueried = true;
                }
                if (name == 'sunmi_printer_plus' &&
                    call.method == 'printText') {
                  printed.add(
                    ((call.arguments as Map)['data'] as Map)['text'].toString(),
                  );
                }
                if (name == 'sunmi_printer_plus') return null;
                return call.method == 'read'
                    ? 'fixture'
                    : <Map<String, dynamic>>[];
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
        }
        late Database db;
        late AppDatabase drift;
        late LocalOrderStorageService storage;
        late OrderSyncRepository outbox;
        late TableSyncCoordinator coordinator;
        final server = AckServer();
        final boards = StreamController<RemoteTableSnapshot>.broadcast();
        await drive(() async {
          databaseFactory = databaseFactoryFfi;
          final dir = await Directory.systemTemp.createTemp('fix9-discount-');
          await databaseFactory.setDatabasesPath(dir.path);
          db = await fileBackedLocalDatabase(dir);
          storage = LocalOrderStorageService.forTesting(db);
          await storage.refreshRecoveryGuard();
          drift = AppDatabase.forTesting(
            NativeDatabase(File('${dir.path}/outbox.sqlite')),
          );
          outbox = OrderSyncRepository(
            PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
            drift,
          );
          coordinator = TableSyncCoordinator(
            outbox: outbox,
            store: storage,
            loadSessions: storage.loadDiningTableSessions,
            mode: () => 'off',
            degraded: () => false,
            staffId: () => 7,
            markPrinted: (_) async {},
          );
        });
        debugOrderStorageOverride = storage;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          debugOrderStorageOverride = null;
          await drive(() async {
            await coordinator.dispose();
            await outbox.dispose();
            await drift.close();
            await db.close();
            await boards.close();
          });
        });
        await pumpWorkspaceMachine(
          tester,
          mode: 'off',
          toggle: false,
          arabic: ar,
          api: server,
          outbox: outbox,
          database: drift,
          coordinator: coordinator,
          boards: boards.stream,
          catalog: const CatalogSnapshot(
            categories: [],
            products: [],
            floors: [],
            tables: [],
            taxes: [],
          ),
        );
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        final PosController c = host.controller;
        await pumpUntilRealCondition(
          tester,
          () => !c.isLoadingStorage && startupDisplayQueried,
          reason: 'real till startup storage loaded',
          timeout: const Duration(seconds: 20),
        );
        final orderName = ar ? 'اليوم الوطني' : 'National day';
        final productName = ar ? 'خصم القهوة' : 'Coffee rule';
        final offerName = ar ? 'عرض القهوة' : 'Coffee offer';
        final manualName = ar ? 'خصم يدوي' : 'Manual saving';
        const coffee = Product(
          id: '10',
          name: 'Coffee',
          category: 'Coffee',
          price: .5,
        );
        c.applyCatalog(
          floors: const [],
          tables: const [],
          branchId: 6,
          categories: const ['Coffee'],
          products: const [coffee],
          discounts: [
            if (kind.contains('product'))
              MerchantDiscount(
                id: 20,
                name: productName,
                scope: 'product',
                amountType: 'percent',
                percent: 20,
                targets: const [
                  DiscountTarget(targetType: 'product', targetId: 10),
                ],
              ),
          ],
          offers: [
            if (kind.contains('offer'))
              Offer(
                id: 30,
                name: offerName,
                type: 'spend_get',
                config: const {
                  'min_subtotal_baisas': 1,
                  'reward_type': 'fixed_off',
                  'reward_value': 100,
                },
              ),
          ],
        );
        c.addProduct(coffee);
        if (kind.contains('order')) {
          c.applyDiscount(
            DiscountConfiguration(
              kind: DiscountKind.percentage,
              value: 10,
              label: orderName,
              discountId: 1,
            ),
          );
        }
        if (kind.contains('manual')) {
          c.applyDiscount(
            DiscountConfiguration(
              kind: DiscountKind.fixedAmount,
              value: .05,
              label: manualName,
              reason: 'Goodwill',
            ),
          );
        }
        final expected = <String, int>{
          if (kind.contains('order')) orderName: 50,
          if (kind.contains('manual')) manualName: 50,
          if (kind.contains('product')) productName: 100,
          if (kind.contains('offer')) offerName: 100,
        };
        final snapshot = c.snapshot();
        final moneyBefore = [
          snapshot.discountAmount,
          snapshot.subtotal,
          snapshot.tax,
          snapshot.total,
        ];
        final wire = buildOrderSyncPayload(
          snapshot,
          now: DateTime.utc(2026),
          newUuid: () => 'display-only-test',
        );
        final rows =
            ((wire.events.first['payload'] as Map)['order'] as Map)['discounts']
                as List;
        expect({
          for (final row in rows) row['name']: row['amount_baisas'],
        }, expected);
        await tester.pump();
        for (final entry in expected.entries) {
          final label = find.text(entry.key);
          expect(label, findsOneWidget);
          final row = find
              .ancestor(of: label, matching: find.byType(Row))
              .first;
          expect(
            find.descendant(
              of: row,
              matching: find.textContaining(
                (entry.value / 1000).toStringAsFixed(3),
              ),
            ),
            findsOneWidget,
          );
        }
        await drive(
          () => SunmiReceiptService.printReceipt(
            OrderSnapshot.fromMap(snapshot.toMap()),
          ),
        );
        for (final entry in expected.entries) {
          expect(
            printed.where(
              (text) =>
                  text.contains(entry.key) &&
                  text.contains(
                    '-${(entry.value / 1000).toStringAsFixed(3)} OMR',
                  ),
            ),
            hasLength(1),
          );
        }
        expect(
          c.snapshot().discountAmount,
          expected.values.reduce((a, b) => a + b) / 1000,
        );
        expect([
          c.snapshot().discountAmount,
          c.snapshot().subtotal,
          c.snapshot().tax,
          c.snapshot().total,
        ], moneyBefore);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'D1 server receipt preserves source rows and nets audit reversals after SQLite reopen',
    () async {
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('d1-server-history-');
      await databaseFactory.setDatabasesPath(dir.path);
      final db = await fileBackedLocalDatabase(dir);
      final storage = LocalOrderStorageService.forTesting(db);
      final record = OrderHistoryRecord.fromServerJson({
        'id': 91,
        'uuid': 'd1-server-bill',
        'order_type': 'dine_in',
        'status': 'paid',
        'receipt_number': 'TEST-D1-SERVER',
        'subtotal_baisas': 500,
        'discount_total_baisas': 150,
        'tax_total_baisas': 18,
        'grand_total_baisas': 368,
        'discount_sources': [
          {
            'source': 'order',
            'discount_id': 1,
            'name': 'National day',
            'amount_baisas': 50,
          },
          {
            'source': 'line',
            'discount_id': 2,
            'name': 'Coffee rule',
            'amount_baisas': 75,
          },
          {
            'source': 'line',
            'discount_id': 2,
            'name': 'Coffee rule',
            'amount_baisas': 25,
          },
          {'source': 'manual', 'name': 'Old manual', 'amount_baisas': 20},
          {'source': 'manual', 'name': 'Old manual', 'amount_baisas': -20},
        ],
        'items': [
          {'product_name': 'Coffee', 'qty': 1, 'line_total_baisas': 500},
        ],
      });
      await storage.saveCompletedOrder(record.snapshot);
      final path = db.path;
      await db.close();
      final reopened = await databaseFactory.openDatabase(path);
      final restored = (await LocalOrderStorageService.forTesting(
        reopened,
      ).loadOrderHistory()).single.snapshot;
      final printed = <String>[];
      const channel = MethodChannel('sunmi_printer_plus');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'printText') {
              printed.add(
                ((call.arguments as Map)['data'] as Map)['text'].toString(),
              );
            }
            return null;
          });
      try {
        expect(await SunmiReceiptService.printReceipt(restored), isTrue);
        expect(
          printed.where(
            (row) => row.contains('National day') && row.contains('-0.050 OMR'),
          ),
          hasLength(1),
        );
        expect(
          printed.where(
            (row) => row.contains('Coffee rule') && row.contains('-0.100 OMR'),
          ),
          hasLength(1),
        );
        expect(printed.where((row) => row.contains('Old manual')), isEmpty);
        expect(restored.total, .368);
        expect(restored.discountAmount, .15);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await reopened.close();
      }
    },
  );
  for (final name in ['Loyalty redemption', 'Stamp reward']) {
    test('D1 keeps existing $name receipt label', () async {
      final snapshot = OrderSnapshot.fromMap({
        'rawSubtotal': .5,
        'subtotal': .45,
        'discountAmount': .05,
        'discountLabel': name,
        'total': .45,
        'tax': 0,
        'items': <Map<String, dynamic>>[],
      });
      final printed = <String>[];
      const channel = MethodChannel('sunmi_printer_plus');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'printText') {
              printed.add(
                ((call.arguments as Map)['data'] as Map)['text'].toString(),
              );
            }
            return null;
          });
      try {
        expect(await SunmiReceiptService.printReceipt(snapshot), isTrue);
        expect(
          printed.where(
            (text) => text.contains(name) && text.contains('-0.050 OMR'),
          ),
          hasLength(1),
        );
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });
  }
}
