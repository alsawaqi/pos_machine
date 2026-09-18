import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';
import 'unified_dine_in_test.dart' show TableFake;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets(
    'shared draft survives editor restart offline and becomes one durable send',
    (tester) async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
      );
      await SqliteDineInStore.createSchema(db);
      addTearDown(db.close);
      final gateway = TableFake();
      const product = QuickProduct(8, 'Coffee', priceBaisas: 1000);
      late CurrentOrderWorkspace w;
      Future<void> open() async {
        w = CurrentOrderWorkspace(
          onExit: () {},
          mainCart: true,
          tableLabel: 'Table 2',
        );
        await tester.pumpWidget(
          MaterialApp(
            home: DineInScreen(
              workspace: w,
              label: 'Table 2',
              createController: () async =>
                  DineInController(gateway, SqliteDineInStore(db, 'scope'), 2),
              catalogue: () => [product],
              onPay: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        w.dispose();
      }

      await open();
      await w.pick(product);
      await w.pick(product);
      await tester.pump();
      expect(w.cartControls!.draftRows.single['qty'], 2);
      expect(gateway.requests, isEmpty);
      await close();
      gateway.failRead = true;
      await open();
      expect(w.cartControls!.draftRows, hasLength(1));
      expect(w.cartControls!.draftRows.single['qty'], 2);
      expect(w.canPay, false);
      expect(gateway.requests, isEmpty);
      gateway.failRead = false;
      await w.cartControls!.refresh!();
      await tester.pumpAndSettle();
      await w.cartControls!.quantity!(w.cartControls!.draftRows.single, 1);
      gateway.loseResponse = true;
      await w.cartControls!.submit!();
      await tester.pump();
      expect(gateway.requests, hasLength(1));
      final id = gateway.requests.single.id;
      await close();
      await open();
      expect(w.cartControls!.draftRows, isEmpty);
      expect(w.canPay, false);
      expect((await SqliteDineInStore(db, 'scope').load())!.id, id);
      expect(gateway.requests, hasLength(1));
      gateway.loseResponse = false;
      await w.cartControls!.retry!();
      await tester.pump();
      expect(gateway.requests, hasLength(2));
      expect(gateway.requests.last.id, id);
      await close();
      await open();
      expect(w.cartControls!.draftRows, isEmpty);
      await close();
    },
  );
}
