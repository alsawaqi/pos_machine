import 'dart:convert';
import 'dart:io';

// Test-only integrity check; crypto is already present in the machine's lock.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_pricing/mithqal_pricing.dart' as core;
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/pricing_adapter.dart';

const _v030GoldenCorpusSha256 =
    '37d2741c0e7a801e6ffb9aef0ae6bbaeb9b13ed4f18201898e13c98d3f772d4f';

void main() {
  final packageRoot = _mithqalPackageRoot;

  test(
    'mithqal_pricing v0.3.0 dependency contains the pinned 39-vector corpus',
    () async {
      final root = await packageRoot();
      final files = _goldenFiles(root);

      expect(files, hasLength(39));
      expect(
        File(
          '${root.path}${Platform.pathSeparator}pubspec.yaml',
        ).readAsStringSync(),
        contains(RegExp(r'^version:\s*0\.3\.0\s*$', multiLine: true)),
      );

      final manifestFile = File(
        '${root.path}${Platform.pathSeparator}goldens.sha256',
      );
      expect(manifestFile.existsSync(), isTrue);
      final existing = manifestFile.readAsStringSync().replaceAll('\r\n', '\n');
      final manifestLines = const LineSplitter()
          .convert(existing)
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      expect(manifestLines, hasLength(40));
      expect(manifestLines.last, 'TOTAL $_v030GoldenCorpusSha256');

      final calculatedLines = <String>[];
      for (final file in files) {
        final normalized = file.readAsStringSync().replaceAll('\r\n', '\n');
        calculatedLines.add(
          '${sha256.convert(utf8.encode(normalized))}  ${_basename(file)}',
        );
      }
      final calculatedBody = calculatedLines.map((line) => '$line\n').join();
      calculatedLines.add(
        'TOTAL ${sha256.convert(utf8.encode(calculatedBody))}',
      );
      expect(existing, '${calculatedLines.join('\n')}\n');
    },
  );

  test(
    'all 38 price vectors (6 VAT-inclusive) cross machine models and the production adapter',
    () async {
      final root = await packageRoot();
      final vectors = <({File file, Map<String, dynamic> json})>[];
      for (final file in _goldenFiles(root)) {
        final json = _map(jsonDecode(file.readAsStringSync()));
        if (json['kind'] != 'split') vectors.add((file: file, json: json));
      }
      expect(vectors, hasLength(38));

      final percentageSelection = pricingOrderDiscountFromMachine(
        discount: const DiscountConfiguration(
          kind: DiscountKind.percentage,
          value: 7.5,
          label: 'loyalty-carry',
          discountId: 91,
          reason: 'adapter-contract',
        ),
        loyaltyRuleId: 17,
        loyaltyPoints: 250,
        loyaltyStamps: 4,
      );
      expect(percentageSelection.loyaltyRuleId, 17);
      expect(percentageSelection.loyaltyPoints, 250);
      expect(percentageSelection.loyaltyStamps, 4);

      final originalTaxes = activeCompanyTaxes;
      final originalSettings = activeTaxSettings;
      try {
        for (final vector in vectors) {
          final name =
              vector.json['name']?.toString() ?? _basename(vector.file);
          final inputJson = _map(vector.json['input']);
          final expected = _map(vector.json['expected']);
          final state = _GoldenMachineState.fromInput(inputJson);
          activeCompanyTaxes = _machineTaxes(inputJson);
          // LAUNCH-P4 — the merchant's "menu prices include VAT" switch rides
          // the machine's tax settings, exactly as /device/config sets it.
          activeTaxSettings = CompanyTaxSettings(
            vatRegistered: true,
            pricesIncludeVat: inputJson['pricesIncludeTax'] == true,
          );

          final now = DateTime.parse(inputJson['now'] as String);
          final adapted = buildPricingInput(state, now);
          _expectAdaptedInput(adapted, inputJson, vector: name);

          final result = core.priceOrder(adapted);
          _expectPriceResult(result, adapted, expected, vector: name);
        }
      } finally {
        activeCompanyTaxes = originalTaxes;
        activeTaxSettings = originalSettings;
      }
    },
  );

  test(
    'split_shares runs all 8 cases directly through core split helpers',
    () async {
      final root = await packageRoot();
      final splitFile = _goldenFiles(root).singleWhere((file) {
        final json = _map(jsonDecode(file.readAsStringSync()));
        return json['kind'] == 'split';
      });
      final split = _map(jsonDecode(splitFile.readAsStringSync()));
      final cases = _mapList(split['cases']);
      expect(cases, hasLength(8));

      // Split state is deliberately outside PricingInput: it is payment state
      // evaluated after grandTotalBaisas exists. These vectors therefore cannot
      // cross buildPricingInput and instead exercise the package's public split
      // boundary directly.
      for (final testCase in cases) {
        final name = testCase['case'] as String;
        if (testCase['equalShare'] != null) {
          final share = _map(testCase['equalShare']);
          expect(
            core.equalShareBaisas(_int(share['grand']), _int(share['count'])),
            share['expected'],
            reason: 'split_shares/$name',
          );
        }
        if (testCase['remainderShare'] != null) {
          final share = _map(testCase['remainderShare']);
          expect(
            core.remainderShareBaisas(
              _int(share['grand']),
              _int(share['paidBase']),
            ),
            share['expected'],
            reason: 'split_shares/$name',
          );
        }
        if (testCase['plan'] != null) {
          final plan = _map(testCase['plan']);
          final actual = core.validateSplitPlan(
            _intList(plan['shares']),
            _int(plan['grand']),
          );
          final expected = plan['expected'] == null
              ? null
              : _intList(plan['expected']);
          expect(actual, expected, reason: 'split_shares/$name');
          if (actual != null) {
            expect(
              core.splitPlanMatchesTotal(actual, _int(plan['grand'])),
              isTrue,
              reason: 'split_shares/$name closes to the exact total',
            );
          }
        }
      }
    },
  );
}

