import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/server_receipt_history.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'real_io_wait.dart';
import 't12_table_loyalty_screen_test.dart'
    show AckServer, product, realLocalDatabase;
import 'workspace_machine_harness.dart';

// The only payment substitute is the external HTTP response. The real controller,
// SQLite stores, bridge, outbox, ACK coordinator and receipt projection run below.
class _DelayedAckServer extends AckServer {
  _DelayedAckServer(this.delay, this.earns);
  final Duration delay;
  final bool earns;
  bool payResponseWaiting = false;
  bool payResponseDelivered = false;
  final payClock = Stopwatch();
  final releaseLateAck = Completer<void>();

  @override
  Dio dio() {
    final delegate = super.dio();
    return Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) async {
            try {
              final response = await delegate.fetch<dynamic>(request);
              final body = request.data;
              final events = body is Map ? body['events'] as List? : null;
              if (events?.any((e) => e['event_type'] == 'order.pay') == true) {
                payClock.start();
                payResponseWaiting = true;
                await Future<void>.delayed(delay);
                if (delay > Duration.zero) await releaseLateAck.future;
                final results = response.data['data']['results'] as List;
                for (final ack in results) {
                  final result = ack['result'] as Map;
                  if (result['status'] == 'paid' && !earns) {
                    result['loyalty_earned'] = {'points': 0, 'stamps': 0};
                  }
                }
                payResponseDelivered = true;
              }
              handler.resolve(response);
            } catch (error, stack) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  error: error,
                  stackTrace: stack,
                ),
              );
            }
          },
        ),
      );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final scenario in [
    (name: 'late EN', late: true, arabic: false, earns: true, dispose: false),
    (name: 'late AR', late: true, arabic: true, earns: true, dispose: false),
    (name: 'timely', late: false, arabic: false, earns: true, dispose: false),
    (
      name: 'zero earned',
      late: true,
      arabic: false,
      earns: false,
      dispose: false,
    ),
    (name: 'disposed', late: true, arabic: false, earns: true, dispose: true),
  ]) {
    testWidgets('E1 real table ACK ${scenario.name} consumes earned notice once', (
      tester,
    ) async {
      final notices = <SnackBar>{};
      void observe() {
        for (final snack in tester.widgetList<SnackBar>(
          find.byType(SnackBar),
        )) {
          if (snack.content is Text &&
              snack.content.key == const ValueKey('table-loyalty-earned')) {
            notices.add(snack);
          }
        }
      }

      Future<void> until(FutureOr<bool> Function() condition, String reason) =>
          pumpUntilRealCondition(tester, () async {
            observe();
            return await condition();
          }, reason: reason);

      Future<T> drive<T>(Future<T> Function() operation) async {
        var complete = false;
        late T result;
        Object? error;
        StackTrace? trace;
        await tester.runAsync(() async {
          unawaited(
            operation().then(
              (value) {
                result = value;
                complete = true;
              },
              onError: (Object e, StackTrace s) {
                error = e;
                trace = s;
                complete = true;
              },
            ),
          );
        });
        await until(() => complete, 'real SQLite/controller operation');
        if (error != null) Error.throwWithStackTrace(error!, trace!);
        return result;
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
              (call) async => call.method == 'read' ? 'fixture' : <Map>[],
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      final server = _DelayedAckServer(
        scenario.late ? const Duration(seconds: 10) : Duration.zero,
        scenario.earns,
      )..customer = {'id': 5, 'name': 'Customer', 'phone': '90000000'};
      final api = PosApiService(
        tokenGetter: () => 'fixture',
        dio: server.dio(),
      );
      late Database localDb;
      late AppDatabase driftDb;
      late LocalOrderStorageService storage;
      late OrderSyncRepository outbox;
      late TableSyncCoordinator coordinator;
      final boards = StreamController<RemoteTableSnapshot>.broadcast();
      await drive(() async {
        databaseFactory = databaseFactoryFfi;
        final directory = await Directory.systemTemp.createTemp('fix9-earned-');
        await databaseFactory.setDatabasesPath(directory.path);
        localDb = await realLocalDatabase();
        storage = LocalOrderStorageService.forTesting(localDb);
        await storage.refreshRecoveryGuard();
        driftDb = AppDatabase.forTesting(
          NativeDatabase(File('${directory.path}/outbox.sqlite')),
        );
        outbox = OrderSyncRepository(api, driftDb);
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
          await coordinator.settled;
          await coordinator.dispose();
          await outbox.dispose();
          await driftDb.close();
          await localDb.close();
          await boards.close();
        });
      });
      Future<void> mount() => pumpWorkspaceMachine(
        tester,
        mode: 'live',
        toggle: false,
        arabic: scenario.arabic,
        api: api,
        outbox: outbox,
        database: driftDb,
        coordinator: coordinator,
        boards: boards.stream,
        wrapStaff: (child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
          child: child,
        ),
        catalog: const CatalogSnapshot(
          categories: [],
          products: [],
          floors: [],
          tables: [],
          taxes: [],
        ),
      ).then((_) {});
      await mount();
      final dynamic host = tester.state(find.byType(StaffPosScreen));
      final PosController controller = host.controller;
      await until(
        () =>
            !controller.isLoadingStorage &&
            controller.diningTableSyncHooks != null,
        'real table bridge attached',
      );
      controller.applyCatalog(
        categories: const ['Drinks'],
        products: const [product],
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
      controller.printReceipts = false;
      controller.printKitchenTickets = false;
      await drive(() async {
        await storage.refreshRecoveryGuard();
        await controller.openDiningTable('1');
        controller.addProduct(product);
        controller.addProduct(product);
      });
      final send = find.byKey(const ValueKey('table-send-to-kitchen'));
      await until(
        () =>
            send.hitTestable().evaluate().isNotEmpty &&
            tester.widget<FilledButton>(send).onPressed != null,
        'real send-to-kitchen control',
      );
      await tester.tap(send);
      await until(
        () =>
            server.events.any((e) => e['event_type'] == 'table.session.round'),
        'staff round accepted by HTTP fixture',
      );
      await drive(() async {
        await coordinator.settled;
        await outbox.flush();
      });
      final adjustment = find.byKey(const ValueKey('table-adjust-discount'));
      await until(
        () =>
            adjustment.evaluate().isNotEmpty &&
            tester.widget<TextButton>(adjustment).onPressed != null,
        'canonical bill detail and sent-line proof ready',
      );
      controller.selectPaymentMethod('Cash');
      var paid = false;
      Object? paymentError;
      var realPaymentStage = 'not started';
      void logPaymentPhase(String phase, [StackTrace? stack]) {
        // This fixture contains synthetic data only. Preserve the exact
        // stalled phase/error in a red run without changing its wait budget.
        // ignore: avoid_print
        print(
          'E1 ${scenario.name} $phase: '
          'stage=$realPaymentStage method=${controller.selectedPaymentMethod} '
          'paid=$paid processing=${controller.isProcessingPayment} '
          'status=${controller.paymentStatus} '
          'message=${controller.lastPaymentMessage} '
          'httpWaiting=${server.payResponseWaiting} '
          'httpDelivered=${server.payResponseDelivered} '
          'error=$paymentError${stack == null ? '' : '\n$stack'}',
        );
      }

      // Diagnostic observers always delegate to the installed real screen
      // callbacks. They never supply a result or alter an error/wait.
      final realPrepare = controller.prepareDiningTableTender!;
      controller.prepareDiningTableTender = (cash) async {
        realPaymentStage = 'prepare tender';
        logPaymentPhase('real callback entered');
        try {
          final result = await realPrepare(cash);
          realPaymentStage = 'prepare tender completed';
          logPaymentPhase('real callback completed');
          return result;
        } catch (error, stack) {
          realPaymentStage = 'prepare tender failed';
          logPaymentPhase('real callback failed: $error', stack);
          Error.throwWithStackTrace(error, stack);
        }
      };
      final realFinalRound = controller.onDiningTableFinalRound!;
      controller.onDiningTableFinalRound = (snapshot) async {
        realPaymentStage = 'final round proof';
        logPaymentPhase('real callback entered');
        try {
          final result = await realFinalRound(snapshot);
          realPaymentStage = 'final round proof completed';
          logPaymentPhase('real callback completed');
          return result;
        } catch (error, stack) {
          realPaymentStage = 'final round proof failed';
          logPaymentPhase('real callback failed: $error', stack);
          Error.throwWithStackTrace(error, stack);
        }
      };
      logPaymentPhase('before payAndPrint');
      await tester.runAsync(() async {
        unawaited(
          controller
              .payAndPrint(cashTenderedAmount: 20)
              .then(
                (message) {
                  // ignore: avoid_print
                  print('E1 ${scenario.name} payment completion: $message');
                  paid = true;
                  logPaymentPhase('payAndPrint completed');
                },
                onError: (Object error, StackTrace stack) {
                  paymentError = error;
                  logPaymentPhase('payAndPrint failed', stack);
                },
              ),
        );
      });
      logPaymentPhase('payAndPrint scheduled');
      try {
        await until(
          () => server.payResponseWaiting,
          'pay request reached HTTP',
        );
      } catch (_) {
        logPaymentPhase('pay HTTP wait failed');
        rethrow;
      }
      if (scenario.late) {
        await until(
          () => paid,
          'bounded receipt refresh finished before late ACK',
        );
        expect(server.payResponseDelivered, false);
      }
      if (scenario.dispose) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
      if (scenario.late) server.releaseLateAck.complete();
      // Inspect the transient notice while it is visible. Payment completion
      // and the remaining durable ACK work may outlast its display duration.
      final notice = find.byKey(const ValueKey('table-loyalty-earned'));
      if (scenario.earns && !scenario.dispose) {
        await until(
          () => notice.evaluate().isNotEmpty,
          'earned notice after ACK',
        );
        expect(notices, hasLength(1));
        final text = tester.widget<Text>(notice).data!;
        expect(
          text,
          scenario.arabic
              ? 'لقد كسبت 44 نقطة · لقد كسبت 1 أختام'
              : 'You earned 44 points · You earned 1 stamps',
        );
        expect(
          coordinator.loyaltyEarnedByOrder.containsKey(server.uuid),
          false,
        );
      }
      await until(
        () => server.payResponseDelivered && paid,
        'HTTP confirmation and controller completion',
      );
      await drive(() async {
        await coordinator.settled;
        await outbox.flush();
      });
      expect(paymentError, isNull);
      if (!scenario.earns || scenario.dispose) {
        expect(notice, findsNothing);
        expect(notices, isEmpty);
      }
      if (scenario.late) {
        expect(
          server.payClock.elapsed,
          greaterThan(const Duration(seconds: 8)),
        );
      }
      final receiptRows = await drive(() => localDb.query('order_history'));
      expect(receiptRows, hasLength(1));
      final receipt =
          jsonDecode(receiptRows.single['snapshot_json'] as String) as Map;
      expect(receipt['serverReceiptConfirmed'], true);
      expect(receiptRows.single['snapshot_json'], contains('TEST-T12-120'));
      final payRow = await drive(() => outbox.rowForKey(server.uuid!));
      expect(payRow!.syncedAt, isNotNull);
      expect(
        server.events.where((e) => e['event_type'] == 'order.pay'),
        hasLength(1),
      );
      expect(
        server.events.where((e) => e['event_type'] == 'order.void'),
        isEmpty,
      );

      if (scenario.dispose) {
        await mount();
      } else {
        // A subsequent receipt refresh for this same bill cannot re-announce it.
        final snapshot = await drive(
          () => ServerReceiptHistory(storage).find(server.uuid!),
        );
        await drive(() => controller.refreshServerReceipt!(snapshot!));
      }
      boards.add(
        RemoteTableSnapshot(
          tables: {1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now())},
        ),
      );
      await until(
        () async => (await localDb.query('dining_tables')).isEmpty,
        'closed copy archived after late payment',
      );
      expect(
        await drive(() => localDb.query('draft_recovery_closed_archive')),
        hasLength(1),
      );
      expect(await drive(() => localDb.query('order_history')), receiptRows);
      expect(notices, hasLength(scenario.earns && !scenario.dispose ? 1 : 0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
