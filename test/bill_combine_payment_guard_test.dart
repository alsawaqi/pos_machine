import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

class PendingCombineStorage extends FakeOrderStorage {
  bool blocked = true;
  int checks = 0;
  @override
  Future<void> assertNoPendingCombine() async {
    checks++;
    if (blocked) throw StateError('unresolved combine');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final method in ['Cash', 'Credit Card', 'Mixed']) {
    test(
      'pending combine blocks $method before payment side effects',
      () async {
        final storage = PendingCombineStorage();
        final controller = PosController(orderStorage: storage);
        addTearDown(controller.dispose);
        const product = Product(
          id: '7',
          name: 'Coffee',
          category: 'Drinks',
          price: 2,
        );
        controller.applyCatalog(
          categories: const ['Drinks'],
          products: const [product],
          floors: const [],
          tables: const [],
        );
        controller.addProduct(product);
        controller.selectedPaymentMethod = method;
        var kitchen = 0;
        controller.onDiningTableFinalRound = (_) async {
          kitchen++;
          return true;
        };
        final before = jsonEncode(controller.snapshot().toMap());
        final message = method == 'Mixed'
            ? await controller.payMixedCashAndCard(cashAmount: 1)
            : await controller.payAndPrint();
        expect(message, contains('pending bill combine'));
        expect(storage.checks, 1);
        expect(storage.history, isEmpty);
        expect(storage.held, isEmpty);
        expect(kitchen, 0);
        expect(controller.isProcessingPayment, false);
        expect(controller.cart.single.qty, 1);
        // No receipt number or frozen snapshot was changed by a refused tender.
        expect(
          jsonDecode(jsonEncode(controller.snapshot().toMap()))['items'],
          jsonDecode(before)['items'],
        );
      },
    );
  }
  test('unresolved combine blocks floor open, clear, move and join', () async {
    final storage = PendingCombineStorage();
    final controller = PosController(orderStorage: storage);
    addTearDown(controller.dispose);
    await controller.openDiningTable('1');
    await controller.clearDiningTableById('1');
    await controller.clearActiveDiningTable();
    await controller.transferDiningTable('1', '2');
    await controller.joinDiningTables('1', '2');
    expect(storage.checks, 5);
    expect(controller.activeDiningTableId, isNull);
    expect(storage.dining, isEmpty);
  });
}
