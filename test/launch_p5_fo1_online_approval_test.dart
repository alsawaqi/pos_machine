import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approval_proof.dart';
import 'package:pos_machine/core/auth_wire.dart';
import 'package:pos_machine/core/manager_auth.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/data/order_sync_repository.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_order_storage.dart';
import 't65_adjustment_journal_test.dart' show AdjustmentServer, bill, seat;
import 'workspace_machine_harness.dart';

/// LAUNCH-P5 fix order 1 — F3 [WIRE] no replay on online actions, and F4
/// exact proofs: a table adjust, a table line cancel and a sold-out switch
/// each carry one proof for their own request (ref = the request's
/// client_request_id) over exactly the §6 subject and amount; a "clear" of
/// several lines signs each line's request with the same in-memory key; a
/// refused (or expired) approval is final for that request, so the next try
/// asks again.
final _vector =
    ((jsonDecode(
                      File(
                        'test/fixtures/approval_proof_goldens.json',
                      ).readAsStringSync(),
                    )
                    as Map)['vectors']
                as List)
            .first
        as Map<String, dynamic>;

ApprovalGrant _grant() => ApprovalGrant(
  approverStaffId: 42,
  name: 'Mona',
  approvedAt: DateTime.now().toUtc(),
  method: 'offline',
  key: hexToBytes(_vector['k_hex'] as String),
);

ActionAuthorization _gate(String action, ApprovalGrant grant) =>
    ActionAuthorization.approval(
      action: action,
      actorStaffId: 7,
      actorName: 'Cashier',
      grant: grant,
      deviceUuid: _vector['device_uuid'] as String,
    );

String _proof({
  required String action,
  required Map block,
  String? subject,
  int? amount,
  String? ref,
}) => approvalProof(
  hexToBytes(_vector['k_hex'] as String),
  approvalCanonical(
    action: action,
    deviceUuid: _vector['device_uuid'] as String,
    approverStaffId: 42,
    approvedAt: block['approved_at'] as String,
    subjectUuid: subject,
    amountBaisas: amount,
    ref: ref,
  ),
);

/// The table server of the T6.5 suite plus the line-cancel endpoint, and a
/// switch that refuses the next write with a 403 approval code.
class _TableServer {
  _TableServer(this.db);
  final Database db;
  final base = AdjustmentServer();
  final cancels = <Map<String, dynamic>>[];

  /// The `X-Staff-Token` of every write (attach the server after the
  /// client's own interceptors to see it: [dio] with `into`).
  final tokens = <Object?>[];
  String? refuseWith;

  /// The server's `data.bill.adjustment_basis_baisas` (deliberately not
  /// the 5.000 OMR subtotal of the T6.5 bill).
  int basis = 4800;

