import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/config_repository.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/session_service.dart';

/// P-F1 regression — the Phase B4 wiring bug: ConfigRepository used to drop
/// the parsed void/comp reason rows (replaceConfig's const-[] defaults wiped
/// the Drift tables on every full sync) and watchCatalog never read them
/// back, so the device's comp button and void-reason chips never appeared.
/// This pins the FULL pipeline: API payload → parse → Drift → catalog.
class _FakeApi implements PosApiService {
  _FakeApi(this.fullPayload);

  final Map<String, dynamic> fullPayload;
  Map<String, dynamic>? deltaPayload;
  int fullCalls = 0;
  int deltaCalls = 0;

  @override
  Future<
      ({
        Map<String, dynamic> data,
        String? terminalId,
        String? generatedAt,
        Map<String, dynamic>? websocket
      })> fetchConfig() async {
    fullCalls++;
    return (
      data: fullPayload,
      terminalId: null,
      generatedAt: 'CURSOR-$fullCalls',
      websocket: null,
    );
  }

  @override
  Future<
      ({
        Map<String, dynamic> data,
        String? terminalId,
        String? generatedAt,
        Map<String, dynamic>? websocket
      })> fetchConfigDelta(String since) async {
    deltaCalls++;
    final delta = deltaPayload;
    if (delta == null) throw StateError('no delta configured');
    return (
      data: delta,
      terminalId: null,
      generatedAt: 'CURSOR-D$deltaCalls',
      websocket: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('unexpected API call: ${invocation.memberName}');
}

class _FakeSession implements SessionService {
  @override
  Future<void> saveTerminalId(String? terminalId) async {}

  @override
  Future<void> saveWebsocketConfig(Map<String, dynamic>? config) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'unexpected session call: ${invocation.memberName}');
}

Map<String, dynamic> _payload() => <String, dynamic>{
      'branch': {'id': 6, 'name': 'Main'},
      'categories': [
        {'id': 1, 'name': 'Coffee', 'display_order': 1, 'status': 'active'},
      ],
      'products': <dynamic>[],
      'floors': <dynamic>[],
      'tables': <dynamic>[],
      'taxes': <dynamic>[],
      'void_reasons': [
        {
          'id': 75,
          'code': 'quality_issue',
          'name': 'Quality Issue',
          'name_ar': 'مشكلة جودة',
          'affects_inventory': true,
          'requires_manager': true,
          'sort_order': 3,
        },
        {
          'id': 73,
          'code': 'change_of_mind',
          'name': 'Customer Change of Mind',
          'affects_inventory': true,
          'requires_manager': false,
          'sort_order': 0,
        },
      ],
      'comp_reasons': [
        {
          'id': 49,
          'code': 'long_wait',
          'name': 'Long Wait',
          'max_amount_baisas': 5000,
          'sort_order': 0,
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('full sync lands void/comp reasons in the catalog (and keeps them '
      'across repeat syncs)', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = ConfigRepository(_FakeApi(_payload()), db, _FakeSession());

    await repo.fetchAndCache();

    final catalog = await repo
        .watchCatalog()
        .firstWhere(
            (c) => c.voidReasons.isNotEmpty && c.compReasons.isNotEmpty)
        .timeout(const Duration(seconds: 5));
    // Sorted by sort_order, full field mapping.
    expect(catalog.voidReasons.map((r) => r.code).toList(),
        ['change_of_mind', 'quality_issue']);
    expect(catalog.voidReasons.last.requiresManager, isTrue);
    expect(catalog.voidReasons.last.nameAr, 'مشكلة جودة');
    expect(catalog.compReasons.single.code, 'long_wait');
    expect(catalog.compReasons.single.maxAmount, closeTo(5.0, 1e-9));

    // The original bug: the SECOND full sync wiped the tables. Re-sync and
    // verify the reasons survive.
    await repo.fetchAndCache();
    final again = await repo
        .watchCatalog()
        .firstWhere(
            (c) => c.voidReasons.isNotEmpty && c.compReasons.isNotEmpty)
        .timeout(const Duration(seconds: 5));
    expect(again.voidReasons, hasLength(2));
    expect(again.compReasons, hasLength(1));
  });

  test('delta sync upserts changed reasons without dropping the rest',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final api = _FakeApi(_payload());
    final repo = ConfigRepository(api, db, _FakeSession());

    await repo.fetchAndCache(); // seeds the cursor

    // Delta: one renamed void reason + one brand-new comp reason.
    api.deltaPayload = <String, dynamic>{
      'void_reasons': [
        {
          'id': 75,
          'code': 'quality_issue',
          'name': 'Quality Problem',
          'affects_inventory': true,
          'requires_manager': true,
          'sort_order': 3,
        },
      ],
      'comp_reasons': [
        {
          'id': 50,
          'code': 'service_recovery',
          'name': 'Service Recovery',
          'sort_order': 1,
        },
      ],
    };
    await repo.syncConfig();
    expect(api.deltaCalls, 1);
    expect(api.fullCalls, 1, reason: 'delta must not fall back to full');

    final catalog = await repo
        .watchCatalog()
        .firstWhere((c) => c.compReasons.length == 2)
        .timeout(const Duration(seconds: 5));
    expect(catalog.voidReasons, hasLength(2)); // untouched row kept
    expect(
      catalog.voidReasons.firstWhere((r) => r.id == 75).name,
      'Quality Problem', // upserted
    );
    expect(catalog.compReasons.map((r) => r.code).toList(),
        ['long_wait', 'service_recovery']);
  });
}
