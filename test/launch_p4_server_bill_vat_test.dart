import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/order_workspace/current_order_workspace.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/display_strings.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P4 device check (T3, Kaldi: prices include VAT, Vat 5%, an auto
/// 10% "national day" discount):
///  1. a table's estimate for a round awaiting confirmation follows the
///     server's quote — discount applied, VAT inside, never added on top;
///  2. server bills label the tax like local carts ("Vat (5%)") with the
///     "Prices include VAT" note, Arabic too;
///  minor: a sold-out tile shows no "+".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vat = CompanyTax(name: 'Vat', nameAr: 'ضريبة القيمة المضافة', ratePercent: 5);

  setUp(() {
    activeCompanyTaxes = const [vat];
    activeTaxSettings = const CompanyTaxSettings(
      vatRegistered: true,
      pricesIncludeVat: true,
    );
  });
  tearDown(() {
    activeCompanyTaxes = const <CompanyTax>[];
    activeTaxSettings = CompanyTaxSettings.legacy;
  });

  /// One pending QR round as the server's table detail lists it: a 2.500
  /// line with its 0.250 discount, tax 0.107 inside, total 2.250.
  const pendingLine = <String, dynamic>{
    'product_id': 11,
    'product_name': 'Latte',
    'qty': 1,
    'unit_price_baisas': 2500,
    'line_discount_baisas': 250,
    'line_total_baisas': 2500,
    'pending_round_id': 7,
  };

  CurrentOrderWorkspace tableWorkspace({Map<String, dynamic>? bill}) {
    final ws = CurrentOrderWorkspace(
      onExit: () {},
      mainCart: true,
      tableLabel: 'T4',
    );
    addTearDown(ws.dispose);
    if (bill != null) ws.bill = WorkspaceBill(bill);
    return ws;
  }

  group('1. the pending round estimate', () {
    test('uses the server quote: discount applied, VAT inside', () {
      final ws = tableWorkspace()
        ..cartControls = const WorkspaceCartControls(
          pendingRows: [pendingLine],
          pendingTax: 107,
          pendingSubtotal: 2500,
          pendingTotal: 2250,
        );
      final bill = ws.cartBill!;
      expect(bill.subtotal, 2500);
      expect(bill.discount, 250);
      expect(bill.tax, 107);
      expect(bill.total, 2250); // was 2607: tax added on top, no discount
      expect(bill.pricesIncludeTax, isTrue);
      expect(bill.discountRows.single.amountBaisas, 250);
    });

    test('without a quote the lines still give the same estimate', () {
      final ws = tableWorkspace()
        ..cartControls = const WorkspaceCartControls(
          pendingRows: [pendingLine],
          pendingTax: 107,
        );
      final bill = ws.cartBill!;
      expect(bill.discount, 250);
      expect(bill.total, 2250);
    });

    test('a saved inclusive bill plus a pending round', () {
      final ws =
          tableWorkspace(
              bill: {
                'uuid': 'bill-1',
                'subtotal_baisas': 1000,
                'discount_total_baisas': 100,
                'tax_total_baisas': 43,
                'grand_total_baisas': 900,
                'prices_include_tax': true,
                'items': [
                  {
                    'id': 1,
                    'product_name': 'Tea',
                    'qty': 1,
                    'line_total_baisas': 1000,
                  },
                ],
              },
            )
            ..cartControls = const WorkspaceCartControls(
              pendingRows: [pendingLine],
              pendingTax: 107,
              pendingSubtotal: 2500,
              pendingTotal: 2250,
            );
      final bill = ws.cartBill!;
      expect(bill.subtotal, 3500);
      expect(bill.discount, 350);
      expect(bill.tax, 150);
      expect(bill.total, 3150);
    });

    test('an exclusive merchant keeps the tax on top of the quote', () {
      activeTaxSettings = const CompanyTaxSettings(
        vatRegistered: true,
        pricesIncludeVat: false,
      );
      final ws = tableWorkspace()
        ..cartControls = const WorkspaceCartControls(
          pendingRows: [pendingLine],
          pendingTax: 113,
          pendingSubtotal: 2500,
          pendingTotal: 2363,
        );
      final bill = ws.cartBill!;
      expect(bill.pricesIncludeTax, isFalse);
      expect(bill.discount, 250);
      expect(bill.total, 2363);
    });
  });

  group('2. server bill tax rows', () {
    Map<String, dynamic> confirmed({bool inclusive = true}) => {
      'uuid': 'bill-2',
      'subtotal_baisas': 2500,
      'discount_total_baisas': 250,
      'tax_total_baisas': 107,
      'grand_total_baisas': 2250,
      'prices_include_tax': inclusive,
      'items': [
        {'id': 3, 'product_name': 'Latte', 'qty': 1, 'line_total_baisas': 2500},
      ],
    };

    test('one tax names itself with its rate; the bill is inclusive', () {
      final bill = WorkspaceBill(confirmed());
      expect(bill.pricesIncludeTax, isTrue);
      final row = bill.taxLines.single;
      expect('${row.displayName(false)} (${row.rateLabel}%)', 'Vat (5%)');
      expect(
        '${row.displayName(true)} (${row.rateLabel}%)',
        'ضريبة القيمة المضافة (5%)',
      );
      expect(row.amount, closeTo(0.107, 1e-9));
    });

    test('two taxes split exactly, else one plain row', () {
      final split = serverBillTaxLines(
        taxBaisas: 97,
        grandBaisas: 1110,
        pricesIncludeTax: true,
        taxes: const [
          CompanyTax(name: 'VAT', ratePercent: 5),
          CompanyTax(name: 'Tourism', ratePercent: 4.5),
        ],
      );
      expect(split.map((l) => l.name), ['VAT', 'Tourism']);
      expect(split.map((l) => l.amount), [0.051, 0.046]);
      final plain = serverBillTaxLines(
        taxBaisas: 99,
        grandBaisas: 1110,
        pricesIncludeTax: true,
        taxes: const [
          CompanyTax(name: 'VAT', ratePercent: 5),
          CompanyTax(name: 'Tourism', ratePercent: 4.5),
        ],
      );
      expect(plain.single.name, isEmpty);
      expect(plain.single.amount, closeTo(0.099, 1e-9));
      expect(
        serverBillTaxLines(
          taxBaisas: 0,
          grandBaisas: 1000,
          pricesIncludeTax: true,
        ),
        isEmpty,
      );
    });

    test('the customer display gets the same rows', () {
      final display = WorkspaceBill(confirmed()).cartDisplay(stale: false);
      expect(display['pricesIncludeTax'], isTrue);
      final order = OrderSnapshot.fromMap(display);
      expect(
        customerTaxRows(order, arabic: false, fallbackLabel: 'Tax').single.label,
        'Vat (5%)',
      );
    });
  });

  group('on the real screen', () {
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      messenger.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      messenger.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    for (final arabic in [false, true]) {
      testWidgets('a confirmed server bill reads like the cart (${arabic ? 'AR' : 'EN'})', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1600, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await pumpWorkspaceMachine(
          tester,
          mode: 'live',
          toggle: false,
          arabic: arabic,
          catalog: const CatalogSnapshot(
            categories: ['Coffee'],
            products: [
              Product(id: '11', name: 'Latte', category: 'Coffee', price: 2.5),
            ],
            floors: [],
            tables: [],
            taxes: [vat],
            companyTax: CompanyTaxSettings(
              vatRegistered: true,
              pricesIncludeVat: true,
            ),
          ),
        );
        final dynamic staff = tester.state(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == 'StaffPosScreen',
          ),
        );
        staff.openServerWorkspace(
          (CurrentOrderWorkspace w) => _PublishBill(w, {
            'uuid': 'bill-2',
            'status': 'open',
            'subtotal_baisas': 2500,
            'discount_total_baisas': 250,
            'tax_total_baisas': 107,
            'grand_total_baisas': 2250,
            'prices_include_tax': true,
            'items': [
              {
                'id': 3,
                'product_id': 11,
                'product_name': 'Latte',
                'qty': 1,
                'line_total_baisas': 2500,
              },
            ],
          }),
          quick: true,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(arabic ? 'ضريبة القيمة المضافة (5%)' : 'Vat (5%)'),
          findsWidgets,
        );
        expect(
          find.byKey(const ValueKey('bill-prices-include-vat')),
          findsOneWidget,
        );
        await disposeWorkspaceMachine(tester);
      });
    }

    testWidgets('a sold-out tile shows no "+"', (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [
            Product(id: '10', name: 'Latte', category: 'Coffee', price: 1.5),
            Product(
              id: '11',
              name: 'Cake',
              category: 'Coffee',
              price: 2,
              soldOut: true,
            ),
          ],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      expect(find.byKey(const ValueKey('product-add-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('product-add-11')), findsNothing);
      await disposeWorkspaceMachine(tester);
    });
  });
}

/// A stand-in server editor: publishes one bill into the main cart.
class _PublishBill extends StatefulWidget {
  const _PublishBill(this.workspace, this.order);
  final CurrentOrderWorkspace workspace;
  final Map<String, dynamic> order;
  @override
  State<_PublishBill> createState() => _PublishBillState();
}

class _PublishBillState extends State<_PublishBill> {
  @override
  void initState() {
    super.initState();
    widget.workspace.attach(
      this,
      pick: (_) async {},
      leave: () async {},
      pay: () async {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.workspace.publish(
        this,
        order: widget.order,
        stale: false,
        canAdd: false,
        canPay: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
