import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 't65_adjustment_journal_test.dart' show AdjustmentServer;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final lifecycle in ['background', 'replaced', 'cancelled']) {
    test(
      'Real adjustment picker $lifecycle keeps journal empty and reports interruption',
      () async {
        final db = await databaseFactoryFfiNoIsolate.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            singleInstance: false,
            version: 2,
            onCreate: (db, _) => SqliteDineInStore.createSchema(db),
          ),
        );
        addTearDown(db.close);
        final server = AdjustmentServer()..db = db;
        final c = DineInController(
          ApiDineInGateway(
            PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
            () => 'scope',
          ),
          SqliteDineInStore(db, 'scope'),
          1,
          staffId: 7,
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) c.dispose();
        });
        await c.start();
        expect(c.canAdjust, true);
        expect(
          await c.adjust((_) async {
            if (lifecycle == 'cancelled') return null;
            if (lifecycle == 'background') {
              c.setForeground(false);
            } else {
              c.dispose();
              disposed = true;
            }
            return {
              'kind': 'discount',
              'mode': 'fixed',
              'amount_baisas': 100,
              'label': 'Synthetic',
            };
          }),
          false,
        );
        expect(server.requests, isEmpty);
        expect(await db.query('dine_in_requests'), isEmpty);
        expect(c.pending, isNull);
        expect(c.notice, lifecycle == 'cancelled' ? isNull : 'refresh');
        if (lifecycle != 'cancelled') {
          expect(
            dineInText(false, c.notice!),
            'Refresh the table before continuing.',
          );
          expect(dineInText(true, c.notice!), 'حدّث الطاولة قبل المتابعة.');
        }
      },
    );
  }
}
