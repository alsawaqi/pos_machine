import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';
import 'package:pos_machine/draft_recovery/recovery_preparation_gate.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'draft_recovery_test.dart';
import 'support/fake_order_storage.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, TableHttp;

class GuardedMemory extends FakeOrderStorage implements DraftRecoveryGuard {
  @override
  final ValueNotifier<bool> recoveryBlocked = ValueNotifier(false);
  String? retired;
  @override
  Future<void> refreshRecoveryGuard() async {}
  @override
  Future<void> assertDraftNotRetired({
    String? uuid,
    String? tableId,
    String? reference,
    String? occupiedAt,
    String? seatingKey,
  }) async {
    if (uuid != null && uuid == retired) throw StateError('Retired draft');
  }

  @override
  Future<void> assertNoPendingCombine() async {
    if (recoveryBlocked.value) throw StateError('Pending recovery');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const product = Product(
    id: '7',
    name: 'Coffee',
    category: 'Drinks',
    price: 1,
  );

  test(
    'completed-sale GPS preparation reserves admission before its first outbox call',
    () async {
      final gate = RecoveryPreparationGate(), gps = Completer<void>();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final http = TableHttp();
      final dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))
        ..httpClientAdapter = http;
      var admitted = false;
      final outbox = OrderSyncRepository(
        PosApiService(tokenGetter: () => 'token', dio: dio),
        db,
        mutationGuard: () async {
          if (admitted) throw StateError('Recovery pending');
        },
      );
      addTearDown(() async {
        await outbox.dispose();
        await db.close();
        dio.close();
      });
      final preparing = gate.run(() async {
        await gps.future;
        // Server outcome deliberately does not ACK; durable paid evidence stays.
        await outbox.enqueueEvent('paid-sale', {
          'client_event_id': 'paid-1',
          'event_type': 'order.pay',
          'payload': {'order_uuid': 'sale'},
        });
      });
      expect(gate.pending, 1);
      expect(gate.assertIdle, throwsStateError);
      expect(await outbox.pendingRows(), isEmpty);
      gps.complete();
      await preparing;
      gate.assertIdle();
      await expectLater(
        outbox.admitDraftRecovery(() async {
          admitted = true;
        }),
        throwsStateError,
      );
      expect(admitted, false);
      expect((await outbox.pendingRows()).single.orderUuid, 'paid-sale');
    },
  );

  test(
    'preparation counter survives failure and parallel held/void callbacks',
    () async {
      final gate = RecoveryPreparationGate(), wait = Completer<void>();
      final first = gate.run(() => wait.future);
      await expectLater(
        gate.run<void>(() async => throw StateError('fixture')),
        throwsStateError,
      );
      expect(gate.pending, 1);
      expect(gate.assertIdle, throwsStateError);
      wait.complete();
      await first;
      gate.assertIdle();
    },
  );

  test(
    'pending recovery blocks cart, hold, delivery and cash without losing existing cart',
    () async {
      final store = GuardedMemory();
      final c = PosController(orderStorage: store)
        ..printReceipts = false
        ..printKitchenTickets = false;
      addTearDown(c.dispose);
      c.addProduct(product);
      final before = c.cart.single.toMap();
      var completed = 0;
      c.onOrderCompleted = (_) {
        completed++;
      };
      store.recoveryBlocked.value = true;
      c.addProduct(product);
      c.incrementCartItem(c.cart.single);
      c.decreaseCartItem(c.cart.single);
      c.removeCartItem(c.cart.single);
      c.clearForNextOrder();
      c.setSplitCount(2);
      c.updateCartItemCustomization(
        c.cart.single,
        modifiers: [],
        notes: 'changed',
      );
      c.setCustomerReferenceNumber('999');
      c.setVehiclePlateNumber('ABC');
      c.applyDiscount(
        const DiscountConfiguration(kind: DiscountKind.fixedAmount, value: 1),
      );
      expect(c.prepareTransferDraft(), isNull);
      expect(
        c.receiveTransferredOrder(
          orderUuid: 'other',
          orderType: OrderType.dineIn,
          items: [],
        ),
        false,
      );
      expect(await c.completeTransfer(), false);
      await c.holdCurrentOrder();
      await c.payAndPrint(cashTenderedAmount: 5);
      await c.completeDeliveryOrder(reference: 'delivery');
      expect(c.cart.single.toMap(), before);
      expect(store.history, isEmpty);
      expect(store.held, isEmpty);
      expect(completed, 0);
      expect(c.splitCount, 1);
      expect(c.discount.isActive, false);
      expect(c.lastPaymentMessage, contains('recovery'));
    },
  );

  test(
    'stale held record cannot return a retired UUID to payable cart',
    () async {
      final store = GuardedMemory()..retired = billId;
      final c = PosController(orderStorage: store);
      addTearDown(c.dispose);
      final draft = OrderSessionDraft.fromMap({
        'serverOrderUuid': billId,
        'orderType': 'dine_in',
        'diningTableId': '1',
        'items': [originalItem()],
      });
      await store.saveHeldOrder(draft);
      final old = store.held.single;
      await c.resumeHeldOrder(old);
      var voided = 0;
      c.onOrderVoided = (_, {orderNumber, reason, voidReasonId, authorization}) {
        voided++;
      };
      await c.discardHeldOrder(old);
      expect(c.cart, isEmpty);
      expect(store.held.single, old);
      expect(voided, 0);
    },
  );

  group('real local storage recovery fence', () {
    late RecoveryHarness h;
    late LocalOrderStorageService storage;
    setUp(() async {
      h = RecoveryHarness();
      await h.init();
      storage = LocalOrderStorageService.forTesting(h.db);
    });
    tearDown(() => h.close());
    test('additive v8-to-v9 journal DDL preserves every old raw row', () async {
      await h.db.execute('DROP TABLE draft_recovery_journal');
      await h.db.execute('DROP TABLE draft_recovery_retired');
      await h.db.setVersion(8);
      final names = [
        'held_orders',
        'dining_tables',
        'order_history',
        'local_table_rounds',
        'local_line_cancellations',
        'bill_combine_journal',
      ];
      final before = <String, String>{};
      for (final name in names) {
        before[name] = jsonEncode(await h.db.query(name));
      }
      await RecoveryStore.createSchema(h.db);
      await h.db.setVersion(9);
      for (final name in names) {
        expect(jsonEncode(await h.db.query(name)), before[name]);
      }
      expect(await h.db.getVersion(), 9);
      expect(await h.db.query('draft_recovery_journal'), isEmpty);
      expect(await h.db.query('draft_recovery_retired'), isEmpty);
    });
    Future<void> pending() async {
      await h.controller.start();
      final local = h.controller.local!, preview = h.controller.preview!;
      await h.store.create(
        RecoveryAttempt({
          'id': recoveryId,
          'state': 'pending',
          'local': local.json,
          'preview': preview.json,
          'delta': local.delta(preview),
        }),
      );
      await storage.refreshRecoveryGuard();
    }

    test(
      'startup and admission lock synchronously; malformed terminal remains locked',
      () async {
        expect(storage.recoveryBlocked.value, true);
        await storage.refreshRecoveryGuard();
        expect(storage.recoveryBlocked.value, false);
        storage.beginRecoveryAdmission();
        expect(storage.recoveryBlocked.value, true);
        await expectLater(storage.clearAllData(), throwsStateError);
        await storage.endRecoveryAdmission();
        expect(storage.recoveryBlocked.value, false);
        await h.db.insert('draft_recovery_journal', {
          'id': 'bad',
          'scope': 'other',
          'state': 'done',
          'payload': '{broken',
        });
        await expectLater(
          storage.refreshRecoveryGuard(),
          throwsFormatException,
        );
        expect(storage.recoveryBlocked.value, true);
        await expectLater(
          storage.assertNoPendingCombine(),
          throwsFormatException,
        );
      },
    );
    test(
      'every original-changing local writer refuses pending and preserves raw rows',
      () async {
        final raw = recoveryJson(await h.db.query('held_orders'));
        final local = await h.local(1);
        final draft = OrderSessionDraft.fromMap(
          recoveryMap(local.json['draft']),
        );
        await pending();
        final session = DiningTableSession(
          tableId: '1',
          floorId: '1',
          status: DiningTableStatus.occupied,
          updatedAt: at,
          occupiedAt: at,
          draft: draft,
          serverOrderUuid: billId,
          seatingKey: seatKey,
        );
        final snapshot = OrderSnapshot.fromMap({
          'serverOrderUuid': billId,
          'diningTableId': '1',
        });
        for (final action in <Future<void> Function()>[
          () => storage.saveHeldOrder(draft),
          () => storage.saveDiningTableSession(session),
          () => storage.saveCompletedOrder(snapshot),
          () => storage.clearDiningTable('1'),
          () => storage.deleteHeldOrder('held-1'),
          storage.clearHeldOrders,
          storage.clearAllData,
          () => storage.saveLocalTableRound(
            LocalTableRound.fromRow(local.rounds.single),
          ),
          () => storage.updateTableSyncFields('1', {'seating_key': seatKey}),
        ]) {
          await expectLater(action(), throwsStateError);
        }
        expect(recoveryJson(await h.db.query('held_orders')), raw);
        expect(await h.db.query('draft_recovery_journal'), hasLength(1));
      },
    );
    test(
      'retired UUID/exact generation blocked; reused reference with new generation allowed',
      () async {
        await h.controller.start();
        await h.controller.confirm();
        await h.controller.sendSavedAdditions();
        expect(h.controller.attempt!.state, 'done');
        await storage.refreshRecoveryGuard();
        expect(storage.recoveryBlocked.value, false);
        await expectLater(
          storage.assertDraftNotRetired(uuid: billId),
          throwsStateError,
        );
        await expectLater(
          storage.assertDraftNotRetired(
            tableId: '1',
            occupiedAt: at.toIso8601String(),
          ),
          throwsStateError,
        );
        await expectLater(
          storage.assertDraftNotRetired(tableId: '1', seatingKey: seatKey),
          throwsStateError,
        );
        await expectLater(
          storage.assertDraftNotRetired(tableId: '1'),
          throwsStateError,
        );
        await storage.assertDraftNotRetired(
          uuid: recoveryId,
          tableId: '1',
          reference: 'REF-1',
          occupiedAt: at.add(const Duration(hours: 1)).toIso8601String(),
          seatingKey: requestId,
        );
        await h.db.delete('draft_recovery_retired');
        await expectLater(
          storage.assertDraftNotRetired(uuid: billId),
          throwsStateError,
        );
        await storage.clearAllData();
        expect(await h.db.query('draft_recovery_journal'), hasLength(1));
      },
    );
    test(
      'missing production schema is never an unlocked legacy fallback',
      () async {
        await h.db.execute('DROP TABLE draft_recovery_journal');
        await expectLater(
          storage.refreshRecoveryGuard(),
          throwsA(isA<DatabaseException>()),
        );
        expect(storage.recoveryBlocked.value, true);
        await expectLater(
          storage.clearHeldOrders(),
          throwsA(isA<DatabaseException>()),
        );
        expect(await h.db.query('held_orders'), hasLength(1));
      },
    );
    test(
      'coordinator evicts only old generation and rejects in-flight stale hydrate',
      () async {
        // This focused recovery fixture already has the ledger columns/rounds.
        // hydrate now also recovers durable cancellation verdict intents.
        await h.db.execute('''
          CREATE TABLE table_sync_verdicts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            observed_at TEXT NOT NULL, table_id TEXT NOT NULL, seating_key TEXT,
            event_kind TEXT NOT NULL, outcome TEXT NOT NULL, detail_json TEXT,
            seen INTEGER NOT NULL DEFAULT 0
          )
        ''');
        final drift = AppDatabase.forTesting(NativeDatabase.memory());
        final outbox = OrderSyncRepository(
          PosApiService(tokenGetter: () => 'x'),
          drift,
        );
        final current = DiningTableSession(
          tableId: '1',
          floorId: '1',
          status: DiningTableStatus.occupied,
          updatedAt: at,
          occupiedAt: at,
          orderReference: 'REF-1',
          serverOrderUuid: billId,
          seatingKey: seatKey,
        );
        var sessions = [current];
        Completer<List<DiningTableSession>>? read;
        final coordinator = TableSyncCoordinator(
          outbox: outbox,
          store: storage,
          loadSessions: () => read?.future ?? Future.value(sessions),
          mode: () => 'live',
          degraded: () => false,
          staffId: () => 1,
          markPrinted: (_) async {},
          guardSession: storage.guardTableSession,
        );
        addTearDown(() async {
          await coordinator.dispose();
          await outbox.dispose();
          await drift.close();
        });
        await coordinator.hydrate();
        coordinator.forgetRecoveredSession(
          tableId: '1',
          uuid: 'different',
          occupiedAt: 'different',
          seatingKey: 'different',
        );
        expect(coordinator.cachedSession('1'), same(current));
        read = Completer();
        final hydrating = coordinator.hydrate();
        await h.controller.start();
        await h.controller.confirm();
        await h.controller.sendSavedAdditions();
        coordinator.forgetRecoveredSession(tableId: '1', uuid: billId);
        read.complete([current]);
        await expectLater(hydrating, throwsStateError);
        expect(coordinator.cachedSession('1'), null);
        expect(await outbox.pendingRows(), isEmpty);
        read = null;
        sessions = [
          current.copyWith(
            serverOrderUuid: recoveryId,
            seatingKey: requestId,
            occupiedAt: at.add(const Duration(hours: 1)),
          ),
        ];
        await coordinator.hydrate();
        coordinator.forgetRecoveredSession(
          tableId: '1',
          uuid: billId,
          occupiedAt: at.toIso8601String(),
          seatingKey: seatKey,
        );
        expect(coordinator.cachedSession('1')!.serverOrderUuid, recoveryId);
      },
    );
  });

  testWidgets(
    'separate recovery entry survives detail refusal and re-evaluates local block on return',
    (tester) async {
      final api = TableFake()..failRead = true, store = TableMemory();
      var blocked = true, recovered = 0, controllers = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async {
              controllers++;
              return DineInController(api, store, 2);
            },
            catalogue: () => [],
            label: 'T2',
            localDraftBlocked: true,
            localDraftBlockedNow: () => blocked,
            onPay: (_) async => fail('Not paying'),
            onCombine: () async => fail('Separate action'),
            onRecover: () async {
              recovered++;
              blocked = false;
              api.failRead = false;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dine-combine')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('dine-recover-draft')));
      await tester.pumpAndSettle();
      expect(recovered, 1);
      expect(controllers, 2);
      expect(api.requests, isEmpty);
      expect(
        find.text(
          'A local draft is unresolved. Resolve it first without creating a second bill.',
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
