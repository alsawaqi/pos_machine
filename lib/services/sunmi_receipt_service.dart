import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/pos_models.dart';
import 'kitchen_ticket.dart';
import 'shift_summary.dart';

class SunmiReceiptService {
  /// Phase G4 — false once a print hit MissingPluginException (non-Sunmi /
  /// dev hardware: there IS no printer). Callers use it to stay silent on
  /// dev instead of alerting staff about a printer that never existed.
  static bool printerPluginAvailable = true;

  static String money(double value) => '${value.toStringAsFixed(3)} OMR';

  static String row(String left, String right, {int width = 32}) {
    final safeLeft = left.length > width - right.length
        ? left.substring(0, width - right.length)
        : left;
    final spaces = width - safeLeft.length - right.length;
    return '$safeLeft${' ' * (spaces > 0 ? spaces : 1)}$right';
  }

  /// Print the branch logo (a base64-encoded PNG) centered. Fail-safe: a bad /
  /// undecodable image is skipped so it can never block the rest of the
  /// receipt from printing.
  static Future<void> _printLogo(String base64Png) async {
    try {
      final bytes = base64Decode(base64Png);
      if (bytes.isEmpty) return;
      await SunmiPrinter.printImage(bytes, align: SunmiPrintAlign.CENTER);
      await SunmiPrinter.lineWrap(1);
    } catch (_) {
      // Ignore — print the rest of the receipt without the logo.
    }
  }

  /// Print a receipt. When [template] is supplied (the merchant-authored
  /// per-branch template from /device/config), its business name / CR / VAT /
  /// header + footer lines drive the printout; otherwise the built-in default
  /// header ("MITHQAL 2.0") is used.
  ///
  /// Phase G4 — NEVER throws; returns false on a printer failure so callers
  /// can alert staff (paper out / cover open) without ever blocking the sale.
  /// MissingPluginException (dev hardware) is a silent false.
  static Future<bool> printReceipt(OrderSnapshot order, {ReceiptTemplate? template}) async {
    try {
      await _printReceiptBody(order, template: template);
      return true;
    } on MissingPluginException {
      printerPluginAvailable = false;
      return false;
    } catch (error) {
      debugPrint('Receipt print failed: $error');
      return false;
    }
  }

