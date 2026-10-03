// LAUNCH-P3 fix order 1 K3 (owner decision 2026-10-02: waste follows the
// selling rule — allow it, but warn): the server records a product waste
// larger than the shelf count and lists those products in the result's
// `shelf_shortfalls`. The till's Record waste screen names them in a warning
// instead of the plain "Recorded" message.
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
import 'package:pos_machine/screens/waste_product_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/expense_restock_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';

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

const _products = [
  Product(
    id: '11',
    name: 'Cheese cake',
    category: 'Cakes',
    price: 1.5,
    stockMode: 'cooked',
    branchStockQty: 1,
  ),
  Product(
    id: '12',
    name: 'Water',
    category: 'Drinks',
    price: 0.2,
    stockMode: 'unit',
    branchStockQty: 10,
  ),
];

Future<_SyncApi> _wasteTwoCakes(
  WidgetTester tester,
  Map<String, dynamic> result, {
  String locale = 'en',
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
              products: _products,
              floors: [],
              tables: [],
              taxes: [],
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
                  MaterialPageRoute(builder: (_) => const WasteProductScreen()),
                ),
                child: const Text('open waste'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open waste'));
  await tester.pumpAndSettle();

  // Rows: Cheese cake (1 on the shelf), Water, then the note field.
  await tester.enterText(find.byType(TextField).at(0), '2');
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return api;
}

void main() {
  test('reads the shortfall names; an older server answer means none', () {
    expect(
      wasteShelfShortfallNames({
        'wasted_lines': 1,
        'shelf_shortfalls': [
          {
            'product_id': 11,
            'name': 'Cheese cake',
            'wasted': '2.000',
            'on_shelf': '1.000',
          },
          {'product_id': 12, 'name': ''},
          'not a map',
        ],
      }),
      ['Cheese cake'],
    );
    expect(wasteShelfShortfallNames({'wasted_lines': 1}), isEmpty);
  });

  testWidgets('a waste past the shelf count is recorded with a warning', (
    tester,
  ) async {
    final api = await _wasteTwoCakes(tester, {
      'wasted_lines': 1,
      'total_qty': '2.000',
      'shelf_shortfalls': [
        {
          'product_id': 11,
          'name': 'Cheese cake',
          'wasted': '2.000',
          'on_shelf': '1.000',
        },
      ],
    });

    // The till never refused it: one event with the full 2 went to the server.
    expect(api.pushed, hasLength(1));
    expect(
      find.text(
        'Waste recorded. It was more than the shelf count of: Cheese cake. '
        'Those counts are now below zero.',
      ),
      findsOneWidget,
    );
    expect(find.text('Recorded waste for 1 product(s).'), findsNothing);
  });

  testWidgets('a waste the shelf covers keeps the plain message', (
    tester,
  ) async {
    await _wasteTwoCakes(tester, {'wasted_lines': 1, 'total_qty': '2.000'});

    expect(find.text('Recorded waste for 1 product(s).'), findsOneWidget);
    expect(find.textContaining('more than the shelf count'), findsNothing);
  });

  testWidgets('the warning is translated (ar)', (tester) async {
    await _wasteTwoCakes(tester, {
      'wasted_lines': 1,
      'shelf_shortfalls': [
        {'product_id': 11, 'name': 'Cheese cake'},
      ],
    }, locale: 'ar');

    expect(
      find.text(
        'تم تسجيل الهدر. كان أكثر من عدد الرف لـ: Cheese cake. '
        'أصبح عددها أقل من الصفر.',
      ),
      findsOneWidget,
    );
  });
}
