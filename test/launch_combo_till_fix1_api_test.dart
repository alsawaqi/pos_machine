import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/combo/combo_edit.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/screens/qr_quick_orders_screen.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'send_to_kitchen_test.dart' show B3Harness;
import 'support/combo_fixtures.dart';
import 'support/fake_order_storage.dart';

/// LAUNCH combo add-on — till client fix order 1, the parts with new APIs
/// (they do not compile at 67d9d45):
///  T-C2 a line cancellation stores the meal / combo it cancelled (local
///       store v11) and offsets exactly that line;
///  T-C3 an edit of a sent combo / meal goes through the sent-line approval
///       and becomes one cancel plus one add;
///  T-C4 the meal offered on a main needs its items sellable (till and the
///       server-priced picker).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  PosController build() {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Menu'],
      products: products,
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      addonGroups: const [size, remove, ice],
      branchId: 6,
      meals: const [meal],
    );
    addTearDown(c.dispose);
    return c;
  }

  CartItem box(PosController c, String drink) => CartItem(
    product: familyBox,
    components: c.resolveCombo(familyBox.comboLines, [
      ComboSelection(lineId: 3, productId: drink),
    ]).components,
  );

  group('T-C2 — the cancellation keeps the cancelled line', () {
    test('a meal / combo cancellation stores its identity; a standard one '
        'keeps its historical row', () {
      final c = build();
      final mealLine = buildTableRoundLines([
        CartItem(
          product: burger,
          meal: const CartMeal(id: 5, name: 'meal', price: 1.2),
        ),
      ]).single;
      LocalLineCancellation cancel(Map<String, dynamic>? line) =>
          LocalLineCancellation(
            clientRequestId: 'r-1',
            tableId: '5',
            seatingKey: 's-1',
            productId: line?['product_id'] as int? ?? 30,
            addonIds: const [],
            qty: 1,
            prepared: false,
            cancelledAt: DateTime.utc(2026, 10, 7),
            outboxKey: 'k-1',
            line: line,
          );
      expect(cancel(mealLine).lineIdentity, {'meal_id': 5});
      final boxLine = buildTableRoundLines([box(c, '34')]).single;
      expect(cancel(boxLine).lineIdentity['combo'], boxLine['combo']);
      final plain = cancel({'product_id': 30, 'qty': 1});
      expect(plain.toRow().containsKey('line_json'), isFalse);
      expect(plain.lineIdentity, isEmpty);
      // The delta offsets exactly the cancelled meal, never a plain main.
      final sent = LocalTableRound(
        clientRequestId: 'round-1',
        tableId: '5',
        seatingKey: 's-1',
        localRoundNo: 1,
        lines: [mealLine],
        submittedAt: DateTime.utc(2026, 10, 7),
        outboxKey: 'k-0',
        status: 'appended',
      );
      expect(tableRoundDelta(const [], [sent], [cancel(mealLine)]), isEmpty);
    });

    test('local store v10 to v11 adds line_json and keeps old rows', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await db.execute(
        'CREATE TABLE dining_tables (table_id TEXT PRIMARY KEY, floor_id TEXT '
        'NOT NULL, status TEXT NOT NULL, order_number INTEGER, '
        'order_reference TEXT, updated_at TEXT NOT NULL, occupied_at TEXT, '
        'paid_at TEXT, draft_json TEXT, paid_snapshot_json TEXT, '
        'primary_table_id TEXT, linked_table_ids_json TEXT)',
      );
      await LocalOrderStorageService.createRemoteTables(db);
      await LocalOrderStorageService.createTableLedger(db);
      final old = LocalLineCancellation(
        clientRequestId: 'r-old',
        tableId: '5',
        seatingKey: 's-1',
        productId: 30,
        addonIds: const [61],
        qty: 1,
        prepared: false,
        cancelledAt: DateTime.utc(2026, 10, 6),
        outboxKey: 'k-old',
      );
      await db.insert('local_line_cancellations', old.toRow());
      await LocalOrderStorageService.addCancellationLineIdentity(db);
      final mealCancel = LocalLineCancellation(
        clientRequestId: 'r-meal',
        tableId: '5',
        seatingKey: 's-1',
        productId: 30,
        addonIds: const [],
        qty: 1,
        prepared: false,
        cancelledAt: DateTime.utc(2026, 10, 7),
        outboxKey: 'k-meal',
        line: const {'product_id': 30, 'meal_id': 5},
      );
      await db.insert('local_line_cancellations', mealCancel.toRow());
      final rows = (await db.query(
        'local_line_cancellations',
        orderBy: 'cancelled_at',
      )).map(LocalLineCancellation.fromRow).toList();
      expect(rows.first.addonIds, [61]);
      expect(rows.first.lineIdentity, isEmpty);
      expect(rows.last.lineIdentity, {'meal_id': 5});
    });
  });

  group('T-C3 — editing a sent combo or meal', () {
    test('a changed sent line asks for the sent-line approval; an unchanged '
        'one or a non-live table does not', () async {
      final c = build();
      final cola = box(c, '32');
      final juice = box(c, '34');
      final asked = <(String, int)>[];
      Future<bool> approve(CartItem item, int qty) async {
        asked.add((item.components.last.productId, qty));
        return true;
      }

      expect(tableLineChanged(cola, juice), isTrue);
      expect(tableLineChanged(cola, box(c, '32')), isFalse);
      cola.qty = 2;
      expect(
        await guardSentLineEdit(
          liveTable: true,
          before: cola,
          after: juice,
          approveSentReduction: approve,
        ),
        isTrue,
      );
      expect(asked, [('32', 2)]);
      expect(
        await guardSentLineEdit(
          liveTable: false,
          before: cola,
          after: juice,
          approveSentReduction: approve,
        ),
        isTrue,
      );
      expect(
        await guardSentLineEdit(
          liveTable: true,
          before: cola,
          after: box(c, '32')..qty = 2,
          approveSentReduction: approve,
        ),
        isTrue,
      );
      expect(asked, hasLength(1));
      // A refused approval leaves the cart as it is.
      expect(
        await guardSentLineEdit(
          liveTable: true,
          before: cola,
          after: juice,
          approveSentReduction: (_, _) async => false,
        ),
        isFalse,
      );
    });

    test(
      'a sent box with Cola changed to Juice: one cancel plus one add',
      () async {
        final c = build();
        final cola = box(c, '32');
        final h = B3Harness();
        await h.init(items: [cola]);
        await h.bridge.send(h.bridge.activeSession()!);
        final juice = box(c, '34');
        final ok = await guardSentLineEdit(
          liveTable: true,
          before: cola,
          after: juice,
          approveSentReduction: (item, qty) async {
            await h.coordinator.cancelLine(
              h.bridge.activeSession()!,
              line: buildTableRoundLines([item]).single,
              qty: qty,
              prepared: false,
              authorizedBy: 'Manager',
            );
            return true;
          },
        );
        expect(ok, isTrue);
        await h.coordinator.settled;
        expect(
          h.events.where((e) => e['event_type'] == 'table.session.cancel_line'),
          hasLength(1),
        );
        final session = h.bridge.activeSession()!;
        final delta = await h.coordinator.delta(
          session.copyWith(draft: session.draft!.copyWith(items: [juice])),
        );
        expect(delta, hasLength(1));
        expect(delta.single['product_id'], 40);
        expect(delta.single['qty'], 1);
        expect((delta.single['combo'] as List).single['product_id'], 34);
      },
    );
  });

  group('T-C4 — the meal is offered only when it can be sold', () {
    test('till: a sold-out fixed item or a sold-out choice line hides it', () {
      final c = build();
      expect(c.mealOffer(burger)?.id, 5);
      c.markSoldOutLocally('31', true);
      expect(c.mealOffer(burger), isNull);
      expect(c.mealFor(burger)?.id, 5); // still the main's meal
      c.markSoldOutLocally('31', false);
      c.markSoldOutLocally('32', true);
      expect(c.mealOffer(burger)?.id, 5); // the juice is left
      c.markSoldOutLocally('34', true);
      expect(c.mealOffer(burger), isNull);
    });

    test('server-priced picker: the meal says it cannot be sold', () {
      final quick = machineQuickCatalogue(
        CatalogSnapshot(
          categories: const ['Menu'],
          products: [
            for (final p in products)
              p.id == '31' ? p.copyWith(soldOut: true) : p,
          ],
          floors: const [],
          tables: const [],
          taxes: const [],
          addonGroups: const [size, remove, ice],
          meals: const [meal],
        ),
      );
      final main = quick.firstWhere((p) => p.id == 30);
      expect(main.meal?.id, 5);
      expect(main.meal?.available, isFalse);
      final ok = machineQuickCatalogue(
        const CatalogSnapshot(
          categories: ['Menu'],
          products: products,
          floors: [],
          tables: [],
          taxes: [],
          addonGroups: [size, remove, ice],
          meals: [meal],
        ),
      ).firstWhere((p) => p.id == 30);
      expect(ok.meal?.available, isTrue);
    });
  });
}
