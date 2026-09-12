import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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

import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/services/audience_service.dart';
import 'package:pos_machine/services/geofence_service.dart';
import 'package:pos_machine/services/live_sync.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/session_service.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'qr_quick_evidence.dart';

import 'package:pos_machine/services/table_shadow_service.dart';

import 'dining_table_qr_sheet_test.dart' show T7SheetFlow, T7SheetGateway;

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

class WorkspaceMachineHarness {
  WorkspaceMachineHarness(this.preferences, this.gateway);
  final SharedPreferences preferences;
  final T7SheetGateway gateway;
}

Future<WorkspaceMachineHarness> pumpWorkspaceMachine(
  WidgetTester tester, {
  required String mode,
  required bool toggle,
  bool arabic = false,
  required CatalogSnapshot catalog,
}) async {
  SharedPreferences.setMockInitialValues({
    'app_language': arabic ? 'ar' : 'en',
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
        catalogProvider.overrideWith((ref) => Stream.value(catalog)),
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
      child: MaterialApp(
        theme: ThemeData(fontFamily: 'QuickEvidence'),
        locale: Locale(arabic ? 'ar' : 'en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: RepaintBoundary(key: quickEvidenceKey, child: StaffPosScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return WorkspaceMachineHarness(preferences, gateway);
}

Future<void> disposeWorkspaceMachine(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}
