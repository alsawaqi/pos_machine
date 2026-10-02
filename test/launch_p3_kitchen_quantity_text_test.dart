// LAUNCH-P3 P3-8: the kitchen screen shows quantities with up to 4 decimals
// (the ledger precision since LAUNCH-P2), so a 0.0003 kg recipe line is no
// longer shown as "0".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/kitchen_production_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  testWidgets('the start dialog shows a 0.0003 kg recipe line, not "0 kg"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so the existing
    // extras header row of the fixed-width dialog overflows here (not with
    // the device font). Ignore only that layout warning.
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(_KitchenApi())],
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const KitchenProductionScreen(staffId: 7, staffName: 'Sami'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Croissant'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // One piece needs 0.0003 kg of saffron.
    expect(find.text('0.0003 kg'), findsOneWidget);
    expect(find.text('0 kg'), findsNothing);
  });

  test('the shared formatter keeps up to 4 decimals and never says "-0"', () {
    expect(kitchenQuantityText(0.0003), '0.0003');
    expect(kitchenQuantityText(0.0123), '0.0123');
    expect(kitchenQuantityText(1.5), '1.5');
    expect(kitchenQuantityText(2), '2');
    expect(kitchenQuantityText(2.000049), '2');
    expect(kitchenQuantityText(-0.5), '-0.5');
    expect(kitchenQuantityText(-0.00001), '0');
    expect(kitchenQuantityText(0.00001), '0');
  });
}

class _KitchenApi implements PosApiService {
  @override
  Future<KitchenData> fetchKitchen() async => KitchenData.fromJson({
    'products': [
      {
        'id': 1,
        'uuid': 'u-1',
        'name': 'Croissant',
        'name_ar': null,
        'category_id': 7,
        'branch_stock_qty': 0.0,
        'max_producible': 3,
        'recipe': [
          {
            'ingredient_id': 9,
            'name': 'Saffron',
            'name_ar': null,
            'quantity': 0.0003,
            'unit': 'kg',
            'branch_balance': 0.001,
          },
        ],
      },
    ],
    'ingredients': [
      {'id': 9, 'name': 'Saffron', 'unit': 'kg', 'branch_balance': 0.001},
    ],
    'active': <Object>[],
  });

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
