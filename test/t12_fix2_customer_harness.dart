import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
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

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/services/local_storage_service.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';

// HTTP-only model of the four real API handlers named in the fix order.
// Exact phone lookup, per-customer accounts, failed ACKs and clamped debits.
class CustomerServer {
  final customers = <int, Map<String, dynamic>>{
    5: {
      'id': 5,
      'name': 'Customer A',
      'phone': '+968 9000 0001',
      'plates': ['A123'],
    },
    6: {
      'id': 6,
      'name': 'Customer B',
      'phone': '+968 9000 0002',
      'plates': ['B123'],
    },
    7: {'id': 7, 'name': 'No account', 'phone': '+968 9000 0003', 'plates': []},
  };
  final balances = <int, Map<int, List<int>>>{
    5: {
      11: [200, 10],
    },
    6: {
      11: [400, 15],
    },
  };
  final events = <Map<String, dynamic>>[];
  final posts = <Map<String, dynamic>>[];
  final orders = <String, Map<String, dynamic>>{};
  final acknowledgements = <String, Map<String, dynamic>>{};
  final requestPaths = <String>[];
  int allocations = 0;
  Map<String, dynamic> profile(int id) => {
    ...customers[id]!,
    'loyalty': [
      for (final e in (balances[id] ?? <int, List<int>>{}).entries)
        {
          'rule_id': e.key,
          'points': e.value[0],
          'stamps': e.value[1],
          'available_points': e.value[0],
          'available_stamps': e.value[1],
        },
    ],
  };
  Map<String, dynamic> acknowledge(Map<String, dynamic> event) {
    final key = event['client_event_id'] as String;
    if (acknowledgements.containsKey(key)) return acknowledgements[key]!;
    final payload = Map<String, dynamic>.from(event['payload'] as Map);
    String? error;
    String? warning;
    final kind = event['event_type'];
    String? uuid = payload['order_uuid'] as String?;
    if (kind == 'order.create') {
      final order = Map<String, dynamic>.from(payload['order'] as Map);
      uuid = order['uuid'] as String;
      if (order['customer_id'] != null &&
          !customers.containsKey(order['customer_id'])) {
        error = 'order references a customer outside the device tenant';
      } else {
        orders[uuid] = order;
      }
    } else if (kind == 'order.pay') {
      final order = orders[uuid];
      if (order == null) {
        error = 'order not found';
      }
      final redeem = payload['loyalty_redeem'] as Map?;
      if (error == null && redeem != null) {
        final customer = order!['customer_id'] as int?;
        final balance = balances[customer]?[redeem['rule_id']];
        if (customer == null) {
          error = 'cannot redeem loyalty without a customer on the order';
        } else if (balance == null) {
          error = 'no loyalty account to redeem from';
        } else {
          final points = (redeem['points'] as num).toInt();
          final stamps = (redeem['stamps'] as num).toInt();
          if (points > balance[0] || stamps > balance[1]) {
            warning = '[LOYALTY_REDEMPTION_SHORTFALL][REVIEW_REQUIRED]';
          }
          balance[0] = (balance[0] - points).clamp(0, 1 << 30);
          balance[1] = (balance[1] - stamps).clamp(0, 1 << 30);
        }
      }
      // Fixture earn rules use points_per_omr=0 / no earn on this fixture bill.
      // Debit balances therefore expose exactly which customer's account moved.
    }
    final ack = <String, dynamic>{
      'client_event_id': key,
      'status': error == null ? 'processed' : 'failed',
      'result': {
        'error': ?error,
        'order_uuid': uuid,
        if (kind == 'order.pay' && error == null) ...{
          'status': 'paid',
          'order_id': 65,
          'receipt_number': 'TEST-0001',
        },
        'loyalty_redeem_warning': ?warning,
      },
    };
    acknowledgements[key] = ack;
    return ack;
  }

