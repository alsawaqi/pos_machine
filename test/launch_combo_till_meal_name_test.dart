import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/row_parsing.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_controller.dart';
import 'package:pos_machine/tablet_orders/tablet_orders_screen.dart';
import 'launch_p6_till_fix3_test.dart' show Gateway, base;

/// LAUNCH combo add-on — device-run follow-up: a tablet / QR meal line shows
/// the meal's display name ("Mocha meal"), as the cart and checkout do, never
/// the plain main ("Mocha"). The main and the items stay listed under it.
/// (Behaviour only: these tests compile at c668db4 and fail there.)
void main() {
  setUp(() => skippedRowLogger = (_, _, _) {});

  final mealLine = {
    'product_id': 4,
    'product_name': 'Mocha',
    'meal_id': 9,
    'meal_name': 'meal',
    'display_name': 'Mocha meal',
    'display_name_ar': 'موكا وجبة',
    'qty': 1,
    'components': [
      {
        'line_id': 51,
        'kind': 'choice',
        'product_id': 7,
        'name': 'cake',
        'qty': 1,
      },
      {
        'line_id': 52,
        'kind': 'choice',
        'product_id': 8,
        'name': 'juice',
        'qty': 1,
      },
    ],
  };

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final gateway = Gateway([
      base(
        'a',
        extra: {
          'lines': [
            mealLine,
            {'product_id': 4, 'product_name': 'Mocha', 'qty': 2},
          ],
        },
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: TabletOrdersScreen(
          controller: TabletOrdersController(gateway),
          poll: const Duration(hours: 1),
          actions: TabletOrderActions(
            myStaffId: 7,
            authorize: (a, {subtitle, alwaysApproval = false}) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the tablet order sheet shows "1 × Mocha meal"', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('tablet-order-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 × Mocha meal'), findsOneWidget);
    expect(find.text('1 × Mocha'), findsNothing);
    // A plain Mocha on the same order keeps its own name.
    expect(find.text('2 × Mocha'), findsOneWidget);
    // The main and the items are listed under the meal.
    expect(find.text('   > Mocha'), findsOneWidget);
    expect(find.text('   > cake'), findsOneWidget);
  });

  testWidgets('the tablet edit dialog names the meal line "Mocha meal"', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('tablet-order-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tablet-edit')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tablet-edit-line-0')),
        matching: find.text('Mocha meal'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tablet-edit-line-1')),
        matching: find.text('Mocha'),
      ),
      findsOneWidget,
    );
  });

  test('a QR / table bill item that is a meal is named as the meal', () {
    expect(QrOrderItem.fromJson(mealLine).name, 'Mocha meal');
    expect(
      QrOrderItem.fromJson({'product_id': 4, 'product_name': 'Mocha'}).name,
      'Mocha',
    );
  });
}
