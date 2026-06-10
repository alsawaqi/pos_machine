import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/log_expense_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// UI-fit regression — the Log Expense form on the Sunmi T3 (15.6" landscape,
/// ~810 logical px tall): wide viewports use the two-pane layout (form left,
/// keypad right) and the WHOLE form — every keypad key and the Record button —
/// must sit inside the viewport with no scrolling. Narrow viewports keep the
/// stacked column.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size logicalSize) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No Drift in this test: loading state → the screen falls back to
          // the const expense categories.
          catalogProvider.overrideWith(
            (ref) => const Stream<CatalogSnapshot>.empty(),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: LogExpenseScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('T3 landscape: whole form fits on screen, no scrolling needed',
      (tester) async {
    const viewport = Size(1700, 810);
    await pumpAt(tester, viewport);

    // Every keypad key and the submit button are laid out fully inside the
    // viewport (an overflow would also fail the test via FlutterError).
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0'];
    for (final key in keys) {
      final rect = tester.getRect(find.text(key));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height),
          reason: 'keypad key $key must be fully visible');
      expect(rect.top, greaterThanOrEqualTo(0));
    }
    final record = tester.getRect(find.text('Record expense'));
    expect(record.bottom, lessThanOrEqualTo(viewport.height),
        reason: 'Record button must be fully visible without scrolling');

    // Two-pane: the keypad sits to the side of the form, not below it —
    // the '1' key starts to the right of the amount/note column.
    final note = tester.getRect(find.byType(TextField));
    final one = tester.getRect(find.text('1'));
    expect(one.left, greaterThan(note.right),
        reason: 'wide layout puts the keypad beside the form');
  });

  testWidgets('narrow portrait keeps the stacked layout', (tester) async {
    await pumpAt(tester, const Size(480, 800));

    // Keypad renders below the note field in one column.
    final note = tester.getRect(find.byType(TextField));
    final one = tester.getRect(find.text('1'));
    expect(one.top, greaterThan(note.bottom));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
