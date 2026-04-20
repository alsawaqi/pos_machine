import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/pos_models.dart';

class SunmiReceiptService {
  static String money(double value) => '${value.toStringAsFixed(3)} OMR';

  static String row(String left, String right, {int width = 32}) {
    final safeLeft = left.length > width - right.length
        ? left.substring(0, width - right.length)
        : left;
    final spaces = width - safeLeft.length - right.length;
    return '$safeLeft${' ' * (spaces > 0 ? spaces : 1)}$right';
  }

  static Future<void> printReceipt(OrderSnapshot order) async {
    await SunmiPrinter.printText(
      'MITHQAL 2.0',
      style: SunmiTextStyle(
        bold: true,
        fontSize: 36,
        align: SunmiPrintAlign.CENTER,
      ),
    );

    await SunmiPrinter.printText(
      'Quick Order Receipt',
      style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
    );

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printText('--------------------------------');

    for (final item in order.items) {
      final name = item['name'].toString();
      final qty = (item['qty'] as num).toInt();
      final total = (item['lineTotal'] as num).toDouble();
      await SunmiPrinter.printText(row('$name x$qty', money(total)));
    }

    await SunmiPrinter.printText('--------------------------------');
    await SunmiPrinter.printText(row('Subtotal', money(order.subtotal)));
    await SunmiPrinter.printText(row('Tax (5%)', money(order.tax)));
    await SunmiPrinter.printText(
      row('TOTAL', money(order.total)),
      style: SunmiTextStyle(bold: true),
    );
    if (order.charityRoundUpAccepted && order.charityRoundUpAmount > 0) {
      await SunmiPrinter.printText(
        row('Charity Round Up', money(order.charityRoundUpAmount)),
      );
      await SunmiPrinter.printText(
        row('AMOUNT PAID', money(order.payableTotal)),
        style: SunmiTextStyle(bold: true),
      );
    }

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printText(
      'Status: ${order.paymentStatus}',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
    );
    await SunmiPrinter.printText(
      'Method: ${order.paymentMethod}',
      style: SunmiTextStyle(align: SunmiPrintAlign.CENTER),
    );

    await SunmiPrinter.lineWrap(1);
    await SunmiPrinter.printQRCode(
      'MITHQAL|TOTAL=${order.payableTotal.toStringAsFixed(3)}|STATUS=${order.paymentStatus}',
      style: SunmiQrcodeStyle(
        qrcodeSize: 4,
        errorLevel: SunmiQrcodeLevel.LEVEL_H,
      ),
    );

    await SunmiPrinter.lineWrap(3);
    await SunmiPrinter.cutPaper();
  }
}
