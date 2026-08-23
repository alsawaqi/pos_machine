import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/shift_summary.dart';

const _persistenceKeys = <String>{
  'discountId',
  'discountAmountType',
  'loyaltyRedeemRuleId',
  'loyaltyRedeemPoints',
  'loyaltyRedeemStamps',
  'compAmount',
  'compReasonId',
  'compReasonName',
  'compLineIndex',
  'compQty',
};

OrderSnapshot _allFieldsSnapshot() => OrderSnapshot.initial().copyWith(
  discountId: 7,
  discountAmountType: 'percent',
  loyaltyRedeemRuleId: 3,
  loyaltyRedeemPoints: 150,
  loyaltyRedeemStamps: 2,
  compAmount: 5.0,
  compReasonId: 42,
  compReasonName: 'Service recovery',
  compLineIndex: 1,
  compQty: 1,
);

OrderSnapshot _jsonRoundTrip(OrderSnapshot snapshot) => OrderSnapshot.fromMap(
  jsonDecode(jsonEncode(snapshot.toMap())) as Map<String, dynamic>,
);

void main() {
  test('JSON round-trip keeps all ten persistence fields', () {
    final original = _allFieldsSnapshot();
    final restored = _jsonRoundTrip(original);

    expect(restored.discountId, original.discountId);
    expect(restored.discountAmountType, original.discountAmountType);
    expect(restored.loyaltyRedeemRuleId, original.loyaltyRedeemRuleId);
    expect(restored.loyaltyRedeemPoints, original.loyaltyRedeemPoints);
    expect(restored.loyaltyRedeemStamps, original.loyaltyRedeemStamps);
    expect(restored.compAmount, original.compAmount);
    expect(restored.compAmount, isA<double>());
    expect(restored.compReasonId, original.compReasonId);
    expect(restored.compReasonName, original.compReasonName);
    expect(restored.compLineIndex, original.compLineIndex);
    expect(restored.compQty, original.compQty);
  });

  test('whole-order fractional comp preserves null and zero defaults', () {
    final restored = _jsonRoundTrip(
      OrderSnapshot.initial().copyWith(
        compAmount: 1.250,
        compReasonId: 9,
        compReasonName: 'Whole order',
      ),
    );

    expect(restored.discountId, isNull);
    expect(restored.discountAmountType, isNull);
    expect(restored.loyaltyRedeemRuleId, isNull);
    expect(restored.loyaltyRedeemPoints, 0);
    expect(restored.loyaltyRedeemStamps, 0);
    expect(restored.compAmount, 1.250);
    expect(restored.compReasonId, 9);
    expect(restored.compReasonName, 'Whole order');
    expect(restored.compLineIndex, isNull);
    expect(restored.compQty, isNull);
  });

  test('sparse map uses constructor-identical persistence defaults', () {
    final restored = OrderSnapshot.fromMap(<String, dynamic>{});

    expect(restored.discountId, isNull);
    expect(restored.discountAmountType, isNull);
    expect(restored.loyaltyRedeemRuleId, isNull);
    expect(restored.loyaltyRedeemPoints, 0);
    expect(restored.loyaltyRedeemStamps, 0);
    expect(restored.compAmount, 0);
    expect(restored.compReasonId, isNull);
    expect(restored.compReasonName, '');
    expect(restored.compLineIndex, isNull);
    expect(restored.compQty, isNull);
  });

  test('integer literals are tolerated for numeric persistence fields', () {
    final restored = OrderSnapshot.fromMap(<String, dynamic>{
      'compAmount': 5,
      'loyaltyRedeemPoints': 150,
      'compQty': 1,
    });

    expect(restored.compAmount, 5.0);
    expect(restored.compAmount, isA<double>());
    expect(restored.loyaltyRedeemPoints, 150);
    expect(restored.compQty, 1);
  });

  test('sparse emission preserves plain, manual, and gift map shapes', () {
    final plainKeys = OrderSnapshot.initial().toMap().keys.toSet();
    expect(plainKeys.intersection(_persistenceKeys), isEmpty);

    final manualKeys = OrderSnapshot.initial()
        .copyWith(
          discountAmount: 1.0,
          discountLabel: 'Manual',
          discountAmountType: 'fixed',
        )
        .toMap()
        .keys
        .toSet();
    expect(manualKeys.intersection(_persistenceKeys), const <String>{
      'discountAmountType',
    });

    final giftKeys = OrderSnapshot.initial()
        .copyWith(compAmount: 2.0)
        .toMap()
        .keys
        .toSet();
    expect(giftKeys.intersection(_persistenceKeys), const <String>{
      'compAmount',
    });
  });

  test('local shift fold sees comp after JSON round-trip', () {
    final createdAt = DateTime(2026, 8, 23, 12);
    final snapshot = _jsonRoundTrip(_allFieldsSnapshot());
    final record = OrderHistoryRecord(
      id: 'persisted-comp',
      orderNumber: snapshot.orderNumber,
      orderType: OrderType.quickOrder,
      createdAt: createdAt,
      snapshot: snapshot,
    );

    final summary = buildLocalShiftSummary(
      [record],
      openedAt: DateTime(2026, 8, 23, 11),
      closedAt: DateTime(2026, 8, 23, 13),
    );

    expect(summary.compBaisas, 5000);
  });
}
