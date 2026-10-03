// LAUNCH item kind (owner decision 2026-10-03): every ingredient amount
// typed on the till offers the units of the ingredient's kind (kg or g, l or
// ml). The restock request and the kitchen batch extras convert to the
// stored unit before sending, so their events and requests keep their
// shape; a restock line reads "12 l", not "12000".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/count_units.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/kitchen_production_screen.dart';
import 'package:pos_machine/screens/restock_request_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';

class _SyncApi implements PosApiService {
  final pushed = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async {
    pushed.addAll(events);
    return {
      'results': [
        {
          'client_event_id': events.single['client_event_id'],
          'status': 'processed',
          'result': {'restock_request_id': 1, 'status': 'submitted'},
        },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API ${i.memberName}');
}

class _KitchenApi implements PosApiService {
  final extrasSent = <List<({int ingredientId, double quantity})>>[];

  @override
  Future<KitchenData> fetchKitchen() async => KitchenData.fromJson({
        'products': [
          {
            'id': 1,
            'uuid': 'u-1',
            'name': 'Cake',
            'branch_stock_qty': 0.0,
            'max_producible': 10,
            'recipe': [
              {
                'ingredient_id': 1,
                'name': 'Flour',
                'quantity': 100,
                'unit': 'g',
                'branch_balance': 5000,
              },
            ],
          },
        ],
        'ingredients': [
          {'id': 1, 'name': 'Flour', 'unit': 'g', 'branch_balance': 5000},
        ],
        'active': <Object>[],
      });

  @override
  Future<ProductionBatch> startProduction({
    required int productId,
    required int quantity,
    int? staffId,
    List<({int ingredientId, double quantity})> extras = const [],
  }) async {
    extrasSent.add(extras);
    return ProductionBatch.fromJson({
      'uuid': 'p-1',
      'status': 'in_progress',
      'product_id': productId,
      'product_name': 'Cake',
      'quantity': quantity,
      'lines': <Object>[],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test('friendlyQuantity shows 1000 g / ml and above in kg / l', () {
    expect(friendlyQuantity(12000, 'ml'), '12 l');
    expect(friendlyQuantity(1500, 'g'), '1.5 kg');
    expect(friendlyQuantity(999, 'ml'), '999 ml');
    expect(friendlyQuantity(0.25, 'kg'), '0.25 kg');
    expect(friendlyQuantity(12345.5, 'g'), '12.3455 kg');
    expect(friendlyQuantity(3, 'piece'), '3 piece');
    expect(friendlyQuantity(2, null), '2');
  });

  testWidgets('a restock line is typed in l and sent in ml', (tester) async {
    final api = _SyncApi();
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogProvider.overrideWith(
            (ref) => Stream.value(
              const CatalogSnapshot(
                categories: [],
                products: [],
                floors: [],
                tables: [],
                taxes: [],
                ingredients: [
                  IngredientRef(id: 1, name: 'Milk', unit: 'ml'),
                  IngredientRef(id: 2, name: 'Cups', unit: 'box'),
                ],
              ),
            ),
          ),
          expenseRestockServiceProvider.overrideWithValue(
            ExpenseRestockService(api),
          ),
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

    // No unit choice before an ingredient is picked.
    expect(find.byKey(const ValueKey('restock-unit')), findsNothing);
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milk (ml)').last);
    await tester.pumpAndSettle();
    // A liquid offers l (picked) and ml.
    expect(find.byKey(const ValueKey('restock-unit')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '12');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('12 l'), findsOneWidget);

    // A box item keeps its own unit (no choice).
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cups (box)').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('restock-unit')), findsNothing);
    await tester.enterText(find.byType(TextField).first, '3');
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit request'));
    await tester.pumpAndSettle();
    expect(api.pushed, hasLength(1));
    expect(api.pushed.single['payload']['lines'], [
      {'ingredient_id': 1, 'quantity': 12000.0},
      {'ingredient_id': 2, 'quantity': 3.0},
    ]);
  });

  testWidgets('a kitchen extra is typed in kg and sent in g', (tester) async {
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
    final api = _KitchenApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: KitchenProductionScreen(staffId: 7, staffName: 'Sami'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Cake'));
    await tester.pump();
    // Let the dialog finish opening (it ignores taps while animating).
    await tester.pump(const Duration(seconds: 1));
    // With the test font the header row overflows and pushes "Add extra"
    // outside the dialog, so press the button itself.
    tester
        .widget<ButtonStyleButton>(
          find.ancestor(
            of: find.text('Add extra'),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        )
        .onPressed!();
    await tester.pump();
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flour').last);
    await tester.pumpAndSettle();
    // A weighed extra starts in its stored unit (g) and offers kg.
    final unitPicker = find.byKey(const ValueKey('extra-unit-0'));
    expect(unitPicker, findsOneWidget);
    expect(tester.widget<DropdownButton<String>>(unitPicker).value, 'g');
    await tester.tap(unitPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('kg').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '0.5',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Start batch'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.extrasSent, hasLength(1));
    expect(api.extrasSent.single, hasLength(1));
    expect(api.extrasSent.single.single.ingredientId, 1);
    expect(api.extrasSent.single.single.quantity, 500);
  });
}
