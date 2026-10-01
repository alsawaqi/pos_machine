import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/device_location_mode.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';

typedef _ConfigResult = ({
  Map<String, dynamic> data,
  String? terminalId,
  String? terminalPin,
      SoftPosProfile softpos,
  String? generatedAt,
  Map<String, dynamic>? websocket,
  bool? audienceMeasurement,
  DeviceLocationMode? locationMode,
});

class _Api implements PosApiService {
  Map<String, dynamic> full = _full('off');
  Map<String, dynamic> delta = {};
  bool failDelta = false;
  bool failFull = false;
  int fullCalls = 0;
  final cursors = <String>[];

  _ConfigResult _result(Map<String, dynamic> data, String cursor) => (
    data: data,
    terminalId: null,
    softpos: const SoftPosProfile(),
    terminalPin: null,
    generatedAt: cursor,
    websocket: null,
    audienceMeasurement: null,
    locationMode: null,
  );

  @override
  Future<_ConfigResult> fetchConfig() async {
    fullCalls++;
    if (failFull) throw StateError('Full config unavailable');
    return _result(full, 'full-$fullCalls');
  }

  @override
  Future<_ConfigResult> fetchConfigDelta(String since) async {
    cursors.add(since);
    if (failDelta) throw StateError('Delta unavailable');
    return _result(delta, 'delta-${cursors.length}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected API call: ${invocation.memberName}');
}

class _Session implements SessionService {
  @override
  Future<void> saveSoftpos(SoftPosProfile value) async {}
  @override
  Future<void> saveTerminalId(String? value) async {}
  @override
  Future<void> saveTerminalPin(String? value) async {}
  @override
  Future<void> saveWebsocketConfig(Map<String, dynamic>? value) async {}
  @override
  Future<void> saveServerAudienceMeasurement(bool? value) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected session call: ${invocation.memberName}');
}

Map<String, dynamic> _full(String mode) => {
  'branch': {'id': 10, 'company_id': 100, 'name': 'Test branch'},
  'settings': {'table_sessions_mode': mode},
  'floors': [
    {'id': 601, 'name': 'Main hall', 'display_order': 0},
  ],
  'tables': [
    {'id': 1001, 'floor_id': 601, 'label': 'T1', 'seats': 4},
  ],
  'categories': [
    {'id': 11, 'name': 'Unchanged category', 'display_order': 0},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late _Api api;
  late ConfigRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _Api();
    repository = ConfigRepository(api, db, _Session());
  });
  tearDown(() => db.close());

  test(
    'periodic delta updates Off/Live/Shadow without login or full fetch',
    () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      final subscription = container.listen(
        tableSessionsModeProvider,
        (_, _) {},
      );
      addTearDown(() {
        subscription.close();
        container.dispose();
      });
      await repository.fetchAndCache();
      await container.read(tableShadowConfigProvider.future);
      expect(container.read(tableSessionsModeProvider), 'off');

      final payload = jsonEncode([
        {'client_event_id': 'keep-me', 'event_type': 'table.session.open'},
      ]);
      await db
          .into(db.orderOutbox)
          .insert(
            OrderOutboxCompanion.insert(
              orderUuid: 'tbl:preserve:open',
              eventsJson: payload,
              createdAt: DateTime.utc(2026, 9, 4),
              attempts: const Value(10),
              serverRejections: const Value(5),
              lastError: const Value('Keep the rejected action for review'),
            ),
          );
      final pending = await db.getOutbox('tbl:preserve:open');
      final tables = await db.select(db.posTables).get();
      final categories = await db.select(db.categories).get();

      for (final mode in ['live', 'shadow', 'off', 'live']) {
        api.delta = {
          'settings': {'table_sessions_mode': mode},
        };
        await repository.syncConfig();
        final meta = await db.getSyncMeta();
        expect(meta?.tableSessionsMode, mode);
        expect(meta?.companyId, 100);
        expect(meta?.branchId, 10);
        expect(meta?.configSchemaVersion, 'delta-${api.cursors.length}');
        await db.watchSyncMeta().firstWhere(
          (row) => row?.tableSessionsMode == mode,
        );
        await container.pump();
        expect(container.read(tableSessionsModeProvider), mode);
        expect(await db.getOutbox('tbl:preserve:open'), pending);
        expect(await db.select(db.posTables).get(), tables);
        expect(await db.select(db.categories).get(), categories);
      }
      expect(api.fullCalls, 1);
      expect(api.cursors, ['full-1', 'delta-1', 'delta-2', 'delta-3']);
      expect(db.schemaVersion, 29);
    },
  );

  final invalidSettings = <String, Map<String, dynamic>>{
    'missing block': {},
    'missing key': {'settings': <String, dynamic>{}},
    for (final value in [null, '', 'LIVE', 'invalid', true, 1, [], {}])
      'invalid $value': {
        'settings': {'table_sessions_mode': value},
      },
  };
  for (final entry in invalidSettings.entries) {
    test(
      'authoritative delta ${entry.key} fails closed from Live to Off',
      () async {
        api.full = _full('live');
        await repository.fetchAndCache();
        expect((await db.getSyncMeta())?.tableSessionsMode, 'live');
        api.delta = entry.value;
        await repository.syncConfig();
        expect((await db.getSyncMeta())?.tableSessionsMode, 'off');
        expect(api.fullCalls, 1);
        expect(api.cursors, ['full-1']);
      },
    );
  }

  test('failed delta falls back to a full authoritative mode update', () async {
    await repository.fetchAndCache();
    api.failDelta = true;
    api.full = _full('live');
    await repository.syncConfig();
    expect((await db.getSyncMeta())?.tableSessionsMode, 'live');
    expect(api.fullCalls, 2);
    expect(api.cursors, ['full-1']);
  });

  test(
    'unavailable delta and full fetch preserve the last saved config',
    () async {
      api.full = _full('live');
      await repository.fetchAndCache();
      final before = await db.getSyncMeta();
      api.failDelta = true;
      api.failFull = true;
      await expectLater(repository.syncConfig(), throwsStateError);
      expect(await db.getSyncMeta(), before);
      expect(api.fullCalls, 2);
    },
  );
}
