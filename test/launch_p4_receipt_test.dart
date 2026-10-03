import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/receipt_layout.dart';
import 'package:pos_machine/services/receipt_renderer.dart';
import 'package:pos_machine/services/sunmi_receipt_service.dart';

/// LAUNCH-P4 C2 — the bilingual receipt: title by VAT registration, the VAT
/// number from company.tax, Muscat date and time, Arabic item names, add-ons
/// and combo components, one AR/EN line per tax, "Prices include VAT", no QR
/// code, and Arabic drawn as a shaped bitmap (the printer's text API cannot
/// shape it). The golden image is reviewed on the T3 by the tester.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final at = DateTime.utc(2026, 10, 3, 8, 15); // 12:15 in Muscat

  const template = ReceiptTemplate(
    businessName: 'Qahwa House',
    businessNameAr: 'بيت القهوة',
    crNumber: '1234567',
    vatNumber: 'TEMPLATE-VAT',
    phone: '+968 9000 0000',
    footerLines: ['Thank you / شكراً لكم'],
  );
  const registered = CompanyTaxSettings(
    vatRegistered: true,
    pricesIncludeVat: true,
    vatNumber: 'OM1100223344',
  );

  OrderSnapshot order({
    bool inclusive = true,
    bool withTax = true,
    String orderType = 'quick_order',
  }) => OrderSnapshot.initial().copyWith(
    orderNumber: 1452,
    receiptNumber: 'QH-0042',
    orderType: orderType,
    items: [
      CartItem(
        product: const Product(
          id: '10',
          name: 'Latte',
          nameAr: 'لاتيه',
          category: 'Coffee',
          price: 1.500,
        ),
        modifiers: const [
          CartItemModifier(
            id: '52',
            group: 'Size',
            label: 'Large',
            labelAr: 'كبير',
            price: 0.200,
          ),
        ],
      ).toMap(),
      CartItem(
        product: const Product(
          id: '20',
          name: 'Burger meal',
          nameAr: 'وجبة برجر',
          category: 'Food',
          price: 3.500,
          productType: 'combo',
        ),
        components: const [
          ComboComponent(
            slotId: 6,
            productId: '33',
            name: 'Chicken burger',
            nameAr: 'برجر دجاج',
            extraPrice: 0.300,
          ),
          ComboComponent(slotId: 7, productId: '31', name: 'Fries', nameAr: 'بطاطس'),
        ],
      ).toMap(),
    ],
    rawSubtotal: 5.500,
    subtotal: 5.500,
    tax: withTax ? 0.262 : 0,
    pricesIncludeTax: inclusive,
    taxLines: withTax
        ? const [
            {
              'name': 'VAT',
              'nameAr': 'ضريبة القيمة المضافة',
              'ratePercent': 5.0,
              'amount': 0.262,
            },
          ]
        : const [],
    total: 5.500,
    activePaymentBaseTotal: 5.500,
    payableTotal: 5.500,
    paymentStatus: 'Paid',
    paymentMethod: 'Cash',
  );

  List<String> texts(List<ReceiptLine> lines) => [
    for (final l in lines) stripIsolates(l.toString()),
  ];

  group('layout', () {
    test('a VAT-registered, VAT-inclusive receipt', () {
      final lines = buildReceiptLines(
        order(),
        header: const ReceiptHeader(
          template: template,
          tax: registered,
          branchName: 'Al Khuwair',
          branchNameAr: 'الخوير',
        ),
        at: at,
      );
      final t = texts(lines);
      expect(t, contains('Qahwa House'));
      expect(t, contains('بيت القهوة'));
      expect(t, contains('Al Khuwair · الخوير'));
      expect(t, contains('CR No. / رقم السجل التجاري: 1234567'));
      // The company record's number, not the template's.
      expect(t, contains('VAT No. / الرقم الضريبي: OM1100223344'));
      expect(t.join('\n'), isNot(contains('TEMPLATE-VAT')));
      expect(t, contains('Simplified tax invoice'));
      expect(t, contains('فاتورة ضريبية مبسطة'));
      expect(t, contains('Receipt No. / رقم الإيصال  QH-0042'));
      expect(t, contains('Date / التاريخ  03/10/2026'));
      expect(t, contains('Time / الوقت  12:15'));
      expect(t, contains('1 x Latte  1.700'));
      expect(t, contains('لاتيه'));
      expect(t, contains('+ Large / كبير (+0.200)'));
      expect(t, contains('1 x Burger meal  3.800'));
      expect(t, contains('> Chicken burger / برجر دجاج (+0.300)'));
      expect(t, contains('> Fries / بطاطس'));
      expect(
        t,
        contains('VAT 5% / ضريبة القيمة المضافة  0.262'),
      );
      expect(t, contains('Prices include VAT / الأسعار شاملة الضريبة'));
      expect(t, contains('TOTAL / الإجمالي  5.500 OMR'));
      expect(t, contains('Payment / طريقة الدفع  Cash / نقدي'));
      expect(t, contains('Thank you / شكراً لكم'));
      expect(t.join('\n'), isNot(contains('MITHQAL|TOTAL')));
    });

    test('not VAT-registered: "Receipt", no VAT number, no tax lines', () {
      final t = texts(
        buildReceiptLines(
          order(inclusive: false, withTax: false),
          header: const ReceiptHeader(
            template: template,
            tax: CompanyTaxSettings(vatRegistered: false),
          ),
          at: at,
        ),
      );
      expect(t, contains('Receipt'));
      expect(t, contains('إيصال'));
      expect(t.join('\n'), isNot(contains('VAT')));
      expect(t.join('\n'), isNot(contains('الضريبة')));
    });

    test('a delivery order prints no tax lines', () {
      final t = texts(
        buildReceiptLines(
          order(withTax: false, orderType: 'delivery'),
          header: const ReceiptHeader(template: template, tax: registered),
          at: at,
        ),
      );
      expect(t, contains('Delivery / توصيل'));
      expect(t.join('\n'), isNot(contains('VAT 5%')));
      expect(t.join('\n'), isNot(contains('Prices include VAT')));
    });

    test('a pre-P4 server (no company.tax) keeps the template VAT number', () {
      final t = texts(
        buildReceiptLines(
          order(inclusive: false),
          header: const ReceiptHeader(template: template),
          at: at,
        ),
      );
      expect(t, contains('VAT No. / الرقم الضريبي: TEMPLATE-VAT'));
      expect(t, contains('Receipt'));
      expect(t, contains('إيصال'));
    });
  });

  group('printing', () {
    final calls = <MethodCall>[];
    const channel = MethodChannel('sunmi_printer_plus');
    setUp(() {
      calls.clear();
      SunmiReceiptService.debugPaperWidth = kReceipt58mmWidth;
      SunmiReceiptService.debugUseBitmap = true; // the device path
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      SunmiReceiptService.debugPaperWidth = null;
      SunmiReceiptService.debugUseBitmap = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('the receipt prints as a bitmap and never as a QR code', (
      tester,
    ) async {
      late bool ok;
      await tester.runAsync(() async {
        ok = await SunmiReceiptService.printReceipt(
          order(),
          template: template,
          tax: registered,
          at: at,
        );
      });
      expect(ok, isTrue);
      final methods = calls.map((c) => c.method).toList();
      expect(methods, contains('printImage'));
      expect(methods, isNot(contains('printQrcode')));
      expect(methods, isNot(contains('printText')));
      expect(methods.last, 'cutPaper');
      final png = (calls.firstWhere((c) => c.method == 'printImage').arguments
          as Map)['image'] as Uint8List;
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
    });

    test('off the Sunmi device the same lines print as text, no QR', () async {
      SunmiReceiptService.debugUseBitmap = false;
      final ok = await SunmiReceiptService.printReceipt(
        order(),
        template: template,
        tax: registered,
        at: at,
      );
      expect(ok, isTrue);
      final methods = calls.map((c) => c.method).toList();
      expect(methods, isNot(contains('printImage')));
      expect(methods, isNot(contains('printQrcode')));
      final printed = calls
          .where((c) => c.method == 'printText')
          .map((c) => ((c.arguments as Map)['data'] as Map)['text'].toString())
          .join('\n');
      expect(printed, contains('Simplified tax invoice'));
      expect(printed, contains('TOTAL / الإجمالي'));
      expect(printed, isNot(contains(String.fromCharCode(0x2067))));
    });
  });

  group('the bitmap', () {
    setUpAll(() async {
      for (final family in {
        'ReceiptLatin': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
        'ReceiptArabic': [
          'NotoNaskhArabic-Regular.ttf',
          'NotoNaskhArabic-Bold.ttf',
        ],
      }.entries) {
        final loader = FontLoader(family.key);
        for (final file in family.value) {
          final bytes = File('test/fixtures/fonts/$file').readAsBytesSync();
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
        }
        await loader.load();
      }
    });

    const options = ReceiptRenderOptions(
      width: kReceipt58mmWidth,
      fontFamily: 'ReceiptLatin',
      fontFamilyFallback: ['ReceiptArabic'],
    );

    test('Arabic is shaped: a joined word is narrower than its letters', () {
      double width(String text) {
        final p = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(
              fontSize: 21,
              fontFamily: 'ReceiptLatin',
              fontFamilyFallback: ['ReceiptArabic'],
            ),
          ),
          textDirection: TextDirection.rtl,
        )..layout();
        return p.width;
      }

      const word = 'ضريبة';
      final joined = width(word);
      final isolated = word.runes
          .map((r) => width(String.fromCharCode(r)))
          .fold<double>(0, (a, b) => a + b);
      expect(joined, lessThan(isolated * 0.9));
    });

    testWidgets('golden: VAT-inclusive Arabic + English receipt (58 mm)', (
      tester,
    ) async {
      final lines = buildReceiptLines(
        order(),
        header: const ReceiptHeader(
          template: template,
          tax: registered,
          branchName: 'Al Khuwair',
          branchNameAr: 'الخوير',
        ),
        at: at,
      );
      late ui.Image image;
      await tester.runAsync(() async {
        image = await renderReceiptImage(lines, options: options);
      });
      expect(image.width, kReceipt58mmWidth);
      await expectLater(
        image,
        matchesGoldenFile('goldens/receipt_vat_inclusive_ar_en_58mm.png'),
      );
    });

    testWidgets('long receipts split into printable strips', (tester) async {
      final many = order().copyWith(
        items: [for (var i = 0; i < 60; i++) ...order().items],
      );
      late List<Uint8List> strips;
      await tester.runAsync(() async {
        strips = await renderReceiptPngStrips(
          buildReceiptLines(
            many,
            header: const ReceiptHeader(tax: registered),
            at: at,
          ),
          options: options,
          maxStripHeight: 800,
        );
      });
      expect(strips.length, greaterThan(2));
    });
  });
}
