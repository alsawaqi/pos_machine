import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/order_sync_payload.dart';
import 'package:pos_machine/state/pos_controller.dart';
import 'support/fake_order_storage.dart';

/// LAUNCH-P4 C8 — VAT on the till: the merchant's `company.tax` setup,
/// inclusive pricing through mithqal_pricing v0.3.0, the held-order card's
/// priced tax (L2), Arabic tax names one line per tax (L3), and deleted taxes
/// purging on a delta (H10).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const latte = Product(id: '11', name: 'Latte', category: 'Coffee', price: 1.050);
  const vat = CompanyTax(
    name: 'VAT',
    nameAr: 'ضريبة القيمة المضافة',
    ratePercent: 5,
  );

  tearDown(() {
    activeCompanyTaxes = const <CompanyTax>[];
    activeTaxSettings = CompanyTaxSettings.legacy;
  });

  PosController build(CompanyTaxSettings tax, {List<CompanyTax>? taxes}) {
    final c = PosController(orderStorage: FakeOrderStorage());
    c.applyCatalog(
      categories: const ['Coffee'],
      products: const [latte],
      floors: const <DiningFloor>[],
      tables: const <DiningTableDefinition>[],
      taxes: taxes ?? const [vat],
      companyTax: tax,
      branchId: 3,
    );
    addTearDown(c.dispose);
    return c;
  }

  group('company.tax', () {
    test('parse -> cache -> catalog carries the VAT setup', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'company': {
          'tax': {
            'vat_registered': true,
            'prices_include_vat': true,
            'vat_number': 'OM1100223344',
          },
        },
        'taxes': [
          {'id': 1, 'name': 'VAT', 'name_ar': 'ضريبة القيمة المضافة', 'rate_percent': 5},
        ],
        'meta': {'company_id': 1, 'branch_id': 3},
        'branch': {'id': 3, 'name': 'Main'},
      });
      await db.replaceConfig(
        branch: parsed.branch,
        categoryRows: parsed.categories,
        productRows: parsed.products,
        floorRows: parsed.floors,
        tableRows: parsed.tables,
        addonGroupRows: parsed.addonGroups,
        addonRows: parsed.addons,
        taxRows: parsed.taxes,
        deliveryProviderRows: parsed.deliveryProviders,
        expenseCategoryRows: parsed.expenseCategories,
        branchIngredientStockRows: parsed.branchIngredientStock,
        discountRows: parsed.discounts,
        loyaltyRuleRows: parsed.loyaltyRules,
        customerRows: parsed.customers,
        ingredientRows: parsed.ingredients,
        meta: parsed.meta,
      );
      final meta = await db.getSyncMeta();
      final catalog = ConfigMapper.toCatalog(
        await db.getBranch(),
        const [],
        const [],
        const [],
        const [],
        await db.getTaxes(),
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        meta,
      );
      expect(catalog.companyTax.isRegistered, isTrue);
      expect(catalog.companyTax.pricesIncludeTax, isTrue);
      expect(catalog.companyTax.printableVatNumber, 'OM1100223344');
      expect(catalog.taxes.single.nameAr, 'ضريبة القيمة المضافة');
    });

    test('a merchant that is not VAT-registered gets no taxes at all', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const [],
        const [],
        const [],
        const [],
        const [TaxRow(id: 1, name: 'VAT', ratePercent: 5)],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const [],
        const SyncMetaRow(
          id: 1,
          companyTaxJson: '{"vat_registered":false,"prices_include_vat":true}',
        ),
      );
      expect(catalog.taxes, isEmpty);
      expect(catalog.companyTax.forbidsTax, isTrue);
      expect(catalog.companyTax.pricesIncludeTax, isFalse);
    });

    test('a registered merchant defaults to prices including VAT', () {
      final settings = CompanyTaxSettings.fromJson(const {
        'vat_registered': true,
      });
      expect(settings.pricesIncludeTax, isTrue);
      expect(CompanyTaxSettings.fromJson(null).vatRegistered, isNull);
    });
  });

  group('inclusive pricing on the till', () {
    test('the VAT is inside the price: total = gross, tax taken out', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: true),
      );
      c.addProduct(latte);
      c.addProduct(latte);
      expect(c.subtotal, closeTo(2.100, 1e-9));
      expect(c.tax, closeTo(0.100, 1e-9)); // round(2100 x 5 / 105)
      expect(c.total, closeTo(2.100, 1e-9));
    });

    test('exclusive merchants keep VAT on top', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: false),
      );
      c.addProduct(latte);
      expect(c.tax, closeTo(0.053, 1e-9)); // round(52.5) = 53
      expect(c.total, closeTo(1.103, 1e-9));
    });

    test('unregistered: no VAT even when tax rows are passed', () {
      final c = build(const CompanyTaxSettings(vatRegistered: false));
      c.addProduct(latte);
      expect(c.taxLines, isEmpty);
      expect(c.tax, 0);
      expect(c.total, closeTo(1.050, 1e-9));
    });

    test('the snapshot freezes the inclusive flag and AR/EN tax lines', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: true),
      );
      c.addProduct(latte);
      final snap = c.snapshot();
      expect(snap.pricesIncludeTax, isTrue);
      expect(snap.taxLines, hasLength(1));
      expect(snap.taxLines.single['name'], 'VAT');
      expect(snap.taxLines.single['nameAr'], 'ضريبة القيمة المضافة');
      expect(snap.taxLines.single['amount'], closeTo(0.050, 1e-9));
      // Survives storage.
      final back = OrderSnapshot.fromMap(snap.toMap());
      expect(back.pricesIncludeTax, isTrue);
      expect(back.taxLines.single['nameAr'], 'ضريبة القيمة المضافة');
    });

    test('order.create stamps prices_include_tax with the inner VAT', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: true),
      );
      c.addProduct(latte);
      final payload = buildOrderSyncPayload(c.snapshot());
      final order = (payload.events.first['payload'] as Map)['order'] as Map;
      expect(order['prices_include_tax'], isTrue);
      expect(order['subtotal_baisas'], 1050);
      expect(order['tax_total_baisas'], 50);
      expect(order['grand_total_baisas'], 1050);
    });

    test('exclusive orders do not send prices_include_tax', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: false),
      );
      c.addProduct(latte);
      final event = buildOrderSyncPayload(c.snapshot()).events.first;
      final order = (event['payload'] as Map)['order'] as Map;
      expect(order.containsKey('prices_include_tax'), isFalse);
      expect(order['grand_total_baisas'], 1103);
    });
  });

  group('L3 — Arabic tax names, one line per tax', () {
    test('cart tax lines keep the Arabic name', () {
      final c = build(
        const CompanyTaxSettings(vatRegistered: true, pricesIncludeVat: false),
        taxes: const [
          vat,
          CompanyTax(name: 'Tourism', nameAr: 'السياحة', ratePercent: 4),
        ],
      );
      c.addProduct(latte);
      expect(c.taxLines, hasLength(2));
      expect(c.taxLines.first.displayName(true), 'ضريبة القيمة المضافة');
      expect(c.taxLines.first.displayName(false), 'VAT');
      expect(c.taxLines.last.displayName(true), 'السياحة');
    });
  });

  group('L2 — held order cards use the priced tax', () {
    HeldOrderRecord held(OrderType type) => HeldOrderRecord(
      id: 'h1',
      orderReference: 'REF-1',
      orderType: type,
      heldAt: DateTime(2026, 10, 3, 12),
      draft: OrderSessionDraft(
        orderReference: 'REF-1',
        orderType: type,
        selectedCategory: 'Coffee',
        customerReferenceNumber: '',
        items: [CartItem(product: latte, qty: 2)],
        discount: const DiscountConfiguration(),
        splitCount: 1,
      ),
    );

    test('a 10% tax is not shown as 5%', () {
      activeTaxSettings = const CompanyTaxSettings(vatRegistered: true);
      activeCompanyTaxes = const [CompanyTax(name: 'VAT', ratePercent: 10)];
      expect(held(OrderType.quickOrder).displayTotal, closeTo(2.310, 1e-9));
    });

    test('VAT-inclusive held orders total the gross', () {
      activeTaxSettings = const CompanyTaxSettings(
        vatRegistered: true,
        pricesIncludeVat: true,
      );
      activeCompanyTaxes = const [vat];
      expect(held(OrderType.quickOrder).displayTotal, closeTo(2.100, 1e-9));
    });

    test('delivery held orders carry no tax', () {
      activeTaxSettings = const CompanyTaxSettings(vatRegistered: true);
      activeCompanyTaxes = const [vat];
      expect(held(OrderType.delivery).displayTotal, closeTo(2.100, 1e-9));
    });
  });

  test('H10 — a delta that deletes a tax purges it from the cache', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.taxCache).insert(
      const TaxCacheCompanion(
        id: Value(1),
        name: Value('VAT'),
        ratePercent: Value(5),
      ),
    );
    final delta = ConfigMapper.parseDelta(<String, dynamic>{
      'deleted': {
        'taxes': [1],
        'void_reasons': [7],
        'comp_reasons': [8],
      },
    });
    expect(delta.deleted.taxes, [1]);
    expect(delta.deleted.voidReasons, [7]);
    expect(delta.deleted.compReasons, [8]);
    await db.applyDelta(
      hasBranch: false,
      branch: delta.changed.branch,
      categoryRows: const [],
      productRows: const [],
      floorRows: const [],
      tableRows: const [],
      addonGroupRows: const [],
      addonRows: const [],
      taxRows: const [],
      deliveryProviderRows: const [],
      expenseCategoryRows: const [],
      branchIngredientStockRows: const [],
      discountRows: const [],
      loyaltyRuleRows: const [],
      customerRows: const [],
      ingredientRows: const [],
      deletedCategoryIds: const [],
      deletedProductIds: const [],
      deletedFloorIds: const [],
      deletedTableIds: const [],
      deletedAddonGroupIds: const [],
      deletedAddonIds: const [],
      deletedIngredientIds: const [],
      deletedDiscountIds: const [],
      deletedLoyaltyRuleIds: const [],
      deletedCustomerIds: const [],
      deletedDeliveryProviderIds: const [],
      deletedExpenseCategoryIds: const [],
      deletedTaxIds: delta.deleted.taxes,
      deletedVoidReasonIds: delta.deleted.voidReasons,
      deletedCompReasonIds: delta.deleted.compReasons,
      cursor: 'c2',
      now: DateTime(2026, 10, 3),
    );
    expect(await db.getTaxes(), isEmpty);
  });

  test('Drift 29 to 30 keeps cached products and adds the P4 columns', () async {
    final db = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
              name_ar TEXT, category_id INTEGER,
              base_price_baisas INTEGER NOT NULL DEFAULT 0,
              branch_stock_qty REAL, image_url TEXT, status TEXT,
              addon_group_ids TEXT NOT NULL DEFAULT '',
              delivery_price_baisas INTEGER,
              delivery_prices_json TEXT NOT NULL DEFAULT '{}',
              stock_mode TEXT, recipe_json TEXT NOT NULL DEFAULT '[]',
              available_from TEXT, available_until TEXT
            )
          ''');
          raw.execute('''
            CREATE TABLE categories (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
              name_ar TEXT, display_order INTEGER NOT NULL DEFAULT 0,
              status TEXT, addon_group_ids_json TEXT NOT NULL DEFAULT '[]'
            )
          ''');
          raw.execute('''
            CREATE TABLE addon_groups (
              id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT '',
              name_ar TEXT, selection_mode TEXT, min_selections INTEGER,
              max_selections INTEGER, status TEXT
            )
          ''');
          raw.execute('''
            CREATE TABLE sync_meta (
              id INTEGER PRIMARY KEY DEFAULT 1, company_id INTEGER,
              branch_id INTEGER, last_config_sync_at INTEGER,
              config_schema_version TEXT, order_cancel_positions TEXT,
              reports_positions TEXT, kitchen_positions TEXT,
              order_numbering_json TEXT, table_sessions_mode TEXT
            )
          ''');
          raw.execute(
            "INSERT INTO products (id, name, base_price_baisas) VALUES (5, 'Tea', 700)",
          );
          raw.execute('PRAGMA user_version = 29');
        },
      ),
    );
    addTearDown(db.close);
    final rows = await db.select(db.products).get();
    expect(db.schemaVersion, 33);
    expect(rows.single.name, 'Tea');
    expect(rows.single.soldInStore, isTrue);
    expect(rows.single.soldOut, isFalse);
    expect(rows.single.productType, 'standard');
    expect((await db.getSyncMeta())?.companyTaxJson, isNull);
  });
}
