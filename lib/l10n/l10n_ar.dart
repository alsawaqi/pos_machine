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
}
