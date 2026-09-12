import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/draft_recovery/recovery_controller.dart';
import 'package:pos_machine/draft_recovery/recovery_screen.dart';
import 'package:pos_machine/draft_recovery/recovery_store.dart';
import 'bill_combine_screen_test.dart' show NoDatabase;
import 'draft_recovery_test.dart' show RecoveryFake, RecoveryHarness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'initial journal-read failure can exit to restore settings without sending',
    (tester) async {
      final api = RecoveryFake();
      final controller = RecoveryController(
        store: RecoveryStore(NoDatabase(), 'scope'),
        gateway: api,
        dineIn: api,
        tableId: 1,
        loadLocal: (_) async => throw StateError('Must not load'),
        checkIdle: () async {},
        admit: (_) async => fail('No creation'),
        onRetired: (_) async => fail('No archive'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      RecoveryScreen(createController: () async => controller),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(controller.initializationFailed, true);
      expect(controller.canLeave, true);
      expect(controller.ready, false);
      expect(api.confirmations, isEmpty);
      expect(api.sent, isEmpty);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(find.byKey(const ValueKey('draft-recovery-review')), findsNothing);
    },
  );
  test(
    'leaving corrupt initialization never releases its persisted business guard',
    () async {
      final h = RecoveryHarness();
      await h.init();
      addTearDown(h.close);
      final before = await h.db.query('held_orders');
      await h.db.insert('draft_recovery_journal', {
        'id': 'unknown',
        'scope': 'scope',
        'state': 'unknown',
        'payload': '{invalid',
      });
      await h.controller.start();
      expect(h.controller.canLeave, true);
      await expectLater(
        RecoveryStore.assertNonePending(h.db),
        throwsFormatException,
      );
      expect(await h.db.query('held_orders'), before);
      expect(await h.db.query('draft_recovery_journal'), hasLength(1));
      expect(h.api.confirmations, isEmpty);
      expect(h.api.sent, isEmpty);
    },
  );
  test(
    'a loaded unresolved attempt remains guarded even if initialization later fails',
    () async {
      final h = RecoveryHarness();
      await h.init();
      addTearDown(h.close);
      await h.controller.start();
      h.api.reply = (_) async => throw StateError('offline');
      await h.controller.confirm();
      const other = '77777777-7777-4777-8777-777777777777';
      await h.db.insert('draft_recovery_journal', {
        'id': other,
        'scope': 'other-scope',
        'state': 'pending',
        'payload': jsonEncode({...h.controller.attempt!.json, 'id': other}),
      });
      final restored = h.create();
      addTearDown(restored.dispose);
      await restored.start();
      expect(restored.initializationFailed, true);
      expect(restored.unresolved, true);
      expect(restored.canLeave, false);
      expect(await h.db.query('draft_recovery_journal'), hasLength(2));
    },
  );
  test(
    'empty incomplete journal schema fails every recovery read and guard',
    () async {
      final h = RecoveryHarness();
      await h.init();
      addTearDown(h.close);
      await h.db.execute('DROP TABLE draft_recovery_journal');
      await h.db.execute(
        'CREATE TABLE draft_recovery_journal (id TEXT, scope TEXT, state TEXT)',
      );
      for (final check in <Future<Object?> Function()>[
        () => RecoveryStore.pending(h.db),
        () => RecoveryStore.assertNonePending(h.db),
        () => RecoveryStore.assertNotRetired(h.db, uuid: 'new'),
        h.store.active,
        () => h.store.read('new'),
        () => h.store.assertOwn(null),
      ]) {
        await expectLater(check(), throwsA(isA<DatabaseException>()));
      }
    },
  );
  for (final join in ['held party', 'dining party', 'linked secondary']) {
    test(
      'another $join overlapping the recovered table preserves all copies',
      () async {
        final h = RecoveryHarness();
        await h.init();
        addTearDown(h.close);
        if (join == 'held party') {
          await h.db.insert('held_orders', {
            'id': 'other',
            'order_type': 'dine_in',
            'draft_json': jsonEncode({
              'diningTableId': '2',
              'joined_table_ids': [1],
            }),
          });
        } else {
          await h.db.insert('dining_tables', {
            'table_id': '2',
            if (join == 'linked secondary') 'primary_table_id': '1',
            if (join == 'dining party') 'linked_table_ids_json': '["1"]',
          });
        }
        final before = await h.db.query('held_orders'),
            tables = await h.db.query('dining_tables');
        await h.controller.start();
        expect(h.controller.error, contains('overlapping joined'));
        expect(h.api.previews, 0);
        expect(h.api.confirmations, isEmpty);
        expect(await h.db.query('held_orders'), before);
        expect(await h.db.query('dining_tables'), tables);
      },
    );
  }
  test(
    'new overlapping party after preview refuses journal creation before POST',
    () async {
      final h = RecoveryHarness();
      await h.init();
      addTearDown(h.close);
      await h.controller.start();
      expect(h.controller.error, null);
      await h.db.insert('dining_tables', {
        'table_id': '2',
        'linked_table_ids_json': '[1]',
      });
      final before = await h.db.query('dining_tables');
      await h.controller.confirm();
      expect(h.api.confirmations, isEmpty);
      expect(await h.store.active(), null);
      expect(await h.db.query('dining_tables'), before);
    },
  );
}
