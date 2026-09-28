import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/providers/providers.dart';
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

const _closedBill = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

class _ClosedBillServer extends AckServer {
  _ClosedBillServer() {
    paid = true;
    uuid = _closedBill;
  }
  final pushes = <Map<String, dynamic>>[];
  Completer<void>? detailGate;
  int heldDetails = 0;

  /// After the discard the server is reachable again: everything that is still
  /// real pending work may sync; archived requests must never be sent.
  bool acceptPushes = false;

  @override
  Dio dio() {
    final delegate = super.dio();
    return Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (o.path.endsWith('/verify-manager-pin')) {
              pinCalls++;
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'ok': pinAccepted,
                    'staff': {'id': 19, 'name': 'Verified Manager'},
                  },
                ),
              );
              return;
            }
            final gate = detailGate;
            if (o.path.endsWith('/detail') && gate != null) {
              heldDetails++;
              await gate.future;
            }
            final body = o.data;
            if (body is Map && body['events'] is List && acceptPushes) {
              pushes.addAll(
                (body['events'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              h.resolve(await delegate.fetch<dynamic>(o));
              return;
            }
            if (body is Map && body['events'] is List) {
              pushes.addAll(
                (body['events'] as List).map(
                  (e) => Map<String, dynamic>.from(e as Map),
                ),
              );
              h.reject(
                DioException(
                  requestOptions: o,
                  type: DioExceptionType.connectionError,
                ),
              );
              return;
            }
            final response = await delegate.fetch<dynamic>(o);
            h.resolve(response);
          },
        ),
      );
  }

  @override
  Future<Map<String, dynamic>?> closedTableBill(String id, int table) async => {
    'uuid': _closedBill,
    'table_id': 1,
    'order_type': 'dine_in',
    'status': 'paid',
    'receipt_number': 'TEST-CLOSED-77',
    'grand_total_baisas': 945,
    'items': [],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  // Fix 10 (F-60, O-21): the same real discard flow as the S1 test; after the
  // manager approves, archived requests are no longer pending work anywhere.
  for (final scenario in ['approve menu', 'approve Clear Table']) {
    testWidgets('F60 real discard $scenario leaves no pending work and records approver', (
      tester,
    ) async {
      Future<void> until(FutureOr<bool> Function() condition, String reason) =>
          pumpUntilRealCondition(
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
        await until(() => done, 'real storage/controller operation');
        if (error != null) Error.throwWithStackTrace(error!, stack!);
        return value;
      }

      Future<void> tap(Finder finder) async {
        await until(
          () => finder.hitTestable().evaluate().isNotEmpty,
          'control ready: $finder',
        );
        await tester.runAsync(() => tester.tap(finder));
        await tester.pump();
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
      var mode = 'live';
      final server = _ClosedBillServer()
        ..pinAccepted = scenario != 'manager refusal';
      final api = PosApiService(
        tokenGetter: () => 'fixture',
        dio: server.dio(),
      );
      late Database localDb;
      late AppDatabase driftDb;
      late LocalOrderStorageService storage;
      late OrderSyncRepository outbox;
      late ProviderContainer outboxContainer;
      late TableSyncCoordinator coordinator;
      final boards = StreamController<RemoteTableSnapshot>.broadcast();
      await drive(() async {
        databaseFactory = databaseFactoryFfi;
        final directory = await Directory.systemTemp.createTemp(
          'fix9-discard-',
        );
        await databaseFactory.setDatabasesPath(directory.path);
        localDb = await realLocalDatabase();
        storage = LocalOrderStorageService.forTesting(localDb);
        await storage.refreshRecoveryGuard();
        driftDb = AppDatabase.forTesting(
          NativeDatabase(File('${directory.path}/outbox.sqlite')),
        );
        debugOrderStorageOverride = storage;
        outboxContainer = ProviderContainer(
          overrides: [
            apiServiceProvider.overrideWithValue(api),
            appDatabaseProvider.overrideWithValue(driftDb),
          ],
        );
        outbox = outboxContainer.read(orderSyncRepositoryProvider);
        coordinator = TableSyncCoordinator(
          outbox: outbox,
          store: storage,
          loadSessions: storage.loadDiningTableSessions,
          mode: () => mode,
          degraded: () => false,
          staffId: () => 7,
          markPrinted: (_) async {},
        );
      });
      debugOrderStorageOverride = storage;
      addTearDown(() async {
        if (server.detailGate case final gate?) {
          if (!gate.isCompleted) gate.complete();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
        debugOrderStorageOverride = null;
        await drive(() async {
          await coordinator.settled;
          await coordinator.dispose();
          outboxContainer.dispose();
          await outbox.dispose();
          await driftDb.close();
          await localDb.close();
          await boards.close();
        });
      });
      Future<PosController> mount() async {
        await pumpWorkspaceMachine(
          tester,
          mode: mode,
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
        final PosController c = host.controller;
        await until(
          () =>
              !c.isLoadingStorage &&
              (mode != 'live' || c.diningTableSyncHooks != null),
          'real controller mounted',
        );
        c.applyCatalog(
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
        c.printReceipts = false;
        c.printKitchenTickets = false;
        return c;
      }

      final first = await mount();
      await drive(() async {
        await first.openDiningTable('1');
        first.addProduct(product);
      });
      await until(() async {
        final rows = await localDb.query('dining_tables');
        if (rows.length != 1 || rows.single['draft_json'] == null) return false;
        final saved = jsonDecode(rows.single['draft_json'] as String) as Map;
        return (saved['serverOrderUuid'] as String? ?? '').isNotEmpty;
      }, 'live coordinator identity persisted with the unsent draft');
      await drive(() async {
        await coordinator.settled;
        // The live open allocated and saved its identity, but the HTTP
        // boundary was unreachable. Leave without auto-sending merchandise.
        mode = 'off';
        await first.returnToDiningFloorPlan();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      var original = await drive(() => localDb.query('dining_tables'));
      expect(original, hasLength(1));
      final draft = jsonDecode(original.single['draft_json'] as String) as Map;
      final localUuid = draft['serverOrderUuid'] as String;
      final localReference = original.single['order_reference'] as String;
      expect(localUuid, isNot(_closedBill));
      expect((draft['items'] as List), hasLength(1));
      // Real immutable outbox rows model the local unsent operation, or its own
      // unsynced tender. No test SQL edits any of the originals.
      final event = {
        'client_event_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
        'event_type': scenario == 'own tender' ? 'order.pay' : 'order.hold',
        'client_timestamp': DateTime.now().toUtc().toIso8601String(),
        'payload': {
          'order_uuid': localUuid,
          if (scenario == 'own tender')
            'payments': [
              {'method': 'cash', 'amount_baisas': 2700},
            ],
        },
      };
      await drive(() => outbox.enqueueEvent(localUuid, event));
      final originalOutbox = await drive(() => outbox.rowForKey(localUuid));
      mode = 'live';
      final c = await mount();
      await drive(() => c.selectOrderType(OrderType.dineIn));
      boards.add(
        RemoteTableSnapshot(
          tables: {1: RemoteTableState(tableId: 1, fetchedAt: DateTime.now())},
        ),
      );
      await until(
        () => find.text('Table 1').hitTestable().evaluate().isNotEmpty,
        'saved occupied tile',
      );
      Future<void> settleTableWork() => drive(() async {
        final hooks = c.diningTableSyncHooks;
        if (hooks is TableKitchenBridge) await hooks.settled;
        await coordinator.settled;
        await outbox.flush();
      });
      await settleTableWork();
      var priorPushes = jsonEncode(server.pushes);
      if (scenario == 'own tender') {
        await tester.longPress(find.text('Table 1').first);
        await until(
          () => find.byType(BottomSheet).evaluate().isNotEmpty,
          'own-tender table actions',
        );
        expect(
          find.byKey(const ValueKey('table-action-discard-copy')),
          findsNothing,
        );
        await tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text(L10nEn().commonCancel),
          ),
        );
      }
      if (scenario == 'approve Clear Table' ||
          scenario == 'own tender' ||
          scenario == 'network timeout') {
        await tap(find.text('Table 1').first);
        await until(
          () => find.text('Clear Table').hitTestable().evaluate().isNotEmpty,
          'closed-copy Clear Table',
        );
        // Reopening is itself a normal persisted draft update. Await its
        // actual SQLite save (not a delay) before taking the action baseline.
        await until(() async {
          final rows = await localDb.query('dining_tables');
          return rows.single['updated_at'] != original.single['updated_at'];
        }, 'reopened draft persisted');
        await settleTableWork();
        original = await drive(() => localDb.query('dining_tables'));
        priorPushes = jsonEncode(server.pushes);
        if (scenario == 'network timeout') {
          final beforeTimeout = await drive(
            () => localDb.query('dining_tables'),
          );
          server.detailGate = Completer<void>();
          final elapsed = Stopwatch()..start();
          await tap(find.text('Clear Table').last);
          await until(
            () => find.textContaining('took too long').evaluate().isNotEmpty,
            'bounded unreachable-server feedback',
          );
          expect(elapsed.elapsed, lessThan(const Duration(seconds: 10)));
          expect(server.heldDetails, greaterThan(0));
          expect(
            await drive(() => localDb.query('dining_tables')),
            beforeTimeout,
          );
          expect(
            await drive(() => localDb.query('draft_recovery_closed_archive')),
            isEmpty,
          );
          server.detailGate!.complete();
          server.detailGate = null;
        }
        await tap(find.text('Clear Table').last);
      } else {
        await tester.longPress(find.text('Table 1').first);
        await tester.pumpAndSettle();
        await tap(find.byKey(const ValueKey('table-action-discard-copy')));
      }
      final confirm = find.byKey(const ValueKey('confirm-discard-saved-copy'));
      if (scenario == 'own tender') {
        await until(
          () =>
              find.textContaining('Check payment result').evaluate().isNotEmpty,
          'own tender recovery explanation',
        );
        expect(confirm, findsNothing);
        expect(find.textContaining(localReference), findsWidgets);
        expect(server.pinCalls, 0);
        final blocked = await drive(() => localDb.query('dining_tables'));
        expect(blocked, original);
        expect(jsonEncode(server.pushes), priorPushes);
        expect(blocked.single['draft_json'], original.single['draft_json']);
        expect(blocked.single['order_reference'], localReference);
        original = blocked;
        priorPushes = jsonEncode(server.pushes);
      } else {
        await until(
          () => confirm.hitTestable().evaluate().isNotEmpty,
          'manager-discard review',
        );
        expect(find.textContaining(localReference), findsWidgets);
        expect(find.textContaining('Coffee'), findsWidgets);
        expect(find.textContaining('TEST-CLOSED-77'), findsWidgets);
        if (scenario == 'approve Clear Table' ||
            scenario == 'network timeout') {
          // Returning to the floor for review flushes the same active draft.
          // It may advance the save timestamp, but no order content may change.
          final review = await drive(() => localDb.query('dining_tables'));
          expect(review.single['draft_json'], original.single['draft_json']);
          expect(review.single['order_reference'], localReference);
          original = review;
          priorPushes = jsonEncode(server.pushes);
        }
        expect(await drive(() => localDb.query('dining_tables')), original);
        await tap(confirm);
        await until(
          () => find.text(L10nEn().posManagerPinTitle).evaluate().isNotEmpty,
          'existing manager PIN gate',
        );
        for (final digit in ['1', '2', '3', '4']) {
          await tap(
            find
                .descendant(of: find.byType(Dialog), matching: find.text(digit))
                .last,
          );
        }
        await tap(find.text(L10nEn().posManagerPinVerify).last);
        await until(() => server.pinCalls == 1, 'manager response');
        if (scenario == 'manager refusal') {
          await tap(
            find
                .descendant(
                  of: find.byType(Dialog),
                  matching: find.text(L10nEn().commonCancel),
                )
                .last,
          );
        } else {
          await until(
            () async =>
                (await localDb.query('dining_tables')).isEmpty &&
                c.diningSessionFor('1') == null,
            'manager discard frees table',
          );
        }
      }
      final archives = await drive(
        () => localDb.query('draft_recovery_closed_archive'),
      );
      final approved =
          scenario.startsWith('approve') || scenario == 'network timeout';
      if (approved) {
        expect(archives, hasLength(1));
        final archived =
            jsonDecode(archives.single['local_json'] as String) as Map;
        expect((archived['rows'] as List).single['row'], original.single);
        expect(
          (archived['outbox'] as List).singleWhere(
            (row) => row['key'] == localUuid,
          )['events_json'],
          originalOutbox!.eventsJson,
        );
        final beforeArchivedFlush = jsonEncode(server.pushes);
        expect(await drive(outbox.pendingRows), isEmpty);
        await drive(outbox.flush);
        expect(
          jsonEncode(server.pushes),
          beforeArchivedFlush,
          reason: 'Archived requests cannot be sent by a later flush',
        );

        // ---- F-60: nothing archived is pending anywhere, even once the server
        // is reachable and every remaining request has had its chance to sync.
        final archivedKeys = [
          for (final row in (archived['outbox'] as List).cast<Map>())
            row['key'] as String,
        ];
        expect(archivedKeys, contains(localUuid));
        expect(
          archivedKeys.any((key) => key.startsWith('tbl:')),
          isTrue,
          reason: 'the live open left an unsynced table-session request',
        );
        server.acceptPushes = true;
        final beforeReachableFlush = jsonEncode(server.pushes);
        await drive(outbox.flush);
        expect(
          jsonEncode(server.pushes),
          beforeReachableFlush,
          reason: 'A reachable server still receives no archived request',
        );
        final all = await drive(outbox.allRows);
        for (final key in archivedKeys) {
          final row = all.singleWhere((r) => r.orderUuid == key);
          expect(
            row.syncedAt,
            isNull,
            reason: 'Discard is not a fabricated server acknowledgement',
          );
        }
        final pending = await drive(() => outbox.watchPending().first);
        expect(
          pending.where((r) => archivedKeys.contains(r.orderUuid)),
          isEmpty,
          reason: 'archived requests are not pending work',
        );
        // The staff screen's pending-table rule (table.session.* with a table id).
        final pendingTables = <String>{
          for (final row in pending)
            for (final e
                in (jsonDecode(row.eventsJson) as List).whereType<Map>())
              if ((e['event_type']?.toString() ?? '').startsWith(
                    'table.session.',
                  ) &&
                  (e['payload'] as Map?)?['table_id'] != null)
                (e['payload'] as Map)['table_id'].toString(),
        };
        expect(pendingTables, isNot(contains('1')));
        expect(await drive(() => outbox.watchStuck().first), isEmpty);
        expect(await drive(() => outbox.watchAttention().first), isEmpty);
        expect(await drive(outbox.stuckBatches), isEmpty);
        // The real degraded-table controller, in a real-time zone (the widget
        // zone does not deliver Drift streams), once the archived rows are older
        // than its 20-second "old queued work" threshold.
        final oldest = all
            .where((r) => archivedKeys.contains(r.orderUuid))
            .map((r) => r.createdAt)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        while (DateTime.now().difference(oldest) <=
            const Duration(seconds: 21)) {
          await drive(() => Future<void>.delayed(const Duration(seconds: 2)));
        }
        late TableDegradedState degradedState;
        await tester.runAsync(() async {
          final real = ProviderContainer(
            overrides: [
              apiServiceProvider.overrideWithValue(api),
              appDatabaseProvider.overrideWithValue(driftDb),
              tableSessionsModeProvider.overrideWithValue('live'),
              connectivityProvider.overrideWith((ref) => Stream.value(true)),
              remoteBoardProvider.overrideWith(
                (ref) => Stream.value(const RemoteTableSnapshot()),
              ),
            ],
          );
          final sub = real.listen(degradedStateProvider, (_, _) {});
          await Future<void>.delayed(const Duration(seconds: 7));
          degradedState = real.read(degradedStateProvider);
          sub.close();
          real.dispose();
        });
        expect(degradedState.degraded, isFalse);
        expect(degradedState.queuedActions, 0);
        expect(degradedState.parkedActions, 0);
        expect(degradedState.hasWarning, isFalse);

        // ---- O-21: the archive records who approved (verified manager PIN).
        final proof =
            jsonDecode(archives.single['proof_json'] as String) as Map;
        expect(proof['authority'], 'existing_manager_approval');
        expect(proof['approved_by'], {
          'method': 'manager_pin',
          'staff_id': 19,
          'name': 'Verified Manager',
        });
      } else {
        expect(archives, isEmpty);
        expect(await drive(() => localDb.query('dining_tables')), original);
      }
      final afterOutbox = await drive(() => outbox.rowForKey(localUuid));
      expect(afterOutbox!.eventsJson, originalOutbox!.eventsJson);
      expect(
        afterOutbox.syncedAt,
        isNull,
        reason: 'Discard is not a fabricated server acknowledgement',
      );
      expect(await drive(() => localDb.query('order_history')), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    });
  }
}
