import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.mosambee');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    SharedPreferences.setMockInitialValues({'terminal_id': 'T'});
    FlutterSecureStorage.setMockInitialValues({'terminal_pin': 'PIN'});
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final split in [false, true]) {
    test(
      'BUSY shows retry copy and leaves sale open without record action (split=$split)',
      () async {
        final storage = FakeOrderStorage();
        final c = PosController(orderStorage: storage);
        addTearDown(c.dispose);
        const product = Product(
          id: '7',
          name: 'Coffee',
          category: 'Drinks',
          price: 2,
        );
        c.applyCatalog(
          categories: const ['Drinks'],
          products: const [product],
          floors: const [],
          tables: const [],
        );
        c.addProduct(product);
        c.selectedPaymentMethod = 'Credit Card';
        final calls = <String>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          throw PlatformException(code: 'BUSY');
        });
        for (var attempt = 0; attempt < 2; attempt++) {
          final future = split
              ? c.payMixedCashAndCard(cashAmount: 1)
              : c.payAndPrint();
          // A parent may enter the record prompt. Resolve it only for cleanup.
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final offeredRecord = c.showPendingReconciliationPrompt;
          if (offeredRecord) {
            c.resolvePendingReconciliation(PendingReconChoice.cancel);
          }
          final message = await future;
          expect(offeredRecord, isFalse);
          expect(
            message,
            'Card terminal is busy. Wait a moment and try again.',
          );
          expect(c.lastPaymentMessage, message);
          expect(c.showPendingReconciliationPrompt, isFalse);
          expect(c.isProcessingPayment, isFalse);
          expect(c.cart.single.qty, 1);
          expect(storage.history, isEmpty);
          expect(calls, List.filled(attempt + 1, 'payWithPreparedSession'));
        }
      },
    );
  }
  test(
    'literal native stages drive the launch overlay, retaining legacy stages',
    () async {
      final adapter = File(
        'android/app/src/main/kotlin/com/example/pos_machine/MosambeeBridge.kt',
      ).readAsStringSync();
      final core = File(
        'android/app/src/main/kotlin/net/mithqal/softpos/SoftPosBridgeCore.kt',
      ).readAsStringSync();
      expect(adapter, contains('"stage" to stage'));
      final stages = RegExp(
        r'"(login|payment|void|refund|healthcheck)"',
      ).allMatches(core).map((m) => m[1]!).toSet();
      expect(
        stages,
        containsAll(['login', 'payment', 'void', 'refund', 'healthcheck']),
      );
      final c = PosController(orderStorage: FakeOrderStorage());
      addTearDown(c.dispose);
      c.isProcessingPayment = true;
      for (final stage in [...stages, 'login_started', 'payment_started']) {
        c.showPaymentLaunchOverlay = false;
        await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('paymentLaunchState', {
              'stage': stage,
              'launchSurface': 'front',
            }),
          ),
          (_) {},
        );
        expect(
          c.showPaymentLaunchOverlay,
          [
            'login',
            'payment',
            'login_started',
            'payment_started',
          ].contains(stage),
          reason: stage,
        );
      }
    },
  );
}
