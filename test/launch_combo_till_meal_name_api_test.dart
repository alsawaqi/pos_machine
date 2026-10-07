import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/qr_quick/qr_quick_models.dart';

/// LAUNCH combo add-on — the shared meal line name (new API): the tablet
/// sheet, the QR-quick orders sheet, QR / table bills and frozen round lines
/// all name a meal line by its display name.
void main() {
  test('serverLineName: display name, then "<main> <meal>", then product', () {
    final meal = {
      'product_id': 4,
      'product_name': 'Mocha',
      'product_name_ar': 'موكا',
      'meal_id': 9,
      'display_name': 'Mocha meal',
      'display_name_ar': 'موكا وجبة',
    };
    expect(serverLineName(meal, arabic: false), 'Mocha meal');
    expect(serverLineName(meal, arabic: true), 'موكا وجبة');
    // A line without the display name builds it from its parts.
    expect(
      serverLineName({
        'product_name': 'Mocha',
        'meal_id': 9,
        'meal_name': 'meal',
      }, arabic: false),
      'Mocha meal',
    );
    expect(
      serverLineName({
        'product_name': 'Mocha',
        'product_name_ar': 'موكا',
      }, arabic: true),
      'موكا',
    );
    expect(serverLineName({'product_id': 4}, arabic: false), '#4');
  });

  test('a frozen round meal line shows the meal on the table panel', () {
    final line = QrRoundDisplayLine.fromJson({
      'product_name': 'Mocha',
      'meal_id': 9,
      'display_name': 'Mocha meal',
      'display_name_ar': 'موكا وجبة',
      'qty': 1,
      'unit_price_baisas': 3000,
      'line_discount_baisas': 0,
      'line_total_baisas': 3000,
    });
    expect(line.displayLabel(arabic: false), 'Mocha meal');
    expect(line.displayLabel(arabic: true), 'موكا وجبة');
    final plain = QrRoundDisplayLine.fromJson({
      'product_name': 'Mocha',
      'product_name_ar': 'موكا',
      'qty': 1,
      'unit_price_baisas': 1800,
      'line_discount_baisas': 0,
      'line_total_baisas': 1800,
    });
    expect(plain.displayLabel(arabic: true), 'موكا');
  });
}