  Dio dio() {
    final d = Dio();
    d.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) async {
          requestPaths.add('${o.method} ${o.path}');
          dynamic value;
          if (o.path.endsWith('/device/customers/search')) {
            final q =
                (o.queryParameters['q'] ?? o.queryParameters['query'] ?? '')
                    .toString()
                    .toLowerCase();
            value = {
              'customers': [
                for (final c in customers.values)
                  if (c['name'].toString().toLowerCase().contains(q) ||
                      c['phone']
                              .toString()
                              .replaceAll(RegExp(r'\D'), '')
                              .contains(q.replaceAll(RegExp(r'\D'), '')) &&
                          RegExp(r'\d').hasMatch(q) ||
                      (c['plates'] as List).any(
                        (p) => p.toString().toLowerCase().contains(q),
                      ))
                    profile(c['id'] as int),
              ],
            };
          } else if (o.method == 'POST' &&
              o.path.endsWith('/device/customers')) {
            final data = Map<String, dynamic>.from(o.data as Map);
            posts.add(data);
            final existing = customers.values.where(
              (c) => c['phone'] == data['phone'],
            );
            final id = existing.isEmpty
                ? 900 + posts.length
                : existing.first['id'] as int;
            customers.putIfAbsent(
              id,
              () => {
                'id': id,
                'name': data['name'],
                'phone': data['phone'],
                'plates': [],
              },
            );
            if (data['plate_number'] != null) {
              (customers[id]!['plates'] as List).add(data['plate_number']);
            }
            value = {'customer': profile(id)};
          } else if (RegExp(r'/device/customers/\d+$').hasMatch(o.path)) {
            value = {'customer': profile(int.parse(o.path.split('/').last))};
          } else if (o.path.endsWith('/device/orders/next-number')) {
            allocations++;
            value = {'number': allocations, 'formatted': 'TEST-$allocations'};
          } else if (o.path.contains('/tables')) {
            value = {'tables': [], 'sessions': []};
          } else if (o.path.endsWith('/incoming')) {
            value = {'transfers': []};
          }
          if (o.data is Map && (o.data as Map).containsKey('events')) {
            final results = <Map<String, dynamic>>[];
            for (final raw in (o.data['events'] as List).cast<Map>()) {
              final event = Map<String, dynamic>.from(raw);
              events.add(event);
              results.add(acknowledge(event));
            }
            value = {'results': results};
          }
          h.resolve(
            Response(
              requestOptions: o,
              statusCode: 200,
              data: {'data': value ?? {}},
            ),
          );
        },
      ),
    );
    return d;
  }
}

Future<Database> realLocalDatabase() async {
  final db = await databaseFactoryFfi.openDatabase(
    '${await databaseFactoryFfi.getDatabasesPath()}/fix2-local.sqlite',
  );
  await db.execute(
    'CREATE TABLE order_history (id TEXT PRIMARY KEY, order_number INTEGER NOT NULL, order_type TEXT NOT NULL, created_at TEXT NOT NULL, snapshot_json TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE held_orders (id TEXT PRIMARY KEY, order_number INTEGER, order_reference TEXT NOT NULL, order_type TEXT NOT NULL, held_at TEXT NOT NULL, draft_json TEXT NOT NULL)',
  );
  await db.execute(
    'CREATE TABLE dining_tables (table_id TEXT PRIMARY KEY, floor_id TEXT NOT NULL, status TEXT NOT NULL, order_number INTEGER, order_reference TEXT, updated_at TEXT NOT NULL, occupied_at TEXT, paid_at TEXT, draft_json TEXT, paid_snapshot_json TEXT, primary_table_id TEXT, linked_table_ids_json TEXT)',
  );
  await LocalOrderStorageService.createRemoteTables(db);
  await LocalOrderStorageService.createTableLedger(db);
  await LocalOrderStorageService.createRemoteBillIdentity(db);
  await CombineStore.createSchema(db);
  await RecoveryStore.createSchema(db);
  return db;
}

