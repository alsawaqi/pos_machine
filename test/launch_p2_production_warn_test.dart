// LAUNCH-P2 (owner decision 2026-10-02): kitchen production follows the
// selling rule — never blocked by the stock numbers. A cooked product the
// books say "can make 0" of still opens, the start dialog only warns, and
// Start sends the batch; the server lets the ingredients go below zero.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/kitchen_production.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/kitchen_production_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';

void main() {
  testWidgets('a batch the books cannot cover still starts, with a warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font draws every glyph as a full square, so the existing
    // "Extra ingredients (declared)" + "Add extra" header row of the fixed
    // 460 px dialog overflows here (not with the device font). Ignore only
    // that layout warning; every other error still fails the test.
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
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const KitchenProductionScreen(staffId: 7, staffName: 'Sami'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The tile shows the shortfall as a warning, but it is not blocked.
    expect(find.text('Cake'), findsOneWidget);
    expect(find.text('Can make up to 0'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.block_rounded), findsNothing);

    await tester.tap(find.text('Cake'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The dialog warns that the stock will go below zero...
    expect(
      find.text(
        'Not enough on the books for that quantity. You can still start; '
        'the ingredient stock will go below zero.',
      ),
      findsOneWidget,
    );
    // ...and Start is enabled anyway.
    final start = find.widgetWithText(FilledButton, 'Start batch');
    expect(tester.widget<FilledButton>(start).onPressed, isNotNull);

    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.started, [(productId: 1, quantity: 1)]);
  });
}

class _KitchenApi implements PosApiService {
  final started = <({int productId, int quantity})>[];

  @override
  Future<KitchenData> fetchKitchen() async => KitchenData.fromJson({
    'products': [
      {
        'id': 1,
        'uuid': 'u-1',
        'name': 'Cake',
        'name_ar': null,
        'category_id': 7,
        'branch_stock_qty': 0.0,
        // The books hold 0.2 kg of flour; one cake needs 0.5 kg.
        'max_producible': 0,
        'recipe': [
          {
            'ingredient_id': 5,
            'name': 'Flour',
            'name_ar': null,
            'quantity': 0.5,
            'unit': 'kg',
            'branch_balance': 0.2,
          },
        ],
      },
    ],
    'ingredients': [
      {'id': 5, 'name': 'Flour', 'unit': 'kg', 'branch_balance': 0.2},
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
    started.add((productId: productId, quantity: quantity));
    return ProductionBatch.fromJson({
      'uuid': 'p-1',
      'status': 'in_progress',
      'product_id': productId,
      'product_name': 'Cake',
      'quantity': quantity.toDouble(),
      'started_at': '2026-10-02T10:00:00+04:00',
      'started_by': 'Sami',
      'lines': <Object>[],
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
