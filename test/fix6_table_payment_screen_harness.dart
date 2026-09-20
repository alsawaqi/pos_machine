import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
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
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'workspace_machine_harness.dart';
import 'real_io_wait.dart';

import 'package:drift/drift.dart' show Value;
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 't65_real_screen_payment_test.dart' as original;

import 'f28_table_payment_recovery_harness.dart' show RecoveryServer, MovingGps;
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';

class ReviewServer extends RecoveryServer {
  String response = 'lost';
  int approvals = 0;
  @override
  Future<String?> verifyManagerPin(String pin) async {
    approvals++;
    return pin == '1234' ? 'Manager' : null;
  }

  @override
  Dio dio() {
    final d = Dio();
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          final batch = ((o.data as Map)['events'] as List).cast<Map>();
          final results = <Map<String, dynamic>>[];
          for (final raw in batch) {
            final e = Map<String, dynamic>.from(raw);
            events.add(e);
            if (e['event_type'] == 'product.waste') {
              results.add({
                'client_event_id': e['client_event_id'],
                'status': 'failed',
                'result': {'error': 'Cannot waste: only -21 on the shelf.'},
              });
              continue;
            }
            uuid = (e['payload'] as Map)['order_uuid'] as String;
            if (e['event_type'] == 'order.pay') {
              expect(claimed, true);
              final payments = (e['payload'] as Map)['payments'] as List;
              expect(
                payments.fold<int>(
                  0,
                  (s, p) => s + (p['amount_baisas'] as int),
                ),
                total,
              );
              paid = true;
            }
            results.add({
              'client_event_id': e['client_event_id'],
              'status': 'processed',
              'result': {
                'order_uuid': uuid,
                'table_session_uuid': original.seat,
                'temp_reference': 'T-FIX7-001',
                if (e['event_type'] == 'order.pay') ...{
                  if (receiptProof) 'status': 'paid',
                  'order_id': 65,
                  'receipt_number': 'TEST-T65-120',
                } else
                  'outcome': e['event_type'] == 'table.session.open'
                      ? 'opened'
                      : 'appended',
                if (e['event_type'] == 'table.session.round') ...{
                  'round_id': 1,
                  'round_no': 1,
                },
              },
            });
          }
          for (final result in results) {
            final body = result['result'] as Map;
            if (body['status'] != 'paid') continue;
            if (response == 'refused') {
              result['status'] = 'failed';
              result['result'] = {'error': 'bill was refused'};
              paid = false;
            } else if (response == 'orphan') {
              body['orphan_tender'] = true;
              body['status'] = 'void';
            }
          }
          if (batch.any((e) => e['event_type'] == 'order.pay')) {
            ids.addAll(
              batch
                  .where((e) => e['event_type'] == 'order.pay')
                  .map((e) => e['client_event_id'] as String),
            );
            if (!answer) {
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                  error: 'ACK lost after server commit',
                ),
              );
              return;
            }
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {
                'data': {'results': results},
              },
            ),
          );
        },
      ),
    );
    return d;
  }
}

