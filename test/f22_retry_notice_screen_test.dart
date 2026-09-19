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
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

import 't65_real_screen_payment_test.dart'
    show AckServer, realLocalDatabase, product;

import 'dart:convert';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';

class _RetryServer extends AckServer {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> dineInAdjust(
    String id,
    Map<String, dynamic> p,
  ) async {
    requests.add(jsonDecode(jsonEncode(p)));
    if (requests.length == 1) {
      throw ApiException(message: 'lost', isNetwork: true);
    }
    throw ApiException.fromErrors([
      {'message': 'external refusal', 'code': 'new_policy_refusal'},
    ], 422);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'F22 real staff-only screen shows a final retry refusal after clearing its journal',
    (tester) async {
      Future<T?> drive<T>(Future<T> Function() action) async {
        var done = false;
        T? value;
        Object? error;
        StackTrace? trace;
        await tester.runAsync(() async {
          unawaited(
            action().then(
              (v) {
                value = v;
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
          reason: 'real SQLite/coordinator operation completed',
        );
        if (!done) throw StateError('Real component workflow did not finish');
        if (error != null) Error.throwWithStackTrace(error!, trace!);
        return value;
      }

      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final name in [
        'plugins.it_nomads.com/flutter_secure_storage',
        'pos_machine/rear_display_host',
      ]) {
        final channel = MethodChannel(name);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              channel,
              (call) async =>
                  call.method == 'read' ? 'fixture' : <Map<String, dynamic>>[],
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      late Database localDb;
      late AppDatabase driftDb;
      late LocalOrderStorageService storage;
      late OrderSyncRepository outbox;
      late TableSyncCoordinator coordinator;
      final server = _RetryServer();
      final boards = StreamController<RemoteTableSnapshot>.broadcast();
      late Directory auxiliary;
      await drive(() async {
        databaseFactory = databaseFactoryFfi;
        auxiliary = await Directory.systemTemp.createTemp('fix7-ack-');
        await databaseFactory.setDatabasesPath(auxiliary.path);
        localDb = await realLocalDatabase();
        storage = LocalOrderStorageService.forTesting(localDb);
        await storage.refreshRecoveryGuard();
        driftDb = AppDatabase.forTesting(NativeDatabase.memory());
        outbox = OrderSyncRepository(
          PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
          driftDb,
        );
        outbox.addAckListener(ServerReceiptHistory(storage).acknowledge);
        coordinator = TableSyncCoordinator(
          outbox: outbox,
          store: storage,
          loadSessions: storage.loadDiningTableSessions,
          mode: () => 'live',
          degraded: () => false,
          staffId: () => 7,
          markPrinted: (_) async {},
        );
      });
      debugOrderStorageOverride = storage;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        debugOrderStorageOverride = null;
        await drive(() async {
          await coordinator.dispose();
          await outbox.dispose();
          await driftDb.close();
          await localDb.close();
          await boards.close();
        });
        await tester.pumpAndSettle();
      });
      Future<void> mount() async {
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          wrapStaff: (child) => MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
            child: child,
          ),
          api: server,
          outbox: outbox,
          database: driftDb,
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
      }

      await mount();
      final dynamic host = tester.state(find.byType(StaffPosScreen));
      final PosController c = host.controller;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await drive(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
      }
      c.applyCatalog(
        branchId: 6,
        categories: const ['Drinks'],
        products: const [product],
        discounts: const [
          MerchantDiscount(
            id: 2,
            name: 'Automatic 15%',
            scope: 'order',
            amountType: 'percent',
            percent: 15,
            autoApply: true,
          ),
        ],
        floors: const [DiningFloor(id: '1', label: 'Main')],
        tables: const [
          DiningTableDefinition(
            id: '1',
            floorId: '1',
            name: 'Table 1',
            sizeLabel: 'square',
            seats: 4,
            sortOrder: 1,
          ),
        ],
      );

      Future<void> settle([int n = 18]) async {
        for (var i = 0; i < n; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await drive(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
        }
      }

      c.printReceipts = false;
      c.printKitchenTickets = false;
      await drive(() async {
        await storage.refreshRecoveryGuard();
        await c.openDiningTable('1');
        c.addProduct(product);
        c.addProduct(product);
      });
      await settle();
      await tester.tap(find.byKey(const ValueKey('table-send-to-kitchen')));
      await settle(40);
      await drive(() async {
        await coordinator.settled;
        await outbox.flush();
      });
      c.availableDiscounts = [];
      final discount = find.byKey(const ValueKey('table-adjust-discount'));
      await pumpUntilRealCondition(
        tester,
        () =>
            discount.evaluate().isNotEmpty &&
            tester.widget<TextButton>(discount).onPressed != null,
        reason: 'the real table adjustment editor to enable Discount',
      );
      expect(tester.widget<TextButton>(discount).onPressed, isNotNull);
      await tester.ensureVisible(discount);
      await tester.tap(discount);
      await settle();
      expect(
        find.byType(Dialog),
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.tap(
        find
            .descendant(of: find.byType(Dialog), matching: find.text('10%'))
            .last,
      );
      await tester.pump();
      await tester.tap(
        find.text(L10nEn().posDiscountDlgApply('10% Discount')).last,
      );
      await pumpUntilRealCondition(
        tester,
        () {
          final savedRetry = find.byKey(const ValueKey('table-adjust-retry'));
          return server.requests.isNotEmpty &&
              savedRetry.evaluate().isNotEmpty &&
              tester.widget<TextButton>(savedRetry).onPressed != null;
        },
        reason: 'the first saved adjustment to reach HTTP and enable its retry',
      );
      expect(server.requests, hasLength(1));
      final retry = find.byKey(const ValueKey('table-adjust-retry'));
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      // The retry completes durable removal and its board refresh before the
      // screen shows the result. HTTP arrival alone is not UI completion.
      await pumpUntilRealCondition(
        tester,
        () => find
            .textContaining('Adjustment refused (new_policy_refusal)')
            .evaluate()
            .isNotEmpty,
        reason: 'the final retry refusal to be visible after durable recovery',
      );
      expect(server.requests, hasLength(2));
      expect(server.requests[1], server.requests[0]);
      expect(
        find.textContaining('Adjustment refused (new_policy_refusal)'),
        findsWidgets,
        reason:
            'Staff must see a final refusal even when retry cleared the pending row',
      );
      final pending = await drive(
        () async => (await SqliteDineInStore.open(
          'inspection',
        )).db.query('dine_in_requests'),
      );
      expect(pending, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