Future<Directory> _mithqalPackageRoot() async {
  final configFile = File('.dart_tool/package_config.json');
  expect(configFile.existsSync(), isTrue, reason: 'run flutter pub get first');
  final config = _map(jsonDecode(await configFile.readAsString()));
  final package = _mapList(
    config['packages'],
  ).singleWhere((entry) => entry['name'] == 'mithqal_pricing');
  final rootUri = configFile.parent.uri.resolve(package['rootUri'] as String);
  final root = Directory.fromUri(rootUri);
  expect(root.existsSync(), isTrue, reason: 'mithqal_pricing must be resolved');
  expect(
    root.path,
    isNot(contains('.pub-cache${Platform.pathSeparator}hosted')),
  );
  return root;
}

List<File> _goldenFiles(Directory root) {
  final directory = Directory('${root.path}${Platform.pathSeparator}goldens');
  expect(directory.existsSync(), isTrue);
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((left, right) => _basename(left).compareTo(_basename(right)));
}

String _basename(File file) => file.uri.pathSegments.last;

void _expectAdaptedInput(
  core.PricingInput actual,
  Map<String, dynamic> expected, {
  required String vector,
}) {
  final lines = _mapList(expected['lines']);
  expect(actual.lines, hasLength(lines.length), reason: '$vector/lines#');
  for (var index = 0; index < lines.length; index++) {
    final got = actual.lines[index];
    final want = lines[index];
    expect(
      got.productId,
      _nullableInt(want['productId']),
      reason: '$vector/line[$index].productId',
    );
    expect(
      got.categoryId,
      _nullableInt(want['categoryId']),
      reason: '$vector/line[$index].categoryId',
    );
    expect(
      got.unitPriceBaisas,
      _int(want['unitPriceBaisas']),
      reason: '$vector/line[$index].unitPrice',
    );
    expect(got.qty, _int(want['qty'], 1), reason: '$vector/line[$index].qty');
    expect(
      got.gifted,
      want['gifted'] == true,
      reason: '$vector/line[$index].gifted',
    );
    expect(
      got.bundleKey,
      want['bundleKey']?.toString() ?? '',
      reason: '$vector/line[$index].bundleKey',
    );
  }

  final rules = _mapList(expected['discountRules']);
  expect(
    actual.discountRules,
    hasLength(rules.length),
    reason: '$vector/discountRules#',
  );
  for (var index = 0; index < rules.length; index++) {
    final got = actual.discountRules[index];
    final want = rules[index];
    expect(got.id, _int(want['id']), reason: '$vector/rule[$index].id');
    expect(
      got.name,
      want['name']?.toString() ?? '',
      reason: '$vector/rule[$index].name',
    );
    expect(
      got.scope,
      want['scope']?.toString() ?? 'order',
      reason: '$vector/rule[$index].scope',
    );
    expect(
      got.amountType,
      want['amountType']?.toString() ?? 'fixed',
      reason: '$vector/rule[$index].amountType',
    );
    expect(
      got.fixedBaisas,
      _nullableInt(want['fixedBaisas']),
      reason: '$vector/rule[$index].fixed',
    );
    expect(
      got.percent,
      _nullableDouble(want['percent']),
      reason: '$vector/rule[$index].percent',
    );
    expect(
      got.validityStart,
      _nullableDate(want['validityStart']),
      reason: '$vector/rule[$index].validityStart',
    );
    expect(
      got.validityEnd,
      _nullableDate(want['validityEnd']),
      reason: '$vector/rule[$index].validityEnd',
    );
    expect(
      got.dayOfWeekMask,
      _nullableInt(want['dayOfWeekMask']),
      reason: '$vector/rule[$index].dayOfWeekMask',
    );
    expect(
      got.timeStart,
      want['timeStart'] as String?,
      reason: '$vector/rule[$index].timeStart',
    );
    expect(
      got.timeEnd,
      want['timeEnd'] as String?,
      reason: '$vector/rule[$index].timeEnd',
    );
    expect(
      got.branchScope,
      _intList(want['branchScope']),
      reason: '$vector/rule[$index].branchScope',
    );
    expect(
      got.stackable,
      want['stackable'] == true,
      reason: '$vector/rule[$index].stackable',
    );
    expect(
      got.requiresManagerApproval,
      want['requiresManagerApproval'] == true,
      reason: '$vector/rule[$index].managerApproval',
    );
    expect(
      got.isActive,
      want['isActive'] != false,
      reason: '$vector/rule[$index].active',
    );
    expect(
      got.autoApply,
      want['autoApply'] == true,
      reason: '$vector/rule[$index].autoApply',
    );
    expect(
      [
        for (final target in got.targets)
          {'targetType': target.targetType, 'targetId': target.targetId},
      ],
      _mapList(want['targets']),
      reason: '$vector/rule[$index].targets',
    );
  }

  final offers = _mapList(expected['offers']);
  expect(actual.offers, hasLength(offers.length), reason: '$vector/offers#');
  for (var index = 0; index < offers.length; index++) {
    final got = actual.offers[index];
    final want = offers[index];
    expect(got.id, _int(want['id']), reason: '$vector/offer[$index].id');
    expect(
      got.name,
      want['name']?.toString() ?? '',
      reason: '$vector/offer[$index].name',
    );
    expect(
      got.nameAr,
      want['nameAr'] as String?,
      reason: '$vector/offer[$index].nameAr',
    );
    expect(
      got.type,
      want['type']?.toString() ?? '',
      reason: '$vector/offer[$index].type',
    );
    expect(
      got.config,
      _map(want['config']),
      reason: '$vector/offer[$index].config',
    );
    expect(
      got.autoApply,
      want['autoApply'] != false,
      reason: '$vector/offer[$index].autoApply',
    );
    expect(
      got.validityStart,
      _nullableDate(want['validityStart']),
      reason: '$vector/offer[$index].validityStart',
    );
    expect(
      got.validityEnd,
      _nullableDate(want['validityEnd']),
      reason: '$vector/offer[$index].validityEnd',
    );
    expect(
      got.dayOfWeekMask,
      _nullableInt(want['dayOfWeekMask']),
      reason: '$vector/offer[$index].dayOfWeekMask',
    );
    expect(
      got.timeStart,
      want['timeStart'] as String?,
      reason: '$vector/offer[$index].timeStart',
    );
    expect(
      got.timeEnd,
      want['timeEnd'] as String?,
      reason: '$vector/offer[$index].timeEnd',
    );
    expect(
      got.branchScope,
      _intList(want['branchScope']),
      reason: '$vector/offer[$index].branchScope',
    );
    expect(
      got.maxPerOrder,
      _nullableInt(want['maxPerOrder']),
      reason: '$vector/offer[$index].maxPerOrder',
    );
    expect(
      got.isActive,
      want['isActive'] != false,
      reason: '$vector/offer[$index].active',
    );
  }

  final orderDiscount = _map(expected['orderDiscount']);
  final expectedKind = switch (orderDiscount['kind']?.toString()) {
    'fixed' => core.OrderDiscountKind.fixedAmount,
    'percentage' => core.OrderDiscountKind.percentage,
    _ => core.OrderDiscountKind.none,
  };
  expect(
    actual.orderDiscount.kind,
    expectedKind,
    reason: '$vector/orderDiscount.kind',
  );
  expect(
    actual.orderDiscount.fixedBaisas,
    _int(orderDiscount['fixedBaisas']),
    reason: '$vector/orderDiscount.fixed',
  );
  expect(
    actual.orderDiscount.percent,
    _double(orderDiscount['percent']),
    reason: '$vector/orderDiscount.percent',
  );
  expect(
    actual.orderDiscount.label,
    orderDiscount['label']?.toString() ?? '',
    reason: '$vector/orderDiscount.label',
  );
  expect(
    actual.orderDiscount.discountId,
    _nullableInt(orderDiscount['discountId']),
    reason: '$vector/orderDiscount.discountId',
  );
  expect(
    actual.orderDiscount.reason,
    orderDiscount['reason']?.toString() ?? '',
    reason: '$vector/orderDiscount.reason',
  );
  expect(
    actual.orderDiscount.loyaltyRuleId,
    _nullableInt(orderDiscount['loyaltyRuleId']),
    reason: '$vector/orderDiscount.loyaltyRuleId',
  );
  expect(
    actual.orderDiscount.loyaltyPoints,
    _int(orderDiscount['loyaltyPoints']),
    reason: '$vector/orderDiscount.loyaltyPoints',
  );
  expect(
    actual.orderDiscount.loyaltyStamps,
    _int(orderDiscount['loyaltyStamps']),
    reason: '$vector/orderDiscount.loyaltyStamps',
  );

  final comp = expected['comp'];
  if (comp == null) {
    expect(actual.comp, isNull, reason: '$vector/comp');
  } else {
    final want = _map(comp);
    expect(actual.comp, isNotNull, reason: '$vector/comp');
    expect(
      actual.comp!.lineIndex,
      _nullableInt(want['lineIndex']),
      reason: '$vector/comp.lineIndex',
    );
    expect(
      actual.comp!.qty,
      _nullableInt(want['qty']),
      reason: '$vector/comp.qty',
    );
    expect(
      actual.comp!.reason,
      want['reason']?.toString() ?? '',
      reason: '$vector/comp.reason',
    );
    // AppliedComp requires an int reasonId, whereas one package vector omits
    // metadata that does not participate in pricing. Assert it when supplied.
    if (want.containsKey('reasonId')) {
      expect(
        actual.comp!.reasonId,
        _nullableInt(want['reasonId']),
        reason: '$vector/comp.reasonId',
      );
    }
  }

  final taxes = _mapList(expected['taxes']);
  expect(actual.taxes, hasLength(taxes.length), reason: '$vector/taxes#');
  for (var index = 0; index < taxes.length; index++) {
    final got = actual.taxes[index];
    final want = taxes[index];
    expect(
      got.name,
      want['name']?.toString() ?? '',
      reason: '$vector/tax[$index].name',
    );
    expect(
      got.nameAr,
      want['nameAr'] as String?,
      reason: '$vector/tax[$index].nameAr',
    );
    expect(
      got.ratePercent,
      _double(want['ratePercent']),
      reason: '$vector/tax[$index].rate',
    );
  }
  expect(
    actual.isDeliveryProvider,
    expected['isDeliveryProvider'] == true,
    reason: '$vector/delivery',
  );
  expect(
    actual.pricesIncludeTax,
    expected['pricesIncludeTax'] == true,
    reason: '$vector/pricesIncludeTax',
  );
  expect(
    actual.now,
    DateTime.parse(expected['now'] as String),
    reason: '$vector/now',
  );
  expect(
    actual.branchId,
    _nullableInt(expected['branchId']),
    reason: '$vector/branchId',
  );
}