  Dio dio({Dio? into}) {
    base.db = db;
    final adjust = base.dio();
    return (into ?? Dio())
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) async {
            if (!o.path.endsWith('/detail')) {
              tokens.add(o.headers['X-Staff-Token']);
            }
            final refusal = refuseWith;
            if (refusal != null && !o.path.endsWith('/detail')) {
              refuseWith = null;
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 403,
                  data: {
                    'data': null,
                    'errors': [
                      {'code': refusal, 'message': 'Approve again.'},
                    ],
                  },
                ),
              );
              return;
            }
            if (o.path.endsWith('/detail')) {
              final detail = base.detail();
              (detail['bill'] as Map)['adjustment_basis_baisas'] = basis;
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {'data': detail},
                ),
              );
              return;
            }
            if (o.path.endsWith('/cancel-line')) {
              final p = Map<String, dynamic>.from(o.data as Map);
              cancels.add(jsonDecode(jsonEncode(p)) as Map<String, dynamic>);
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'data': {
                      'outcome': 'cancelled',
                      'table_session_uuid': seat,
                      'winner_table_session_uuid': null,
                      'seating_key': p['seating_key'],
                      'table_id': p['table_id'],
                      'order_uuid': bill,
                      'cancelled_qty': p['qty'],
                      'grand_total_baisas': 4000,
                    },
                  },
                ),
              );
              return;
            }
            try {
              final response = await adjust.fetch<dynamic>(o);
              h.resolve(response);
            } on DioException catch (e) {
              h.reject(e);
            }
          },
        ),
      );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  savedRequestRules();

  group('table adjust', () {
    late Database db;
    late _TableServer server;
    late DineInController c;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      server = _TableServer(db);
      c = DineInController(
        ApiDineInGateway(
          PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
          () => 'scope',
        ),
        SqliteDineInStore(db, 'scope'),
        1,
        staffId: 7,
      );
      await c.start();
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test(
      'a fixed discount: ref = its client_request_id, one exact proof',
      () async {
        final grant = _grant();
        await c.adjust(
          (_) async => {
            'kind': 'discount',
            'mode': 'fixed',
            'amount_baisas': 300,
            'label': 'Friend',
            'gate': _gate('discount.manual', grant),
          },
        );
        final request = server.base.requests.single;
        final block = request['authorization'] as Map;
        expect(block['ref'], request['client_request_id']);
        expect(
          block['proof'],
          _proof(
            action: 'discount.manual',
            block: block,
            subject: request['seating_key'] as String,
            amount: 300,
            ref: request['client_request_id'] as String,
          ),
        );
      },
    );

    test(
      'a percent discount is signed over the server basis × percent',
      () async {
        final grant = _grant();
        await c.adjust(
          (_) async => {
            'kind': 'discount',
            'mode': 'percent',
            'percent_bp': 1250,
            'label': 'Regular',
            'gate': _gate('discount.manual', grant),
          },
        );
        final request = server.base.requests.single;
        final block = request['authorization'] as Map;
        // The server's basis 4.800 OMR × 12.5 % = 600 (not the 5.000 subtotal).
        expect(block['amount_baisas'], 600);
        expect(
          block['proof'],
          _proof(
            action: 'discount.manual',
            block: block,
            subject: request['seating_key'] as String,
            amount: 600,
            ref: request['client_request_id'] as String,
          ),
        );
        // The private rule hint never reaches the wire.
        expect((request['adjustment'] as Map).keys, isNot(contains('gate')));
      },
    );

    test('a 403 approval refusal is final: the next try asks again', () async {
      server.refuseWith = 'approval_invalid';
      final ok = await c.adjust(
        (_) async => {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 300,
          'label': 'Friend',
          'gate': _gate('discount.manual', _grant()),
        },
      );
      expect(ok, isFalse);
      expect(c.notice, 'adjust_refused:approval_invalid');
      expect(c.pending, isNull, reason: 'nothing kept to replay');
      expect(await SqliteDineInStore(db, 'scope').load(), isNull);
    });
  });

  group('table line cancel', () {
    late Database db;
    late _TableServer server;
    late DineInController c;
    Map<String, dynamic> line() => Map<String, dynamic>.from(
      ((c.detail!.bill!['items'] as List).first as Map),
    )..['line_total_baisas'] = 3000;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      server = _TableServer(db);
      c = DineInController(
        ApiDineInGateway(
          PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
          () => 'scope',
        ),
        SqliteDineInStore(db, 'scope'),
        1,
        staffId: 7,
      );
      await c.start();
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test(
      'a clear of two lines: one request and one proof per line, same K',
      () async {
        final grant = _grant();
        final approval = {
          'prepared': false,
          'authorized_by': 'Mona',
          'reason': 'guest left',
          'gate': _gate('table.cancel_line', grant),
        };
        expect(
          await c.cancelLine(line(), 1, approve: () async => approval),
          isTrue,
        );
        // The approval stays open for the next line of the clear.
        expect(grant.canSign, isTrue);
        expect(
          await c.cancelLine(line(), 1, approve: () async => approval),
          isTrue,
        );
        expect(server.cancels, hasLength(2));
        final refs = <String>{};
        for (final request in server.cancels) {
          final block = request['authorization'] as Map;
          expect(block['ref'], request['client_request_id']);
          refs.add(block['ref'] as String);
          expect(
            block['proof'],
            _proof(
              action: 'table.cancel_line',
              block: block,
              subject: request['seating_key'] as String,
              ref: request['client_request_id'] as String,
            ),
          );
          expect(block.containsKey('amount_baisas'), isFalse);
        }
        expect(refs, hasLength(2));
        expect(
          (server.cancels[0]['authorization'] as Map)['proof'],
          isNot((server.cancels[1]['authorization'] as Map)['proof']),
        );
      },
    );

    test('a 403 approval refusal is final: nothing kept to replay', () async {
      server.refuseWith = 'approval_invalid';
      final ok = await c.cancelLine(
        line(),
        1,
        approve: () async => {
          'prepared': false,
          'authorized_by': 'Mona',
          'reason': 'guest left',
          'gate': _gate('table.cancel_line', _grant()),
        },
      );
      expect(ok, isFalse);
      expect(c.notice, 'cancel_refused:approval_invalid');
      expect(c.pending, isNull);
    });
  });

  group('the proof amount of a table discount', () {
    DineInDetail detail({int? basis}) => DineInDetail({
      'table': {'id': 1, 'label': 'T1'},
      'occupied': true,
      'orphaned': false,
      'seating': {'uuid': seat, 'table_id': 1, 'status': 'open'},
      'bill': {
        'uuid': bill,
        'grand_total_baisas': 6300,
        'subtotal_baisas': 6000,
        'items': <Object>[],
        'adjustment_basis_baisas': ?basis,
      },
      'rounds': [
        {
          'id': 1,
          'round_no': 1,
          'entered_by': 'staff',
          'status': 'accepted',
          'priced_lines': <Object>[],
          'subtotal_baisas': 6000,
          'tax_baisas': 300,
          'total_baisas': 6300,
        },
      ],
    });

    test('percent and percent rule use the server\'s adjustment basis', () {
      // The basis (not the subtotal, not the rounds) decides.
      final d = detail(basis: 5900);
      expect(
        tableAdjustProofAmount(d, {
          'kind': 'discount',
          'mode': 'percent',
          'percent_bp': 1250,
        }),
        738, // 737.5 rounds half away from zero, as the server does
      );
      expect(
        tableAdjustProofAmount(
          d,
          {'kind': 'discount', 'mode': 'rule', 'discount_id': 3},
          rule: {'type': 'percent', 'value': 15.0},
        ),
        885,
      );
    });

    test('fixed amounts as sent; nothing for the others', () {
      final d = detail(basis: 5900);
      expect(
        tableAdjustProofAmount(
          d,
          {'kind': 'discount', 'mode': 'rule', 'discount_id': 3},
          rule: {'type': 'fixed', 'value': 1.25},
        ),
        1250,
      );
      expect(
        tableAdjustProofAmount(d, {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 400,
        }),
        400,
      );
      for (final intent in [
        {'kind': 'comp', 'mode': 'apply'},
        {'kind': 'loyalty', 'mode': 'redeem'},
      ]) {
        expect(tableAdjustProofAmount(d, intent), isNull);
      }
    });

    test('no basis from the server: the till does not compute one', () {
      expect(
        tableAdjustProofAmount(detail(), {
          'kind': 'discount',
          'mode': 'percent',
          'percent_bp': 1250,
        }),
        isNull,
      );
    });
  });

  test(
    'a cancel_bill refused for its approval is final, not retried forever',
    () async {
      final api = _BillApi();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = OrderSyncRepository(api, db)
        ..cancellationRoute = (_) async => seat;
      final acks = <Map<String, dynamic>>[];
      repo.addAckListener((row, events, results) async => acks.addAll(results));
      final event = {
        'client_event_id': 'cb-1',
        'event_type': 'table.session.cancel_bill',
        'client_timestamp': '2026-10-04T06:00:00.000Z',
        'payload': {'client_request_id': 'cb-1', 'seating_key': 's-1'},
      };
      await db.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: 'cancel-bill:cb-1',
          eventsJson: jsonEncode([event]),
          createdAt: DateTime.utc(2026, 10, 4, 6),
        ),
      );
      await repo.flush();
      expect(api.calls, 1);
      expect(acks.single['status'], 'failed');
      expect(
        (acks.single['result'] as Map)['refusal_code'],
        'approval_invalid',
      );
      final row = await db.getOutbox('cancel-bill:cb-1');
      expect(row!.syncedAt, isNotNull, reason: 'settled as a final refusal');
    },
  );

  group('sold out', () {
    const latte = Product(
      id: '10',
      name: 'Latte',
      category: 'Coffee',
      price: 1.5,
    );
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      messenger.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      messenger.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    testWidgets('one proof per request, over the product uuid', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _SoldOutApi();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final harness = await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        api: api,
        database: db,
        allowAllTicks: false,
        extraPrefs: {
          'p5_product_uuids_json': jsonEncode({'10': 'prod-uuid-10'}),
        },
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [latte],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      Future<void> switchWithPin() async {
        await tester.longPress(find.text('Latte').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('sold-out-switch-confirm')));
        await tester.pumpAndSettle();
        final sheet = find.byType(ManagerApprovalSheet);
        for (final d in (_vector['pin'] as String).split('')) {
          await tester.tap(find.descendant(of: sheet, matching: find.text(d)));
          await tester.pump();
        }
        final before = api.switches.length;
        await tester.tap(find.byKey(const ValueKey('manager-approval-verify')));
        for (var i = 0; i < 200 && api.switches.length == before; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
      }

      await switchWithPin();
      await switchWithPin();
      expect(api.switches, hasLength(2));
      final device = currentDeviceUuid(harness.preferences);
      final ids = <Object?>{};
      for (final call in api.switches) {
        final block = call['authorization'] as Map;
        final requestId = call['client_request_id'] as String;
        ids.add(requestId);
        expect(block['ref'], requestId);
        expect(block['subject_uuid'], 'prod-uuid-10');
        expect(block.containsKey('amount_baisas'), isFalse);
        expect(
          block['proof'],
          approvalProof(
            hexToBytes(_vector['k_hex'] as String),
            approvalCanonical(
              action: 'sold_out.toggle',
              deviceUuid: device,
              approverStaffId: 3,
              approvedAt: block['approved_at'] as String,
              subjectUuid: 'prod-uuid-10',
              ref: requestId,
            ),
          ),
        );
      }
      expect(ids, hasLength(2), reason: 'a new request id (and proof) each');
      await disposeWorkspaceMachine(tester);
    });
  });
}

