// LAUNCH item kind (owner decision 2026-10-03): a Weighed ingredient can be
// counted in kg or g and a Liquid one in l or ml; the till converts the
// count to the ingredient's stored unit, so the `stock.count` event keeps
// its launch-p1 shape. Counted (piece) ingredients are unchanged.
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
          'result': {'stock_count_id': 1, 'lines': 1},
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

const _ingredients = [
  IngredientRef(id: 1, name: 'Milk', unit: 'ml'),
  IngredientRef(id: 2, name: 'Flour', unit: 'g'),
  IngredientRef(id: 3, name: 'Rice', unit: 'kg'),
  IngredientRef(id: 4, name: 'Eggs', unit: 'piece'),
];

Future<_SyncApi> _pumpCount(WidgetTester tester) async {
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
              ingredients: _ingredients,
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
                  MaterialPageRoute(builder: (_) => const StockCountScreen()),
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
  return api;
}

Map<int, Object?> _countedUnits(_SyncApi api) => {
      for (final l in (api.pushed.single['payload']['lines'] as List))
        (l as Map)['ingredient_id'] as int: l['counted_units'],
    };

void main() {
  group('countUnitChoices', () {
    test('weighed and liquid items offer both units, largest first', () {
      expect(countUnitChoices('g'), ['kg', 'g']);
      expect(countUnitChoices('kg'), ['kg', 'g']);
      expect(countUnitChoices('ml'), ['l', 'ml']);
      expect(countUnitChoices('L'), ['l', 'ml']);
    });

    test('counted items and custom units offer none', () {
      expect(countUnitChoices('piece'), isEmpty);
      expect(countUnitChoices('box'), isEmpty);
      expect(countUnitChoices(null), isEmpty);
    });
  });

  group('toStoredUnits', () {
    test('converts to the stored unit at the ledger precision', () {
      expect(toStoredUnits(12, 'l', 'ml'), 12000);
      expect(toStoredUnits(12.345, 'kg', 'g'), 12345);
      expect(toStoredUnits(250, 'g', 'kg'), 0.25);
      expect(toStoredUnits(0.5, 'ml', 'l'), 0.0005);
      expect(toStoredUnits(0.4, 'ml', 'l'), 0.0004);
      expect(toStoredUnits(3, 'ml', 'ml'), 3);
    });
  });

  testWidgets('each weighed / liquid line offers its two units; '
      'pieces offer none', (tester) async {
    await _pumpCount(tester);
    expect(find.byKey(const ValueKey('count-unit-1-l')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-unit-1-ml')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-unit-2-kg')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-unit-2-g')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-unit-3-kg')), findsOneWidget);
    expect(find.byKey(const ValueKey('count-unit-4-piece')), findsNothing);
    // The largest unit is picked until staff switch it.
    expect(find.text('Count in l'), findsOneWidget);
    expect(find.text('Count in kg'), findsNWidgets(2));
  });

  testWidgets('the count is sent in the stored unit', (tester) async {
    final api = await _pumpCount(tester);
    final fields = find.byType(TextField);
    // Rows: Milk, Flour, Rice, Eggs, then the note field.
    await tester.enterText(fields.at(0), '12'); // 12 l of milk
    await tester.tap(find.byKey(const ValueKey('count-unit-2-g')));
    await tester.pump();
    await tester.enterText(fields.at(1), '250'); // 250 g of flour
    await tester.enterText(fields.at(2), '30.5'); // 30.5 kg of rice
    await tester.enterText(fields.at(3), '6'); // 6 eggs
    await tester.pump();
    await tester.tap(find.text('Submit count (4)'));
    await tester.pumpAndSettle();

    expect(api.pushed, hasLength(1));
    expect(_countedUnits(api), {1: 12000.0, 2: 250.0, 3: 30.5, 4: null});
    // Counted items keep the launch-p1 piece line.
    expect(
      (api.pushed.single['payload']['lines'] as List).last,
      {'ingredient_id': 4, 'counted_pieces': 6.0},
    );
    expect(find.text('Count in g'), findsNothing); // screen closed
  });

  testWidgets('switching a line back to the large unit converts again', (
    tester,
  ) async {
    final api = await _pumpCount(tester);
    await tester.tap(find.byKey(const ValueKey('count-unit-1-ml')));
    await tester.pump();
    expect(find.text('Count in ml'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('count-unit-1-l')));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '1.5');
    await tester.pump();
    await tester.tap(find.text('Submit count (1)'));
    await tester.pumpAndSettle();

    expect(_countedUnits(api), {1: 1500.0});
  });
}
