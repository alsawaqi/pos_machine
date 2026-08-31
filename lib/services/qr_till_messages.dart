typedef QrTillMessage = ({String en, String ar});

/// Every stable action code enumerated from the shipped QR staff controllers.
/// This is intentionally separate from generic transport/auth and local
/// coordinator codes so a server-contract sweep can compare it exactly.
const Set<String> qrTillServerRefusalCodes = {
  'device_not_table_board_reader',
  'device_unassigned',
  'device_not_attended',
  'order_not_found',
  'qr_order_not_settleable',
  'order_not_bound_to_device_session',
  'qr_session_expired',
  'qr_session_not_settleable',
  'charge_already_claimed',
  'qr_charge_recovery_required',
  'geofence_fix_required',
  'geofence_outside',
  'validation_failed',
  'rate_limited',
  'qr_session_not_ordered',
  'qr_order_not_reopenable',
  'order_already_held',
  'order_not_awaiting_payment',
  'numbering_disabled',
  'device_not_payment_station',
  'session_not_ordered',
  'qr_table_not_found',
  'qr_table_charge_live',
  'qr_table_payment_pending',
  'qr_table_unpaid_order',
  'charge_not_claimed_by_device',
  'charge_outcome_uncertain',
  'qr_round_not_found',
  'qr_round_not_pending',
};

/// QR-002 S2's source-enumerated refusal copy. Keep this map explicit: adding a
/// server exception code must fail the companion enumeration test until staff
/// receive an actionable message in both languages.
const Map<String, QrTillMessage> qrTillRefusalMessages = {
  'device_not_table_board_reader': (
    en: 'This device is not allowed to view the QR tables board.',
    ar: 'هذا الجهاز غير مخوّل لعرض لوحة طاولات QR.',
  ),
  'device_unassigned': (
    en: 'This device is not assigned to a branch.',
    ar: 'هذا الجهاز غير مرتبط بفرع.',
  ),
  'device_not_attended': (
    en: 'Use an attended till or handheld device for this action.',
    ar: 'استخدم جهاز كاشير أو جهازاً يدوياً تحت إشراف الموظف.',
  ),
  'order_not_found': (
    en: 'The order was not found. Refresh the tables board.',
    ar: 'لم يتم العثور على الطلب. حدّث لوحة الطاولات.',
  ),
  'qr_order_not_settleable': (
    en: 'This QR order can no longer be settled from this screen.',
    ar: 'لم يعد من الممكن تسوية طلب QR من هذه الشاشة.',
  ),
  'order_not_bound_to_device_session': (
    en: 'The order is not linked to a recoverable QR session.',
    ar: 'الطلب غير مرتبط بجلسة QR قابلة للاسترداد.',
  ),
  'qr_session_expired': (
    en: 'The table session expired. Move the order to the counter.',
    ar: 'انتهت جلسة الطاولة. انقل الطلب إلى الكاشير.',
  ),
  'qr_session_not_settleable': (
    en: 'The table session is not ready for settlement.',
    ar: 'جلسة الطاولة غير جاهزة للتسوية.',
  ),
  'charge_already_claimed': (
    en: 'Another device already holds this payment. Do not take money.',
    ar: 'جهاز آخر حجز هذه الدفعة. لا تستلم أي مبلغ.',
  ),
  'qr_charge_recovery_required': (
    en: 'A card may have been charged. Ask a manager and do not retry.',
    ar: 'قد تكون البطاقة خُصمت. اطلب المدير ولا تعِد المحاولة.',
  ),
  'geofence_fix_required': (
    en: 'A current location is required before taking payment.',
    ar: 'يلزم تحديد الموقع الحالي قبل استلام الدفعة.',
  ),
  'geofence_outside': (
    en: 'This device is outside the branch payment area.',
    ar: 'هذا الجهاز خارج نطاق الدفع الخاص بالفرع.',
  ),
  'order_not_awaiting_payment': (
    en: 'The order is no longer awaiting this payment.',
    ar: 'الطلب لم يعد بانتظار هذه الدفعة.',
  ),
  'charge_not_claimed_by_device': (
    en: 'This till no longer holds the payment claim.',
    ar: 'جهاز الكاشير هذا لم يعد يحتفظ بحجز الدفعة.',
  ),
  'charge_outcome_uncertain': (
    en: 'The card outcome is uncertain. Ask a manager and do not retry.',
    ar: 'نتيجة البطاقة غير مؤكدة. اطلب المدير ولا تعِد المحاولة.',
  ),
  'qr_round_not_found': (
    en: 'This QR round was not found. Refresh the tables board.',
    ar: 'لم يتم العثور على جولة QR هذه. حدّث لوحة الطاولات.',
  ),
  'qr_round_not_pending': (
    en: 'This QR round was already confirmed, rejected, or closed. Refresh the table before acting again.',
    ar: 'تم تأكيد جولة QR هذه أو رفضها أو إغلاقها مسبقاً. حدّث الطاولة قبل تنفيذ إجراء آخر.',
  ),
  'device_not_payment_station': (
    en: 'This action requires the correct attended payment device.',
    ar: 'يتطلب هذا الإجراء جهاز الدفع الصحيح تحت إشراف الموظف.',
  ),
  'session_not_ordered': (
    en: 'The QR session is not waiting for payment.',
    ar: 'جلسة QR ليست بانتظار الدفع.',
  ),
  'order_already_held': (
    en: 'The order is already at the counter but has no receipt number.',
    ar: 'الطلب موجود بالفعل لدى الكاشير ولكن بلا رقم إيصال.',
  ),
  'numbering_disabled': (
    en: 'Order numbering must be enabled before moving to the counter.',
    ar: 'يجب تفعيل ترقيم الطلبات قبل النقل إلى الكاشير.',
  ),
  'qr_session_not_ordered': (
    en: 'This table session is not awaiting payment.',
    ar: 'جلسة الطاولة هذه ليست بانتظار الدفع.',
  ),
  'qr_order_not_reopenable': (
    en: 'This order cannot be reopened for more rounds.',
    ar: 'لا يمكن إعادة فتح هذا الطلب لإضافة جولات.',
  ),
  'qr_table_charge_live': (
    en: 'A payment is in progress. Do not clear this table.',
    ar: 'هناك دفعة قيد التنفيذ. لا تخلِ هذه الطاولة.',
  ),
  'qr_table_payment_pending': (
    en: 'This table still has an unpaid payment request.',
    ar: 'لا يزال لهذه الطاولة طلب دفع غير مسدد.',
  ),
  'qr_table_unpaid_order': (
    en: 'This table still has an unpaid order.',
    ar: 'لا يزال على هذه الطاولة طلب غير مدفوع.',
  ),
  'qr_table_not_found': (
    en: 'The table was not found. Refresh the board.',
    ar: 'لم يتم العثور على الطاولة. حدّث اللوحة.',
  ),
  'validation_failed': (
    en: 'The request was invalid. Refresh and try again.',
    ar: 'الطلب غير صالح. حدّث الصفحة وحاول مجدداً.',
  ),
  'rate_limited': (
    en: 'Too many requests. Wait a moment before refreshing.',
    ar: 'طلبات كثيرة جداً. انتظر قليلاً قبل التحديث.',
  ),
  'unauthorized': (
    en: 'This device is no longer authorized.',
    ar: 'لم يعد هذا الجهاز مخوّلاً.',
  ),
  'network': (
    en: 'Cannot reach the server. Check the connection.',
    ar: 'تعذر الاتصال بالخادم. تحقق من الشبكة.',
  ),
  'qr_payment_attempt_unresolved': (
    en: 'A previous payment attempt is unresolved. Do not take money again.',
    ar: 'محاولة دفع سابقة لم تُحسم. لا تستلم المبلغ مرة أخرى.',
  ),
  'qr_settlement_claim_not_held': (
    en: 'This till does not hold a valid settlement claim. Do not take money.',
    ar: 'هذا الجهاز لا يحتفظ بحجز تسوية صالح. لا تستلم أي مبلغ.',
  ),
  'qr_settlement_claim_expired': (
    en: 'The payment reservation expired. Close this sheet and refresh; do not take money.',
    ar: 'انتهت مهلة حجز الدفعة. أغلق هذه الشاشة وحدّثها، ولا تستلم أي مبلغ.',
  ),
  'qr_settlement_claim_changed': (
    en: 'The frozen payment amount changed unexpectedly. Do not take money; ask for help.',
    ar: 'تغيّر مبلغ الدفع المحجوز بشكل غير متوقع. لا تستلم المبلغ واطلب المساعدة.',
  ),
  'qr_settlement_revalidation_failed': (
    en: 'The payment reservation could not be confirmed. No money was taken; refresh before trying again.',
    ar: 'تعذر تأكيد حجز الدفعة. لم يتم استلام أي مبلغ؛ حدّث الشاشة قبل المحاولة مجدداً.',
  ),
};

