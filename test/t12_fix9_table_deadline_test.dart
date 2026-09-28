import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'real_io_wait.dart';
import 't12_fix3_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final clear in [false, true]) {
    testWidgets(
      'S2 real SQLite held ${clear ? 'clear' : 'return'} gives feedback within ten seconds and retries',
      (tester) async {
        final r = Fix3Rig(tester);
        await r.boot();
        await r.tap(find.text(r.l.displayOrderTypeDineIn).first);
        await r.tableOpen('1');
        await r.add();
        final reference = r.c.currentOrderReference;
        await pumpUntilRealCondition(
          tester,
          () async {
            final saved = await r.storage.loadDiningTableSessions();
            return saved.length == 1 && saved.single.draft?.items.length == 1;
          },
          timeout: const Duration(seconds: 20),
          reason: 'original draft is durably saved before holding SQLite',
        );
        final original = await r.drive(r.storage.loadDiningTableSessions);
        final gate = await r.holdDb();
        var done = false;
        final watch = Stopwatch()..start();
        Object? error;
        await tester.runAsync(() async {
          final action = clear
              ? r.c.clearActiveDiningTable()
              : r.c.returnToDiningFloorPlan();
          unawaited(
            action.then(
              (_) => done = true,
              onError: (Object e) {
                error = e;
                done = true;
              },
            ),
          );
        });
        // Real wall time, not pump-time: the held transaction is the actual
        // production store's SQL operation, not a slow-storage fake.
        try {
          await pumpUntilRealCondition(
            tester,
            () => done,
            timeout: const Duration(seconds: 10),
            reason: 'bounded table action returned with feedback',
          );
          expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
          expect(error, isNull);
          await tester.pump();
          expect(find.textContaining('Reconnect and try again'), findsWidgets);
          expect(r.c.lastPaymentMessage, contains('Reconnect and try again'));
          expect(r.c.tableTransitionInProgress, isFalse);
          expect(r.c.activeDiningTableId, '1');
          expect(r.c.currentOrderReference, reference);
          expect(r.c.cart, hasLength(1));
        } finally {
          gate.complete();
          await pumpUntilRealCondition(
            tester,
            () => done,
            timeout: const Duration(seconds: 10),
            reason: 'released operation is drained before fixture disposal',
          );
        }
        await r.drive(() async {
          final after = await r.storage.loadDiningTableSessions();
          expect(after.single.orderReference, original!.single.orderReference);
          expect(after.single.draft!.items, hasLength(1));
        });
        await r.drive(
          () => clear
              ? r.c.clearActiveDiningTable()
              : r.c.returnToDiningFloorPlan(),
        );
        expect(r.c.activeDiningTableId, isNull);
        expect(r.c.cart, isEmpty);
        final afterRetry = await r.drive(r.storage.loadDiningTableSessions);
        expect(afterRetry, clear ? isEmpty : hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'S2 real joined-table clear retains every seat on timeout and retries atomically',
    (tester) async {
      final r = Fix3Rig(tester);
      await r.boot();
      await r.tap(find.text(r.l.displayOrderTypeDineIn).first);
      await r.tableOpen('1');
      await r.add();
      await r.drive(r.c.returnToDiningFloorPlan);
      await r.drive(() => r.c.joinDiningTables('1', '2'));
      final original = await r.drive(
        () => r.localDb.query('dining_tables', orderBy: 'table_id'),
      );
      expect(original, hasLength(2));
      final gate = await r.holdDb();
      var done = false;
      Object? error;
      await tester.runAsync(() async {
        unawaited(
          r.c
              .clearDiningTableById('1')
              .then(
                (_) => done = true,
                onError: (Object e) {
                  error = e;
                  done = true;
                },
              ),
        );
      });
      try {
        await pumpUntilRealCondition(
          tester,
          () => done,
          timeout: const Duration(seconds: 10),
          reason: 'joined clear bounded feedback',
        );
        await tester.pump();
        expect(error, isNull);
        expect(find.textContaining('Reconnect and try again'), findsWidgets);
        expect(r.c.diningTableSessions, hasLength(2));
      } finally {
        gate.complete();
        await pumpUntilRealCondition(
          tester,
          () => done,
          timeout: const Duration(seconds: 10),
          reason: 'joined clear drain before disposal',
        );
      }
      expect(
        await r.drive(
          () => r.localDb.query('dining_tables', orderBy: 'table_id'),
        ),
        original,
      );
      await r.drive(() => r.c.clearDiningTableById('1'));
      expect(await r.drive(() => r.localDb.query('dining_tables')), isEmpty);
      expect(r.c.diningTableSessions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
