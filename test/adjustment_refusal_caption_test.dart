import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';

void main() {
  for (final ar in [false, true]) {
    test(
      'Unknown adjustment refusals cannot resolve to captions ${ar ? "AR" : "EN"}',
      () {
        for (final code in [
          'print',
          'refresh',
          'held',
          'discount',
          'uncertain',
          'future_policy',
          'adjust_request_conflict',
        ]) {
          expect(
            dineInText(ar, 'adjust_refused:$code'),
            ar
                ? 'تعذر تنفيذ التعديل ($code). حدّث الفاتورة قبل المحاولة مجدداً.'
                : 'Adjustment refused ($code). Refresh the bill before trying again.',
          );
        }
        for (final code in [
          'bill_missing',
          'bill_reserved',
          'adjustment_exceeds_bill',
          'full_comp_not_supported',
          'comp_cap_exceeded',
          'discount_rule_not_applicable',
          'approval_required',
          'customer_not_found',
        ]) {
          expect(dineInText(ar, 'adjust_refused:$code'), dineInText(ar, code));
        }
      },
    );
  }
}
