/// LAUNCH-P4 C2 — the ONE customer receipt layout (till; the handheld mirrors
/// it in Part D). Pure: an [OrderSnapshot] + the branch template + the
/// merchant's VAT setup become a list of [ReceiptLine]s; the renderer
/// (receipt_renderer.dart) draws them as a bitmap so Arabic is shaped
/// correctly on the Sunmi printer, whose text API does not shape Arabic.
///
/// Layout, top to bottom (Arabic and English together; amounts in OMR, 3 dp):
///
///  1. [logo — printed separately before the bitmap]
///  2. Business name (EN, large) / business name (AR)
///  3. Branch name (EN · AR), template header lines, address, "Tel:"
///  4. "CR No. / رقم السجل التجاري: …"
///  5. "VAT No. / الرقم الضريبي: …" — from company.tax when the merchant is
///     VAT-registered (the template's number only on a pre-P4 server)
///  6. Pending banner (EN + AR) when the server number is still pending
///  7. Title, English then Arabic on its own line: "Simplified tax invoice"
///     + "فاتورة ضريبية مبسطة" when VAT-registered, else "Receipt" + "إيصال"
///  8. Order type (EN · AR); "Receipt No. / رقم الإيصال"; "Date / التاريخ"
///     dd/MM/yyyy and "Time / الوقت" HH:mm in Muscat time (UTC+4);
///     table / floor; delivery app
///  9. ---- items: "qty x English name" with the line total; the Arabic name
///     on its own right-aligned line when present; add-ons indented with
///     "+"; combo components indented with ">" and their add-ons below
/// 10. ---- discounts, offers, comp (each negative), "Subtotal / المجموع
///     الفرعي"
/// 11. One line per tax: "VAT 5% / ضريبة القيمة المضافة" + amount (none
///     when not registered or on a delivery order)
/// 12. "Prices include VAT / الأسعار شاملة الضريبة" when the order was
///     priced VAT-inclusive
/// 13. "TOTAL / الإجمالي" (large); split, charity round-up; "AMOUNT PAID /
///     المبلغ المدفوع"
/// 14. "Payment / طريقة الدفع", "Status / الحالة", customer reference
/// 15. Template footer lines
///
/// Every Arabic segment inside a mixed line is a right-to-left isolate
/// ([arIsolate]) so digits and punctuation after it keep their order.
///
/// No QR code is printed (L10: the old `MITHQAL|TOTAL` code had no use).
library;

import '../models/pos_models.dart';
import 'discount_display.dart';
import 'server_receipt_history.dart';

enum ReceiptLineKind {
  heading,
  centered,
  title,
  pair,
  item,
  itemAr,
  detail,
  total,
  note,
  divider,
  gap,
}

/// One printable line of the receipt. [text] is shown as written (it may
/// already combine English and Arabic); [amount] is right-aligned.
class ReceiptLine {
  const ReceiptLine(
    this.kind, {
    this.text = '',
    this.amount = '',
    this.bold = false,
  });

  final ReceiptLineKind kind;
  final String text;
  final String amount;
  final bool bold;

  @override
  String toString() => amount.isEmpty ? text : '$text  $amount';
}

/// The receipt's identity block, resolved once per print.
class ReceiptHeader {
  const ReceiptHeader({
    this.template,
    this.tax = CompanyTaxSettings.legacy,
    this.branchName = '',
    this.branchNameAr = '',
  });

  final ReceiptTemplate? template;
  final CompanyTaxSettings tax;
  final String branchName;
  final String branchNameAr;
}

String receiptAmount(double value) => value.toStringAsFixed(3);
String receiptMoney(double value) => '${value.toStringAsFixed(3)} OMR';

String _two(int v) => v.toString().padLeft(2, '0');

/// Muscat wall-clock time (UTC+4, no daylight saving).
DateTime muscatTime(DateTime at) => at.toUtc().add(const Duration(hours: 4));

String receiptDate(DateTime at) {
  final t = muscatTime(at);
  return '${_two(t.day)}/${_two(t.month)}/${t.year}';
}

