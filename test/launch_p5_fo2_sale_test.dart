import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/auth_wire.dart';
import 'package:pos_machine/core/authorization.dart';
import 'package:pos_machine/core/permissions.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/state/pos_controller.dart';

import 'support/fake_order_storage.dart';

/// LAUNCH-P5 fix order 2 — T2 (a gift approval never grows), T3 (the
/// loyalty discount row says it is loyalty), T6 (a manual discount above
/// the maximum on the final amounts), T11 (an acknowledged outbox row keeps
/// no staff token), T12 (no gift tender inside a split).
const _latte = Product(id: '10', name: 'Latte', category: 'X', price: 2.0);
const _tea = Product(id: '11', name: 'Tea', category: 'X', price: 1.0);
const _device = '3f1b2c4d-5e6f-4a7b-8c9d-0e1f2a3b4c5d';

PosController _build(FakeOrderStorage storage) =>
    PosController(orderStorage: storage)..applyCatalog(
      categories: const ['X'],
      products: const [_latte, _tea],
      floors: const [],
      tables: const [],
      taxes: const <CompanyTax>[],
    );

ActionAuthorization _giftApproval() => ActionAuthorization.approval(
  action: 'gift',
  actorStaffId: 7,
  actorName: 'Cashier',
  deviceUuid: _device,
  grant: ApprovalGrant(
    approverStaffId: 9,
    name: 'Manager',
    approvedAt: DateTime.utc(2026, 10, 4, 9),
    method: 'offline',
    key: Uint8List(32),
  ),
);

class _Api implements PosApiService {
  @override
  Future<Map<String, dynamic>> pushSync(
    List<Map<String, dynamic>> events,
  ) async => {
    'results': [
      for (final e in events)
        {
          'client_event_id': e['client_event_id'],
          'status': 'processed',
          'result': <String, dynamic>{},
        },
    ],
  };

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T2 — a gift approval never covers more than the approver saw', () {
    late FakeOrderStorage storage;
    late PosController c;
    OrderSnapshot? done;

    setUp(() {
      storage = FakeOrderStorage();
      c = _build(storage);
      done = null;
      c.onOrderCompleted = (s) => done = s;
    });
    tearDown(() => c.dispose());

    CartItem giftLatte() {
      c.addProduct(_tea);
      c.addProduct(_latte);
      final item = c.cart.firstWhere((i) => i.product.id == '10');
      c.toggleGiftItem(item);
      c.recordGiftAuthorization(item, _giftApproval());
      return item;
    }

    List<Map<String, dynamic>> giftBlocks() => [
      for (final b in done!.authorizations)
        if (b['action'] == 'gift') b,
    ];

    test(
      'the review probe: nine more taps never join the gifted line',
      () async {
        final item = giftLatte();
        for (var i = 0; i < 9; i++) {
          c.addProduct(_latte);
        }
        expect(item.qty, 1);
        expect(item.gifted, isTrue);
        final lattes = c.cart.where((i) => i.product.id == '10').toList();
        expect(lattes, hasLength(2));
        expect(lattes.firstWhere((i) => !i.gifted).qty, 9);
        await c.payAndPrint();
        final blocks = giftBlocks();
        expect(blocks, hasLength(1));
        expect(blocks.single['amount_baisas'], 2000);
        expect(blocks.single['proof'], isNotNull);
      },
    );

    test(
      'a quantity change drops the gift and its approval, with a message',
      () async {
        final approval = _giftApproval();
        c.addProduct(_tea);
        c.addProduct(_latte);
        final item = c.cart.firstWhere((i) => i.product.id == '10');
        c.toggleGiftItem(item);
        c.recordGiftAuthorization(item, approval);
        final messages = <String>[];
        c.onDraftRedemptionCleared = messages.add;
        c.incrementCartItem(item);
        expect(item.qty, 2);
        expect(item.gifted, isFalse);
        expect(approval.grant!.canSign, isFalse, reason: 'the key is wiped');
        expect(messages.single, contains('Latte'));
        await c.payAndPrint();
        expect(giftBlocks(), isEmpty);
      },
    );