void _expectPriceResult(
  core.PriceResult actual,
  core.PricingInput input,
  Map<String, dynamic> expected, {
  required String vector,
}) {
  void amount(int got, String key) {
    expect(got, _int(expected[key]), reason: '$vector/$key');
  }

  amount(actual.rawSubtotalBaisas, 'rawSubtotalBaisas');
  amount(actual.lineDiscountTotalBaisas, 'lineDiscountTotalBaisas');
  amount(actual.offerDiscountTotalBaisas, 'offerDiscountTotalBaisas');
  amount(actual.orderDiscountBaisas, 'orderDiscountBaisas');
  amount(actual.discountTotalBaisas, 'discountTotalBaisas');
  amount(actual.subtotalBaisas, 'subtotalBaisas');
  amount(actual.giftedTotalBaisas, 'giftedTotalBaisas');
  amount(actual.managerCompBaisas, 'managerCompBaisas');
  amount(actual.compTotalBaisas, 'compTotalBaisas');
  amount(actual.taxedBaseBaisas, 'taxedBaseBaisas');
  amount(actual.taxTotalBaisas, 'taxTotalBaisas');
  amount(actual.grandTotalBaisas, 'grandTotalBaisas');

  final expectedLines = _mapList(expected['lineDiscounts']);
  expect(
    actual.lineDiscounts,
    hasLength(expectedLines.length),
    reason: '$vector/lineDiscounts#',
  );
  for (var index = 0; index < expectedLines.length; index++) {
    final got = actual.lineDiscounts[index];
    final want = expectedLines[index];
    expect(
      got.lineIndex,
      _int(want['lineIndex']),
      reason: '$vector/lineDiscount[$index].lineIndex',
    );
    expect(
      got.amountBaisas,
      _int(want['amountBaisas']),
      reason: '$vector/lineDiscount[$index].amount',
    );
    expect(
      got.ruleId,
      _nullableInt(want['ruleId']),
      reason: '$vector/lineDiscount[$index].ruleId',
    );
    expect(
      got.amountType,
      want['amountType'] as String?,
      reason: '$vector/lineDiscount[$index].amountType',
    );
    final sourceRule = input.discountRules.singleWhere(
      (rule) => rule.id == got.ruleId,
    );
    expect(
      got.label,
      sourceRule.name,
      reason: '$vector/lineDiscount[$index].label',
    );
  }

  final expectedOffers = _mapList(expected['appliedOffers']);
  expect(
    actual.appliedOffers,
    hasLength(expectedOffers.length),
    reason: '$vector/appliedOffers#',
  );
  for (var index = 0; index < expectedOffers.length; index++) {
    final got = actual.appliedOffers[index];
    final want = expectedOffers[index];
    expect(
      got.offerId,
      _int(want['offerId']),
      reason: '$vector/offer[$index].id',
    );
    expect(
      got.applications,
      _int(want['applications']),
      reason: '$vector/offer[$index].applications',
    );
    expect(
      got.orderAmountBaisas,
      _int(want['orderAmountBaisas']),
      reason: '$vector/offer[$index].orderAmount',
    );
    expect(
      got.lineAmountsBaisas,
      _intKeyMap(want['lineAmountsBaisas']),
      reason: '$vector/offer[$index].lineAmounts',
    );
    expect(
      got.totalBaisas,
      got.orderAmountBaisas +
          got.lineAmountsBaisas.values.fold<int>(
            0,
            (sum, value) => sum + value,
          ),
      reason: '$vector/offer[$index].total',
    );
    final sourceOffer = input.offers.singleWhere(
      (offer) => offer.id == got.offerId,
    );
    expect(got.name, sourceOffer.name, reason: '$vector/offer[$index].name');
    expect(
      got.nameAr,
      sourceOffer.nameAr,
      reason: '$vector/offer[$index].nameAr',
    );
  }

  expect(
    actual.giftAmountsBaisas,
    _intKeyMap(expected['giftAmountsBaisas']),
    reason: '$vector/giftAmountsBaisas',
  );

  final expectedTaxes = _mapList(expected['taxLines']);
  expect(
    actual.taxLines,
    hasLength(expectedTaxes.length),
    reason: '$vector/taxLines#',
  );
  for (var index = 0; index < expectedTaxes.length; index++) {
    final got = actual.taxLines[index];
    final want = expectedTaxes[index];
    final sourceTax = input.taxes[index];
    expect(got.name, want['name'], reason: '$vector/tax[$index].name');
    expect(
      got.amountBaisas,
      _int(want['amountBaisas']),
      reason: '$vector/tax[$index].amount',
    );
    expect(got.nameAr, sourceTax.nameAr, reason: '$vector/tax[$index].nameAr');
    expect(
      got.ratePercent,
      sourceTax.ratePercent,
      reason: '$vector/tax[$index].rate',
    );
  }

  final unclampedRow =
      actual.discountTotalBaisas -
      actual.lineDiscountTotalBaisas -
      actual.offerDiscountTotalBaisas;
  expect(
    actual.orderDiscountRowBaisas,
    unclampedRow < 0 ? 0 : unclampedRow,
    reason: '$vector/orderDiscountRowBaisas',
  );
  expect(
    actual.subtotalBaisas,
    actual.rawSubtotalBaisas - actual.discountTotalBaisas,
    reason: '$vector/subtotal invariant',
  );
  expect(
    actual.taxedBaseBaisas,
    actual.subtotalBaisas - actual.compTotalBaisas,
    reason: '$vector/taxed-base invariant',
  );
  // Inclusive (LAUNCH-P4): the tax sits INSIDE the grand total.
  expect(actual.pricesIncludeTax, input.pricesIncludeTax);
  expect(
    actual.rawSubtotalBaisas -
        actual.discountTotalBaisas -
        actual.compTotalBaisas +
        (input.pricesIncludeTax ? 0 : actual.taxTotalBaisas),
    actual.grandTotalBaisas,
    reason: '$vector/additive invariant',
  );
}

