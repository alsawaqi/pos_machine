import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/authorization.dart';
import 'package:pos_machine/core/training_mode.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/log_expense_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/receipt_layout.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_order_storage.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';

/// LAUNCH-P5 fix order 2 — T1 (training touches nothing real), T9 (the
/// training slip), T10 (training ends at every sign-out and re-pair; the
/// pairing, login and unlock routes stay open).
class _Api implements PosApiService {
  final pushed = <Map<String, dynamic>>[];
  ApiException? refusal;

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    if (refusal != null) throw refusal!;
    pushed.addAll(events);
    return {
      'results': [
        for (final e in events)
          {
            'client_event_id': e['client_event_id'],
            'status': 'processed',
            'result': <String, dynamic>{},
          },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
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

  const latte = Product(id: '10', name: 'Latte', category: 'X', price: 2.0);
  const floor = DiningFloor(id: 'f1', label: 'Main Hall');
  const table = DiningTableDefinition(
    id: 't1',
    floorId: 'f1',
    name: 'T1',
    sizeLabel: 'square',
    seats: 4,
    sortOrder: 1,
  );

  PosController build(FakeOrderStorage storage) =>
      PosController(orderStorage: storage)..applyCatalog(
        categories: const ['X'],
        products: const [latte],
        floors: const [floor],
        tables: const [table],
        taxes: const <CompanyTax>[],
      );

  group('T1 — training touches nothing real', () {
    test('a real held order is neither resumed nor discarded', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      c.addProduct(latte);
      await c.holdCurrentOrder();
      expect(storage.held, hasLength(1));
      c.training = true;
      await c.refreshHeldOrders();
      final record = storage.held.single;
      expect(
        await c.resumeHeldOrder(record),
        'Not available in training mode.',
      );
      expect(storage.held, hasLength(1), reason: 'the real held copy stays');
      expect(c.cart, isEmpty);
      final voided = <String>[];
      c.onOrderVoided =
          (
            uuid, {
            orderNumber,
            reason,
            voidReasonId,
            ActionAuthorization? authorization,
          }) => voided.add(uuid);
      expect(
        await c.discardHeldOrder(record),
        'Not available in training mode.',
      );
      expect(storage.held, hasLength(1));
      expect(voided, isEmpty);
    });

    test('a real paid order is not cancelled', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      final voided = <String>[];
      c.onOrderVoided =
          (
            uuid, {
            orderNumber,
            reason,
            voidReasonId,
            ActionAuthorization? authorization,
          }) => voided.add(uuid);
      c.addProduct(latte);
      await c.payAndPrint();
      await c.refreshOrderHistory();
      final record = c.orderHistory.single;
      TrainingMode.active = true; // the app-wide flag alone is enough
      final message = await c.cancelCompletedOrder(
        record,
        cancelFullOrder: true,
        itemIndexes: const <int>{},
      );
      expect(message, 'Not available in training mode.');
      await c.refreshOrderHistory();
      expect(c.orderHistory.single.snapshot.isFullyCanceled, isFalse);
      expect(storage.history.single.snapshot.isFullyCanceled, isFalse);
      expect(voided, isEmpty);
    });

    test('a real table is not opened', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      await c.selectOrderType(OrderType.dineIn);
      c.training = true;
      await c.openDiningTable('t1');
      expect(c.activeDiningTableId, isNull);
      expect(c.displayNote, 'Not available in training mode.');
    });

    test('training starts only from a counter order', () {
      expect(trainingOrderTypeAllowed(OrderType.quickOrder), isTrue);
      expect(trainingOrderTypeAllowed(OrderType.toGo), isTrue);
      expect(trainingOrderTypeAllowed(OrderType.dineIn), isFalse);
      expect(trainingOrderTypeAllowed(OrderType.delivery), isFalse);
      expect(
        trainingOrderTypeAllowed(OrderType.quickOrder, activeTableId: 't1'),
        isFalse,
      );
      expect(
        trainingOrderTypeAllowed(OrderType.quickOrder, workspaceOpen: true),
        isFalse,
      );
    });

    test('a pay-out refused for training is final, never queued', () async {
      final api = _Api()
        ..refusal = ApiException(
          message: 'Not available in training mode.',
          code: 'training_mode',
        );
      final queued = <String>[];
      final service = ExpenseRestockService(
        api,
        queue: (key, event) async => queued.add(key),
      );
      await expectLater(
        service.logExpense(
          category: 'other',
          amountBaisas: 500,
          paidFromDrawer: true,
          shiftUuid: 'shift-1',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(queued, isEmpty);
    });

    testWidgets('the pay-out screen refuses in training', (tester) async {
      SharedPreferences.setMockInitialValues({
        TrainingMode.preferenceKey: true,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), prefs);
      await session.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', position: 'manager'),
      );
      await session.saveOpenShift(
        OpenShiftData(
          uuid: 'shift-1',
          openingCashBaisas: 0,
          openedAt: DateTime.utc(2026, 10, 4, 5),
          staffId: 4,
        ),
      );
      final api = _Api();
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            sessionServiceProvider.overrideWithValue(session),
            apiServiceProvider.overrideWithValue(api),
            catalogProvider.overrideWith((ref) => const Stream.empty()),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: LogExpenseScreen(),
          ),
        ),
      );
      await tester.pump();
      for (final d in '500'.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await tester.tap(find.byType(FilledButton).last);
      await tester.pump();
      await tester.pump();
      expect(find.text('Not available in training mode.'), findsOneWidget);
      expect(api.pushed, isEmpty);
    });

