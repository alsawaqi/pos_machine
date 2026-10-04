import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
// Test-only: fake_async ships with flutter_test (already in the lock).
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/permissions.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/sold_out_sync.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P4 C6 — sold out on the till: a manual per-branch switch (never
/// stock). A sold-out product shows a badge and cannot be added; a
/// long-press switches it (managers / supervisors directly, anyone else with
/// the manager-approval PIN); the till polls GET /device/sold-out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(id: '10', name: 'Latte', category: 'Coffee', price: 1.5);
  const cake = Product(
    id: '11',
    name: 'Cake',
    category: 'Coffee',
    price: 2,
    soldOut: true,
  );

  group('controller', () {
    PosController build() {
      final c = PosController(orderStorage: FakeOrderStorage());
      c.applyCatalog(
        categories: const ['Coffee'],
        products: const [latte, cake],
        floors: const <DiningFloor>[],
        tables: const <DiningTableDefinition>[],
        branchId: 6,
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a sold-out product cannot be added', () {
      final c = build();
      expect(c.isSoldOut(cake), isTrue);
      expect(c.isUnorderable(cake), isTrue);
      c.addProduct(cake);
      expect(c.cart, isEmpty);
      c.addProduct(latte);
      expect(c.cart.single.product.id, '10');
    });

    test('a local switch takes effect at once, both ways', () {
      final c = build();
      c.markSoldOutLocally('10', true);
      expect(c.isSoldOut(latte), isTrue);
      c.addProduct(latte);
      expect(c.cart, isEmpty);
      c.markSoldOutLocally('11', false);
      c.addProduct(cake);
      expect(c.cart.single.product.id, '11');
    });

    test('the tick list (sold_out.toggle) decides who switches directly', () {
      final m = PositionPermissions.defaults;
      expect(m.allows('manager', 'sold_out.toggle'), isTrue);
      expect(m.allows('Supervisor', 'sold_out.toggle'), isTrue);
      expect(m.allows('cashier', 'sold_out.toggle'), isFalse);
      expect(m.allows(null, 'sold_out.toggle'), isFalse);
    });
  });

  group('the poll', () {
    test('every 60 s while online; nothing applied on failure', () {
      fakeAsync((async) {
        var online = false;
        var fail = false;
        var fetches = 0;
        final applied = <Set<int>>[];
        final sync = SoldOutSync(
          fetch: () async {
            fetches++;
            if (fail) throw StateError('offline');
            return {11};
          },
          apply: (ids) async => applied.add(ids),
          online: () => online,
        )..start();
        async.flushMicrotasks();
        expect(fetches, 0, reason: 'offline at start');
        online = true;
        async.elapse(const Duration(seconds: 60));
        expect(fetches, 1);
        expect(applied, [
          {11},
        ]);
        fail = true;
        async.elapse(const Duration(seconds: 60));
        expect(fetches, 2);
        expect(applied, hasLength(1));
        fail = false;
        sync.onResume();
        async.flushMicrotasks();
        expect(fetches, 3);
        expect(applied, hasLength(2));
        sync.stop();
        async.elapse(const Duration(minutes: 5));
        expect(fetches, 3);
      });
    });

    test('the cached catalog takes exactly the polled ids', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      for (final id in [10, 11, 12]) {
        await db.into(db.products).insert(
          ProductsCompanion(
            id: Value(id),
            name: Value('P$id'),
            soldOut: Value(id == 12),
          ),
        );
      }
      await db.applySoldOut({11});
      final rows = await db.select(db.products).get();
      expect({
        for (final r in rows) r.id: r.soldOut,
      }, {10: false, 11: true, 12: false});
    });
  });

  group('the API', () {
    late _Adapter adapter;
    late PosApiService api;
    setUp(() {
      adapter = _Adapter();
      api = PosApiService(
        tokenGetter: () => 'token',
        dio: Dio(
          BaseOptions(
            baseUrl: 'https://p4.test/api/v1',
            validateStatus: (_) => true,
          ),
        )..httpClientAdapter = adapter,
      );
    });

    test('GET /device/sold-out returns the ids', () async {
      adapter.reply = (_) => {
        'data': {
          'product_ids': [11, 14],
          'as_of': '2026-10-03T12:00:00Z',
        },
        'errors': <Object?>[],
      };
      expect(await api.fetchSoldOut(), {11, 14});
      expect(adapter.requests.single.method, 'GET');
      expect(adapter.requests.single.path, '/device/sold-out');
    });

    test('POST /device/products/{id}/sold-out sends the contract', () async {
      // LAUNCH-P5 C3 — the authorization block replaces approver_staff_id.
      final block = {
        'action': 'sold_out.toggle',
        'ref': 'product:11',
        'mode': 'approval',
        'actor_staff_id': 7,
        'approver_staff_id': 3,
      };
      await api.setProductSoldOut(
        11,
        soldOut: true,
        staffId: 7,
        authorization: block,
      );
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, '/device/products/11/sold-out');
      expect(request.body, {
        'sold_out': true,
        'staff_id': 7,
        'authorization': block,
        'auth_v': 1,
      });
      await api.setProductSoldOut(11, soldOut: false, staffId: 7);
      expect(adapter.requests.last.body, {
        'sold_out': false,
        'staff_id': 7,
        'auth_v': 1,
      });
    });
  });

  group('the real product grid', () {
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      messenger.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      messenger.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    testWidgets('badge, no add on tap, long-press switches (manager)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _Api();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        api: api,
        database: db,
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [latte, cake],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      final element = tester.element(find.byType(StaffPosScreen));
      final container = ProviderScope.containerOf(element);
      await tester.runAsync(
        () => container
            .read(sessionServiceProvider)
            .saveStaff(
              const StaffSessionData(id: 7, name: 'Mona', position: 'manager'),
            ),
      );
      final dynamic state = tester.state(find.byType(StaffPosScreen));
      final PosController controller = state.controller as PosController;

      expect(find.byKey(const ValueKey('product-sold-out-badge')), findsOneWidget);
      await tester.tap(find.text('Cake').first);
      await tester.pumpAndSettle();
      expect(controller.cart, isEmpty);

      await tester.longPress(find.text('Latte').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sold-out-switch')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sold-out-switch-confirm')));
      await tester.pumpAndSettle();
      expect(api.switches, [
        {
          'product': 10,
          'sold_out': true,
          'staff': 7,
          'authorization': {
            'action': 'sold_out.toggle',
            'ref': 'product:10',
            'mode': 'position',
            'actor_staff_id': 7,
          },
        },
      ]);
      expect(controller.isSoldOut(latte), isTrue);
      expect(find.byKey(const ValueKey('product-sold-out-badge')), findsNWidgets(2));
      await disposeWorkspaceMachine(tester);
    });
  });
}

class _Api implements PosApiService {
  final switches = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];

  @override
  Future<void> setProductSoldOut(
    int productId, {
    required bool soldOut,
    required int staffId,
    Map<String, dynamic>? authorization,
  }) async {
    switches.add({
      'product': productId,
      'sold_out': soldOut,
      'staff': staffId,
      'authorization': authorization,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected network operation: ${invocation.memberName}',
  );
}

class _Request {
  _Request(RequestOptions options)
    : method = options.method,
      path = options.path,
      body = options.data == null ? null : jsonDecode(jsonEncode(options.data));
  final String method;
  final String path;
  final Object? body;
}

class _Adapter implements HttpClientAdapter {
  final requests = <_Request>[];
  Map<String, dynamic> Function(_Request)? reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = _Request(options);
    requests.add(request);
    final body =
        reply?.call(request) ??
        {'data': <String, dynamic>{}, 'errors': <Object?>[]};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