final class _GoldenMachineState implements MachinePricingState {
  const _GoldenMachineState({
    required this.cart,
    required this.availableDiscounts,
    required this.availableOffers,
    required this.discount,
    required this.appliedComp,
    required this.loyaltyRedeemRuleId,
    required this.loyaltyRedeemPoints,
    required this.loyaltyRedeemStamps,
    required this.selectedOrderType,
    required this.pricingBranchId,
  });

  factory _GoldenMachineState.fromInput(Map<String, dynamic> input) {
    final orderDiscount = _map(input['orderDiscount']);
    final comp = input['comp'] == null ? null : _map(input['comp']);
    return _GoldenMachineState(
      cart: [
        for (var index = 0; index < _mapList(input['lines']).length; index++)
          _machineLine(_mapList(input['lines'])[index], index),
      ],
      availableDiscounts: [
        for (final rule in _mapList(input['discountRules']))
          _machineDiscount(rule),
      ],
      availableOffers: [
        for (final offer in _mapList(input['offers'])) _machineOffer(offer),
      ],
      discount: _machineOrderDiscount(orderDiscount),
      appliedComp: comp == null
          ? null
          : AppliedComp(
              reasonId: _int(comp['reasonId']),
              reasonName: comp['reason']?.toString() ?? '',
              lineIndex: _nullableInt(comp['lineIndex']),
              qty: _nullableInt(comp['qty']),
            ),
      loyaltyRedeemRuleId: _nullableInt(orderDiscount['loyaltyRuleId']),
      loyaltyRedeemPoints: _int(orderDiscount['loyaltyPoints']),
      loyaltyRedeemStamps: _int(orderDiscount['loyaltyStamps']),
      selectedOrderType: input['isDeliveryProvider'] == true
          ? OrderType.delivery
          : OrderType.quickOrder,
      pricingBranchId: _nullableInt(input['branchId']),
    );
  }

