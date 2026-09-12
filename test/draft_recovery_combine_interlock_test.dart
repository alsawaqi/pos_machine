import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/bill_combine/combine_local.dart';
import 'package:pos_machine/bill_combine/combine_models.dart';
import 'package:pos_machine/bill_combine/combine_store.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';

import 'bill_combine_test.dart' show previewJson, seatingId;
import 'draft_recovery_test.dart' show RecoveryHarness, recoveryId;

void main() {
  sqfliteFfiInit();
  late RecoveryHarness h;
  late CombineStore combine;
  late CombineAttempt combination;
  late RecoveryAttempt recovery;
  setUp(() async {
    h = RecoveryHarness();
    await h.init();
    combination = await _combineAttempt(h);
    combine = CombineStore(h.db, 'another-device-scope');
    final local = await h.local(1);
    final preview = RecoveryPreview(h.api.previewJson);
    recovery = RecoveryAttempt({
      'id': recoveryId,
      'state': 'pending',
      'local': local.json,
      'preview': preview.json,
      'delta': local.delta(preview),
    });
  });
  tearDown(() => h.close());

  test(
    'valid separate-table combine remains available with no saved recovery',
    () async {
      final before = await _originals(h);

      await combine.create(combination);

      expect((await combine.active())!.encoded, combination.encoded);
      expect(await h.store.active(), isNull);
      expect(await _originals(h), before);
    },
  );

  test(
    'pending recovery blocks foreign-scope combine without changing raw rows',
    () async {
      // Both inputs independently match real stored drafts. The refusal must
      // come from the other journal, not a malformed synthetic CombineAttempt.
      await combine.verifyLocal(combination.local);
      await h.store.create(recovery);
      final before = await _allRows(h);

      await expectLater(combine.create(combination), throwsStateError);

      expect(await _allRows(h), before);
      expect(await combine.active(), isNull);
      expect((await h.store.active())!.encoded, recovery.encoded);
    },
  );

  test(
    'pending combine reciprocally blocks recovery without changing raw rows',
    () async {
      await combine.create(combination);
      final before = await _allRows(h);

      await expectLater(h.store.create(recovery), throwsStateError);

      expect(await _allRows(h), before);
      expect((await combine.active())!.encoded, combination.encoded);
      expect(await h.store.active(), isNull);
    },
  );

  for (final first in ['combine', 'recovery']) {
    test(
      'concurrent journal creation admits only the first transaction ($first)',
      () async {
        final before = await _originals(h);
        // Queue both preparations before awaiting either. A guard outside its
        // creation transaction could let both observe empty journals and write.
        final results = await Future.wait([
          if (first == 'combine') ...[
            _result(combine.create(combination)),
            _result(h.store.create(recovery)),
          ] else ...[
            _result(h.store.create(recovery)),
            _result(combine.create(combination)),
          ],
        ]);

        expect(results, ['created', 'refused']);
        final combines = await h.db.query('bill_combine_journal');
        final recoveries = await h.db.query('draft_recovery_journal');
        expect(combines.length + recoveries.length, 1);
        expect(combines, first == 'combine' ? hasLength(1) : isEmpty);
        expect(recoveries, first == 'recovery' ? hasLength(1) : isEmpty);
        expect(await _originals(h), before);
      },
    );
  }

  test(
    'a corrupt terminal recovery label cannot authorize a combine',
    () async {
      await h.db.insert('draft_recovery_journal', {
        'id': recoveryId,
        'scope': 'old-device-scope',
        'state': 'done',
        'payload': '{broken',
      });
      final before = await _allRows(h);

      await expectLater(combine.create(combination), throwsFormatException);

      expect(await _allRows(h), before);
      expect(await combine.active(), isNull);
    },
  );
  for (final corrupt in ['unknown', 'terminal JSON', 'columns', 'scope']) {
    test('recovery refuses $corrupt in any older combine history', () async {
      final terminal = combination.withState('not_applied');
      await h.db.insert('bill_combine_journal', {
        'id': corrupt == 'columns' ? 'different' : terminal.id,
        'scope': corrupt == 'scope' ? '' : 'other-old-device',
        'state': corrupt == 'unknown' ? 'future_unknown' : 'not_applied',
        'payload': corrupt == 'terminal JSON' ? '{bad' : terminal.encoded,
      });
      final before = await _allRows(h);
      await expectLater(h.store.create(recovery), throwsFormatException);
      expect(await _allRows(h), before);
    });
  }
}

Future<String> _result(Future<void> operation) async {
  try {
    await operation;
    return 'created';
  } on StateError {
    return 'refused';
  }
}

Future<CombineAttempt> _combineAttempt(RecoveryHarness h) async {
  const source = '66666666-6666-4666-8666-666666666666';
  await h.db.insert('held_orders', {
    'id': 'separate-combine-draft',
    'order_type': 'dine_in',
    'draft_json': jsonEncode({
      'serverOrderUuid': source,
      'orderReference': 'REF-2',
      'diningTableId': '2',
      'orderType': 'dine_in',
      'splitCount': 1,
      'discount': {'value': 0},
      'items': [
        {
          'id': '7',
          'name': 'Coffee',
          'qty': 1,
          'basePrice': 1.0,
          'unitPrice': 1.0,
          'lineTotal': 1.0,
          'notes': '',
          'modifiers': [],
        },
      ],
    }),
  });
  final local = await loadCombineLocal(h.db, 2);
  final preview = previewJson();
  preview['table_id'] = 2;
  (preview['source'] as Map)['uuid'] = source;
  return CombineAttempt({
    'id': seatingId,
    'state': 'pending',
    'local': local.json,
    'preview': preview,
  });
}

Future<List<List<Map<String, Object?>>>> _originals(RecoveryHarness h) async =>
    [
      for (final table in [
        'held_orders',
        'dining_tables',
        'local_table_rounds',
        'local_line_cancellations',
        'order_history',
        'draft_recovery_retired',
      ])
        await h.db.query(table),
    ];

Future<List<List<Map<String, Object?>>>> _allRows(RecoveryHarness h) async => [
  ...await _originals(h),
  await h.db.query('bill_combine_journal'),
  await h.db.query('draft_recovery_journal'),
];
