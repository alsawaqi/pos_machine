import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/table_round_validation.dart';
import 'package:pos_machine/l10n/l10n_en.dart';
import 'package:pos_machine/l10n/l10n_ar.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'package:pos_machine/widgets/table_reconciliation_sheet.dart';
import 'send_to_kitchen_test.dart' show B3Harness;
import 'table_required_size_test.dart' show product, group;

Future<B3Harness> fixture({bool valid = false}) async {
  final h = B3Harness();
  await h.init(
    items: [
      CartItem(
        product: product,
        qty: 1,
        modifiers: valid
            ? [
                const CartItemModifier(
                  id: '2',
                  group: 'size',
                  label: 'medium',
                  price: .3,
                ),
              ]
            : [],
      ),
    ],
  );
  h.controller.allProducts = [product];
  h.controller.addonGroups = [group];
  return h;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final path in [
    'leave',
    'final',
    'direct',
    'offline',
    'payment-preflight',
  ]) {
    test(
      'required size blocks $path without discarding the draft or printing',
      () async {
        final h = await fixture();
        if (path == 'offline') h.online = false;
        final session = h.bridge.activeSession()!;
        if (path == 'leave') {
          h.bridge.onTableLeft('5');
          await h.bridge.settled;
        } else {
          final action = switch (path) {
            'final' => h.controller.onDiningTableFinalRound!(
              OrderSnapshot.initial(),
            ),
            'direct' => h.coordinator.sendRound(session),
            'payment-preflight' => h.bridge.validatePending(session),
            _ => h.bridge.send(session),
          };
          await expectLater(
            action,
            throwsA(isA<TableRoundSelectionException>()),
          );
        }
        expect(h.memory.rounds, isEmpty);
        expect(h.tickets, isEmpty);
        expect(
          h.events.where((e) => e['event_type'] == 'table.session.round'),
          isEmpty,
        );
        expect(h.controller.cart.single.product.id, '1');
        expect(h.controller.cart.single.qty, 1);
        expect(h.controller.cart.single.modifiers, isEmpty);
      },
    );
  }
  test('select size after refused send submits the same bill once', () async {
    final h = await fixture();
    final uuid = h.controller.activeDiningTableBillUuid;
    await expectLater(
      h.bridge.send(h.bridge.activeSession()!),
      throwsA(isA<TableRoundSelectionException>()),
    );
    final item = h.controller.cart.single;
    h.controller.updateCartItemCustomization(
      item,
      modifiers: [
        const CartItemModifier(
          id: '2',
          group: 'size',
          label: 'medium',
          price: .3,
        ),
      ],
      notes: '',
    );
    await h.bridge.send(h.bridge.activeSession()!);
    await h.bridge.send(h.bridge.activeSession()!);
    expect(h.memory.rounds, hasLength(1));
    expect(h.tickets, hasLength(1));
    expect(h.memory.rounds.values.single.lines.single['addon_ids'], [2]);
    expect(h.controller.activeDiningTableBillUuid, uuid);
  });
  test(
    'catalogue changes do not resubmit or reject already sent quantities',
    () async {
      final h = await fixture(valid: true);
      await h.bridge.send(h.bridge.activeSession()!);
      h.controller.addonGroups = [
        AddonGroup(
          id: 1,
          name: 'size',
          multiSelect: true,
          minSelections: 2,
          maxSelections: 2,
          options: group.options,
        ),
      ];
      await h.bridge.validatePending(h.bridge.activeSession()!);
      await h.bridge.send(h.bridge.activeSession()!);
      expect(h.memory.rounds, hasLength(1));
      expect(h.tickets, hasLength(1));
      h.controller.incrementCartItem(h.controller.cart.single);
      await expectLater(
        h.bridge.send(h.bridge.activeSession()!),
        throwsA(isA<TableRoundSelectionException>()),
      );
      expect(h.memory.rounds, hasLength(1));
      expect(h.tickets, hasLength(1));
    },
  );
  test('maximum selection and raw impossible minimum are never relaxed', () {
    for (final g in [
      group,
      AddonGroup(
        id: 1,
        name: 'size',
        multiSelect: false,
        minSelections: 2,
        maxSelections: 1,
        options: group.options,
      ),
    ]) {
      expect(
        () => validateTableRoundSelections(
          [
            {
              'product_id': 1,
              'qty': 1,
              'addon_ids': g == group ? [1, 2] : [2],
            },
          ],
          productForId: (_) => product,
          groupsForProduct: (_) => [g],
        ),
        throwsA(isA<TableRoundSelectionException>()),
      );
    }
  });
  for (final source in ['main_pos', 'handheld']) {
    test(
      '$source held bill routes Pay to review and never local tender',
      () async {
        final raw = <String, dynamic>{
          'table_id': 2,
          'seating': {
            'uuid': 'seat',
            'status': 'open',
            'needs_review_count': 1,
          },
          'bill': {
            'order_uuid': 'bill',
            'status': 'open',
            'source': source,
            'customer_rounds': 0,
            'staff_rounds': 1,
            'grand_total_baisas': 0,
          },
        };
        final row = RemoteTableState.fromBoard(raw, DateTime.now());
        final h = await fixture();
        expect(
          customerOccupiesDiningTable(
            mode: 'live',
            session: h.bridge.activeSession(),
            remote: row,
          ),
          true,
        );
        var local = 0, review = 0;
        await TableCartPayRouter().route(
          mode: 'live',
          tableId: 2,
          contextKey: 'same',
          board: const RemoteTableSnapshot(),
          fetchBoard: () async => [raw],
          isCurrent: () => true,
          changed: () {},
          openSheet: () async {
            review++;
          },
          openLocal: () async {
            local++;
          },
        );
        expect(review, 1);
        expect(local, 0);
      },
    );
  }
  for (final ar in [false, true]) {
    test(
      'held add-on message is actionable and not a successful pricing claim ar=$ar',
      () {
        final row = TableSyncVerdict(
          observedAt: DateTime.now(),
          tableId: '2',
          eventKind: 'round',
          outcome: 'held',
          detail: {
            'request': {
              'lines': [
                {'qty': 1},
              ],
            },
            'held_lines': [
              {'line_index': 0, 'reason': 'addon_selection_invalid'},
            ],
            'review_reasons': ['catalogue'],
          },
        );
        final copy = tableReconciliationCopy(ar ? L10nAr() : L10nEn(), row);
        expect(copy, contains(ar ? 'لم تُقبل' : 'not accepted for payment'));
        expect(copy, isNot(contains('addon_selection_invalid')));
        expect(
          const TableRoundSelectionException(
            'Coffee',
            'size',
          ).message(arabic: ar),
          contains(ar ? 'الإضافات' : 'Add On'),
        );
      },
    );
  }
}
