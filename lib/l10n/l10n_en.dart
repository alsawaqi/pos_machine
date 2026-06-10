// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonPrint => 'Print';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonBack => 'Back';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonLogout => 'Log out';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionServer => 'Server';

  @override
  String get settingsServerAddress => 'Server address';

  @override
  String get settingsServerHint => 'e.g. 192.168.1.50:8088';

  @override
  String settingsUsingDefault(String url) {
    return 'Using the built-in default: $url';
  }

  @override
  String settingsActive(String url) {
    return 'Active: $url';
  }

  @override
  String get settingsTestConnection => 'Test connection';

  @override
  String get settingsSaved => 'Settings saved.';

  @override
  String settingsServerReachable(String url) {
    return 'Server reachable at $url';
  }

  @override
  String settingsServerUnreachable(String url) {
    return 'Could not reach $url';
  }

  @override
  String get settingsResetDefault => 'Reset to default';

  @override
  String get settingsSectionReceipts => 'Receipts';

  @override
  String get settingsPrintReceipts => 'Print receipts';

  @override
  String get settingsPrintReceiptsHint =>
      'Print a Sunmi receipt when an order completes.';

  @override
  String get settingsPrintKitchenTickets => 'Print kitchen tickets';

  @override
  String get settingsPrintKitchenTicketsHint =>
      'Print an items-only kitchen ticket when an order completes or is held.';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsLanguageHint => 'Applies immediately across the app.';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';
}
