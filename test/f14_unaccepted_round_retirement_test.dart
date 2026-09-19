import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/draft_recovery/recovery_local.dart';
import 'draft_recovery_test.dart';

void main() {
  sqfliteFfiInit();
  test('F14 closed bill read requests complete round evidence', () async {
    final dio = Dio();
    final requests = <RequestOptions>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'data': {
                  'orders': [
                    {
                      'uuid': billId,
                      'table_id': 5,
                      'order_type': 'dine_in',
                      'status': 'paid',
                      'table_round_evidence': {'complete': true},
                    },
                  ],
                },
                'meta': {'last_page': 1},
                'errors': [],
              },
            ),
          );
        },
      ),
    );
    final result = await PosApiService(
      tokenGetter: () => 'fixture',
      dio: dio,
    ).closedTableBill(billId, 5);
    expect(requests.single.queryParameters['include_table_rounds'], 1);
    expect(result!['table_round_evidence'], {'complete': true});
  });
  for (final shape in [
    'rejected',
    'held-rejected',
    'held-absent',
    'local-pending',
    'server-pending',
    'no-proof',
    'wrong-accepted-lines',
    'unsent',
  ]) {
    test(
      'F14 real SQLite ledger $shape archives all evidence only with closed accepted-round proof',
      () async {
        final h = RecoveryHarness();
        await h.init(qty: shape == 'unsent' ? 3 : 2);
        addTearDown(h.close);
        await h.db.execute(
          'ALTER TABLE local_line_cancellations ADD COLUMN seating_key TEXT',
        );
        final accepted = (await h.db.query('local_table_rounds')).single;
        const rejectedId = '55555555-5555-4555-8555-555555555555';
        const key = 'tbl:$seatKey:round:$rejectedId';
        final rejectedLines = [
          {'product_id': 8, 'qty': 1},
        ];
        await h.db.insert('local_table_rounds', {
          ...accepted,
          'client_request_id': rejectedId,
          'local_round_no': 2,
          'server_round_id': 21,
          'server_round_no': 2,
          'outbox_key': key,
          'lines_json': jsonEncode(rejectedLines),
          'status': shape == 'rejected'
              ? 'rejected'
              : shape == 'local-pending'
              ? 'pending'
              : 'held',
          'held_lines_json': '[{"line_index":0,"reason":"out_of_stock"}]',
          'review_reasons_json': '["out_of_stock"]',
        });
        h.outbox[key] = OrderOutboxRow(
          orderUuid: key,
          eventsJson: jsonEncode([
            {
              'event_type': 'table.session.round',
              'client_event_id': rejectedId,
              'payload': {
                'client_request_id': rejectedId,
                'seating_key': seatKey,
                'table_id': 1,
                'order_uuid': billId,
                'lines': rejectedLines,
              },
            },
          ]),
          createdAt: DateTime.now(),
          syncedAt: DateTime.now(),
          attempts: 0,
          serverRejections: 0,
        );
        final originals = await h.db.query('dining_tables');
        final ledger = await h.db.query('local_table_rounds');
        if (shape == 'local-pending') {
          await expectLater(
            loadRecoveryLocal(
              h.db,
              1,
              outboxRow: (key) async => h.outbox[key],
              currentGenerationOnly: true,
            ),
            throwsStateError,
          );
          expect(await h.db.query('dining_tables'), originals);
          return;
        }
        final local = await loadRecoveryLocal(
          h.db,
          1,
          outboxRow: (key) async => h.outbox[key],
          currentGenerationOnly: true,
        );
        final bill = <String, dynamic>{
          'uuid': billId,
          'table_id': 1,
          'order_type': 'dine_in',
          'status': 'paid',
          'items': [
            {
              'id': 100,
              'product_id': 7,
              'qty': 2.0,
              'notes': 'Keep Exactly',
              'addons': [],
              'status': 'paid',
            },
          ],
          if (shape != 'no-proof')
            'table_round_evidence': {
              'complete': true,
              'order_uuid': billId,
              'table_id': 1,
              'table_session_uuid': seatId,
              'seating_status': 'closed',
              'merged': false,
              'rounds': [
                {
                  'id': 20,
                  'round_no': 1,
                  'same_seating': true,
                  'entered_by': 'staff',
                  'status': 'accepted',
                  'needs_review': false,
                  'client_request_id': requestId,
                  'lines': [
                    {
                      'order_item_id': 100,
                      'product_id': 7,
                      'qty': shape == 'wrong-accepted-lines' ? 3 : 2,
                      'notes': 'Keep Exactly',
                      'addon_ids': [],
                    },
                  ],
                },
                if (shape != 'held-absent')
                  {
                    'id': 21,
                    'round_no': 2,
                    'same_seating': true,
                    'entered_by': 'staff',
                    'status': shape == 'server-pending'
                        ? 'pending_confirmation'
                        : 'rejected',
                    'needs_review': true,
                    'client_request_id': rejectedId,
                    'lines': [],
                  },
              ],
            },
        };
        final okay = [
          'rejected',
          'held-rejected',
          'held-absent',
        ].contains(shape);
        expect(
          await h.store.retireClosed(
            local,
            bill: bill,
            table: {
              'table': {'id': 1},
              'occupied': false,
              'orphaned': false,
              'seating': null,
              'bill': null,
            },
          ),
          okay,
        );
        expect(await h.db.query('local_table_rounds'), ledger);
        if (okay) {
          expect(await h.db.query('dining_tables'), isEmpty);
          final archived =
              jsonDecode(
                    (await h.db.query(
                          'draft_recovery_closed_archive',
                        )).single['local_json']
                        as String,
                  )
                  as Map;
          expect(archived['rounds'], ledger);
          expect(h.outbox, hasLength(2));
        } else {
          expect(await h.db.query('dining_tables'), originals);
          expect(await h.db.query('draft_recovery_closed_archive'), isEmpty);
        }
      },
    );
  }
}
