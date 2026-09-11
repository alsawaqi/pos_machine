/// Shared EN/AR copy for the two native clients (handheld has no ARB runtime).
class QuickCopy {
  const QuickCopy(this.arabic);
  final bool arabic;
  String pair(String en, String ar) => arabic ? ar : en;
  String name(String en, String ar) => arabic && ar.trim().isNotEmpty ? ar : en;
  String get title => pair('QR Quick Orders', 'طلبات QR السريعة');
  String get add => pair('Add items', 'إضافة أصناف');
  String get pay => pair('Proceed to pay', 'المتابعة للدفع');
  String get move => pair('Send to counter', 'إرسال إلى الكاشير');
  String get refresh => pair('Refresh', 'تحديث');
  String get retry =>
      pair('Check / retry same request', 'تحقق / أعد نفس الطلب');
  String get submit => pair('Send additions', 'إرسال الإضافات');
  String get cancel => pair('Cancel', 'إلغاء');
  String get total => pair('Bill total', 'إجمالي الفاتورة');
  String get existing =>
      pair('Items already on this bill', 'الأصناف الموجودة في هذه الفاتورة');
  String get draft =>
      pair('New items — not sent yet', 'أصناف جديدة — لم تُرسل بعد');
  String get pricing => pair(
    'The server prices new items and adds them to this same bill. Existing items stay unchanged.',
    'يحدد الخادم أسعار الأصناف الجديدة ويضيفها إلى نفس الفاتورة. تبقى الأصناف السابقة دون تغيير.',
  );
  String get empty => pair(
    'No QR quick orders waiting.',
    'لا توجد طلبات QR سريعة بانتظار المعالجة.',
  );
  String get noPayment => pair(
    'For now, settle this bill on the till. Handheld payment integration is the next step.',
    'حالياً، سدّد هذه الفاتورة على جهاز الكاشير. دمج الدفع على الجهاز المحمول هو الخطوة التالية.',
  );
  String get stale => pair(
    'Connection not confirmed. Refresh before changing an order.',
    'لم يتم تأكيد الاتصال. حدّث قبل تعديل الطلب.',
  );
  String get uncertain => pair(
    'Addition result not confirmed. Check the SAME request before adding more or paying. It is saved if you close this screen.',
    'لم يتم تأكيد نتيجة الإضافة. تحقّق من نفس الطلب قبل إضافة المزيد أو الدفع. يبقى محفوظاً عند إغلاق هذه الشاشة.',
  );
  String state(String charge, String session) {
    if (charge == 'live_claim') {
      return pair('Payment in progress', 'الدفع قيد التنفيذ');
    }
    if (charge == 'uncertain') {
      return pair('Payment needs review', 'الدفع يحتاج إلى مراجعة');
    }
    if (charge == 'declined') return pair('Card declined', 'البطاقة مرفوضة');
    if (charge == 'cancelled') {
      return pair('Payment cancelled', 'تم إلغاء الدفع');
    }
    return switch (session) {
      'expired' => pair('Phone session expired', 'انتهت جلسة الهاتف'),
      'closed' => pair('Phone session closed', 'جلسة الهاتف مغلقة'),
      'missing' => pair('Phone session unavailable', 'جلسة الهاتف غير متاحة'),
      _ => pair('Waiting for staff', 'بانتظار الموظف'),
    };
  }

  String message(String code) => switch (code) {
    'added' => pair(
      'Items added to the same bill.',
      'أُضيفت الأصناف إلى نفس الفاتورة.',
    ),
    'uncertain' => uncertain,
    'storage' => pair(
      'Cannot open the saved-request journal. No new additions can be sent. Ask support to recover it.',
      'تعذّر فتح سجل الطلبات المحفوظة. لا يمكن إرسال إضافات جديدة. اطلب المساعدة لاستعادته.',
    ),
    'product_unavailable' ||
    'addon_unavailable' ||
    'addon_selection_invalid' ||
    'invalid_catalogue_line' ||
    'validation_failed' => pair(
      'An item or option is unavailable. Review the additions and try again.',
      'أحد الأصناف أو الخيارات غير متاح. راجع الإضافات وحاول مجدداً.',
    ),
    'charge_already_claimed' => pair(
      'Another payment is in progress. Do not take payment again.',
      'توجد عملية دفع جارية. لا تستلم الدفع مرة أخرى.',
    ),
    'qr_charge_recovery_required' || 'charge_outcome_uncertain' => pair(
      'A manager must review the earlier payment before continuing.',
      'يجب على المدير مراجعة الدفع السابق قبل المتابعة.',
    ),
    'order_not_editable' => pair(
      'This bill cannot accept items now. Refresh its status.',
      'لا يمكن إضافة أصناف إلى هذه الفاتورة الآن. حدّث حالتها.',
    ),
    'order_not_found' => pair(
      'This order is no longer available. Refresh the list.',
      'هذا الطلب لم يعد متاحاً. حدّث القائمة.',
    ),
    'identity_changed' => pair(
      'Device or server changed. Close and reopen QR Quick Orders.',
      'تغيّر الجهاز أو الخادم. أغلق طلبات QR السريعة وافتحها مجدداً.',
    ),
    _ => pair(
      'Request refused or unavailable. Refresh before continuing.',
      'الطلب مرفوض أو غير متاح. حدّث قبل المتابعة.',
    ),
  };
}
