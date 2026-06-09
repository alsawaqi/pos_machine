import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// Per-branch custom receipt template: parsed from /device/config
/// `branch.receipt_template`, cached on the branch row, decoded into the
/// catalog, and handed to PosController for SunmiReceiptService.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptTemplate.fromJson', () {
    test('parses fields, trims strings, and drops blank lines', () {
      final t = ReceiptTemplate.fromJson(<String, dynamic>{
        'business_name': '  Aroma Cafe ',
        'business_name_ar': 'مقهى أروما',
        'cr_number': 'CR-12345',
        'vat_number': 'OM100200300',
        'address': 'Al Khuwair',
        'phone': '+968 9000 0000',
        'header_lines': ['Welcome', '   ', 'Dine-in'],
        'footer_lines': ['Thank you', ''],
        'show_qr': false,
      })!;

      expect(t.businessName, 'Aroma Cafe');
      expect(t.businessNameAr, 'مقهى أروما');
      expect(t.crNumber, 'CR-12345');
      expect(t.vatNumber, 'OM100200300');
      expect(t.headerLines, ['Welcome', 'Dine-in']);
      expect(t.footerLines, ['Thank you']);
      expect(t.showQr, isFalse);
      expect(t.isEmpty, isFalse);
    });

    test('returns null for a null map', () {
      expect(ReceiptTemplate.fromJson(null), isNull);
    });

    test('defaults show_qr to true and reports isEmpty for a blank template', () {
      final t = ReceiptTemplate.fromJson(<String, dynamic>{
        'business_name': '',
        'header_lines': <String>[],
      })!;
      expect(t.showQr, isTrue);
      expect(t.businessName, isNull);
      expect(t.isEmpty, isTrue);
    });
  });

  group('config mapper', () {
    test('parse caches the receipt_template JSON on the branch row', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{
        'branch': {
          'id': 10,
          'name': 'Main',
          'receipt_template': {'cr_number': 'CR-99', 'show_qr': true},
        },
      });

      expect(cfg.branch.receiptTemplateJson.value, contains('CR-99'));
    });

    test('parse leaves the template null when the branch has none', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{
        'branch': {'id': 10, 'name': 'Main'},
      });
      expect(cfg.branch.receiptTemplateJson.value, isNull);
    });

    test('toCatalog decodes the cached template into the snapshot', () {
      final branch = BranchRow(
        id: 10,
        name: 'Main',
        receiptTemplateJson: '{"business_name":"Aroma Cafe","cr_number":"CR-12345"}',
      );
      final snap = ConfigMapper.toCatalog(
        branch, const [], const [], const [], const [], const [],
      );

      expect(snap.receiptTemplate, isNotNull);
      expect(snap.receiptTemplate!.businessName, 'Aroma Cafe');
      expect(snap.receiptTemplate!.crNumber, 'CR-12345');
    });

    test('toCatalog yields a null template when none is cached', () {
      final snap = ConfigMapper.toCatalog(
        BranchRow(id: 10, name: 'Main'), const [], const [], const [], const [], const [],
      );
      expect(snap.receiptTemplate, isNull);
    });
  });

  group('PosController', () {
    test('applyCatalog stores the receipt template', () {
      final c = PosController();
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        receiptTemplate: const ReceiptTemplate(businessName: 'Aroma Cafe'),
      );

      expect(c.receiptTemplate, isNotNull);
      expect(c.receiptTemplate!.businessName, 'Aroma Cafe');
    });
  });
}
