import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/models/pos_models.dart';

MerchantDiscount _disc({
  String scope = 'order',
  String amountType = 'percent',
  double? fixedAmount,
  double? percent = 10,
  DateTime? validityStart,
  DateTime? validityEnd,
  int? dayOfWeekMask,
  String? timeStart,
  String? timeEnd,
  List<int> branchScope = const [],
  bool requiresManagerApproval = false,
  bool isActive = true,
}) =>
    MerchantDiscount(
      id: 1,
      name: 'Test',
      scope: scope,
      amountType: amountType,
      fixedAmount: fixedAmount,
      percent: percent,
      validityStart: validityStart,
      validityEnd: validityEnd,
      dayOfWeekMask: dayOfWeekMask,
      timeStart: timeStart,
      timeEnd: timeEnd,
      branchScope: branchScope,
      requiresManagerApproval: requiresManagerApproval,
      isActive: isActive,
    );

void main() {
  final noon = DateTime(2026, 6, 8, 12, 0, 0); // a fixed wall-clock instant

  group('MerchantDiscount.amountFor', () {
    test('percent of subtotal', () {
      expect(_disc(amountType: 'percent', percent: 10).amountFor(5.0), 0.5);
    });
    test('fixed amount', () {
      expect(
        _disc(amountType: 'fixed', fixedAmount: 1.5, percent: null)
            .amountFor(5.0),
        1.5,
      );
    });
    test('clamped to the subtotal', () {
      expect(
        _disc(amountType: 'fixed', fixedAmount: 10.0, percent: null)
            .amountFor(5.0),
        5.0,
      );
    });
  });

  group('MerchantDiscount.appliesAt', () {
    test('inactive never applies', () {
      expect(_disc(isActive: false).appliesAt(noon, branchId: 1), isFalse);
    });

    test('validity window bounds', () {
      expect(
        _disc(validityStart: DateTime(2026, 7, 1)).appliesAt(noon, branchId: 1),
        isFalse,
      );
      expect(
        _disc(validityEnd: DateTime(2026, 5, 1)).appliesAt(noon, branchId: 1),
        isFalse,
      );
      expect(
        _disc(
          validityStart: DateTime(2026, 6, 1),
          validityEnd: DateTime(2026, 6, 30),
        ).appliesAt(noon, branchId: 1),
        isTrue,
      );
    });

    test('day-of-week mask (server convention 1<<dow, Sun=0)', () {
      final todayBit = 1 << (noon.weekday % 7);
      final otherBit = 1 << ((noon.weekday + 1) % 7);
      expect(
        _disc(dayOfWeekMask: todayBit).appliesAt(noon, branchId: 1),
        isTrue,
      );
      expect(
        _disc(dayOfWeekMask: otherBit).appliesAt(noon, branchId: 1),
        isFalse,
      );
    });

    test('time-of-day window', () {
      expect(
        _disc(timeStart: '08:00:00', timeEnd: '17:00:00')
            .appliesAt(noon, branchId: 1),
        isTrue,
      );
      expect(
        _disc(timeStart: '13:00:00', timeEnd: '17:00:00')
            .appliesAt(noon, branchId: 1),
        isFalse,
      );
    });

    test('time window wrapping midnight', () {
      final eve = DateTime(2026, 6, 8, 23, 0, 0);
      final disc = _disc(timeStart: '22:00:00', timeEnd: '02:00:00');
      expect(disc.appliesAt(eve, branchId: 1), isTrue);
      expect(disc.appliesAt(noon, branchId: 1), isFalse);
    });

    test('branch scope membership (empty = all)', () {
      expect(_disc(branchScope: const [5]).appliesAt(noon, branchId: 5), isTrue);
      expect(
        _disc(branchScope: const [5]).appliesAt(noon, branchId: 6),
        isFalse,
      );
      expect(_disc().appliesAt(noon, branchId: 99), isTrue);
    });
  });

  group('MerchantDiscount.toConfiguration', () {
    test('percent rule → percentage config carrying id + amount_type', () {
      final cfg = MerchantDiscount(
        id: 3,
        name: 'Ramadan 10%',
        scope: 'order',
        amountType: 'percent',
        percent: 10,
      ).toConfiguration();
      expect(cfg.kind, DiscountKind.percentage);
      expect(cfg.value, 10);
      expect(cfg.label, 'Ramadan 10%');
      expect(cfg.discountId, 3);
      expect(cfg.amountType, 'percent');
    });

    test('fixed rule → fixed-amount config', () {
      final cfg = MerchantDiscount(
        id: 4,
        name: 'OMR 1 off',
        scope: 'order',
        amountType: 'fixed',
        fixedAmount: 1.0,
      ).toConfiguration();
      expect(cfg.kind, DiscountKind.fixedAmount);
      expect(cfg.value, 1.0);
      expect(cfg.discountId, 4);
      expect(cfg.amountType, 'fixed');
    });
  });
}