/// LAUNCH-P5 fix order 1 — rules from the handheld build, applied to the
/// till: a saved request keeps its maker's token for every retry, and only
/// the logged-in person's own live request can sign them out.
void savedRequestRules() {
  group('saved requests keep their maker', () {
    late Database db;
    late _TableServer server;
    late PosApiService api;
    var signedOut = <String?>[];

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      server = _TableServer(db);
      signedOut = <String?>[];
      final dio = Dio();
      api = PosApiService(
        tokenGetter: () => 'fixture',
        dio: dio,
        onStaffUnverified: signedOut.add,
      );
      server.dio(into: dio);
      StaffTokenHolder.set(7, 'tok-7');
    });
    tearDown(() async {
      StaffTokenHolder.clear();
      await db.close();
    });

    Future<DineInController> controller(int staffId) async {
      final c = DineInController(
        ApiDineInGateway(api, () => 'scope'),
        SqliteDineInStore(db, 'scope'),
        1,
        staffId: staffId,
      );
      await c.start();
      return c;
    }

    Future<bool> adjust(DineInController c) => c.adjust(
      (_) async => {
        'kind': 'discount',
        'mode': 'fixed',
        'amount_baisas': 300,
        'label': 'Friend',
        'gate': _gate('discount.manual', _grant()),
      },
    );

    test(
      'a retry sends the maker\'s stored token, whoever is logged in',
      () async {
        final made = await controller(7);
        server.base.loseAck = true; // applied, but the reply is lost
        expect(await adjust(made), isFalse);
        expect(made.notice, 'uncertain');
        made.dispose();
        // Omar logs in on the till; the saved request comes back with its
        // maker's token from the journal.
        StaffTokenHolder.set(8, 'tok-8');
        final next = await controller(8);
        expect(next.pending?.staffToken, 'tok-7');
        expect(await next.retry(), isTrue);
        next.dispose();
        expect(server.tokens, ['tok-7', 'tok-7']);
        // Settled: the maker's token leaves with the request.
        expect(
          await db.query(
            'dine_in_drafts',
            where: 'scope LIKE ?',
            whereArgs: ['scope::maker:%'],
          ),
          isEmpty,
        );
      },
    );

    test(
      'staff_unverified on somebody else\'s saved request: kept, shown, nobody signed out',
      () async {
        final made = await controller(7);
        server.base.loseAck = true;
        await adjust(made);
        made.dispose();
        StaffTokenHolder.set(8, 'tok-8');
        final next = await controller(8);
        server.refuseWith = 'staff_unverified';
        expect(await next.retry(), isFalse);
        expect(next.notice, 'staff_unverified');
        expect(next.pending, isNotNull, reason: 'the request is kept');
        expect(signedOut, isEmpty, reason: 'Omar stays logged in');
        next.dispose();
      },
    );

    test(
      'staff_unverified on one\'s own live request signs them out',
      () async {
        final c = await controller(7);
        server.refuseWith = 'staff_unverified';
        expect(await adjust(c), isFalse);
        expect(server.tokens.single, 'tok-7');
        expect(signedOut, hasLength(1));
        expect(c.pending, isNotNull, reason: 'kept for the next login');
        c.dispose();
      },
    );

    test(
      'a request naming another staff member never carries this token',
      () async {
        final shiftDio = Dio();
        final headers = <Object?>[];
        final shiftApi = PosApiService(
          tokenGetter: () => 'fixture',
          dio: shiftDio,
        );
        shiftDio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) {
              headers.add(o.headers['X-Staff-Token']);
              h.resolve(
                Response(
                  requestOptions: o,
                  statusCode: 200,
                  data: {
                    'data': {'shift': null},
                    'errors': <Object>[],
                  },
                ),
              );
            },
          ),
        );
        await shiftApi.fetchCurrentShift(staffId: 9);
        await shiftApi.fetchCurrentShift(staffId: 7);
        await shiftApi.fetchCurrentShift();
        expect(headers, [null, 'tok-7', 'tok-7']);
      },
    );

    test('a queued cancel_bill is sent with its maker\'s token', () async {
      final bills = _BillApi();
      final outboxDb = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(outboxDb.close);
      final repo = OrderSyncRepository(bills, outboxDb)
        ..cancellationRoute = (_) async => seat;
      await outboxDb.enqueueOutbox(
        OrderOutboxCompanion.insert(
          orderUuid: 'cancel-bill:cb-2',
          eventsJson: jsonEncode([
            {
              'client_event_id': 'cb-2',
              'event_type': 'table.session.cancel_bill',
              'client_timestamp': '2026-10-04T06:00:00.000Z',
              'payload': {
                'client_request_id': 'cb-2',
                'seating_key': 's-2',
                'staff_id': 7,
                'staff_token': 'tok-7',
              },
            },
          ]),
          createdAt: DateTime.utc(2026, 10, 4, 6),
        ),
      );
      StaffTokenHolder.set(8, 'tok-8');
      await repo.flush();
      expect(bills.tokens, ['tok-7']);
    });
  });
}

