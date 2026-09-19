import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/data/table_shadow_repository.dart';
import 'package:pos_machine/data/table_sync_coordinator.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/qr_tables_screen.dart';
import 'package:pos_machine/screens/settings_screen.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/audience_service.dart';
import 'package:pos_machine/services/geofence_service.dart';
import 'package:pos_machine/services/live_sync.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/settings_service.dart';
import 'package:pos_machine/services/table_shadow_service.dart';

import 'dining_table_qr_sheet_test.dart' show T7SheetFlow, T7SheetGateway;
import 'support/fake_order_storage.dart';

// Every startup dependency is inert or memory-only. In particular the real
// coordinator provider must not reach LocalOrderStorageService.instance.
class _Outbox implements OrderSyncRepository {
  @override
  Future<int> flush() async => 0;
  @override
  Stream<List<OrderOutboxRow>> watchPending() => Stream.value([]);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected outbox operation: ${invocation.memberName}');
}

class _Coordinator implements TableSyncCoordinator {
  @override
  Future<void> Function(Map<String, dynamic> event, Map<String, dynamic> ack)?
  paymentAcknowledged;
  @override
  void Function(List<Map<String, dynamic>> lines)? validateRound;
  @override
  String? Function(int productId)? stockModeForProduct;
  @override
  Future<TablePaymentContext> Function(OrderSnapshot)? paymentContext;
  @override
  Future<bool> Function(DiningTableSession, List<Map<String, dynamic>>)?
  printRound;
  @override
  void Function(DiningTableSession, String, String)? bindBillIdentity;
  @override
  Future<void> hydrate() async {}
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Stream<List<TableSyncVerdict>> get verdicts => const Stream.empty();
  @override
  DiningTableSession? cachedSession(String tableId) => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected table operation: ${invocation.memberName}');
}

class _Shadow implements TableShadowRepository {
  @override
  List<LocalTableShadowView> Function()? localTables;
  @override
  Map<int, TableActivityBoardRow> get activityBoard => const {};
  @override
  Map<int, TableActivityBoardRow> get displayActivityBoard => const {};
  @override
  void setFloorPlanVisible(bool visible) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected shadow operation: ${invocation.memberName}');
}

class _NoDegraded extends TableDegradedController {
  @override
  TableDegradedState build() => const TableDegradedState();
}

class _AutoPrint implements QrRoundAutoPrintController {
  @override
  void start({required bool enabled}) {}
  @override
  void stop() {}
  @override
  Future<void> setEnabled(bool enabled) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected printer operation: ${invocation.memberName}',
  );
}

class _LiveSync implements LiveSyncService {
  @override
  void start() {}
  @override
  Future<void> stop() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected live sync: ${invocation.memberName}');
}

class _Audience implements AudienceService {
  @override
  Future<void> stop() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected audience operation: ${invocation.memberName}',
  );
}

class _Api implements PosApiService {
  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected network operation: ${invocation.memberName}',
  );
}

class _Harness {
  _Harness(this.preferences, this.gateway);
  final SharedPreferences preferences;
  final T7SheetGateway gateway;
}

