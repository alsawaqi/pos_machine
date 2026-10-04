import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approval_proof.dart';
import 'package:pos_machine/core/authorization.dart';
import 'package:pos_machine/core/permissions.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/expense_restock_payload.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/services/shift_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';

import 'support/fake_order_storage.dart';

/// LAUNCH-P5 C3 — the authorization wire: blocks on every gated event, the
/// staff id on order.pay, `auth_v: 1` on every event this build creates, and
/// never the fixed word "Manager".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final goldens =
      jsonDecode(
            File(
              'test/fixtures/approval_proof_goldens.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final vector = (goldens['vectors'] as List).first as Map<String, dynamic>;

  ApprovalGrant goldenGrant() => ApprovalGrant(
    approverStaffId: vector['approver_staff_id'] as int,
    name: 'Mona',
    approvedAt: DateTime.parse(vector['approved_at'] as String),
    method: 'offline',
    key: hexToBytes(vector['k_hex'] as String),
  );

  group('authorization block', () {
    test('an approval block carries the golden proof', () {
      final auth = ActionAuthorization.approval(
        action: vector['action'] as String,
        actorStaffId: 9,
        actorName: 'Cashier',
        grant: goldenGrant(),
        deviceUuid: vector['device_uuid'] as String,
      );
      final block = auth.block(
        subjectUuid: vector['subject_uuid'] as String,
        amountBaisas: vector['amount_baisas'] as int,
        ref: vector['ref'] as String,
      );
      expect(block, {
        'action': 'discount.manual',
        'ref': 'discount:0',
        'mode': 'approval',
        'actor_staff_id': 9,
        'approver_staff_id': 42,
        'approved_at': '2026-10-04T09:15:30.123Z',
        'method': 'offline',
        'proof': vector['proof_hex'],
        'subject_uuid': vector['subject_uuid'],
        'amount_baisas': 250,
      });
      expect(auth.authorizedByName, 'Mona');
    });

    test('a position block names only the actor', () {
      final auth = ActionAuthorization.position(
        action: 'comp',
        actorStaffId: 3,
        actorName: 'Sara',
      );
      expect(auth.block(ref: 'comp:0'), {
        'action': 'comp',
        'ref': 'comp:0',
        'mode': 'position',
        'actor_staff_id': 3,
      });
      expect(auth.authorizedByName, 'Sara');
    });

    test('a forgotten grant signs nothing more', () {
      final grant = goldenGrant();
      final auth = ActionAuthorization.approval(
        action: 'comp',
        actorStaffId: 1,
        actorName: 'A',
        grant: grant,
        deviceUuid: 'd',
      );
      grant.forget();
      expect(auth.block(ref: 'comp:0').containsKey('proof'), isFalse);
      expect(auth.block(ref: 'comp:0')['approver_staff_id'], 42);
    });
  });

  group('events', () {
    test('order.pay carries the staff id; order.create the blocks', () {
      final snapshot = OrderSnapshot.initial().copyWith(
        items: [
          {
            'id': '10',
            'name': 'Latte',
            'qty': 1,
            'unitPrice': 1.0,
            'lineTotal': 1.0,
          },
        ],
        rawSubtotal: 1.0,
        subtotal: 1.0,
        total: 1.0,
        payableTotal: 1.0,
        activePaymentBaseTotal: 1.0,
        paymentMethod: 'Cash',
        serverOrderUuid: 'order-1',
        authorizations: [
          {
            'action': 'comp',
            'ref': 'comp:0',
            'mode': 'position',
            'actor_staff_id': 4,
          },
        ],
      );
      final payload = buildOrderSyncPayload(snapshot, staffId: 4);
      final create = payload.events.first['payload']['order'] as Map;
      expect(create['authorizations'], snapshot.authorizations);
      final pay = payload.events[1];
      expect(pay['event_type'], 'order.pay');
      expect(pay['payload']['staff_id'], 4);
    });

    test('a sale without gated actions sends no authorizations key', () {
      final snapshot = OrderSnapshot.initial().copyWith(
        items: [
          {
            'id': '10',
            'name': 'Latte',
            'qty': 1,
            'unitPrice': 1.0,
            'lineTotal': 1.0,
          },
        ],
        rawSubtotal: 1.0,
        subtotal: 1.0,
        total: 1.0,
        payableTotal: 1.0,
        serverOrderUuid: 'order-2',
      );
      final create =
          buildOrderSyncPayload(snapshot).events.first['payload']['order']
              as Map;
      expect(create.containsKey('authorizations'), isFalse);
    });

    test('order.void carries the voider and the block', () {
      final event = buildOrderVoidEvent(
        orderUuid: 'o-1',
        staffId: 8,
        authorizedBy: 'Mona',
        authorization: {'action': 'order.void_paid', 'mode': 'position'},
      );
      expect(event['payload']['staff_id'], 8);
      expect(event['payload']['authorized_by'], 'Mona');
      expect(event['payload']['authorization'], {
        'action': 'order.void_paid',
        'mode': 'position',
      });
    });

    test('the standalone QR order.pay carries the staff id', () {
      final event = buildStandaloneQrPayEvent(
        orderUuid: 'q-1',
        frozenAmountBaisas: 500,
        method: 'cash',
        staffId: 6,
      );
      expect(event['payload']['staff_id'], 6);
    });

    test('a device pay-out is paid from the drawer and gated', () {
      final event = buildExpenseLogEvent(
        category: 'supplies',
        amountBaisas: 1500,
        staffId: 2,
        paidFromDrawer: true,
        authorization: {'action': 'payout', 'mode': 'position'},
      );
      expect(event['payload']['paid_from_drawer'], isTrue);
      expect(event['payload']['authorization'], {
        'action': 'payout',
        'mode': 'position',
      });
      expect(event['payload']['auth_v'], 1);
    });

    test('every builder stamps auth_v', () {
      final snapshot = OrderSnapshot.initial().copyWith(
        items: [
          {
            'id': '10',
            'name': 'Latte',
            'qty': 1,
            'unitPrice': 1.0,
            'lineTotal': 1.0,
          },
        ],
        rawSubtotal: 1.0,
        subtotal: 1.0,
        total: 1.0,
        payableTotal: 1.0,
        serverOrderUuid: 'o-9',
      );
      for (final e in buildOrderSyncPayload(snapshot).events) {
        expect(e['payload']['auth_v'], 1, reason: e['event_type'] as String);
      }
      expect(
        buildTableSessionEvent(
          'open',
          seatingKey: 's',
          tableId: '3',
          queuedOffline: false,
          payload: const {},
        )['payload']['auth_v'],
        1,
      );
      expect(
        buildStandaloneQrPayEvent(
          orderUuid: 'q',
          frozenAmountBaisas: 1,
          method: 'cash',
        )['payload']['auth_v'],
        1,
      );
    });

    test('shift.open carries auth_v', () {
      final event = buildShiftOpenEvent(
        shiftUuid: 's-1',
        openingCashBaisas: 0,
        staffId: 1,
      );
      expect(event['payload']['auth_v'], 1);
    });

    test(
      'events this build creates carry auth_v; an older one stays legacy',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        addTearDown(db.close);
        await db.enqueueOutbox(
          OrderOutboxCompanion.insert(
            orderUuid: 'k-1',
            eventsJson: jsonEncode([
              buildOrderVoidEvent(orderUuid: 'o-1'),
              {
                'client_event_id': 'x',
                'event_type': 'order.hold',
                'client_timestamp': '2026-10-04T00:00:00Z',
                'payload': {'order': {}},
              },
            ]),
            createdAt: DateTime.utc(2026, 10, 4),
          ),
        );
        final row = await db.getOutbox('k-1');
        final events = (jsonDecode(row!.eventsJson) as List).cast<Map>();
        // The void comes from a P5 builder; the hold was queued as an older
        // build made it and is sent byte for byte.
        expect(events.map((e) => e['payload']['auth_v']), [1, null]);
      },
    );
  });

  group('the controller signs a sale\'s approvals at completion', () {
    const latte = Product(id: '10', name: 'Latte', category: 'X', price: 10.0);

    PosController build(FakeOrderStorage storage) {
      final c = PosController(orderStorage: storage);
      c.applyCatalog(
        categories: const ['X'],
        products: const [latte],
        floors: const [],
        tables: const [],
        taxes: const <CompanyTax>[],
      );
      c.staffPermissions = () =>
          StaffPermissions(PositionPermissions.defaults, 'cashier');
      c.currentActor = () => (id: 5, name: 'Cashier');
      return c;
    }

    test(
      'a manual discount approval is signed over the order and amount',
      () async {
        final storage = FakeOrderStorage();
        final c = build(storage);
        addTearDown(c.dispose);
        OrderSnapshot? done;
        c.onOrderCompleted = (s) => done = s;
        c.addProduct(latte);
        c.applyDiscount(
          const DiscountConfiguration(
            kind: DiscountKind.percentage,
            value: 30,
            label: 'Friend',
          ),
        );
        final grant = goldenGrant();
        c.recordOrderAuthorization(
          'discount',
          ActionAuthorization.approval(
            action: 'discount.manual',
            actorStaffId: 5,
            actorName: 'Cashier',
            grant: grant,
            deviceUuid: vector['device_uuid'] as String,
          ),
        );
        await c.payAndPrint();
        expect(done, isNotNull);
        final blocks = done!.authorizations;
        expect(blocks, hasLength(1));
        final block = blocks.single;
        expect(block['action'], 'discount.manual');
        expect(block['mode'], 'approval');
        expect(block['ref'], 'discount:0');
        expect(block['approver_staff_id'], 42);
        expect(block['subject_uuid'], done!.serverOrderUuid);
        expect(block['amount_baisas'], 3000);
        final expected = approvalProof(
          hexToBytes(vector['k_hex'] as String),
          approvalCanonical(
            action: 'discount.manual',
            deviceUuid: vector['device_uuid'] as String,
            approverStaffId: 42,
            approvedAt: vector['approved_at'] as String,
            subjectUuid: done!.serverOrderUuid,
            amountBaisas: 3000,
            ref: 'discount:0',
          ),
        );
        expect(block['proof'], expected);
        // The key is wiped once the sale is signed.
        expect(grant.canSign, isFalse);
        // The payload carries the same blocks.
        final create =
            buildOrderSyncPayload(
                  done!,
                  staffId: 5,
                ).events.first['payload']['order']
                as Map;
        expect(create['authorizations'], blocks);
      },
    );

    test('a discount within the maximum sends no block', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(latte);
      c.applyDiscount(
        const DiscountConfiguration(
          kind: DiscountKind.percentage,
          value: 10,
          label: 'Small',
        ),
      );
      await c.payAndPrint();
      expect(done!.authorizations, isEmpty);
    });

    test(
      'a discount above the maximum with no approval is still reported',
      () async {
        final storage = FakeOrderStorage();
        final c = build(storage);
        addTearDown(c.dispose);
        OrderSnapshot? done;
        c.onOrderCompleted = (s) => done = s;
        c.addProduct(latte);
        c.applyDiscount(
          const DiscountConfiguration(
            kind: DiscountKind.fixedAmount,
            value: 5,
            label: 'Half',
          ),
        );
        await c.payAndPrint();
        expect(done!.authorizations, [
          {
            'action': 'discount.manual',
            'ref': 'discount:0',
            'mode': 'position',
            'actor_staff_id': 5,
          },
        ]);
      },
    );

    test('clearing the discount drops its approval', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(latte);
      c.applyDiscount(
        const DiscountConfiguration(
          kind: DiscountKind.percentage,
          value: 50,
          label: 'Big',
        ),
      );
      final grant = goldenGrant();
      c.recordOrderAuthorization(
        'discount',
        ActionAuthorization.approval(
          action: 'discount.manual',
          actorStaffId: 5,
          actorName: 'Cashier',
          grant: grant,
          deviceUuid: 'd',
        ),
      );
      c.clearDiscount();
      expect(grant.canSign, isFalse);
      await c.payAndPrint();
      expect(done!.authorizations, isEmpty);
    });

    test('a gift line is signed as gift:i over its comps row', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(latte);
      final item = c.cart.single;
      expect(c.toggleGiftItem(item), isTrue);
      c.recordGiftAuthorization(
        item,
        ActionAuthorization.position(
          action: 'gift',
          actorStaffId: 5,
          actorName: 'Cashier',
        ),
      );
      await c.payAndPrint();
      expect(done!.authorizations, [
        {
          'action': 'gift',
          'ref': 'gift:0',
          'mode': 'position',
          'actor_staff_id': 5,
        },
      ]);
    });

    test('loyalty and gift-tender blocks use the Part A refs', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(latte);
      c.recordOrderAuthorization(
        'gift_tender',
        ActionAuthorization.position(
          action: 'gift',
          actorStaffId: 5,
          actorName: 'Cashier',
        ),
      );
      c.selectPaymentMethod('Gift');
      await c.payAndPrint();
      expect(done!.authorizations, [
        {
          'action': 'gift',
          'ref': 'tender:0',
          'mode': 'position',
          'actor_staff_id': 5,
        },
      ]);
    });

    test('a comp approval is signed over the comp row', () async {
      final storage = FakeOrderStorage();
      final c = build(storage);
      addTearDown(c.dispose);
      OrderSnapshot? done;
      c.onOrderCompleted = (s) => done = s;
      c.addProduct(latte);
      c.applyComp(const AppliedComp(reasonId: 3, reasonName: 'Staff meal'));
      c.recordOrderAuthorization(
        'comp',
        ActionAuthorization.position(
          action: 'comp',
          actorStaffId: 5,
          actorName: 'Cashier',
        ),
      );
      await c.payAndPrint();
      expect(done!.authorizations, [
        {
          'action': 'comp',
          'ref': 'comp:0',
          'mode': 'position',
          'actor_staff_id': 5,
        },
      ]);
    });

    test(
      'a paid cancel voids with the real approver, never "Manager"',
      () async {
        final storage = FakeOrderStorage();
        final c = build(storage);
        addTearDown(c.dispose);
        c.addProduct(latte);
        await c.payAndPrint();
        await c.refreshOrderHistory();
        final record = c.orderHistory.single;
        String? voidedBy;
        ActionAuthorization? passed;
        c.onOrderVoided =
            (uuid, {orderNumber, reason, voidReasonId, authorization}) {
              passed = authorization;
              voidedBy = authorization?.authorizedByName;
            };
        final gate = ActionAuthorization.position(
          action: 'order.void_paid',
          actorStaffId: 5,
          actorName: 'Sara',
        );
        await c.cancelCompletedOrder(
          record,
          cancelFullOrder: true,
          itemIndexes: const {},
          authorization: gate,
        );
        expect(passed, same(gate));
        expect(voidedBy, 'Sara');
        await c.refreshOrderHistory();
        expect(
          c.orderHistory.single.snapshot.cancellations.single.authorizedBy,
          'Sara',
        );
      },
    );
  });
}
