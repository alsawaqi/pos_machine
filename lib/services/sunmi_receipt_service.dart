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
    final orderType = OrderTypeLabel.fromStorage(order.orderType).label;

    await SunmiPrinter.printText(
      'MITHQAL 2.0',
      style: SunmiTextStyle(
        bold: true,
        fontSize: 36,
        align: SunmiPrintAlign.CENTER,
      ),
    );

    await SunmiPrinter.printText(
      '$orderType Receipt',
      style: SunmiTextStyle(bold: true, align: SunmiPrintAlign.CENTER),
    );
    await SunmiPrinter.printText(
      'Order #${order.orderNumber}',
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
