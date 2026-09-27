import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'real_io_wait.dart';
import 't12_fix3_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final arabic in [false, true]) {
    testWidgets(
      'A1 real SQLite table transition resolves messages after screen dispose '
      '${arabic ? "Arabic" : "English"}',
      (tester) async {
        final r = Fix3Rig(tester, arabic: arabic);
        await r.boot();
        await r.tap(find.text(r.l.displayOrderTypeDineIn).first);
        await r.tableOpen('1');
        await r.add();
        final expectedNote = r.l.ctrlMsgChooseTableDineIn;
        final reference = r.c.currentOrderReference;
        expect(r.c.localize!().ctrlMsgChooseTableDineIn, expectedNote);

        // Hold an actual transaction on the same file-backed SQLite connection
        // used by the controller. Its table transition must wait for that DB.
        final gate = await r.holdDb();
        bool completed = false;
        Object? failure;
        StackTrace? failureTrace;
        await tester.runAsync(() async {
          unawaited(
            r.c.returnToDiningFloorPlan().then(
              (_) => completed = true,
              onError: (Object error, StackTrace trace) {
                failure = error;
                failureTrace = trace;
                completed = true;
              },
            ),
          );
        });
        expect(r.c.tableTransitionInProgress, isTrue);
        expect(completed, isFalse);
        expect(r.c.activeDiningTableId, '1');

        await tester.pumpWidget(const SizedBox.shrink());
        expect(find.byType(StaffPosScreen), findsNothing);
        expect(completed, isFalse);
        gate.complete();
        await pumpUntilRealCondition(
          tester,
          () => completed,
          reason: 'disposed screen table transition completes',
          timeout: const Duration(seconds: 20),
        );
        expect(failure, isNull, reason: '$failureTrace');
        expect(r.c.tableTransitionInProgress, isFalse);
        expect(r.c.selectedOrderType, OrderType.dineIn);
        expect(r.c.activeDiningTableId, isNull);
        expect(r.c.cart, isEmpty);
        expect(r.c.displayNote, expectedNote);
        expect(r.c.localize!().ctrlMsgChooseTableDineIn, expectedNote);
        final saved = (await r.drive(r.storage.loadDiningTableSessions))!;
        expect(saved.single.tableId, '1');
        expect(saved.single.orderReference, reference);
        expect(saved.single.draft!.items.single.qty, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
