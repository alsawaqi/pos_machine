import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/draft_recovery/recovery_admission.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_models.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_store.dart';
import 'package:pos_machine/qr_quick/qr_quick_store.dart';

void main() {
  sqfliteFfiInit();

  test(
    'empty existing schemas admit recovery without changing storage',
    () async {
      final harness = await _Harness.open();
      addTearDown(harness.close);
      final before = await harness.rows();

      await harness.check();

      expect(await harness.rows(), before);
    },
  );

  test(
    'valid terminal history across scopes stays retained and admits',
    () async {
      final harness = await _Harness.open();
      addTearDown(harness.close);
      await harness.checkoutRow(_paid(), scope: 'old-device|old-branch');
      for (final state in ['released', 'managed']) {
        await harness.checkoutRow(
          CheckoutAttempt(
            id: '$state-before-claim',
            orderUuid: 'bill-$state',
            state: state,
            createdAt: _time,
          ).json,
          scope: 'different-api|different-device',
        );
        await harness.checkoutRow({
          ..._paid(),
          'id': '$state-partial',
          'state': state,
          'event': null,
          'captures': [
            {'method': 'cash', 'amount_baisas': 1000, 'status': 'success'},
          ],
        }, scope: 'current-device');
      }
      final before = await harness.rows();

      await harness.check();

      expect(await harness.rows(), before);
      expect(
        (await harness.checkout.query('qr_checkout_attempts')),
        hasLength(5),
      );
    },
  );

  for (final state in [
    'claiming',
    'reserved',
    'capturing',
    'pending',
    'refused',
    'uncertain',
    'releasing',
  ]) {
    test('checkout $state in a foreign scope refuses recovery', () async {
      final harness = await _Harness.open();
      addTearDown(harness.close);
      await harness.checkoutRow(_paid(), scope: 'current-device');
      final pending = _paid(id: 'foreign-attempt');
      pending['state'] = state;
      await harness.checkoutRow(
        pending,
        scope: 'previous-server|previous-device',
      );
      final before = await harness.rows();

      await expectLater(harness.check(), throwsStateError);

      expect(await harness.rows(), before);
    });
  }

  final corruptions = <String, void Function(Map<String, Object?>)>{
    'malformed JSON': (row) => row['payload'] = '{broken',
    'non-object payload': (row) => row['payload'] = '[]',
    'unknown state': (row) {
      row['state'] = 'future_state';
      _edit(row, (payload) => payload['state'] = 'future_state');
    },
    'column ID mismatch': (row) => row['id'] = 'different-attempt',
    'terminal column hides pending payload': (row) =>
        _edit(row, (payload) => payload['state'] = 'pending'),
    'empty scope': (row) => row['scope'] = ' ',
    'invalid timestamp': (row) =>
        _edit(row, (payload) => payload['created_at'] = 'not-a-time'),
    'empty bill identity': (row) =>
        _edit(row, (payload) => payload['order_uuid'] = ''),
    'missing captures': (row) =>
        _edit(row, (payload) => payload.remove('captures')),
    'corrupt capture map': (row) =>
        _edit(row, (payload) => payload['captures'] = ['invalid']),
    'paid without event': (row) =>
        _edit(row, (payload) => payload['event'] = null),
    'paid without claim': (row) =>
        _edit(row, (payload) => payload['claim'] = null),
    'wrong claim bill': (row) => _edit(
      row,
      (payload) => (payload['claim'] as Map)['order_uuid'] = 'different-bill',
    ),
    'wrong payment event ID': (row) => _edit(
      row,
      (payload) =>
          (payload['event'] as Map)['client_event_id'] = 'different-event',
    ),
    'wrong payment bill': (row) => _edit(
      row,
      (payload) => ((payload['event'] as Map)['payload'] as Map)['order_uuid'] =
          'different-bill',
    ),
    'wrong total': (row) => _edit(
      row,
      (payload) => (payload['claim'] as Map)['charge_amount_baisas'] = 5000,
    ),
    'capture differs from event': (row) => _edit(
      row,
      (payload) =>
          ((payload['captures'] as List).single as Map)['amount_baisas'] = 1,
    ),
    'invalid order ID': (row) =>
        _edit(row, (payload) => payload['order_id'] = 0),
    'managed partial capture without claim': (row) {
      row['state'] = 'managed';
      _edit(row, (payload) {
        payload['state'] = 'managed';
        payload['claim'] = null;
        payload['event'] = null;
      });
    },
    'released partial capture exceeds claim': (row) {
      row['state'] = 'released';
      _edit(row, (payload) {
        payload['state'] = 'released';
        payload['event'] = null;
        ((payload['captures'] as List).single as Map)['amount_baisas'] = 9999;
      });
    },
  };
  for (final entry in corruptions.entries) {
    test(
      'terminal checkout with ${entry.key} blocks and retains evidence',
      () async {
        final harness = await _Harness.open();
        addTearDown(harness.close);
        final row = <String, Object?>{
          'id': 'attempt',
          'scope': 'other-device|other-company',
          'state': 'paid',
          'payload': jsonEncode(_paid()),
        };
        entry.value(row);
        await harness.checkout.insert('qr_checkout_attempts', row);
        final before = await harness.rows();

        await expectLater(harness.check(), throwsFormatException);

        expect(await harness.rows(), before);
      },
    );
  }

  for (final journal in ['dine_in_requests', 'qr_quick_requests']) {
    for (final malformed in [false, true]) {
      test(
        '$journal ${malformed ? 'malformed' : 'pending'} foreign-scope row blocks',
        () async {
          final harness = await _Harness.open();
          addTearDown(harness.close);
          final db = journal == 'dine_in_requests'
              ? harness.dineIn
              : harness.quick;
          await db.insert(journal, {
            'scope': 'previous-server|previous-branch|previous-device',
            'request_id': 'saved-request',
            if (journal == 'dine_in_requests') ...{
              'table_id': 12,
              'seating_uuid': 'saved-seating',
              'bill_uuid': 'saved-bill',
            } else
              'order_uuid': 'saved-bill',
            'payload': malformed
                ? '{broken'
                : jsonEncode({
                    'client_request_id': 'saved-request',
                    if (journal == 'dine_in_requests') ...{
                      'table_id': 12,
                      'seating_key': 'saved-key',
                      'submitted_at': _time.toIso8601String(),
                      'queued_offline': false,
                    },
                    'lines': [
                      {'product_id': 1, 'qty': 1, 'addon_ids': [], 'notes': ''},
                    ],
                  }),
          });
          final before = await harness.rows();

          await expectLater(harness.check(), throwsStateError);

          expect(await harness.rows(), before);
        },
      );
    }
  }

  for (final journal in [
    'qr_checkout_attempts',
    'dine_in_requests',
    'qr_quick_requests',
  ]) {
    for (final partial in [false, true]) {
      test(
        '${partial ? 'incomplete' : 'missing'} $journal schema refuses admission',
        () async {
          final harness = await _Harness.open(omitSchema: journal);
          addTearDown(harness.close);
          final db = switch (journal) {
            'qr_checkout_attempts' => harness.checkout,
            'dine_in_requests' => harness.dineIn,
            _ => harness.quick,
          };
          if (partial) {
            await db.execute('CREATE TABLE $journal (unrelated TEXT)');
          }
          final before = await db.query('sqlite_master');

          await expectLater(harness.check(), throwsA(isA<DatabaseException>()));

          expect(
            await db.query('sqlite_master'),
            before,
            reason:
                'Admission must not silently create or repair journal schemas.',
          );
        },
      );
    }
  }
}