const Map<String, QrTillMessage> qrTillUiMessages = {
  'round_title': (en: 'Round', ar: 'الجولة'),
  'round_awaiting': (en: 'Awaiting confirmation', ar: 'بانتظار التأكيد'),
  'rounds_awaiting': (
    en: 'Rounds awaiting confirmation',
    ar: 'جولات بانتظار التأكيد',
  ),
  'round_confirm': (en: 'Confirm round', ar: 'تأكيد الجولة'),
  'round_reject': (en: 'Reject round', ar: 'رفض الجولة'),
  'round_keep': (en: 'Keep pending', ar: 'إبقاؤها معلّقة'),
  'round_confirm_question': (
    en: 'Send this frozen round to the kitchen?',
    ar: 'هل تريد إرسال هذه الجولة المثبتة إلى المطبخ؟',
  ),
  'round_reject_question': (
    en: 'Reject this round without adding it to the order?',
    ar: 'هل تريد رفض هذه الجولة دون إضافتها إلى الطلب؟',
  ),
  'round_confirmed': (
    en: 'Round confirmed and added to the order.',
    ar: 'تم تأكيد الجولة وإضافتها إلى الطلب.',
  ),
  'round_rejected': (
    en: 'Round rejected. No items were added.',
    ar: 'تم رفض الجولة ولم تُضف أي أصناف.',
  ),
  'round_print_failed': (
    en: 'The round was confirmed, but its kitchen ticket did not print.',
    ar: 'تم تأكيد الجولة، لكن تعذرت طباعة تذكرة المطبخ.',
  ),
  'round_retry_print': (en: 'Retry print', ar: 'إعادة الطباعة'),
  'round_done': (en: 'Done', ar: 'تم'),
  'round_notes': (en: 'Notes', ar: 'ملاحظات'),
  'round_total': (en: 'Round total', ar: 'إجمالي الجولة'),
};

String qrTillUiCopy(String key, {bool arabic = false}) {
  final message = qrTillUiMessages[key];
  if (message == null) return key;
  return arabic ? message.ar : message.en;
}

String qrTillMessageForCode(String? code, {bool arabic = false}) {
  final message = qrTillRefusalMessages[code];
  if (message != null) return arabic ? message.ar : message.en;
  return arabic
      ? 'تعذر إكمال الإجراء. حدّث اللوحة واطلب المساعدة.'
      : 'The action could not be completed. Refresh and ask for help.';
}
