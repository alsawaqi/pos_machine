import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';

Map<String, dynamic> tableFixture({
  int selected = 2,
  String source = 'qr_web',
  String status = 'open',
  bool pending = false,
}) => {
  'table': {'id': selected, 'label': 'T$selected'},
  'occupied': true,
  'orphaned': false,
  'seating': {
    'uuid': '11111111-1111-4111-8111-111111111111',
    'table_id': 1,
    'status': 'open',
    'temp_reference': 'T-006',
    'joined_table_ids': [2],
  },
  'bill': {
    'uuid': 'bill-1',
    'source': source,
    'status': status,
    'charge': 'none',
    'temp_reference': 'T-006',
    'grand_total_baisas': 4750,
    'items': [
      {
        'id': 99,
        'product_name': 'Frozen coffee',
        'qty': 1,
        'line_total_baisas': 4750,
      },
    ],
  },
  'rounds': [
    {
      'id': 7,
      'round_no': 1,
      'entered_by': 'staff',
      'status': 'accepted',
      'priced_lines': [],
    },
    {
      'id': 8,
      'round_no': 2,
      'entered_by': 'customer',
      'status': pending ? 'pending_confirmation' : 'accepted',
      'priced_lines': [
        {'product_name': 'Water', 'qty': 1, 'line_total_baisas': 500},
      ],
    },
  ],
};

class TableMemory implements DineInStore {
  DineInRequest? request;
  bool failSave = false, failRemove = false;
  @override
  Future<DineInRequest?> load() async => request;
  @override
  Future<void> save(DineInRequest value) async {
    if (failSave || request != null) throw StateError('storage');
    request = value;
  }

  @override
  Future<void> remove(DineInRequest value) async {
    if (failRemove) throw StateError('storage');
    expect(request!.id, value.id);
    request = null;
  }
}

class TableFake implements DineInGateway {
  Map<String, dynamic> value = tableFixture();
  final calls = <String>[];
  final requests = <DineInRequest>[];
  bool failRead = false, loseResponse = false;
  String outcome = 'appended', roundStatus = 'accepted';
  String? wrongBill;
  TableMemory? journal;
  Completer<void>? wait;
  @override
  Future<DineInDetail> detail(int id) async {
    calls.add('read:$id');
    if (failRead) throw StateError('offline');
    return DineInDetail(value);
  }

  @override
  Future<Map<String, dynamic>> append(DineInRequest request) async {
    calls.add('round');
    requests.add(request);
    if (journal != null) expect(journal!.request!.id, request.id);
    await wait?.future;
    if (loseResponse) throw StateError('lost');
    return {
      'outcome': outcome,
      'table_session_uuid': request.seatingUuid,
      'winner_table_session_uuid': null,
      'order_uuid': wrongBill ?? 'bill-1',
      'seating_key': request.payload['seating_key'],
      'table_id': request.payload['table_id'],
      'round_id': 9,
      'round_no': 3,
      'round_status': roundStatus,
      'total_baisas': 500,
    };
  }

  @override
  Future<void> review(
    DineInDetail detail,
    Map<String, dynamic> round,
    bool accept,
  ) async {
    calls.add('review:${round['entered_by']}:${round['id']}:$accept');
  }

  @override
  Future<void> clear(int id) async {
    calls.add('clear:$id');
  }

  @override
  Future<void> reopen(String id) async {
    calls.add('reopen:$id');
  }
}

