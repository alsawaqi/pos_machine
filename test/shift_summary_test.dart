import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/shift_summary.dart';

/// Phase C6 — the Z-report: server-summary parsing, the device-local
/// fallback fold, and the printed layout contract.
void main() {
  group('ShiftSalesSummary.fromServerResult', () {
    test('parses the shift.close summary block', () {
      final s = ShiftSalesSummary.fromServerResult({
        'order_count': 2,
        'gross_sales_baisas': 5000,
        'discount_total_baisas': 500,
        'comp_total_baisas': 250,
        'tax_total_baisas': 0,
        'grand_total_baisas': 4250,
        'tenders': [
          {'method': 'cash', 'amount_baisas': 3000, 'count': 1},
          {'method': 'card', 'amount_baisas': 1250, 'count': 1},
        ],
        'void_count': 1,
        'void_total_baisas': 1500,
        'round_up_baisas': 100,
        'branch_expenses_baisas': 2000,
      });

      expect(s, isNotNull);
      expect(s!.source, 'server');
      expect(s.orderCount, 2);
      expect(s.grandBaisas, 4250);
      expect(s.tenders, hasLength(2));
      expect(s.tenders.first.method, 'cash');
      expect(s.voidTotalBaisas, 1500);
      expect(s.branchExpensesBaisas, 2000);
    });

    test('null in, null out (older API)', () {
      expect(ShiftSalesSummary.fromServerResult(null), isNull);
    });

    test('round-trips through toJson/fromJson for the reprint snapshot', () {
      final original = ShiftSalesSummary.fromServerResult({
        'order_count': 1,
        'gross_sales_baisas': 1000,
        'discount_total_baisas': 0,
        'comp_total_baisas': 0,
        'tax_total_baisas': 50,
        'grand_total_baisas': 1050,
        'tenders': [
          {'method': 'cash', 'amount_baisas': 1050, 'count': 1},
        ],
        'void_count': 0,
        'void_total_baisas': 0,
        'round_up_baisas': 0,
        'branch_expenses_baisas': 0,
      })!;

      final restored = ShiftSalesSummary.fromJson(original.toJson());
      expect(restored.grandBaisas, 1050);
      expect(restored.tenders.single.amountBaisas, 1050);
      expect(restored.source, 'server');
    });
  });

  group('buildLocalShiftSummary', () {
    OrderHistoryRecord record({
      required DateTime at,
      double total = 2.0,
      String paymentMethod = 'Cash',
      List<SplitPaymentRecord> splits = const [],
      bool roundUp = false,
      bool fromServer = false,
      List<OrderCancellationRecord> cancellations = const [],
    }) {
      final snapshot = OrderSnapshot.initial().copyWith(
        items: [
          {'id': '1', 'name': 'Item', 'qty': 1, 'lineTotal': total},
        ],
        rawSubtotal: total,
        subtotal: total,
        total: total,
        payableTotal: total,
        paymentMethod: paymentMethod,
        splitPayments: splits,
        charityRoundUpAccepted: roundUp,
        charityRoundUpAmount: roundUp ? 0.1 : 0,
        cancellations: cancellations,
      );
      return OrderHistoryRecord(
        id: 'r${at.millisecondsSinceEpoch}',
        orderNumber: 1,
        orderType: OrderType.quickOrder,
        createdAt: at,
        snapshot: snapshot,
        fromServer: fromServer,
      );
    }

    final openedAt = DateTime(2026, 6, 10, 8);
    final closedAt = DateTime(2026, 6, 10, 16);

    test('folds window sales by method, skips outside + server records', () {
      final summary = buildLocalShiftSummary(
        [
          record(at: DateTime(2026, 6, 10, 9), total: 2.0),
          record(
            at: DateTime(2026, 6, 10, 10),
            total: 3.0,
            paymentMethod: 'Credit Card',
            roundUp: true,
          ),
          // Outside the window — ignored.
          record(at: DateTime(2026, 6, 10, 7), total: 9.0),
          // Server record — not this device's log.
          record(at: DateTime(2026, 6, 10, 11), total: 9.0, fromServer: true),
        ],
        openedAt: openedAt,
        closedAt: closedAt,
      );

      expect(summary.source, 'local');
      expect(summary.orderCount, 2);
      expect(summary.grossBaisas, 5000);
      expect(summary.grandBaisas, 5000);
      expect(summary.roundUpBaisas, 100);
      final cash = summary.tenders.firstWhere((t) => t.method == 'cash');
      final card = summary.tenders.firstWhere((t) => t.method == 'card');
      expect(cash.amountBaisas, 2000);
      expect(card.amountBaisas, 3000);
    });

    test('explodes split tenders per guest at their base amount', () {
      final at = DateTime(2026, 6, 10, 12);
      final summary = buildLocalShiftSummary(
        [
          record(at: at, total: 6.0, splits: [
            SplitPaymentRecord(
              splitIndex: 1,
              splitCount: 2,
              paymentMethod: 'Cash',
              baseAmount: 3.0,
              charityRoundUpAccepted: false,
              charityRoundUpAmount: 0,
              paidAmount: 3.0,
              paidAt: at,
            ),
            SplitPaymentRecord(
              splitIndex: 2,
              splitCount: 2,
              paymentMethod: 'Credit Card',
              baseAmount: 3.0,
              charityRoundUpAccepted: true,
              charityRoundUpAmount: 0.05,
              paidAmount: 3.05,
              paidAt: at,
            ),
          ]),
        ],
        openedAt: openedAt,
        closedAt: closedAt,
      );

      expect(summary.tenders.firstWhere((t) => t.method == 'cash').amountBaisas, 3000);
      expect(summary.tenders.firstWhere((t) => t.method == 'card').amountBaisas, 3000);
      expect(summary.roundUpBaisas, 50);
    });

    test('a fully-canceled order counts as a void, not a sale', () {
      final at = DateTime(2026, 6, 10, 12);
      final summary = buildLocalShiftSummary(
        [
          record(at: at, total: 4.0, cancellations: [
            OrderCancellationRecord(
              id: 'c1',
              fullOrder: true,
              itemName: '',
              quantity: 0,
              amount: 4.0,
              canceledAt: at,
              authorizedBy: 'Manager',
            ),
          ]),
        ],
        openedAt: openedAt,
        closedAt: closedAt,
      );

      expect(summary.orderCount, 0);
      expect(summary.voidCount, 1);
      expect(summary.voidTotalBaisas, 4000);
      expect(summary.grandBaisas, 0);
    });
  });

  group('buildShiftSummaryLines', () {
    ShiftSummaryTicket ticket({bool isReprint = false, String source = 'server'}) {
      return ShiftSummaryTicket(
        deviceCode: 'POS-TEST-001',
        staffName: 'Sara',
        openedAt: DateTime(2026, 6, 10, 8),
        closedAt: DateTime(2026, 6, 10, 16),
        openingBaisas: 10000,
        expectedBaisas: 13000,
        countedBaisas: 12500,
        varianceBaisas: -500,
        isReprint: isReprint,
        summary: ShiftSalesSummary(
          orderCount: 2,
          grossBaisas: 5000,
          discountBaisas: 500,
          compBaisas: 0,
          taxBaisas: 0,
          grandBaisas: 4500,
          tenders: const [
            ShiftTenderLine(method: 'cash', amountBaisas: 3000, count: 1),
            ShiftTenderLine(method: 'card', amountBaisas: 1500, count: 1),
          ],
          voidCount: 1,
          voidTotalBaisas: 1500,
          roundUpBaisas: 100,
          branchExpensesBaisas: 0,
          source: source,
        ),
      );
    }

    test('renders header, sales, tenders, voids and the drawer math', () {
      final texts = buildShiftSummaryLines(ticket()).map((l) => l.text).toList();

      expect(texts.first, 'SHIFT SUMMARY');
      expect(texts.join('\n'), contains('POS-TEST-001'));
      expect(texts.any((t) => t.startsWith('Orders') && t.endsWith('2')), isTrue);
      expect(texts.any((t) => t.startsWith('Gross sales') && t.endsWith('5.000')), isTrue);
      expect(texts.any((t) => t.startsWith('Discounts') && t.endsWith('-0.500')), isTrue);
      expect(texts.any((t) => t.startsWith('TOTAL') && t.endsWith('4.500')), isTrue);
      expect(texts.any((t) => t.startsWith('Cash (1)') && t.endsWith('3.000')), isTrue);
      expect(texts.any((t) => t.startsWith('Card (1)') && t.endsWith('1.500')), isTrue);
      expect(texts.any((t) => t.startsWith('Round-up donations') && t.endsWith('0.100')), isTrue);
      expect(texts.any((t) => t.startsWith('Voids (1)') && t.endsWith('1.500')), isTrue);
      expect(texts.any((t) => t.startsWith('Opening float') && t.endsWith('10.000')), isTrue);
      expect(texts.any((t) => t.startsWith('Expected cash') && t.endsWith('13.000')), isTrue);
      expect(texts.any((t) => t.startsWith('Counted cash') && t.endsWith('12.500')), isTrue);
      expect(texts.any((t) => t.contains('VARIANCE (SHORT)') && t.endsWith('-0.500')), isTrue);
    });

    test('reprint banner + offline tag render only when applicable', () {
      final plain = buildShiftSummaryLines(ticket()).map((l) => l.text);
      expect(plain, isNot(contains('*** REPRINT ***')));
      expect(plain.any((t) => t.contains('OFFLINE')), isFalse);

      final reprint = buildShiftSummaryLines(ticket(isReprint: true)).map((l) => l.text);
      expect(reprint, contains('*** REPRINT ***'));

      final local = buildShiftSummaryLines(ticket(source: 'local')).map((l) => l.text);
      expect(local.any((t) => t.contains('OFFLINE')), isTrue);
    });

    test('ticket snapshot round-trips for the manager reprint', () {
      final restored = ShiftSummaryTicket.fromJson(
        ticket().toJson(),
        isReprint: true,
      );

      expect(restored, isNotNull);
      expect(restored!.isReprint, isTrue);
      expect(restored.varianceBaisas, -500);
      expect(restored.summary.tenders, hasLength(2));
      expect(ShiftSummaryTicket.fromJson(null), isNull);
    });
  });
}
