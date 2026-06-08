import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/services/shift_payload.dart';

String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

void main() {
  group('shift payload', () {
    final at = DateTime.utc(2026, 6, 8, 9);

    test('shift.open carries staff + opening float (baisas)', () {
      final event = buildShiftOpenEvent(
        shiftUuid: 'shift-1',
        openingCashBaisas: 10000,
        staffId: 7,
        now: at,
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'shift.open');
      expect(event['client_event_id'], 'uuid-0');
      final p = event['payload'] as Map<String, dynamic>;
      expect(p['uuid'], 'shift-1');
      expect(p['staff_id'], 7);
      expect(p['opening_cash_baisas'], 10000);
      expect(p['opened_at'], '2026-06-08T09:00:00.000Z');
    });

    test('shift.open opened_at can be overridden', () {
      final opened = DateTime.utc(2026, 6, 8, 7, 30);
      final event = buildShiftOpenEvent(
        shiftUuid: 'shift-1',
        openingCashBaisas: 0,
        staffId: 1,
        openedAt: opened,
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      expect(p['opened_at'], '2026-06-08T07:30:00.000Z');
    });

    test('shift.close references the open shift uuid + counted cash', () {
      final event = buildShiftCloseEvent(
        shiftUuid: 'shift-1',
        closingCashBaisas: 12500,
        now: at,
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'shift.close');
      final p = event['payload'] as Map<String, dynamic>;
      expect(p['shift_uuid'], 'shift-1');
      expect(p['closing_cash_baisas'], 12500);
      expect(p['closed_at'], '2026-06-08T09:00:00.000Z');
    });

    test('ShiftCloseResult parses expected + variance (short drawer)', () {
      final r = ShiftCloseResult.fromResult(const {
        'status': 'closed',
        'expected_cash_baisas': 13000,
        'variance_baisas': -500,
      });
      expect(r.expectedCashBaisas, 13000);
      expect(r.varianceBaisas, -500);
    });

    test('ShiftCloseResult defaults missing fields to zero', () {
      final r = ShiftCloseResult.fromResult(const {});
      expect(r.expectedCashBaisas, 0);
      expect(r.varianceBaisas, 0);
    });
  });
}