  static Future<void> _printReceiptBody(OrderSnapshot order, {ReceiptTemplate? template}) async {
    final orderType = OrderTypeLabel.fromStorage(order.orderType).label;
    final t = (template != null && !template.isEmpty) ? template : null;

    // Header — optional logo, then business name (large), then the merchant's
    // custom header block. The logo (when present) stands in for the default
    // name, so we only fall back to "MITHQAL 2.0" when there's neither.
    if (t?.logoBase64 != null) {
      await _printLogo(t!.logoBase64!);
    }

    final headerName = t?.businessName ?? (t?.logoBase64 == null ? 'MITHQAL 2.0' : null);
    if (headerName != null) {
      await SunmiPrinter.printText(
        headerName,
        style: SunmiTextStyle(
          bold: true,
          fontSize: 36,
          align: SunmiPrintAlign.CENTER,
        ),
      );
    }
    if (t != null) {
      if (t.businessNameAr != null) {
        await SunmiPrinter.printText(
          t.businessNameAr!,
          style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
        );
      }
      for (final line in t.headerLines) {
        await SunmiPrinter.printText(line, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
      if (t.address != null) {
        await SunmiPrinter.printText(t.address!, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
      if (t.phone != null) {
        await SunmiPrinter.printText('Tel: ${t.phone}', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
      if (t.crNumber != null) {
        await SunmiPrinter.printText('CR No.: ${t.crNumber}', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
      if (t.vatNumber != null) {
        await SunmiPrinter.printText('VAT No.: ${t.vatNumber}', style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
    }

    await SunmiPrinter.printText(
      '$orderType Receipt',
      style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
    );
    await SunmiPrinter.printText(
      // P-F8 — the merchant's sequential number when allocated, else '#N'.
      'Order ${order.displayOrderNumber}',
      style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
    );
    if (order.diningTableName.trim().isNotEmpty) {
      final floorLabel = order.diningFloorLabel.trim();
      final tableLabel = floorLabel.isEmpty
          ? 'Table ${order.diningTableName.trim()}'
          : 'Table ${order.diningTableName.trim()} | $floorLabel';
      await SunmiPrinter.printText(
        tableLabel,
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
    }

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printText('--------------------------------');

    for (final item in order.items) {
      final name = item['name'].toString();
      final qty = (item['qty'] as num).toInt();
      final total = (item['lineTotal'] as num).toDouble();
      await SunmiPrinter.printText(row('$name x$qty', money(total)));
    }

    await SunmiPrinter.printText('--------------------------------');
    if (order.discountAmount > 0) {
      await SunmiPrinter.printText(
        row(
          order.discountLabel.isEmpty ? 'Discount' : order.discountLabel,
          '-${money(order.discountAmount)}',
        ),
      );
    }
    // Phase B — the manager comp write-off, printed as its own line so it is
    // never confused with a discount on the customer's copy.
    if (order.compAmount > 0) {
      await SunmiPrinter.printText(
        row(
          order.compReasonName.isEmpty
              ? 'Comp'
              : 'Comp (${order.compReasonName})',
          '-${money(order.compAmount)}',
        ),
      );
    }
    await SunmiPrinter.printText(row('Subtotal', money(order.subtotal)));
    await SunmiPrinter.printText(row('Tax (5%)', money(order.tax)));
    await SunmiPrinter.printText(
      row('TOTAL', money(order.total)),
      style: SunmiTextStyle(bold: true),
    );
    if (order.splitCount > 1) {
      final splitBaseTotal = order.splitPayments.isEmpty
          ? order.activePaymentBaseTotal
          : order.splitPaymentsBaseTotal;
      await SunmiPrinter.printText(
        row('Split Bill (${order.splitCount})', money(splitBaseTotal)),
      );
    }
    if (order.splitPayments.isNotEmpty) {
      await SunmiPrinter.printText('Split Payments');
      for (final payment in order.splitPayments) {
        await SunmiPrinter.printText(
          row(
            '  Guest ${payment.splitIndex} ${payment.paymentMethod}',
            money(payment.paidAmount),
          ),
        );
        if (payment.charityRoundUpAccepted &&
            payment.charityRoundUpAmount > 0) {
          await SunmiPrinter.printText(
            row('    Charity Round Up', money(payment.charityRoundUpAmount)),
          );
        }
      }
    } else if (order.charityRoundUpAccepted && order.charityRoundUpAmount > 0) {
      await SunmiPrinter.printText(
        row('Charity Round Up', money(order.charityRoundUpAmount)),
      );
    }
    await SunmiPrinter.printText(
      row('AMOUNT PAID', money(order.payableTotal)),
      style: SunmiTextStyle(bold: true),
    );

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printText(
      'Status: ${order.paymentStatus}',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
    );
    await SunmiPrinter.printText(
      'Method: ${order.paymentMethod}',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
    );
    if (order.customerReferenceNumber.trim().isNotEmpty) {
      await SunmiPrinter.printText(
        'Customer: ${order.customerReferenceNumber.trim()}',
        style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
      );
    }

    // QR — printed unless the merchant turned it off in the template.
    if (t == null || t.showQr) {
      await SunmiPrinter.lineWrap(1);
      await SunmiPrinter.printQRCode(
        'MITHQAL|TOTAL=${order.payableTotal.toStringAsFixed(3)}|STATUS=${order.paymentStatus}',
        style: SunmiQrcodeStyle(
          qrcodeSize: 4,
          errorLevel: SunmiQrcodeLevel.LEVEL_H,
        ),
      );
    }

    // Merchant's custom footer lines (thank-you note, policy, etc.).
    if (t != null && t.footerLines.isNotEmpty) {
      await SunmiPrinter.lineWrap(1);
      for (final line in t.footerLines) {
        await SunmiPrinter.printText(line, style: SunmiTextStyle(align: SunmiPrintAlign.CENTER));
      }
    }

    await SunmiPrinter.lineWrap(3);
    await SunmiPrinter.cutPaper();
  }

  /// Phase C1 — print a kitchen ticket (items + qty + add-ons + notes, no
  /// prices; blueprint §6.10). FAIL-SAFE by design: any printer error
  /// (including MissingPluginException on non-Sunmi dev hardware) is swallowed
  /// so a kitchen print can never block order completion or holding. Returns
  /// false on failure (Phase G4) so callers can alert staff.
  static Future<bool> printKitchenTicket(KitchenTicketData ticket) =>
      _printLines(buildKitchenTicketLines(ticket));

  /// Phase C6 — print the shift-close Z-report (blueprint Phase 9 #88).
  /// Same fail-safe contract as the kitchen ticket.
  static Future<bool> printShiftSummary(ShiftSummaryTicket ticket) =>
      _printLines(buildShiftSummaryLines(ticket));

  /// Phase G3 — print arbitrary pre-built ticket lines (the mid-shift
  /// X-report uses this). Same fail-safe contract.
  static Future<bool> printTicketLines(List<KitchenTicketLine> lines) =>
      _printLines(lines);

  /// Render pre-built styled lines, swallowing every printer failure.
  /// Returns false on failure; MissingPluginException additionally clears
  /// [printerPluginAvailable] (dev hardware — stay silent).
  static Future<bool> _printLines(List<KitchenTicketLine> lines) async {
    try {
      for (final line in lines) {
        final align =
            line.center ? SunmiPrintAlign.CENTER : SunmiPrintAlign.LEFT;
        await SunmiPrinter.printText(
          line.text,
          style: line.fontSize == null
              ? SunmiTextStyle(bold: line.bold, align: align)
              : SunmiTextStyle(
                  bold: line.bold,
                  fontSize: line.fontSize!,
                  align: align,
                ),
        );
      }
      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cutPaper();
      return true;
    } on MissingPluginException {
      printerPluginAvailable = false;
      return false;
    } catch (error) {
      debugPrint('Ticket print failed: $error');
      return false;
    }
  }
}
