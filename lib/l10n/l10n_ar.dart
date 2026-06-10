// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class L10nAr extends L10n {
  L10nAr([String locale = 'ar']) : super(locale);

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
  String get stockCountSubmittedNoVariance =>
      'تم إرسال الجرد — كل شيء مطابق للسجلات.';

  @override
  String stockCountSubmittedWithVariance(int count) {
    return 'تم إرسال الجرد — $count من البنود فيها فرق.';
  }

  @override
  String get stockCountSubmitFailed => 'تعذر إرسال الجرد. تحقق من الاتصال.';

  @override
  String stockCountRowPieceHint(
    String pieceLabel,
    String balance,
    String unit,
  ) {
    return 'العدّ بوحدة $pieceLabel · الرصيد الدفتري: $balance $unit';
  }

  @override
  String stockCountRowOnBook(String balance, String unit) {
    return 'الرصيد الدفتري: $balance $unit';
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
}