    test('the screen guards are wired (held, history, settings, entry)', () {
      // The real screen is a 21 000-line widget; these guards sit at the
      // entry of each flow (the controller refuses on its own as well).
      final s = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
      expect(
        RegExp(
          r'Future<void> _openHeldOrdersDialog\(\) async \{\s*if \(_blockedInTraining\(\)\) return;',
        ).hasMatch(s),
        isTrue,
      );
      expect(
        RegExp(
          r'required OrderHistoryRecord record,\s*\}\) async \{\s*if \(_blockedInTraining\(\)\) return;',
        ).hasMatch(s),
        isTrue,
      );
      expect(s, contains('SettingsScreen(showOperations: !training)'));
      expect(s, contains('trainingOrderTypeAllowed('));
    });
  });

  group('T9 — the training slip', () {
    test('no tax-invoice title, no VAT number, a TRAINING-n number', () {
      const tax = CompanyTaxSettings(
        vatRegistered: true,
        vatNumber: 'OM1100000001',
      );
      final order = OrderSnapshot.initial().copyWith(
        training: true,
        receiptNumber: trainingReceiptNumber(3),
      );
      final texts = [
        for (final l in buildReceiptLines(
          order,
          header: const ReceiptHeader(tax: tax),
          at: DateTime.utc(2026, 10, 4),
        ))
          '${l.text}|${l.amount}',
      ].join('\n');
      expect(texts, contains('TRAINING — NOT A RECEIPT'));
      expect(texts, isNot(contains('Simplified tax invoice')));
      expect(texts, isNot(contains('فاتورة ضريبية مبسطة')));
      expect(texts, isNot(contains('OM1100000001')));
      expect(texts, contains('TRAINING-3'));
      // A real receipt is unchanged.
      final real = [
        for (final l in buildReceiptLines(
          OrderSnapshot.initial(),
          header: const ReceiptHeader(tax: tax),
          at: DateTime.utc(2026, 10, 4),
        ))
          l.text,
      ].join('\n');
      expect(real, contains('Simplified tax invoice'));
      expect(real, contains('OM1100000001'));
    });

    test('a training sale never uses or advances the real number', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      c.training = true;
      var allocations = 0;
      c.allocateReceiptNumber = () async {
        allocations++;
        return (number: 77, formatted: 'R-77');
      };
      final before = c.currentOrderNumber;
      c.addProduct(latte);
      await c.payAndPrint();
      c.addProduct(latte);
      await c.payAndPrint();
      expect(TrainingOrderStore.orders.map((o) => o.receiptNumber), [
        'TRAINING-1',
        'TRAINING-2',
      ]);
      expect(TrainingOrderStore.orders.map((o) => o.displayOrderNumber), [
        'TRAINING-1',
        'TRAINING-2',
      ]);
      expect(c.currentOrderNumber, before);
      expect(allocations, 0);
    });
  });

  group('T10 — training ends at sign-out and re-pair', () {
    test('the pairing, login and unlock routes are allowed', () {
      for (final path in [
        '/auth/pos/login',
        '/auth/device/activate',
        '/device/auth/unlock-pin-lock',
      ]) {
        expect(TrainingMode.allows('POST', path), isTrue, reason: path);
      }
      expect(TrainingMode.allows('POST', '/device/sync/push'), isFalse);
    });

    Future<ProviderContainer> trainingContainer() async {
      SharedPreferences.setMockInitialValues({
        TrainingMode.preferenceKey: true,
      });
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final session = SessionService(const FlutterSecureStorage(), prefs);
      await session.saveStaff(
        const StaffSessionData(id: 4, name: 'Sara', staffToken: 'tok'),
        login: true,
      );
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(session),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(trainingModeProvider), isTrue);
      TrainingOrderStore.orders.add(OrderSnapshot.initial());
      return c;
    }

    test('every logout leaves training', () async {
      final c = await trainingContainer();
      await c.read(sessionControllerProvider.notifier).logoutStaff();
      expect(c.read(trainingModeProvider), isFalse);
      expect(TrainingMode.active, isFalse);
      expect(TrainingOrderStore.orders, isEmpty);
      expect(
        c.read(sharedPreferencesProvider).getBool(TrainingMode.preferenceKey),
        isNull,
      );
    });

    test('a re-pair leaves training', () async {
      final c = await trainingContainer();
      await c.read(sessionControllerProvider.notifier).clearForRePair();
      expect(c.read(trainingModeProvider), isFalse);
      expect(TrainingMode.active, isFalse);
    });
  });
}
