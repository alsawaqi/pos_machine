import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/services/config_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final value in [null, '', 'garbage', 'SHADOW', 1, true, [], {}]) {
    test('absent or garbage mode $value parses as off', () {
      final parsed = ConfigMapper.parse({
        'settings': {'table_sessions_mode': ?value},
      });
      expect(parsed.meta.tableSessionsMode.value, 'off');
    });
  }

  for (final value in ['off', 'shadow', 'live']) {
    test('valid $value is preserved', () {
      final parsed = ConfigMapper.parse({
        'settings': {'table_sessions_mode': value},
      });
      expect(parsed.meta.tableSessionsMode.value, value);
    });
  }

  test(
    'config updates flip the provider without rebuilding its container',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      final subscription = container.listen(
        tableSessionsModeProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.read(tableShadowConfigProvider.future);
      expect(container.read(tableSessionsModeProvider), 'off');
      for (final value in ['shadow', 'live', 'off']) {
        final parsed = ConfigMapper.parse({
          'settings': {'table_sessions_mode': value},
        });
        await db.into(db.syncMeta).insertOnConflictUpdate(parsed.meta);
        await db.watchSyncMeta().firstWhere(
          (row) => row?.tableSessionsMode == value,
        );
        await container.pump();
        expect(container.read(tableSessionsModeProvider), value);
      }
    },
  );

  test(
    'Drift 28 to 29 preserves existing sync metadata and adds nullable mode',
    () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (raw) {
            raw.execute('''
        CREATE TABLE sync_meta (
          id INTEGER PRIMARY KEY DEFAULT 1, company_id INTEGER, branch_id INTEGER,
          last_config_sync_at INTEGER, config_schema_version TEXT,
          order_cancel_positions TEXT, reports_positions TEXT, kitchen_positions TEXT,
          order_numbering_json TEXT
        )
      ''');
            raw.execute(
              "INSERT INTO sync_meta (id, company_id, branch_id, config_schema_version) VALUES (1, 7, 9, 'keep')",
            );
            raw.execute('PRAGMA user_version = 28');
          },
        ),
      );
      addTearDown(db.close);
      final row = await db.watchSyncMeta().first;
      // LAUNCH-P4 moved the head to 30, the combo add-on to 31; the 28 ->
      // head upgrade still keeps
      // the row and adds the nullable mode.
      expect(db.schemaVersion, 31);
      expect(row?.companyId, 7);
      expect(row?.branchId, 9);
      expect(row?.configSchemaVersion, 'keep');
      expect(row?.tableSessionsMode, isNull);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        31,
      );
    },
  );
}