Future<_Harness> _pumpPos(
  WidgetTester tester, {
  required String mode,
  required bool toggle,
}) async {
  SharedPreferences.setMockInitialValues({
    'terminal_id': 'TERM-T7',
    'kiosk_id': 'KIOSK-T7',
    'company_id': 9,
    'branch_id': 6,
    'show_legacy_qr_tables_tab': toggle,
    'staff_session_json': jsonEncode({
      'id': 7,
      'name': 'Test Cashier',
      'position': 'cashier',
      'branch_id': 6,
    }),
    'open_shift_json': jsonEncode({
      'uuid': 'shift-t7',
      'opening_cash_baisas': 0,
      'opened_at': '2026-09-06T08:00:00',
      'staff_id': 7,
    }),
  });
  final preferences = await SharedPreferences.getInstance();
  final session = SessionService(const FlutterSecureStorage(), preferences);
  await session.load();
  final gateway = T7SheetGateway(board: []);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
        sessionServiceProvider.overrideWithValue(session),
        releaseBuildProvider.overrideWithValue(true),
        apiServiceProvider.overrideWithValue(_Api()),
        appDatabaseProvider.overrideWith(
          (ref) => throw StateError(
            'The legacy-tab widget harness must never open a DB',
          ),
        ),
        tableSessionsModeProvider.overrideWithValue(mode),
        orderSyncRepositoryProvider.overrideWithValue(_Outbox()),
        tableSyncCoordinatorProvider.overrideWithValue(_Coordinator()),
        tableShadowRepositoryProvider.overrideWithValue(_Shadow()),
        remoteBoardProvider.overrideWith(
          (ref) => Stream.value(const RemoteTableSnapshot()),
        ),
        tableActivityNoticeProvider.overrideWith((ref) => const Stream.empty()),
        tableShadowConfigProvider.overrideWith((ref) => Stream.value(null)),
        degradedStateProvider.overrideWith(_NoDegraded.new),
        orderSyncAttentionProvider.overrideWith((ref) => Stream.value([])),
        stuckOrderSyncProvider.overrideWith((ref) => Stream.value([])),
        catalogProvider.overrideWith((ref) => const Stream.empty()),
        connectivityProvider.overrideWith((ref) => Stream.value(false)),
        geofenceProvider.overrideWith(
          (ref) => Stream.value(const GeofenceStatus(FenceState.disabled)),
        ),
        liveSyncProvider.overrideWithValue(_LiveSync()),
        audienceServiceProvider.overrideWithValue(_Audience()),
        qrRoundAutoPrintControllerProvider.overrideWithValue(_AutoPrint()),
        qrTillServiceProvider.overrideWithValue(gateway),
        qrRoundGatewayProvider.overrideWithValue(gateway),
        qrSettlementCoordinatorProvider.overrideWithValue(T7SheetFlow()),
        shiftReconciliationProvider.overrideWith((ref, staffId) async => null),
      ],
      child: const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: StaffPosScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(preferences, gateway);
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const rear = MethodChannel('pos_machine/rear_display_host');
  const printer = MethodChannel('sunmi_printer_plus');
  const toggleKey = ValueKey('settings-legacy-qr-tab-toggle');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugOrderStorageOverride = FakeOrderStorage();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      secure,
      (call) async => call.method == 'read' ? 't7-memory-token' : null,
    );
    messenger.setMockMethodCallHandler(
      rear,
      (call) async => call.method == 'getPresentationDisplays'
          ? <Map<String, dynamic>>[]
          : true,
    );
    messenger.setMockMethodCallHandler(printer, (call) async => null);
  });
  tearDown(() {
    debugOrderStorageOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [secure, rear, printer]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test(
    'setting defaults off and copyWith preserves unrelated settings',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final service = SettingsService(preferences);
      expect(service.showLegacyQrTablesTab, isFalse);
      expect(service.snapshot().showLegacyQrTablesTab, isFalse);
      const settings = AppSettings(
        printReceipts: false,
        printKitchenTickets: false,
        printQrKitchenRounds: true,
        language: 'ar',
        audienceMeasurement: true,
      );
      final enabled = settings.copyWith(showLegacyQrTablesTab: true);
      expect(enabled.showLegacyQrTablesTab, isTrue);
      expect(enabled.printReceipts, settings.printReceipts);
      expect(enabled.printKitchenTickets, settings.printKitchenTickets);
      expect(enabled.printQrKitchenRounds, settings.printQrKitchenRounds);
      expect(enabled.language, settings.language);
      expect(enabled.audienceMeasurement, settings.audienceMeasurement);
      expect(enabled.copyWith(language: 'en').showLegacyQrTablesTab, isTrue);
      expect(
        enabled.copyWith(showLegacyQrTablesTab: false).showLegacyQrTablesTab,
        isFalse,
      );
    },
  );

  test(
    'setting persists under the exact key and survives service recreation',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final service = SettingsService(preferences);
      await service.saveShowLegacyQrTablesTab(true);
      expect(preferences.getBool('show_legacy_qr_tables_tab'), isTrue);
      expect(
        SettingsService(preferences).snapshot().showLegacyQrTablesTab,
        isTrue,
      );
      await service.saveShowLegacyQrTablesTab(false);
      expect(preferences.getBool('show_legacy_qr_tables_tab'), isFalse);
      expect(
        SettingsService(preferences).snapshot().showLegacyQrTablesTab,
        isFalse,
      );
      expect(preferences.getKeys(), {'show_legacy_qr_tables_tab'});
    },
  );

  testWidgets(
    'Settings retires the legacy switch without rewriting its saved value',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            releaseBuildProvider.overrideWithValue(true),
            orderSyncAttentionProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: SettingsScreen(showOperations: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-unified-dine-in')),
      );
      expect(find.byKey(toggleKey), findsNothing);
      expect(find.text('Show the old QR Tables tab'), findsNothing);
      expect(find.text('Table orders are in Dine-In'), findsOneWidget);
      expect(preferences.getBool('show_legacy_qr_tables_tab'), isNull);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      expect(
        container.read(settingsControllerProvider).showLegacyQrTablesTab,
        isFalse,
      );
      await _dispose(tester);
    },
  );

  for (final mode in ['off', 'shadow', 'live']) {
    for (final enabled in [false, true]) {
      testWidgets(
        'actual nav $mode old toggle=$enabled exposes no separate QR Tables',
        (tester) async {
          tester.view.physicalSize = const Size(1600, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final harness = await _pumpPos(tester, mode: mode, toggle: enabled);
          expect(find.byType(StaffPosScreen), findsOneWidget);
          expect(find.text('QR Tables'), findsNothing);
          expect(find.text('Offers'), findsOneWidget);
          expect(find.text('Messages'), findsOneWidget);
          expect(harness.gateway.calls, isEmpty);
          expect(find.byType(QrTablesScreen), findsNothing);
          expect(
            harness.preferences.getBool('show_legacy_qr_tables_tab'),
            enabled,
          );
          debugPrint(
            'T7_LEGACY_TAB_MATRIX mode=$mode toggle=$enabled '
            'visible=false legacy_route=retired',
          );
          await _dispose(tester);
        },
      );
    }

    testWidgets('Settings return cannot restore QR Tables in $mode', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = await _pumpPos(tester, mode: mode, toggle: false);
      for (final enabled in [true, false]) {
        await tester.tap(find.byIcon(Icons.settings_outlined));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settings-unified-dine-in')),
          300,
          scrollable: find
              .descendant(
                of: find.byType(SettingsScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.byKey(toggleKey), findsNothing);
        await harness.preferences.setBool('show_legacy_qr_tables_tab', enabled);
        await tester.pumpAndSettle();
        expect(
          harness.preferences.getBool('show_legacy_qr_tables_tab'),
          enabled,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('QR Tables'), findsNothing);
      }
      expect(harness.gateway.calls, isEmpty);
      debugPrint(
        'T7_LEGACY_TAB_RETURN mode=$mode toggle=true,false '
        'visible=false,false',
      );
      await _dispose(tester);
    });
  }
}