class CustomerRig {
  CustomerRig(
    this.tester, {
    this.arabic = false,
    this.stamps = false,
    this.width = 1600,
    this.gpsDelay = false,
  });
  final WidgetTester tester;
  final bool arabic, stamps, gpsDelay;
  final double width;
  final server = CustomerServer();
  late Database localDb;
  late AppDatabase driftDb;
  late LocalOrderStorageService storage;
  late OrderSyncRepository outbox;
  late TableSyncCoordinator coordinator;
  late PosController c;
  final boards = StreamController<RemoteTableSnapshot>.broadcast();
  int cardCalls = 0, printerCalls = 0, gpsCalls = 0;
  int measuredGpsMillis = 0;
  L10n get l => L10n.of(tester.element(find.byType(StaffPosScreen)));
  Future<T?> drive<T>(Future<T> Function() action) async {
    bool done = false;
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
      reason: 'real operation finished',
    );
    if (error != null) Error.throwWithStackTrace(error!, trace!);
    return value;
  }

  Future<void> settle([int frames = 6]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await drive(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    }
  }

  Future<void> tap(Finder target) async {
    await pumpUntilRealCondition(
      tester,
      () => target.hitTestable().evaluate().isNotEmpty,
      reason: '${target.toString()} reachable',
    );
    await tester.tap(target.hitTestable().first);
    await settle();
  }

  Future<void> start() async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    void channel(String name, Future<dynamic> Function(MethodCall) handle) {
      final ch = MethodChannel(name);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, handle);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ch, null),
      );
    }

    channel(
      'plugins.it_nomads.com/flutter_secure_storage',
      (call) async => call.method == 'read' ? 'fixture' : null,
    );
    channel(
      'pos_machine/rear_display_host',
      (call) async => <Map<String, dynamic>>[],
    );
    channel('com.example.mosambee', (call) async {
      if (call.method != 'prepareLogin') cardCalls++;
      return jsonEncode({
        'status': 'success',
        'responseCode': '00',
        'rrn': 'TEST-RRN',
      });
    });
    channel('com.example.manager_biometrics', (call) async => true);
    channel('sunmi_printer_plus', (call) async {
      printerCalls++;
      return true;
    });
    channel('flutter.baseflow.com/geolocator', (call) async {
      if (call.method == 'getCurrentPosition') {
        gpsCalls++;
        if (gpsDelay) {
          final elapsed = Stopwatch()..start();
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          measuredGpsMillis = elapsed.elapsedMilliseconds;
        }
      }
      if (call.method == 'getCurrentPosition' ||
          call.method == 'getLastKnownPosition') {
        return {
          'latitude': 23.6,
          'longitude': 58.4,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'accuracy': 1.0,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
        };
      }
      return true;
    });
    await drive(() async {
      databaseFactory = databaseFactoryFfi;
      final dir = await Directory.systemTemp.createTemp('t12-fix2-');
      await databaseFactory.setDatabasesPath(dir.path);
      localDb = await realLocalDatabase();
      storage = LocalOrderStorageService.forTesting(localDb);
      await storage.refreshRecoveryGuard();
      driftDb = AppDatabase.forTesting(
        NativeDatabase(File('${dir.path}/drift.sqlite')),
      );
      outbox = OrderSyncRepository(
        PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
        driftDb,
      );
      outbox.addAckListener(ServerReceiptHistory(storage).acknowledge);
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
      await tester.pump();
      debugOrderStorageOverride = null;
      await drive(() async {
        await coordinator.dispose();
        await outbox.dispose();
        await driftDb.close();
        await localDb.close();
        await boards.close();
      });
    });
    await mount();
  }

  Future<void> restart() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await drive(() async {
      await coordinator.settled;
    });
    await mount();
  }

  Future<void> mount() async {
    final harness = await pumpWorkspaceMachine(
      tester,
      mode: 'off',
      toggle: false,
      arabic: arabic,
      realServices: true,
      realTableHealth: true,
      wrapStaff: (child) => MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(0.8)),
        child: child,
      ),
      api: PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
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
    await harness.preferences.setBool('manager_biometric_registered', true);
    await drive(
      () => LocalStorageService.saveSoftposProfile(
        SoftPosProfile.fromJson({
          'provider': 'mosambee_dhofar',
          'enabled': true,
          'package_name': 'com.mosambee.dhofar.softpos',
        }),
      ),
    );
    final dynamic host = tester.state(find.byType(StaffPosScreen));
    c = host.controller;
    await pumpUntilRealCondition(
      tester,
      () => !c.isLoadingStorage,
      reason: 'SQLite startup complete',
    );
    c.applyCatalog(
      categories: const ['Drinks'],
      products: const [coffee],
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
        DiningTableDefinition(
          id: '2',
          floorId: '1',
          name: 'Table 2',
          sizeLabel: 'square',
          seats: 4,
          sortOrder: 2,
        ),
      ],
      taxes: const [],
      deliveryProviders: const [DeliveryProvider(id: 1, name: 'Test Delivery')],
    );
    c.loyaltyRules = [
      LoyaltyRule(
        id: 11,
        name: stamps ? 'Stamps' : 'Points',
        type: stamps ? 'visit_based' : 'spend_based',
        config: stamps
            ? {
                'stamps_required': 5,
                'reward_type': 'fixed',
                'reward_value': '0.500',
                'min_order_value': '999',
              }
            : {
                'redemption_points': 100,
                'redemption_value': '0.500',
                'points_per_omr': 0,
              },
      ),
      const LoyaltyRule(
        id: 12,
        name: 'Other program',
        type: 'spend_based',
        config: {'points_per_omr': 0},
      ),
    ];
    c.printReceipts = false;
    c.printKitchenTickets = false;
    await settle();
  }

  static const coffee = Product(
    id: '10',
    name: 'Coffee',
    category: 'Drinks',
    price: 2.7,
  );
  Future<void> add() async {
    c.addProduct(coffee);
    await settle();
  }

  Future<void> payPage() => tap(find.text(l.posPayBtnProcessToPay));
  Future<void> chooseEarn() async {
    if (find.byType(CheckboxListTile).evaluate().isEmpty) return;
    await tap(find.widgetWithText(CheckboxListTile, 'Other program'));
    await tap(find.widgetWithText(FilledButton, l.posEarnPickerConfirm));
    expect(c.selectedEarnRuleIds, [11]);
  }

  Future<void> attach([int id = 5]) async {
    await tap(find.byTooltip(l.posCustomerSearchOption));
    await tester.enterText(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(TextField),
      ),
      (server.customers[id]!['phone'] as String).replaceAll(RegExp(r'\D'), ''),
    );
    await tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, l.posCustomerSearchButton),
      ),
    );
    await tap(find.text(server.customers[id]!['name'] as String));
    await chooseEarn();
    expect(c.selectedCustomer?.id, id);
  }

  Future<void> redeem() async {
    await tap(find.text(l.posPaymentAddDiscount));
    await tap(
      find.text(
        stamps
            ? l.posDiscountRedeemStampOption
            : l.posDiscountRedeemPointsOption,
      ),
    );
    await tap(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.widgetWithText(FilledButton, l.posRedeemConfirm),
      ),
    );
    expect(c.loyaltyRedeemRuleId, 11);
  }

  Future<void> exit({bool cancel = false}) async {
    if (cancel) {
      await tap(
        find.widgetWithText(
          findType('_PaymentBottomActionButton'),
          l.commonCancel,
        ),
      );
    } else {
      await tap(find.byIcon(Icons.arrow_back_rounded).first);
    }
  }

  Type findType(String name) => tester.allWidgets
      .firstWhere((w) => w.runtimeType.toString() == name)
      .runtimeType;
  Future<void> closeNotice() async {
    final close = find.byIcon(Icons.close_rounded).hitTestable();
    if (close.evaluate().isNotEmpty &&
        find.byType(Dialog).evaluate().isNotEmpty) {
      await tap(close.last);
    }
  }

  Future<void> cash() async {
    await tap(find.text('10 OMR'));
    await tap(
      find.ancestor(
        of: find.text(l.posPaymentCash),
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_PaymentMethodActionButton',
        ),
      ),
    );
  }

  Future<void> checkMoney(
    String name, {
    int? customer = 5,
    bool redeem = true,
    int posts = 0,
    List<int>? earn,
    bool gift = false,
    bool delivery = false,
  }) async {
    final finalEvent = delivery ? 'order.deliver' : 'order.pay';
    await pumpUntilRealCondition(
      tester,
      () => server.events.any((e) => e['event_type'] == finalEvent),
      reason: 'real outbox pushed payment',
    );
    await pumpUntilRealCondition(
      tester,
      () => !c.isProcessingPayment && c.cart.isEmpty,
      reason: 'completion resets order',
    );
    await drive(() async {
      await coordinator.settled;
      await outbox.flush();
    });
    final creates = server.events
        .where((e) => e['event_type'] == 'order.create')
        .toList();
    final pays = server.events
        .where((e) => e['event_type'] == finalEvent)
        .toList();
    expect(creates, hasLength(1));
    expect(pays, hasLength(1));
    for (final event in server.events.where(
      (e) => e['event_type'] == 'order.hold',
    )) {
      final held = event['payload']['order'] as Map;
      for (final field in [
        'customer',
        'customer_id',
        'earnRuleIds',
        'loyaltyRedeemCustomerId',
      ]) {
        expect(
          held.containsKey(field),
          false,
          reason: 'hold wire stays unchanged',
        );
      }
    }
    final order = creates.single['payload']['order'] as Map;
    final pay = pays.single['payload'] as Map;
    final ack = server.acknowledgements[pays.single['client_event_id']]!;
    final expectedRedeem = redeem
        ? {'rule_id': 11, 'points': stamps ? 0 : 100, 'stamps': stamps ? 5 : 0}
        : null;
    final expectedEarn = delivery
        ? <int>[]
        : earn ?? (customer == null || gift ? <int>[] : [11]);
    final measurements = {
      'case': name,
      'customer_id': order['customer_id'],
      'loyalty_redeem': pay['loyalty_redeem'],
      'discount_baisas': order['discount_total_baisas'],
      'loyalty_rule_ids': pay['loyalty_rule_ids'] ?? [],
      'pay_count': delivery ? 0 : pays.length,
      'deliver_count': delivery ? pays.length : 0,
      'ack': ack['status'],
      'customer_posts': server.posts,
      'balances': server.balances.map(
        (k, v) =>
            MapEntry(k.toString(), v.map((r, b) => MapEntry(r.toString(), b))),
      ),
    };
    // ignore: avoid_print
    print('FIX2_MONEY ${jsonEncode(measurements)}');
    expect(order['customer_id'], customer);
    expect(pay['loyalty_redeem'], expectedRedeem);
    expect(order['discount_total_baisas'], redeem ? 500 : 0);
    expect(pay['loyalty_rule_ids'] ?? [], expectedEarn);
    expect(ack['status'], 'processed');
    expect(server.posts, hasLength(posts));
    expect(server.balances[5]![11], [
      200 - (redeem && customer == 5 && !stamps ? 100 : 0),
      10 - (redeem && customer == 5 && stamps ? 5 : 0),
    ]);
    expect(server.balances[6]![11], [
      400 - (redeem && customer == 6 && !stamps ? 100 : 0),
      15 - (redeem && customer == 6 && stamps ? 5 : 0),
    ]);
  }
}