class TableHttp implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  Object data = tableFixture();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({'data': data, 'errors': []}),
      200,
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
  late TableFake gateway;
  late TableMemory store;
  late DineInController controller;
  final lines = [
    QrQuickLine(4, 2, [7], notes: 'No ice'),
  ];
  setUp(() {
    gateway = TableFake();
    store = TableMemory();
    gateway.journal = store;
    controller = DineInController(gateway, store, 2, staffId: 5);
  });
  tearDown(() => controller.dispose());
  test(
    'joined member displays one canonical bill and deterministic rounds',
    () {
      final value = tableFixture();
      (value['rounds'] as List).insert(0, {
        'id': 6,
        'round_no': 1,
        'entered_by': 'customer',
        'status': 'rejected',
        'priced_lines': [],
      });
      final detail = DineInDetail(value);
      expect(detail.tableId, 2);
      expect(detail.primaryTableId, 1);
      expect(detail.reference, 'T-006');
      expect(detail.billUuid, 'bill-1');
      expect(detail.rounds.map((r) => r['id']), [6, 7, 8]);
      expect(detail.bill!['grand_total_baisas'], 4750);
    },
  );
  test('snapshot is detached from the HTTP map', () {
    final value = tableFixture();
    final detail = DineInDetail(value);
    (value['bill'] as Map)['grand_total_baisas'] = 1;
    expect(detail.bill!['grand_total_baisas'], 4750);
  });
  test('bad/partial snapshots fail closed', () {
    for (final key in ['table', 'occupied', 'rounds']) {
      final value = tableFixture()..remove(key);
      expect(() => DineInDetail(value), throwsFormatException);
    }
  });
  for (final source in ['main_pos', 'handheld']) {
    test('$source does not become a QR claim', () async {
      gateway.value = tableFixture(source: source);
      await controller.start();
      expect(controller.canPay, false);
      expect(controller.canAdd, true);
    });
  }
  for (final status in ['held', 'awaiting_payment', 'paid', 'void']) {
    test('$status freezes additions', () async {
      gateway.value = tableFixture(status: status);
      await controller.start();
      expect(controller.canAdd, false);
      expect(await controller.add(lines), false);
      expect(gateway.requests, isEmpty);
    });
  }
  test('pending confirmation blocks payment, not read-only review', () async {
    gateway.value = tableFixture(pending: true);
    await controller.start();
    expect(controller.canPay, false);
    await controller.review(8, false);
    expect(gateway.calls, contains('review:customer:8:false'));
    expect(store.request, null);
  });
  test(
    'durable intent precedes POST and contains no client money, GPS or ownership',
    () async {
      await controller.start();
      final before = jsonEncode(gateway.value);
      expect(await controller.add(lines), true);
      final request = gateway.requests.single;
      expect(request.tableId, 2);
      expect(request.payload['table_id'], 1);
      expect(request.payload['queued_offline'], false);
      expect(request.payload['staff_id'], 5);
      expect(request.payload['lines'], [
        {
          'product_id': 4,
          'qty': 2,
          'addon_ids': [7],
          'notes': 'No ice',
        },
      ]);
      expect(request.payload.keys.toSet(), {
        'table_id',
        'seating_key',
        'client_request_id',
        'queued_offline',
        'submitted_at',
        'staff_id',
        'lines',
      });
      expect(jsonEncode(gateway.value), before);
      expect(store.request, null);
    },
  );
  test(
    'storage failure sends nothing and never creates a second request',
    () async {
      await controller.start();
      store.failSave = true;
      expect(await controller.add(lines), false);
      expect(gateway.requests, isEmpty);
    },
  );
  test(
    'lost reply/restart retries byte-identical intent and locks money',
    () async {
      await controller.start();
      gateway.loseResponse = true;
      expect(await controller.add(lines), false);
      expect(controller.canPay, false);
      final original = gateway.requests.single;
      final restarted = DineInController(gateway, store, 2);
      addTearDown(restarted.dispose);
      await restarted.start();
      expect(restarted.pending!.encoded, original.encoded);
      gateway.loseResponse = false;
      gateway.outcome = 'replayed';
      expect(await restarted.retry(), true);
      expect(gateway.requests.last.id, original.id);
      expect(gateway.requests.last.encoded, original.encoded);
      expect(store.request, null);
    },
  );
  test('another tap while POST pending cannot submit twice', () async {
    await controller.start();
    gateway.wait = Completer<void>();
    final first = controller.add(lines);
    await Future<void>.delayed(Duration.zero);
    expect(await controller.add(lines), false);
    expect(controller.canPay, false);
    gateway.wait!.complete();
    expect(await first, true);
    expect(gateway.requests, hasLength(1));
  });
  test(
    'new party after polling cannot receive the previous unsent draft',
    () async {
      await controller.start();
      final old = controller.detail!;
      (gateway.value['seating'] as Map)['uuid'] = 'other-seat';
      await controller.refresh();
      expect(
        await controller.add(
          lines,
          expectedSeating: old.seatingUuid,
          expectedBill: old.billUuid,
        ),
        false,
      );
      expect(gateway.requests, isEmpty);
      expect(controller.notice, 'changed');
    },
  );
  test('fresh re-read detects bill adoption before POST', () async {
    await controller.start();
    (gateway.value['bill'] as Map)['uuid'] = 'other-bill';
    expect(await controller.add(lines), false);
    expect(gateway.requests, isEmpty);
  });
  test('old saved intent may not reopen a cleared seating', () async {
    await controller.start();
    gateway.loseResponse = true;
    await controller.add(lines);
    (gateway.value['seating'] as Map)['uuid'] = 'new-party';
    expect(await controller.retry(), false);
    expect(gateway.requests, hasLength(1));
    expect(store.request, isNotNull);
    expect(controller.notice, 'recovery');
  });
  test('mismatched acknowledgement retains intent', () async {
    await controller.start();
    gateway.wrongBill = 'wrong';
    expect(await controller.add(lines), false);
    expect(store.request, isNotNull);
  });
  test(
    'catalogue held acknowledgement is a stored round, not a failed new draft',
    () async {
      await controller.start();
      gateway.outcome = 'held';
      gateway.roundStatus = 'pending_confirmation';
      expect(await controller.add(lines), true);
      expect(controller.notice, 'held');
      expect(store.request, null);
    },
  );
  test(
    'fresh bill_unpaid unlocks; after uncertainty it cannot erase the intent',
    () async {
      await controller.start();
      gateway.outcome = 'bill_unpaid';
      expect(await controller.add(lines), false);
      expect(store.request, null);
      gateway.loseResponse = true;
      await controller.add(lines);
      gateway.loseResponse = false;
      expect(await controller.retry(), false);
      expect(store.request, isNotNull);
    },
  );
  test(
    'ack journal deletion failure leaves retry and payment blocked',
    () async {
      await controller.start();
      store.failRemove = true;
      expect(await controller.add(lines), false);
      expect(controller.canPay, false);
      expect(store.request, isNotNull);
    },
  );
  test('offline and background never authorize another mutation', () async {
    await controller.start();
    gateway.failRead = true;
    await controller.refresh();
    expect(controller.canAdd, false);
    expect(controller.canPay, false);
    controller.setForeground(false);
    final count = gateway.calls.length;
    await controller.refresh();
    expect(await controller.add(lines), false);
    expect(gateway.calls.length, count);
  });
  test('bill or orphan blocks empty-seating clear', () async {
    await controller.start();
    await controller.clear();
    expect(gateway.calls.where((c) => c.startsWith('clear:')), isEmpty);
  });
  test(
    'empty shared seating clear uses table id and no local mutation',
    () async {
      gateway.value['bill'] = null;
      await controller.start();
      await controller.clear();
      expect(gateway.calls, contains('clear:2'));
    },
  );
  test(
    'SQLite scope, insert-only identity, recreation and compare/delete',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      addTearDown(db.close);
      final first = SqliteDineInStore(db, 'a'),
          other = SqliteDineInStore(db, 'b');
      final request = DineInRequest.create(
        DineInDetail(tableFixture()),
        lines,
        5,
      );
      await first.save(request);
      expect(await other.load(), null);
      expect(
        (await SqliteDineInStore(db, 'a').load())!.encoded,
        request.encoded,
      );
      await expectLater(first.save(request), throwsA(anything));
      await first.remove(request);
      expect(await first.load(), null);
      await expectLater(first.remove(request), throwsStateError);
    },
  );
  test('request rejects injected money, order ids and GPS', () {
    final request = DineInRequest.create(
      DineInDetail(tableFixture()),
      lines,
      null,
    );
    for (final key in ['unit_price_baisas', 'order_item_id', 'lat']) {
      final payload = request.payload;
      (payload['lines'] as List).first[key] = 1;
      expect(
        () => DineInRequest(
          tableId: 2,
          seatingUuid: request.seatingUuid,
          billUuid: request.billUuid,
          payload: payload,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'authenticated adapter preserves canonical URL and selects review by origin',
    () async {
      final adapter = TableHttp();
      final dio = Dio(BaseOptions(baseUrl: 'http://table-test.invalid/api/v1'))
        ..httpClientAdapter = adapter;
      final api = PosApiService(tokenGetter: () => 'test-token', dio: dio);
      var scope = 'a';
      final remote = ApiDineInGateway(api, () => scope);
      final detail = await remote.detail(2);
      expect(adapter.requests.single.path, '/device/tables/2/detail');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer test-token',
      );
      final request = DineInRequest.create(detail, lines, 5);
      await remote.append(request);
      expect(
        adapter.requests.last.path,
        '/device/tables/${request.seatingUuid}/round',
      );
      expect(adapter.requests.last.data, request.payload);
      adapter.data = {'outcome': 'accepted'};
      await remote.review(detail, detail.rounds.first, true);
      expect(
        adapter.requests.last.path,
        '/device/tables/${detail.seatingUuid}/rounds/7/confirm',
      );
      await remote.review(detail, detail.rounds.last, false);
      expect(adapter.requests.last.path, '/device/qr/reject-round');
      expect(adapter.requests.last.data, {'round_id': 8});
      scope = 'b';
      final count = adapter.requests.length;
      await expectLater(remote.append(request), throwsStateError);
      expect(adapter.requests.length, count);
    },
  );
  test('another host intent is recovered after an insert conflict', () async {
    await controller.start();
    final other = DineInRequest.create(DineInDetail(tableFixture()), lines, 8);
    await store.save(other);
    expect(await controller.add(lines), false);
    expect(controller.pending!.id, other.id);
    expect(controller.canPay, false);
    expect(gateway.requests, isEmpty);
  });
  testWidgets(
    'staff picker submits only its new line on the same seating and leaves totals server-owned',
    (tester) async {
      tester.view.physicalSize = const Size(480, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async => DineInController(gateway, store, 2),
            catalogue: () => [const QuickProduct(4, 'New water')],
            label: 'T2',
            onPay: (_) async => fail('Unsent draft must not pay'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('dine-add')));
      await tester.tap(find.byKey(const ValueKey('dine-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-product-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-qty-plus')));
      await tester.enterText(
        find.byKey(const ValueKey('quick-notes')),
        'Chilled',
      );
      await tester.tap(find.byKey(const ValueKey('quick-option-add')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('dine-pay')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('dine-pay')))
            .onPressed,
        null,
      );
      await tester.tap(find.byKey(const ValueKey('dine-send')));
      await tester.pumpAndSettle();
      expect(gateway.requests.single.payload['lines'], [
        {'product_id': 4, 'qty': 2, 'addon_ids': [], 'notes': 'Chilled'},
      ]);
      expect(gateway.requests.single.billUuid, 'bill-1');
      expect(gateway.requests.single.payload['table_id'], 1);
      expect(store.request, null);
      expect((gateway.value['bill'] as Map)['grand_total_baisas'], 4750);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  for (final blocked in [1, 2]) {
    test(
      'local draft on covered table $blocked blocks new money and review',
      () async {
        gateway.value = tableFixture(pending: true);
        final guarded = DineInController(
          gateway,
          store,
          2,
          localDraftTables: () => {blocked},
        );
        addTearDown(guarded.dispose);
        await guarded.start();
        expect(guarded.detail!.coveredTableIds, {1, 2});
        expect(guarded.hasLocalConflict, true);
        expect(guarded.canPay, false);
        expect(await guarded.add(lines), false);
        await guarded.review(8, true);
        expect(gateway.requests, isEmpty);
        expect(
          gateway.calls.where((call) => call.startsWith('review:')),
          isEmpty,
        );
      },
    );
  }
  test(
    'unrelated local table draft does not block this shared seating',
    () async {
      final guarded = DineInController(
        gateway,
        store,
        2,
        localDraftTables: () => {99},
      );
      addTearDown(guarded.dispose);
      await guarded.start();
      expect(guarded.hasLocalConflict, false);
      expect(guarded.canPay, true);
      expect(await guarded.add(lines), true);
    },
  );
  test(
    'joining a blocked local table during re-read prevents the POST',
    () async {
      final guarded = DineInController(
        gateway,
        store,
        2,
        localDraftTables: () => {3},
      );
      addTearDown(guarded.dispose);
      await guarded.start();
      (gateway.value['seating'] as Map)['joined_table_ids'] = [2, 3];
      expect(await guarded.add(lines), false);
      expect(gateway.requests, isEmpty);
    },
  );
  test(
    'printer failure does not turn an acknowledged addition into an order retry',
    () async {
      (gateway.value['rounds'] as List).add({
        'id': 9,
        'round_no': 3,
        'entered_by': 'staff',
        'status': 'accepted',
        'priced_lines': [],
      });
      var prints = 0;
      final printing = DineInController(
        gateway,
        store,
        2,
        printAccepted: (detail, round) async {
          expect(detail.billUuid, 'bill-1');
          expect(round['id'], 9);
          expect(store.request, null);
          prints++;
          return false;
        },
      );
      addTearDown(printing.dispose);
      await printing.start();
      expect(await printing.add(lines), true);
      expect(prints, 1);
      expect(printing.notice, 'print_failed');
      expect(printing.pending, null);
      await printing.retryPrint(9);
      expect(prints, 2);
      expect(gateway.requests, hasLength(1));
    },
  );
  test('stored printed-at skips a new claim/print callback', () async {
    (gateway.value['rounds'] as List).add({
      'id': 9,
      'round_no': 3,
      'entered_by': 'staff',
      'status': 'accepted',
      'priced_lines': [],
      'kitchen_printed_at': '2026-09-12T10:00:00Z',
    });
    final printing = DineInController(
      gateway,
      store,
      2,
      printAccepted: (_, _) async => fail('already printed'),
    );
    addTearDown(printing.dispose);
    await printing.start();
    expect(await printing.add(lines), true);
    await printing.retryPrint(9);
    expect(printing.notice, null);
  });
  test('pending/rejected rounds do not print', () async {
    gateway.value = tableFixture(pending: true);
    gateway.outcome = 'held';
    gateway.roundStatus = 'pending_confirmation';
    final printing = DineInController(
      gateway,
      store,
      2,
      printAccepted: (_, _) async => fail('not accepted'),
    );
    addTearDown(printing.dispose);
    await printing.start();
    expect(await printing.add(lines), true);
    await printing.review(8, false);
    await printing.retryPrint(8);
    expect(printing.pending, null);
  });
  for (final ar in [false, true]) {
    testWidgets(
      'native ${ar ? 'AR' : 'EN'} shared bill shows frozen lines, same ref and normal-pay callback only',
      (tester) async {
        tester.view.physicalSize = const Size(480, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final paid = <String>[];
        final screenController = DineInController(gateway, store, 2);
        await tester.pumpWidget(
          MaterialApp(
            home: DineInScreen(
              createController: () async => screenController,
              catalogue: () => [],
              label: 'T2',
              arabic: ar,
              onPay: (id) async {
                paid.add(id);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('T-006'), findsOneWidget);
        expect(find.textContaining('Frozen coffee'), findsOneWidget);
        expect(find.textContaining('4.750'), findsWidgets);
        expect(find.byType(TextField), findsNothing);
        final pay = find.byKey(const ValueKey('dine-pay'));
        await tester.ensureVisible(pay);
        await tester.tap(pay);
        await tester.pumpAndSettle();
        expect(paid, ['bill-1']);
        expect(gateway.requests, isEmpty);
        expect(find.text('Cash'), findsNothing);
        expect(find.text('Card'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'local draft blocks addition/review/settlement without touching its cart',
    (tester) async {
      gateway.value = tableFixture(pending: true);
      final localCart = <String>['unsent water'];
      final before = List<String>.of(localCart);
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async => DineInController(gateway, store, 2),
            catalogue: () => [],
            label: 'T2',
            localDraftBlocked: true,
            onPay: (_) async => fail('no payment'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('dine-confirm-8')))
            .onPressed,
        null,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dine-add')),
        200,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('dine-add')))
            .onPressed,
        null,
      );
      expect(localCart, before);
      expect(gateway.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'visible-only ten-second reads stop behind checkout and in background',
    (tester) async {
      final wait = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async => DineInController(gateway, store, 2),
            catalogue: () => [],
            label: 'T2',
            onPay: (_) => wait.future,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final baseline = gateway.calls.length;
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(gateway.calls.length, greaterThan(baseline));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('dine-pay')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('dine-pay')));
      await tester.pump();
      final atPay = gateway.calls.length;
      await tester.pump(const Duration(seconds: 30));
      expect(gateway.calls.length, atPay);
      wait.complete();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final paused = gateway.calls.length;
      await tester.pump(const Duration(seconds: 30));
      expect(gateway.calls.length, paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
