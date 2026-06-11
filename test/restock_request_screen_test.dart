import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/restock_request_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// UI-fit regression — the Request Restock form on the Sunmi T3 (15.6"
/// landscape, ~810 logical px tall): wide viewports use the two-pane layout
/// (picker/note/submit left, added-lines card right) so the WHOLE form — the
/// Submit button and every added line — sits inside the viewport with no page
/// scrolling even after a cashier adds 8 ingredient lines (a long request
/// scrolls only inside the lines card). Narrow viewports keep the stacked
/// column with the lines inline.
void main() {
  final ingredients = [
    for (var i = 1; i <= 8; i++) IngredientRef(id: i, name: 'Ingredient $i', unit: 'kg'),
  ];
  final snapshot = CatalogSnapshot(
    categories: const [],
    products: const [],
    floors: const [],
    tables: const [],
    taxes: const [],
    ingredients: ingredients,
  );

  Future<void> pumpAt(WidgetTester tester, Size logicalSize) async {
    tester.view.physicalSize = logicalSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No Drift in this test: the catalog stream emits one snapshot with
          // the test ingredients (an empty catalog would show the empty state).
          catalogProvider.overrideWith((ref) => Stream.value(snapshot)),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: RestockRequestScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Add one line through the UI: pick the ingredient in the dropdown, type a
  /// quantity (the qty field is the first TextField), tap the add button.
  Future<void> addLine(WidgetTester tester, int id) async {
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingredient $id (kg)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
  }

  testWidgets('T3 landscape: 8 lines and the submit button fit on screen',
      (tester) async {
    const viewport = Size(1700, 810);
    await pumpAt(tester, viewport);

    for (var i = 1; i <= 8; i++) {
      await addLine(tester, i);
    }
    expect(find.byType(ListTile), findsNWidgets(8));

    // The submit button and every added line are laid out fully inside the
    // viewport (an overflow would also fail the test via FlutterError).
    final submit = tester.getRect(find.text('Submit request'));
    expect(submit.bottom, lessThanOrEqualTo(viewport.height),
        reason: 'Submit button must be fully visible without scrolling');
    expect(submit.top, greaterThanOrEqualTo(0));
    for (final tile in find.byType(ListTile).evaluate()) {
      final rect = tester.getRect(find.byWidget(tile.widget));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height),
          reason: 'every added line must be fully visible');
      expect(rect.top, greaterThanOrEqualTo(0));
    }

    // Two-pane: the lines card sits to the side of the form, not below it —
    // the first line starts to the right of the note field.
    final note = tester.getRect(find.byType(TextField).at(1));
    final firstTile = tester.getRect(find.byType(ListTile).first);
    expect(firstTile.left, greaterThan(note.right),
        reason: 'wide layout puts the lines card beside the form');

    // The lines card has its own internal scroll view (page + card).
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
  });

  testWidgets('narrow portrait keeps the stacked layout', (tester) async {
    await pumpAt(tester, const Size(480, 800));
    await addLine(tester, 1);

    // The added line renders inline below the picker and above the note field,
    // in one column with a single scroll view.
    final picker = tester.getRect(find.byType(DropdownButton<int>));
    final tile = tester.getRect(find.byType(ListTile));
    final note = tester.getRect(find.byType(TextField).at(1));
    expect(tile.top, greaterThan(picker.bottom));
    expect(note.top, greaterThan(tile.bottom));
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
}
