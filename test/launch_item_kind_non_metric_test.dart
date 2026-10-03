// LAUNCH item kind addendum (owner decision 2026-10-03): every Liquid item
// can also be typed in US gallons and fl oz, and every Weighed item in lb and
// oz, always labelled with their size. The till converts to the stored unit
// (g / ml, or legacy kg / l) with the exact factors before sending.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/count_units.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/stock_count_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';

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
          'result': {'stock_count_id': 1, 'lines': 2},
        },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API ${i.memberName}');
}

class _NoConfigSync implements ConfigRepository {
  @override
  Future<void> syncConfig({bool preferDelta = true}) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected config call ${i.memberName}');
}

void main() {
  group('exact non-metric factors', () {
    test('liquids: US gallon and fl oz', () {
      expect(toStoredUnits(1, 'gal', 'ml'), 3785.4118);
      expect(toStoredUnits(2, 'gal', 'l'), 7.5708);
      expect(toStoredUnits(1, 'fl oz', 'ml'), 29.5735);
      expect(toStoredUnits(128, 'fl oz', 'ml'), 3785.4118); // 1 gallon
    });

    test('weighed: lb and oz', () {
      expect(toStoredUnits(1, 'lb', 'g'), 453.5924);
      expect(toStoredUnits(2, 'lb', 'kg'), 0.9072);
      expect(toStoredUnits(16, 'oz', 'g'), 453.5924); // 1 lb
      expect(toStoredUnits(1, 'oz', 'g'), 28.3495);
    });

    test('the non-metric units say their size', () {
      expect(countUnitLabel('gal'), 'gal (3.785 l)');
      expect(countUnitLabel('fl oz'), 'fl oz (29.57 ml)');
      expect(countUnitLabel('lb'), 'lb (453.6 g)');
      expect(countUnitLabel('oz'), 'oz (28.35 g)');
      expect(countUnitLabel('kg'), 'kg');
    });

    test('a counted item offers none of them', () {
      expect(countUnitChoices('piece'), isEmpty);
    });
  });

  testWidgets('a count in gallons and pounds is sent in ml and g', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'staff_session_json': jsonEncode({
        'id': 7,
        'name': 'Test Cashier',
        'position': 'cashier',
        'branch_id': 6,
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final session = SessionService(const FlutterSecureStorage(), prefs);
    final api = _SyncApi();
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(session),
          catalogProvider.overrideWith(
            (ref) => Stream.value(
              const CatalogSnapshot(
                categories: [],
                products: [],
                floors: [],
                tables: [],
                taxes: [],
                ingredients: [
                  IngredientRef(id: 1, name: 'Oil', unit: 'ml'),
                  IngredientRef(id: 2, name: 'Beef', unit: 'g'),
                ],
              ),
            ),
          ),
          expenseRestockServiceProvider.overrideWithValue(
            ExpenseRestockService(api),
          ),
          configRepositoryProvider.overrideWithValue(_NoConfigSync()),
        ],
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StockCountScreen(),
                    ),
                  ),
                  child: const Text('open count'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open count'));
    await tester.pumpAndSettle();

    // The chips name their size.
    expect(find.text('gal (3.785 l)'), findsOneWidget);
    expect(find.text('lb (453.6 g)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('count-unit-1-gal')));
    await tester.tap(find.byKey(const ValueKey('count-unit-2-lb')));
    await tester.pump();
    expect(find.text('Count in gal (3.785 l)'), findsOneWidget);
    final fields = find.byType(TextField);
    // Rows: Oil, Beef, then the note field.
    await tester.enterText(fields.at(0), '2'); // 2 gallons of oil
    await tester.enterText(fields.at(1), '10'); // 10 lb of beef
    await tester.pump();
    await tester.tap(find.text('Submit count (2)'));
    await tester.pumpAndSettle();

    expect(api.pushed.single['payload']['lines'], [
      {'ingredient_id': 1, 'counted_units': 7570.8236},
      {'ingredient_id': 2, 'counted_units': 4535.9237},
    ]);
  });
}
