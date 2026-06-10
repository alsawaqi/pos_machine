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

  /// No description provided for @displayOrderTypeQuickOrder.
  ///
  /// In en, this message translates to:
  /// **'Quick Order'**
  String get displayOrderTypeQuickOrder;

  /// No description provided for @displayOrderTypeToGo.
  ///
  /// In en, this message translates to:
  /// **'To Go'**
  String get displayOrderTypeToGo;

  /// No description provided for @displayOrderTypeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get displayOrderTypeDelivery;

  /// No description provided for @displayOrderTypeDineIn.
  ///
  /// In en, this message translates to:
  /// **'Dine In'**
  String get displayOrderTypeDineIn;

  /// No description provided for @displayStatusWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get displayStatusWaiting;

  /// No description provided for @displayStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get displayStatusPaid;

  /// No description provided for @displayStatusPaidPendingRecon.
  ///
  /// In en, this message translates to:
  /// **'Paid (pending reconciliation)'**
  String get displayStatusPaidPendingRecon;

  /// No description provided for @displayStatusAwaitingConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Awaiting confirmation'**
  String get displayStatusAwaitingConfirmation;

  /// No description provided for @displayStatusCardNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Card charge not confirmed'**
  String get displayStatusCardNotConfirmed;

  /// No description provided for @displayStatusPaymentCanceled.
  ///
  /// In en, this message translates to:
  /// **'Payment canceled'**
  String get displayStatusPaymentCanceled;

  /// No description provided for @displayStatusPreparingPayment.
  ///
  /// In en, this message translates to:
  /// **'Preparing payment'**
  String get displayStatusPreparingPayment;

  /// No description provided for @displayStatusProcessingPayment.
  ///
  /// In en, this message translates to:
  /// **'Processing payment'**
  String get displayStatusProcessingPayment;

  /// No description provided for @displayStatusSplitPending.
  ///
  /// In en, this message translates to:
  /// **'Split payment pending'**
  String get displayStatusSplitPending;

  /// No description provided for @displayStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get displayStatusCanceled;

  /// No description provided for @displayStatusPartiallyCanceled.
  ///
  /// In en, this message translates to:
  /// **'Partially Canceled'**
  String get displayStatusPartiallyCanceled;

  /// No description provided for @displayStatusVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get displayStatusVoid;

  /// No description provided for @displayStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get displayStatusRefunded;

  /// No description provided for @displayMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get displayMethodCash;

  /// No description provided for @displayMethodCard.
  ///
  /// In en, this message translates to:
  /// **'Credit Card'**
  String get displayMethodCard;

  /// No description provided for @displayMethodSplit.
  ///
  /// In en, this message translates to:
  /// **'Split Payment'**
  String get displayMethodSplit;

  /// No description provided for @cdProcessingSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Processing Selection'**
  String get cdProcessingSelectionTitle;

  /// No description provided for @cdPreparingPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing Payment'**
  String get cdPreparingPaymentTitle;

  /// No description provided for @cdProcessingSelectionMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait while we confirm your choice and open the payment terminal.'**
  String get cdProcessingSelectionMessage;

  /// No description provided for @cdPreparingPaymentMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait while the payment terminal is opening.'**
  String get cdPreparingPaymentMessage;

  /// No description provided for @cdHeaderPaymentCompleted.
  ///
  /// In en, this message translates to:
  /// **'Payment completed successfully'**
  String get cdHeaderPaymentCompleted;

  /// No description provided for @cdHeaderReviewCharity.
  ///
  /// In en, this message translates to:
  /// **'Review the optional charity round-up before payment'**
  String get cdHeaderReviewCharity;

  /// No description provided for @cdHeaderItemsWillAppear.
  ///
  /// In en, this message translates to:
  /// **'Your items and total will appear here'**
  String get cdHeaderItemsWillAppear;

  /// No description provided for @cdHeaderItemLineCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item line in the current order} other{{count} item lines in the current order}}'**
  String cdHeaderItemLineCount(int count);

  /// No description provided for @cdHeaderTableItemLineCount.
  ///
  /// In en, this message translates to:
  /// **'Table {table} | {count, plural, =1{1 item line in the current order} other{{count} item lines in the current order}}'**
  String cdHeaderTableItemLineCount(String table, int count);

  /// No description provided for @cdHeroRoundUpForCharity.
  ///
  /// In en, this message translates to:
  /// **'Round up for charity'**
  String get cdHeroRoundUpForCharity;

  /// No description provided for @cdHeroReadyForOrder.
  ///
  /// In en, this message translates to:
  /// **'Ready for your order'**
  String get cdHeroReadyForOrder;

  /// No description provided for @cdHeroOrderTotal.
  ///
  /// In en, this message translates to:
  /// **'Order total'**
  String get cdHeroOrderTotal;

  /// No description provided for @cdHeroCharityNote.
  ///
  /// In en, this message translates to:
  /// **'The extra rounded amount will be donated to charity.'**
  String get cdHeroCharityNote;

  /// No description provided for @cdHeroReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Please review your items and total before payment.'**
  String get cdHeroReviewNote;

  /// No description provided for @cdSubtotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get cdSubtotalLabel;

  /// No description provided for @cdTaxLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get cdTaxLabel;

  /// No description provided for @cdPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get cdPaymentLabel;

  /// No description provided for @cdOrderDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get cdOrderDetailsTitle;

  /// No description provided for @cdOrderDetailsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live order view for the customer-facing display'**
  String get cdOrderDetailsSubtitle;

  /// No description provided for @cdBannerThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your visit. Your order has been completed.'**
  String get cdBannerThankYou;

  /// No description provided for @cdBannerReviewWhileCashier.
  ///
  /// In en, this message translates to:
  /// **'Please review the order details while the cashier prepares payment.'**
  String get cdBannerReviewWhileCashier;

  /// No description provided for @cdTapToPayTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap Here To Pay'**
  String get cdTapToPayTitle;

  /// No description provided for @cdTapToPaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your payment is ready. Please tap your card or phone on the customer-facing NFC area.'**
  String get cdTapToPaySubtitle;

  /// No description provided for @cdContactlessReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready for contactless payment'**
  String get cdContactlessReadyTitle;

  /// No description provided for @cdContactlessHoldHint.
  ///
  /// In en, this message translates to:
  /// **'Hold the card, phone, or wearable near the rear NFC area until the terminal confirms the transaction.'**
  String get cdContactlessHoldHint;

  /// No description provided for @cdChipCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get cdChipCard;

  /// No description provided for @cdChipPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get cdChipPhone;

  /// No description provided for @cdChipWearable.
  ///
  /// In en, this message translates to:
  /// **'Wearable'**
  String get cdChipWearable;

  /// No description provided for @cdTotalToPay.
  ///
  /// In en, this message translates to:
  /// **'Total to pay'**
  String get cdTotalToPay;

  /// No description provided for @cdIncludesCharityRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Includes {amount} charity round-up.'**
  String cdIncludesCharityRoundUp(String amount);

  /// No description provided for @cdPresentToContinue.
  ///
  /// In en, this message translates to:
  /// **'Present your card, phone, or wearable to continue the payment.'**
  String get cdPresentToContinue;

  /// No description provided for @cdTapFooterKeepNear.
  ///
  /// In en, this message translates to:
  /// **'Keep the card or phone near the customer-facing NFC area until the terminal confirms the payment.'**
  String get cdTapFooterKeepNear;

  /// No description provided for @cdCharityTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Up For Charity?'**
  String get cdCharityTitle;

  /// No description provided for @cdCharityQuestion.
  ///
  /// In en, this message translates to:
  /// **'Would you like to round your payment to the next whole OMR? Only the extra amount will be donated to charity.'**
  String get cdCharityQuestion;

  /// No description provided for @cdCharityEncouragement.
  ///
  /// In en, this message translates to:
  /// **'A small round-up can make a meaningful donation while keeping your payment simple.'**
  String get cdCharityEncouragement;

  /// No description provided for @cdCharityTileOrderTotal.
  ///
  /// In en, this message translates to:
  /// **'Order Total'**
  String get cdCharityTileOrderTotal;

  /// No description provided for @cdCharityTileOrderTotalCaption.
  ///
  /// In en, this message translates to:
  /// **'Current order amount'**
  String get cdCharityTileOrderTotalCaption;

  /// No description provided for @cdCharityTileRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Round Up'**
  String get cdCharityTileRoundUp;

  /// No description provided for @cdCharityTileRoundUpCaption.
  ///
  /// In en, this message translates to:
  /// **'Extra donation amount'**
  String get cdCharityTileRoundUpCaption;

  /// No description provided for @cdCharityTileNewTotal.
  ///
  /// In en, this message translates to:
  /// **'New Total'**
  String get cdCharityTileNewTotal;

  /// No description provided for @cdCharityTileNewTotalCaption.
  ///
  /// In en, this message translates to:
  /// **'Final amount to pay'**
  String get cdCharityTileNewTotalCaption;

  /// No description provided for @cdCharityNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get cdCharityNo;

  /// No description provided for @cdCharityNoSubtitleShort.
  ///
  /// In en, this message translates to:
  /// **'Keep original total'**
  String get cdCharityNoSubtitleShort;

  /// No description provided for @cdCharityNoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pay the original order total'**
  String get cdCharityNoSubtitle;

  /// No description provided for @cdCharityYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get cdCharityYes;

  /// No description provided for @cdCharityYesSubtitleShort.
  ///
  /// In en, this message translates to:
  /// **'Round up to donate'**
  String get cdCharityYesSubtitleShort;

  /// No description provided for @cdCharityYesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Round up and donate the extra amount'**
  String get cdCharityYesSubtitle;

  /// No description provided for @cdTouchOkCount.
  ///
  /// In en, this message translates to:
  /// **'Touch OK x{count}'**
  String cdTouchOkCount(int count);

  /// No description provided for @cdTouchTestTitle.
  ///
  /// In en, this message translates to:
  /// **'Touch Test'**
  String get cdTouchTestTitle;

  /// No description provided for @cdTouchTestHint.
  ///
  /// In en, this message translates to:
  /// **'Tap here to verify'**
  String get cdTouchTestHint;

  /// No description provided for @cdTouchDetectedAt.
  ///
  /// In en, this message translates to:
  /// **'Rear touch detected at {time} (#{count})'**
  String cdTouchDetectedAt(String time, int count);

  /// No description provided for @cdBadgeUpdatingChoice.
  ///
  /// In en, this message translates to:
  /// **'UPDATING CHOICE'**
  String get cdBadgeUpdatingChoice;

  /// No description provided for @cdBadgeSecureCardPayment.
  ///
  /// In en, this message translates to:
  /// **'SECURE CARD PAYMENT'**
  String get cdBadgeSecureCardPayment;

  /// No description provided for @cdQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity: {qty}'**
  String cdQuantity(int qty);

  /// No description provided for @cdNoItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No items yet'**
  String get cdNoItemsYet;

  /// No description provided for @cdEmptyStateHint.
  ///
  /// In en, this message translates to:
  /// **'The display will update as soon as the cashier adds products.'**
  String get cdEmptyStateHint;

  /// No description provided for @cdFinalBadge.
  ///
  /// In en, this message translates to:
  /// **'FINAL'**
  String get cdFinalBadge;

  /// No description provided for @cdSummaryPaid.
  ///
  /// In en, this message translates to:
  /// **'Thank you. Your payment has been completed.'**
  String get cdSummaryPaid;

  /// No description provided for @cdSummaryAwaitingCashier.
  ///
  /// In en, this message translates to:
  /// **'A cashier will confirm the order and complete payment when ready.'**
  String get cdSummaryAwaitingCashier;

  /// No description provided for @ctrlMsgChooseTableDineIn.
  ///
  /// In en, this message translates to:
  /// **'Choose a table to start or continue a dine-in order.'**
  String get ctrlMsgChooseTableDineIn;

  /// No description provided for @ctrlMsgEditingTableOnFloor.
  ///
  /// In en, this message translates to:
  /// **'Editing {table} in {floor}.'**
  String ctrlMsgEditingTableOnFloor(String table, String floor);

  /// No description provided for @ctrlMsgAddItemsForTable.
  ///
  /// In en, this message translates to:
  /// **'Add items for {table}.'**
  String ctrlMsgAddItemsForTable(String table);

  /// No description provided for @ctrlMsgAssignItemsToTable.
  ///
  /// In en, this message translates to:
  /// **'Assigning the current items to {table}.'**
  String ctrlMsgAssignItemsToTable(String table);

  /// No description provided for @ctrlFloorFallbackDining.
  ///
  /// In en, this message translates to:
  /// **'Dining'**
  String get ctrlFloorFallbackDining;

  /// No description provided for @ctrlMsgOrderHeld.
  ///
  /// In en, this message translates to:
  /// **'Reference {reference} was placed on hold.'**
  String ctrlMsgOrderHeld(String reference);

  /// No description provided for @ctrlMsgHoldFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to hold the order right now.'**
  String get ctrlMsgHoldFailed;

  /// No description provided for @ctrlMsgOrderResumed.
  ///
  /// In en, this message translates to:
  /// **'Resumed held reference {reference}.'**
  String ctrlMsgOrderResumed(String reference);

  /// No description provided for @ctrlMsgHeldOrderDiscarded.
  ///
  /// In en, this message translates to:
  /// **'Held reference {reference} was discarded.'**
  String ctrlMsgHeldOrderDiscarded(String reference);

  /// No description provided for @ctrlMsgOrderAlreadyCanceled.
  ///
  /// In en, this message translates to:
  /// **'Order #{n} is already fully canceled.'**
  String ctrlMsgOrderAlreadyCanceled(int n);

  /// No description provided for @ctrlMsgNoCancellableItems.
  ///
  /// In en, this message translates to:
  /// **'No cancellable items were selected.'**
  String get ctrlMsgNoCancellableItems;

  /// No description provided for @ctrlMsgOrderCanceledByManagerNote.
  ///
  /// In en, this message translates to:
  /// **'Order canceled by manager.'**
  String get ctrlMsgOrderCanceledByManagerNote;

  /// No description provided for @ctrlMsgItemsCanceledByManagerNote.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item canceled by manager.} other{{count} items canceled by manager.}}'**
  String ctrlMsgItemsCanceledByManagerNote(int count);

  /// No description provided for @ctrlMsgOrderFullyCanceled.
  ///
  /// In en, this message translates to:
  /// **'Order #{n} was fully canceled.'**
  String ctrlMsgOrderFullyCanceled(int n);

  /// No description provided for @ctrlMsgItemsCanceledFromOrder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item canceled} other{{count} items canceled}} from order #{n}.'**
  String ctrlMsgItemsCanceledFromOrder(int count, int n);

  /// No description provided for @ctrlMsgPaymentCanceledWithMethod.
  ///
  /// In en, this message translates to:
  /// **'{method} payment canceled.'**
  String ctrlMsgPaymentCanceledWithMethod(String method);

  /// No description provided for @ctrlMsgCustomerResponseTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timed out waiting for the customer response.'**
  String get ctrlMsgCustomerResponseTimeout;

  /// No description provided for @ctrlMsgTenderedCashTooLow.
  ///
  /// In en, this message translates to:
  /// **'Tendered cash must be at least {amount}.'**
  String ctrlMsgTenderedCashTooLow(String amount);

  /// No description provided for @ctrlMsgCashierCompletingSplitCash.
  ///
  /// In en, this message translates to:
  /// **'The cashier is completing split bill cash payment {index} of {total}.'**
  String ctrlMsgCashierCompletingSplitCash(int index, int total);

  /// No description provided for @ctrlMsgCashierCompletingCash.
  ///
  /// In en, this message translates to:
  /// **'The cashier is completing a cash payment.'**
  String get ctrlMsgCashierCompletingCash;

  /// No description provided for @ctrlMsgCashPaymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Cash payment recorded successfully.'**
  String get ctrlMsgCashPaymentRecorded;

  /// No description provided for @ctrlMsgCashPaymentCompleted.
  ///
  /// In en, this message translates to:
  /// **'Cash payment completed. Thank you.'**
  String get ctrlMsgCashPaymentCompleted;

  /// No description provided for @ctrlMsgTapToPayRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Thank you for rounding up for charity. Tap your card or phone on the rear NFC area to pay.'**
  String get ctrlMsgTapToPayRoundUp;

  /// No description provided for @ctrlMsgTapToPay.
  ///
  /// In en, this message translates to:
  /// **'Tap your card or phone on the rear NFC area to pay.'**
  String get ctrlMsgTapToPay;

  /// No description provided for @ctrlMsgCardPendingReconRecorded.
  ///
  /// In en, this message translates to:
  /// **'Card recorded as pending reconciliation. The bank settlement will confirm it.'**
  String get ctrlMsgCardPendingReconRecorded;

  /// No description provided for @ctrlMsgPaymentPendingBankThanks.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded pending bank confirmation. Thank you.'**
  String get ctrlMsgPaymentPendingBankThanks;

  /// No description provided for @ctrlMsgCardApprovedRoundUpThanks.
  ///
  /// In en, this message translates to:
  /// **'{message} Thank you for supporting charity.'**
  String ctrlMsgCardApprovedRoundUpThanks(String message);

  /// No description provided for @ctrlMsgPaymentApprovedRoundUpNote.
  ///
  /// In en, this message translates to:
  /// **'Payment approved. Your round-up donation will go to charity. Thank you.'**
  String get ctrlMsgPaymentApprovedRoundUpNote;

  /// No description provided for @ctrlMsgPaymentApprovedNote.
  ///
  /// In en, this message translates to:
  /// **'Payment approved. Thank you.'**
  String get ctrlMsgPaymentApprovedNote;

  /// No description provided for @ctrlMsgClearSplitBillFirst.
  ///
  /// In en, this message translates to:
  /// **'Clear Split Bill before using cash and card split payment.'**
  String get ctrlMsgClearSplitBillFirst;

  /// No description provided for @ctrlMsgEnterCashBelowTotal.
  ///
  /// In en, this message translates to:
  /// **'Enter a cash amount less than {amount} before using split payment.'**
  String ctrlMsgEnterCashBelowTotal(String amount);

  /// No description provided for @ctrlMsgSplitPaymentCanceled.
  ///
  /// In en, this message translates to:
  /// **'Split payment canceled.'**
  String get ctrlMsgSplitPaymentCanceled;

  /// No description provided for @ctrlMsgTapForRemainingSplitRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Thank you for rounding up for charity. Tap your card or phone for the remaining split payment.'**
  String get ctrlMsgTapForRemainingSplitRoundUp;

  /// No description provided for @ctrlMsgTapForRemainingSplit.
  ///
  /// In en, this message translates to:
  /// **'Tap your card or phone for the remaining split payment.'**
  String get ctrlMsgTapForRemainingSplit;

  /// No description provided for @ctrlMsgSplitRecordedCardPending.
  ///
  /// In en, this message translates to:
  /// **'Split payment recorded. Cash {cash}; card {card} pending reconciliation.'**
  String ctrlMsgSplitRecordedCardPending(String cash, String card);

  /// No description provided for @ctrlMsgSplitCompletedCashCard.
  ///
  /// In en, this message translates to:
  /// **'Split payment completed. Cash {cash} and card {card} recorded.'**
  String ctrlMsgSplitCompletedCashCard(String cash, String card);

  /// No description provided for @ctrlMsgCashReceivedCardPendingNote.
  ///
  /// In en, this message translates to:
  /// **'Cash received; card payment recorded pending bank confirmation. Thank you.'**
  String get ctrlMsgCashReceivedCardPendingNote;

  /// No description provided for @ctrlMsgSplitCompletedRoundUpNote.
  ///
  /// In en, this message translates to:
  /// **'Split payment completed with a card round-up donation. Thank you.'**
  String get ctrlMsgSplitCompletedRoundUpNote;

  /// No description provided for @ctrlMsgSplitCompletedNote.
  ///
  /// In en, this message translates to:
  /// **'Split payment completed. Thank you.'**
  String get ctrlMsgSplitCompletedNote;

  /// No description provided for @ctrlMsgSplitProgressRecorded.
  ///
  /// In en, this message translates to:
  /// **'Split payment {index} of {total} recorded. Continue with guest {next}.'**
  String ctrlMsgSplitProgressRecorded(int index, int total, int next);

  /// No description provided for @ctrlMsgGuestPaidCollectNext.
  ///
  /// In en, this message translates to:
  /// **'Guest {index} paid {amount}. Collect split payment {next} of {total}.'**
  String ctrlMsgGuestPaidCollectNext(
    int index,
    String amount,
    int next,
    int total,
  );

  /// No description provided for @ctrlMsgSplitCompletedSummary.
  ///
  /// In en, this message translates to:
  /// **'Split payment completed. {total} payments recorded for {amount}.'**
  String ctrlMsgSplitCompletedSummary(int total, String amount);

  /// No description provided for @ctrlMsgSplitBillCompletedNote.
  ///
  /// In en, this message translates to:
  /// **'Split bill completed with {total} payments. Thank you.'**
  String ctrlMsgSplitBillCompletedNote(int total);

  /// No description provided for @ctrlMsgRoundUpPromptQuestion.
  ///
  /// In en, this message translates to:
  /// **'Would you like to round up {amount} to charity?'**
  String ctrlMsgRoundUpPromptQuestion(String amount);

  /// No description provided for @ctrlOverlayPreparingCashPayment.
  ///
  /// In en, this message translates to:
  /// **'Preparing Cash Payment'**
  String get ctrlOverlayPreparingCashPayment;

  /// No description provided for @ctrlOverlayPreparingSecurePayment.
  ///
  /// In en, this message translates to:
  /// **'Preparing Secure Payment'**
  String get ctrlOverlayPreparingSecurePayment;

  /// No description provided for @ctrlMsgPreparingRoundedCash.
  ///
  /// In en, this message translates to:
  /// **'Thank you. We are preparing the rounded amount for cash payment.'**
  String get ctrlMsgPreparingRoundedCash;

  /// No description provided for @ctrlMsgPreparingRoundedCard.
  ///
  /// In en, this message translates to:
  /// **'Thank you. We are preparing the rounded amount for card payment.'**
  String get ctrlMsgPreparingRoundedCard;

  /// No description provided for @ctrlMsgPreparingOriginalCash.
  ///
  /// In en, this message translates to:
  /// **'Thank you. We are preparing the original amount for cash payment.'**
  String get ctrlMsgPreparingOriginalCash;

  /// No description provided for @ctrlMsgPreparingOriginalCard.
  ///
  /// In en, this message translates to:
  /// **'Thank you. We are preparing the original amount for card payment.'**
  String get ctrlMsgPreparingOriginalCard;

  /// No description provided for @ctrlMsgCardUnconfirmedReviewing.
  ///
  /// In en, this message translates to:
  /// **'The card charge could not be confirmed. Staff is reviewing the payment.'**
  String get ctrlMsgCardUnconfirmedReviewing;

  /// No description provided for @ctrlOverlayConnectingTerminal.
  ///
  /// In en, this message translates to:
  /// **'Connecting To Payment Terminal'**
  String get ctrlOverlayConnectingTerminal;

  /// No description provided for @ctrlOverlayWaitingPaymentResult.
  ///
  /// In en, this message translates to:
  /// **'Waiting For Payment Result'**
  String get ctrlOverlayWaitingPaymentResult;

  /// No description provided for @ctrlMsgTerminalOpening.
  ///
  /// In en, this message translates to:
  /// **'Payment Terminal is opening securely. Please wait while the payment terminal prepares the transaction.'**
  String get ctrlMsgTerminalOpening;

  /// No description provided for @ctrlMsgRoundedSentToTerminal.
  ///
  /// In en, this message translates to:
  /// **'The rounded amount has been sent to Payment Terminal. Please follow the terminal instructions while we wait for the final response.'**
  String get ctrlMsgRoundedSentToTerminal;

  /// No description provided for @ctrlMsgTotalSentToTerminal.
  ///
  /// In en, this message translates to:
  /// **'The order total has been sent to Payment Terminal. Please follow the terminal instructions while we wait for the final response.'**
  String get ctrlMsgTotalSentToTerminal;

  /// No description provided for @managerAuthRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Register Manager Fingerprint'**
  String get managerAuthRegisterTitle;

  /// No description provided for @managerAuthRegisterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manager authorization setup'**
  String get managerAuthRegisterSubtitle;

  /// No description provided for @managerAuthRegisterDescription.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint on the device sensor.'**
  String get managerAuthRegisterDescription;

  /// No description provided for @managerAuthApprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager Approval Required'**
  String get managerAuthApprovalRequiredTitle;

  /// No description provided for @managerAuthCancelOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel completed order'**
  String get managerAuthCancelOrderSubtitle;

  /// No description provided for @managerAuthCancelOrderDescription.
  ///
  /// In en, this message translates to:
  /// **'Place your fingerprint to unlock order cancellation.'**
  String get managerAuthCancelOrderDescription;

  /// No description provided for @managerAuthDefaultSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manager approval'**
  String get managerAuthDefaultSubtitle;

  /// No description provided for @managerAuthDefaultDescription.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to approve.'**
  String get managerAuthDefaultDescription;

  /// No description provided for @posCompNothingTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to Comp'**
  String get posCompNothingTitle;

  /// No description provided for @posCompNothingMessage.
  ///
  /// In en, this message translates to:
  /// **'Add items to the order first.'**
  String get posCompNothingMessage;

  /// No description provided for @posCompAppliedTitle.
  ///
  /// In en, this message translates to:
  /// **'Comp Applied'**
  String get posCompAppliedTitle;

  /// No description provided for @posCompExistingMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{reason}\" is comping {amount} on this order.'**
  String posCompExistingMessage(String reason, String amount);

  /// No description provided for @posCompRemoveButton.
  ///
  /// In en, this message translates to:
  /// **'Remove comp'**
  String get posCompRemoveButton;

  /// No description provided for @posCompKeepButton.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get posCompKeepButton;

  /// No description provided for @posCompRemovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Comp Removed'**
  String get posCompRemovedTitle;

  /// No description provided for @posCompRemovedMessage.
  ///
  /// In en, this message translates to:
  /// **'The order is back to its full total.'**
  String get posCompRemovedMessage;

  /// No description provided for @posCompRegisterManagerMessage.
  ///
  /// In en, this message translates to:
  /// **'Register the manager fingerprint once before comping items.'**
  String get posCompRegisterManagerMessage;

  /// No description provided for @posCompManagerApprovalMessage.
  ///
  /// In en, this message translates to:
  /// **'Comps always need manager approval.'**
  String get posCompManagerApprovalMessage;

  /// No description provided for @posCompLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Comp Locked'**
  String get posCompLockedTitle;

  /// No description provided for @posCompDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Comp (Manager)'**
  String get posCompDialogTitle;

  /// No description provided for @posCompWhatLabel.
  ///
  /// In en, this message translates to:
  /// **'What is being comped?'**
  String get posCompWhatLabel;

  /// No description provided for @posCompWholeOrderOption.
  ///
  /// In en, this message translates to:
  /// **'Whole order'**
  String get posCompWholeOrderOption;

  /// No description provided for @posCompReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get posCompReasonLabel;

  /// No description provided for @posCompAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Comp amount: {amount}'**
  String posCompAmountLabel(String amount);

  /// No description provided for @posCompExceedsCapMessage.
  ///
  /// In en, this message translates to:
  /// **'Exceeds the \"{reason}\" cap of {cap}.'**
  String posCompExceedsCapMessage(String reason, String cap);

  /// No description provided for @posCompApplyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply comp'**
  String get posCompApplyButton;

  /// No description provided for @posCompAppliedMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{reason}\" — {amount} written off.'**
  String posCompAppliedMessage(String reason, String amount);

  /// No description provided for @posManagerRegisterFingerprintTitle.
  ///
  /// In en, this message translates to:
  /// **'Register Manager Fingerprint'**
  String get posManagerRegisterFingerprintTitle;

  /// No description provided for @posManagerApprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager Approval Required'**
  String get posManagerApprovalRequiredTitle;

  /// No description provided for @posManagerFingerprintNotApprovedMessage.
  ///
  /// In en, this message translates to:
  /// **'Manager fingerprint was not approved.'**
  String get posManagerFingerprintNotApprovedMessage;

  /// No description provided for @posManagerRegisterSensorMessage.
  ///
  /// In en, this message translates to:
  /// **'Place the manager finger on the sensor to enable cancellation.'**
  String get posManagerRegisterSensorMessage;

  /// No description provided for @posManagerRegisteredTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager Registered'**
  String get posManagerRegisteredTitle;

  /// No description provided for @posManagerRegistrationNotCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration Not Completed'**
  String get posManagerRegistrationNotCompletedTitle;

  /// No description provided for @posManagerRegisteredMessage.
  ///
  /// In en, this message translates to:
  /// **'Manager fingerprint approval is ready for order cancellation.'**
  String get posManagerRegisteredMessage;

  /// No description provided for @posManagerNotRegisteredMessage.
  ///
  /// In en, this message translates to:
  /// **'The manager fingerprint was not registered on this terminal.'**
  String get posManagerNotRegisteredMessage;

  /// No description provided for @posPayTenderedTooLowTitle.
  ///
  /// In en, this message translates to:
  /// **'Tendered Amount Too Low'**
  String get posPayTenderedTooLowTitle;

  /// No description provided for @posPayTenderedTooLowMessage.
  ///
  /// In en, this message translates to:
  /// **'Tendered cash must be at least {amount}.'**
  String posPayTenderedTooLowMessage(String amount);

  /// No description provided for @posPayClearSplitFirstTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Split Bill First'**
  String get posPayClearSplitFirstTitle;

  /// No description provided for @posPayClearSplitFirstMessage.
  ///
  /// In en, this message translates to:
  /// **'Cash and card split payment can be used after clearing guest split bill.'**
  String get posPayClearSplitFirstMessage;

  /// No description provided for @posPayEnterCashPortionTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Cash Portion'**
  String get posPayEnterCashPortionTitle;

  /// No description provided for @posPayEnterCashPortionMessage.
  ///
  /// In en, this message translates to:
  /// **'Enter the cash amount first. It must be less than {amount} so the rest can go to card.'**
  String posPayEnterCashPortionMessage(String amount);

  /// No description provided for @posHoldOrderHeldTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Held'**
  String get posHoldOrderHeldTitle;

  /// No description provided for @posHeldOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Held Orders'**
  String get posHeldOrdersTitle;

  /// No description provided for @posHeldOrdersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Resume any paused ticket and continue from where you left off.'**
  String get posHeldOrdersSubtitle;

  /// No description provided for @posHeldResumedTitle.
  ///
  /// In en, this message translates to:
  /// **'Held Order Resumed'**
  String get posHeldResumedTitle;

  /// No description provided for @posHeldDiscardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard Held Order?'**
  String get posHeldDiscardConfirmTitle;

  /// No description provided for @posHeldDiscardConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Reference {reference} will be removed and cannot be resumed afterwards.'**
  String posHeldDiscardConfirmMessage(String reference);

  /// No description provided for @posHeldKeepButton.
  ///
  /// In en, this message translates to:
  /// **'Keep It'**
  String get posHeldKeepButton;

  /// No description provided for @posHeldDiscardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get posHeldDiscardButton;

  /// No description provided for @posHeldDiscardedTitle.
  ///
  /// In en, this message translates to:
  /// **'Held Order Discarded'**
  String get posHeldDiscardedTitle;

  /// No description provided for @posHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Order History'**
  String get posHistoryTitle;

  /// No description provided for @posHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review completed orders, their payment details, and reprint receipts whenever needed.'**
  String get posHistorySubtitle;

  /// No description provided for @posHistoryReceiptPrintedTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt Printed'**
  String get posHistoryReceiptPrintedTitle;

  /// No description provided for @posHistoryReceiptPrintedMessage.
  ///
  /// In en, this message translates to:
  /// **'Previous receipt for order #{orderNumber} was sent to the printer.'**
  String posHistoryReceiptPrintedMessage(int orderNumber);

  /// No description provided for @posKitchenReprintSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reprint kitchen ticket'**
  String get posKitchenReprintSubtitle;

  /// No description provided for @posKitchenReprintDescription.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to reprint the kitchen ticket for order #{orderNumber}.'**
  String posKitchenReprintDescription(int orderNumber);

  /// No description provided for @posKitchenApprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval Required'**
  String get posKitchenApprovalRequiredTitle;

  /// No description provided for @posKitchenApprovalDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Manager approval was not granted for the kitchen reprint.'**
  String get posKitchenApprovalDeniedMessage;

  /// No description provided for @posKitchenTicketPrintedTitle.
  ///
  /// In en, this message translates to:
  /// **'Kitchen Ticket Printed'**
  String get posKitchenTicketPrintedTitle;

  /// No description provided for @posKitchenTicketPrintedMessage.
  ///
  /// In en, this message translates to:
  /// **'Kitchen ticket for order #{orderNumber} was sent to the printer.'**
  String posKitchenTicketPrintedMessage(int orderNumber);

  /// No description provided for @posCancelReqNotAllowedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Not Allowed'**
  String get posCancelReqNotAllowedTitle;

  /// No description provided for @posCancelReqNotAllowedMessage.
  ///
  /// In en, this message translates to:
  /// **'Your role is not permitted to cancel orders on this terminal.'**
  String get posCancelReqNotAllowedMessage;

  /// No description provided for @posCancelReqRegisterManagerMessage.
  ///
  /// In en, this message translates to:
  /// **'Register the manager fingerprint once before cancelling this completed order.'**
  String get posCancelReqRegisterManagerMessage;

  /// No description provided for @posCancelReqManagerRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager Fingerprint Required'**
  String get posCancelReqManagerRequiredTitle;

  /// No description provided for @posCancelReqUnlockMessage.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to unlock cancellation.'**
  String get posCancelReqUnlockMessage;

  /// No description provided for @posCancelReqLockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Locked'**
  String get posCancelReqLockedTitle;

  /// No description provided for @posCancelReqOrderCanceledTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Canceled'**
  String get posCancelReqOrderCanceledTitle;

  /// No description provided for @posCancelReqItemsCanceledTitle.
  ///
  /// In en, this message translates to:
  /// **'Items Canceled'**
  String get posCancelReqItemsCanceledTitle;

  /// No description provided for @posCancelReqDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get posCancelReqDialogTitle;

  /// No description provided for @posSearchProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Products'**
  String get posSearchProductsTitle;

  /// No description provided for @posSearchProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Type product name or category'**
  String get posSearchProductsHint;

  /// No description provided for @posSearchTablesTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Tables'**
  String get posSearchTablesTitle;

  /// No description provided for @posSearchTablesHint.
  ///
  /// In en, this message translates to:
  /// **'Search by table name or ticket'**
  String get posSearchTablesHint;

  /// No description provided for @posCustomerSearchOption.
  ///
  /// In en, this message translates to:
  /// **'Search customer'**
  String get posCustomerSearchOption;

  /// No description provided for @posCustomerSearchOptionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find by name / phone / plate, see loyalty'**
  String get posCustomerSearchOptionSubtitle;

  /// No description provided for @posCustomerEnterNumberOption.
  ///
  /// In en, this message translates to:
  /// **'Enter number'**
  String get posCustomerEnterNumberOption;

  /// No description provided for @posCustomerClearOption.
  ///
  /// In en, this message translates to:
  /// **'Clear customer'**
  String get posCustomerClearOption;

  /// No description provided for @posCustomerAttachedTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Attached'**
  String get posCustomerAttachedTitle;

  /// No description provided for @posCustomerAttachedWithPoints.
  ///
  /// In en, this message translates to:
  /// **'{name}  ·  {count, plural, =1{1 point} other{{count} points}}'**
  String posCustomerAttachedWithPoints(String name, int count);

  /// No description provided for @posCustomerAttachedSummary.
  ///
  /// In en, this message translates to:
  /// **'{name}  ·  {summary}'**
  String posCustomerAttachedSummary(String name, String summary);

  /// No description provided for @posCustomerNumberTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer Number'**
  String get posCustomerNumberTitle;

  /// No description provided for @posCustomerNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Enter number, then fetch loyalty'**
  String get posCustomerNumberHint;

  /// No description provided for @posCustomerNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'No Customer Found'**
  String get posCustomerNotFoundTitle;

  /// No description provided for @posCustomerNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'No customer matches \"{query}\". Kept as an order reference.'**
  String posCustomerNotFoundMessage(String query);

  /// No description provided for @posLoyaltySummaryPoints.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pt} other{{count} pts}}'**
  String posLoyaltySummaryPoints(int count);

  /// No description provided for @posLoyaltySummaryStamps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stamp} other{{count} stamps}}'**
  String posLoyaltySummaryStamps(int count);

  /// No description provided for @posLoyaltyNoneYet.
  ///
  /// In en, this message translates to:
  /// **'no loyalty yet'**
  String get posLoyaltyNoneYet;

  /// No description provided for @posLoyaltyRedeemButton.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get posLoyaltyRedeemButton;

  /// No description provided for @posLoyaltyRewardRedeemedTitle.
  ///
  /// In en, this message translates to:
  /// **'Reward Redeemed'**
  String get posLoyaltyRewardRedeemedTitle;

  /// No description provided for @posLoyaltyStampRedeemedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stamp} other{{count} stamps}} → {amount} off.'**
  String posLoyaltyStampRedeemedMessage(int count, String amount);

  /// No description provided for @posLoyaltyNoCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'No Customer'**
  String get posLoyaltyNoCustomerTitle;

  /// No description provided for @posLoyaltyNoCustomerMessage.
  ///
  /// In en, this message translates to:
  /// **'Attach a customer first to redeem loyalty.'**
  String get posLoyaltyNoCustomerMessage;

  /// No description provided for @posLoyaltyNothingToRedeemTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to Redeem'**
  String get posLoyaltyNothingToRedeemTitle;

  /// No description provided for @posLoyaltyNothingToRedeemMessage.
  ///
  /// In en, this message translates to:
  /// **'No redeemable points or stamps for this order yet.'**
  String get posLoyaltyNothingToRedeemMessage;

  /// No description provided for @posLoyaltyCannotRedeemTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot Redeem'**
  String get posLoyaltyCannotRedeemTitle;

  /// No description provided for @posLoyaltyCannotRedeemMessage.
  ///
  /// In en, this message translates to:
  /// **'The order total is too low to redeem a block.'**
  String get posLoyaltyCannotRedeemMessage;

  /// No description provided for @posLoyaltyPointsRedeemedTitle.
  ///
  /// In en, this message translates to:
  /// **'Points Redeemed'**
  String get posLoyaltyPointsRedeemedTitle;

  /// No description provided for @posLoyaltyPointsRedeemedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point} other{{count} points}} → {amount} off.'**
  String posLoyaltyPointsRedeemedMessage(int count, String amount);

  /// No description provided for @posPlateTitle.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Plate'**
  String get posPlateTitle;

  /// No description provided for @posPlateHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the car plate number'**
  String get posPlateHint;

  /// No description provided for @posMsgNoDeliveryProvidersTitle.
  ///
  /// In en, this message translates to:
  /// **'No Delivery Providers'**
  String get posMsgNoDeliveryProvidersTitle;

  /// No description provided for @posMsgNoDeliveryProvidersMessage.
  ///
  /// In en, this message translates to:
  /// **'No delivery providers are set up yet. Add them in the merchant portal.'**
  String get posMsgNoDeliveryProvidersMessage;

  /// No description provided for @posMsgCashPaymentCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash Payment Complete'**
  String get posMsgCashPaymentCompleteTitle;

  /// No description provided for @posMsgPaymentApprovedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Approved'**
  String get posMsgPaymentApprovedTitle;

  /// No description provided for @posMsgSplitPaymentRecordedTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Payment Recorded'**
  String get posMsgSplitPaymentRecordedTitle;

  /// No description provided for @posMsgPaymentCanceledTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Canceled'**
  String get posMsgPaymentCanceledTitle;

  /// No description provided for @posMsgPaymentFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Failed'**
  String get posMsgPaymentFailedTitle;

  /// No description provided for @posMsgPaymentUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Update'**
  String get posMsgPaymentUpdateTitle;

  /// No description provided for @posDiningTablePaidTitle.
  ///
  /// In en, this message translates to:
  /// **'{table} Paid'**
  String posDiningTablePaidTitle(String table);

  /// No description provided for @posDiningTicketPaidMessage.
  ///
  /// In en, this message translates to:
  /// **'Ticket #{ticket} was paid successfully. Clear the table when it is ready for the next guest.'**
  String posDiningTicketPaidMessage(String ticket);

  /// No description provided for @posDiningPaidTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid Total'**
  String get posDiningPaidTotalLabel;

  /// No description provided for @posDiningFloorLabel.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get posDiningFloorLabel;

  /// No description provided for @posDiningClearTableButton.
  ///
  /// In en, this message translates to:
  /// **'Clear Table'**
  String get posDiningClearTableButton;

  /// No description provided for @posDiningTableClearedTitle.
  ///
  /// In en, this message translates to:
  /// **'{table} Cleared'**
  String posDiningTableClearedTitle(String table);

  /// No description provided for @posDiningTableClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'{table} is now available for the next guest.'**
  String posDiningTableClearedMessage(String table);

  /// No description provided for @posDiscountSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply a discount'**
  String get posDiscountSheetTitle;

  /// No description provided for @posDiscountRedeemPointsOption.
  ///
  /// In en, this message translates to:
  /// **'Redeem loyalty points'**
  String get posDiscountRedeemPointsOption;

  /// No description provided for @posDiscountRedeemPointsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point available} other{{count} points available}}  ·  {rule}'**
  String posDiscountRedeemPointsSubtitle(int count, String rule);

  /// No description provided for @posDiscountRedeemStampOption.
  ///
  /// In en, this message translates to:
  /// **'Redeem stamp reward'**
  String get posDiscountRedeemStampOption;

  /// No description provided for @posDiscountStampRewardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stamp} other{{count} stamps}} → {amount} off  ·  {rule}'**
  String posDiscountStampRewardSubtitle(int count, String amount, String rule);

  /// No description provided for @posDiscountManagerApprovalTag.
  ///
  /// In en, this message translates to:
  /// **'manager approval'**
  String get posDiscountManagerApprovalTag;

  /// No description provided for @posDiscountCustomAmountOption.
  ///
  /// In en, this message translates to:
  /// **'Custom amount'**
  String get posDiscountCustomAmountOption;

  /// No description provided for @posDiscountRemoveOption.
  ///
  /// In en, this message translates to:
  /// **'Remove discount'**
  String get posDiscountRemoveOption;

  /// No description provided for @posDiscountClearedTitle.
  ///
  /// In en, this message translates to:
  /// **'Discount Cleared'**
  String get posDiscountClearedTitle;

  /// No description provided for @posDiscountClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'The order discount has been removed.'**
  String get posDiscountClearedMessage;

  /// No description provided for @posDiscountPercentOff.
  ///
  /// In en, this message translates to:
  /// **'{percent}% off'**
  String posDiscountPercentOff(String percent);

  /// No description provided for @posDiscountAmountOff.
  ///
  /// In en, this message translates to:
  /// **'{amount} off'**
  String posDiscountAmountOff(String amount);

  /// No description provided for @posDiscountApproveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Approve discount'**
  String get posDiscountApproveSubtitle;

  /// No description provided for @posDiscountApproveDescription.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to approve \"{name}\".'**
  String posDiscountApproveDescription(String name);

  /// No description provided for @posDiscountApprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval Required'**
  String get posDiscountApprovalRequiredTitle;

  /// No description provided for @posDiscountApprovalDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Manager approval was not granted for \"{name}\".'**
  String posDiscountApprovalDeniedMessage(String name);

  /// No description provided for @posDiscountAppliedTitle.
  ///
  /// In en, this message translates to:
  /// **'Discount Applied'**
  String get posDiscountAppliedTitle;

  /// No description provided for @posDiscountAppliedMessage.
  ///
  /// In en, this message translates to:
  /// **'{name} is now active.'**
  String posDiscountAppliedMessage(String name);

  /// No description provided for @posDiscountDefaultLabel.
  ///
  /// In en, this message translates to:
  /// **'Order discount'**
  String get posDiscountDefaultLabel;

  /// No description provided for @posSplitInProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Payment In Progress'**
  String get posSplitInProgressTitle;

  /// No description provided for @posSplitInProgressMessage.
  ///
  /// In en, this message translates to:
  /// **'Finish all split payments before changing the guest count.'**
  String get posSplitInProgressMessage;

  /// No description provided for @posSplitClearedTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Bill Cleared'**
  String get posSplitClearedTitle;

  /// No description provided for @posSplitClearedMessage.
  ///
  /// In en, this message translates to:
  /// **'The order is back to a single payment.'**
  String get posSplitClearedMessage;

  /// No description provided for @posSplitReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Bill Ready'**
  String get posSplitReadyTitle;

  /// No description provided for @posSplitReadyMessage.
  ///
  /// In en, this message translates to:
  /// **'The order is split into {count, plural, =1{1 share} other{{count} shares}} of {amount} each.'**
  String posSplitReadyMessage(int count, String amount);

  /// No description provided for @posCharityConfirmRoundUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Charity Round-Up'**
  String get posCharityConfirmRoundUpTitle;

  /// No description provided for @posCharityConfirmRoundUpBody.
  ///
  /// In en, this message translates to:
  /// **'Choose whether to add the optional charity donation before the payment terminal opens. The customer display will show the same totals.'**
  String get posCharityConfirmRoundUpBody;

  /// No description provided for @posCharityOrderTotal.
  ///
  /// In en, this message translates to:
  /// **'Order Total'**
  String get posCharityOrderTotal;

  /// No description provided for @posCharityRoundUp.
  ///
  /// In en, this message translates to:
  /// **'Round Up'**
  String get posCharityRoundUp;

  /// No description provided for @posCharityNewTotal.
  ///
  /// In en, this message translates to:
  /// **'New Total'**
  String get posCharityNewTotal;

  /// No description provided for @posCharityKeepOriginalTotal.
  ///
  /// In en, this message translates to:
  /// **'No, keep original total'**
  String get posCharityKeepOriginalTotal;

  /// No description provided for @posCharityRoundUpYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, round up for charity'**
  String get posCharityRoundUpYes;

  /// No description provided for @posReconCardNotConfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Card charge not confirmed'**
  String get posReconCardNotConfirmedTitle;

  /// No description provided for @posReconCardNotConfirmedBody.
  ///
  /// In en, this message translates to:
  /// **'The terminal did not confirm the {amount} card charge (e.g. an NFC timeout).\n\nIf the customer was charged, record it as PENDING RECONCILIATION — it will be matched against the bank settlement file. Otherwise cancel and try the charge again.'**
  String posReconCardNotConfirmedBody(String amount);

  /// No description provided for @posReconCancelRetry.
  ///
  /// In en, this message translates to:
  /// **'Cancel — retry charge'**
  String get posReconCancelRetry;

  /// No description provided for @posReconMarkPaidPending.
  ///
  /// In en, this message translates to:
  /// **'Mark paid — pending reconciliation'**
  String get posReconMarkPaidPending;

  /// No description provided for @posPaymentPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing Payment'**
  String get posPaymentPreparingTitle;

  /// No description provided for @posPaymentPreparingMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait while the payment terminal opens.'**
  String get posPaymentPreparingMessage;

  /// No description provided for @posPaymentSecureCardBadge.
  ///
  /// In en, this message translates to:
  /// **'SECURE CARD PAYMENT'**
  String get posPaymentSecureCardBadge;

  /// No description provided for @posPaymentRecordingCashTitle.
  ///
  /// In en, this message translates to:
  /// **'Recording Cash Payment'**
  String get posPaymentRecordingCashTitle;

  /// No description provided for @posPaymentRecordingCashMessage.
  ///
  /// In en, this message translates to:
  /// **'Please wait while the cash payment is completed.'**
  String get posPaymentRecordingCashMessage;

  /// No description provided for @posPaymentCashCheckoutBadge.
  ///
  /// In en, this message translates to:
  /// **'CASH CHECKOUT'**
  String get posPaymentCashCheckoutBadge;

  /// No description provided for @posPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get posPaymentTitle;

  /// No description provided for @posPaymentNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New Order'**
  String get posPaymentNewOrder;

  /// No description provided for @posPaymentOrderRef.
  ///
  /// In en, this message translates to:
  /// **'Ref {reference}'**
  String posPaymentOrderRef(String reference);

  /// No description provided for @posPaymentTableChip.
  ///
  /// In en, this message translates to:
  /// **'Table {table}'**
  String posPaymentTableChip(String table);

  /// No description provided for @posPaymentOrderItems.
  ///
  /// In en, this message translates to:
  /// **'Order Items'**
  String get posPaymentOrderItems;

  /// No description provided for @posPaymentSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posPaymentSubtotal;

  /// No description provided for @posPaymentDiscountFallback.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posPaymentDiscountFallback;

  /// No description provided for @posPaymentNetSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Net Subtotal'**
  String get posPaymentNetSubtotal;

  /// No description provided for @posPaymentCompRow.
  ///
  /// In en, this message translates to:
  /// **'Comp · {reason}'**
  String posPaymentCompRow(String reason);

  /// No description provided for @posPaymentTaxLine.
  ///
  /// In en, this message translates to:
  /// **'{name} ({rate}%)'**
  String posPaymentTaxLine(String name, String rate);

  /// No description provided for @posPaymentGuestShareRow.
  ///
  /// In en, this message translates to:
  /// **'Guest {n} Share'**
  String posPaymentGuestShareRow(int n);

  /// No description provided for @posPaymentShareDue.
  ///
  /// In en, this message translates to:
  /// **'Share Due'**
  String get posPaymentShareDue;

  /// No description provided for @posPaymentTotalDue.
  ///
  /// In en, this message translates to:
  /// **'Total Due'**
  String get posPaymentTotalDue;

  /// No description provided for @posPaymentCustomerNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer Number (Optional)'**
  String get posPaymentCustomerNumberLabel;

  /// No description provided for @posPaymentCustomerNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Add a customer number for reference'**
  String get posPaymentCustomerNumberHint;

  /// No description provided for @posPaymentVehiclePlateLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle Plate (Optional)'**
  String get posPaymentVehiclePlateLabel;

  /// No description provided for @posPaymentVehiclePlateHint.
  ///
  /// In en, this message translates to:
  /// **'Add a vehicle plate for drive-thru'**
  String get posPaymentVehiclePlateHint;

  /// No description provided for @posPaymentDeliveryProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Delivery Provider'**
  String get posPaymentDeliveryProviderLabel;

  /// No description provided for @posPaymentDeliveryProviderHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a delivery provider'**
  String get posPaymentDeliveryProviderHint;

  /// No description provided for @posPaymentRedeemLoyalty.
  ///
  /// In en, this message translates to:
  /// **'Redeem Loyalty'**
  String get posPaymentRedeemLoyalty;

  /// No description provided for @posPaymentAddDiscount.
  ///
  /// In en, this message translates to:
  /// **'Add Discount'**
  String get posPaymentAddDiscount;

  /// No description provided for @posPaymentSplitBill.
  ///
  /// In en, this message translates to:
  /// **'Split Bill'**
  String get posPaymentSplitBill;

  /// No description provided for @posPaymentComp.
  ///
  /// In en, this message translates to:
  /// **'Comp'**
  String get posPaymentComp;

  /// No description provided for @posPaymentCompApplied.
  ///
  /// In en, this message translates to:
  /// **'Comp ✓'**
  String get posPaymentCompApplied;

  /// No description provided for @posPaymentTendered.
  ///
  /// In en, this message translates to:
  /// **'Tendered'**
  String get posPaymentTendered;

  /// No description provided for @posPaymentCardBalance.
  ///
  /// In en, this message translates to:
  /// **'Card Balance'**
  String get posPaymentCardBalance;

  /// No description provided for @posPaymentChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get posPaymentChange;

  /// No description provided for @posPaymentQuickCash.
  ///
  /// In en, this message translates to:
  /// **'{amount} OMR'**
  String posPaymentQuickCash(int amount);

  /// No description provided for @posPaymentCollectingGuest.
  ///
  /// In en, this message translates to:
  /// **'Collecting guest {n} of {total}: {amount}.'**
  String posPaymentCollectingGuest(int n, int total, String amount);

  /// No description provided for @posPaymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get posPaymentCash;

  /// No description provided for @posPaymentCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get posPaymentCard;

  /// No description provided for @posPaymentSplitPayment.
  ///
  /// In en, this message translates to:
  /// **'Split\nPayment'**
  String get posPaymentSplitPayment;

  /// No description provided for @posNavHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get posNavHome;

  /// No description provided for @posNavReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get posNavReport;

  /// No description provided for @posNavHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get posNavHistory;

  /// No description provided for @posNavReportsComingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports Coming Next'**
  String get posNavReportsComingTitle;

  /// No description provided for @posNavReportsComingBody.
  ///
  /// In en, this message translates to:
  /// **'We will connect detailed reporting once the local order archive is fully connected to the database flow.'**
  String get posNavReportsComingBody;

  /// No description provided for @posNavAlreadyHomeBody.
  ///
  /// In en, this message translates to:
  /// **'You are already on the main POS screen.'**
  String get posNavAlreadyHomeBody;

  /// No description provided for @posNavBrandTagline.
  ///
  /// In en, this message translates to:
  /// **'Better ordering'**
  String get posNavBrandTagline;

  /// No description provided for @posNavStaffFallback.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get posNavStaffFallback;

  /// No description provided for @posNavOrderHistory.
  ///
  /// In en, this message translates to:
  /// **'Order History'**
  String get posNavOrderHistory;

  /// No description provided for @posNavHeldOrders.
  ///
  /// In en, this message translates to:
  /// **'Held Orders'**
  String get posNavHeldOrders;

  /// No description provided for @posNavLoyalty.
  ///
  /// In en, this message translates to:
  /// **'Loyalty'**
  String get posNavLoyalty;

  /// No description provided for @posNavReceiptPrintedTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt Printed'**
  String get posNavReceiptPrintedTitle;

  /// No description provided for @posNavReceiptPrintedBody.
  ///
  /// In en, this message translates to:
  /// **'The current order receipt was sent to the printer.'**
  String get posNavReceiptPrintedBody;

  /// No description provided for @posMenuCloseShift.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get posMenuCloseShift;

  /// No description provided for @posMenuCloseShiftSub.
  ///
  /// In en, this message translates to:
  /// **'Count the drawer and reconcile cash'**
  String get posMenuCloseShiftSub;

  /// No description provided for @posMenuLogExpense.
  ///
  /// In en, this message translates to:
  /// **'Log expense'**
  String get posMenuLogExpense;

  /// No description provided for @posMenuLogExpenseSub.
  ///
  /// In en, this message translates to:
  /// **'Record a petty-cash expense'**
  String get posMenuLogExpenseSub;

  /// No description provided for @posMenuRequestRestock.
  ///
  /// In en, this message translates to:
  /// **'Request restock'**
  String get posMenuRequestRestock;

  /// No description provided for @posMenuRequestRestockSub.
  ///
  /// In en, this message translates to:
  /// **'Ask the branch to restock ingredients'**
  String get posMenuRequestRestockSub;

  /// No description provided for @posMenuStockCount.
  ///
  /// In en, this message translates to:
  /// **'Day-end stock count'**
  String get posMenuStockCount;

  /// No description provided for @posMenuStockCountSub.
  ///
  /// In en, this message translates to:
  /// **'Count the shelf and reconcile variances'**
  String get posMenuStockCountSub;

  /// No description provided for @posMenuShiftSummary.
  ///
  /// In en, this message translates to:
  /// **'Shift summary (Z-report)'**
  String get posMenuShiftSummary;

  /// No description provided for @posMenuShiftSummarySub.
  ///
  /// In en, this message translates to:
  /// **'Reprint the last closed shift — manager only'**
  String get posMenuShiftSummarySub;

  /// No description provided for @posMenuSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get posMenuSettings;

  /// No description provided for @posMenuSettingsSub.
  ///
  /// In en, this message translates to:
  /// **'Server address, printing'**
  String get posMenuSettingsSub;

  /// No description provided for @posMenuLogoutSub.
  ///
  /// In en, this message translates to:
  /// **'Return to the staff PIN screen'**
  String get posMenuLogoutSub;

  /// No description provided for @posMenuNoShiftSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'No Shift Summary Yet'**
  String get posMenuNoShiftSummaryTitle;

  /// No description provided for @posMenuNoShiftSummaryBody.
  ///
  /// In en, this message translates to:
  /// **'Close a shift first — its summary is kept for reprinting.'**
  String get posMenuNoShiftSummaryBody;

  /// No description provided for @posMenuShiftSummaryShort.
  ///
  /// In en, this message translates to:
  /// **'Shift summary'**
  String get posMenuShiftSummaryShort;

  /// No description provided for @posMenuShiftSummaryAuthDesc.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to reprint the last shift summary.'**
  String get posMenuShiftSummaryAuthDesc;

  /// No description provided for @posMenuApprovalRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Approval Required'**
  String get posMenuApprovalRequiredTitle;

  /// No description provided for @posMenuApprovalNotGrantedBody.
  ///
  /// In en, this message translates to:
  /// **'Manager approval was not granted for the shift summary.'**
  String get posMenuApprovalNotGrantedBody;

  /// No description provided for @posMenuShiftSummaryPrintedTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift Summary Printed'**
  String get posMenuShiftSummaryPrintedTitle;

  /// No description provided for @posMenuShiftSummaryPrintedBody.
  ///
  /// In en, this message translates to:
  /// **'The last shift summary was sent to the printer.'**
  String get posMenuShiftSummaryPrintedBody;

  /// No description provided for @posMenuLogoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get posMenuLogoutConfirmTitle;

  /// No description provided for @posMenuLogoutConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'You will return to the staff PIN screen. The device stays set up.'**
  String get posMenuLogoutConfirmBody;

  /// No description provided for @posOrderPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Current Order'**
  String get posOrderPanelTitle;

  /// No description provided for @posOrderPanelNewOrder.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get posOrderPanelNewOrder;

  /// No description provided for @posOrderPanelRef.
  ///
  /// In en, this message translates to:
  /// **'Ref {reference}'**
  String posOrderPanelRef(String reference);

  /// No description provided for @posOrderPanelTableChip.
  ///
  /// In en, this message translates to:
  /// **'Table {table}'**
  String posOrderPanelTableChip(String table);

  /// No description provided for @posOrderPanelFloorPlan.
  ///
  /// In en, this message translates to:
  /// **'Floor Plan'**
  String get posOrderPanelFloorPlan;

  /// No description provided for @posOrderPanelClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get posOrderPanelClear;

  /// No description provided for @posOrderPanelSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posOrderPanelSubtotal;

  /// No description provided for @posOrderPanelDiscount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posOrderPanelDiscount;

  /// No description provided for @posOrderPanelNetSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Net Subtotal'**
  String get posOrderPanelNetSubtotal;

  /// No description provided for @posOrderPanelComp.
  ///
  /// In en, this message translates to:
  /// **'Comp · {reason}'**
  String posOrderPanelComp(String reason);

  /// No description provided for @posOrderPanelPerShare.
  ///
  /// In en, this message translates to:
  /// **'Per Share ({count})'**
  String posOrderPanelPerShare(int count);

  /// No description provided for @posOrderPanelTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posOrderPanelTotal;

  /// No description provided for @posOrderPanelBackToFloor.
  ///
  /// In en, this message translates to:
  /// **'Back To Floor'**
  String get posOrderPanelBackToFloor;

  /// No description provided for @posOrderPanelHold.
  ///
  /// In en, this message translates to:
  /// **'Hold'**
  String get posOrderPanelHold;

  /// No description provided for @posOrderPanelClearTable.
  ///
  /// In en, this message translates to:
  /// **'Clear Table'**
  String get posOrderPanelClearTable;

  /// No description provided for @posOrderPanelVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get posOrderPanelVoid;

  /// No description provided for @posCatalogCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get posCatalogCategories;

  /// No description provided for @posCatalogProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get posCatalogProducts;

  /// No description provided for @posCatalogFavourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get posCatalogFavourites;

  /// No description provided for @posCatalogFavouritesComingTitle.
  ///
  /// In en, this message translates to:
  /// **'Favourites Coming Next'**
  String get posCatalogFavouritesComingTitle;

  /// No description provided for @posCatalogFavouritesComingBody.
  ///
  /// In en, this message translates to:
  /// **'We will wire favourite products to the local database in the next pass.'**
  String get posCatalogFavouritesComingBody;

  /// No description provided for @posCatalogSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get posCatalogSearchHint;

  /// No description provided for @posCatalogViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get posCatalogViewList;

  /// No description provided for @posCatalogViewGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get posCatalogViewGrid;

  /// No description provided for @posClockAm.
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get posClockAm;

  /// No description provided for @posClockPm.
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get posClockPm;

  /// No description provided for @posClockMonthJan.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get posClockMonthJan;

  /// No description provided for @posClockMonthFeb.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get posClockMonthFeb;

  /// No description provided for @posClockMonthMar.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get posClockMonthMar;

  /// No description provided for @posClockMonthApr.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get posClockMonthApr;

  /// No description provided for @posClockMonthMay.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get posClockMonthMay;

  /// No description provided for @posClockMonthJun.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get posClockMonthJun;

  /// No description provided for @posClockMonthJul.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get posClockMonthJul;

  /// No description provided for @posClockMonthAug.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get posClockMonthAug;

  /// No description provided for @posClockMonthSep.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get posClockMonthSep;

  /// No description provided for @posClockMonthOct.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get posClockMonthOct;

  /// No description provided for @posClockMonthNov.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get posClockMonthNov;

  /// No description provided for @posClockMonthDec.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get posClockMonthDec;

  /// No description provided for @posClockDate.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}, {year}'**
  String posClockDate(String month, int day, int year);

  /// No description provided for @posCartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Tap any product to start the order'**
  String get posCartEmptyTitle;

  /// No description provided for @posCartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'The cart, actions, and totals will appear here.'**
  String get posCartEmptySubtitle;

  /// No description provided for @posCartAddOn.
  ///
  /// In en, this message translates to:
  /// **'Add On'**
  String get posCartAddOn;

  /// No description provided for @posCartQtyTimesName.
  ///
  /// In en, this message translates to:
  /// **'{qty}x {name}'**
  String posCartQtyTimesName(int qty, String name);

  /// No description provided for @posCartQtyTimesPrice.
  ///
  /// In en, this message translates to:
  /// **'{qty} x {price}'**
  String posCartQtyTimesPrice(int qty, String price);

  /// No description provided for @posCustomizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Customize {name}'**
  String posCustomizeTitle(String name);

  /// No description provided for @posCustomizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select add-ons and leave notes for this order line.'**
  String get posCustomizeSubtitle;

  /// No description provided for @posCustomizeNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get posCustomizeNotesLabel;

  /// No description provided for @posCustomizeNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Add preparation notes for the kitchen or cashier'**
  String get posCustomizeNotesHint;

  /// No description provided for @posCustomizeApply.
  ///
  /// In en, this message translates to:
  /// **'Apply {amount}'**
  String posCustomizeApply(String amount);

  /// No description provided for @posProductsEmptySearchTitle.
  ///
  /// In en, this message translates to:
  /// **'No products match your search.'**
  String get posProductsEmptySearchTitle;

  /// No description provided for @posProductsEmptyCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'No products available here yet.'**
  String get posProductsEmptyCategoryTitle;

  /// No description provided for @posProductsEmptySearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Try another product name or clear the current search.'**
  String get posProductsEmptySearchSubtitle;

  /// No description provided for @posProductsEmptyCategorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose another category or add products to this category later.'**
  String get posProductsEmptyCategorySubtitle;

  /// No description provided for @posProductsClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear Search'**
  String get posProductsClearSearch;

  /// No description provided for @posProductSoldOutBadge.
  ///
  /// In en, this message translates to:
  /// **'SOLD OUT'**
  String get posProductSoldOutBadge;

  /// No description provided for @posProductLowStockBadge.
  ///
  /// In en, this message translates to:
  /// **'LOW STOCK'**
  String get posProductLowStockBadge;

  /// No description provided for @posProductAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get posProductAdd;

  /// No description provided for @posPayBtnProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing Payment'**
  String get posPayBtnProcessing;

  /// No description provided for @posPayBtnProcessToPay.
  ///
  /// In en, this message translates to:
  /// **'Process to Pay'**
  String get posPayBtnProcessToPay;

  /// No description provided for @posPayBtnCompletingOrder.
  ///
  /// In en, this message translates to:
  /// **'Completing order'**
  String get posPayBtnCompletingOrder;

  /// No description provided for @posPayBtnPayAmount.
  ///
  /// In en, this message translates to:
  /// **'PAY {amount}'**
  String posPayBtnPayAmount(String amount);

  /// No description provided for @posDiningTicketNumber.
  ///
  /// In en, this message translates to:
  /// **'Ticket #{number}'**
  String posDiningTicketNumber(String number);

  /// No description provided for @posDiningRefNumber.
  ///
  /// In en, this message translates to:
  /// **'Ref {reference}'**
  String posDiningRefNumber(String reference);

  /// No description provided for @posDiningSeats.
  ///
  /// In en, this message translates to:
  /// **'Seats {count}'**
  String posDiningSeats(int count);

  /// No description provided for @posDiningStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE'**
  String get posDiningStatusAvailable;

  /// No description provided for @posDiningStatusOccupied.
  ///
  /// In en, this message translates to:
  /// **'OCCUPIED'**
  String get posDiningStatusOccupied;

  /// No description provided for @posDiningStatusPaidClear.
  ///
  /// In en, this message translates to:
  /// **'PAID / CLEAR'**
  String get posDiningStatusPaidClear;

  /// No description provided for @posStorageHeldEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No held orders yet'**
  String get posStorageHeldEmptyTitle;

  /// No description provided for @posStorageHeldEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Any order you place on hold will appear here so the staff can continue it later.'**
  String get posStorageHeldEmptyMessage;

  /// No description provided for @posStorageHistoryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No completed orders yet'**
  String get posStorageHistoryEmptyTitle;

  /// No description provided for @posStorageHistoryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Completed payments will be archived here so the staff can review them or print receipts again.'**
  String get posStorageHistoryEmptyMessage;

  /// No description provided for @posFingerprintBannerTitle.
  ///
  /// In en, this message translates to:
  /// **'Manager cancellation approval'**
  String get posFingerprintBannerTitle;

  /// No description provided for @posFingerprintBannerMessage.
  ///
  /// In en, this message translates to:
  /// **'Register once, then use fingerprint approval before opening completed order cancellation.'**
  String get posFingerprintBannerMessage;

  /// No description provided for @posFingerprintRegisterManager.
  ///
  /// In en, this message translates to:
  /// **'Register Manager'**
  String get posFingerprintRegisterManager;

  /// No description provided for @posFingerprintWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for fingerprint'**
  String get posFingerprintWaiting;

  /// No description provided for @posStorageHeldRef.
  ///
  /// In en, this message translates to:
  /// **'Ref {ref}'**
  String posStorageHeldRef(String ref);

  /// No description provided for @posStorageItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String posStorageItemsCount(int count);

  /// No description provided for @posStorageSplitBadge.
  ///
  /// In en, this message translates to:
  /// **'Split {n}'**
  String posStorageSplitBadge(int n);

  /// No description provided for @posStorageItemQtyName.
  ///
  /// In en, this message translates to:
  /// **'{qty}x {name}'**
  String posStorageItemQtyName(int qty, String name);

  /// No description provided for @posStorageContinueOrder.
  ///
  /// In en, this message translates to:
  /// **'Continue Order'**
  String get posStorageContinueOrder;

  /// No description provided for @posStorageDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get posStorageDiscard;

  /// No description provided for @posStorageOrderNumber.
  ///
  /// In en, this message translates to:
  /// **'Order #{n}'**
  String posStorageOrderNumber(int n);

  /// No description provided for @posStorageSplitsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 split} other{{count} splits}}'**
  String posStorageSplitsCount(int count);

  /// No description provided for @posStorageCanceledAmount.
  ///
  /// In en, this message translates to:
  /// **'Canceled {amount}'**
  String posStorageCanceledAmount(String amount);

  /// No description provided for @posStorageKitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get posStorageKitchen;

  /// No description provided for @posStorageCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get posStorageCanceled;

  /// No description provided for @posCancelPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order #{n}'**
  String posCancelPageTitle(int n);

  /// No description provided for @posCancelPageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manager approved. Cancel the full order or select the completed items to cancel.'**
  String get posCancelPageSubtitle;

  /// No description provided for @posCancelPageReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Pick a cancellation reason first.'**
  String get posCancelPageReasonRequired;

  /// No description provided for @posCancelPageOrderItems.
  ///
  /// In en, this message translates to:
  /// **'Order Items'**
  String get posCancelPageOrderItems;

  /// No description provided for @posCancelPageCancellableCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cancellable'**
  String posCancelPageCancellableCount(int count);

  /// No description provided for @posCancelPageSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get posCancelPageSaving;

  /// No description provided for @posCancelPageCancelSelected.
  ///
  /// In en, this message translates to:
  /// **'Cancel Selected ({count})'**
  String posCancelPageCancelSelected(int count);

  /// No description provided for @posCancelPageCancelFullOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Full Order'**
  String get posCancelPageCancelFullOrder;

  /// No description provided for @posCancelPageOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get posCancelPageOrderSummary;

  /// No description provided for @posCancelPagePaidTotal.
  ///
  /// In en, this message translates to:
  /// **'Paid total'**
  String get posCancelPagePaidTotal;

  /// No description provided for @posCancelPageCanceledMetric.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get posCancelPageCanceledMetric;

  /// No description provided for @posCancelPagePaymentMetric.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get posCancelPagePaymentMetric;

  /// No description provided for @posCancelPageCancellationLog.
  ///
  /// In en, this message translates to:
  /// **'Cancellation Log'**
  String get posCancelPageCancellationLog;

  /// No description provided for @posCancelPageNoCancellations.
  ///
  /// In en, this message translates to:
  /// **'No cancellations recorded.'**
  String get posCancelPageNoCancellations;

  /// No description provided for @posCancelPageItemFallback.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get posCancelPageItemFallback;

  /// No description provided for @posCancelPageItemQtyName.
  ///
  /// In en, this message translates to:
  /// **'{qty} x {name}'**
  String posCancelPageItemQtyName(int qty, String name);

  /// No description provided for @posDeliveryPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Delivery Provider'**
  String get posDeliveryPickerTitle;

  /// No description provided for @posDeliveryPickerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Product prices update to the selected provider.'**
  String get posDeliveryPickerSubtitle;

  /// No description provided for @posKeyboardSpace.
  ///
  /// In en, this message translates to:
  /// **'SPACE'**
  String get posKeyboardSpace;

  /// No description provided for @posKeyboardClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get posKeyboardClear;

  /// No description provided for @posKeyboardBackspace.
  ///
  /// In en, this message translates to:
  /// **'Backspace'**
  String get posKeyboardBackspace;

  /// No description provided for @posCustomerSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search failed. Check the connection.'**
  String get posCustomerSearchFailed;

  /// No description provided for @posCustomerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Name, phone, or plate'**
  String get posCustomerSearchHint;

  /// No description provided for @posCustomerSearchButton.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get posCustomerSearchButton;

  /// No description provided for @posCustomerSearchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No customers found.'**
  String get posCustomerSearchNoResults;

  /// No description provided for @posCustomerSearchPoints.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point} other{{count} points}}'**
  String posCustomerSearchPoints(int count);

  /// No description provided for @posRedeemTitle.
  ///
  /// In en, this message translates to:
  /// **'Redeem points'**
  String get posRedeemTitle;

  /// No description provided for @posRedeemPerBlock.
  ///
  /// In en, this message translates to:
  /// **'{points} points = {value} per block'**
  String posRedeemPerBlock(int points, String value);

  /// No description provided for @posRedeemSummary.
  ///
  /// In en, this message translates to:
  /// **'{points} points  →  {value} off'**
  String posRedeemSummary(int points, String value);

  /// No description provided for @posRedeemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get posRedeemConfirm;

  /// No description provided for @posDiscountDlgTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Discount'**
  String get posDiscountDlgTitle;

  /// No description provided for @posDiscountDlgPercentageSection.
  ///
  /// In en, this message translates to:
  /// **'Percentage Discounts'**
  String get posDiscountDlgPercentageSection;

  /// No description provided for @posDiscountDlgFixedSection.
  ///
  /// In en, this message translates to:
  /// **'Fixed Discounts'**
  String get posDiscountDlgFixedSection;

  /// No description provided for @posDiscountDlgClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Discount'**
  String get posDiscountDlgClear;

  /// No description provided for @posDiscountDlgApply.
  ///
  /// In en, this message translates to:
  /// **'Apply {label}'**
  String posDiscountDlgApply(String label);

  /// No description provided for @posSplitDlgTitle.
  ///
  /// In en, this message translates to:
  /// **'Split Bill'**
  String get posSplitDlgTitle;

  /// No description provided for @posSplitDlgSingleBill.
  ///
  /// In en, this message translates to:
  /// **'Single Bill'**
  String get posSplitDlgSingleBill;

  /// No description provided for @posSplitDlgGuests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Guest} other{{count} Guests}}'**
  String posSplitDlgGuests(int count);

  /// No description provided for @posSplitDlgEachGuestPays.
  ///
  /// In en, this message translates to:
  /// **'Each guest pays'**
  String get posSplitDlgEachGuestPays;

  /// No description provided for @posSplitDlgSinglePaymentTotal.
  ///
  /// In en, this message translates to:
  /// **'Single payment total'**
  String get posSplitDlgSinglePaymentTotal;

  /// No description provided for @posSplitDlgApplySplit.
  ///
  /// In en, this message translates to:
  /// **'Apply Split'**
  String get posSplitDlgApplySplit;

  /// No description provided for @posSplitDlgUseSingleBill.
  ///
  /// In en, this message translates to:
  /// **'Use Single Bill'**
  String get posSplitDlgUseSingleBill;

  /// No description provided for @displayMethodCardShort.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get displayMethodCardShort;

  /// No description provided for @displayMethodGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get displayMethodGift;

  /// No description provided for @ctrlMsgGiftRecorded.
  ///
  /// In en, this message translates to:
  /// **'Gift order recorded — nothing charged.'**
  String get ctrlMsgGiftRecorded;

  /// No description provided for @ctrlMsgGiftCompleted.
  ///
  /// In en, this message translates to:
  /// **'This order is our gift. Thank you!'**
  String get ctrlMsgGiftCompleted;

  /// No description provided for @posPaymentGift.
  ///
  /// In en, this message translates to:
  /// **'Gift'**
  String get posPaymentGift;

  /// No description provided for @posPayGiftConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Gift This Order?'**
  String get posPayGiftConfirmTitle;

  /// No description provided for @posPayGiftConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The whole order ({amount} OMR) will be gifted — nothing is charged to the customer. Inventory still deducts.'**
  String posPayGiftConfirmMessage(String amount);

  /// No description provided for @posPayGiftRegisterManagerMessage.
  ///
  /// In en, this message translates to:
  /// **'Register the manager fingerprint once before gifting an order.'**
  String get posPayGiftRegisterManagerMessage;

  /// No description provided for @posPayGiftManagerApprovalMessage.
  ///
  /// In en, this message translates to:
  /// **'Place the manager fingerprint to gift this order.'**
  String get posPayGiftManagerApprovalMessage;

  /// No description provided for @posPayGiftDeniedMessage.
  ///
  /// In en, this message translates to:
  /// **'Manager approval was not granted for the gift.'**
  String get posPayGiftDeniedMessage;
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
