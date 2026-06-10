import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/services/expense_restock_payload.dart';

String Function() _seqUuid() {
  var n = 0;
  return () => 'uuid-${n++}';
}

void main() {
  final at = DateTime.utc(2026, 6, 8, 9);

  group('expense.log payload', () {
    test('carries category + amount (baisas) + staff + note', () {
      final event = buildExpenseLogEvent(
        category: 'utilities',
        amountBaisas: 5000,
        staffId: 7,
        note: 'water bill',
        now: at,
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'expense.log');
      expect(event['client_event_id'], 'uuid-0');
      expect(event['client_timestamp'], '2026-06-08T09:00:00.000Z');
      final p = event['payload'] as Map<String, dynamic>;
      expect(p['category'], 'utilities');
      expect(p['amount_baisas'], 5000);
      expect(p['staff_id'], 7);
      expect(p['note'], 'water bill');
    });

    test('omits staff_id / note / logged_at when not provided', () {
      final event = buildExpenseLogEvent(
        category: 'other',
        amountBaisas: 1000,
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      expect(p.containsKey('staff_id'), isFalse);
      expect(p.containsKey('note'), isFalse);
      expect(p.containsKey('logged_at'), isFalse);
      expect(p['category'], 'other');
      expect(p['amount_baisas'], 1000);
    });

    test('an empty note is dropped, logged_at can be overridden', () {
      final logged = DateTime.utc(2026, 6, 8, 7, 30);
      final event = buildExpenseLogEvent(
        category: 'supplies',
        amountBaisas: 2500,
        note: '',
        loggedAt: logged,
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      expect(p.containsKey('note'), isFalse);
      expect(p['logged_at'], '2026-06-08T07:30:00.000Z');
    });

    test('the five categories match the server enum', () {
      expect(expenseCategories,
          ['utilities', 'supplies', 'maintenance', 'salaries', 'other']);
    });
  });

  group('restock.request payload', () {
    test('carries the lines (ingredient_id + quantity) + note', () {
      final event = buildRestockRequestEvent(
        lines: const [
          RestockRequestLineInput(ingredientId: 1, quantity: 5),
          RestockRequestLineInput(ingredientId: 2, quantity: 2.5),
        ],
        note: 'low on milk',
        now: at,
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'restock.request');
      expect(event['client_event_id'], 'uuid-0');
      final p = event['payload'] as Map<String, dynamic>;
      final lines = (p['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.length, 2);
      expect(lines[0]['ingredient_id'], 1);
      expect(lines[0]['quantity'], 5);
      expect(lines[1]['ingredient_id'], 2);
      expect(lines[1]['quantity'], 2.5);
      expect(p['note'], 'low on milk');
    });

    test('merges duplicate ingredient lines (server rejects repeats)', () {
      final event = buildRestockRequestEvent(
        lines: const [
          RestockRequestLineInput(ingredientId: 1, quantity: 5),
          RestockRequestLineInput(ingredientId: 1, quantity: 3),
          RestockRequestLineInput(ingredientId: 2, quantity: 1),
        ],
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      final lines = (p['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.length, 2);
      final byId = {for (final l in lines) l['ingredient_id']: l['quantity']};
      expect(byId[1], 8); // 5 + 3 merged
      expect(byId[2], 1);
    });

    test('drops non-positive quantities', () {
      final event = buildRestockRequestEvent(
        lines: const [
          RestockRequestLineInput(ingredientId: 1, quantity: 0),
          RestockRequestLineInput(ingredientId: 2, quantity: -4),
          RestockRequestLineInput(ingredientId: 3, quantity: 2),
        ],
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      final lines = (p['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.length, 1);
      expect(lines.first['ingredient_id'], 3);
      expect(lines.first['quantity'], 2);
    });

    test('omits note when not provided', () {
      final event = buildRestockRequestEvent(
        lines: const [RestockRequestLineInput(ingredientId: 1, quantity: 1)],
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      expect(p.containsKey('note'), isFalse);
      expect(p.containsKey('requested_at'), isFalse);
    });
  });

  group('stock.count payload (Phase A)', () {
    test('carries pieces / units lines + staff + note', () {
      final event = buildStockCountEvent(
        lines: const [
          StockCountLineInput(ingredientId: 1, countedPieces: 6),
          StockCountLineInput(ingredientId: 2, countedUnits: 4.5),
        ],
        staffId: 7,
        note: 'evening close',
        now: at,
        newUuid: _seqUuid(),
      );

      expect(event['event_type'], 'stock.count');
      expect(event['client_event_id'], 'uuid-0');
      final p = event['payload'] as Map<String, dynamic>;
      final lines = (p['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines, hasLength(2));
      expect(lines[0]['ingredient_id'], 1);
      expect(lines[0]['counted_pieces'], 6);
      expect(lines[0].containsKey('counted_units'), isFalse);
      expect(lines[1]['ingredient_id'], 2);
      expect(lines[1]['counted_units'], 4.5);
      expect(p['staff_id'], 7);
      expect(p['note'], 'evening close');
    });

    test('zero is a valid count; negatives are dropped; last duplicate wins', () {
      final event = buildStockCountEvent(
        lines: const [
          StockCountLineInput(ingredientId: 1, countedPieces: 5),
          StockCountLineInput(ingredientId: 1, countedPieces: 0),
          StockCountLineInput(ingredientId: 2, countedUnits: -1),
        ],
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      final lines = (p['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines, hasLength(1));
      expect(lines[0]['ingredient_id'], 1);
      expect(lines[0]['counted_pieces'], 0);
      expect(p.containsKey('staff_id'), isFalse);
      expect(p.containsKey('note'), isFalse);
      expect(p.containsKey('counted_at'), isFalse);
    });

    test('counted_at can be set explicitly (UTC ISO8601)', () {
      final counted = DateTime.utc(2026, 6, 8, 22, 15);
      final event = buildStockCountEvent(
        lines: const [StockCountLineInput(ingredientId: 3, countedUnits: 12)],
        countedAt: counted,
        now: at,
        newUuid: _seqUuid(),
      );
      final p = event['payload'] as Map<String, dynamic>;
      expect(p['counted_at'], '2026-06-08T22:15:00.000Z');
    });
  });
}
