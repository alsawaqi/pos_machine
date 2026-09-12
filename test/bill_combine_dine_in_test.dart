import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory;

void main() {
  testWidgets(
    'combine recovery remains reachable after a normal detail refusal',
    (tester) async {
      final api = TableFake()..failRead = true;
      final store = TableMemory();
      var reviews = 0, controllers = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async {
              controllers++;
              return DineInController(api, store, 2);
            },
            catalogue: () => [],
            label: 'T2',
            writesAllowed: false,
            localDraftBlocked: true,
            onPay: (_) async => fail('No payment allowed'),
            onCombine: () async {
              reviews++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dine-combine')));
      await tester.pumpAndSettle();
      expect(reviews, 1);
      expect(controllers, 2);
      expect(api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'unsent staff items disable combining, without losing the items',
    (tester) async {
      final api = TableFake(), store = TableMemory();
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            createController: () async => DineInController(api, store, 2),
            catalogue: () => [const QuickProduct(4, 'Water')],
            label: 'T2',
            onPay: (_) async => fail('Unsent items must not pay'),
            onCombine: () async => fail('Unsent items must not combine'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dine-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-product-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-option-add')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('dine-combine')))
            .onPressed,
        null,
      );
      expect(find.byKey(const ValueKey('dine-send')), findsOneWidget);
      expect(api.requests, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
