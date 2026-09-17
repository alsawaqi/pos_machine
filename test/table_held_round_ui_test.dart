import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;

void main() {
  for (final writable in [true, false]) {
    testWidgets(
      'held correction stays separate from blocked local payment writable=$writable',
      (tester) async {
        final api = TableFake()
          ..value = tableFixture(source: 'main_pos', pending: true);
        var corrections = 0, pays = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: DineInScreen(
              label: 'Table 2',
              catalogue: () => [],
              writesAllowed: writable,
              localDraftBlocked: true,
              createController: () async =>
                  DineInController(api, TableMemory(), 2),
              onPay: (_) async {
                pays++;
              },
              onCorrectHeldRound: () async {
                corrections++;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        final action = find.byKey(const ValueKey('dine-correct-held-round'));
        expect(action, findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(action).onPressed,
          writable ? isNotNull : isNull,
        );
        if (writable) await tester.tap(action);
        await tester.pump();
        expect(corrections, writable ? 1 : 0);
        expect(pays, 0);
        expect(api.requests, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
