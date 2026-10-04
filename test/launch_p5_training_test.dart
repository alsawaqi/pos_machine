import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/training_mode.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/receipt_layout.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_order_storage.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

/// LAUNCH-P5 C7 — training mode: a separate store, nothing in the outbox,
/// no server calls, receipts marked, and exit discards.
class _Adapter implements HttpClientAdapter {
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      jsonEncode({'data': <String, dynamic>{}, 'errors': <Object?>[]}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // LAUNCH-P5 fix order 2c — never the shared on-disk orders database
  // (.dart_tool/sqflite_common_ffi/databases/mithqal_orders.db): test
  // files running in parallel would lock each other out of it.
  setUp(() => debugOrderStorageOverride = FakeOrderStorage());
  tearDown(() => debugOrderStorageOverride = null);
  tearDown(() {
    TrainingMode.active = false;
    TrainingOrderStore.clear();
  });

  group('no server calls', () {
    late _Adapter adapter;
    late PosApiService api;
    setUp(() {
      adapter = _Adapter();
      api = PosApiService(
        tokenGetter: () => 'token',
        dio: Dio(
          BaseOptions(
            baseUrl: 'https://p5.test/api/v1',
            validateStatus: (_) => true,
          ),
        )..httpClientAdapter = adapter,
      );
    });

    test('while training, business calls never leave the till', () async {
      TrainingMode.active = true;
      for (final call in <Future<Object?> Function()>[
        () => api.pushSync([
          {'client_event_id': 'x', 'event_type': 'order.create', 'payload': {}},
        ]),
        () => api.fetchSoldOut(),
        () => api.fetchQrTableBoard(),
        () => api.searchCustomers('9'),
        () => api.fetchKitchen(),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'training_mode'),
          ),
        );
      }
      expect(adapter.paths, isEmpty);
      // Config, staff status and approvers still refresh.
      await api.fetchActiveStaffIds().catchError((_) => <int>{});
      await api.fetchApprovers().catchError(
        (_) => (approvers: <Map<String, dynamic>>[], asOf: null),
      );
      expect(adapter.paths, [
        'GET /device/staff-status',
        'GET /device/approvers',
      ]);
    });

    test('out of training the same calls go through', () async {
      await api.fetchSoldOut().catchError((_) => <int>{});
      expect(adapter.paths, ['GET /device/sold-out']);
    });
  });

  test('anything queued while training carries training: true', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    TrainingMode.active = true;
    await db.enqueueOutbox(
      OrderOutboxCompanion.insert(
        orderUuid: 'k',
        eventsJson: jsonEncode([buildOrderVoidEvent(orderUuid: 'o')]),
        createdAt: DateTime.utc(2026, 10, 4),
      ),
    );
    final event =
        (jsonDecode((await db.getOutbox('k'))!.eventsJson) as List).single
            as Map;
    expect(event['payload']['training'], isTrue);
    expect(event['payload']['auth_v'], 1);
  });

  group('training sales', () {
    const latte = Product(id: '10', name: 'Latte', category: 'X', price: 2.0);

    PosController build(FakeOrderStorage storage) {
      final c = PosController(orderStorage: storage);
      c.applyCatalog(
        categories: const ['X'],
        products: const [latte],
        floors: const [],
        tables: const [],
        taxes: const <CompanyTax>[],
      );
      c.training = true;
      return c;
    }

    test(
      'stay in the training store, never the history or the outbox',
      () async {
        final storage = FakeOrderStorage();
        final c = build(storage);
        addTearDown(c.dispose);
        var queued = 0;
        c.onOrderCompleted = (_) => queued++;
        c.addProduct(latte);
        await c.payAndPrint();
        expect(queued, 0);
        expect(storage.history, isEmpty);
        expect(TrainingOrderStore.orders, hasLength(1));
        expect(TrainingOrderStore.orders.single.training, isTrue);
        expect(c.cart, isEmpty);
      },
    );

    test('are cash only and cannot be held or sent to a table', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      c.addProduct(latte);
      c.selectPaymentMethod('Card');
      final message = await c.payAndPrint();
      expect(message, 'Training mode: cash only.');
      expect(TrainingOrderStore.orders, isEmpty);
      expect(await c.holdCurrentOrder(), 'Not available in training mode.');
      expect(storage.held, isEmpty);
      await c.selectOrderType(OrderType.dineIn);
      expect(c.selectedOrderType, isNot(OrderType.dineIn));
    });

    test('print "TRAINING — NOT A RECEIPT" in both languages', () {
      final order = OrderSnapshot.initial().copyWith(training: true);
      final lines = buildReceiptLines(
        order,
        header: const ReceiptHeader(),
        at: DateTime.utc(2026, 10, 4),
      );
      final texts = lines.map((l) => l.text).toList();
      expect(texts, contains('TRAINING — NOT A RECEIPT'));
      expect(texts, contains('تدريب — ليس إيصالاً'));
      final real = buildReceiptLines(
        OrderSnapshot.initial(),
        header: const ReceiptHeader(),
        at: DateTime.utc(2026, 10, 4),
      );
      expect(
        real.map((l) => l.text),
        isNot(contains('TRAINING — NOT A RECEIPT')),
      );
    });
  });

  test('leaving training discards it', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    expect(container.read(trainingModeProvider), isFalse);
    await container.read(trainingModeProvider.notifier).enter();
    expect(TrainingMode.active, isTrue);
    expect(prefs.getBool(TrainingMode.preferenceKey), isTrue);
    TrainingOrderStore.orders.add(OrderSnapshot.initial());
    await container.read(trainingModeProvider.notifier).exit();
    expect(TrainingMode.active, isFalse);
    expect(TrainingOrderStore.orders, isEmpty);
    expect(prefs.getBool(TrainingMode.preferenceKey), isNull);
  });

  test('the training screens are wired (gate, menu, banner)', () {
    final gate = File('lib/screens/staff_startup_gate.dart').readAsStringSync();
    expect(gate, contains('ref.watch(trainingModeProvider)'));
    final screen = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
    expect(screen, contains("'training.use'"));
    expect(
      screen,
      contains('controller.training = ref.watch(trainingModeProvider)'),
    );
  });
}
