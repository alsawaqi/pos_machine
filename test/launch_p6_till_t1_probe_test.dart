import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart'
    show TableCartPayRouter, tableBillNeedsSheet, dineInDetailHasTabletRound;

/// LAUNCH-P6 till fix order 1, T-1 (HIGH) — a till-opened table bill with a
/// sent tablet round must be paid from the server sheet (the full server
/// total), never from the till's local cart (which lacks the tablet lines).
///
/// The probe: a board row of a bill the till opened (`source: main_pos`),
/// one staff round and one sent tablet round. A tablet round has no QR
/// session, so the server counts it as a staff round; with F-20 the board
/// also carries `tablet_rounds`.
Map<String, dynamic> boardRow({int? tabletRounds}) => {
  'table_id': 3,
  'table_label': '3',
  'seating': {
    'uuid': 'seat-3',
    'status': 'open',
    'origin': 'main_pos',
    'pending_rounds': <Object>[],
  },
  'bill': {
    'order_uuid': 'bill-3',
    'status': 'open',
    'source': 'main_pos',
    'grand_total_baisas': 5000,
    'customer_rounds': 0,
    'staff_rounds': 2,
    'tablet_rounds': ?tabletRounds,
  },
};

Map<String, dynamic> detail({required String enteredBy}) => {
  'table': {'id': 3, 'label': '3'},
  'occupied': true,
  'orphaned': false,
  'seating': {'uuid': 'seat-3', 'table_id': 3},
  'bill': {
    'uuid': 'bill-3',
    'source': 'main_pos',
    'grand_total_baisas': 5000,
    'items': <Object>[],
  },
  'rounds': [
    {
      'id': 1,
      'round_no': 1,
      'status': 'accepted',
      'entered_by': 'staff',
      'priced_lines': <Object>[],
    },
    {
      'id': 2,
      'round_no': 2,
      'status': 'accepted',
      'entered_by': enteredBy,
      'priced_lines': <Object>[],
    },
  ],
};

Future<List<String>> route(Map<String, dynamic> row) async {
  final routes = <String>[];
  await TableCartPayRouter().route(
    mode: 'live',
    tableId: 3,
    contextKey: 'k',
    board: const RemoteTableSnapshot(),
    fetchBoard: () async => [row],
    isCurrent: () => true,
    changed: () {},
    openSheet: () async => routes.add('sheet'),
    openLocal: () async => routes.add('local'),
  );
  return routes;
}

void main() {
  test('T-1: a till bill with a tablet round (board tablet_rounds) pays '
      'from the server sheet', () async {
    final row = RemoteTableState.fromBoard(
      boardRow(tabletRounds: 1),
      DateTime.utc(2026, 10, 6),
    );
    expect(tableBillNeedsSheet('live', row), isTrue);
    expect(await route(boardRow(tabletRounds: 1)), ['sheet']);
  });

  test('T-1: no tablet round (or an older server without the field) keeps '
      'the local tender', () async {
    expect(await route(boardRow()), ['local']);
    expect(await route(boardRow(tabletRounds: 0)), ['local']);
  });

  test('T-1: the F-20 board shape (customer_rounds includes tablet rounds) '
      'and the detail bill count', () async {
    final row = boardRow(tabletRounds: 1);
    (row['bill'] as Map)
      ..['customer_rounds'] = 1
      ..['staff_rounds'] = 1;
    expect(await route(row), ['sheet']);
    final json = detail(enteredBy: 'staff');
    (json['bill'] as Map)['tablet_rounds'] = 1;
    expect(dineInDetailHasTabletRound(DineInDetail(json)), isTrue);
  });

  test('T-1: the table detail names a tablet round (entered_by tablet)', () {
    expect(
      dineInDetailHasTabletRound(DineInDetail(detail(enteredBy: 'tablet'))),
      isTrue,
    );
    expect(
      dineInDetailHasTabletRound(DineInDetail(detail(enteredBy: 'staff'))),
      isFalse,
    );
  });
}
