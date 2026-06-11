import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/branch_report.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/branch_reports_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F6 — the branch Reports dashboard: model decode, the
/// reports_positions access policy wiring, and the screen rendering a
/// fixture report at the T3's landscape size.
Map<String, dynamic> _fixture() => <String, dynamic>{
      'from': '2026-06-05',
      'to': '2026-06-11',
      'summary': {
        'orders': 42,
        'gross_baisas': 123456,
        'discount_baisas': 5000,
        'comp_baisas': 3000,
        'gift_baisas': 2000,
        'tax_baisas': 8000,
        'avg_order_baisas': 2939,
        'distinct_customers': 7,
        'loyalty_points_earned': 120,
        'loyalty_points_redeemed': 30,
        'loyalty_stamps_earned': 9,
        'loyalty_stamps_redeemed': 1,
      },
      'by_day': [
        {'date': '2026-06-05', 'total_baisas': 50000, 'orders': 20},
        {'date': '2026-06-06', 'total_baisas': 73456, 'orders': 22},
      ],
      'by_hour': [
        {'hour': 9, 'total_baisas': 30000, 'orders': 10},
        {'hour': 13, 'total_baisas': 93456, 'orders': 32},
      ],
      'by_method': [
        {'method': 'cash', 'total_baisas': 60000, 'count': 25},
        {'method': 'bank_pos', 'total_baisas': 63456, 'count': 17},
      ],
      'by_order_type': [
        {'order_type': 'dine_in', 'total_baisas': 100000, 'count': 30},
        {'order_type': 'quick', 'total_baisas': 23456, 'count': 12},
      ],
      'top_products': [
        {'name': 'White Mocha', 'qty': 18, 'total_baisas': 45000},
      ],
      'top_customers': [
        {'name': 'Ali', 'orders': 5, 'total_baisas': 20000},
      ],
      'discounts': [
        {'name': 'Happy Hour', 'amount_baisas': 5000, 'count': 4},
      ],
      'stock_consumption': [
        {'name': 'Milk', 'qty': 12.5, 'unit': 'L'},
      ],
    };

class _FakeApi implements PosApiService {
  bool fail = false;

  @override
  Future<BranchReport> fetchBranchReport({
    required DateTime from,
    required DateTime to,
  }) async {
    if (fail) throw ApiException(message: 'offline', isNetwork: true);
    return BranchReport.fromJson(_fixture());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected: ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BranchReport.fromJson decodes every section (baisas → OMR)', () {
    final r = BranchReport.fromJson(_fixture());
    expect(r.summary.orders, 42);
    expect(r.summary.gross, closeTo(123.456, 1e-9));
    expect(r.summary.gift, closeTo(2.0, 1e-9));
    expect(r.summary.loyaltyStampsEarned, 9);
    expect(r.byDay, hasLength(2));
    expect(r.byDay.first.total, closeTo(50.0, 1e-9));
    expect(r.byHour.last.hour, 13);
    expect(r.byMethod.map((m) => m.method), contains('bank_pos'));
    expect(r.byOrderType.first.orderType, 'dine_in');
    expect(r.topProducts.single.qty, 18);
    expect(r.topCustomers.single.name, 'Ali');
    expect(r.discounts.single.count, 4);
    expect(r.stockConsumption.single.unit, 'L');
    // Defensive: an empty body decodes to a zeroed report.
    expect(BranchReport.fromJson(const {}).isEmpty, isTrue);
  });

  test('reports_positions flows config → meta → catalog → controller gate',
      () {
    final parsed = ConfigMapper.parse(<String, dynamic>{
      'settings': {
        'order_cancel_positions': ['manager'],
        'reports_positions': ['manager', 'supervisor'],
      },
    });
    expect(parsed.meta.reportsPositions.value, '["manager","supervisor"]');

    final controller = PosController();
    addTearDown(controller.dispose);
    controller.applyCatalog(
      categories: const ['X'],
      products: const [],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      reportsPositions: const ['manager', 'supervisor'],
    );
    expect(controller.positionCanViewReports('Supervisor'), isTrue);
    expect(controller.positionCanViewReports('manager'), isTrue);
    expect(controller.positionCanViewReports('cashier'), isFalse);
    expect(controller.positionCanViewReports(null), isFalse);
  });

  testWidgets('the dashboard renders KPIs + sections from the report',
      (tester) async {
    tester.view.physicalSize = const Size(1700, 810);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiServiceProvider.overrideWithValue(api),
        ],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: BranchReportsScreen(branchName: 'Kaldi Azaiba'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Branch Reports'), findsOneWidget);
    expect(find.textContaining('Kaldi Azaiba'), findsOneWidget);
    expect(find.text('Gross Sales'), findsOneWidget);
    expect(find.text('Sales by Day'), findsOneWidget);
    expect(find.text('Payment Methods'), findsOneWidget);

    // The lower sections live below the fold of the scrolling dashboard.
    await tester.dragUntilVisible(
      find.text('Happy Hour'),
      find.byType(ListView),
      const Offset(0, -260),
    );
    expect(find.text('Top Products'), findsOneWidget);
    expect(find.text('White Mocha'), findsOneWidget);
    expect(find.text('Stock Consumption'), findsOneWidget);
    expect(find.textContaining('Milk'), findsOneWidget);
    expect(find.text('Happy Hour'), findsOneWidget);
  });

  testWidgets('a load failure shows the retry state, and retry recovers',
      (tester) async {
    tester.view.physicalSize = const Size(1700, 810);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiServiceProvider.overrideWithValue(api)],
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: BranchReportsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    api.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Gross Sales'), findsOneWidget);
  });
}
