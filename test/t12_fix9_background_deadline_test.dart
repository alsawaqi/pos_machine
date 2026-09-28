import 'dart:async';
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
import 'package:pos_machine/state/pos_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'real_io_wait.dart';
import 't12_table_loyalty_screen_test.dart'
    show AckServer, product, realLocalDatabase;
import 'workspace_machine_harness.dart';

class _SlowBackgroundServer extends AckServer {
  _SlowBackgroundServer(this.slowVerify);
  final bool slowVerify;
  bool armed = false;
  bool delayed = false;
  final delayClock = Stopwatch();

  @override
  Dio dio() {
    final delegate = super.dio();
    return Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            final events = options.data is Map
                ? (options.data as Map)['events']
                : null;
            final round =
                events is List &&
                events.any((e) => e['event_type'] == 'table.session.round');
            if (armed &&
                (slowVerify || !delayed) &&
                (slowVerify ? options.path.endsWith('/detail') : round)) {
              delayed = true;
              delayClock.start();
              await Future<void>.delayed(const Duration(seconds: 10));
              delayClock.stop();
            }
            handler.resolve(await delegate.fetch<dynamic>(options));
          },
        ),
      );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final slowVerify in [false, true]) {
    testWidgets(
      'S2 real Back to Floor background ${slowVerify ? 'verification' : 'ACK'} survives completed UI deadline',
      (tester) async {
        Future<void> until(
          FutureOr<bool> Function() condition,
          String reason,
        ) => pumpUntilRealCondition(
          tester,
          condition,
          reason: reason,
          timeout: const Duration(seconds: 20),
        );
        Future<T> drive<T>(Future<T> Function() operation) async {
          var done = false;
          late T value;
          Object? error;
          StackTrace? stack;
          await tester.runAsync(() async {
            unawaited(
              operation().then(
                (v) {
                  value = v;
                  done = true;
                },
                onError: (Object e, StackTrace s) {
                  error = e;
                  stack = s;
                  done = true;
                },
              ),
            );
          });
          await until(() => done, 'real controller/storage operation');
          if (error != null) Error.throwWithStackTrace(error!, stack!);
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
                (call) async => call.method == 'read' ? 'fixture' : <Map>[],
              );
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
        }
        final server = _SlowBackgroundServer(slowVerify);
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
          final directory = await Directory.systemTemp.createTemp('fix9-bg-');
          await databaseFactory.setDatabasesPath(directory.path);
          localDb = await realLocalDatabase();
          storage = LocalOrderStorageService.forTesting(localDb);
          await storage.refreshRecoveryGuard();
          driftDb = AppDatabase.forTesting(
            NativeDatabase(File('${directory.path}/outbox.sqlite')),
          );
          outbox = OrderSyncRepository(api, driftDb);
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
          await tester.pump(const Duration(milliseconds: 1));
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
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
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
        );
        final dynamic host = tester.state(find.byType(StaffPosScreen));
        final PosController controller = host.controller;
        await until(
          () =>
              !controller.isLoadingStorage &&
              controller.diningTableSyncHooks is TableKitchenBridge,
          'real bridge mounted',
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
          await controller.openDiningTable('1');
          controller.addProduct(product);
          controller.addProduct(product);
        });
        await until(() async {
          final saved = await storage.loadDiningTableSessions();
          return saved.singleOrNull?.seatingState == 'open';
        }, 'real open ACK persisted before leaving');
        await drive(() => coordinator.settled);
        final bridge = controller.diningTableSyncHooks as TableKitchenBridge;
        server.armed = true;
        final leaving = Stopwatch()..start();
        await drive(controller.returnToDiningFloorPlan);
        expect(leaving.elapsed, lessThan(const Duration(seconds: 8)));
        expect(controller.activeDiningTableId, isNull);
        await drive(() async {
          await bridge.settled;
          await coordinator.settled;
        });
        expect(server.delayed, true);
        expect(
          server.delayClock.elapsed,
          greaterThan(const Duration(seconds: 8)),
        );
        final rounds = await drive(() => storage.readLocalTableRounds());
        expect(rounds, hasLength(1));
        expect(rounds.single.status, 'appended');
        expect(rounds.single.serverRoundId, 1);
        final roundRow = await drive(
          () => outbox.rowForKey(rounds.single.outboxKey),
        );
        expect(roundRow!.syncedAt, isNotNull);
        expect(
          server.events.where((e) => e['event_type'] == 'table.session.round'),
          hasLength(1),
        );
        expect(
          server.events.where(
            (e) =>
                e['event_type'] == 'order.pay' ||
                e['event_type'] == 'order.void',
          ),
          isEmpty,
        );
        expect(await drive(() => localDb.query('order_history')), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
