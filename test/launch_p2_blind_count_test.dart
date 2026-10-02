import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/stock_count_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';

/// LAUNCH-P2 P2-6 blind counts on the till: the day-end count screen never
/// shows the system / on-book quantity before submit, and it still sends the
/// exact launch-p1 `stock.count` event (old and new servers both accept it).

/// Records every pushed sync event and answers with one settled result.
class _SyncApi implements PosApiService {
  _SyncApi(this.result);
  final Map<String, dynamic> result;
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
          'result': result,
        },
      ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected API ${i.memberName}');
}

/// The post-submit config refresh is best-effort; nothing to sync here.
class _NoConfigSync implements ConfigRepository {
  @override
  Future<void> syncConfig({bool preferDelta = true}) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw StateError('Unexpected config call ${i.memberName}');
}

const _ingredients = [
  // Piece-counted: counted in bottles of 1.5 l.
  IngredientRef(
    id: 1,
    name: 'Milk',
    unit: 'l',
    pieceUnitLabel: 'bottle',
    unitsPerPiece: 1.5,
  ),
  IngredientRef(id: 2, name: 'Flour', unit: 'kg'),
  IngredientRef(id: 3, name: 'Saffron'),
];

// Distinctive book balances that must never reach the screen.
const _balances = <int, double>{1: 12.25, 2: 37.75, 3: 4.125};

Future<_SyncApi> _pumpCount(
  WidgetTester tester, {
  String locale = 'en',
  Map<String, dynamic> result = const {
    'stock_count_id': 81,
    'lines': 2,
    'lines_with_variance': 1,
  },
}) async {
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
  final api = _SyncApi(result);
  tester.view.physicalSize = const Size(1280, 900);
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
              ingredientBalances: _balances,
            ),
          ),
        ),
        expenseRestockServiceProvider.overrideWithValue(
          ExpenseRestockService(api),
        ),
        configRepositoryProvider.overrideWithValue(_NoConfigSync()),
      ],
      child: MaterialApp(
        locale: Locale(locale),
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

Iterable<String> _visibleTexts(WidgetTester tester) sync* {
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    yield widget.data ?? widget.textSpan?.toPlainText() ?? '';
  }
  for (final element in find.byType(EditableText).evaluate()) {
    yield (element.widget as EditableText).controller.text;
  }
}

void main() {
  for (final locale in ['en', 'ar']) {
    testWidgets('the count screen never shows the book quantity before '
        'submit ($locale)', (tester) async {
      await _pumpCount(tester, locale: locale);
      expect(find.byType(StockCountScreen), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);

      final texts = _visibleTexts(tester).join('\n');
      for (final number in ['12.25', '12.250', '37.75', '37.750', '4.125']) {
        expect(texts, isNot(contains(number)));
      }
      expect(texts, isNot(contains('On book')));
      expect(texts, isNot(contains('on book')));
      expect(texts, isNot(contains('الرصيد الدفتري')));

      // Staff are told what to count in — never how much is expected.
      if (locale == 'en') {
        expect(find.text('Count in bottles'), findsOneWidget);
        expect(find.text('Count in kg'), findsOneWidget);
      } else {
        expect(find.text('العدّ بوحدة bottle'), findsOneWidget);
        expect(find.text('العدّ بوحدة kg'), findsOneWidget);
      }
    });
  }

  testWidgets('submit sends the unchanged launch-p1 stock.count event', (
    tester,
  ) async {
    final api = await _pumpCount(tester);
    final fields = find.byType(TextField);
    // Rows: Milk, Flour, Saffron, then the note field.
    await tester.enterText(fields.at(0), '4');
    await tester.enterText(fields.at(1), '30.5');
    await tester.pump();
    await tester.tap(find.text('Submit count (2)'));
    await tester.pumpAndSettle();

    expect(api.pushed, hasLength(1));
    final event = api.pushed.single;
    // launch-p1 shape: exactly these keys, no new fields.
    expect(event.keys.toSet(), {
      'client_event_id',
      'event_type',
      'client_timestamp',
      'payload',
    });
    expect(event['event_type'], 'stock.count');
    expect(event['client_event_id'], isA<String>());
    expect(
      DateTime.tryParse(event['client_timestamp'] as String)?.isUtc,
      isTrue,
    );
    expect(event['payload'], {
      'lines': [
        {'ingredient_id': 1, 'counted_pieces': 4.0},
        {'ingredient_id': 2, 'counted_units': 30.5},
      ],
      'staff_id': 7,
    });
    // Variance only AFTER submit, as the server reports it.
    expect(
      find.text('Count submitted — 1 line(s) had a variance.'),
      findsOneWidget,
    );
  });

  testWidgets('a result without a variance figure is confirmed neutrally', (
    tester,
  ) async {
    await _pumpCount(tester, result: const {'stock_count_id': 82, 'lines': 1});
    await tester.enterText(find.byType(TextField).at(1), '12');
    await tester.pump();
    await tester.tap(find.text('Submit count (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Count submitted.'), findsOneWidget);
    expect(find.textContaining('matched the books'), findsNothing);
  });
}
