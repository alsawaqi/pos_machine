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

  @override
  String get pinLoginTitle => 'Staff login';

  @override
  String get pinLoginSubtitle => 'Enter your PIN to load this branch.';

  @override
  String get pinLoginButton => 'Login';

  @override
  String pinLoginPinLengthError(int min, int max) {
    return 'Enter your $min–$max digit PIN.';
  }

  @override
  String get pinLoginFailedError => 'Login failed. Please try again.';

  @override
  String get shiftOpenTitle => 'Open shift';

  @override
  String get shiftOpenSubtitle => 'Count the opening cash float.';

  @override
  String shiftOpenWelcomeSubtitle(String staffName) {
    return 'Welcome $staffName. Count the opening cash float.';
  }

  @override
  String get shiftOpenCheckingExisting => 'Checking for an open shift…';

  @override
  String get shiftOpenOpeningCashLabel => 'Opening cash (OMR)';

  @override
  String get shiftOpenSubmitButton => 'Open shift';

  @override
  String get shiftOpenErrorNoStaffSession =>
      'No staff session. Please log in again.';

  @override
  String get shiftOpenErrorOpenFailed =>
      'Could not open the shift. Check your connection.';

  @override
  String get shiftOpenErrorAdoptFailed =>
      'This device already has an open shift, but it could not be loaded. Check your connection and try again.';

  @override
  String get shiftCloseTitle => 'Close shift';

  @override
  String get shiftCloseSubmitButton => 'Close shift';

  @override
  String get shiftCloseNoOpenShift => 'No open shift on this device.';

  @override
  String get shiftCloseFailed =>
      'Could not close the shift. Check your connection.';

  @override
  String get shiftCloseOpeningFloatLabel => 'Opening float (OMR)';

  @override
  String get shiftCloseCountedDrawerCashLabel => 'Counted drawer cash (OMR)';

  @override
  String get shiftCloseDrawerBalanced => 'Drawer balanced';

  @override
  String get shiftCloseDrawerShort => 'Drawer short';

  @override
  String get shiftCloseDrawerOver => 'Drawer over';

  @override
  String get shiftCloseExpectedCash => 'Expected cash';

  @override
  String get shiftCloseCountedCash => 'Counted cash';

  @override
  String get shiftCloseVariance => 'Variance';

  @override
  String get shiftClosePrintSummary => 'Print summary';

  @override
  String get deviceSetupTitle => 'Set up this device';

  @override
  String get deviceSetupSubtitle =>
      'Scan or enter the activation code generated for this device in the admin portal. You only do this once.';

  @override
  String get deviceSetupScanQrButton => 'Scan QR code';

  @override
  String get deviceSetupOrEnterManually => 'or enter it manually';

  @override
  String get deviceSetupActivationCodeLabel => 'Activation code';

  @override
  String get deviceSetupSettingsTooltip => 'Settings';

  @override
  String get deviceSetupErrorEnterCode =>
      'Enter the activation code from the admin portal.';

  @override
  String get deviceSetupErrorFailed => 'Device setup failed. Please try again.';

  @override
  String get deviceSetupErrorCameraBlocked =>
      'Camera access is blocked. Enable it in Settings to scan the code (or enter it manually).';

  @override
  String get deviceSetupErrorCameraPermission =>
      'Camera permission is needed to scan the QR code (or enter it manually).';

  @override
  String get terminalSetupTitle => 'Connect This POS Terminal';

  @override
  String get terminalSetupSubtitle =>
      'Enter the terminal ID before the staff POS is unlocked. This value is saved locally and used for Payment Terminaly payment requests.';

  @override
  String get terminalSetupTerminalIdLabel => 'Terminal ID';

  @override
  String get terminalSetupTerminalIdHint => 'Enter the payment terminal ID';

  @override
  String get terminalSetupTerminalIdRequired => 'Please enter the terminal ID.';

  @override
  String terminalSetupSaveFailed(String error) {
    return 'Failed to save the terminal ID: $error';
  }

  @override
  String get terminalSetupContinueButton => 'Continue To POS';

  @override
  String get qrScannerTitle => 'Scan activation code';

  @override
  String get qrScannerSwitchCameraTooltip => 'Switch camera';

  @override
  String get qrScannerHint =>
      'Point the camera at the activation QR code. If it doesn\'t open, tap the switch-camera icon, or go back and enter the code manually.';

  @override
  String qrScannerCameraStartError(String code) {
    return 'Could not start the camera ($code).';
  }

  @override
  String get qrScannerErrorHelp =>
      'Try the switch-camera icon above, use the device scanner, or enter the code manually.';

  @override
  String get qrScannerEnterManuallyButton => 'Enter the code manually';

  @override
  String get geofenceCheckingLocationTitle => 'Checking location…';

  @override
  String get geofenceCheckingLocationMessage =>
      'Acquiring a GPS fix for this branch.';

  @override
  String get geofenceLocationRequiredTitle => 'Location required';

  @override
  String get geofenceLocationRequiredMessage =>
      'Enable location services and grant permission to use the POS.';

  @override
  String get geofenceOutsideTitle => 'Outside the store area';

  @override
  String get geofenceLockedTitle => 'Locked';

  @override
  String get geofenceOutsideNoDistanceMessage =>
      'This device is outside the permitted branch area.';

  @override
  String geofenceOutsideDistanceMessage(int distance, int radius) {
    return 'You are about $distance m from the branch (allowed within $radius m). Move closer, or tap Retry to pull the latest branch location/radius set by the admin.';
  }

  @override
  String get expenseTitle => 'Log expense';

  @override
  String get expenseCategoryLabel => 'Category';

  @override
  String get expenseAmountOmrLabel => 'Amount (OMR)';

  @override
  String get expenseNoteOptionalLabel => 'Note (optional)';

  @override
  String get expenseRecordButton => 'Record expense';

  @override
  String get expenseRecordedMessage => 'Expense recorded.';

  @override
  String get expenseAmountGreaterThanZeroError =>
      'Enter an amount greater than zero.';

  @override
  String get expenseSubmitFailedError =>
      'Could not log the expense. Check your connection.';

  @override
  String get expenseCategoryUtilities => 'Utilities';

  @override
  String get expenseCategorySupplies => 'Supplies';

  @override
  String get expenseCategoryMaintenance => 'Maintenance';

  @override
  String get expenseCategorySalaries => 'Salaries';

  @override
  String get expenseCategoryOther => 'Other';

  @override
  String get restockTitle => 'Request restock';

  @override
  String get restockAddIngredientLabel => 'Add ingredient';

  @override
  String get restockIngredientHint => 'Ingredient';

  @override
  String get restockQtyHint => 'Qty';

  @override
  String get restockNoteLabel => 'Note (optional)';

  @override
  String get restockSubmitButton => 'Submit request';

  @override
  String get restockSubmittedSnack => 'Restock request submitted.';

  @override
  String get restockSubmitFailedError =>
      'Could not submit the request. Check your connection.';

  @override
  String get restockPickIngredientError => 'Pick an ingredient.';

  @override
  String get restockQuantityError => 'Enter a quantity greater than zero.';

  @override
  String get restockAddAtLeastOneError => 'Add at least one ingredient.';

  @override
  String get restockEmptyState =>
      'No ingredients available yet.\nSync the device to load the catalogue.';

  @override
  String restockIngredientFallback(int id) {
    return 'Ingredient #$id';
  }

  @override
  String get stockCountTitle => 'Day-end stock count';

  @override
  String get stockCountInstructions =>
      'Count what is physically on the shelf. Leave a row blank to skip it. Shortfalls are recorded as waste, overages as adjustments.';

  @override
  String stockCountInvalidCount(String name) {
    return 'Invalid count for $name.';
  }

  @override
  String stockCountWholeUnitsOnly(String name, String unitLabel) {
    return '$name is counted in whole ${unitLabel}s.';
  }

  @override
  String get stockCountEnterAtLeastOne => 'Enter at least one counted amount.';

  @override
  String get stockCountSubmittedNoVariance =>
      'Count submitted — everything matched the books.';

  @override
  String stockCountSubmittedWithVariance(int count) {
    return 'Count submitted — $count line(s) had a variance.';
  }

  @override
  String get stockCountSubmitFailed =>
      'Could not submit the count. Check your connection.';

  @override
  String stockCountRowPieceHint(
    String pieceLabel,
    String balance,
    String unit,
  ) {
    return 'Count in ${pieceLabel}s · on book: $balance $unit';
  }

  @override
  String stockCountRowOnBook(String balance, String unit) {
    return 'On book: $balance $unit';
  }

  @override
  String get stockCountQtyHint => 'qty';

  @override
  String get stockCountNoteLabel => 'Note (optional)';

  @override
  String stockCountSubmitButton(int count) {
    return 'Submit count ($count)';
  }

  @override
  String get stockCountEmptyState =>
      'No ingredients available yet.\nSync the device to load the catalogue.';
}
