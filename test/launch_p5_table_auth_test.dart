import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/approval_proof.dart';
import 'package:pos_machine/core/authorization.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 't65_adjustment_journal_test.dart' show AdjustmentServer;

/// LAUNCH-P5 C3 — a table adjust carries its authorization block, signed
/// over the request's seating_key (and, for a fixed discount, its amount),
/// beside the price-free intent; the old `authorized_by` text is the real
/// name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  final vector =
      ((jsonDecode(
                        File(
                          'test/fixtures/approval_proof_goldens.json',
                        ).readAsStringSync(),
                      )
                      as Map)['vectors']
                  as List)
              .first
          as Map<String, dynamic>;

  test(
    'an approved fixed table discount is signed over the seating key',
    () async {
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      addTearDown(db.close);
      final server = AdjustmentServer()..db = db;
      final c = DineInController(
        ApiDineInGateway(
          PosApiService(tokenGetter: () => 'fixture', dio: server.dio()),
          () => 'scope',
        ),
        SqliteDineInStore(db, 'scope'),
        1,
        staffId: 7,
      );
      addTearDown(c.dispose);
      await c.start();
      final grant = ApprovalGrant(
        approverStaffId: 42,
        name: 'Mona',
        approvedAt: DateTime.parse(vector['approved_at'] as String),
        method: 'offline',
        key: hexToBytes(vector['k_hex'] as String),
      );
      final gate = ActionAuthorization.approval(
        action: 'discount.manual',
        actorStaffId: 7,
        actorName: 'Cashier',
        grant: grant,
        deviceUuid: vector['device_uuid'] as String,
      );
      await c.adjust(
        (_) async => {
          'kind': 'discount',
          'mode': 'fixed',
          'amount_baisas': 300,
          'label': 'Friend',
          'gate': gate,
        },
      );
      final request = server.requests.single;
      // The intent stays price-free and gate-free.
      expect((request['adjustment'] as Map).containsKey('gate'), isFalse);
      expect(request['auth_v'], 1);
      final block = request['authorization'] as Map;
      final seating = request['seating_key'] as String;
      expect(block['action'], 'discount.manual');
      expect(block['mode'], 'approval');
      expect(block['approver_staff_id'], 42);
      expect(block['subject_uuid'], seating);
      expect(block['amount_baisas'], 300);
      // LAUNCH-P5 fix order 1 (F3) — one proof per request: ref = its id.
      expect(block['ref'], request['client_request_id']);
      expect(
        block['proof'],
        approvalProof(
          hexToBytes(vector['k_hex'] as String),
          approvalCanonical(
            action: 'discount.manual',
            deviceUuid: vector['device_uuid'] as String,
            approverStaffId: 42,
            approvedAt: vector['approved_at'] as String,
            subjectUuid: seating,
            amountBaisas: 300,
            ref: request['client_request_id'] as String,
          ),
        ),
      );
      expect(grant.canSign, isFalse, reason: 'the key is wiped once signed');
    },
  );
}