void runFix6PaymentScreen(String scenario) {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final mode in [scenario]) {
    testWidgets('Fix6 real screen $mode shows accurate recovery and a working exit', (
      tester,
    ) async {
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
      final server = ReviewServer();
      final gps = MovingGps()..failTenderFix = mode == 'new-lost';
      final oldGps = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = gps;
      addTearDown(() => GeolocatorPlatform.instance = oldGps);
      final boards = StreamController<RemoteTableSnapshot>.broadcast();
      late Directory auxiliary;
      await drive(() async {
        databaseFactory = databaseFactoryFfi;
        auxiliary = await Directory.systemTemp.createTemp('fix8-ack-');
        await databaseFactory.setDatabasesPath(auxiliary.path);
        localDb = await original.realLocalDatabase();
        storage = LocalOrderStorageService.forTesting(localDb);
        await storage.refreshRecoveryGuard();
        driftDb = AppDatabase.forTesting(NativeDatabase.memory());
        outbox = OrderSyncRepository(
          PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
          driftDb,
        );
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
      TableKitchenBridge? bridge;
      addTearDown(() async {
        bridge?.detach();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        debugOrderStorageOverride = null;
        await drive(() async {
          await coordinator.dispose();
          await outbox.dispose();
          await driftDb.close();
          await localDb.close();
          await boards.close();
        });
      });
      Future<void> mount() async {
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          arabic: mode == 'ar-pending' || mode == 'orphan',
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
      await pumpUntilRealCondition(
        tester,
        () => c.diningTableSyncHooks != null,
        reason: 'real table bridge attached',
      );
      c.applyCatalog(
        categories: const ['Drinks'],
        products: const [
          original.product,
          Product(id: '11', name: 'Sweet', category: 'Drinks', price: 0.3),
          Product(id: '12', name: 'Unsent', category: 'Drinks', price: 1),
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
      c.printReceipts = false;
      c.printKitchenTickets = false;
      bridge = c.diningTableSyncHooks as TableKitchenBridge;
      await drive(() async {
        await storage.refreshRecoveryGuard();
        expect(c.diningTableDefinitions, isNotEmpty);
        await c.openDiningTable('1');
        expect(c.activeDiningTableId, '1', reason: c.lastPaymentMessage);
        c.addProduct(original.product);
        c.addProduct(original.product);
      });
      await drive(() async {
        await bridge!.send(bridge.activeSession()!);
        await coordinator.settled;
        await outbox.flush();
      });
      await pumpUntilRealCondition(
        tester,
        () =>
            server.events
                .where((e) => e['event_type'] == 'table.session.round')
                .length ==
            1,
        reason: 'first accepted staff round ACK',
      );

      await drive(() async {
        await driftDb
            .into(driftDb.branchCache)
            .insert(
              BranchCacheCompanion.insert(
                id: const Value(1),
                latitude: const Value(23.588),
                longitude: const Value(58.3829),
              ),
            );
      });
      await pumpUntilRealCondition(tester, () {
        final button = find.byKey(const ValueKey('table-adjust-discount'));
        return button.evaluate().isNotEmpty &&
            tester.widget<TextButton>(button).onPressed != null;
      }, reason: 'real canonical table editor finished loading before tender');
      c.selectPaymentMethod('Cash');
      await drive(() => c.payAndPrint(cashTenderedAmount: 20));
      final journal = (await drive(
        () => SqliteCheckoutStore.open('inspection'),
      ))!;
      expect(
        c.lastPaymentMessage.contains('before payment'),
        isNot(true),
        reason: c.lastPaymentMessage,
      );
      final before = (await drive(
        () => journal.db.query('qr_checkout_attempts'),
      ))!.single;
      expect(before['state'], 'pending');
      final saved = CheckoutAttempt.decode(before['payload'] as String);
      final row = (await drive(() => outbox.rowForKey(server.uuid!)))!;
      expect(row.syncedAt, isNull);
      expect(server.paid, true, reason: 'Server committed; only ACK was lost');

      if (mode == 'standalone') {
        final standaloneEvent = Map<String, dynamic>.from(saved.event!);
        standaloneEvent['payload'] = Map<String, dynamic>.from(
          standaloneEvent['payload'] as Map,
        )..remove('gps');
        final standalone = saved.copy(
          paymentContract: 'qr',
          event: standaloneEvent,
        );
        await drive(() async {
          await journal.db.update(
            'qr_checkout_attempts',
            {'payload': jsonEncode(standalone.json)},
            where: 'id = ?',
            whereArgs: [saved.id],
          );
          await (driftDb.update(driftDb.orderOutbox)
                ..where((t) => t.orderUuid.equals(saved.orderUuid)))
              .write(OrderOutboxCompanion(syncedAt: Value(DateTime.now())));
        });
      } else if (mode == 'refused') {
        await drive(() async {
          await (driftDb.update(
            driftDb.orderOutbox,
          )..where((t) => t.orderUuid.equals(saved.orderUuid))).write(
            const OrderOutboxCompanion(
              serverRejections: Value(5),
              lastError: Value('bill was refused'),
            ),
          );
        });
      }
      bridge.detach();
      bridge = null;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      server.answer = mode == 'refused' || mode == 'orphan';
      server.response = mode;
      await mount();
      boards.add(
        RemoteTableSnapshot(
          tables: {1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now())},
        ),
      );
      if (mode == 'standalone') {
        final dynamic h = tester.state(find.byType(StaffPosScreen));
        final PosController c2 = h.controller;
        await pumpUntilRealCondition(
          tester,
          () => !c2.isLoadingStorage && c2.diningTableSyncHooks != null,
          reason: 'real restarted host finished loading',
        );
        // Await the same real outbox queue used by startup. The explicitly
        // standalone journal must remain untouched by the table listener.
        await drive(outbox.flush);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('table-check-payment-result')),
          findsNothing,
        );
        expect(
          (await drive(
            () => journal.db.query('qr_checkout_attempts'),
          ))!.single['state'],
          'pending',
        );
        expect(
          await drive(() => localDb.query('draft_recovery_closed_archive')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        return;
      }
      await pumpUntilRealCondition(tester, () {
        final f = find.byKey(const ValueKey('table-check-payment-result'));
        return f.evaluate().isNotEmpty &&
            tester.widget<TextButton>(f).onPressed != null;
      }, reason: 'real host exposes enabled saved-payment control');
      if (mode == 'ar-pending') {
        expect(
          find.text('الدفع محفوظ ولم تتأكد نتيجته. لا تأخذ دفعة أخرى.'),
          findsOneWidget,
        );
        expect(find.text('تحقق من نتيجة الدفع'), findsOneWidget);
        final beforeCount = server.events
            .where((e) => e['event_type'] == 'order.pay')
            .length;
        await tester.tap(
          find.byKey(const ValueKey('table-check-payment-result')),
        );
        await pumpUntilRealCondition(
          tester,
          () =>
              server.events
                  .where((e) => e['event_type'] == 'order.pay')
                  .length >
              beforeCount,
          reason: 'Arabic check button replays original payment',
        );
        expect(server.ids, {saved.id});
        expect(
          (await drive(
            () => journal.db.query('qr_checkout_attempts'),
          ))!.single['state'],
          'pending',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        return;
      }
      await pumpUntilRealCondition(
        tester,
        () async =>
            (await journal.db.query('qr_checkout_attempts')).single['state'] ==
            (mode == 'orphan' ? 'uncertain' : 'refused'),
        reason: 'real outbox ACK durably records manager-review state',
      );
      expect(
        find.text(
          mode == 'orphan'
              ? 'توقف. ربما تم أخذ دفعة سابقة. لا تكرر الدفع. يجب أن يتحقق المشرف من الجهاز والفاتورة.'
              : 'Return any cash collected. Do not take another payment until this attempt is resolved.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(mode == 'orphan' ? 'تسليم للمشرف' : 'Manager takeover'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('table-check-payment-result')),
      );
      await pumpUntilRealCondition(
        tester,
        () => find.byType(QrCheckoutBoundary).evaluate().isNotEmpty,
        reason: 'banner opens existing guarded checkout boundary',
      );
      await pumpUntilRealCondition(
        tester,
        () => find
            .byKey(const ValueKey('qr-checkout-exit'))
            .evaluate()
            .isNotEmpty,
        reason: 'existing manager exit is reachable',
      );
      expect(find.byKey(const ValueKey('qr-checkout-retry')), findsNothing);
      expect(
        await drive(() => localDb.query('draft_recovery_closed_archive')),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('qr-checkout-exit')));
      await pumpUntilRealCondition(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        reason: 'real manager PIN dialog',
      );
      // Cancel is denied authority: row and manager-review route stay intact.
      Navigator.of(tester.element(find.byType(AlertDialog))).pop(false);
      await tester.pump();
      expect(
        (await drive(
          () => journal.db.query('qr_checkout_attempts'),
        ))!.single['state'],
        mode == 'orphan' ? 'uncertain' : 'refused',
      );
      await tester.tap(find.byKey(const ValueKey('qr-checkout-exit')));
      await pumpUntilRealCondition(
        tester,
        () => find.byType(AlertDialog).evaluate().isNotEmpty,
        reason: 'manager PIN dialog reopened',
      );
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(digit),
          ),
        );
        await tester.pump();
      }
      final approve = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(FilledButton),
      );
      await tester.tap(approve);
      await pumpUntilRealCondition(
        tester,
        () => find.byType(QrCheckoutBoundary).evaluate().isEmpty,
        reason: 'approved manager takeover exits real checkout',
      );
      expect(server.approvals, 1);
      expect(
        (await drive(
          () => journal.db.query('qr_checkout_attempts'),
        ))!.single['state'],
        'managed',
      );
      if (mode == 'refused') {
        expect(
          await drive(() => localDb.query('draft_recovery_closed_archive')),
          isEmpty,
        );
      } else {
        // Once the manager owns the orphan tender, the existing retirement
        // proof can archive the bill paid elsewhere. It is not a pay ACK.
        await pumpUntilRealCondition(
          tester,
          () async =>
              (await localDb.query('draft_recovery_closed_archive')).length ==
              1,
          reason:
              'existing closed-bill proof archives only after manager handover',
        );
        expect(await drive(storage.loadOrderHistory), isEmpty);
      }
      expect(server.ids, {saved.id});
      final afterCount = server.events
          .where((e) => e['event_type'] == 'order.pay')
          .length;
      await drive(outbox.flush);
      expect(
        server.events.where((e) => e['event_type'] == 'order.pay').length,
        afterCount,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