  @override
  final List<CartItem> cart;
  @override
  final List<MerchantDiscount> availableDiscounts;
  @override
  final List<Offer> availableOffers;
  @override
  final DiscountConfiguration discount;
  @override
  final AppliedComp? appliedComp;
  @override
  final int? loyaltyRedeemRuleId;
  @override
  final int loyaltyRedeemPoints;
  @override
  final int loyaltyRedeemStamps;
  @override
  final OrderType selectedOrderType;
  @override
  final int? pricingBranchId;
}

CartItem _machineLine(Map<String, dynamic> line, int index) {
  final productId = line['productId'];
  final baisas = _int(line['unitPriceBaisas']);
  return CartItem(
    product: Product(
      id: productId == null ? 'golden-null-$index' : _int(productId).toString(),
      name: 'Golden product $index',
      category: 'Golden category',
      categoryId: _nullableInt(line['categoryId']),
      price: baisas / 1000.0,
    ),
    qty: _int(line['qty'], 1),
    gifted: line['gifted'] == true,
    bundleKey: line['bundleKey']?.toString() ?? '',
  );
}

MerchantDiscount _machineDiscount(Map<String, dynamic> rule) =>
    MerchantDiscount(
      id: _int(rule['id']),
      name: rule['name']?.toString() ?? '',
      scope: rule['scope']?.toString() ?? 'order',
      amountType: rule['amountType']?.toString() ?? 'fixed',
      fixedAmount: rule['fixedBaisas'] == null
          ? null
          : _int(rule['fixedBaisas']) / 1000.0,
      percent: _nullableDouble(rule['percent']),
      validityStart: _nullableDate(rule['validityStart']),
      validityEnd: _nullableDate(rule['validityEnd']),
      dayOfWeekMask: _nullableInt(rule['dayOfWeekMask']),
      timeStart: rule['timeStart'] as String?,
      timeEnd: rule['timeEnd'] as String?,
      branchScope: _intList(rule['branchScope']),
      stackable: rule['stackable'] == true,
      requiresManagerApproval: rule['requiresManagerApproval'] == true,
      isActive: rule['isActive'] != false,
      autoApply: rule['autoApply'] == true,
      targets: [
        for (final target in _mapList(rule['targets']))
          DiscountTarget(
            targetType: target['targetType']?.toString() ?? '',
            targetId: _int(target['targetId']),
          ),
      ],
    );

