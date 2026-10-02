// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class L10nAr extends L10n {
  L10nAr([String locale = 'ar']) : super(locale);

  @override
  String get settingsShowLegacyQrTablesTab => 'إظهار تبويب طاولات QR القديم';

  @override
  String get settingsShowLegacyQrTablesTabHint =>
      'خيار احتياطي لإصدار واحد. مخطط الصالة هو واجهة الطاولات.';

  @override
  String get tableSettleBill => 'تسوية الفاتورة';

  @override
  String tableCustomerPending(String label, int count) {
    return '$label: طلب عميل ($count صنف) — أكّده بالضغط على الطاولة.';
  }

  @override
  String tableCustomerKitchen(String label) {
    return '$label: أُرسل طلب العميل إلى المطبخ.';
  }

  @override
  String tableCustomerBill(String label) {
    return '$label: طلب العميل الفاتورة.';
  }

  @override
  String get tableSending => '⏳ جارٍ الإرسال';

  @override
  String tableActivityReview(int count) {
    return 'تحتاج إلى مراجعة ($count)';
  }

  @override
  String tablePendingBell(int count) {
    return '🔔 $count جولة بانتظار التأكيد';
  }

  @override
  String get tableSearchOffline =>
      'بحث الخادم غير متاح دون اتصال — النتائج المحلية فقط.';

  @override
  String get tableSearchFailed =>
      'تعذر البحث على الخادم — النتائج المحلية فقط.';

  @override
  String get tableSearchSearching => 'جارٍ البحث في طاولات الخادم…';

  @override
  String tableSearchMatch(String label, String reference, String total) {
    return '$label · $reference · $total ر.ع.';
  }

  @override
  String tableOfflineBanner(String time, int count) {
    return 'العمل دون اتصال منذ $time — المتاح: فتح الطاولات، إضافة الأصناف، النقل، الدمج، الإخلاء، تذكرة المطبخ، النقد، البطاقة، الإيصال. غير متاح: الطاولات المفتوحة على أجهزة أخرى، طلبات هاتف العميل وتأكيدها، تسوية بطاقة QR، إلغاء طلبات QR. في الانتظار: $count إجراء للطاولات.';
  }

  @override
  String tableSyncPendingBanner(int count) {
    return 'مزامنة الطاولات قيد الانتظار. تبقى إجراءات الطاولات المشتركة محدودة حتى استعادة المزامنة. في الانتظار: $count إجراء للطاولات.';
  }

  @override
  String tableParkedActionsBanner(int count) {
    return 'تحتاج $count من إجراءات الطاولات إلى مراجعة بعد رفض الخادم. هي محفوظة على هذا الجهاز ولن تعاد محاولتها تلقائيًا. راجع أخطاء المزامنة قبل إعادة المحاولة.';
  }

  @override
  String tableReplayUnverified(int count) {
    return 'تعذر التحقق من $count مسودة محفوظة للطاولات وفق إعدادات هذا الفرع. بقيت دون تغيير ولم تُرسل. راجعها قبل الاستخدام.';
  }

  @override
  String get tableReconciledTitle => 'تمت مزامنة الطاولات';

  @override
  String get tableReconciledDismiss => 'تم';

  @override
  String get tableReconciledSettings => 'الطاولات';

  @override
  String get tableReconciledHistory =>
      'آخر 200 رسالة مزامنة — تبقى المدفوعات الفاشلة في قائمة التنبيهات.';

  @override
  String get tableReconciledEmpty => 'لا توجد رسائل مزامنة للطاولات.';

  @override
  String get tableHistoryUnavailable =>
      'تعذر تحميل سجل الطاولات. أغلق هذا القسم وافتحه لإعادة المحاولة.';

  @override
  String get tableReviewReasonUnknown => 'السبب غير مذكور';

  @override
  String tableReconciledAttached(String table) {
    return 'انضمت الطاولة $table إلى الجلسة الموجودة على الخادم.';
  }

  @override
  String tableReconciledMerged(String table) {
    return 'الطاولة $table: كانت مفتوحة على جهاز آخر؛ أضيفت أصنافك إلى تلك الفاتورة وتحتاج إلى مراجعة.';
  }

  @override
  String tableReconciledClosed(String table) {
    return 'أُغلقت الطاولة $table على الخادم قبل وصول طلب فتحها.';
  }

  @override
  String tableReconciledHeld(String table, int count, String reason) {
    return 'الطاولة $table: تعذر تسعير $count صنف ($reason) — راجع بالضغط على الطاولة.';
  }

  @override
  String tableReconciledRoundStopped(String table) {
    return 'الطاولة $table: الفاتورة على الخادم مغلقة أو بانتظار الدفع؛ لم تُضف هذه الأصناف. راجع بالضغط على الطاولة.';
  }

  @override
  String tableReconciledMoveOccupied(String to, String from) {
    return 'كانت الطاولة $to مشغولة على الخادم؛ لا يزال الخادم يعرض فاتورتك على الطاولة $from.';
  }

  @override
  String tableReconciledMoveStale(String from, String to) {
    return 'لم يُطبّق النقل من الطاولة $from إلى الطاولة $to: جلسة الخادم لم تعد سارية أو لم يتم العثور عليها. تحقق من الطاولات؛ لم تتغير طاولتك المحلية.';
  }

  @override
  String tableReconciledJoin(String table, String seats) {
    return 'الطاولة $table: تعذر دمج هذه الطاولات على الخادم: $seats. تحقق من الطاولات؛ لم تتغير الطاولات المحلية.';
  }

  @override
  String tableReconciledUnpaid(String table) {
    return 'لا تزال للطاولة $table فاتورة غير مدفوعة على الخادم — اضغط على الطاولة لإلغائها أو دفعها.';
  }

  @override
  String tableReconciledCancellation(String table, int count) {
    return 'الطاولة $table: لم يُعثر على $count صنف مطلوب للإلغاء على الخادم. راجع الفاتورة بالضغط على الطاولة.';
  }

  @override
  String tableReconciledOther(String table, String outcome) {
    return 'الطاولة $table: نتيجة الخادم $outcome. راجع بالضغط على الطاولة؛ لم تتغير الطاولة المحلية.';
  }

  @override
  String get tableServerView => 'عرض الخادم';

  @override
  String tableServerFree(String age) {
    return 'الخادم: متاحة · $age';
  }

  @override
  String tableServerQr(String reference, String age) {
    return 'الخادم: ضيوف QR · $reference · $age';
  }

  @override
  String tableServerOccupied(String age) {
    return 'الخادم: مشغولة · $age';
  }

  @override
  String get tableServerReferenceDiffers => ' · المرجع مختلف';

  @override
  String tableServerNeedsReview(int count) {
    return ' + بحاجة للمراجعة ($count)';
  }

  @override
  String get tableServerPayment => 'الخادم: الدفع جارٍ';

  @override
  String tableServerStale(String age) {
    return 'عرض الخادم قديم ($age)';
  }

  @override
  String tableServerAgeSeconds(int count) {
    return '$count ث';
  }

  @override
  String tableServerAgeMinutes(int count) {
    return '$count د';
  }

  @override
  String get tableSoakTitle => 'مراقبة الطاولات (عرض الخادم)';

  @override
  String tableSoakMode(String mode) {
    return 'الوضع: $mode';
  }

  @override
  String tableSoakCursor(String value) {
    return 'المؤشر: $value';
  }

  @override
  String tableSoakLastSuccess(String value) {
    return 'آخر نجاح: $value';
  }

  @override
  String tableSoakFailures(int count) {
    return 'الإخفاقات: $count';
  }

  @override
  String tableSoakError(String value) {
    return 'آخر خطأ: $value';
  }

  @override
  String get tableSoakEmpty => 'لا توجد اختلافات مسجلة.';

  @override
  String get tableSoakCopy => 'نسخ';

  @override
  String get tableModeOff => 'إيقاف';

  @override
  String get tableModeShadow => 'مراقبة فقط';

  @override
  String get tableModeLive => 'مباشر (مراقبة فقط في T5)';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonDone => 'تم';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonPrint => 'طباعة';

  @override
  String get commonConfirm => 'تأكيد';

  @override
  String get commonBack => 'رجوع';

  @override
  String get commonContinue => 'متابعة';

  @override
  String get commonLogout => 'تسجيل الخروج';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionServer => 'الخادم';

  @override
  String get settingsSectionOperations => 'العمليات';

  @override
  String settingsStuckSalesCount(int count) {
    return 'مبيعات عالقة ($count)';
  }

  @override
  String get settingsStuckSalesSubtitle =>
      'رفض الخادم هذه المبيعات مرارًا. اضغط لعرض التفاصيل وإعادة المحاولة.';

  @override
  String get settingsStuckSalesDialogBody =>
      'تبقى هذه المبيعات محفوظة على الجهاز. إعادة المحاولة آمنة لأن الخادم يتجاهل معرّفات الأحداث المكررة.';

  @override
  String settingsGpsHeldSalesCount(int count) {
    return 'مبيعات تنتظر GPS ($count)';
  }

  @override
  String settingsAttentionSalesCount(int count) {
    return 'مبيعات تحتاج إلى متابعة ($count)';
  }

  @override
  String get settingsGpsHeldSalesSubtitle =>
      'هذه المبيعات محفوظة ولكن لا يمكن مزامنتها حتى يحصل الجهاز على موقع GPS صالح. اضغط لعرض التفاصيل وإعادة المحاولة.';

  @override
  String get settingsAttentionSalesSubtitle =>
      'بعض المبيعات تنتظر GPS، وأخرى رفضها الخادم. اضغط لعرض التفاصيل وإعادة المحاولة.';

  @override
  String get settingsGpsHeldStatus => 'في انتظار موقع GPS صالح';

  @override
  String get settingsGpsHeldSalesDialogBody =>
      'تبقى هذه المبيعات محفوظة على الجهاز وتُعاد محاولتها تلقائيًا عند توفر موقع GPS صالح.';

  @override
  String get settingsAttentionSalesDialogBody =>
      'تبقى هذه المبيعات محفوظة على الجهاز. تحتاج المبيعات المعلقة بسبب GPS إلى موقع صالح، ويمكن إعادة محاولة المبيعات المرفوضة من الخادم بأمان.';

  @override
  String get settingsRetryAll => 'إعادة محاولة الكل';

  @override
  String get settingsRetryStarted =>
      'بدأت إعادة المحاولة. ستبقى أي مبيعات مرفوضة محفوظة على هذا الجهاز.';

  @override
  String get settingsAttentionRetryStarted =>
      'بدأت إعادة المحاولة. ستبقى أي مبيعات تنتظر GPS أو قبول الخادم محفوظة على هذا الجهاز.';

  @override
  String get settingsRetryFailed =>
      'تعذر بدء إعادة المحاولة. ما زالت المبيعات محفوظة على هذا الجهاز.';

  @override
  String get settingsUnknownSyncError => 'خطأ غير معروف من الخادم';

  @override
  String get settingsServerAddress => 'عنوان الخادم';

  @override
  String get settingsServerHint => 'مثال: 192.168.1.50:8088';

  @override
  String settingsUsingDefault(String url) {
    return 'الافتراضي المدمج قيد الاستخدام: $url';
  }

  @override
  String settingsActive(String url) {
    return 'النشط: $url';
  }

  @override
  String get settingsTestConnection => 'اختبار الاتصال';

  @override
  String get settingsSaved => 'تم حفظ الإعدادات.';

  @override
  String settingsServerReachable(String url) {
    return 'يمكن الوصول إلى الخادم $url';
  }

  @override
  String settingsServerUnreachable(String url) {
    return 'تعذر الوصول إلى $url';
  }

  @override
  String get settingsResetDefault => 'إعادة الضبط الافتراضي';

  @override
  String get settingsSectionReceipts => 'الإيصالات';

  @override
  String get settingsPrintReceipts => 'طباعة الإيصالات';

  @override
  String get settingsPrintReceiptsHint => 'اطبع إيصال Sunmi عند اكتمال الطلب.';

  @override
  String get settingsPrintKitchenTickets => 'طباعة تذاكر المطبخ';

  @override
  String get settingsPrintKitchenTicketsHint =>
      'اطبع تذكرة مطبخ بالأصناف فقط عند اكتمال الطلب أو تعليقه.';

  @override
  String get settingsPrintQrKitchenRounds =>
      'طباعة جولات QR للمطبخ على هذا الجهاز';

  @override
  String get settingsPrintQrKitchenRoundsHint =>
      'اطبع جولات طلبات الطاولة عبر QR بعد قبولها. عطّلها على أجهزة الكاشير الأخرى لمنع التذاكر المكررة.';

  @override
  String get settingsSectionLanguage => 'اللغة';

  @override
  String get settingsLanguageHint => 'تُطبَّق فورًا في كامل التطبيق.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get pinLoginTitle => 'تسجيل دخول الموظف';

  @override
  String get pinLoginSubtitle => 'أدخل رمز PIN الخاص بك لتحميل هذا الفرع.';

  @override
  String get pinLoginButton => 'تسجيل الدخول';

  @override
  String pinLoginPinLengthError(int min, int max) {
    return 'أدخل رمز PIN المكوّن من $min إلى $max أرقام.';
  }

  @override
  String get pinLoginFailedError =>
      'فشل تسجيل الدخول. يُرجى المحاولة مرة أخرى.';

  @override
  String get shiftOpenTitle => 'فتح الوردية';

  @override
  String get shiftOpenSubtitle => 'قم بعدّ النقد الافتتاحي في الدرج.';

  @override
  String shiftOpenWelcomeSubtitle(String staffName) {
    return 'مرحبًا $staffName. قم بعدّ النقد الافتتاحي في الدرج.';
  }

  @override
  String get shiftOpenCheckingExisting => 'جارٍ التحقق من وجود وردية مفتوحة…';

  @override
  String get shiftOpenOpeningCashLabel => 'النقد الافتتاحي (OMR)';

  @override
  String get shiftOpenSubmitButton => 'فتح الوردية';

  @override
  String get shiftOpenErrorNoStaffSession =>
      'لا توجد جلسة موظف. يرجى تسجيل الدخول مرة أخرى.';

  @override
  String get shiftOpenErrorOpenFailed => 'تعذّر فتح الوردية. تحقق من اتصالك.';

  @override
  String get shiftOpenErrorAdoptFailed =>
      'يوجد لهذا الجهاز وردية مفتوحة بالفعل، لكن تعذّر تحميلها. تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get shiftCloseTitle => 'إغلاق الوردية';

  @override
  String get shiftCloseSubmitButton => 'إغلاق الوردية';

  @override
  String get shiftCloseNoOpenShift => 'لا توجد وردية مفتوحة على هذا الجهاز.';

  @override
  String get shiftCloseFailed => 'تعذّر إغلاق الوردية. تحقق من الاتصال.';

  @override
  String get shiftCloseOpeningFloatLabel => 'الرصيد الافتتاحي (OMR)';

  @override
  String get shiftCloseCountedDrawerCashLabel => 'النقد المعدود في الدرج (OMR)';

  @override
  String get shiftCloseDrawerBalanced => 'الدرج متوازن';

  @override
  String get shiftCloseDrawerShort => 'عجز في الدرج';

  @override
  String get shiftCloseDrawerOver => 'زيادة في الدرج';

  @override
  String get shiftCloseExpectedCash => 'النقد المتوقع';

  @override
  String get shiftCloseCountedCash => 'النقد المعدود';

  @override
  String get shiftCloseVariance => 'الفرق';

  @override
  String get shiftClosePrintSummary => 'طباعة الملخص';

  @override
  String shiftHandoverWarning(int staffId) {
    return 'هذا الدرج يخص الموظف رقم $staffId. إغلاقه ينهي وردية ذلك الموظف. بدّل الموظف إذا كان المالك سيواصل العمل.';
  }

  @override
  String get shiftHandoverSwitchStaff => 'تبديل الموظف';

  @override
  String shiftHandoverOwner(int staffId) {
    return 'مالك الوردية رقم $staffId';
  }

  @override
  String get deviceSetupTitle => 'إعداد هذا الجهاز';

  @override
  String get deviceSetupSubtitle =>
      'امسح رمز التفعيل الذي تم إنشاؤه لهذا الجهاز في بوابة الإدارة أو أدخله يدويًا. تتم هذه الخطوة مرة واحدة فقط.';

  @override
  String get deviceSetupScanQrButton => 'مسح رمز QR';

  @override
  String get deviceSetupOrEnterManually => 'أو أدخله يدويًا';

  @override
  String get deviceSetupActivationCodeLabel => 'رمز التفعيل';

  @override
  String get deviceSetupSettingsTooltip => 'الإعدادات';

  @override
  String get deviceSetupErrorEnterCode => 'أدخل رمز التفعيل من بوابة الإدارة.';

  @override
  String get deviceSetupErrorFailed =>
      'فشل إعداد الجهاز. يرجى المحاولة مرة أخرى.';

  @override
  String get deviceSetupErrorDeviceMismatch =>
      'رمز التفعيل هذا يخص جهازًا آخر. اطلب من المسؤول رمز هذا الجهاز.';

  @override
  String get deviceSetupErrorSerialMissing =>
      'تعذّرت قراءة الرقم التسلسلي لهذا الجهاز، لذلك لا يمكن التحقق من الرمز. أعد تشغيل الجهاز وحاول مرة أخرى. إذا تكرر ذلك، تواصل مع الدعم.';

  @override
  String get deviceSetupErrorAppMismatch =>
      'هذا الرمز مخصص لنوع آخر من الأجهزة. اطلب من المسؤول التحقق من نوع الجهاز، أو استخدم التطبيق المطابق.';

  @override
  String get deviceSetupErrorCameraBlocked =>
      'تم حظر الوصول إلى الكاميرا. فعِّله من الإعدادات لمسح الرمز (أو أدخله يدويًا).';

  @override
  String get deviceSetupErrorCameraPermission =>
      'يلزم إذن الكاميرا لمسح رمز QR (أو أدخله يدويًا).';

  @override
  String get terminalSetupTitle => 'ربط جهاز نقطة البيع هذا';

  @override
  String get terminalSetupSubtitle =>
      'أدخل معرّف الجهاز الطرفي قبل فتح نقطة البيع للموظفين. تُحفظ هذه القيمة محليًا وتُستخدم لطلبات الدفع عبر جهاز الدفع.';

  @override
  String get terminalSetupTerminalIdLabel => 'معرّف الجهاز الطرفي';

  @override
  String get terminalSetupTerminalIdHint => 'أدخل معرّف جهاز الدفع';

  @override
  String get terminalSetupTerminalIdRequired =>
      'يرجى إدخال معرّف الجهاز الطرفي.';

  @override
  String terminalSetupSaveFailed(String error) {
    return 'تعذّر حفظ معرّف الجهاز الطرفي: $error';
  }

  @override
  String get terminalSetupContinueButton => 'المتابعة إلى نقطة البيع';

  @override
  String get qrScannerTitle => 'مسح رمز التفعيل';

  @override
  String get qrScannerSwitchCameraTooltip => 'تبديل الكاميرا';

  @override
  String get qrScannerHint =>
      'وجّه الكاميرا نحو رمز QR الخاص بالتفعيل. إذا لم تعمل، اضغط على أيقونة تبديل الكاميرا، أو ارجع وأدخل الرمز يدويًا.';

  @override
  String qrScannerCameraStartError(String code) {
    return 'تعذّر تشغيل الكاميرا ($code).';
  }

  @override
  String get qrScannerErrorHelp =>
      'جرّب أيقونة تبديل الكاميرا في الأعلى، أو استخدم ماسح الجهاز، أو أدخل الرمز يدويًا.';

  @override
  String get qrScannerEnterManuallyButton => 'إدخال الرمز يدويًا';

  @override
  String get geofenceCheckingLocationTitle => 'جارٍ التحقق من الموقع…';

  @override
  String get geofenceCheckingLocationMessage =>
      'جارٍ تحديد موقع GPS لهذا الفرع.';

  @override
  String get geofenceLocationRequiredTitle => 'الموقع مطلوب';

  @override
  String get geofenceLocationRequiredMessage =>
      'فعّل خدمات الموقع وامنح الإذن لاستخدام نقطة البيع.';

  @override
  String get geofenceOutsideTitle => 'خارج نطاق المتجر';

  @override
  String get geofenceLockedTitle => 'مقفل';

  @override
  String get geofenceOutsideNoDistanceMessage =>
      'هذا الجهاز خارج نطاق الفرع المسموح به.';

  @override
  String geofenceOutsideDistanceMessage(int distance, int radius) {
    return 'أنت على بُعد $distance م تقريبًا من الفرع (المسموح ضمن $radius م). اقترب أكثر، أو اضغط \"إعادة المحاولة\" لجلب أحدث موقع/نطاق للفرع كما حدده المسؤول.';
  }

  @override
  String get expenseTitle => 'تسجيل مصروف';

  @override
  String get expenseCategoryLabel => 'الفئة';

  @override
  String get expenseAmountOmrLabel => 'المبلغ (ر.ع.)';

  @override
  String get expenseNoteOptionalLabel => 'ملاحظة (اختياري)';

  @override
  String get expenseRecordButton => 'تسجيل المصروف';

  @override
  String get expenseRecordedMessage => 'تم تسجيل المصروف.';

  @override
  String get expenseAmountGreaterThanZeroError => 'أدخل مبلغًا أكبر من صفر.';

  @override
  String get expenseSubmitFailedError =>
      'تعذر تسجيل المصروف. تحقق من الاتصال بالإنترنت.';

  @override
  String get expenseCategoryUtilities => 'المرافق';

  @override
  String get expenseCategorySupplies => 'المستلزمات';

  @override
  String get expenseCategoryMaintenance => 'الصيانة';

  @override
  String get expenseCategorySalaries => 'الرواتب';

  @override
  String get expenseCategoryOther => 'أخرى';

  @override
  String get restockTitle => 'طلب إعادة توريد';

  @override
  String get restockAddIngredientLabel => 'إضافة مكوّن';

  @override
  String get restockIngredientHint => 'المكوّن';

  @override
  String get restockQtyHint => 'الكمية';

  @override
  String get restockNoteLabel => 'ملاحظة (اختياري)';

  @override
  String get restockSubmitButton => 'إرسال الطلب';

  @override
  String get restockSubmittedSnack => 'تم إرسال طلب إعادة التوريد.';

  @override
  String get restockSubmitFailedError =>
      'تعذّر إرسال الطلب. يرجى التحقق من الاتصال.';

  @override
  String get restockPickIngredientError => 'يرجى اختيار مكوّن.';

  @override
  String get restockQuantityError => 'أدخل كمية أكبر من صفر.';

  @override
  String get restockAddAtLeastOneError => 'أضف مكوّناً واحداً على الأقل.';

  @override
  String get restockEmptyState =>
      'لا توجد مكوّنات متاحة بعد.\nقم بمزامنة الجهاز لتحميل الكتالوج.';

  @override
  String restockIngredientFallback(int id) {
    return 'المكوّن رقم $id';
  }

  @override
  String get stockCountTitle => 'جرد المخزون نهاية اليوم';

  @override
  String get stockCountInstructions =>
      'عُدّ ما هو موجود فعليًا على الرف. اترك الصف فارغًا لتخطيه. يُسجَّل النقص كهدر، والزيادة كتسوية.';

  @override
  String stockCountInvalidCount(String name) {
    return 'قيمة الجرد غير صالحة للمكوّن $name.';
  }

  @override
  String stockCountWholeUnitsOnly(String name, String unitLabel) {
    return '$name يُعدّ بوحدات كاملة من $unitLabel.';
  }

  @override
  String get stockCountEnterAtLeastOne => 'أدخل كمية معدودة واحدة على الأقل.';

  @override
  String get stockCountSubmitted => 'تم إرسال الجرد.';

  @override
  String get stockCountSubmitFailed => 'تعذر إرسال الجرد. تحقق من الاتصال.';

  @override
  String stockCountRowCountInPieces(String pieceLabel) {
    return 'العدّ بوحدة $pieceLabel';
  }

  @override
  String stockCountRowCountInUnit(String unit) {
    return 'العدّ بوحدة $unit';
  }

  @override
  String get stockCountQtyHint => 'الكمية';

  @override
  String get stockCountNoteLabel => 'ملاحظة (اختياري)';

  @override
  String stockCountSubmitButton(int count) {
    return 'إرسال الجرد ($count)';
  }

  @override
  String get stockCountEmptyState =>
      'لا توجد مكوّنات متاحة بعد.\nقم بمزامنة الجهاز لتحميل الكتالوج.';

  @override
  String get wasteProductTitle => 'تسجيل الهدر';

  @override
  String get wasteProductInstructions =>
      'أدخل كمية كل منتج مطبوخ أو مخزّن تم هدره، ثم اختر السبب. اترك الصف فارغًا لتجاهله.';

  @override
  String get wasteProductEmptyState =>
      'لا توجد منتجات مطبوخة أو مخزّنة في هذا الفرع بعد.\nقم بمزامنة الجهاز لتحميل الكتالوج.';

  @override
  String wasteProductOnShelf(String qty) {
    return 'على الرف: $qty';
  }

  @override
  String get wasteProductReasonLabel => 'السبب';

  @override
  String get wasteProductNoteLabel => 'ملاحظة (اختياري)';

  @override
  String get wasteProductNoteRequiredForOther => 'أضف ملاحظة توضّح سبب الهدر.';

  @override
  String get wasteProductEnterAtLeastOne => 'أدخل كمية لمنتج واحد على الأقل.';

  @override
  String wasteProductInvalidQty(String name) {
    return 'كمية غير صحيحة لـ $name.';
  }

  @override
  String wasteProductSubmitButton(int count) {
    return 'تسجيل الهدر ($count)';
  }

  @override
  String wasteProductSubmitted(int count) {
    return 'تم تسجيل هدر $count منتج.';
  }

  @override
  String get wasteProductSubmitFailed => 'تعذّر تسجيل الهدر. حاول مرة أخرى.';

  @override
  String get wasteReasonExpired => 'منتهي الصلاحية';

  @override
  String get wasteReasonSpoiled => 'تالف';

  @override
  String get wasteReasonBroken => 'مكسور';

  @override
  String get wasteReasonDropped => 'سقط';

  @override
  String get wasteReasonContamination => 'تلوّث';

  @override
  String get wasteReasonOther => 'أخرى';

  @override
  String get displayOrderTypeQuickOrder => 'طلب سريع';

  @override
  String get displayOrderTypeToGo => 'سفري';

  @override
  String get displayOrderTypeDelivery => 'توصيل';

  @override
  String get displayOrderTypeDineIn => 'محلي';

  @override
  String get displayStatusWaiting => 'بانتظار الدفع';

  @override
  String get displayStatusPaid => 'مدفوع';

  @override
  String get displayStatusPaidPendingRecon => 'مدفوع (بانتظار التسوية)';

  @override
  String get displayStatusAwaitingConfirmation => 'بانتظار التأكيد';

  @override
  String get displayStatusCardNotConfirmed => 'لم يتم تأكيد خصم البطاقة';

  @override
  String get displayStatusPaymentCanceled => 'أُلغي الدفع';

  @override
  String get displayStatusPreparingPayment => 'جارٍ تجهيز الدفع';

  @override
  String get displayStatusProcessingPayment => 'جارٍ معالجة الدفع';

  @override
  String get displayStatusSplitPending => 'دفعة مقسّمة قيد الإكمال';

  @override
  String get displayStatusCanceled => 'ملغي';

  @override
  String get displayStatusPartiallyCanceled => 'ملغي جزئيًا';

  @override
  String get displayStatusVoid => 'ملغي';

  @override
  String get displayStatusRefunded => 'مسترد';

  @override
  String get displayMethodCash => 'نقدًا';

  @override
  String get displayMethodCard => 'بطاقة ائتمان';

  @override
  String get displayMethodSplit => 'دفع مقسّم';

  @override
  String get cdProcessingSelectionTitle => 'جارٍ معالجة الاختيار';

  @override
  String get cdPreparingPaymentTitle => 'جارٍ تجهيز الدفع';

  @override
  String get cdProcessingSelectionMessage =>
      'يرجى الانتظار بينما نؤكد اختيارك ونفتح جهاز الدفع.';

  @override
  String get cdPreparingPaymentMessage =>
      'يرجى الانتظار بينما يتم فتح جهاز الدفع.';

  @override
  String get cdHeaderPaymentCompleted => 'تم الدفع بنجاح';

  @override
  String get cdHeaderReviewCharity =>
      'راجع خيار تقريب المبلغ للتبرع الخيري قبل الدفع';

  @override
  String get cdHeaderItemsWillAppear => 'ستظهر الأصناف والإجمالي هنا';

  @override
  String cdHeaderItemLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بند في الطلب الحالي',
      many: '$count بندًا في الطلب الحالي',
      few: '$count بنود في الطلب الحالي',
      two: 'بندان في الطلب الحالي',
      one: 'بند واحد في الطلب الحالي',
      zero: 'لا توجد بنود في الطلب الحالي',
    );
    return '$_temp0';
  }

  @override
  String cdHeaderTableItemLineCount(String table, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count بند في الطلب الحالي',
      many: '$count بندًا في الطلب الحالي',
      few: '$count بنود في الطلب الحالي',
      two: 'بندان في الطلب الحالي',
      one: 'بند واحد في الطلب الحالي',
      zero: 'لا توجد بنود في الطلب الحالي',
    );
    return 'الطاولة $table | $_temp0';
  }

  @override
  String get cdHeroRoundUpForCharity => 'التقريب للتبرع الخيري';

  @override
  String get cdHeroReadyForOrder => 'جاهزون لاستقبال طلبك';

  @override
  String get cdHeroOrderTotal => 'إجمالي الطلب';

  @override
  String get cdHeroCharityNote =>
      'سيُتبرّع بالمبلغ الإضافي الناتج عن التقريب للجهة الخيرية.';

  @override
  String get cdHeroReviewNote => 'يرجى مراجعة الأصناف والإجمالي قبل الدفع.';

  @override
  String get cdSubtotalLabel => 'المجموع الفرعي';

  @override
  String get cdTaxLabel => 'الضريبة';

  @override
  String get cdPaymentLabel => 'الدفع';

  @override
  String get cdOrderDetailsTitle => 'تفاصيل الطلب';

  @override
  String get cdOrderDetailsSubtitle =>
      'عرض مباشر للطلب على الشاشة المواجهة للعميل';

  @override
  String get cdBannerThankYou => 'شكرًا لزيارتكم. تم إكمال طلبكم.';

  @override
  String get cdBannerReviewWhileCashier =>
      'يرجى مراجعة تفاصيل الطلب بينما يجهّز الكاشير عملية الدفع.';

  @override
  String get cdTapToPayTitle => 'المس هنا للدفع';

  @override
  String get cdTapToPaySubtitle =>
      'عملية الدفع جاهزة. يرجى تمرير البطاقة أو الهاتف على منطقة NFC المواجهة للعميل.';

  @override
  String get cdContactlessReadyTitle => 'جاهز للدفع اللاتلامسي';

  @override
  String get cdContactlessHoldHint =>
      'قرّب البطاقة أو الهاتف أو الساعة الذكية من منطقة NFC الخلفية حتى يؤكد الجهاز إتمام العملية.';

  @override
  String get cdChipCard => 'بطاقة';

  @override
  String get cdChipPhone => 'هاتف';

  @override
  String get cdChipWearable => 'ساعة ذكية';

  @override
  String get cdTotalToPay => 'الإجمالي المستحق';

  @override
  String cdIncludesCharityRoundUp(String amount) {
    return 'يشمل $amount من تقريب المبلغ للتبرع الخيري.';
  }

  @override
  String get cdPresentToContinue =>
      'قرّب بطاقتك أو هاتفك أو ساعتك الذكية لمتابعة عملية الدفع.';

  @override
  String get cdTapFooterKeepNear =>
      'أبقِ البطاقة أو الهاتف قرب منطقة NFC المواجهة للعميل حتى يؤكد الجهاز عملية الدفع.';

  @override
  String get cdCharityTitle => 'هل تودّ التقريب للتبرع الخيري؟';

  @override
  String get cdCharityQuestion =>
      'هل تودّ تقريب مبلغ الدفع إلى أقرب OMR كامل؟ سيُتبرّع بالمبلغ الإضافي فقط للجهة الخيرية.';

  @override
  String get cdCharityEncouragement =>
      'تقريب بسيط للمبلغ قد يصنع تبرعًا ذا أثر مع إبقاء عملية الدفع سهلة.';

  @override
  String get cdCharityTileOrderTotal => 'إجمالي الطلب';

  @override
  String get cdCharityTileOrderTotalCaption => 'قيمة الطلب الحالية';

  @override
  String get cdCharityTileRoundUp => 'مبلغ التقريب';

  @override
  String get cdCharityTileRoundUpCaption => 'مبلغ التبرع الإضافي';

  @override
  String get cdCharityTileNewTotal => 'الإجمالي الجديد';

  @override
  String get cdCharityTileNewTotalCaption => 'المبلغ النهائي المستحق';

  @override
  String get cdCharityNo => 'لا';

  @override
  String get cdCharityNoSubtitleShort => 'إبقاء الإجمالي الأصلي';

  @override
  String get cdCharityNoSubtitle => 'دفع إجمالي الطلب الأصلي';

  @override
  String get cdCharityYes => 'نعم';

  @override
  String get cdCharityYesSubtitleShort => 'قرّب المبلغ للتبرع';

  @override
  String get cdCharityYesSubtitle => 'تقريب المبلغ والتبرع بالفارق';

  @override
  String cdTouchOkCount(int count) {
    return 'اللمس يعمل ×$count';
  }

  @override
  String get cdTouchTestTitle => 'اختبار اللمس';

  @override
  String get cdTouchTestHint => 'انقر هنا للتحقق';

  @override
  String cdTouchDetectedAt(String time, int count) {
    return 'تم رصد لمسة على الشاشة الخلفية عند $time (#$count)';
  }

  @override
  String get cdBadgeUpdatingChoice => 'جارٍ تحديث الاختيار';

  @override
  String get cdBadgeSecureCardPayment => 'دفع آمن بالبطاقة';

  @override
  String cdQuantity(int qty) {
    return 'الكمية: $qty';
  }

  @override
  String get cdNoItemsYet => 'لا توجد أصناف بعد';

  @override
  String get cdEmptyStateHint =>
      'سيتم تحديث الشاشة فور إضافة الكاشير للمنتجات.';

  @override
  String get cdFinalBadge => 'النهائي';

  @override
  String get cdSummaryPaid => 'شكرًا لكم. تم إكمال عملية الدفع.';

  @override
  String get cdSummaryAwaitingCashier =>
      'سيؤكد الكاشير الطلب ويُكمل الدفع عند الجاهزية.';

  @override
  String get ctrlMsgChooseTableDineIn =>
      'اختر طاولة لبدء طلب داخل المطعم أو متابعته.';

  @override
  String ctrlMsgEditingTableOnFloor(String table, String floor) {
    return 'جارٍ تعديل الطاولة $table في $floor.';
  }

  @override
  String ctrlMsgAddItemsForTable(String table) {
    return 'أضف الأصناف للطاولة $table.';
  }

  @override
  String ctrlMsgAssignItemsToTable(String table) {
    return 'جارٍ إسناد الأصناف الحالية إلى الطاولة $table.';
  }

  @override
  String get ctrlFloorFallbackDining => 'الصالة';

  @override
  String ctrlMsgOrderHeld(String reference) {
    return 'تم تعليق الطلب ذي المرجع $reference.';
  }

  @override
  String get ctrlMsgHoldFailed => 'تعذر تعليق الطلب في الوقت الحالي.';

  @override
  String ctrlMsgOrderResumed(String reference) {
    return 'تمت استعادة الطلب المعلق ذي المرجع $reference.';
  }

  @override
  String ctrlMsgHeldOrderDiscarded(String reference) {
    return 'تم حذف الطلب المعلق ذي المرجع $reference.';
  }

  @override
  String ctrlMsgOrderAlreadyCanceled(int n) {
    return 'الطلب #$n ملغى بالكامل بالفعل.';
  }

  @override
  String get ctrlMsgNoCancellableItems =>
      'لم يتم تحديد أي أصناف قابلة للإلغاء.';

  @override
  String get ctrlMsgOrderCanceledByManagerNote =>
      'تم إلغاء الطلب بواسطة المدير.';

  @override
  String ctrlMsgItemsCanceledByManagerNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إلغاء $count صنفًا بواسطة المدير.',
      few: 'تم إلغاء $count أصناف بواسطة المدير.',
      two: 'تم إلغاء صنفين بواسطة المدير.',
      one: 'تم إلغاء صنف واحد بواسطة المدير.',
    );
    return '$_temp0';
  }

  @override
  String ctrlMsgOrderFullyCanceled(int n) {
    return 'تم إلغاء الطلب #$n بالكامل.';
  }

  @override
  String ctrlMsgItemsCanceledFromOrder(int count, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إلغاء $count صنفًا',
      few: 'تم إلغاء $count أصناف',
      two: 'تم إلغاء صنفين',
      one: 'تم إلغاء صنف واحد',
    );
    return '$_temp0 من الطلب #$n.';
  }

  @override
  String ctrlMsgPaymentCanceledWithMethod(String method) {
    return 'تم إلغاء الدفع ($method).';
  }

  @override
  String get ctrlMsgCustomerResponseTimeout => 'انتهت مهلة انتظار رد العميل.';

  @override
  String ctrlMsgTenderedCashTooLow(String amount) {
    return 'يجب ألا يقل المبلغ النقدي المستلم عن $amount.';
  }

  @override
  String ctrlMsgCashierCompletingSplitCash(int index, int total) {
    return 'يقوم الكاشير بإتمام الدفعة النقدية $index من $total لتقسيم الفاتورة.';
  }

  @override
  String get ctrlMsgCashierCompletingCash =>
      'يقوم الكاشير بإتمام الدفع النقدي.';

  @override
  String get ctrlMsgCashPaymentRecorded => 'تم تسجيل الدفع النقدي بنجاح.';

  @override
  String get ctrlMsgCashPaymentCompleted => 'اكتمل الدفع النقدي. شكرًا لك.';

  @override
  String get ctrlMsgPaidSaleKeptForReview =>
      'تم استلام الدفع، لكن تعذّر حفظ هذه العملية للإرسال. تم الاحتفاظ بها على هذا الجهاز لمراجعة المدير. لا تحصّل المبلغ من العميل مرة أخرى.';

  @override
  String get ctrlMsgTapToPayRoundUp =>
      'شكرًا لتقريب المبلغ للتبرع الخيري. قرّب بطاقتك أو هاتفك من منطقة NFC الخلفية لإتمام الدفع.';

  @override
  String get ctrlMsgTapToPay =>
      'قرّب بطاقتك أو هاتفك من منطقة NFC الخلفية لإتمام الدفع.';

  @override
  String get ctrlMsgCardPendingReconRecorded =>
      'تم تسجيل عملية البطاقة قيد التسوية، وستؤكدها تسوية البنك.';

  @override
  String get ctrlMsgCardNoTerminalAssigned =>
      'لا يوجد جهاز دفع مُعيَّن لهذا الجهاز بعد. الدفع بالبطاقة غير متاح — اطلب من المسؤول تعيين جهاز دفع.';

  @override
  String get ctrlMsgPaymentPendingBankThanks =>
      'تم تسجيل الدفع بانتظار تأكيد البنك. شكرًا لك.';

  @override
  String ctrlMsgCardApprovedRoundUpThanks(String message) {
    return '$message شكرًا لدعمك العمل الخيري.';
  }

  @override
  String get ctrlMsgPaymentApprovedRoundUpNote =>
      'تمت الموافقة على الدفع. سيُوجَّه مبلغ التقريب تبرعًا للجهة الخيرية. شكرًا لك.';

  @override
  String get ctrlMsgPaymentApprovedNote => 'تمت الموافقة على الدفع. شكرًا لك.';

  @override
  String get ctrlMsgClearSplitBillFirst =>
      'ألغِ تقسيم الفاتورة قبل استخدام الدفع المقسّم نقدًا وبالبطاقة.';

  @override
  String ctrlMsgEnterCashBelowTotal(String amount) {
    return 'أدخل مبلغًا نقديًا أقل من $amount قبل استخدام الدفع المقسّم.';
  }

  @override
  String get ctrlMsgSplitPaymentCanceled => 'تم إلغاء الدفع المقسّم.';

  @override
  String get ctrlMsgTapForRemainingSplitRoundUp =>
      'شكرًا لتقريب المبلغ للتبرع الخيري. قرّب بطاقتك أو هاتفك لدفع المبلغ المتبقي.';

  @override
  String get ctrlMsgTapForRemainingSplit =>
      'قرّب بطاقتك أو هاتفك لدفع المبلغ المتبقي.';

  @override
  String ctrlMsgSplitRecordedCardPending(String cash, String card) {
    return 'تم تسجيل الدفع المقسّم: نقدًا $cash، وبالبطاقة $card قيد التسوية.';
  }

  @override
  String ctrlMsgSplitCompletedCashCard(String cash, String card) {
    return 'اكتمل الدفع المقسّم: تم تسجيل $cash نقدًا و$card بالبطاقة.';
  }

  @override
  String get ctrlMsgCashReceivedCardPendingNote =>
      'تم استلام النقد، وتم تسجيل دفعة البطاقة بانتظار تأكيد البنك. شكرًا لك.';

  @override
  String get ctrlMsgSplitCompletedRoundUpNote =>
      'اكتمل الدفع المقسّم مع تبرع بتقريب مبلغ البطاقة. شكرًا لك.';

  @override
  String get ctrlMsgSplitCompletedNote => 'اكتمل الدفع المقسّم. شكرًا لك.';

  @override
  String ctrlMsgSplitProgressRecorded(int index, int total, int next) {
    return 'تم تسجيل الدفعة $index من $total. تابع مع الضيف $next.';
  }

  @override
  String ctrlMsgGuestPaidCollectNext(
    int index,
    String amount,
    int next,
    int total,
  ) {
    return 'دفع الضيف $index مبلغ $amount. حصّل الدفعة $next من $total.';
  }

  @override
  String ctrlMsgSplitCompletedSummary(int total, String amount) {
    return 'اكتمل الدفع المقسّم. تم تسجيل $total من الدفعات بإجمالي $amount.';
  }

  @override
  String ctrlMsgSplitBillCompletedNote(int total) {
    return 'اكتمل تقسيم الفاتورة بعدد $total من الدفعات. شكرًا لك.';
  }

  @override
  String ctrlMsgRoundUpPromptQuestion(String amount) {
    return 'هل ترغب في تقريب المبلغ والتبرع بـ$amount للجهة الخيرية؟';
  }

  @override
  String get ctrlOverlayPreparingCashPayment => 'جارٍ تجهيز الدفع النقدي';

  @override
  String get ctrlOverlayPreparingSecurePayment => 'جارٍ تجهيز الدفع الآمن';

  @override
  String get ctrlMsgPreparingRoundedCash =>
      'شكرًا لك. نجهّز المبلغ المقرّب للدفع النقدي.';

  @override
  String get ctrlMsgPreparingRoundedCard =>
      'شكرًا لك. نجهّز المبلغ المقرّب للدفع بالبطاقة.';

  @override
  String get ctrlMsgPreparingOriginalCash =>
      'شكرًا لك. نجهّز المبلغ الأصلي للدفع النقدي.';

  @override
  String get ctrlMsgPreparingOriginalCard =>
      'شكرًا لك. نجهّز المبلغ الأصلي للدفع بالبطاقة.';

  @override
  String get ctrlMsgCardUnconfirmedReviewing =>
      'تعذر تأكيد عملية البطاقة. يقوم الموظف بمراجعة الدفع.';

  @override
  String get ctrlOverlayConnectingTerminal => 'جارٍ الاتصال بجهاز الدفع';

  @override
  String get ctrlOverlayWaitingPaymentResult => 'بانتظار نتيجة الدفع';

  @override
  String get ctrlMsgTerminalOpening =>
      'يتم فتح جهاز الدفع بأمان. يرجى الانتظار ريثما يجهّز الجهاز العملية.';

  @override
  String get ctrlMsgRoundedSentToTerminal =>
      'تم إرسال المبلغ المقرّب إلى جهاز الدفع. يرجى اتباع تعليمات الجهاز بينما ننتظر الرد النهائي.';

  @override
  String get ctrlMsgTotalSentToTerminal =>
      'تم إرسال إجمالي الطلب إلى جهاز الدفع. يرجى اتباع تعليمات الجهاز بينما ننتظر الرد النهائي.';

  @override
  String get managerAuthRegisterTitle => 'تسجيل بصمة المدير';

  @override
  String get managerAuthRegisterSubtitle => 'إعداد تفويض المدير';

  @override
  String get managerAuthRegisterDescription =>
      'ضع بصمة المدير على مستشعر الجهاز.';

  @override
  String get managerAuthApprovalRequiredTitle => 'موافقة المدير مطلوبة';

  @override
  String get managerAuthCancelOrderSubtitle => 'إلغاء طلب مكتمل';

  @override
  String get managerAuthCancelOrderDescription =>
      'ضع بصمتك للسماح بإلغاء الطلب.';

  @override
  String get managerAuthDefaultSubtitle => 'موافقة المدير';

  @override
  String get managerAuthDefaultDescription => 'ضع بصمة المدير للموافقة.';

  @override
  String get posCompNothingTitle => 'لا توجد أصناف للضيافة';

  @override
  String get posCompNothingMessage => 'أضف أصنافًا إلى الطلب أولًا.';

  @override
  String get posCompAppliedTitle => 'تم تطبيق الضيافة';

  @override
  String posCompExistingMessage(String reason, String amount) {
    return 'تُطبَّق ضيافة \"$reason\" بقيمة $amount على هذا الطلب.';
  }

  @override
  String get posCompRemoveButton => 'إزالة الضيافة';

  @override
  String get posCompKeepButton => 'إبقاء';

  @override
  String get posCompRemovedTitle => 'تمت إزالة الضيافة';

  @override
  String get posCompRemovedMessage => 'عاد الطلب إلى إجماليه الكامل.';

  @override
  String get posCompRegisterManagerMessage =>
      'سجّل بصمة المدير مرة واحدة قبل تطبيق الضيافة على الأصناف.';

  @override
  String get posCompManagerApprovalMessage =>
      'الضيافة تتطلب موافقة المدير دائمًا.';

  @override
  String get posCompLockedTitle => 'الضيافة مقفلة';

  @override
  String get posCompDialogTitle => 'ضيافة (المدير)';

  @override
  String get posCompWhatLabel => 'ما الذي ستشمله الضيافة؟';

  @override
  String get posCompWholeOrderOption => 'الطلب بالكامل';

  @override
  String get posCompReasonLabel => 'السبب';

  @override
  String posCompAmountLabel(String amount) {
    return 'قيمة الضيافة: $amount';
  }

  @override
  String posCompExceedsCapMessage(String reason, String cap) {
    return 'يتجاوز حد \"$reason\" البالغ $cap.';
  }

  @override
  String get posCompApplyButton => 'تطبيق الضيافة';

  @override
  String posCompAppliedMessage(String reason, String amount) {
    return '\"$reason\" — تم شطب $amount.';
  }

  @override
  String get posManagerRegisterFingerprintTitle => 'تسجيل بصمة المدير';

  @override
  String get posManagerApprovalRequiredTitle => 'موافقة المدير مطلوبة';

  @override
  String get posManagerFingerprintNotApprovedMessage =>
      'لم تتم الموافقة ببصمة المدير.';

  @override
  String get posManagerRegisterSensorMessage =>
      'ضع إصبع المدير على المستشعر لتفعيل إلغاء الطلبات.';

  @override
  String get posManagerRegisteredTitle => 'تم تسجيل المدير';

  @override
  String get posManagerRegistrationNotCompletedTitle => 'لم يكتمل التسجيل';

  @override
  String get posManagerRegisteredMessage =>
      'موافقة بصمة المدير جاهزة لإلغاء الطلبات.';

  @override
  String get posManagerNotRegisteredMessage =>
      'لم تُسجَّل بصمة المدير على هذا الجهاز.';

  @override
  String get posPayTenderedTooLowTitle => 'المبلغ المستلم غير كافٍ';

  @override
  String posPayTenderedTooLowMessage(String amount) {
    return 'يجب ألا يقل النقد المستلم عن $amount.';
  }

  @override
  String get posPayClearSplitFirstTitle => 'أنهِ تقسيم الفاتورة أولًا';

  @override
  String get posPayClearSplitFirstMessage =>
      'يمكن استخدام الدفع المقسّم بين النقد والبطاقة بعد إلغاء تقسيم فاتورة الضيوف.';

  @override
  String get posPayEnterCashPortionTitle => 'أدخل الجزء النقدي';

  @override
  String posPayEnterCashPortionMessage(String amount) {
    return 'أدخل المبلغ النقدي أولًا، ويجب أن يكون أقل من $amount ليُدفع الباقي بالبطاقة.';
  }

  @override
  String get posHoldOrderHeldTitle => 'تم تعليق الطلب';

  @override
  String get posHeldOrdersTitle => 'الطلبات المعلّقة';

  @override
  String get posHeldOrdersSubtitle =>
      'استأنف أي تذكرة معلّقة وتابع من حيث توقفت.';

  @override
  String get posHeldResumedTitle => 'تم استئناف الطلب المعلّق';

  @override
  String get posHeldDiscardConfirmTitle => 'حذف الطلب المعلّق؟';

  @override
  String posHeldDiscardConfirmMessage(String reference) {
    return 'سيُحذف المرجع $reference ولن يمكن استئنافه بعد ذلك.';
  }

  @override
  String get posHeldKeepButton => 'الاحتفاظ به';

  @override
  String get posHeldDiscardButton => 'حذف';

  @override
  String get posHeldDiscardedTitle => 'تم حذف الطلب المعلّق';

  @override
  String get posHistoryTitle => 'سجل الطلبات';

  @override
  String get posHistorySubtitle =>
      'راجع الطلبات المكتملة وتفاصيل دفعها وأعد طباعة الإيصالات عند الحاجة.';

  @override
  String get posHistoryReceiptPrintedTitle => 'تمت طباعة الإيصال';

  @override
  String posHistoryReceiptPrintedMessage(int orderNumber) {
    return 'أُرسل الإيصال السابق للطلب رقم $orderNumber إلى الطابعة.';
  }

  @override
  String get posKitchenReprintSubtitle => 'إعادة طباعة تذكرة المطبخ';

  @override
  String posKitchenReprintDescription(int orderNumber) {
    return 'ضع بصمة المدير لإعادة طباعة تذكرة المطبخ للطلب رقم $orderNumber.';
  }

  @override
  String get posKitchenApprovalRequiredTitle => 'الموافقة مطلوبة';

  @override
  String get posKitchenApprovalDeniedMessage =>
      'لم يمنح المدير الموافقة على إعادة طباعة تذكرة المطبخ.';

  @override
  String get posKitchenTicketPrintedTitle => 'تمت طباعة تذكرة المطبخ';

  @override
  String posKitchenTicketPrintedMessage(int orderNumber) {
    return 'أُرسلت تذكرة المطبخ للطلب رقم $orderNumber إلى الطابعة.';
  }

  @override
  String get posCancelReqNotAllowedTitle => 'الإلغاء غير مسموح';

  @override
  String get posCancelReqNotAllowedMessage =>
      'دورك الوظيفي غير مخوّل بإلغاء الطلبات على هذا الجهاز.';

  @override
  String get posCancelReqRegisterManagerMessage =>
      'سجّل بصمة المدير مرة واحدة قبل إلغاء هذا الطلب المكتمل.';

  @override
  String get posCancelReqManagerRequiredTitle => 'بصمة المدير مطلوبة';

  @override
  String get posCancelReqUnlockMessage => 'ضع بصمة المدير لفتح خاصية الإلغاء.';

  @override
  String get posCancelReqLockedTitle => 'الإلغاء مقفل';

  @override
  String get posCancelReqOrderCanceledTitle => 'تم إلغاء الطلب';

  @override
  String get posCancelReqItemsCanceledTitle => 'تم إلغاء أصناف';

  @override
  String get posCancelReqDialogTitle => 'إلغاء الطلب';

  @override
  String get posSearchProductsTitle => 'البحث عن المنتجات';

  @override
  String get posSearchProductsHint => 'اكتب اسم المنتج أو الفئة';

  @override
  String get posSearchTablesTitle => 'البحث عن الطاولات';

  @override
  String get posSearchTablesHint => 'ابحث باسم الطاولة أو رقم التذكرة';

  @override
  String get posCustomerSearchOption => 'البحث عن عميل';

  @override
  String get posCustomerSearchOptionSubtitle =>
      'ابحث بالاسم / الهاتف / رقم اللوحة مع عرض رصيد الولاء';

  @override
  String get posCustomerEnterNumberOption => 'إدخال رقم';

  @override
  String get posCustomerClearOption => 'إزالة العميل';

  @override
  String get posCustomerAttachedTitle => 'تم ربط العميل';

  @override
  String posCustomerAttachedWithPoints(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة',
      many: '$count نقطة',
      few: '$count نقاط',
      two: 'نقطتان',
      one: 'نقطة واحدة',
    );
    return '$name  ·  $_temp0';
  }

  @override
  String posCustomerAttachedSummary(String name, String summary) {
    return '$name  ·  $summary';
  }

  @override
  String get posCustomerNumberTitle => 'رقم العميل';

  @override
  String get posCustomerNumberHint => 'أدخل الرقم ليتم جلب رصيد الولاء';

  @override
  String get posCustomerNotFoundTitle => 'لم يتم العثور على عميل';

  @override
  String posCustomerNotFoundMessage(String query) {
    return 'لا يوجد عميل مطابق لـ \"$query\". تم الاحتفاظ به كمرجع للطلب.';
  }

  @override
  String posLoyaltySummaryPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة',
      many: '$count نقطة',
      few: '$count نقاط',
      two: 'نقطتان',
      one: 'نقطة واحدة',
    );
    return '$_temp0';
  }

  @override
  String posLoyaltySummaryStamps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طابع',
      many: '$count طابعًا',
      few: '$count طوابع',
      two: 'طابعان',
      one: 'طابع واحد',
    );
    return '$_temp0';
  }

  @override
  String get posLoyaltyNoneYet => 'لا يوجد رصيد ولاء بعد';

  @override
  String get posLoyaltyRedeemButton => 'استبدال';

  @override
  String get posLoyaltyRewardRedeemedTitle => 'تم استبدال المكافأة';

  @override
  String posLoyaltyStampRedeemedMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طابع',
      many: '$count طابعًا',
      few: '$count طوابع',
      two: 'طابعان',
      one: 'طابع واحد',
    );
    return '$_temp0 → خصم $amount.';
  }

  @override
  String get posLoyaltyNoCustomerTitle => 'لا يوجد عميل';

  @override
  String get posLoyaltyNoCustomerMessage =>
      'اربط عميلًا أولًا لاستبدال رصيد الولاء.';

  @override
  String get posLoyaltyNothingToRedeemTitle => 'لا يوجد ما يمكن استبداله';

  @override
  String get posLoyaltyNothingToRedeemMessage =>
      'لا توجد نقاط أو طوابع قابلة للاستبدال لهذا الطلب بعد.';

  @override
  String get posLoyaltyCannotRedeemTitle => 'تعذر الاستبدال';

  @override
  String get posLoyaltyCannotRedeemMessage =>
      'إجمالي الطلب أقل من الحد الأدنى لاستبدال شريحة نقاط.';

  @override
  String get posLoyaltyPointsRedeemedTitle => 'تم استبدال النقاط';

  @override
  String posLoyaltyPointsRedeemedMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة',
      many: '$count نقطة',
      few: '$count نقاط',
      two: 'نقطتان',
      one: 'نقطة واحدة',
    );
    return '$_temp0 → خصم $amount.';
  }

  @override
  String get posPlateTitle => 'لوحة المركبة';

  @override
  String get posPlateHint => 'أدخل رقم لوحة المركبة';

  @override
  String get posMsgNoDeliveryProvidersTitle => 'لا توجد شركات توصيل';

  @override
  String get posMsgNoDeliveryProvidersMessage =>
      'لم يتم إعداد أي شركة توصيل بعد. أضفها من بوابة التاجر.';

  @override
  String get posMsgCashPaymentCompleteTitle => 'اكتمل الدفع نقدًا';

  @override
  String get posMsgPaymentApprovedTitle => 'تمت الموافقة على الدفع';

  @override
  String get posMsgSplitPaymentRecordedTitle => 'تم تسجيل الدفعة المقسمة';

  @override
  String get posMsgPaymentCanceledTitle => 'تم إلغاء الدفع';

  @override
  String get posMsgPaymentFailedTitle => 'فشل الدفع';

  @override
  String get posMsgPaymentUpdateTitle => 'تحديث حالة الدفع';

  @override
  String posDiningTablePaidTitle(String table) {
    return 'تم دفع حساب $table';
  }

  @override
  String posDiningTicketPaidMessage(String ticket) {
    return 'تم دفع التذكرة رقم $ticket بنجاح. قم بإخلاء الطاولة عندما تصبح جاهزة للضيف التالي.';
  }

  @override
  String get posDiningPaidTotalLabel => 'الإجمالي المدفوع';

  @override
  String get posDiningFloorLabel => 'الصالة';

  @override
  String get posDiningClearTableButton => 'إخلاء الطاولة';

  @override
  String posDiningTableClearedTitle(String table) {
    return 'تم إخلاء $table';
  }

  @override
  String posDiningTableClearedMessage(String table) {
    return '$table متاحة الآن للضيف التالي.';
  }

  @override
  String get posDiscountSheetTitle => 'تطبيق خصم';

  @override
  String get posDiscountRedeemPointsOption => 'استبدال نقاط الولاء';

  @override
  String posDiscountRedeemPointsSubtitle(int count, String rule) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة متاحة',
      many: '$count نقطة متاحة',
      few: '$count نقاط متاحة',
      two: 'نقطتان متاحتان',
      one: 'نقطة واحدة متاحة',
    );
    return '$_temp0  ·  $rule';
  }

  @override
  String get posDiscountRedeemStampOption => 'استبدال مكافأة الطوابع';

  @override
  String posDiscountStampRewardSubtitle(int count, String amount, String rule) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count طابع',
      many: '$count طابعًا',
      few: '$count طوابع',
      two: 'طابعان',
      one: 'طابع واحد',
    );
    return '$_temp0 → خصم $amount  ·  $rule';
  }

  @override
  String get posDiscountManagerApprovalTag => 'موافقة المدير';

  @override
  String get posDiscountCustomAmountOption => 'مبلغ مخصص';

  @override
  String get posDiscountRemoveOption => 'إزالة الخصم';

  @override
  String get posDiscountClearedTitle => 'تم إلغاء الخصم';

  @override
  String get posDiscountClearedMessage => 'تمت إزالة خصم الطلب.';

  @override
  String posDiscountPercentOff(String percent) {
    return 'خصم $percent%';
  }

  @override
  String posDiscountAmountOff(String amount) {
    return 'خصم $amount';
  }

  @override
  String get posDiscountApproveSubtitle => 'اعتماد الخصم';

  @override
  String posDiscountApproveDescription(String name) {
    return 'ضع بصمة المدير لاعتماد \"$name\".';
  }

  @override
  String get posDiscountApprovalRequiredTitle => 'الموافقة مطلوبة';

  @override
  String posDiscountApprovalDeniedMessage(String name) {
    return 'لم تُمنح موافقة المدير على \"$name\".';
  }

  @override
  String get posDiscountAppliedTitle => 'تم تطبيق الخصم';

  @override
  String posDiscountAppliedMessage(String name) {
    return 'أصبح $name فعالًا الآن.';
  }

  @override
  String get posDiscountDefaultLabel => 'خصم الطلب';

  @override
  String get posSplitInProgressTitle => 'دفعة مقسمة قيد التنفيذ';

  @override
  String get posSplitInProgressMessage =>
      'أكمل جميع الدفعات المقسمة قبل تغيير عدد الضيوف.';

  @override
  String get posSplitClearedTitle => 'تم إلغاء تقسيم الفاتورة';

  @override
  String get posSplitClearedMessage => 'عاد الطلب إلى دفعة واحدة.';

  @override
  String get posSplitReadyTitle => 'تم تجهيز تقسيم الفاتورة';

  @override
  String posSplitReadyMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count حصة',
      many: '$count حصة',
      few: '$count حصص',
      two: 'حصتين',
      one: 'حصة واحدة',
    );
    return 'تم تقسيم الطلب إلى $_temp0 بقيمة $amount لكل حصة.';
  }

  @override
  String get posCharityConfirmRoundUpTitle => 'تأكيد التقريب للتبرع الخيري';

  @override
  String get posCharityConfirmRoundUpBody =>
      'اختر ما إذا كنت تريد إضافة التبرع الخيري الاختياري قبل فتح جهاز الدفع. ستعرض شاشة العميل الإجماليات نفسها.';

  @override
  String get posCharityOrderTotal => 'إجمالي الطلب';

  @override
  String get posCharityRoundUp => 'التقريب';

  @override
  String get posCharityNewTotal => 'الإجمالي الجديد';

  @override
  String get posCharityKeepOriginalTotal => 'لا، الإبقاء على الإجمالي الأصلي';

  @override
  String get posCharityRoundUpYes => 'نعم، التقريب للتبرع الخيري';

  @override
  String get posReconCardNotConfirmedTitle => 'لم يتم تأكيد خصم البطاقة';

  @override
  String get posReconStillWaitingBanner =>
      'عملية بطاقة غير محسومة — يلزم اتخاذ قرار. قد يكون العميل قد دُفع منه بالفعل؛ تحقق من جهاز الدفع قبل الاختيار.';

  @override
  String posReconCardNotConfirmedBody(String amount) {
    return 'لم يؤكد جهاز الدفع عملية خصم البطاقة بمبلغ $amount (مثل انتهاء مهلة NFC).\n\nإذا تم خصم المبلغ من العميل، فسجِّل العملية كقيد التسوية — وستتم مطابقتها مع ملف التسوية البنكية. وإلا فألغِ العملية وأعد محاولة الخصم.';
  }

  @override
  String get posReconCancelRetry => 'إلغاء — إعادة محاولة الخصم';

  @override
  String get posReconMarkPaidPending => 'تسجيل كمدفوع — قيد التسوية';

  @override
  String get posPaymentPreparingTitle => 'جارٍ تجهيز الدفع';

  @override
  String get posPaymentPreparingMessage => 'يرجى الانتظار حتى يفتح جهاز الدفع.';

  @override
  String get posPaymentSecureCardBadge => 'دفع آمن بالبطاقة';

  @override
  String get posPaymentRecordingCashTitle => 'جارٍ تسجيل الدفع النقدي';

  @override
  String get posPaymentRecordingCashMessage =>
      'يرجى الانتظار حتى اكتمال الدفع النقدي.';

  @override
  String get posPaymentCashCheckoutBadge => 'دفع نقدي';

  @override
  String get posPaymentTitle => 'الدفع';

  @override
  String get posPaymentNewOrder => 'طلب جديد';

  @override
  String posPaymentOrderRef(String reference) {
    return 'مرجع $reference';
  }

  @override
  String posPaymentTableChip(String table) {
    return 'الطاولة $table';
  }

  @override
  String get posPaymentOrderItems => 'أصناف الطلب';

  @override
  String get posPaymentSubtotal => 'المجموع الفرعي';

  @override
  String get posPaymentDiscountFallback => 'الخصم';

  @override
  String get posPaymentNetSubtotal => 'صافي المجموع الفرعي';

  @override
  String posPaymentCompRow(String reason) {
    return 'ضيافة · $reason';
  }

  @override
  String posPaymentTaxLine(String name, String rate) {
    return '$name ($rate%)';
  }

  @override
  String posPaymentGuestShareRow(int n) {
    return 'حصة الضيف $n';
  }

  @override
  String get posPaymentShareDue => 'الحصة المستحقة';

  @override
  String get posPaymentTotalDue => 'الإجمالي المستحق';

  @override
  String get posPaymentCustomerNumberLabel => 'رقم العميل (اختياري)';

  @override
  String get posPaymentCustomerNumberHint => 'أضف رقم العميل كمرجع';

  @override
  String get posPaymentVehiclePlateLabel => 'لوحة المركبة (اختياري)';

  @override
  String get posPaymentVehiclePlateHint =>
      'أضف لوحة المركبة لخدمة الطلب من السيارة';

  @override
  String get posPaymentDeliveryProviderLabel => 'مزوّد التوصيل';

  @override
  String get posPaymentDeliveryProviderHint => 'اختر مزوّد التوصيل';

  @override
  String get posPaymentRedeemLoyalty => 'استبدال نقاط الولاء';

  @override
  String get posPaymentTransfer => 'تحويل';

  @override
  String get posTransferDialogTitle => 'تحويل الطلب';

  @override
  String get posTransferSendSection => 'إرسال الطلب الحالي إلى';

  @override
  String get posTransferIncomingSection => 'التحويلات الواردة';

  @override
  String get posTransferNoDevices => 'لا توجد أجهزة أخرى في هذا الفرع.';

  @override
  String get posTransferNoIncoming => 'لا توجد تحويلات بانتظار الاستلام.';

  @override
  String get posTransferReceive => 'استلام';

  @override
  String get posTransferEmptyCartTitle => 'لا يوجد ما يُحوَّل';

  @override
  String get posTransferEmptyCartMessage => 'أضف أصنافًا إلى الطلب قبل تحويله.';

  @override
  String get posTransferSentTitle => 'تم تحويل الطلب';

  @override
  String get posTransferReceivedTitle => 'تم استلام الطلب';

  @override
  String get posTransferFailedTitle => 'فشل التحويل';

  @override
  String get posTransferReplaceCartTitle => 'استبدال الطلب الحالي؟';

  @override
  String get posTransferReplaceCartMessage =>
      'استلام هذا التحويل يمسح الطلب الموجود في السلة حاليًا.';

  @override
  String get posTransferBlockedMessage =>
      'لا يمكن تحويل الطلبات التي تحتوي على خصومات أو ضيافة أو أصناف مُهداة أو باقات أو دفعات مقسّمة أو طلبات توصيل. أزلها أو أكمل البيع على هذا الجهاز.';

  @override
  String get posTransferReceiveBlockedMessage =>
      'أكمل عملية الدفع الجارية قبل استلام طلب محوَّل.';

  @override
  String get posTransferConflictMessage =>
      'كانت هناك عملية دفع جارية أثناء تحويل الطلب، لذا بقيت السلة كما هي. تحقق من الجهاز الآخر قبل تحصيل المبلغ مرتين.';

  @override
  String get posTransferClaimedPendingMessage =>
      'تم استلام الطلب — سيتم تحميله فور إتمام عملية البيع الحالية.';

  @override
  String get posPaymentAddDiscount => 'إضافة خصم';

  @override
  String get posPaymentSplitBill => 'تقسيم الفاتورة';

  @override
  String get posPaymentComp => 'ضيافة';

  @override
  String get posPaymentCompApplied => 'ضيافة ✓';

  @override
  String get posPaymentTendered => 'المبلغ المستلم';

  @override
  String get posPaymentCardBalance => 'المتبقي على البطاقة';

  @override
  String get posPaymentChange => 'الباقي';

  @override
  String posPaymentQuickCash(int amount) {
    return '$amount OMR';
  }

  @override
  String posPaymentCollectingGuest(int n, int total, String amount) {
    return 'تحصيل حصة الضيف $n من $total: $amount.';
  }

  @override
  String get posPaymentCash => 'نقدًا';

  @override
  String get posPaymentCard => 'بطاقة';

  @override
  String get posPaymentSplitPayment => 'تقسيم\nالدفع';

  @override
  String get posNavHome => 'الرئيسية';

  @override
  String get posNavReport => 'التقارير';

  @override
  String get posNavHistory => 'السجل';

  @override
  String get posNavReportsComingTitle => 'التقارير قادمة قريبًا';

  @override
  String get posNavReportsComingBody =>
      'سنوفر التقارير التفصيلية بعد اكتمال ربط أرشيف الطلبات المحلي بقاعدة البيانات.';

  @override
  String get posNavAlreadyHomeBody =>
      'أنت بالفعل في الشاشة الرئيسية لنقطة البيع.';

  @override
  String get posNavBrandTagline => 'طلبات أفضل';

  @override
  String get posNavStaffFallback => 'موظف';

  @override
  String get posNavOrderHistory => 'سجل الطلبات';

  @override
  String get posNavHeldOrders => 'الطلبات المعلّقة';

  @override
  String get posNavLoyalty => 'الولاء';

  @override
  String get posNavReceiptPrintedTitle => 'تمت طباعة الإيصال';

  @override
  String get posNavReceiptPrintedBody =>
      'تم إرسال إيصال الطلب الحالي إلى الطابعة.';

  @override
  String get posMenuCloseShift => 'إغلاق الوردية';

  @override
  String get posMenuCloseShiftSub => 'عدّ درج النقد وتسوية النقدية';

  @override
  String get posMenuLogExpense => 'تسجيل مصروف';

  @override
  String get posMenuLogExpenseSub => 'تسجيل مصروف نثري';

  @override
  String get posMenuRequestRestock => 'طلب تزويد المخزون';

  @override
  String get posMenuRequestRestockSub => 'اطلب من الفرع تزويد المكوّنات';

  @override
  String get posMenuStockCount => 'جرد نهاية اليوم';

  @override
  String get posMenuStockCountSub => 'عدّ الرفوف وتسوية الفروقات';

  @override
  String get posMenuWasteProduct => 'تسجيل الهدر';

  @override
  String get posMenuWasteProductSub =>
      'سجّل المنتجات المطبوخة أو المخزّنة المهدورة';

  @override
  String get posMenuShiftSummary => 'ملخص الوردية (تقرير Z)';

  @override
  String get posMenuShiftSummarySub =>
      'إعادة طباعة آخر وردية مغلقة — للمدير فقط';

  @override
  String get posMenuSettings => 'الإعدادات';

  @override
  String get posMenuSettingsSub => 'عنوان الخادم والطباعة';

  @override
  String get posMenuLogoutSub => 'العودة إلى شاشة PIN للموظفين';

  @override
  String get posMenuNoShiftSummaryTitle => 'لا يوجد ملخص وردية بعد';

  @override
  String get posMenuNoShiftSummaryBody =>
      'أغلق وردية أولًا — يُحتفظ بملخصها لإعادة الطباعة.';

  @override
  String get posMenuShiftSummaryShort => 'ملخص الوردية';

  @override
  String get posMenuShiftSummaryAuthDesc =>
      'ضع بصمة المدير لإعادة طباعة ملخص آخر وردية.';

  @override
  String get posMenuApprovalRequiredTitle => 'الموافقة مطلوبة';

  @override
  String get posMenuApprovalNotGrantedBody =>
      'لم تُمنح موافقة المدير لملخص الوردية.';

  @override
  String get posMenuShiftSummaryPrintedTitle => 'تمت طباعة ملخص الوردية';

  @override
  String get posMenuShiftSummaryPrintedBody =>
      'تم إرسال ملخص آخر وردية إلى الطابعة.';

  @override
  String get posMenuLogoutConfirmTitle => 'تسجيل الخروج؟';

  @override
  String get posMenuLogoutConfirmBody =>
      'ستعود إلى شاشة PIN للموظفين. يبقى الجهاز جاهزًا كما هو.';

  @override
  String get posOrderPanelTitle => 'الطلب الحالي';

  @override
  String get posOrderPanelNewOrder => 'جديد';

  @override
  String posOrderPanelRef(String reference) {
    return 'مرجع $reference';
  }

  @override
  String posOrderPanelTableChip(String table) {
    return 'طاولة $table';
  }

  @override
  String get posOrderPanelFloorPlan => 'مخطط الصالة';

  @override
  String get posOrderPanelClear => 'مسح';

  @override
  String get posOrderPanelSubtotal => 'المجموع الفرعي';

  @override
  String get posOrderPanelDiscount => 'الخصم';

  @override
  String get posOrderPanelNetSubtotal => 'صافي المجموع الفرعي';

  @override
  String posOrderPanelComp(String reason) {
    return 'ضيافة · $reason';
  }

  @override
  String posOrderPanelPerShare(int count) {
    return 'لكل حصة ($count)';
  }

  @override
  String get posOrderPanelTotal => 'الإجمالي';

  @override
  String get posOrderPanelBackToFloor => 'العودة إلى الصالة';

  @override
  String get posOrderPanelHold => 'تعليق';

  @override
  String get posOrderPanelClearTable => 'إخلاء الطاولة';

  @override
  String get posOrderPanelVoid => 'إبطال';

  @override
  String get posCatalogCategories => 'الفئات';

  @override
  String get posCatalogProducts => 'المنتجات';

  @override
  String get posCatalogFavourites => 'المفضلة';

  @override
  String get posCatalogFavouritesComingTitle => 'المفضلة قادمة قريبًا';

  @override
  String get posCatalogFavouritesComingBody =>
      'سنربط المنتجات المفضلة بقاعدة البيانات المحلية في تحديث قادم.';

  @override
  String get posCatalogSearchHint => 'بحث';

  @override
  String get posCatalogViewList => 'قائمة';

  @override
  String get posCatalogViewGrid => 'شبكة';

  @override
  String get posClockAm => 'ص';

  @override
  String get posClockPm => 'م';

  @override
  String get posClockMonthJan => 'يناير';

  @override
  String get posClockMonthFeb => 'فبراير';

  @override
  String get posClockMonthMar => 'مارس';

  @override
  String get posClockMonthApr => 'أبريل';

  @override
  String get posClockMonthMay => 'مايو';

  @override
  String get posClockMonthJun => 'يونيو';

  @override
  String get posClockMonthJul => 'يوليو';

  @override
  String get posClockMonthAug => 'أغسطس';

  @override
  String get posClockMonthSep => 'سبتمبر';

  @override
  String get posClockMonthOct => 'أكتوبر';

  @override
  String get posClockMonthNov => 'نوفمبر';

  @override
  String get posClockMonthDec => 'ديسمبر';

  @override
  String posClockDate(String month, int day, int year) {
    return '$day $month $year';
  }

  @override
  String get posCartEmptyTitle => 'اضغط على أي منتج لبدء الطلب';

  @override
  String get posCartEmptySubtitle =>
      'ستظهر سلة الطلب والإجراءات والإجماليات هنا.';

  @override
  String get posCartAddOn => 'إضافات';

  @override
  String posCartQtyTimesName(int qty, String name) {
    return '$qty× $name';
  }

  @override
  String posCartQtyTimesPrice(int qty, String price) {
    return '$qty × $price';
  }

  @override
  String posCustomizeTitle(String name) {
    return 'تخصيص $name';
  }

  @override
  String get posCustomizeSubtitle =>
      'اختر الإضافات واترك ملاحظات لهذا البند من الطلب.';

  @override
  String get posCustomizeNotesLabel => 'ملاحظات';

  @override
  String get posCustomizeNotesHint => 'أضف ملاحظات التحضير للمطبخ أو الكاشير';

  @override
  String posCustomizeApply(String amount) {
    return 'تطبيق $amount';
  }

  @override
  String get posProductsEmptySearchTitle => 'لا توجد منتجات مطابقة لبحثك.';

  @override
  String get posProductsEmptyCategoryTitle => 'لا توجد منتجات متاحة هنا بعد.';

  @override
  String get posProductsEmptySearchSubtitle =>
      'جرّب اسم منتج آخر أو امسح البحث الحالي.';

  @override
  String get posProductsEmptyCategorySubtitle =>
      'اختر فئة أخرى أو أضف منتجات إلى هذه الفئة لاحقًا.';

  @override
  String get posProductsClearSearch => 'مسح البحث';

  @override
  String get posProductSoldOutBadge => 'نفدت الكمية';

  @override
  String get posProductLowStockBadge => 'مخزون منخفض';

  @override
  String get posProductOutsideHoursBadge => 'غير متاح الآن';

  @override
  String get posProductAdd => 'إضافة';

  @override
  String get posPayBtnProcessing => 'جارٍ معالجة الدفع';

  @override
  String get posPayBtnProcessToPay => 'المتابعة إلى الدفع';

  @override
  String get posPayBtnCompletingOrder => 'جارٍ إتمام الطلب';

  @override
  String posPayBtnPayAmount(String amount) {
    return 'ادفع $amount';
  }

  @override
  String posDiningTicketNumber(String number) {
    return 'تذكرة #$number';
  }

  @override
  String posDiningRefNumber(String reference) {
    return 'مرجع $reference';
  }

  @override
  String posDiningSeats(int count) {
    return 'المقاعد: $count';
  }

  @override
  String get posDiningStatusAvailable => 'متاحة';

  @override
  String get posDiningStatusOccupied => 'مشغولة';

  @override
  String get posDiningStatusPaidClear => 'مدفوعة / إخلاء';

  @override
  String get posStorageHeldEmptyTitle => 'لا توجد طلبات معلّقة بعد';

  @override
  String get posStorageHeldEmptyMessage =>
      'أي طلب تقوم بتعليقه سيظهر هنا ليتمكن الموظفون من متابعته لاحقًا.';

  @override
  String get posStorageHistoryEmptyTitle => 'لا توجد طلبات مكتملة بعد';

  @override
  String get posStorageHistoryEmptyMessage =>
      'سيتم أرشفة المدفوعات المكتملة هنا ليتمكن الموظفون من مراجعتها أو إعادة طباعة الإيصالات.';

  @override
  String get posFingerprintBannerTitle => 'موافقة المدير على الإلغاء';

  @override
  String get posFingerprintBannerMessage =>
      'سجّل مرة واحدة، ثم استخدم الموافقة بالبصمة قبل فتح إلغاء الطلبات المكتملة.';

  @override
  String get posFingerprintRegisterManager => 'تسجيل المدير';

  @override
  String get posFingerprintWaiting => 'في انتظار البصمة';

  @override
  String posStorageHeldRef(String ref) {
    return 'مرجع $ref';
  }

  @override
  String posStorageItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صنف',
      many: '$count صنفًا',
      few: '$count أصناف',
      two: 'صنفان',
      one: 'صنف واحد',
    );
    return '$_temp0';
  }

  @override
  String posStorageSplitBadge(int n) {
    return 'تقسيم $n';
  }

  @override
  String posStorageItemQtyName(int qty, String name) {
    return '$qty× $name';
  }

  @override
  String get posStorageContinueOrder => 'متابعة الطلب';

  @override
  String get posStorageDiscard => 'تجاهل';

  @override
  String posStorageOrderNumber(int n) {
    return 'الطلب #$n';
  }

  @override
  String posStorageSplitsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count تقسيم',
      many: '$count تقسيمًا',
      few: '$count تقسيمات',
      two: 'تقسيمان',
      one: 'تقسيم واحد',
    );
    return '$_temp0';
  }

  @override
  String posStorageCanceledAmount(String amount) {
    return 'ملغي $amount';
  }

  @override
  String get posStorageKitchen => 'المطبخ';

  @override
  String get posStorageCanceled => 'ملغي';

  @override
  String posCancelPageTitle(int n) {
    return 'إلغاء الطلب #$n';
  }

  @override
  String get posCancelPageSubtitle =>
      'تمت موافقة المدير. ألغِ الطلب كاملًا أو حدد الأصناف المكتملة لإلغائها.';

  @override
  String get posCancelPageReasonRequired => 'اختر سبب الإلغاء أولًا.';

  @override
  String get posCancelPageServerFullOnly =>
      'الطلبات المتزامنة تُلغى بالكامل فقط.';

  @override
  String get posDiningTableActionsTooltip => 'إجراءات الطاولة';

  @override
  String get posManagerPinTitle => 'الرمز السري للمدير';

  @override
  String get posManagerPinSubtitle =>
      'أدخل الرمز السري للمدير للموافقة على هذا الإجراء.';

  @override
  String get posManagerPinInvalid => 'لم يُقبل الرمز. تحقق منه وحاول مجددًا.';

  @override
  String get posManagerPinOffline =>
      'التحقق من الرمز يتطلب اتصالًا بالخادم — استخدم البصمة بدلًا منه.';

  @override
  String get posManagerPinVerify => 'تحقق';

  @override
  String get posCustomerDetailsTooltip => 'بيانات الزبون';

  @override
  String get posCustomerDetailsWallet => 'المحفظة';

  @override
  String get posCustomerDetailsPlates => 'لوحات المركبات';

  @override
  String get posCustomerDetailsNoPlates => 'لا توجد لوحات مسجلة بعد.';

  @override
  String get posCustomerDetailsLoyalty => 'الولاء';

  @override
  String get posCustomerDetailsRedeem => 'استبدال';

  @override
  String posCustomerDetailsStampProgress(int got, int needed) {
    return '$got/$needed طوابع';
  }

  @override
  String get posPlateSearchTooltip => 'البحث عن الزبائن باللوحة';

  @override
  String get posPlateSearchTitle => 'البحث باللوحة';

  @override
  String posPlateSearchNoMatches(String plate) {
    return 'لا يوجد زبائن مرتبطون بـ $plate.';
  }

  @override
  String posPlateSearchPickCustomer(String plate) {
    return 'الزبائن المرتبطون بـ $plate';
  }

  @override
  String get posEarnPickerTitle => 'برنامج الولاء';

  @override
  String posEarnPickerSubtitle(String name) {
    return 'ضمن أي برنامج تُحتسب مكافآت هذا الطلب لـ $name؟';
  }

  @override
  String get posEarnPickerConfirm => 'تأكيد';

  @override
  String get posDiscountDlgCustomSection => 'مخصص';

  @override
  String get posDiscountDlgCustomPercentHint => 'نسبة مئوية (مثل 7.5)';

  @override
  String get posDiscountDlgCustomAmountHint => 'مبلغ (ر.ع)';

  @override
  String get posDiscountDlgReasonHint => 'السبب (مطلوب للقيمة المخصصة)';

  @override
  String get posDiscountDlgReasonRequired => 'أدخل سبب الخصم المخصص.';

  @override
  String get posPaymentBankPos => 'جهاز البنك';

  @override
  String get displayMethodBankPos => 'جهاز البنك';

  @override
  String get ctrlMsgBankPosRecording => 'جارٍ تسجيل الدفع عبر جهاز البنك…';

  @override
  String get ctrlMsgBankPosRecorded => 'تم تسجيل الدفع عبر جهاز البنك.';

  @override
  String get ctrlMsgBankPosCompleted =>
      'تم استلام الدفع على جهاز البنك. شكرًا لك!';

  @override
  String get posCartGift => 'إهداء';

  @override
  String get posCartGifted => 'مُهدى';

  @override
  String get posGiftItemApprovalMessage => 'إهداء صنف يتطلب موافقة المدير.';

  @override
  String get posGiftItemBlockedTitle => 'الطلب مُضاف بالفعل';

  @override
  String get posGiftItemBlockedMessage =>
      'الطلب بأكمله مُضاف كضيافة — لا يوجد ما يُهدى.';

  @override
  String get posGiftItemGiftedTitle => 'تم إهداء الصنف';

  @override
  String get posGiftItemRemovedTitle => 'أُلغي الإهداء';

  @override
  String get reportsTitle => 'تقارير الفرع';

  @override
  String get reportsLoadFailed =>
      'تعذّر تحميل التقرير. تحقق من الاتصال وحاول مجددًا.';

  @override
  String get reportsRetry => 'إعادة المحاولة';

  @override
  String get reportsRangeToday => 'اليوم';

  @override
  String get reportsRange7d => '7 أيام';

  @override
  String get reportsRange30d => '30 يومًا';

  @override
  String get reportsRangeCustom => 'مخصص';

  @override
  String get reportsNoData => 'لا توجد بيانات لهذه الفترة.';

  @override
  String get reportsKpiGross => 'إجمالي المبيعات';

  @override
  String get reportsKpiOrders => 'الطلبات';

  @override
  String get reportsKpiAvgOrder => 'متوسط الطلب';

  @override
  String get reportsKpiTax => 'الضريبة';

  @override
  String get reportsKpiDiscounts => 'الخصومات';

  @override
  String get reportsKpiCompsGifts => 'الضيافة والإهداءات';

  @override
  String get reportsKpiCustomers => 'الزبائن';

  @override
  String get reportsKpiPointsRedeemed => 'نقاط مستبدلة';

  @override
  String get reportsSalesByDay => 'المبيعات حسب اليوم';

  @override
  String get reportsSalesByHour => 'المبيعات حسب الساعة';

  @override
  String get reportsTenderMix => 'طرق الدفع';

  @override
  String get reportsOrderTypes => 'أنواع الطلبات';

  @override
  String get reportsTopProducts => 'أكثر المنتجات مبيعًا';

  @override
  String get reportsStockConsumption => 'استهلاك المخزون';

  @override
  String get reportsLoyalty => 'الولاء';

  @override
  String get reportsPointsEarned => 'نقاط مكتسبة';

  @override
  String get reportsPointsRedeemed => 'نقاط مستبدلة';

  @override
  String get reportsStampsEarned => 'طوابع مكتسبة';

  @override
  String get reportsStampsRedeemed => 'طوابع مستبدلة';

  @override
  String get reportsTopCustomers => 'أفضل الزبائن';

  @override
  String get reportsDiscounts => 'الخصومات';

  @override
  String get reportsMethodLoyalty => 'الولاء';

  @override
  String reportsQtyTimes(String qty) {
    return '×$qty';
  }

  @override
  String reportsOrdersCount(int count) {
    return '$count طلبات';
  }

  @override
  String reportsTimesUsed(int count) {
    return 'استُخدم $count مرة';
  }

  @override
  String get reportsNotAllowedTitle => 'التقارير مقفلة';

  @override
  String get reportsNotAllowedBody =>
      'دورك لا يسمح بعرض تقارير الفرع على هذا الجهاز.';

  @override
  String get reportsChooserDashboardSub =>
      'المبيعات والمنتجات والزبائن والمخزون لهذا الفرع.';

  @override
  String get reportsChooserXReportSub =>
      'طباعة مبيعات الوردية الحالية حتى الآن.';

  @override
  String get posMenuCloseShiftAndLogout => 'إغلاق الوردية وتسجيل الخروج';

  @override
  String get posMenuCloseShiftAndLogoutSub =>
      'عُدّ الدرج، اطبع ملخص الوردية، ثم سجّل الخروج.';

  @override
  String get posMenuLogoutOnly => 'تبديل الموظف';

  @override
  String get posMenuLogoutOnlySub =>
      'يبقى الدرج مفتوحًا. يجب على الموظف التالي تسجيل الدخول بصفة مالكه أو تسويته قبل البيع.';

  @override
  String get posCancelPageOrderItems => 'أصناف الطلب';

  @override
  String posCancelPageCancellableCount(int count) {
    return '$count قابلة للإلغاء';
  }

  @override
  String get posCancelPageSaving => 'جارٍ الحفظ...';

  @override
  String posCancelPageCancelSelected(int count) {
    return 'إلغاء المحدد ($count)';
  }

  @override
  String get posCancelPageCancelFullOrder => 'إلغاء الطلب بالكامل';

  @override
  String get posCancelPageOrderSummary => 'ملخص الطلب';

  @override
  String get posCancelPagePaidTotal => 'الإجمالي المدفوع';

  @override
  String get posCancelPageCanceledMetric => 'الملغي';

  @override
  String get posCancelPagePaymentMetric => 'الدفع';

  @override
  String get posCancelPageCancellationLog => 'سجل الإلغاءات';

  @override
  String get posCancelPageNoCancellations => 'لا توجد إلغاءات مسجلة.';

  @override
  String get posCancelPageItemFallback => 'صنف';

  @override
  String posCancelPageItemQtyName(int qty, String name) {
    return '$qty × $name';
  }

  @override
  String get posDeliveryPickerTitle => 'اختر مزود التوصيل';

  @override
  String get posDeliveryPickerSubtitle =>
      'يتم تحديث أسعار المنتجات حسب المزود المحدد.';

  @override
  String get posKeyboardSpace => 'مسافة';

  @override
  String get posKeyboardClear => 'مسح الكل';

  @override
  String get posKeyboardBackspace => 'حذف';

  @override
  String get posCustomerSearchFailed => 'فشل البحث. تحقق من الاتصال.';

  @override
  String get posCustomerSearchHint => 'الاسم أو الهاتف أو رقم اللوحة';

  @override
  String get posCustomerSearchButton => 'بحث';

  @override
  String get posCustomerSearchNoResults => 'لم يتم العثور على عملاء.';

  @override
  String posCustomerSearchPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نقطة',
      many: '$count نقطة',
      few: '$count نقاط',
      two: 'نقطتان',
      one: 'نقطة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get posRedeemTitle => 'استبدال النقاط';

  @override
  String posRedeemPerBlock(int points, String value) {
    return '$points نقطة = $value لكل حزمة';
  }

  @override
  String posRedeemSummary(int points, String value) {
    return '$points نقطة ← خصم $value';
  }

  @override
  String get posRedeemConfirm => 'استبدال';

  @override
  String get posDiscountDlgTitle => 'إضافة خصم';

  @override
  String get posDiscountDlgPercentageSection => 'خصومات بالنسبة المئوية';

  @override
  String get posDiscountDlgFixedSection => 'خصومات ثابتة';

  @override
  String get posDiscountDlgClear => 'إزالة الخصم';

  @override
  String posDiscountDlgApply(String label) {
    return 'تطبيق $label';
  }

  @override
  String get posSplitDlgTitle => 'تقسيم الفاتورة';

  @override
  String get posSplitDlgSingleBill => 'فاتورة واحدة';

  @override
  String posSplitDlgGuests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ضيف',
      many: '$count ضيفًا',
      few: '$count ضيوف',
      two: 'ضيفان',
      one: 'ضيف واحد',
    );
    return '$_temp0';
  }

  @override
  String get posSplitDlgEachGuestPays => 'يدفع كل ضيف';

  @override
  String get posSplitDlgSinglePaymentTotal => 'إجمالي الدفعة الواحدة';

  @override
  String get posSplitDlgApplySplit => 'تطبيق التقسيم';

  @override
  String get posSplitDlgUseSingleBill => 'استخدام فاتورة واحدة';

  @override
  String get posSplitDlgCustomAmounts => 'تخصيص المبالغ';

  @override
  String posSplitDlgGuestN(int n) {
    return 'الضيف $n';
  }

  @override
  String posSplitDlgLastGuestRemainder(int n) {
    return 'الضيف $n يدفع المتبقي';
  }

  @override
  String get posSplitDlgAmountsInvalid =>
      'يجب أن يدفع كل ضيف مبلغًا أكبر من صفر.';

  @override
  String get posSplitPlanRejectedMessage =>
      'المبالغ المخصصة لم تعد تطابق إجمالي الطلب — لم يتم تطبيق التقسيم.';

  @override
  String posSplitCustomReadyMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ضيف',
      many: '$count ضيفًا',
      few: '$count ضيوف',
      two: 'ضيفين',
    );
    return 'تم تقسيم الطلب على $_temp0 بمبالغ مخصصة — الضيف 1 يدفع $amount.';
  }

  @override
  String get displayMethodCardShort => 'البطاقة';

  @override
  String get displayMethodGift => 'هدية';

  @override
  String get ctrlMsgGiftRecorded =>
      'تم تسجيل الطلب كهدية — لم يُحصَّل أي مبلغ.';

  @override
  String get ctrlMsgGiftCompleted => 'هذا الطلب هدية منا. شكرًا لكم!';

  @override
  String get posPaymentGift => 'هدية';

  @override
  String get posPayGiftConfirmTitle => 'إهداء هذا الطلب؟';

  @override
  String posPayGiftConfirmMessage(String amount) {
    return 'سيُقدَّم الطلب بالكامل ($amount OMR) كهدية — لن يُحصَّل أي مبلغ من العميل، وسيُخصم المخزون كالمعتاد.';
  }

  @override
  String get posPayGiftRegisterManagerMessage =>
      'سجِّل بصمة المدير مرة واحدة قبل إهداء أي طلب.';

  @override
  String get posPayGiftManagerApprovalMessage =>
      'ضع بصمة المدير لإهداء هذا الطلب.';

  @override
  String get posPayGiftDeniedMessage => 'لم تُمنح موافقة المدير على الهدية.';

  @override
  String get posPrintFailedReceiptTitle => 'لم يُطبع الإيصال';

  @override
  String get posPrintFailedReceiptBody =>
      'تحقق من الطابعة (الورق / الغطاء). الطلب محفوظ — أعد طباعته من السجل.';

  @override
  String get posPrintFailedKitchenTitle => 'لم تُطبع تذكرة المطبخ';

  @override
  String get posPrintFailedKitchenBody =>
      'الطلب محفوظ. أعد طباعة نسخة المطبخ من السجل.';

  @override
  String get posPrintFailedShiftTitle => 'لم يُطبع ملخص الوردية';

  @override
  String get posPrintFailedShiftBody =>
      'تحقق من الطابعة ثم أعد الطباعة من قائمة الموظف.';

  @override
  String get shiftClosePrintFailed =>
      'لم يُطبع الملخص — تحقق من الطابعة وحاول مرة أخرى.';

  @override
  String get posMidShiftReportTitle => 'الوردية الحالية';

  @override
  String get posMidShiftThisDeviceOnly =>
      'هذا الجهاز فقط — تقدير مباشر، وليس تسوية الإغلاق.';

  @override
  String get posMidShiftNoOpenShiftTitle => 'لا توجد وردية مفتوحة';

  @override
  String get posMidShiftNoOpenShiftBody =>
      'افتح وردية أولاً — يغطي التقرير جلسة الدرج الحالية.';

  @override
  String get posMidShiftAuthSubtitle => 'تقرير الوردية';

  @override
  String get posMidShiftAuthDesc =>
      'ضع بصمة المدير لعرض تقرير الوردية الحالية.';

  @override
  String get posMidShiftAuthDeniedBody =>
      'لم تُمنح موافقة المدير على تقرير الوردية.';

  @override
  String get posMidShiftOrders => 'الطلبات';

  @override
  String get posMidShiftGross => 'إجمالي المبيعات';

  @override
  String get posMidShiftDiscounts => 'الخصومات';

  @override
  String get posMidShiftComps => 'الضيافات';

  @override
  String get posMidShiftTax => 'الضريبة';

  @override
  String get posMidShiftTotal => 'الإجمالي';

  @override
  String get posMidShiftRoundUp => 'تبرعات التقريب';

  @override
  String get posMidShiftVoids => 'الإلغاءات';

  @override
  String get posMidShiftOpeningFloat => 'الرصيد الافتتاحي';

  @override
  String get posMidShiftCashTaken => 'النقد المحصّل (هذا الجهاز)';

  @override
  String posDiningActionsTitle(String table) {
    return 'الطاولة $table';
  }

  @override
  String get posDiningActionOpen => 'فتح الطاولة';

  @override
  String get posDiningActionMove => 'النقل إلى طاولة أخرى';

  @override
  String get posDiningActionMoveHint =>
      'انتقل الضيوف إلى مقاعد أخرى — ينتقل الطلب معهم.';

  @override
  String get posDiningActionMerge => 'ضم طاولة شاغرة';

  @override
  String get posDiningActionMergeHint =>
      'اضمم طاولة شاغرة مجاورة إلى هذه المجموعة — فاتورة واحدة، وتُفرَّغان معًا.';

  @override
  String posDiningJoinedWith(String label) {
    return 'مضمومة ← $label';
  }

  @override
  String get posDiningPickFreeTable => 'النقل إلى أي طاولة شاغرة؟';

  @override
  String get posDiningPickMergeTarget => 'ضم أي طاولة شاغرة؟';

  @override
  String get posDiningMergeConfirmTitle => 'ضم الطاولتين؟';

  @override
  String posDiningMergeConfirmBody(
    String source,
    String sourceTotal,
    String target,
    String targetTotal,
  ) {
    return 'ستنضم $target إلى مجموعة $source — يتشاركان فاتورة واحدة على $source ($sourceTotal) وتُفرَّغان معًا عند الدفع.';
  }

  @override
  String get posDiningNoFreeTables => 'لا توجد طاولات شاغرة حاليًا.';

  @override
  String get posDiningNoMergeTargets => 'لا توجد طاولات شاغرة للضم.';

  @override
  String get posDiningActionFailed =>
      'تغيّرت حالة الطاولة — حدّث مخطط الطاولات وحاول مرة أخرى.';

  @override
  String get posDiningTableMovedTitle => 'تم نقل الطاولة';

  @override
  String get posDiningTablesMergedTitle => 'تم ضم الطاولتين';

  @override
  String ctrlMsgTableTransferred(String from, String to) {
    return 'تم نقل $from إلى $to — انتقل الطلب مع الضيوف.';
  }

  @override
  String ctrlMsgTablesMerged(String source, String target) {
    return 'تم ضم $source مع $target.';
  }

  @override
  String get posNavOffers => 'العروض';

  @override
  String get posOffersNone => 'لا توجد عروض فعّالة في هذا الفرع حاليًا.';

  @override
  String posOffersAppliedTimes(int n) {
    return 'مطبّق ×$n';
  }

  @override
  String get posOfferTypeBogo => 'اشترِ واحصل';

  @override
  String get posOfferTypeBundle => 'باقة';

  @override
  String get posOfferTypeMultiBuy => 'شراء متعدد';

  @override
  String get posOfferTypeCheapestFree => 'الأرخص مجانًا';

  @override
  String get posOfferTypeSpendGet => 'أنفق واحصل';

  @override
  String posOffersBundleNeed(int n) {
    return 'اختر $n';
  }

  @override
  String get posOffersBundlePrice => 'سعر الباقة:';

  @override
  String get posOffersBundleAdd => 'إضافة الباقة';

  @override
  String posCustomizeMinHint(int n) {
    return 'اختر $n على الأقل';
  }

  @override
  String get posNavKitchen => 'المطبخ';

  @override
  String get kitchenNotAllowedTitle => 'المطبخ مقفل';

  @override
  String get kitchenNotAllowedBody =>
      'منصبك الوظيفي لا يسمح بفتح شاشة إنتاج المطبخ على هذا الجهاز.';

  @override
  String get kitchenTitle => 'إنتاج المطبخ';

  @override
  String get kitchenRefresh => 'تحديث';

  @override
  String get kitchenOffline =>
      'المطبخ يحتاج اتصالًا بالإنترنت — يتحقق الخادم من الإنتاج مباشرةً.';

  @override
  String get kitchenLoadFailed =>
      'تعذّر تحميل المطبخ. تحقق من الاتصال وحاول مجددًا.';

  @override
  String get kitchenRetry => 'إعادة المحاولة';

  @override
  String get kitchenNoProducts =>
      'لا توجد منتجات مطبوخة معدّة لهذا الفرع.\nحدّد منتجًا كمطبوخ في بوابة التاجر أولًا.';

  @override
  String get kitchenOtherCategory => 'أخرى';

  @override
  String kitchenShelfCount(String count) {
    return 'على الرف: $count';
  }

  @override
  String kitchenCanMake(int count) {
    return 'يمكن تحضير حتى $count';
  }

  @override
  String get kitchenNoRecipe => 'بلا وصفة — الكمية غير مقيّدة';

  @override
  String get kitchenActiveTitle => 'قيد التحضير';

  @override
  String get kitchenNoActive => 'لا توجد دفعات قيد التحضير.';

  @override
  String kitchenStartedBy(String name) {
    return 'بدأها $name';
  }

  @override
  String get kitchenFinish => 'إنهاء';

  @override
  String get kitchenCancelBatch => 'إلغاء الدفعة';

  @override
  String kitchenStartBatchTitle(String name) {
    return 'تحضير $name';
  }

  @override
  String get kitchenQuantity => 'الكمية (قطع)';

  @override
  String get kitchenRecipeLocked => 'الوصفة (مثبتة × الكمية / المتاح)';

  @override
  String get kitchenInsufficient =>
      'المخزون المسجل لا يكفي لهذه الكمية. يمكنك البدء، وسيصبح رصيد المكونات أقل من الصفر.';

  @override
  String get kitchenExtrasTitle => 'مكونات إضافية (مصرّح بها)';

  @override
  String get kitchenAddExtra => 'إضافة مكوّن';

  @override
  String kitchenExtraQtyHint(String unit) {
    return 'الكمية $unit';
  }

  @override
  String get kitchenStart => 'بدء الدفعة';

  @override
  String get kitchenDialogCancel => 'إلغاء';

  @override
  String get kitchenBatchStarted => 'بدأت الدفعة — تم خصم المكونات.';

  @override
  String kitchenBatchStartedShort(String names) {
    return 'بدأت الدفعة. المخزون المسجل لم يكفِ من: $names. أصبح رصيدها أقل من الصفر.';
  }

  @override
  String get kitchenBatchFinished => 'اكتملت الدفعة — أُضيفت القطع إلى الرف.';

  @override
  String get kitchenBatchCancelled => 'أُلغيت الدفعة — أُعيدت المكونات.';

  @override
  String get kitchenPinTitle => 'موافقة المدير';

  @override
  String get kitchenPinHint => 'رمز المدير';

  @override
  String get kitchenPinInvalid => 'رمز المدير غير صحيح.';

  @override
  String kitchenFinishTitle(String name) {
    return 'إنهاء $name';
  }

  @override
  String get kitchenExpiryLabel => 'صالح حتى';

  @override
  String get kitchenExpiryToday => 'اليوم';

  @override
  String get kitchenExpiryTomorrow => 'غدًا';

  @override
  String kitchenExpiryInDays(int n) {
    return 'خلال $n أيام';
  }

  @override
  String get kitchenExpiryNever => 'بلا انتهاء';

  @override
  String get kitchenExpiryPickDate => 'اختر تاريخًا';

  @override
  String get kitchenExpiryNeverHint => 'لن تُعلَّم هذه الدفعة في نهاية اليوم.';

  @override
  String kitchenExpiryResolvedHint(String date) {
    return 'صالحة حتى نهاية $date.';
  }

  @override
  String kitchenExpiresOn(String date) {
    return 'صالح حتى $date';
  }

  @override
  String get dispositionTitle => 'أصناف منتهية — نهاية اليوم';

  @override
  String get dispositionSubtitle =>
      'هذه القطع المطبوخة تجاوزت تاريخ صلاحيتها. حدّد مصير كل منها قبل إغلاق الوردية: هدر، أو إهداء (بموافقة المدير وذكر المستلم)، أو إبقاؤها للبيع (بموافقة المدير).';

  @override
  String dispositionExpiredCount(String expired, String shelf) {
    return '$expired منتهية من أصل $shelf على الرف';
  }

  @override
  String get dispositionWaste => 'هدر';

  @override
  String get dispositionGiveAway => 'إهداء';

  @override
  String get dispositionCarryOver => 'إبقاء للبيع';

  @override
  String dispositionRemaining(String qty) {
    return 'متبقٍ $qty بلا تحديد';
  }

  @override
  String get dispositionGiftCommentHint =>
      'من استلمها؟ (إلزامي — اسم موظف أو زبون)';

  @override
  String get dispositionSkip => 'تخطٍّ الآن';

  @override
  String get dispositionSubmit => 'تطبيق ومتابعة';

  @override
  String get dispositionDone => 'تم تسجيل التصرف.';

  @override
  String get kitchenGateTitle => 'رمز موظف المطبخ';

  @override
  String get kitchenGateHint => 'أدخل رمز أحد موظفي المطبخ';

  @override
  String get kitchenGateConfirm => 'فتح المطبخ';

  @override
  String get kitchenGateInvalid =>
      'هذا الرمز لا يخص موظفًا مسموحًا له بالمطبخ.';

  @override
  String kitchenOperatingAs(String name) {
    return 'باسم $name';
  }

  @override
  String get posNavMessages => 'الرسائل';

  @override
  String get posMessagesNone => 'لا توجد إعلانات لك حتى الآن.';

  @override
  String get posMessagesUntitled => 'إعلان';

  @override
  String get posMessagesPopupTitle => 'رسالة جديدة';

  @override
  String get posPaymentDeliveryProceed => 'متابعة';

  @override
  String get posDeliveryRecordedTitle => 'تم تسجيل التوصيل';

  @override
  String get posDeliveryProceedTitle => 'إتمام طلب التوصيل';

  @override
  String get posDeliveryProceedSubtitle =>
      'لا يُدفع شيء عند الكاشير — تسدد شركة التوصيل لاحقًا بعد خصم عمولتها.';

  @override
  String get posDeliveryProceedReference => 'رقم طلب الشركة';

  @override
  String get posDeliveryProceedReferenceHint => 'إلزامي — مثل TLB-88421';

  @override
  String get posDeliveryProceedCustomer => 'رقم الزبون';

  @override
  String get posDeliveryProceedDriver => 'رقم السائق';

  @override
  String get posDeliveryProceedOptionalHint => 'اختياري';

  @override
  String get posDeliveryProceedConfirm => 'إتمام الطلب';

  @override
  String get ctrlMsgDeliveryRecorded =>
      'تم تسجيل طلب التوصيل — بانتظار تحقق الشركة.';

  @override
  String get ctrlMsgDeliveryCompleted =>
      'اكتمل طلب التوصيل. بانتظار تسوية الشركة.';

  @override
  String get displayStatusPendingVerification => 'بانتظار التحقق';

  @override
  String get displayMethodDelivery => 'توصيل';

  @override
  String get posOffersNotForDelivery =>
      'لا تنطبق العروض على طلبات شركات التوصيل — سعر الشركة المعلن نهائي.';

  @override
  String get tableSharedAdjustmentsUnavailable =>
      'غير متاح للفواتير المشتركة بعد';

  @override
  String get tableSendToKitchen => 'إرسال إلى المطبخ';

  @override
  String tableSentAt(String time) {
    return 'أُرسل $time';
  }

  @override
  String get tableCancelSentTitle => 'إلغاء أصناف مرسلة';

  @override
  String get tableCancelSentApproval =>
      'تلزم موافقة المدير لإلغاء أصناف أُرسلت إلى المطبخ.';

  @override
  String get tableWasPrepared => 'هل تم تحضيره؟';

  @override
  String get tablePreparedYes => 'نعم — تسجيل هدر';

  @override
  String get tablePreparedNo => 'لا — إلغاء فقط';

  @override
  String get tableCancelSentReason => 'السبب (اختياري)';

  @override
  String get tableLocalOnly => 'محلي فقط';

  @override
  String get tableActionFailed =>
      'تعذر حفظ إجراء الطاولة. يرجى المحاولة مجددًا.';

  @override
  String get tableCustomerBillTitle => 'فاتورة العميل';

  @override
  String get tableAddItems => 'إضافة أصناف';

  @override
  String get tableSeparateLocal => 'فتح طاولة محلية منفصلة';

  @override
  String get tableSeparateLocalWarning =>
      'هذا الفرع في وضع المتابعة فقط: لا يمكن لجهاز الكاشير إضافة أصناف إلى فاتورة العميل بعد. فتح طاولة محلية يبدأ فاتورة منفصلة على هذا الجهاز.';

  @override
  String get tableSheetClose => 'إغلاق';

  @override
  String get tableShared => 'مشتركة';

  @override
  String get tableCustomerOccupied => 'مشغولة بواسطة عميل';

  @override
  String get qrPendingTitle => 'قيد الانتظار عبر QR';

  @override
  String get qrPendingWaitingStation => 'بانتظار الدفع عند الجهاز';

  @override
  String get qrPendingAtCounter => 'عند الكاشير';

  @override
  String get qrPendingSessionEnded => 'انتهت الجلسة';

  @override
  String get qrPendingCardInProgress => 'دفع البطاقة جارٍ';

  @override
  String get qrPendingDeclined => 'رُفضت محاولة الدفع';

  @override
  String get qrPendingCancelled => 'أُلغيت محاولة الدفع';

  @override
  String get qrPendingRecovery => 'يحتاج إلى مراجعة';

  @override
  String get qrPendingSendToCounter => 'إرسال إلى الكاشير';

  @override
  String get qrPendingSettle => 'تسوية';

  @override
  String get qrPendingVoid => 'إلغاء الطلب';

  @override
  String get qrPendingEmpty => 'لا توجد طلبات QR سريعة غير مدفوعة.';

  @override
  String get qrPendingUnavailable =>
      'القائمة غير متاحة. حدّثها قبل استلام الدفع.';

  @override
  String get qrPendingRefresh => 'تحديث';

  @override
  String qrPendingStale(String time) {
    return 'لم يتم التحديث منذ $time';
  }

  @override
  String qrPendingAge(int minutes) {
    return 'منذ $minutes دقيقة';
  }

  @override
  String qrPendingItems(int count) {
    return '$count أصناف';
  }

  @override
  String qrPendingPhone(String tail) {
    return 'رقم الهاتف ينتهي بـ $tail';
  }

  @override
  String get qrPendingMoved => 'تم نقل الطلب إلى الكاشير.';

  @override
  String get qrPendingGone => 'لم يعد هذا الطلب قيد الانتظار.';

  @override
  String get qrPendingClose => 'إغلاق';

  @override
  String get pay002Title => 'عكس دفعة البطاقة';

  @override
  String get pay002Void => 'إلغاء دفعة البطاقة';

  @override
  String get pay002Refund => 'استرداد';

  @override
  String get pay002Payment => 'دفعة البطاقة';

  @override
  String get pay002Reason => 'سبب الإلغاء';

  @override
  String get pay002Custom => 'مبلغ مخصص (ر.ع.)';

  @override
  String get pay002Lines => 'كميات الاسترداد';

  @override
  String get pay002Remaining => 'الكمية المتبقية';

  @override
  String get pay002ManagerPin => 'الرمز السري للمدير';

  @override
  String get pay002Continue => 'متابعة';

  @override
  String get pay002Cancel => 'إلغاء';

  @override
  String get pay002Confirm => 'تأكيد مبلغ البنك';

  @override
  String get pay002Progress => 'جارٍ عكس دفعة البطاقة';

  @override
  String get pay002Recovery =>
      'تحقق من الإيصال في سجل تطبيق البنك. أبلغ عن النتيجة أو اتركها للمسؤول. لا تكرر العملية البنكية.';

  @override
  String get pay002Report => 'الإبلاغ عن النتيجة';

  @override
  String get pay002RetryReport => 'إعادة إرسال تقرير النتيجة';

  @override
  String get pay002Reprint => 'إعادة طباعة إيصال العكس';

  @override
  String get pay002PrintFailed =>
      'لم تكتمل الطباعة. أعد الطباعة عند الحاجة فقط.';

  @override
  String get pay002ReceiptJson => 'بيانات الإيصال (JSON من سجل البنك)';

  @override
  String get pay002Operator => 'اسم الموظف';

  @override
  String get pay002NoPayments => 'لا توجد دفعات بطاقة متاحة للعكس.';

  @override
  String get pay002Online => 'يتطلب عكس دفعات البطاقة اتصالاً بالإنترنت.';

  @override
  String get pay002CheckTerminal => 'فحص جهاز الدفع';

  @override
  String get pay002Terminal => 'جهاز الدفع بالبطاقة';

  @override
  String get pay002PayingVia => 'الدفع عبر';

  @override
  String get pay002FirstLaunch =>
      'افتح تطبيق البنك وأكمل إعداده قبل قبول البطاقات.';

  @override
  String get pay002Noterminalcredentials =>
      'لا توجد بيانات اعتماد للجهاز. تواصل مع المسؤول.';

  @override
  String get pay002Softposunavailable => 'جهاز الدفع غير متاح.';

  @override
  String get pay002Softposnotconfigured => 'لم يتم إعداد جهاز الدفع.';

  @override
  String get pay002Softposmismatch =>
      'البنك المعيّن وتطبيق الجهاز غير متطابقين.';

  @override
  String get pay002Softposappupdaterequired => 'يلزم تحديث تطبيق الدفع.';

  @override
  String get pay002Cardblocked => 'دفعات البطاقة محظورة. تواصل مع المسؤول.';

  @override
  String get pay002Select => 'اختر';

  @override
  String get pay002Done => 'إغلاق';

  @override
  String get pay002Approved => 'تمت الموافقة';

  @override
  String get pay002Declined => 'مرفوضة';

  @override
  String get pay002Uncertain => 'النتيجة غير مؤكدة — يجب على المدير التحقق';

  @override
  String get pay002Cancelled => 'أُلغيت قبل الإرسال إلى البنك';

  @override
  String get pay002ResponseCode => 'رمز الاستجابة';

  @override
  String get pay002Rrn => 'الرقم المرجعي للبنك';

  @override
  String get pay002AuthCode => 'رمز التفويض';

  @override
  String get pay002ManagerCheck => 'تحقق من سجل البنك قبل تسجيل هذه الدفعة.';

  @override
  String get ctrlMsgCardTerminalBusy =>
      'جهاز الدفع مشغول. انتظر قليلاً ثم حاول مرة أخرى.';
}
