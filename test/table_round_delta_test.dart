import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/table_sync_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

void main() {
  const product = Product(
    id: '10',
    name: 'Latte',
    category: 'Coffee',
    price: 2,
  );
  const addon = CartItemModifier(
    id: '30',
    group: 'Milk',
    label: 'Oat',
    price: .3,
  );
  final now = DateTime.utc(2026, 9, 6);
  LocalTableRound round(String status, int qty) => LocalTableRound(
    clientRequestId: 'request',
    tableId: '5',
    seatingKey: 'seat',
    localRoundNo: 1,
    lines: [
      {'product_id': 10, 'qty': qty},
    ],
    submittedAt: now,
    outboxKey: 'row',
    status: status,
  );
  LocalLineCancellation cancellation(String status, int qty, int? cancelled) =>
      LocalLineCancellation(
        clientRequestId: 'cancel',
        tableId: '5',
        seatingKey: 'seat',
        productId: 10,
        addonIds: [],
        qty: qty,
        prepared: false,
        cancelledAt: now,
        outboxKey: 'cancel-row',
        status: status,
        cancelledQty: cancelled,
      );

  test('fingerprint is product plus addon set plus normalized notes', () {
    expect(
      tableLineFingerprint({
        'product_id': 10,
        'addon_ids': [31, 30],
        'notes': '  NO \n Sugar ',
      }),
      tableLineFingerprint({
        'product_id': 10,
        'addon_ids': [30, 31],
        'notes': 'no sugar',
      }),
    );
    expect(
      tableLineFingerprint({'product_id': 10, 'notes': null}),
      tableLineFingerprint({'product_id': 10, 'notes': ''}),
    );
    expect(
      tableLineFingerprint({'product_id': 10}),
      isNot(tableLineFingerprint({'product_id': 11})),
    );
    expect(
      tableLineFingerprint({
        'product_id': 10,
        'addon_ids': [30],
      }),
      isNot(
        tableLineFingerprint({
          'product_id': 10,
          'addon_ids': [31],
        }),
      ),
    );
  });

  test(
    'table line mapping equals order.create identities and never prices',
    () {
      final items = [
        CartItem(
          product: product,
          qty: 3,
          notes: ' No sugar ',
          modifiers: [
            addon,
            const CartItemModifier(
              id: 'demo-addon',
              group: 'Demo',
              label: 'Local',
              price: 9,
            ),
          ],
        ),
        CartItem(
          product: const Product(
            id: 'demo',
            name: 'Demo',
            category: 'Coffee',
            price: 1,
          ),
        ),
      ];
      final snapshot = OrderSnapshot.initial().copyWith(
        items: items.map((item) => item.toMap()).toList(),
        serverOrderUuid: 'bill',
        rawSubtotal: 10,
        subtotal: 10,
        total: 10,
      );
      final order =
          ((buildOrderSyncPayload(snapshot, now: now).events.first['payload']
                  as Map)['order']
              as Map);
      final expected = [
        for (final raw in order['lines'] as List)
          {
            'product_id': (raw as Map)['product_id'],
            'qty': raw['qty'],
            if (raw['notes'] != null) 'notes': raw['notes'],
            if (raw['addons'] != null)
              'addon_ids': [
                for (final a in raw['addons'] as List) (a as Map)['add_on_id'],
              ],
          },
      ];
      final actual = buildTableRoundLines(items);
      expect(actual, expected);
      expect(actual, [
        {
          'product_id': 10,
          'qty': 3,
          'notes': 'No sugar',
          'addon_ids': [30],
        },
      ]);
      expect(actual.single.keys.toSet(), {
        'product_id',
        'qty',
        'notes',
        'addon_ids',
      });
    },
  );

  for (final status in ['queued', 'appended', 'held', 'merged', 'replayed']) {
    test(
      '$status quantities count as sent for positive and negative deltas',
      () {
        expect(
          tableRoundDelta(
            [CartItem(product: product, qty: 5)],
            [round(status, 3)],
            [],
          ),
          [
            {'product_id': 10, 'qty': 2},
          ],
        );
        expect(
          tableRoundDelta(
            [CartItem(product: product, qty: 1)],
            [round(status, 3)],
            [],
          ),
          [
            {'product_id': 10, 'qty': -2},
          ],
        );
      },
    );
  }
  for (final status in ['bill_terminal', 'bill_unpaid', 'failed']) {
    test('$status quantities do not count as sent', () {
      expect(
        tableRoundDelta(
          [CartItem(product: product, qty: 2)],
          [round(status, 2)],
          [],
        ),
        [
          {'product_id': 10, 'qty': 2},
        ],
      );
    });
  }
  test('queued intent and acknowledged actual cancellation count once', () {
    final items = [CartItem(product: product, qty: 1)];
    expect(
      tableRoundDelta(
        items,
        [round('appended', 3)],
        [cancellation('queued', 2, null)],
      ),
      isEmpty,
    );
    expect(
      tableRoundDelta(
        items,
        [round('appended', 3)],
        [cancellation('cancelled', 2, 1)],
      ),
      [
        {'product_id': 10, 'qty': -1},
      ],
    );
    expect(
      tableRoundDelta(
        items,
        [round('appended', 3)],
        [cancellation('replayed', 2, 2)],
      ),
      isEmpty,
    );
    expect(
      tableRoundDelta(
        items,
        [round('appended', 3)],
        [cancellation('nothing_to_cancel', 2, 0)],
      ),
      [
        {'product_id': 10, 'qty': -2},
      ],
    );
  });
}
