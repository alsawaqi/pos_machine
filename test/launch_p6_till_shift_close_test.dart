import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/shift_close_screen.dart';
import 'package:pos_machine/services/api_models.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/shift_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_order_storage.dart';

/// LAUNCH-P6 Part C item 9 (till) — the shift close lists unpaid tablet
/// orders (`GET device/tablet-orders?unpaid_only=1`) as a warning; it never
/// blocks the close.
class _Api implements PosApiService {
  List<dynamic> tablet = const [];
  bool fail = false;
  final asked = <bool>[];

  @override
  Future<List<dynamic>> fetchTabletOrders({bool unpaidOnly = false}) async {
    asked.add(unpaidOnly);
    if (fail) {
      throw ApiException(message: 'offline', code: 'network', isNetwork: true);
    }
    return tablet;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

Map<String, dynamic> row(String uuid, String type, {String? table}) => {
  'tablet_order_uuid': uuid,
  'order_uuid': 'o-$uuid',
  'order_type': type,
  'state': 'sent',
  'paid': false,
  'unpaid': true,
  'order_number': type == 'dine_in' ? null : '27',
  'table': table == null ? null : {'id': 5, 'uuid': 't', 'name': table},
  'lines': const <Object>[],
  'total_baisas': 2000,
  'grand_total_baisas': 2500,
};

void main() {
  setUp(() => debugOrderStorageOverride = FakeOrderStorage());
  tearDown(() => debugOrderStorageOverride = null);
  late SharedPreferences prefs;
  late SessionService session;
  late _Api api;
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'print_receipts': false});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    session = SessionService(const FlutterSecureStorage(), prefs);
    api = _Api();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await session.saveStaff(
      const StaffSessionData(
        id: 4,
        name: 'Sara',
        position: 'cashier',
        attendance: StaffAttendance(open: true, uuid: 'att-1'),
      ),
    );
    await session.saveOpenShift(
      OpenShiftData(
        uuid: 'shift-1',
        openingCashBaisas: 2000,
        openedAt: DateTime.utc(2026, 10, 6, 5),
        staffId: 4,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, {Locale? locale}) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionServiceProvider.overrideWithValue(session),
          apiServiceProvider.overrideWithValue(api),
          appDatabaseProvider.overrideWithValue(db),
          shiftServiceProvider.overrideWithValue(ShiftService(api)),
          connectivityProvider.overrideWith((ref) => Stream.value(true)),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const ShiftCloseScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('unpaid tablet orders are listed as a warning, not a block', (
    tester,
  ) async {
    api.tablet = [
      row('a', 'dine_in', table: '5'),
      row('b', 'to_go'),
      'a bad row',
    ];
    await pump(tester);
    expect(api.asked, [true]);
    expect(find.byKey(const ValueKey('tablet-unpaid-warning')), findsOneWidget);
    expect(find.text('2 tablet orders are still unpaid'), findsOneWidget);
    expect(find.text('Table 5 · Dine in · 2.500'), findsOneWidget);
    expect(find.text('#27 · To go · 2.500'), findsOneWidget);
    // Not a block: the close button stays available.
    final close = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Close shift'),
    );
    expect(close.onPressed, isNotNull);
  });

  testWidgets('Arabic warning', (tester) async {
    api.tablet = [row('b', 'to_go')];
    await pump(tester, locale: const Locale('ar'));
    expect(find.text('طلب واحد من الجهاز اللوحي لم يُدفع بعد'), findsOneWidget);
  });

  testWidgets('none unpaid, or offline: no warning', (tester) async {
    await pump(tester);
    expect(find.byKey(const ValueKey('tablet-unpaid-warning')), findsNothing);
    api.fail = true;
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    expect(find.byKey(const ValueKey('tablet-unpaid-warning')), findsNothing);
  });
}
