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
      // This fixture is a held staff round, not a normal customer arrival.
      (api.value['rounds'] as List).last['entered_by'] = 'staff';
      (api.value['rounds'] as List).last['needs_review'] = true;
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
  testWidgets(
    'OBS9 rejected held staff round with pending customer round has no correction button',
    (tester) async {
      final api = TableFake()..value = tableFixture(pending: true);
      (api.value['rounds'] as List).first['status'] = 'pending_confirmation';
      (api.value['rounds'] as List).first['needs_review'] = true;
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
      (api.value['rounds'] as List).first['status'] = 'rejected';
      await tester.tap(find.byKey(const ValueKey('dine-refresh')));
      await tester.pumpAndSettle();
      expect(
        (api.value['rounds'] as List).last['status'],
        'pending_confirmation',
      );
      expect(
        find.byKey(const ValueKey('dine-correct-held-round')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