class _BillApi implements PosApiService {
  int calls = 0;
  final tokens = <String?>[];

  @override
  Future<Map<String, dynamic>> dineInCancelBill(
    String uuid,
    Map<String, dynamic> payload, {
    String? staffToken,
  }) async {
    calls++;
    tokens.add(staffToken);
    throw ApiException(
      message: 'The approval could not be verified. Approve again.',
      statusCode: 403,
      code: 'approval_invalid',
      hasStructuredErrorCode: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected ${invocation.memberName}');
}

class _SoldOutApi implements PosApiService {
  final switches = <Map<String, Object?>>[];

  @override
  Future<List<Map<String, dynamic>>> fetchIncomingTransfers() async => [];

  @override
  Future<ApproverVerification?> verifyApprover(String pin) async =>
      pin == _vector['pin']
      ? ApproverVerification(
          staffId: 3,
          name: 'Mona',
          salt: _vector['salt_hex'] as String,
          iterations: _vector['iterations'] as int,
          check: _vector['check_hex'] as String,
        )
      : null;

  @override
  Future<void> setProductSoldOut(
    int productId, {
    required bool soldOut,
    required int staffId,
    Map<String, dynamic>? authorization,
    String? clientRequestId,
  }) async {
    switches.add({
      'product': productId,
      'sold_out': soldOut,
      'authorization': authorization,
      'client_request_id': clientRequestId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected network operation: ${invocation.memberName}',
  );
}