Offer _machineOffer(Map<String, dynamic> offer) => Offer(
  id: _int(offer['id']),
  name: offer['name']?.toString() ?? '',
  nameAr: offer['nameAr'] as String?,
  type: offer['type']?.toString() ?? '',
  config: _map(offer['config']),
  autoApply: offer['autoApply'] != false,
  validityStart: _nullableDate(offer['validityStart']),
  validityEnd: _nullableDate(offer['validityEnd']),
  dayOfWeekMask: _nullableInt(offer['dayOfWeekMask']),
  timeStart: offer['timeStart'] as String?,
  timeEnd: offer['timeEnd'] as String?,
  branchScope: _intList(offer['branchScope']),
  maxPerOrder: _nullableInt(offer['maxPerOrder']),
  isActive: offer['isActive'] != false,
);

DiscountConfiguration _machineOrderDiscount(Map<String, dynamic> discount) =>
    switch (discount['kind']?.toString()) {
      'fixed' => DiscountConfiguration(
        kind: DiscountKind.fixedAmount,
        value: _int(discount['fixedBaisas']) / 1000.0,
        label: discount['label']?.toString() ?? '',
        discountId: _nullableInt(discount['discountId']),
        reason: discount['reason']?.toString() ?? '',
      ),
      'percentage' => DiscountConfiguration(
        kind: DiscountKind.percentage,
        value: _double(discount['percent']),
        label: discount['label']?.toString() ?? '',
        discountId: _nullableInt(discount['discountId']),
        reason: discount['reason']?.toString() ?? '',
      ),
      _ => const DiscountConfiguration(),
    };

List<CompanyTax> _machineTaxes(Map<String, dynamic> input) => [
  for (final tax in _mapList(input['taxes']))
    CompanyTax(
      name: tax['name']?.toString() ?? '',
      nameAr: tax['nameAr'] as String?,
      ratePercent: _double(tax['ratePercent']),
    ),
];

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(Object? value) =>
    value is List ? value.map(_map).toList(growable: false) : const [];

List<int> _intList(Object? value) => value is List
    ? value.map((element) => _int(element)).toList(growable: false)
    : const [];

Map<int, int> _intKeyMap(Object? value) =>
    _map(value).map((key, amount) => MapEntry(int.parse(key), _int(amount)));

int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

int? _nullableInt(Object? value) => value is num ? value.toInt() : null;

double _double(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

double? _nullableDouble(Object? value) =>
    value is num ? value.toDouble() : null;

DateTime? _nullableDate(Object? value) =>
    value is String ? DateTime.parse(value) : null;