String receiptTime(DateTime at) {
  final t = muscatTime(at);
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// Arabic segments are wrapped in a right-to-left ISOLATE (U+2067 … U+2069)
/// so the numbers and punctuation that follow them in a mostly-English line
/// keep their left-to-right order ("Tel / هاتف: +968 …").
String arIsolate(String ar) => '$_rli$ar$_pdi';

final String _rli = String.fromCharCode(0x2067); // RIGHT-TO-LEFT ISOLATE
final String _pdi = String.fromCharCode(0x2069); // POP DIRECTIONAL ISOLATE
final RegExp _isolates = RegExp(
  '[${String.fromCharCode(0x2066)}-${String.fromCharCode(0x2069)}]',
);

/// Removes the direction isolates (plain-text fallback, tests).
String stripIsolates(String text) => text.replaceAll(_isolates, '');

String _bi(String en, String ar) =>
    ar.trim().isEmpty ? en : '$en / ${arIsolate(ar.trim())}';

String _rate(num rate) =>
    rate == rate.roundToDouble() ? rate.toStringAsFixed(0) : rate.toString();

const Map<String, String> _orderTypeAr = {
  'quick_order': 'طلب سريع',
  'to_go': 'سفري',
  'delivery': 'توصيل',
  'dine_in': 'محلي',
};

String _paymentMethodAr(String method) {
  final m = method.toLowerCase();
  if (m.contains('split')) return 'دفع مقسّم';
  if (m.contains('bank')) return 'جهاز البنك';
  if (m.contains('card')) return 'بطاقة';
  if (m.contains('gift')) return 'هدية';
  if (m.contains('loyalty')) return 'نقاط الولاء';
  if (m.contains('delivery')) return 'تطبيق التوصيل';
  if (m.contains('cash')) return 'نقدي';
  return '';
}

String _statusAr(String status) {
  final s = status.toLowerCase();
  if (s.contains('pending')) return 'بانتظار التحقق';
  if (s.contains('paid') || s.contains('complete') || s.contains('success')) {
    return 'مدفوع';
  }
  if (s.contains('cancel') || s.contains('void')) return 'ملغى';
  return '';
}

/// Build the receipt lines for [order], printed at [at] (the order time for
/// a reprint).
List<ReceiptLine> buildReceiptLines(
  OrderSnapshot order, {
  required ReceiptHeader header,
  required DateTime at,
}) {
  final lines = <ReceiptLine>[];
  final t = header.template;
  final tax = header.tax;

  // ---- 2-5: who issues it ---------------------------------------------------
  final businessName = t?.businessName?.trim() ?? '';
  final businessNameAr = t?.businessNameAr?.trim() ?? '';
  if (businessName.isNotEmpty) {
    lines.add(ReceiptLine(ReceiptLineKind.heading, text: businessName));
  } else if (businessNameAr.isEmpty && (t?.logoBase64 ?? '').isEmpty) {
    lines.add(const ReceiptLine(ReceiptLineKind.heading, text: 'MITHQAL 2.0'));
  }
  if (businessNameAr.isNotEmpty) {
    lines.add(
      ReceiptLine(ReceiptLineKind.heading, text: businessNameAr, bold: true),
    );
  }
  final branch = [
    header.branchName.trim(),
    header.branchNameAr.trim(),
  ].where((s) => s.isNotEmpty).join(' · ');
  if (branch.isNotEmpty) {
    lines.add(ReceiptLine(ReceiptLineKind.centered, text: branch));
  }
  for (final line in t?.headerLines ?? const <String>[]) {
    lines.add(ReceiptLine(ReceiptLineKind.centered, text: line));
  }
  if ((t?.address ?? '').trim().isNotEmpty) {
    lines.add(ReceiptLine(ReceiptLineKind.centered, text: t!.address!.trim()));
  }
  if ((t?.phone ?? '').trim().isNotEmpty) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.centered,
        text: '${_bi('Tel', 'هاتف')}: ${t!.phone!.trim()}',
      ),
    );
  }
  if ((t?.crNumber ?? '').trim().isNotEmpty) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.centered,
        text: '${_bi('CR No.', 'رقم السجل التجاري')}: ${t!.crNumber!.trim()}',
      ),
    );
  }
  // The VAT number comes from the company record (company.tax). A pre-P4
  // server sends none, so the branch template's number still prints there.
  final vatNumber = tax.vatRegistered == null
      ? (t?.vatNumber?.trim().isNotEmpty ?? false ? t!.vatNumber!.trim() : null)
      : tax.printableVatNumber;
  if (vatNumber != null) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.centered,
        text: '${_bi('VAT No.', 'الرقم الضريبي')}: $vatNumber',
      ),
    );
  }

  // ---- 6-8: what it is --------------------------------------------------------
  lines.add(const ReceiptLine(ReceiptLineKind.gap));
  if (order.receiptPending) {
    lines
      ..add(const ReceiptLine(ReceiptLineKind.title, text: pendingReceiptEn))
      ..add(const ReceiptLine(ReceiptLineKind.title, text: pendingReceiptAr));
  }
  // The title in English, then Arabic on its own line.
  lines
    ..add(
      ReceiptLine(
        ReceiptLineKind.title,
        text: tax.isRegistered ? 'Simplified tax invoice' : 'Receipt',
      ),
    )
    ..add(
      ReceiptLine(
        ReceiptLineKind.title,
        text: tax.isRegistered ? 'فاتورة ضريبية مبسطة' : 'إيصال',
      ),
    );
  final orderType = OrderTypeLabel.fromStorage(order.orderType).label;
  lines.add(
    ReceiptLine(
      ReceiptLineKind.centered,
      text: _bi(orderType, _orderTypeAr[order.orderType] ?? ''),
    ),
  );
  lines
    ..add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Receipt No. / رقم الإيصال',
        amount: order.displayOrderNumber,
        bold: true,
      ),
    )
    ..add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Date / التاريخ',
        amount: receiptDate(at),
      ),
    )
    ..add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Time / الوقت',
        amount: receiptTime(at),
      ),
    );
  if (order.diningTableName.trim().isNotEmpty) {
    final floor = order.diningFloorLabel.trim();
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Table / الطاولة',
        amount: floor.isEmpty
            ? order.diningTableName.trim()
            : '${order.diningTableName.trim()} | $floor',
      ),
    );
  }
  if (order.deliveryProviderName.trim().isNotEmpty) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Delivery / التوصيل',
        amount: order.deliveryProviderName.trim(),
      ),
    );
  }

  // ---- 9: items ------------------------------------------------------------------
  lines.add(const ReceiptLine(ReceiptLineKind.divider));
  for (final item in order.items) {
    final name = item['name']?.toString() ?? '';
    final nameAr = item['nameAr']?.toString().trim() ?? '';
    final qty = (item['qty'] as num?)?.toInt() ?? 1;
    final total = (item['lineTotal'] as num?)?.toDouble() ?? 0;
    lines.add(
      ReceiptLine(
        ReceiptLineKind.item,
        text: '$qty x $name',
        amount: receiptAmount(total),
      ),
    );
    if (nameAr.isNotEmpty) {
      lines.add(ReceiptLine(ReceiptLineKind.itemAr, text: nameAr));
    }
    for (final raw in (item['components'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final cName = raw['name']?.toString() ?? '';
      final cNameAr = raw['nameAr']?.toString().trim() ?? '';
      final cQty = (raw['qty'] as num?)?.toInt() ?? 1;
      final extra = (raw['extraPrice'] as num?)?.toDouble() ?? 0;
      lines.add(
        ReceiptLine(
          ReceiptLineKind.detail,
          text:
              '> ${cQty > 1 ? '$cQty x ' : ''}${_bi(cName, cNameAr)}'
              '${extra > 0 ? ' (+${receiptAmount(extra)})' : ''}',
        ),
      );
      for (final m in (raw['modifiers'] as List?) ?? const []) {
        if (m is! Map) continue;
        lines.add(ReceiptLine(ReceiptLineKind.detail, text: '   ${_addon(m)}'));
      }
    }
    for (final m in (item['modifiers'] as List?) ?? const []) {
      if (m is! Map) continue;
      lines.add(ReceiptLine(ReceiptLineKind.detail, text: _addon(m)));
    }
  }
  lines.add(const ReceiptLine(ReceiptLineKind.divider));

  // ---- 10: discounts / comp / subtotal --------------------------------------
  for (final discount in snapshotDiscountDisplayRows(order)) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: _bi(discount.label(), 'خصم'),
        amount: '-${receiptMoney(discount.amountBaisas / 1000)}',
      ),
    );
  }
  if (order.compAmount > 0) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: order.compReasonName.isEmpty
            ? _bi('Comp', 'ضيافة')
            : '${_bi('Comp', 'ضيافة')} (${order.compReasonName})',
        amount: '-${receiptMoney(order.compAmount)}',
      ),
    );
  }
  lines.add(
    ReceiptLine(
      ReceiptLineKind.pair,
      text: 'Subtotal / المجموع الفرعي',
      amount: receiptAmount(order.subtotal),
    ),
  );

  // ---- 11-12: tax lines (none when not registered / delivery) --------------
  final taxLines = order.taxLines;
  if (taxLines.isNotEmpty) {
    for (final line in taxLines) {
      final rate = (line['ratePercent'] as num?) ?? 0;
      final name = line['name']?.toString() ?? '';
      final nameAr = line['nameAr']?.toString().trim() ?? '';
      lines.add(
        ReceiptLine(
          ReceiptLineKind.pair,
          text: nameAr.isEmpty
              ? '$name ${_rate(rate)}%'
              : '$name ${_rate(rate)}% / ${arIsolate(nameAr)}',
          amount: receiptAmount((line['amount'] as num?)?.toDouble() ?? 0),
        ),
      );
    }
  } else if (order.tax != 0) {
    // An older snapshot without frozen tax lines: one combined row.
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Tax / الضريبة',
        amount: receiptAmount(order.tax),
      ),
    );
  }
  if (order.pricesIncludeTax && (taxLines.isNotEmpty || order.tax != 0)) {
    lines.add(
      const ReceiptLine(
        ReceiptLineKind.note,
        text: 'Prices include VAT / الأسعار شاملة الضريبة',
      ),
    );
  }

  // ---- 13: totals and payment -------------------------------------------------
  lines.add(
    ReceiptLine(
      ReceiptLineKind.total,
      text: 'TOTAL / الإجمالي',
      amount: receiptMoney(order.total),
    ),
  );
  if (order.splitCount > 1) {
    final splitBaseTotal = order.splitPayments.isEmpty
        ? order.activePaymentBaseTotal
        : order.splitPaymentsBaseTotal;
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Split bill / فاتورة مقسّمة (${order.splitCount})',
        amount: receiptAmount(splitBaseTotal),
      ),
    );
  }
  if (order.splitPayments.isNotEmpty) {
    for (final payment in order.splitPayments) {
      lines.add(
        ReceiptLine(
          ReceiptLineKind.pair,
          text:
              '  ${_bi('Guest', 'ضيف')} ${payment.splitIndex} · '
              '${payment.paymentMethod}',
          amount: receiptAmount(payment.paidAmount),
        ),
      );
      if (payment.charityRoundUpAccepted && payment.charityRoundUpAmount > 0) {
        lines.add(
          ReceiptLine(
            ReceiptLineKind.pair,
            text: '    Charity round-up / تبرع',
            amount: receiptAmount(payment.charityRoundUpAmount),
          ),
        );
      }
    }
  } else if (order.charityRoundUpAccepted && order.charityRoundUpAmount > 0) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Charity round-up / تبرع',
        amount: receiptAmount(order.charityRoundUpAmount),
      ),
    );
  }
  lines.add(
    ReceiptLine(
      ReceiptLineKind.pair,
      text: 'AMOUNT PAID / المبلغ المدفوع',
      amount: receiptMoney(order.payableTotal),
      bold: true,
    ),
  );

  // ---- 14: payment details -----------------------------------------------------
  lines
    ..add(const ReceiptLine(ReceiptLineKind.gap))
    ..add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Payment / طريقة الدفع',
        amount: _bi(order.paymentMethod, _paymentMethodAr(order.paymentMethod)),
      ),
    )
    ..add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Status / الحالة',
        amount: _bi(order.paymentStatus, _statusAr(order.paymentStatus)),
      ),
    );
  if (order.customerReferenceNumber.trim().isNotEmpty) {
    lines.add(
      ReceiptLine(
        ReceiptLineKind.pair,
        text: 'Customer / العميل',
        amount: order.customerReferenceNumber.trim(),
      ),
    );
  }

  // ---- 15: footer -------------------------------------------------------------------
  final footer = t?.footerLines ?? const <String>[];
  if (footer.isNotEmpty) {
    lines.add(const ReceiptLine(ReceiptLineKind.gap));
    for (final line in footer) {
      lines.add(ReceiptLine(ReceiptLineKind.centered, text: line));
    }
  }
  return lines;
}

String _addon(Map<dynamic, dynamic> m) {
  final label = m['label']?.toString() ?? '';
  final labelAr = m['labelAr']?.toString().trim() ?? '';
  final price = (m['price'] as num?)?.toDouble() ?? 0;
  return '+ ${_bi(label, labelAr)}'
      '${price > 0 ? ' (+${receiptAmount(price)})' : ''}';
}
