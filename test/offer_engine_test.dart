import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/offer_engine.dart';
import 'package:pos_machine/services/order_sync_payload.dart';

/// P-F9 — the offer engine end-to-end: every offer type's money semantics,
/// the exclusion rules (gifted lines, bundle-tagged lines), the baisas-exact
/// allocations, the mapper passthrough (API JSON → Drift → Offer) and the
/// sync-payload split (offer rows carry offer_id; the order-level entry is
/// the combined discount minus line discounts minus offers).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Product p(int id, double price, {int? cat}) => Product(
        id: '$id',
        name: 'P$id',
        category: 'Cat',
        categoryId: cat,
        price: price,
      );

  CartItem item(
    int id,
    double price, {
    int qty = 1,
    int? cat,
    bool gifted = false,
    String bundleKey = '',
  }) =>
      CartItem(
        product: p(id, price, cat: cat),
        qty: qty,
        gifted: gifted,
        bundleKey: bundleKey,
      );

  List<double> nets(List<CartItem> cart) =>
      [for (final c in cart) c.product.price * c.qty];

  final now = DateTime(2026, 6, 10, 12, 0, 0); // a Wednesday, midday

  List<AppliedOffer> eval(
    List<CartItem> cart,
    List<Offer> offers, {
    List<double>? lineNet,
    int branchId = 6,
  }) =>
      evaluateOffers(
        cart: cart,
        lineNet: lineNet ?? nets(cart),
        offers: offers,
        now: now,
        branchId: branchId,
      );

  group('bogo', () {
    test('buy 1 get 1 free (same_as_buy) makes the cheaper unit free', () {
      final cart = [item(10, 2.0), item(10, 2.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'B1G1', type: 'bogo', config: {
          'buy': {'product_ids': [10], 'qty': 1},
          'get': {'same_as_buy': true, 'qty': 1},
        }),
      ]);
      expect(applied, hasLength(1));
      expect(applied.first.applications, 1);
      expect(applied.first.total, 2.0);
    });

    test('cross-product get with percent_off discounts the get line', () {
      final cart = [item(10, 3.0), item(20, 0.5)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Burger+Drink', type: 'bogo', config: {
          'buy': {'product_ids': [10], 'qty': 1},
          'get': {'product_ids': [20], 'qty': 1, 'percent_off': 50},
        }),
      ]);
      expect(applied, hasLength(1));
      expect(applied.first.lineAmounts, {1: 0.25});
      expect(applied.first.total, 0.25);
    });

    test('insufficient get units undoes the buys — no application', () {
      // Buy 2 get 1 same_as_buy with only 2 units: the buys consume both,
      // nothing is left to reward, the application must roll back.
      final cart = [item(10, 2.0, qty: 2)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'B2G1', type: 'bogo', config: {
          'buy': {'product_ids': [10], 'qty': 2},
          'get': {'same_as_buy': true, 'qty': 1},
        }),
      ]);
      expect(applied, isEmpty);
    });

    test('max_per_order caps repeats; null repeats until units run out', () {
      final cart = [item(10, 2.0, qty: 4)];
      const config = {
        'buy': {'product_ids': [10], 'qty': 1},
        'get': {'same_as_buy': true, 'qty': 1},
      };
      final capped = eval(cart, [
        const Offer(
            id: 1, name: 'B1G1', type: 'bogo', config: config, maxPerOrder: 1),
      ]);
      expect(capped.first.applications, 1);
      expect(capped.first.total, 2.0);

      final unlimited = eval(cart, [
        const Offer(id: 1, name: 'B1G1', type: 'bogo', config: config),
      ]);
      expect(unlimited.first.applications, 2);
      expect(unlimited.first.total, 4.0);
    });

    test('category selector matches units by category id', () {
      final cart = [item(10, 1.5, cat: 3), item(11, 1.0, cat: 3)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Cat BOGO', type: 'bogo', config: {
          'buy': {'category_ids': [3], 'qty': 1},
          'get': {'same_as_buy': true, 'qty': 1},
        }),
      ]);
      // The expensive unit buys, the cheap one goes free.
      expect(applied.first.lineAmounts, {1: 1.0});
    });
  });

  group('multi_buy', () {
    test('3 for 1.000 discounts the set down to the bundle price', () {
      final cart = [item(10, 0.5, qty: 3)];
      final applied = eval(cart, [
        const Offer(id: 1, name: '3-for-1', type: 'multi_buy', config: {
          'product_ids': [10],
          'qty': 3,
          'price_baisas': 1000,
        }),
      ]);
      expect(applied, hasLength(1));
      expect(applied.first.total, 0.5); // 1.500 − 1.000
    });

    test('set already cheaper than the offer price applies nothing', () {
      final cart = [item(10, 0.3, qty: 3)]; // 0.900 < 1.000
      final applied = eval(cart, [
        const Offer(id: 1, name: '3-for-1', type: 'multi_buy', config: {
          'product_ids': [10],
          'qty': 3,
          'price_baisas': 1000,
        }),
      ]);
      expect(applied, isEmpty);
    });

    test('repeats per complete set', () {
      final cart = [item(10, 0.5, qty: 6)];
      final applied = eval(cart, [
        const Offer(id: 1, name: '3-for-1', type: 'multi_buy', config: {
          'product_ids': [10],
          'qty': 3,
          'price_baisas': 1000,
        }),
      ]);
      expect(applied.first.applications, 2);
      expect(applied.first.total, 1.0);
    });

    test('allocation across mixed-price lines is baisas-exact', () {
      // Set value 1.500, price 1.000 → 0.500 off split 233/167/100 baisas
      // (largest remainder), summing EXACTLY to 500.
      final cart = [item(10, 0.7), item(11, 0.5), item(12, 0.3)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Mix 3', type: 'multi_buy', config: {
          'product_ids': [10, 11, 12],
          'qty': 3,
          'price_baisas': 1000,
        }),
      ]);
      final amounts = applied.first.lineAmounts;
      expect(amounts[0], 0.233);
      expect(amounts[1], 0.167);
      expect(amounts[2], 0.100);
      expect(applied.first.total, 0.5);
    });
  });

  group('cheapest_free', () {
    test('buy 3, the cheapest goes free', () {
      final cart = [item(10, 3.0), item(11, 2.0), item(12, 1.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Cheapest free', type: 'cheapest_free',
            config: {
              'product_ids': [10, 11, 12],
              'qty': 3,
            }),
      ]);
      expect(applied.first.lineAmounts, {2: 1.0});
      expect(applied.first.applications, 1);
    });

    test('free_count must stay below the set qty', () {
      final cart = [item(10, 1.0, qty: 3)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Bad config', type: 'cheapest_free', config: {
          'product_ids': [10],
          'qty': 3,
          'free_count': 3,
        }),
      ]);
      expect(applied, isEmpty);
    });
  });

  group('spend_get', () {
    test('below the threshold nothing applies', () {
      final cart = [item(10, 5.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Spend 10', type: 'spend_get', config: {
          'min_subtotal_baisas': 10000,
          'reward_type': 'percent_off',
          'reward_value': 10,
        }),
      ]);
      expect(applied, isEmpty);
    });

    test('percent_off rewards an order-level amount', () {
      final cart = [item(10, 6.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Spend 5 save 10%', type: 'spend_get',
            config: {
              'min_subtotal_baisas': 5000,
              'reward_type': 'percent_off',
              'reward_value': 10,
            }),
      ]);
      expect(applied.first.orderAmount, 0.6);
      expect(applied.first.lineAmounts, isEmpty);
    });

    test('fixed_off clamps to the eligible subtotal', () {
      final cart = [item(10, 1.5)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'Spend 1 get 2 off', type: 'spend_get',
            config: {
              'min_subtotal_baisas': 1000,
              'reward_type': 'fixed_off',
              'reward_value': 2000,
            }),
      ]);
      expect(applied.first.orderAmount, 1.5);
    });

    test('free_product frees the cheapest matching unit when present', () {
      final cart = [item(10, 6.0), item(30, 1.2)];
      const offer = Offer(id: 1, name: 'Free dessert', type: 'spend_get',
          config: {
            'min_subtotal_baisas': 5000,
            'reward_type': 'free_product',
            'reward_product_id': 30,
          });
      final applied = eval(cart, [offer]);
      expect(applied.first.lineAmounts, {1: 1.2});

      // The reward product missing from the cart → nothing happens.
      expect(eval([item(10, 6.0)], [offer]), isEmpty);
    });
  });

  group('bundle', () {
    const bundle = Offer(id: 9, name: 'Meal Deal', type: 'bundle', config: {
      'price_baisas': 2000,
      'groups': [
        {'product_ids': [10], 'qty': 1},
        {'product_ids': [20], 'qty': 1},
      ],
    });

    test('an intact instance is discounted exactly to the bundle price', () {
      final cart = [
        item(10, 1.5, bundleKey: '9:1'),
        item(20, 1.0, bundleKey: '9:1'),
      ];
      final applied = eval(cart, [bundle]);
      expect(applied, hasLength(1));
      // 2.500 − 2.000 = 0.500 split 300/200 proportionally, sum exact.
      expect(applied.first.lineAmounts, {0: 0.3, 1: 0.2});
      expect(applied.first.total, 0.5);
    });

    test('a broken instance (missing a group item) gets no discount', () {
      final cart = [item(10, 1.5, bundleKey: '9:1')];
      expect(eval(cart, [bundle]), isEmpty);
    });

    test('instances of other offers are ignored', () {
      final cart = [
        item(10, 1.5, bundleKey: '8:1'),
        item(20, 1.0, bundleKey: '8:1'),
      ];
      expect(eval(cart, [bundle]), isEmpty);
    });

    test('two instances both apply', () {
      final cart = [
        item(10, 1.5, bundleKey: '9:1'),
        item(20, 1.0, bundleKey: '9:1'),
        item(10, 1.5, bundleKey: '9:2'),
        item(20, 1.0, bundleKey: '9:2'),
      ];
      final applied = eval(cart, [bundle]);
      expect(applied.first.applications, 2);
      expect(applied.first.total, 1.0);
    });
  });

  group('exclusions and ordering', () {
    test('gifted lines join neither unit pools nor the spend threshold', () {
      // A gifted 2.000 + a paid 2.000: BOGO can't pair (one unit only) and a
      // spend_get over 3.000 doesn't trigger (eligible = 2.000).
      final cart = [item(10, 2.0, gifted: true), item(10, 2.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'B1G1', type: 'bogo', config: {
          'buy': {'product_ids': [10], 'qty': 1},
          'get': {'same_as_buy': true, 'qty': 1},
        }),
        const Offer(id: 2, name: 'Spend 3', type: 'spend_get', config: {
          'min_subtotal_baisas': 3000,
          'reward_type': 'percent_off',
          'reward_value': 10,
        }),
      ]);
      expect(applied, isEmpty);
    });

    test('bundle-tagged lines are excluded from auto offer pools', () {
      final cart = [item(10, 2.0, bundleKey: '9:1'), item(10, 2.0)];
      final applied = eval(cart, [
        const Offer(id: 1, name: 'B1G1', type: 'bogo', config: {
          'buy': {'product_ids': [10], 'qty': 1},
          'get': {'same_as_buy': true, 'qty': 1},
        }),
      ]);
      expect(applied, isEmpty); // only one free unit — no pair
    });

    test('a unit feeds at most one offer; offers evaluate in id order', () {
      final cart = [item(10, 2.0), item(10, 2.0)];
      const config = {
        'buy': {'product_ids': [10], 'qty': 1},
        'get': {'same_as_buy': true, 'qty': 1},
      };
      final applied = eval(cart, [
        const Offer(id: 2, name: 'Second', type: 'bogo', config: config),
        const Offer(id: 1, name: 'First', type: 'bogo', config: config),
      ]);
      expect(applied, hasLength(1));
      expect(applied.first.offerId, 1); // lower id wins the units
    });

    test('inactive and out-of-branch offers are skipped', () {
      final cart = [item(10, 2.0), item(10, 2.0)];
      const config = {
        'buy': {'product_ids': [10], 'qty': 1},
        'get': {'same_as_buy': true, 'qty': 1},
      };
      final applied = eval(cart, [
        const Offer(
            id: 1, name: 'Off', type: 'bogo', config: config, isActive: false),
        const Offer(
            id: 2,
            name: 'Elsewhere',
            type: 'bogo',
            config: config,
            branchScope: [99]),
      ]);
      expect(applied, isEmpty);
    });
  });

  group('ConfigMapper passthrough', () {
    test('parse() turns the offers slice into Drift companions', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'offers': [
          {
            'id': 5,
            'name': 'Meal Deal',
            'name_ar': 'وجبة',
            'type': 'bundle',
            'config': {
              'price_baisas': 2000,
              'groups': [
                {'product_ids': [10], 'qty': 1},
              ],
            },
            'auto_apply': false,
            'dayofweek_mask': 62,
            'time_start': '11:00:00',
            'time_end': '14:00:00',
            'branch_scope_json': [6],
            'max_per_order': 2,
            'status': 'active',
          },
        ],
      });
      expect(parsed.offers, hasLength(1));
      final c = parsed.offers.first;
      expect(c.id.value, 5);
      expect(c.name.value, 'Meal Deal');
      expect(c.nameAr.value, 'وجبة');
      expect(c.type.value, 'bundle');
      expect(c.configJson.value, contains('"price_baisas":2000'));
      expect(c.autoApply.value, false);
      expect(c.dayofweekMask.value, 62);
      expect(c.timeStart.value, '11:00:00');
      expect(c.branchScopeJson.value, '[6]');
      expect(c.maxPerOrder.value, 2);
      expect(c.status.value, 'active');
    });

    test('parseDelta() surfaces deleted.offers ids', () {
      final delta = ConfigMapper.parseDelta(<String, dynamic>{
        'deleted': {
          'offers': [3, 4],
        },
      });
      expect(delta.deleted.offers, [3, 4]);
    });

    test('toCatalog() rebuilds Offers (config decoded, scope, active)', () {
      final catalog = ConfigMapper.toCatalog(
        null, const [], const [], const [], const [], const [],
        const [], const [], const [], const [], const [], const [],
        const [], const [], const [], null, const [], const [],
        const [
          OfferRow(
            id: 5,
            name: 'Meal Deal',
            nameAr: 'وجبة',
            type: 'bundle',
            configJson: '{"price_baisas":2000}',
            autoApply: false,
            branchScopeJson: '[6]',
            maxPerOrder: 2,
            status: 'active',
          ),
          OfferRow(
            id: 6,
            name: 'Paused',
            type: 'bogo',
            configJson: '{}',
            autoApply: true,
            status: 'paused',
          ),
        ],
      );
      expect(catalog.offers, hasLength(2));
      final offer = catalog.offers.first;
      expect(offer.id, 5);
      expect(offer.nameAr, 'وجبة');
      expect(offer.config['price_baisas'], 2000);
      expect(offer.autoApply, false);
      expect(offer.branchScope, [6]);
      expect(offer.maxPerOrder, 2);
      expect(offer.isActive, true);
      expect(offer.isBundle, true);
      expect(catalog.offers[1].isActive, false);
    });
  });

  group('order sync payload', () {
    String Function() seqUuid() {
      var n = 0;
      return () => 'uuid-${n++}';
    }

    test('offer rows carry offer_id; the order-level entry is the rest', () {
      // Combined discount 1.500 = 0.500 manual order-level + 1.000 offer.
      final snap = OrderSnapshot.initial().copyWith(
        orderType: 'quick_order',
        items: [
          {
            'id': '10',
            'name': 'Burger',
            'qty': 2,
            'unitPrice': 2.5,
            'lineTotal': 5.0,
          },
        ],
        rawSubtotal: 5.0,
        discountAmount: 1.5,
        discountLabel: 'Manual',
        tax: 0,
        total: 3.5,
        paymentMethod: 'Cash',
        offers: [
          {'offer_id': 3, 'name': 'B1G1', 'amount': 1.0, 'line_index': 0},
        ],
      );
      final payload = buildOrderSyncPayload(
        snap,
        lat: null,
        lng: null,
        staffId: 7,
        newUuid: seqUuid(),
      );
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      expect(order['discount_total_baisas'], 1500);
      final discounts = (order['discounts'] as List).cast<Map>();
      expect(discounts, hasLength(2));
      expect(discounts[0]['name'], 'Manual');
      expect(discounts[0]['amount_baisas'], 500);
      expect(discounts[0].containsKey('offer_id'), false);
      expect(discounts[1]['name'], 'B1G1');
      expect(discounts[1]['amount_baisas'], 1000);
      expect(discounts[1]['offer_id'], 3);
      expect(discounts[1]['line_index'], 0);
      // money invariant
      expect(
        (order['subtotal_baisas'] as int) -
            (order['discount_total_baisas'] as int) +
            (order['tax_total_baisas'] as int),
        order['grand_total_baisas'],
      );
    });

    test('an offers-only discount emits no order-level row', () {
      final snap = OrderSnapshot.initial().copyWith(
        orderType: 'quick_order',
        items: [
          {
            'id': '10',
            'name': 'Burger',
            'qty': 2,
            'unitPrice': 2.5,
            'lineTotal': 5.0,
          },
        ],
        rawSubtotal: 5.0,
        discountAmount: 1.0,
        tax: 0,
        total: 4.0,
        paymentMethod: 'Cash',
        offers: [
          {'offer_id': 3, 'name': 'B1G1', 'amount': 1.0, 'line_index': 0},
        ],
      );
      final payload = buildOrderSyncPayload(
        snap,
        lat: null,
        lng: null,
        staffId: 7,
        newUuid: seqUuid(),
      );
      final order =
          (payload.events[0]['payload'] as Map)['order'] as Map<String, dynamic>;
      final discounts = (order['discounts'] as List).cast<Map>();
      expect(discounts, hasLength(1));
      expect(discounts.first['offer_id'], 3);
    });
  });
}
