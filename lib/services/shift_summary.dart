/// Phase C6 — the shift-close sales summary / Z-report (blueprint Phase 9
/// #88 "Daily sales summary (Manager only)"; Additions §1.2 Shift Report).
///
/// SOURCE OF TRUTH is the `summary` the server returns on shift.close (same
/// transaction + attribution as expected_cash). The LOCAL calculator below is
/// the fallback for an older API, folded from the device's own order log —
/// visibly tagged, because it can legitimately diverge (other devices' sales
/// are absent, cash round-ups are local-only, partial cancels are not
/// netted). Everything in this file is PURE (no printer / IO) and the printed
/// layout is unit-tested like the kitchen ticket.
library;

import '../models/pos_models.dart';
import 'kitchen_ticket.dart' show KitchenTicketLine, formatKitchenTicketTime;
import 'order_sync_payload.dart' show mapPaymentMethod, omrToBaisas;

class ShiftTenderLine {
  const ShiftTenderLine({
    required this.method,
    required this.amountBaisas,
    required this.count,
  });

  final String method;
  final int amountBaisas;
  final int count;

  Map<String, dynamic> toJson() =>
      {'method': method, 'amount_baisas': amountBaisas, 'count': count};

  factory ShiftTenderLine.fromJson(Map<String, dynamic> json) => ShiftTenderLine(
        method: json['method']?.toString() ?? '',
        amountBaisas: (json['amount_baisas'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// The sales numbers on a Z-report (all money integer baisas).
class ShiftSalesSummary {
  const ShiftSalesSummary({
    required this.orderCount,
    required this.grossBaisas,
    required this.discountBaisas,
    required this.compBaisas,
    required this.taxBaisas,
    required this.grandBaisas,
    required this.tenders,
    required this.voidCount,
    required this.voidTotalBaisas,
    required this.roundUpBaisas,
    required this.branchExpensesBaisas,
    required this.source,
  });

  final int orderCount;
  final int grossBaisas;
  final int discountBaisas;
  final int compBaisas;
  final int taxBaisas;
  final int grandBaisas;
  final List<ShiftTenderLine> tenders;
  final int voidCount;
  final int voidTotalBaisas;
  final int roundUpBaisas;

  /// Branch-scoped, informational only — never in the drawer math.
  final int branchExpensesBaisas;

  /// 'server' (authoritative, from the close result) or 'local' (this
  /// device's own log — printed with an OFFLINE tag).
  final String source;

  /// Parse the server's shift.close `summary` block. Null in = null out
  /// (older API → caller falls back to [buildLocalShiftSummary]).
  static ShiftSalesSummary? fromServerResult(Map<String, dynamic>? summary) {
    if (summary == null) return null;
    return ShiftSalesSummary(
      orderCount: (summary['order_count'] as num?)?.toInt() ?? 0,
      grossBaisas: (summary['gross_sales_baisas'] as num?)?.toInt() ?? 0,
      discountBaisas: (summary['discount_total_baisas'] as num?)?.toInt() ?? 0,
      compBaisas: (summary['comp_total_baisas'] as num?)?.toInt() ?? 0,
      taxBaisas: (summary['tax_total_baisas'] as num?)?.toInt() ?? 0,
      grandBaisas: (summary['grand_total_baisas'] as num?)?.toInt() ?? 0,
      tenders: ((summary['tenders'] as List?) ?? const [])
          .whereType<Map>()
          .map((t) => ShiftTenderLine.fromJson(t.cast<String, dynamic>()))
          .toList(),
      voidCount: (summary['void_count'] as num?)?.toInt() ?? 0,
      voidTotalBaisas: (summary['void_total_baisas'] as num?)?.toInt() ?? 0,
      roundUpBaisas: (summary['round_up_baisas'] as num?)?.toInt() ?? 0,
      branchExpensesBaisas:
          (summary['branch_expenses_baisas'] as num?)?.toInt() ?? 0,
      source: 'server',
    );
  }

  Map<String, dynamic> toJson() => {
        'order_count': orderCount,
        'gross_sales_baisas': grossBaisas,
        'discount_total_baisas': discountBaisas,
        'comp_total_baisas': compBaisas,
        'tax_total_baisas': taxBaisas,
        'grand_total_baisas': grandBaisas,
        'tenders': tenders.map((t) => t.toJson()).toList(),
        'void_count': voidCount,
        'void_total_baisas': voidTotalBaisas,
        'round_up_baisas': roundUpBaisas,
        'branch_expenses_baisas': branchExpensesBaisas,
        'source': source,
      };

  factory ShiftSalesSummary.fromJson(Map<String, dynamic> json) =>
      ShiftSalesSummary(
        orderCount: (json['order_count'] as num?)?.toInt() ?? 0,
        grossBaisas: (json['gross_sales_baisas'] as num?)?.toInt() ?? 0,
        discountBaisas: (json['discount_total_baisas'] as num?)?.toInt() ?? 0,
        compBaisas: (json['comp_total_baisas'] as num?)?.toInt() ?? 0,
        taxBaisas: (json['tax_total_baisas'] as num?)?.toInt() ?? 0,
        grandBaisas: (json['grand_total_baisas'] as num?)?.toInt() ?? 0,
        tenders: ((json['tenders'] as List?) ?? const [])
            .whereType<Map>()
            .map((t) => ShiftTenderLine.fromJson(t.cast<String, dynamic>()))
            .toList(),
        voidCount: (json['void_count'] as num?)?.toInt() ?? 0,
        voidTotalBaisas: (json['void_total_baisas'] as num?)?.toInt() ?? 0,
        roundUpBaisas: (json['round_up_baisas'] as num?)?.toInt() ?? 0,
        branchExpensesBaisas:
            (json['branch_expenses_baisas'] as num?)?.toInt() ?? 0,
        source: json['source']?.toString() ?? 'server',
      );
}

/// Offline fallback: fold the DEVICE-LOCAL order log over the shift window.
/// Reads the records the caller loaded from LocalOrderStorageService —
/// NEVER controller.orderHistory (that may hold server records when online).
/// Split tenders are exploded per guest at their pre-round-up base amount so
/// the per-method totals match the server's tender semantics.
ShiftSalesSummary buildLocalShiftSummary(
  List<OrderHistoryRecord> localHistory, {
  required DateTime openedAt,
  required DateTime closedAt,
}) {
  var orderCount = 0;
  var gross = 0.0, discount = 0.0, comp = 0.0, tax = 0.0, grand = 0.0;
  var voidCount = 0;
  var voidTotal = 0.0, roundUp = 0.0;
  final tenderAmounts = <String, double>{};
  final tenderCounts = <String, int>{};

  for (final record in localHistory) {
    if (record.fromServer) continue;
    if (record.createdAt.isBefore(openedAt) ||
        record.createdAt.isAfter(closedAt)) {
      continue;
    }
    final s = record.snapshot;

    if (s.isFullyCanceled) {
      voidCount++;
      voidTotal += s.total;
      continue;
    }

    orderCount++;
    gross += s.rawSubtotal;
    discount += s.discountAmount;
    comp += s.compAmount;
    tax += s.tax;
    grand += s.total;

    if (s.splitPayments.isNotEmpty) {
      for (final p in s.splitPayments) {
        final method = mapPaymentMethod(p.paymentMethod);
        tenderAmounts[method] = (tenderAmounts[method] ?? 0) + p.baseAmount;
        tenderCounts[method] = (tenderCounts[method] ?? 0) + 1;
        if (p.charityRoundUpAccepted) roundUp += p.charityRoundUpAmount;
      }
    } else {
      final method = mapPaymentMethod(s.paymentMethod);
      tenderAmounts[method] = (tenderAmounts[method] ?? 0) + s.total;
      tenderCounts[method] = (tenderCounts[method] ?? 0) + 1;
      if (s.charityRoundUpAccepted) roundUp += s.charityRoundUpAmount;
    }
  }

  final methods = tenderAmounts.keys.toList()..sort();
  return ShiftSalesSummary(
    orderCount: orderCount,
    grossBaisas: omrToBaisas(gross),
    discountBaisas: omrToBaisas(discount),
    compBaisas: omrToBaisas(comp),
    taxBaisas: omrToBaisas(tax),
    grandBaisas: omrToBaisas(grand),
    tenders: methods
        .map((m) => ShiftTenderLine(
              method: m,
              amountBaisas: omrToBaisas(tenderAmounts[m]!),
              count: tenderCounts[m] ?? 0,
            ))
        .toList(),
    voidCount: voidCount,
    voidTotalBaisas: omrToBaisas(voidTotal),
    roundUpBaisas: omrToBaisas(roundUp),
    branchExpensesBaisas: 0, // expenses live server-side only
    source: 'local',
  );
}

/// Everything one printed Z-report shows (summary + drawer + context).
/// Serializable so the LAST close survives for a manager reprint.
class ShiftSummaryTicket {
  const ShiftSummaryTicket({
    required this.deviceCode,
    required this.staffName,
    required this.openedAt,
    required this.closedAt,
    required this.openingBaisas,
    required this.expectedBaisas,
    required this.countedBaisas,
    required this.varianceBaisas,
    required this.summary,
    this.isReprint = false,
  });

  final String deviceCode;
  final String staffName;
  final DateTime openedAt;
  final DateTime closedAt;
  final int openingBaisas;
  final int expectedBaisas;
  final int countedBaisas;
  final int varianceBaisas;
  final ShiftSalesSummary summary;
  final bool isReprint;

  Map<String, dynamic> toJson() => {
        'device_code': deviceCode,
        'staff_name': staffName,
        'opened_at': openedAt.toIso8601String(),
        'closed_at': closedAt.toIso8601String(),
        'opening_baisas': openingBaisas,
        'expected_baisas': expectedBaisas,
        'counted_baisas': countedBaisas,
        'variance_baisas': varianceBaisas,
        'summary': summary.toJson(),
      };

  static ShiftSummaryTicket? fromJson(
    Map<String, dynamic>? json, {
    bool isReprint = false,
  }) {
    if (json == null) return null;
    final summary = json['summary'];
    if (summary is! Map) return null;
    return ShiftSummaryTicket(
      deviceCode: json['device_code']?.toString() ?? '',
      staffName: json['staff_name']?.toString() ?? '',
      openedAt: DateTime.tryParse(json['opened_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      closedAt: DateTime.tryParse(json['closed_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      openingBaisas: (json['opening_baisas'] as num?)?.toInt() ?? 0,
      expectedBaisas: (json['expected_baisas'] as num?)?.toInt() ?? 0,
      countedBaisas: (json['counted_baisas'] as num?)?.toInt() ?? 0,
      varianceBaisas: (json['variance_baisas'] as num?)?.toInt() ?? 0,
      summary:
          ShiftSalesSummary.fromJson(summary.cast<String, dynamic>()),
      isReprint: isReprint,
    );
  }
}

const String _divider = '--------------------------------';

String _money(int baisas) {
  final sign = baisas < 0 ? '-' : '';
  return '$sign${(baisas.abs() / 1000).toStringAsFixed(3)}';
}

String _row(String left, String right, {int width = 32}) {
  final safeLeft = left.length > width - right.length - 1
      ? left.substring(0, width - right.length - 1)
      : left;
  final spaces = width - safeLeft.length - right.length;
  return '$safeLeft${' ' * (spaces > 0 ? spaces : 1)}$right';
}

String _tenderLabel(String method) => switch (method) {
      'cash' => 'Cash',
      'card' => 'Card',
      'loyalty' => 'Loyalty',
      'gift' => 'Gift',
      _ => method,
    };

/// The printed Z-report layout. Drawer math is IDENTICAL to the server's
/// CloseShiftHandler + the merchant Shift Report: expected = opening + net
/// cash (expenses informational, never deducted); variance negative = SHORT.
List<KitchenTicketLine> buildShiftSummaryLines(ShiftSummaryTicket t) {
  final s = t.summary;
  final lines = <KitchenTicketLine>[
    const KitchenTicketLine('SHIFT SUMMARY',
        bold: true, fontSize: 32, center: true),
    const KitchenTicketLine('(Z-REPORT)', bold: true, center: true),
  ];

  if (t.isReprint) {
    lines.add(
      const KitchenTicketLine('*** REPRINT ***', bold: true, center: true),
    );
  }
  if (s.source == 'local') {
    lines.add(const KitchenTicketLine('OFFLINE - device-local figures',
        bold: true, center: true));
  }

  lines
    ..add(KitchenTicketLine(
      'Device ${t.deviceCode}'
      '${t.staffName.isEmpty ? '' : '  |  ${t.staffName}'}',
      center: true,
    ))
    ..add(KitchenTicketLine(
      '${formatKitchenTicketTime(t.openedAt)} - '
      '${formatKitchenTicketTime(t.closedAt)}',
      center: true,
    ))
    ..add(const KitchenTicketLine(_divider))
    ..add(const KitchenTicketLine('SALES', bold: true))
    ..add(KitchenTicketLine(_row('Orders', '${s.orderCount}')))
    ..add(KitchenTicketLine(_row('Gross sales', _money(s.grossBaisas))));

  if (s.discountBaisas > 0) {
    lines.add(
        KitchenTicketLine(_row('Discounts', '-${_money(s.discountBaisas)}')));
  }
  if (s.compBaisas > 0) {
    lines.add(KitchenTicketLine(_row('Comps', '-${_money(s.compBaisas)}')));
  }
  if (s.taxBaisas > 0) {
    lines.add(KitchenTicketLine(_row('Tax', _money(s.taxBaisas))));
  }
  lines.add(KitchenTicketLine(
    _row('TOTAL', _money(s.grandBaisas)),
    bold: true,
  ));

  if (s.tenders.isNotEmpty) {
    lines
      ..add(const KitchenTicketLine(_divider))
      ..add(const KitchenTicketLine('TENDERS', bold: true));
    for (final tender in s.tenders) {
      lines.add(KitchenTicketLine(_row(
        '${_tenderLabel(tender.method)} (${tender.count})',
        _money(tender.amountBaisas),
      )));
    }
  }
  if (s.roundUpBaisas > 0) {
    // Charity money, not revenue — its own memo row.
    lines.add(KitchenTicketLine(
        _row('Round-up donations', _money(s.roundUpBaisas))));
  }

  if (s.voidCount > 0) {
    lines
      ..add(const KitchenTicketLine(_divider))
      ..add(KitchenTicketLine(_row(
        'Voids (${s.voidCount})',
        _money(s.voidTotalBaisas),
      )));
  }
  if (s.branchExpensesBaisas > 0) {
    lines.add(KitchenTicketLine(_row(
      'Branch expenses',
      _money(s.branchExpensesBaisas),
    )));
  }

  final varianceWord = t.varianceBaisas == 0
      ? 'BALANCED'
      : t.varianceBaisas < 0
          ? 'SHORT'
          : 'OVER';
  lines
    ..add(const KitchenTicketLine(_divider))
    ..add(const KitchenTicketLine('DRAWER', bold: true))
    ..add(KitchenTicketLine(_row('Opening float', _money(t.openingBaisas))))
    ..add(KitchenTicketLine(_row('Expected cash', _money(t.expectedBaisas))))
    ..add(KitchenTicketLine(_row('Counted cash', _money(t.countedBaisas))))
    ..add(KitchenTicketLine(
      _row('VARIANCE ($varianceWord)', _money(t.varianceBaisas)),
      bold: true,
    ))
    ..add(const KitchenTicketLine(_divider));

  return lines;
}
