import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/pos_models.dart';
import 'kitchen_ticket.dart';
import 'receipt_layout.dart';
import 'receipt_renderer.dart';
import 'shift_summary.dart';

class SunmiReceiptService {
  static String? lastPrinterStatus;
  static Future<bool> printReversalSlip(List<SlipLine> lines) => _printLines([
    for (final line in lines)
      KitchenTicketLine(
        line.text,
        bold: line.bold,
        center: true,
        fontSize: line.large ? 32 : 24,
      ),
  ]);

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

  /// Print a customer receipt — LAUNCH-P4 C2: the one bilingual layout
  /// ([buildReceiptLines]) drawn as a bitmap ([renderReceiptPngStrips]) so
  /// Arabic prints shaped and joined (the printer's text API cannot). The
  /// branch logo, when set, prints first. [tax] = the merchant's VAT setup
  /// (title, VAT number); [at] = the order time to print (now for a new
  /// sale, the original time for a reprint). No QR code (L10).
  ///
  /// Phase G4 — NEVER throws; returns false on a printer failure so callers
  /// can alert staff (paper out / cover open) without ever blocking the sale.
  /// MissingPluginException (dev hardware) is a silent false.
  static Future<bool> printReceipt(
    OrderSnapshot order, {
    ReceiptTemplate? template,
    CompanyTaxSettings? tax,
    String branchName = '',
    String branchNameAr = '',
    DateTime? at,
  }) async {
    try {
      await _printReceiptBody(
        order,
        template: template,
        tax: tax ?? activeTaxSettings,
        branchName: branchName,
        branchNameAr: branchNameAr,
        at: at ?? DateTime.now(),
      );
      lastPrinterStatus = 'ready';
      return true;
    } on MissingPluginException {
      printerPluginAvailable = false;
      lastPrinterStatus = printerPluginAvailable ? 'error' : 'unavailable';
      return false;
    } catch (error) {
      debugPrint('Receipt print failed: $error');
      lastPrinterStatus = printerPluginAvailable ? 'error' : 'unavailable';
      return false;
    }
  }

  /// Tests: receives every receipt's lines as plain text (direction isolates
  /// removed) exactly as they are laid out for printing — the bitmap itself
  /// cannot be read back.
  @visibleForTesting
  static void Function(List<String> lines)? debugReceiptLines;

  /// Tests (and a future setting) can force the paper width in dots.
  @visibleForTesting
  static int? debugPaperWidth;
  static int? _paperWidth;

  /// 576 dots on 80 mm paper, else 384 (58 mm). Asked once from the printer.
  static Future<int> _paperWidthDots() async {
    final forced = debugPaperWidth;
    if (forced != null) return forced;
    final cached = _paperWidth;
    if (cached != null) return cached;
    var width = kReceipt58mmWidth;
    try {
      final paper = await SunmiConfig.getPaper();
      if (paper != null && paper.contains('80')) width = kReceipt80mmWidth;
    } catch (_) {
      // Unknown printer: 384 dots fits both paper widths.
    }
    return _paperWidth = width;
  }

  static Future<void> _printReceiptBody(
    OrderSnapshot order, {
    ReceiptTemplate? template,
    required CompanyTaxSettings tax,
    required String branchName,
    required String branchNameAr,
    required DateTime at,
  }) async {
    final t = (template != null && !template.isEmpty) ? template : null;
    if (t?.logoBase64 != null) {
      await _printLogo(t!.logoBase64!);
    }
    final lines = buildReceiptLines(
      order,
      header: ReceiptHeader(
        template: t,
        tax: tax,
        branchName: branchName,
        branchNameAr: branchNameAr,
      ),
      at: at,
    );
    debugReceiptLines?.call([
      for (final line in lines) stripIsolates(line.toString()),
    ]);
    List<Uint8List> strips;
    try {
      strips = await renderReceiptPngStrips(
        lines,
        options: ReceiptRenderOptions(width: await _paperWidthDots()),
      );
    } catch (error) {
      debugPrint('Receipt render failed, printing text: $error');
      strips = const <Uint8List>[];
    }
    if (strips.isEmpty) {
      // Last resort: the same lines as plain text (Arabic may print unjoined
      // here, but a sale always gets its receipt).
      for (final line in lines) {
        if (line.kind == ReceiptLineKind.gap) continue;
        await SunmiPrinter.printText(
          line.kind == ReceiptLineKind.divider
              ? '--------------------------------'
              : stripIsolates(
                  line.amount.isEmpty
                      ? line.text
                      : row(line.text, line.amount),
                ),
        );
      }
    } else {
      for (final strip in strips) {
        await SunmiPrinter.printImage(strip, align: SunmiPrintAlign.CENTER);
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
        final align = line.center
            ? SunmiPrintAlign.CENTER
            : SunmiPrintAlign.LEFT;
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
      lastPrinterStatus = 'ready';
      return true;
    } on MissingPluginException {
      printerPluginAvailable = false;
      lastPrinterStatus = printerPluginAvailable ? 'error' : 'unavailable';
      return false;
    } catch (error) {
      debugPrint('Ticket print failed: $error');
      lastPrinterStatus = printerPluginAvailable ? 'error' : 'unavailable';
      return false;
    }
  }
}
