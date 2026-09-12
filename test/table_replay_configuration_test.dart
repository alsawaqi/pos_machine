import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/table_replay_configuration.dart';
import 'package:pos_machine/services/config_mapper.dart';

void main() {
  late AppDatabase db;
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final config = ConfigMapper.parse({
      'branch': {'id': 10, 'company_id': 100},
      'tables': [
        {'id': 1001, 'floor_id': 601, 'label': 'T1', 'seats': 4},
      ],
    });
    await db.into(db.syncMeta).insert(config.meta);
    for (final table in config.tables) {
      await db.into(db.posTables).insert(table);
    }
    await db
        .into(db.orderOutbox)
        .insert(
          OrderOutboxCompanion.insert(
            orderUuid: 'tbl:preserved',
            eventsJson: '[{"evidence":true}]',
            createdAt: DateTime(2026, 9, 4),
            attempts: const Value(10),
            serverRejections: const Value(5),
            lastError: const Value('old refusal'),
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'paired config supplies immutable table IDs without changing stored data',
    () async {
      final before = await db.getOutbox('tbl:preserved');
      final meta = await db.getSyncMeta();
      final tables = await db.select(db.posTables).get();
      final config = await TableReplayConfiguration.read(
        db,
        scope: 'server/100/10/till',
        companyId: 100,
        branchId: 10,
      );
      expect(config?.tableIds, {'1001'});
      expect(config?.scope, 'server/100/10/till');
      expect(() => config!.tableIds.add('1'), throwsUnsupportedError);
      expect(await db.getOutbox('tbl:preserved'), before);
      expect(await db.getSyncMeta(), meta);
      expect(await db.select(db.posTables).get(), tables);
    },
  );

  for (final pair in [
    (null, 10),
    (100, null),
    (0, 10),
    (100, 0),
    (1, 10),
    (100, 1),
  ]) {
    test(
      'unverified company/branch $pair cannot admit cached tables',
      () async {
        final before = await db.getOutbox('tbl:preserved');
        expect(
          await TableReplayConfiguration.read(
            db,
            scope: 'scope',
            companyId: pair.$1,
            branchId: pair.$2,
          ),
          isNull,
        );
        expect(await db.getOutbox('tbl:preserved'), before);
      },
    );
  }

  test('missing cache metadata or device scope fails closed', () async {
    expect(
      await TableReplayConfiguration.read(
        db,
        scope: '',
        companyId: 100,
        branchId: 10,
      ),
      isNull,
    );
    await db.delete(db.syncMeta).go();
    expect(
      await TableReplayConfiguration.read(
        db,
        scope: 'scope',
        companyId: 100,
        branchId: 10,
      ),
      isNull,
    );
  });
}
