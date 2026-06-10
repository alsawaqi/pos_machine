import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'l10n_ar.dart';
import 'l10n_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get commonPrint;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get commonLogout;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsSectionServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get settingsSectionServer;

  /// No description provided for @settingsServerAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get settingsServerAddress;

  /// No description provided for @settingsServerHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 192.168.1.50:8088'**
  String get settingsServerHint;

  /// No description provided for @settingsUsingDefault.
  ///
  /// In en, this message translates to:
  /// **'Using the built-in default: {url}'**
  String settingsUsingDefault(String url);

  /// No description provided for @settingsActive.
  ///
  /// In en, this message translates to:
  /// **'Active: {url}'**
  String settingsActive(String url);

  /// No description provided for @settingsTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get settingsTestConnection;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved.'**
  String get settingsSaved;

  /// No description provided for @settingsServerReachable.
  ///
  /// In en, this message translates to:
  /// **'Server reachable at {url}'**
  String settingsServerReachable(String url);

  /// No description provided for @settingsServerUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {url}'**
  String settingsServerUnreachable(String url);

  /// No description provided for @settingsResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get settingsResetDefault;

  /// No description provided for @settingsSectionReceipts.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get settingsSectionReceipts;

  /// No description provided for @settingsPrintReceipts.
  ///
  /// In en, this message translates to:
  /// **'Print receipts'**
  String get settingsPrintReceipts;

  /// No description provided for @settingsPrintReceiptsHint.
  ///
  /// In en, this message translates to:
  /// **'Print a Sunmi receipt when an order completes.'**
  String get settingsPrintReceiptsHint;

  /// No description provided for @settingsPrintKitchenTickets.
  ///
  /// In en, this message translates to:
  /// **'Print kitchen tickets'**
  String get settingsPrintKitchenTickets;

  /// No description provided for @settingsPrintKitchenTicketsHint.
  ///
  /// In en, this message translates to:
  /// **'Print an items-only kitchen ticket when an order completes or is held.'**
  String get settingsPrintKitchenTicketsHint;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Applies immediately across the app.'**
  String get settingsLanguageHint;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @pinLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Staff login'**
  String get pinLoginTitle;

  /// No description provided for @pinLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to load this branch.'**
  String get pinLoginSubtitle;

  /// No description provided for @pinLoginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get pinLoginButton;

  /// No description provided for @pinLoginPinLengthError.
  ///
  /// In en, this message translates to:
  /// **'Enter your {min}–{max} digit PIN.'**
  String pinLoginPinLengthError(int min, int max);

  /// No description provided for @pinLoginFailedError.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please try again.'**
  String get pinLoginFailedError;

  /// No description provided for @shiftOpenTitle.
  ///
  /// In en, this message translates to:
  /// **'Open shift'**
  String get shiftOpenTitle;

  /// No description provided for @shiftOpenSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Count the opening cash float.'**
  String get shiftOpenSubtitle;

  /// No description provided for @shiftOpenWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome {staffName}. Count the opening cash float.'**
  String shiftOpenWelcomeSubtitle(String staffName);

  /// No description provided for @shiftOpenCheckingExisting.
  ///
  /// In en, this message translates to:
  /// **'Checking for an open shift…'**
  String get shiftOpenCheckingExisting;

  /// No description provided for @shiftOpenOpeningCashLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening cash (OMR)'**
  String get shiftOpenOpeningCashLabel;

  /// No description provided for @shiftOpenSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Open shift'**
  String get shiftOpenSubmitButton;

  /// No description provided for @shiftOpenErrorNoStaffSession.
  ///
  /// In en, this message translates to:
  /// **'No staff session. Please log in again.'**
  String get shiftOpenErrorNoStaffSession;

  /// No description provided for @shiftOpenErrorOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the shift. Check your connection.'**
  String get shiftOpenErrorOpenFailed;

  /// No description provided for @shiftOpenErrorAdoptFailed.
  ///
  /// In en, this message translates to:
  /// **'This device already has an open shift, but it could not be loaded. Check your connection and try again.'**
  String get shiftOpenErrorAdoptFailed;

  /// No description provided for @shiftCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get shiftCloseTitle;

  /// No description provided for @shiftCloseSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get shiftCloseSubmitButton;

  /// No description provided for @shiftCloseNoOpenShift.
  ///
  /// In en, this message translates to:
  /// **'No open shift on this device.'**
  String get shiftCloseNoOpenShift;

  /// No description provided for @shiftCloseFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not close the shift. Check your connection.'**
  String get shiftCloseFailed;

  /// No description provided for @shiftCloseOpeningFloatLabel.
  ///
  /// In en, this message translates to:
  /// **'Opening float (OMR)'**
  String get shiftCloseOpeningFloatLabel;

  /// No description provided for @shiftCloseCountedDrawerCashLabel.
  ///
  /// In en, this message translates to:
  /// **'Counted drawer cash (OMR)'**
  String get shiftCloseCountedDrawerCashLabel;

  /// No description provided for @shiftCloseDrawerBalanced.
  ///
  /// In en, this message translates to:
  /// **'Drawer balanced'**
  String get shiftCloseDrawerBalanced;

  /// No description provided for @shiftCloseDrawerShort.
  ///
  /// In en, this message translates to:
  /// **'Drawer short'**
  String get shiftCloseDrawerShort;

  /// No description provided for @shiftCloseDrawerOver.
  ///
  /// In en, this message translates to:
  /// **'Drawer over'**
  String get shiftCloseDrawerOver;

  /// No description provided for @shiftCloseExpectedCash.
  ///
  /// In en, this message translates to:
  /// **'Expected cash'**
  String get shiftCloseExpectedCash;

  /// No description provided for @shiftCloseCountedCash.
  ///
  /// In en, this message translates to:
  /// **'Counted cash'**
  String get shiftCloseCountedCash;

  /// No description provided for @shiftCloseVariance.
  ///
  /// In en, this message translates to:
  /// **'Variance'**
  String get shiftCloseVariance;

  /// No description provided for @shiftClosePrintSummary.
  ///
  /// In en, this message translates to:
  /// **'Print summary'**
  String get shiftClosePrintSummary;

  /// No description provided for @deviceSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up this device'**
  String get deviceSetupTitle;

  /// No description provided for @deviceSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan or enter the activation code generated for this device in the admin portal. You only do this once.'**
  String get deviceSetupSubtitle;

  /// No description provided for @deviceSetupScanQrButton.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get deviceSetupScanQrButton;

  /// No description provided for @deviceSetupOrEnterManually.
  ///
  /// In en, this message translates to:
  /// **'or enter it manually'**
  String get deviceSetupOrEnterManually;

  /// No description provided for @deviceSetupActivationCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Activation code'**
  String get deviceSetupActivationCodeLabel;

  /// No description provided for @deviceSetupSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get deviceSetupSettingsTooltip;

  /// No description provided for @deviceSetupErrorEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the activation code from the admin portal.'**
  String get deviceSetupErrorEnterCode;

  /// No description provided for @deviceSetupErrorFailed.
  ///
  /// In en, this message translates to:
  /// **'Device setup failed. Please try again.'**
  String get deviceSetupErrorFailed;

  /// No description provided for @deviceSetupErrorCameraBlocked.
  ///
  /// In en, this message translates to:
  /// **'Camera access is blocked. Enable it in Settings to scan the code (or enter it manually).'**
  String get deviceSetupErrorCameraBlocked;

  /// No description provided for @deviceSetupErrorCameraPermission.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is needed to scan the QR code (or enter it manually).'**
  String get deviceSetupErrorCameraPermission;

  /// No description provided for @terminalSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect This POS Terminal'**
  String get terminalSetupTitle;

  /// No description provided for @terminalSetupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the terminal ID before the staff POS is unlocked. This value is saved locally and used for Payment Terminaly payment requests.'**
  String get terminalSetupSubtitle;

  /// No description provided for @terminalSetupTerminalIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Terminal ID'**
  String get terminalSetupTerminalIdLabel;

  /// No description provided for @terminalSetupTerminalIdHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the payment terminal ID'**
  String get terminalSetupTerminalIdHint;

  /// No description provided for @terminalSetupTerminalIdRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the terminal ID.'**
  String get terminalSetupTerminalIdRequired;

  /// No description provided for @terminalSetupSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save the terminal ID: {error}'**
  String terminalSetupSaveFailed(String error);

  /// No description provided for @terminalSetupContinueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue To POS'**
  String get terminalSetupContinueButton;

  /// No description provided for @qrScannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan activation code'**
  String get qrScannerTitle;

  /// No description provided for @qrScannerSwitchCameraTooltip.
  ///
  /// In en, this message translates to:
  /// **'Switch camera'**
  String get qrScannerSwitchCameraTooltip;

  /// No description provided for @qrScannerHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the activation QR code. If it doesn\'t open, tap the switch-camera icon, or go back and enter the code manually.'**
  String get qrScannerHint;

  /// No description provided for @qrScannerCameraStartError.
  ///
  /// In en, this message translates to:
  /// **'Could not start the camera ({code}).'**
  String qrScannerCameraStartError(String code);

  /// No description provided for @qrScannerErrorHelp.
  ///
  /// In en, this message translates to:
  /// **'Try the switch-camera icon above, use the device scanner, or enter the code manually.'**
  String get qrScannerErrorHelp;

  /// No description provided for @qrScannerEnterManuallyButton.
  ///
  /// In en, this message translates to:
  /// **'Enter the code manually'**
  String get qrScannerEnterManuallyButton;

  /// No description provided for @geofenceCheckingLocationTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking location…'**
  String get geofenceCheckingLocationTitle;

  /// No description provided for @geofenceCheckingLocationMessage.
  ///
  /// In en, this message translates to:
  /// **'Acquiring a GPS fix for this branch.'**
  String get geofenceCheckingLocationMessage;

  /// No description provided for @geofenceLocationRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Location required'**
  String get geofenceLocationRequiredTitle;

  /// No description provided for @geofenceLocationRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable location services and grant permission to use the POS.'**
  String get geofenceLocationRequiredMessage;

  /// No description provided for @geofenceOutsideTitle.
  ///
  /// In en, this message translates to:
  /// **'Outside the store area'**
  String get geofenceOutsideTitle;

  /// No description provided for @geofenceLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get geofenceLockedTitle;

  /// No description provided for @geofenceOutsideNoDistanceMessage.
  ///
  /// In en, this message translates to:
  /// **'This device is outside the permitted branch area.'**
  String get geofenceOutsideNoDistanceMessage;

  /// No description provided for @geofenceOutsideDistanceMessage.
  ///
  /// In en, this message translates to:
  /// **'You are about {distance} m from the branch (allowed within {radius} m). Move closer, or tap Retry to pull the latest branch location/radius set by the admin.'**
  String geofenceOutsideDistanceMessage(int distance, int radius);

  /// No description provided for @expenseTitle.
  ///
  /// In en, this message translates to:
  /// **'Log expense'**
  String get expenseTitle;

  /// No description provided for @expenseCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get expenseCategoryLabel;

  /// No description provided for @expenseAmountOmrLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount (OMR)'**
  String get expenseAmountOmrLabel;

  /// No description provided for @expenseNoteOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get expenseNoteOptionalLabel;

  /// No description provided for @expenseRecordButton.
  ///
  /// In en, this message translates to:
  /// **'Record expense'**
  String get expenseRecordButton;

  /// No description provided for @expenseRecordedMessage.
  ///
  /// In en, this message translates to:
  /// **'Expense recorded.'**
  String get expenseRecordedMessage;

  /// No description provided for @expenseAmountGreaterThanZeroError.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero.'**
  String get expenseAmountGreaterThanZeroError;

  /// No description provided for @expenseSubmitFailedError.
  ///
  /// In en, this message translates to:
  /// **'Could not log the expense. Check your connection.'**
  String get expenseSubmitFailedError;

  /// No description provided for @expenseCategoryUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get expenseCategoryUtilities;

  /// No description provided for @expenseCategorySupplies.
  ///
  /// In en, this message translates to:
  /// **'Supplies'**
  String get expenseCategorySupplies;

  /// No description provided for @expenseCategoryMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get expenseCategoryMaintenance;

  /// No description provided for @expenseCategorySalaries.
  ///
  /// In en, this message translates to:
  /// **'Salaries'**
  String get expenseCategorySalaries;

  /// No description provided for @expenseCategoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get expenseCategoryOther;

  /// No description provided for @restockTitle.
  ///
  /// In en, this message translates to:
  /// **'Request restock'**
  String get restockTitle;

  /// No description provided for @restockAddIngredientLabel.
  ///
  /// In en, this message translates to:
  /// **'Add ingredient'**
  String get restockAddIngredientLabel;

  /// No description provided for @restockIngredientHint.
  ///
  /// In en, this message translates to:
  /// **'Ingredient'**
  String get restockIngredientHint;

  /// No description provided for @restockQtyHint.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get restockQtyHint;

  /// No description provided for @restockNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get restockNoteLabel;

  /// No description provided for @restockSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit request'**
  String get restockSubmitButton;

  /// No description provided for @restockSubmittedSnack.
  ///
  /// In en, this message translates to:
  /// **'Restock request submitted.'**
  String get restockSubmittedSnack;

  /// No description provided for @restockSubmitFailedError.
  ///
  /// In en, this message translates to:
  /// **'Could not submit the request. Check your connection.'**
  String get restockSubmitFailedError;

  /// No description provided for @restockPickIngredientError.
  ///
  /// In en, this message translates to:
  /// **'Pick an ingredient.'**
  String get restockPickIngredientError;

  /// No description provided for @restockQuantityError.
  ///
  /// In en, this message translates to:
  /// **'Enter a quantity greater than zero.'**
  String get restockQuantityError;

  /// No description provided for @restockAddAtLeastOneError.
  ///
  /// In en, this message translates to:
  /// **'Add at least one ingredient.'**
  String get restockAddAtLeastOneError;

  /// No description provided for @restockEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No ingredients available yet.\nSync the device to load the catalogue.'**
  String get restockEmptyState;

  /// No description provided for @restockIngredientFallback.
  ///
  /// In en, this message translates to:
  /// **'Ingredient #{id}'**
  String restockIngredientFallback(int id);

  /// No description provided for @stockCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Day-end stock count'**
  String get stockCountTitle;

  /// No description provided for @stockCountInstructions.
  ///
  /// In en, this message translates to:
  /// **'Count what is physically on the shelf. Leave a row blank to skip it. Shortfalls are recorded as waste, overages as adjustments.'**
  String get stockCountInstructions;

  /// No description provided for @stockCountInvalidCount.
  ///
  /// In en, this message translates to:
  /// **'Invalid count for {name}.'**
  String stockCountInvalidCount(String name);

  /// No description provided for @stockCountWholeUnitsOnly.
  ///
  /// In en, this message translates to:
  /// **'{name} is counted in whole {unitLabel}s.'**
  String stockCountWholeUnitsOnly(String name, String unitLabel);

  /// No description provided for @stockCountEnterAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'Enter at least one counted amount.'**
  String get stockCountEnterAtLeastOne;

  /// No description provided for @stockCountSubmittedNoVariance.
  ///
  /// In en, this message translates to:
  /// **'Count submitted — everything matched the books.'**
  String get stockCountSubmittedNoVariance;

  /// No description provided for @stockCountSubmittedWithVariance.
  ///
  /// In en, this message translates to:
  /// **'Count submitted — {count} line(s) had a variance.'**
  String stockCountSubmittedWithVariance(int count);

  /// No description provided for @stockCountSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not submit the count. Check your connection.'**
  String get stockCountSubmitFailed;

  /// No description provided for @stockCountRowPieceHint.
  ///
  /// In en, this message translates to:
  /// **'Count in {pieceLabel}s · on book: {balance} {unit}'**
  String stockCountRowPieceHint(String pieceLabel, String balance, String unit);

  /// No description provided for @stockCountRowOnBook.
  ///
  /// In en, this message translates to:
  /// **'On book: {balance} {unit}'**
  String stockCountRowOnBook(String balance, String unit);

  /// No description provided for @stockCountQtyHint.
  ///
  /// In en, this message translates to:
  /// **'qty'**
  String get stockCountQtyHint;

  /// No description provided for @stockCountNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get stockCountNoteLabel;

  /// No description provided for @stockCountSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit count ({count})'**
  String stockCountSubmitButton(int count);

  /// No description provided for @stockCountEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No ingredients available yet.\nSync the device to load the catalogue.'**
  String get stockCountEmptyState;
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return L10nAr();
    case 'en':
      return L10nEn();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