final _time = DateTime.utc(2026, 9, 12, 12);

Map<String, dynamic> _paid({String id = 'attempt'}) {
  final captures = [
    {'method': 'cash', 'amount_baisas': 4750, 'status': 'success'},
  ];
  return CheckoutAttempt(
    id: id,
    orderUuid: 'bill',
    state: 'paid',
    createdAt: _time,
    claim: {
      'order_uuid': 'bill',
      'status': 'awaiting_payment',
      'charge_amount_baisas': 4750,
      'charge_claimed_at': _time.toIso8601String(),
      'charge_deadline_at': _time
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'already_claimed_by_this_device': false,
    },
    orderId: 12,
    event: {
      'client_event_id': id,
      'event_type': 'order.pay',
      'client_timestamp': _time.toIso8601String(),
      'payload': {
        'order_uuid': 'bill',
        'paid_at': _time.toIso8601String(),
        'payments': captures,
      },
    },
    captures: captures,
    receiptNumber: 'R-012',
  ).json;
}

void _edit(
  Map<String, Object?> row,
  void Function(Map<String, dynamic>) change,
) {
  final payload = (jsonDecode(row['payload'] as String) as Map)
      .cast<String, dynamic>();
  change(payload);
  row['payload'] = jsonEncode(payload);
}

class _Harness {
  _Harness(this.checkout, this.dineIn, this.quick);
  final Database checkout;
  final Database dineIn;
  final Database quick;

  static Future<_Harness> open({String? omitSchema}) async {
    Future<Database> database() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    final checkout = await database();
    final dineIn = await database();
    final quick = await database();
    if (omitSchema != 'qr_checkout_attempts') {
      await SqliteCheckoutStore.createSchema(checkout);
    }
    if (omitSchema != 'dine_in_requests') {
      await SqliteDineInStore.createSchema(dineIn);
    }
    if (omitSchema != 'qr_quick_requests') {
      await SqliteQrQuickStore.createSchema(quick);
    }
    return _Harness(checkout, dineIn, quick);
  }

  Future<void> check() => assertRecoveryJournalsIdle(
    checkout: checkout,
    dineIn: dineIn,
    quick: quick,
  );

  Future<void> checkoutRow(
    Map<String, dynamic> payload, {
    required String scope,
  }) async {
    await checkout.insert('qr_checkout_attempts', {
      'id': payload['id'],
      'scope': scope,
      'state': payload['state'],
      'payload': jsonEncode(payload),
    });
  }

  Future<List<List<Map<String, Object?>>>> rows() async => [
    await checkout.query('qr_checkout_attempts'),
    await dineIn.query('dine_in_requests'),
    await quick.query('qr_quick_requests'),
  ];

  Future<void> close() async {
    await checkout.close();
    await dineIn.close();
    await quick.close();
  }
}
