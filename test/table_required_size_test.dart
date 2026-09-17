import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';
import 'send_to_kitchen_test.dart' show B3Harness;

const product = Product(
  id: '1',
  name: 'White coffee',
  category: 'Coffee',
  price: .5,
  addonGroupIds: [1],
);
const group = AddonGroup(
  id: 1,
  name: 'size',
  multiSelect: false,
  minSelections: 1,
  maxSelections: 1,
  options: [
    AddonOption(id: 1, label: 'large', priceDelta: .5),
    AddonOption(id: 2, label: 'medium', priceDelta: .3),
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final selected in [false, true]) {
    test(
      selected
          ? 'valid explicit size sends exactly one round and ticket'
          : 'missing required size must not enqueue or print a staff round',
      () async {
        final h = B3Harness();
        await h.init(
          items: [
            CartItem(
              product: product,
              qty: 1,
              modifiers: selected
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
        expect(
          h.controller.addonGroupsForProduct(product).single.minSelections,
          1,
        );
        Object? refusal;
        try {
          await h.bridge.send(h.bridge.activeSession()!);
        } catch (e) {
          refusal = e;
        }
        final sent = h.events
            .where((e) => e['event_type'] == 'table.session.round')
            .toList();
        debugPrint(
          jsonEncode({
            'selected': selected,
            'round_events': sent.length,
            'tickets': h.tickets.length,
            'refusal': refusal?.toString(),
            'lines': sent.map((e) => (e['payload'] as Map)['lines']).toList(),
          }),
        );
        expect(
          sent,
          selected ? hasLength(1) : isEmpty,
          reason: 'Required options must be complete before any send.',
        );
        expect(
          h.tickets,
          selected ? hasLength(1) : isEmpty,
          reason: 'Do not print a known invalid draft.',
        );
        if (selected) {
          expect(
            (((sent.single['payload'] as Map)['lines'] as List).single
                as Map)['addon_ids'],
            [2],
          );
        }
      },
    );
  }
  test('staff-only held bill must enter server review before payment', () {
    final row = RemoteTableState(
      tableId: 2,
      fetchedAt: DateTime.now(),
      seatingUuid: 'seat',
      seatingStatus: 'open',
      billOrderUuid: 'bill',
      billStatus: 'open',
      billSource: 'main_pos',
      billCustomerRounds: 0,
      billStaffRounds: 1,
      needsReviewCount: 1,
      billGrandTotalBaisas: 0,
    );
    expect(
      tableBillNeedsSheet('live', row),
      true,
      reason:
          'A held staff round needs review even without a customer QR round.',
    );
  });
}
