/// Closed, price-free contract shared by the table intent journal and dialogs.
void validateBillAdjustment(Map<String, dynamic> value) {
  final kind = value['kind'];
  final mode = value['mode'];
  final allowed = switch ('$kind:$mode') {
    'discount:percent' => {'kind', 'mode', 'percent_bp', 'label', 'reason'},
    'discount:fixed' => {'kind', 'mode', 'amount_baisas', 'label', 'reason'},
    'discount:rule' => {
      'kind',
      'mode',
      'discount_id',
      'authorized_by',
      'approved_by_staff_id',
    },
    'discount:clear' || 'comp:clear' || 'customer:detach' => {'kind', 'mode'},
    'comp:apply' => {
      'kind',
      'mode',
      'comp_reason_id',
      'target',
      'note',
      'authorized_by',
      'approved_by_staff_id',
    },
    'customer:attach' => {'kind', 'mode', 'customer_id'},
    _ => throw const FormatException('Invalid adjustment kind'),
  };
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Unexpected adjustment field');
  }
  bool integer(Object? n, int min, int max) => n is int && n >= min && n <= max;
  bool text(Object? s, int max, {bool required = false}) => s == null
      ? !required
      : s is String && s.length <= max && (!required || s.trim().isNotEmpty);
  if ((mode == 'percent' && !integer(value['percent_bp'], 1, 10000)) ||
      (mode == 'fixed' && !integer(value['amount_baisas'], 1, 999999999999)) ||
      (kind == 'discount' &&
          const {'percent', 'fixed'}.contains(mode) &&
          !text(value['label'], 255, required: true)) ||
      !text(value['reason'], 160) ||
      !text(value['note'], 2000) ||
      !text(value['authorized_by'], 100) ||
      (value.containsKey('approved_by_staff_id') &&
          !integer(value['approved_by_staff_id'], 1, 2147483647)) ||
      (mode == 'rule' && !integer(value['discount_id'], 1, 2147483647)) ||
      (mode == 'attach' && !integer(value['customer_id'], 1, 2147483647))) {
    throw const FormatException('Invalid adjustment value');
  }
  if (kind == 'comp' && mode == 'apply') {
    final target = value['target'];
    if (!integer(value['comp_reason_id'], 1, 2147483647) ||
        !text(value['authorized_by'], 100, required: true) ||
        (target != 'bill' &&
            (target is! Map ||
                target.keys.any(
                  (key) => !{'order_item_id', 'qty'}.contains(key),
                ) ||
                !integer(target['order_item_id'], 1, 2147483647) ||
                !integer(target['qty'], 1, 999)))) {
      throw const FormatException('Invalid complimentary target');
    }
  }
}
