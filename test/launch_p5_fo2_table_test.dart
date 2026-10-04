import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/permissions.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_gateway.dart';
import 'package:pos_machine/dine_in/dine_in_store.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 't65_adjustment_journal_test.dart' show AdjustmentServer;

/// LAUNCH-P5 fix order 2 — T7: a fixed table discount is checked against
/// the bill's adjustment basis (as the server does, 1-baisa tolerance), and
/// an \`approval_required\` refusal of an adjustment opens the approval sheet
/// once (the same choice, as a new request).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('the server formula over the adjustment basis', () {
    // Tax-inclusive bill: subtotal 10.000, basis 8.700; a fixed 1.000.
    final onBasis = tableDiscountPercentOf(
      amountBaisas: 1000,
      basisBaisas: 8700,
    );
    expect(onBasis, closeTo(11.48, 0.01));
    final cashier = StaffPermissions(PositionPermissions.defaults, 'cashier');
    expect(cashier.can('discount.manual', amountPercent: onBasis), isFalse);
    // The old check (against the subtotal) said 10 % and let it through.
    expect(
      cashier.can(
        'discount.manual',
        amountPercent: discountPercentOf(discountAmount: 1, subtotal: 10),
      ),
      isTrue,
    );
    // The 1-baisa tolerance: exactly 10 % of 10.000 is 1.000.
    expect(tableDiscountPercentOf(amountBaisas: 1001, basisBaisas: 10000), 10);
    expect(tableDiscountPercentOf(amountBaisas: 0, basisBaisas: 0), 0);
  });

  test('the table discount dialog checks the basis', () {
    final screen = File('lib/screens/staff_pos_screen.dart').readAsStringSync();
    expect(
      RegExp(
        r"tableDiscountPercentOf\(\s*amountBaisas: \(value\.value \* 1000\)\.round\(\),\s*basisBaisas:\s*\(\(bill\['adjustment_basis_baisas'\]",
      ).hasMatch(screen),
      isTrue,
    );
    expect(
      screen,
      contains('pickAdjustmentWithApproval: _pickTableAdjustmentWithApproval,'),
    );
  });

  group('approval_required on an adjustment', () {
    late Database db;
    late AdjustmentServer server;
    late DineInController c;
    var refuse = 0;
    final sent = <Map<String, dynamic>>[];

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          singleInstance: false,
          version: 2,
          onCreate: (db, _) => SqliteDineInStore.createSchema(db),
        ),
      );
      server = AdjustmentServer()..db = db;
      refuse = 0;
      sent.clear();
      final inner = server.dio();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (o, h) async {
              if (o.path.endsWith('/adjust')) {
                sent.add(
                  jsonDecode(jsonEncode(o.data)) as Map<String, dynamic>,
                );
                if (refuse > 0) {
                  refuse--;
                  h.resolve(
                    Response(
                      requestOptions: o,
                      statusCode: 403,
                      data: {
                        'data': {'reason': 'not_ticked'},
                        'errors': [
                          {
                            'code': 'approval_required',
                            'message': 'A manager must approve this.',
                          },
                        ],
                      },
                    ),
                  );
                  return;
                }
              }
              try {
                h.resolve(await inner.fetch<dynamic>(o));
              } on DioException catch (e) {
                h.reject(e);
              }
            },
          ),
        );
      c = DineInController(
        ApiDineInGateway(
          PosApiService(tokenGetter: () => 'fixture', dio: dio),
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

    Map<String, dynamic> fixed({String label = 'Friend'}) => {
      'kind': 'discount',
      'mode': 'fixed',
      'amount_baisas': 300,
      'label': label,
    };

    test('the sheet is asked once and the choice is sent again', () async {
      refuse = 1;
      var sheets = 0;
      final ok = await c.adjust(
        (_) async => fixed(),
        approvalPick: (_) async {
          sheets++;
          return fixed(label: 'Friend (approved)');
        },
      );
      expect(ok, isTrue);
      expect(sheets, 1);
      expect(sent, hasLength(2));
      expect(
        sent[1]['client_request_id'],
        isNot(sent[0]['client_request_id']),
        reason: 'a new request, never a replay of the refused one',
      );
      expect((sent[1]['adjustment'] as Map)['label'], 'Friend (approved)');
    });

    test('refused again: shown, not looped', () async {
      refuse = 2;
      var sheets = 0;
      final ok = await c.adjust(
        (_) async => fixed(),
        approvalPick: (_) async {
          sheets++;
          return fixed();
        },
      );
      expect(ok, isFalse);
      expect(sheets, 1);
      expect(c.notice, 'adjust_refused:approval_required');
    });

    test('no approval picker: the refusal is shown as before', () async {
      refuse = 1;
      expect(await c.adjust((_) async => fixed()), isFalse);
      expect(sent, hasLength(1));
      expect(c.notice, 'adjust_refused:approval_required');
    });
  });
}