    test('a decrease and an options change drop it too', () async {
      c.addProduct(_tea);
      c.addProduct(_latte);
      final item = c.cart.firstWhere((i) => i.product.id == '10');
      c.incrementCartItem(item); // qty 2, then gifted
      c.toggleGiftItem(item);
      c.recordGiftAuthorization(item, _giftApproval());
      c.decreaseCartItem(item);
      expect(item.gifted, isFalse);

      c.toggleGiftItem(item);
      c.recordGiftAuthorization(item, _giftApproval());
      c.updateCartItemCustomization(
        item,
        modifiers: const [
          CartItemModifier(
            id: 'm1',
            group: 'Milk',
            label: 'Oat milk',
            price: 0.5,
          ),
        ],
        notes: '',
      );
      expect(item.gifted, isFalse);
    });

    test(
      'a gift that grew any other way is never signed over the larger amount',
      () async {
        final item = giftLatte(); // approved at 2.000
        // A path that changes the line without dropping the gift (none is
        // known; this is the last line of defence at signing).
        item.qty = 3;
        c.addProduct(_tea); // re-prices the cart
        expect(c.giftAmountFor(item), 6.0);
        await c.payAndPrint();
        expect(giftBlocks(), isEmpty);
      },
    );
  });

  group('T12 — no gift tender inside a split', () {
    test('refused by the controller', () async {
      final storage = FakeOrderStorage();
      final c = _build(storage);
      addTearDown(c.dispose);
      c.addProduct(_latte);
      c.setSplitCount(2);
      expect(c.splitActive, isTrue);
      c.selectPaymentMethod('Gift');
      final message = await c.payAndPrint();
      expect(
        message,
        'A gift covers the whole bill. It cannot be one part of a split.',
      );
      expect(storage.history, isEmpty);
    });
  });

  test('T12 — the Gift button is hidden during a split', () {
    final screen = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
    expect(
      RegExp(
        r'if \(qr != null \|\|\s*\(!_liveTable && !controller\.splitActive\)\)',
      ).hasMatch(screen),
      isTrue,
    );
    expect(
      RegExp(
        r'Future<void> _submitGiftPayment\(\) async \{[^}]*if \(controller\.splitActive\) return;',
      ).hasMatch(screen),
      isTrue,
    );
  });

  group('T3 — the loyalty discount row', () {
    test('carries source: loyalty and no discount_id', () async {
      final storage = FakeOrderStorage();
      final c = _build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(_latte);
      c.attachCustomer(const CustomerSearchResult(id: 5, name: 'C'));
      expect(
        c.applyLoyaltyRedemption(
          ruleId: 3,
          valueOmr: 0.5,
          label: 'Loyalty redemption',
          customerId: 5,
          points: 50,
        ),
        isTrue,
      );
      await c.payAndPrint();
      final order =
          (buildOrderSyncPayload(done!, staffId: 7).events.first['payload']
                  as Map)['order']
              as Map;
      final row = (order['discounts'] as List).single as Map;
      expect(row['source'], 'loyalty');
      expect(row.containsKey('discount_id'), isTrue);
      expect(row['discount_id'], isNull);
      expect(row['amount_baisas'], 500);
    });

    test('a manual discount carries no source', () async {
      final storage = FakeOrderStorage();
      final c = _build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(_latte);
      c.applyDiscount(
        const DiscountConfiguration(
          kind: DiscountKind.fixedAmount,
          value: 0.2,
          label: 'Friend',
        ),
      );
      await c.payAndPrint();
      final order =
          (buildOrderSyncPayload(done!, staffId: 7).events.first['payload']
                  as Map)['order']
              as Map;
      final row = (order['discounts'] as List).single as Map;
      expect(row.containsKey('source'), isFalse);
    });
  });

  group('T6 — a manual discount on the final amounts', () {
    test('above the maximum after items were removed, with no approval', () {
      final storage = FakeOrderStorage();
      final c = _build(storage);
      addTearDown(c.dispose);
      final cashier = StaffPermissions(PositionPermissions.defaults, 'cashier');
      for (var i = 0; i < 5; i++) {
        c.addProduct(_latte); // 10.000
      }
      c.applyDiscount(
        const DiscountConfiguration(
          kind: DiscountKind.fixedAmount,
          value: 1.0, // 10 %: within the cashier's limit
          label: 'Friend',
        ),
      );
      expect(c.manualDiscountAboveMax(cashier), isNull);
      final latte = c.cart.single;
      for (var i = 0; i < 4; i++) {
        c.decreaseCartItem(latte); // down to 2.000: now 50 %
      }
      expect(c.manualDiscountAboveMax(cashier), closeTo(50, 0.01));
      // An approver's approval covers it; a position block does not.
      c.recordOrderAuthorization(
        'discount',
        ActionAuthorization.position(
          action: 'discount.manual',
          actorStaffId: 7,
          actorName: 'Cashier',
        ),
      );
      expect(c.manualDiscountAboveMax(cashier), isNotNull);
      c.recordOrderAuthorization(
        'discount',
        ActionAuthorization.approval(
          action: 'discount.manual',
          actorStaffId: 7,
          actorName: 'Cashier',
          deviceUuid: _device,
          grant: ApprovalGrant(
            approverStaffId: 9,
            name: 'Manager',
            approvedAt: DateTime.utc(2026, 10, 4, 9),
            method: 'offline',
            key: Uint8List(32),
          ),
        ),
      );
      expect(c.manualDiscountAboveMax(cashier), isNull);
      // A manager may give 50 %.
      expect(
        c.manualDiscountAboveMax(
          StaffPermissions(PositionPermissions.defaults, 'manager'),
        ),
        isNull,
      );
    });

    test('the payment page re-checks it before opening', () {
      // The local payment page asks the sheet when the check above says so.
      final screen = File(
        'lib/screens/staff_pos_screen.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'if \(!await _recheckManualDiscount\(\) \|\| !mounted\) return;\s*'
          r'setState\(\(\) \{\s*_showPaymentPage = true;',
        ).hasMatch(screen),
        isTrue,
      );
    });
  });

  group('T11 — acknowledged rows keep no staff token', () {
    test('stripped when the server acknowledges the row', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      StaffTokenHolder.set(7, 'tok-7');
      addTearDown(StaffTokenHolder.clear);
      final event = buildOrderVoidEvent(orderUuid: 'o-1', staffId: 7);
      expect(event['payload']['staff_token'], 'tok-7');
      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: 'o-1:void',
          eventsJson: jsonEncode([event]),
          createdAt: DateTime.utc(2026, 10, 4, 6),
        ),
      );
      // Unsent: the maker's token stays for the retry.
      expect((await db.getOutbox('o-1:void'))!.eventsJson, contains('tok-7'));
      await OrderSyncRepository(_Api(), db).flush();
      final row = (await db.getOutbox('o-1:void'))!;
      expect(row.syncedAt, isNotNull);
      expect(row.eventsJson, isNot(contains('staff_token')));
      final kept = (jsonDecode(row.eventsJson) as List).single as Map;
      expect(kept['client_event_id'], event['client_event_id']);
      expect(kept['payload']['order_uuid'], 'o-1');
      expect(kept['payload']['auth_v'], 1);
    });

    test('the table verdict keeps the acknowledged request without it', () {
      final kept = payloadWithoutStaffToken({
        'client_request_id': 'r-1',
        'staff_token': 'tok-7',
      });
      expect(kept, {'client_request_id': 'r-1'});
      final screen = File(
        'lib/data/table_sync_coordinator.dart',
      ).readAsStringSync();
      expect(
        screen.split("'request': payloadWithoutStaffToken(payload)").length - 1,
        2,
      );
    });

    test('the helper strips the top level and the order', () {
      final json = jsonEncode([
        {
          'payload': {
            'staff_token': 'a',
            'order': {'staff_token': 'b', 'uuid': 'u'},
          },
        },
        {
          'payload': {'x': 1},
        },
      ]);
      final out = eventsWithoutStaffTokens(json)!;
      expect(out, isNot(contains('staff_token')));
      expect(out, contains('"uuid":"u"'));
      expect(eventsWithoutStaffTokens('[{"payload":{"x":1}}]'), isNull);
      expect(eventsWithoutStaffTokens('not json staff_token'), isNull);
    });
  });
}
