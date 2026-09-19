import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;

void main() {
  testWidgets(
    'OBS9 correction disappears after rejection and stays absent on a table with no pending round',
    (tester) async {
      final api = TableFake()
        ..value = tableFixture(source: 'main_pos', pending: true);
      await tester.pumpWidget(
        MaterialApp(
          home: DineInScreen(
            label: 'Table 2',
            catalogue: () => [],
            localDraftBlocked: true,
            createController: () async =>
                DineInController(api, TableMemory(), 2),
            onPay: (_) async {},
            onCorrectHeldRound: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dine-correct-held-round')),
        findsOneWidget,
      );
      (api.value['rounds'] as List).last['status'] = 'rejected';
      await tester.tap(find.byKey(const ValueKey('dine-refresh')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dine-correct-held-round')),
        findsNothing,
      );
      api.value = tableFixture(source: 'main_pos', pending: false);
      await tester.tap(find.byKey(const ValueKey('dine-refresh')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dine-correct-held-round')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
