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
  String get settingsSectionOperations => 'Operations';

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

  @override
  String get displayOrderTypeQuickOrder => 'Quick Order';

  @override
  String get displayOrderTypeToGo => 'To Go';

  @override
  String get displayOrderTypeDelivery => 'Delivery';

  @override
  String get displayOrderTypeDineIn => 'Dine In';

  @override
  String get displayStatusWaiting => 'Waiting';

  @override
  String get displayStatusPaid => 'Paid';

  @override
  String get displayStatusPaidPendingRecon => 'Paid (pending reconciliation)';

  @override
  String get displayStatusAwaitingConfirmation => 'Awaiting confirmation';

  @override
  String get displayStatusCardNotConfirmed => 'Card charge not confirmed';

  @override
  String get displayStatusPaymentCanceled => 'Payment canceled';

  @override
  String get displayStatusPreparingPayment => 'Preparing payment';

  @override
  String get displayStatusProcessingPayment => 'Processing payment';

  @override
  String get displayStatusSplitPending => 'Split payment pending';

  @override
  String get displayStatusCanceled => 'Canceled';

  @override
  String get displayStatusPartiallyCanceled => 'Partially Canceled';

  @override
  String get displayStatusVoid => 'Void';

  @override
  String get displayStatusRefunded => 'Refunded';

  @override
  String get displayMethodCash => 'Cash';

  @override
  String get displayMethodCard => 'Credit Card';

  @override
  String get displayMethodSplit => 'Split Payment';

  @override
  String get cdProcessingSelectionTitle => 'Processing Selection';

  @override
  String get cdPreparingPaymentTitle => 'Preparing Payment';

  @override
  String get cdProcessingSelectionMessage =>
      'Please wait while we confirm your choice and open the payment terminal.';

  @override
  String get cdPreparingPaymentMessage =>
      'Please wait while the payment terminal is opening.';

  @override
  String get cdHeaderPaymentCompleted => 'Payment completed successfully';

  @override
  String get cdHeaderReviewCharity =>
      'Review the optional charity round-up before payment';

  @override
  String get cdHeaderItemsWillAppear => 'Your items and total will appear here';

  @override
  String cdHeaderItemLineCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count item lines in the current order',
      one: '1 item line in the current order',
    );
    return '$_temp0';
  }

  @override
  String cdHeaderTableItemLineCount(String table, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count item lines in the current order',
      one: '1 item line in the current order',
    );
    return 'Table $table | $_temp0';
  }

  @override
  String get cdHeroRoundUpForCharity => 'Round up for charity';

  @override
  String get cdHeroReadyForOrder => 'Ready for your order';

  @override
  String get cdHeroOrderTotal => 'Order total';

  @override
  String get cdHeroCharityNote =>
      'The extra rounded amount will be donated to charity.';

  @override
  String get cdHeroReviewNote =>
      'Please review your items and total before payment.';

  @override
  String get cdSubtotalLabel => 'Subtotal';

  @override
  String get cdTaxLabel => 'Tax';

  @override
  String get cdPaymentLabel => 'Payment';

  @override
  String get cdOrderDetailsTitle => 'Order Details';

  @override
  String get cdOrderDetailsSubtitle =>
      'Live order view for the customer-facing display';

  @override
  String get cdBannerThankYou =>
      'Thank you for your visit. Your order has been completed.';

  @override
  String get cdBannerReviewWhileCashier =>
      'Please review the order details while the cashier prepares payment.';

  @override
  String get cdTapToPayTitle => 'Tap Here To Pay';

  @override
  String get cdTapToPaySubtitle =>
      'Your payment is ready. Please tap your card or phone on the customer-facing NFC area.';

  @override
  String get cdContactlessReadyTitle => 'Ready for contactless payment';

  @override
  String get cdContactlessHoldHint =>
      'Hold the card, phone, or wearable near the rear NFC area until the terminal confirms the transaction.';

  @override
  String get cdChipCard => 'Card';

  @override
  String get cdChipPhone => 'Phone';

  @override
  String get cdChipWearable => 'Wearable';

  @override
  String get cdTotalToPay => 'Total to pay';

  @override
  String cdIncludesCharityRoundUp(String amount) {
    return 'Includes $amount charity round-up.';
  }

  @override
  String get cdPresentToContinue =>
      'Present your card, phone, or wearable to continue the payment.';

  @override
  String get cdTapFooterKeepNear =>
      'Keep the card or phone near the customer-facing NFC area until the terminal confirms the payment.';

  @override
  String get cdCharityTitle => 'Round Up For Charity?';

  @override
  String get cdCharityQuestion =>
      'Would you like to round your payment to the next whole OMR? Only the extra amount will be donated to charity.';

  @override
  String get cdCharityEncouragement =>
      'A small round-up can make a meaningful donation while keeping your payment simple.';

  @override
  String get cdCharityTileOrderTotal => 'Order Total';

  @override
  String get cdCharityTileOrderTotalCaption => 'Current order amount';

  @override
  String get cdCharityTileRoundUp => 'Round Up';

  @override
  String get cdCharityTileRoundUpCaption => 'Extra donation amount';

  @override
  String get cdCharityTileNewTotal => 'New Total';

  @override
  String get cdCharityTileNewTotalCaption => 'Final amount to pay';

  @override
  String get cdCharityNo => 'No';

  @override
  String get cdCharityNoSubtitleShort => 'Keep original total';

  @override
  String get cdCharityNoSubtitle => 'Pay the original order total';

  @override
  String get cdCharityYes => 'Yes';

  @override
  String get cdCharityYesSubtitleShort => 'Round up to donate';

  @override
  String get cdCharityYesSubtitle => 'Round up and donate the extra amount';

  @override
  String cdTouchOkCount(int count) {
    return 'Touch OK x$count';
  }

  @override
  String get cdTouchTestTitle => 'Touch Test';

  @override
  String get cdTouchTestHint => 'Tap here to verify';

  @override
  String cdTouchDetectedAt(String time, int count) {
    return 'Rear touch detected at $time (#$count)';
  }

  @override
  String get cdBadgeUpdatingChoice => 'UPDATING CHOICE';

  @override
  String get cdBadgeSecureCardPayment => 'SECURE CARD PAYMENT';

  @override
  String cdQuantity(int qty) {
    return 'Quantity: $qty';
  }

  @override
  String get cdNoItemsYet => 'No items yet';

  @override
  String get cdEmptyStateHint =>
      'The display will update as soon as the cashier adds products.';

  @override
  String get cdFinalBadge => 'FINAL';

  @override
  String get cdSummaryPaid => 'Thank you. Your payment has been completed.';

  @override
  String get cdSummaryAwaitingCashier =>
      'A cashier will confirm the order and complete payment when ready.';

  @override
  String get ctrlMsgChooseTableDineIn =>
      'Choose a table to start or continue a dine-in order.';

  @override
  String ctrlMsgEditingTableOnFloor(String table, String floor) {
    return 'Editing $table in $floor.';
  }

  @override
  String ctrlMsgAddItemsForTable(String table) {
    return 'Add items for $table.';
  }

  @override
  String ctrlMsgAssignItemsToTable(String table) {
    return 'Assigning the current items to $table.';
  }

  @override
  String get ctrlFloorFallbackDining => 'Dining';

  @override
  String ctrlMsgOrderHeld(String reference) {
    return 'Reference $reference was placed on hold.';
  }

  @override
  String get ctrlMsgHoldFailed => 'Unable to hold the order right now.';

  @override
  String ctrlMsgOrderResumed(String reference) {
    return 'Resumed held reference $reference.';
  }

  @override
  String ctrlMsgHeldOrderDiscarded(String reference) {
    return 'Held reference $reference was discarded.';
  }

  @override
  String ctrlMsgOrderAlreadyCanceled(int n) {
    return 'Order #$n is already fully canceled.';
  }

  @override
  String get ctrlMsgNoCancellableItems => 'No cancellable items were selected.';

  @override
  String get ctrlMsgOrderCanceledByManagerNote => 'Order canceled by manager.';

  @override
  String ctrlMsgItemsCanceledByManagerNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items canceled by manager.',
      one: '1 item canceled by manager.',
    );
    return '$_temp0';
  }

  @override
  String ctrlMsgOrderFullyCanceled(int n) {
    return 'Order #$n was fully canceled.';
  }

  @override
  String ctrlMsgItemsCanceledFromOrder(int count, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items canceled',
      one: '1 item canceled',
    );
    return '$_temp0 from order #$n.';
  }

  @override
  String ctrlMsgPaymentCanceledWithMethod(String method) {
    return '$method payment canceled.';
  }

  @override
  String get ctrlMsgCustomerResponseTimeout =>
      'Timed out waiting for the customer response.';

  @override
  String ctrlMsgTenderedCashTooLow(String amount) {
    return 'Tendered cash must be at least $amount.';
  }

  @override
  String ctrlMsgCashierCompletingSplitCash(int index, int total) {
    return 'The cashier is completing split bill cash payment $index of $total.';
  }

  @override
  String get ctrlMsgCashierCompletingCash =>
      'The cashier is completing a cash payment.';

  @override
  String get ctrlMsgCashPaymentRecorded =>
      'Cash payment recorded successfully.';

  @override
  String get ctrlMsgCashPaymentCompleted =>
      'Cash payment completed. Thank you.';

  @override
  String get ctrlMsgTapToPayRoundUp =>
      'Thank you for rounding up for charity. Tap your card or phone on the rear NFC area to pay.';

  @override
  String get ctrlMsgTapToPay =>
      'Tap your card or phone on the rear NFC area to pay.';

  @override
  String get ctrlMsgCardPendingReconRecorded =>
      'Card recorded as pending reconciliation. The bank settlement will confirm it.';

  @override
  String get ctrlMsgPaymentPendingBankThanks =>
      'Payment recorded pending bank confirmation. Thank you.';

  @override
  String ctrlMsgCardApprovedRoundUpThanks(String message) {
    return '$message Thank you for supporting charity.';
  }

  @override
  String get ctrlMsgPaymentApprovedRoundUpNote =>
      'Payment approved. Your round-up donation will go to charity. Thank you.';

  @override
  String get ctrlMsgPaymentApprovedNote => 'Payment approved. Thank you.';

  @override
  String get ctrlMsgClearSplitBillFirst =>
      'Clear Split Bill before using cash and card split payment.';

  @override
  String ctrlMsgEnterCashBelowTotal(String amount) {
    return 'Enter a cash amount less than $amount before using split payment.';
  }

  @override
  String get ctrlMsgSplitPaymentCanceled => 'Split payment canceled.';

  @override
  String get ctrlMsgTapForRemainingSplitRoundUp =>
      'Thank you for rounding up for charity. Tap your card or phone for the remaining split payment.';

  @override
  String get ctrlMsgTapForRemainingSplit =>
      'Tap your card or phone for the remaining split payment.';

  @override
  String ctrlMsgSplitRecordedCardPending(String cash, String card) {
    return 'Split payment recorded. Cash $cash; card $card pending reconciliation.';
  }

  @override
  String ctrlMsgSplitCompletedCashCard(String cash, String card) {
    return 'Split payment completed. Cash $cash and card $card recorded.';
  }

  @override
  String get ctrlMsgCashReceivedCardPendingNote =>
      'Cash received; card payment recorded pending bank confirmation. Thank you.';

  @override
  String get ctrlMsgSplitCompletedRoundUpNote =>
      'Split payment completed with a card round-up donation. Thank you.';

  @override
  String get ctrlMsgSplitCompletedNote => 'Split payment completed. Thank you.';

  @override
  String ctrlMsgSplitProgressRecorded(int index, int total, int next) {
    return 'Split payment $index of $total recorded. Continue with guest $next.';
  }

  @override
  String ctrlMsgGuestPaidCollectNext(
    int index,
    String amount,
    int next,
    int total,
  ) {
    return 'Guest $index paid $amount. Collect split payment $next of $total.';
  }

  @override
  String ctrlMsgSplitCompletedSummary(int total, String amount) {
    return 'Split payment completed. $total payments recorded for $amount.';
  }

  @override
  String ctrlMsgSplitBillCompletedNote(int total) {
    return 'Split bill completed with $total payments. Thank you.';
  }

  @override
  String ctrlMsgRoundUpPromptQuestion(String amount) {
    return 'Would you like to round up $amount to charity?';
  }

  @override
  String get ctrlOverlayPreparingCashPayment => 'Preparing Cash Payment';

  @override
  String get ctrlOverlayPreparingSecurePayment => 'Preparing Secure Payment';

  @override
  String get ctrlMsgPreparingRoundedCash =>
      'Thank you. We are preparing the rounded amount for cash payment.';

  @override
  String get ctrlMsgPreparingRoundedCard =>
      'Thank you. We are preparing the rounded amount for card payment.';

  @override
  String get ctrlMsgPreparingOriginalCash =>
      'Thank you. We are preparing the original amount for cash payment.';

  @override
  String get ctrlMsgPreparingOriginalCard =>
      'Thank you. We are preparing the original amount for card payment.';

  @override
  String get ctrlMsgCardUnconfirmedReviewing =>
      'The card charge could not be confirmed. Staff is reviewing the payment.';

  @override
  String get ctrlOverlayConnectingTerminal => 'Connecting To Payment Terminal';

  @override
  String get ctrlOverlayWaitingPaymentResult => 'Waiting For Payment Result';

  @override
  String get ctrlMsgTerminalOpening =>
      'Payment Terminal is opening securely. Please wait while the payment terminal prepares the transaction.';

  @override
  String get ctrlMsgRoundedSentToTerminal =>
      'The rounded amount has been sent to Payment Terminal. Please follow the terminal instructions while we wait for the final response.';

  @override
  String get ctrlMsgTotalSentToTerminal =>
      'The order total has been sent to Payment Terminal. Please follow the terminal instructions while we wait for the final response.';

  @override
  String get managerAuthRegisterTitle => 'Register Manager Fingerprint';

  @override
  String get managerAuthRegisterSubtitle => 'Manager authorization setup';

  @override
  String get managerAuthRegisterDescription =>
      'Place the manager fingerprint on the device sensor.';

  @override
  String get managerAuthApprovalRequiredTitle => 'Manager Approval Required';

  @override
  String get managerAuthCancelOrderSubtitle => 'Cancel completed order';

  @override
  String get managerAuthCancelOrderDescription =>
      'Place your fingerprint to unlock order cancellation.';

  @override
  String get managerAuthDefaultSubtitle => 'Manager approval';

  @override
  String get managerAuthDefaultDescription =>
      'Place the manager fingerprint to approve.';

  @override
  String get posCompNothingTitle => 'Nothing to Comp';

  @override
  String get posCompNothingMessage => 'Add items to the order first.';

  @override
  String get posCompAppliedTitle => 'Comp Applied';

  @override
  String posCompExistingMessage(String reason, String amount) {
    return '\"$reason\" is comping $amount on this order.';
  }

  @override
  String get posCompRemoveButton => 'Remove comp';

  @override
  String get posCompKeepButton => 'Keep';

  @override
  String get posCompRemovedTitle => 'Comp Removed';

  @override
  String get posCompRemovedMessage => 'The order is back to its full total.';

  @override
  String get posCompRegisterManagerMessage =>
      'Register the manager fingerprint once before comping items.';

  @override
  String get posCompManagerApprovalMessage =>
      'Comps always need manager approval.';

  @override
  String get posCompLockedTitle => 'Comp Locked';

  @override
  String get posCompDialogTitle => 'Comp (Manager)';

  @override
  String get posCompWhatLabel => 'What is being comped?';

  @override
  String get posCompWholeOrderOption => 'Whole order';

  @override
  String get posCompReasonLabel => 'Reason';

  @override
  String posCompAmountLabel(String amount) {
    return 'Comp amount: $amount';
  }

  @override
  String posCompExceedsCapMessage(String reason, String cap) {
    return 'Exceeds the \"$reason\" cap of $cap.';
  }

  @override
  String get posCompApplyButton => 'Apply comp';

  @override
  String posCompAppliedMessage(String reason, String amount) {
    return '\"$reason\" — $amount written off.';
  }

  @override
  String get posManagerRegisterFingerprintTitle =>
      'Register Manager Fingerprint';

  @override
  String get posManagerApprovalRequiredTitle => 'Manager Approval Required';

  @override
  String get posManagerFingerprintNotApprovedMessage =>
      'Manager fingerprint was not approved.';

  @override
  String get posManagerRegisterSensorMessage =>
      'Place the manager finger on the sensor to enable cancellation.';

  @override
  String get posManagerRegisteredTitle => 'Manager Registered';

  @override
  String get posManagerRegistrationNotCompletedTitle =>
      'Registration Not Completed';

  @override
  String get posManagerRegisteredMessage =>
      'Manager fingerprint approval is ready for order cancellation.';

  @override
  String get posManagerNotRegisteredMessage =>
      'The manager fingerprint was not registered on this terminal.';

  @override
  String get posPayTenderedTooLowTitle => 'Tendered Amount Too Low';

  @override
  String posPayTenderedTooLowMessage(String amount) {
    return 'Tendered cash must be at least $amount.';
  }

  @override
  String get posPayClearSplitFirstTitle => 'Clear Split Bill First';

  @override
  String get posPayClearSplitFirstMessage =>
      'Cash and card split payment can be used after clearing guest split bill.';

  @override
  String get posPayEnterCashPortionTitle => 'Enter Cash Portion';

  @override
  String posPayEnterCashPortionMessage(String amount) {
    return 'Enter the cash amount first. It must be less than $amount so the rest can go to card.';
  }

  @override
  String get posHoldOrderHeldTitle => 'Order Held';

  @override
  String get posHeldOrdersTitle => 'Held Orders';

  @override
  String get posHeldOrdersSubtitle =>
      'Resume any paused ticket and continue from where you left off.';

  @override
  String get posHeldResumedTitle => 'Held Order Resumed';

  @override
  String get posHeldDiscardConfirmTitle => 'Discard Held Order?';

  @override
  String posHeldDiscardConfirmMessage(String reference) {
    return 'Reference $reference will be removed and cannot be resumed afterwards.';
  }

  @override
  String get posHeldKeepButton => 'Keep It';

  @override
  String get posHeldDiscardButton => 'Discard';

  @override
  String get posHeldDiscardedTitle => 'Held Order Discarded';

  @override
  String get posHistoryTitle => 'Order History';

  @override
  String get posHistorySubtitle =>
      'Review completed orders, their payment details, and reprint receipts whenever needed.';

  @override
  String get posHistoryReceiptPrintedTitle => 'Receipt Printed';

  @override
  String posHistoryReceiptPrintedMessage(int orderNumber) {
    return 'Previous receipt for order #$orderNumber was sent to the printer.';
  }

  @override
  String get posKitchenReprintSubtitle => 'Reprint kitchen ticket';

  @override
  String posKitchenReprintDescription(int orderNumber) {
    return 'Place the manager fingerprint to reprint the kitchen ticket for order #$orderNumber.';
  }

  @override
  String get posKitchenApprovalRequiredTitle => 'Approval Required';

  @override
  String get posKitchenApprovalDeniedMessage =>
      'Manager approval was not granted for the kitchen reprint.';

  @override
  String get posKitchenTicketPrintedTitle => 'Kitchen Ticket Printed';

  @override
  String posKitchenTicketPrintedMessage(int orderNumber) {
    return 'Kitchen ticket for order #$orderNumber was sent to the printer.';
  }

  @override
  String get posCancelReqNotAllowedTitle => 'Cancellation Not Allowed';

  @override
  String get posCancelReqNotAllowedMessage =>
      'Your role is not permitted to cancel orders on this terminal.';

  @override
  String get posCancelReqRegisterManagerMessage =>
      'Register the manager fingerprint once before cancelling this completed order.';

  @override
  String get posCancelReqManagerRequiredTitle => 'Manager Fingerprint Required';

  @override
  String get posCancelReqUnlockMessage =>
      'Place the manager fingerprint to unlock cancellation.';

  @override
  String get posCancelReqLockedTitle => 'Cancellation Locked';

  @override
  String get posCancelReqOrderCanceledTitle => 'Order Canceled';

  @override
  String get posCancelReqItemsCanceledTitle => 'Items Canceled';

  @override
  String get posCancelReqDialogTitle => 'Cancel Order';

  @override
  String get posSearchProductsTitle => 'Search Products';

  @override
  String get posSearchProductsHint => 'Type product name or category';

  @override
  String get posSearchTablesTitle => 'Search Tables';

  @override
  String get posSearchTablesHint => 'Search by table name or ticket';

  @override
  String get posCustomerSearchOption => 'Search customer';

  @override
  String get posCustomerSearchOptionSubtitle =>
      'Find by name / phone / plate, see loyalty';

  @override
  String get posCustomerEnterNumberOption => 'Enter number';

  @override
  String get posCustomerClearOption => 'Clear customer';

  @override
  String get posCustomerAttachedTitle => 'Customer Attached';

  @override
  String posCustomerAttachedWithPoints(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
    );
    return '$name  ·  $_temp0';
  }

  @override
  String posCustomerAttachedSummary(String name, String summary) {
    return '$name  ·  $summary';
  }

  @override
  String get posCustomerNumberTitle => 'Customer Number';

  @override
  String get posCustomerNumberHint => 'Enter number, then fetch loyalty';

  @override
  String get posCustomerNotFoundTitle => 'No Customer Found';

  @override
  String posCustomerNotFoundMessage(String query) {
    return 'No customer matches \"$query\". Kept as an order reference.';
  }

  @override
  String posLoyaltySummaryPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pts',
      one: '1 pt',
    );
    return '$_temp0';
  }

  @override
  String posLoyaltySummaryStamps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stamps',
      one: '1 stamp',
    );
    return '$_temp0';
  }

  @override
  String get posLoyaltyNoneYet => 'no loyalty yet';

  @override
  String get posLoyaltyRedeemButton => 'Redeem';

  @override
  String get posLoyaltyRewardRedeemedTitle => 'Reward Redeemed';

  @override
  String posLoyaltyStampRedeemedMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stamps',
      one: '1 stamp',
    );
    return '$_temp0 → $amount off.';
  }

  @override
  String get posLoyaltyNoCustomerTitle => 'No Customer';

  @override
  String get posLoyaltyNoCustomerMessage =>
      'Attach a customer first to redeem loyalty.';

  @override
  String get posLoyaltyNothingToRedeemTitle => 'Nothing to Redeem';

  @override
  String get posLoyaltyNothingToRedeemMessage =>
      'No redeemable points or stamps for this order yet.';

  @override
  String get posLoyaltyCannotRedeemTitle => 'Cannot Redeem';

  @override
  String get posLoyaltyCannotRedeemMessage =>
      'The order total is too low to redeem a block.';

  @override
  String get posLoyaltyPointsRedeemedTitle => 'Points Redeemed';

  @override
  String posLoyaltyPointsRedeemedMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
    );
    return '$_temp0 → $amount off.';
  }

  @override
  String get posPlateTitle => 'Vehicle Plate';

  @override
  String get posPlateHint => 'Enter the car plate number';

  @override
  String get posMsgNoDeliveryProvidersTitle => 'No Delivery Providers';

  @override
  String get posMsgNoDeliveryProvidersMessage =>
      'No delivery providers are set up yet. Add them in the merchant portal.';

  @override
  String get posMsgCashPaymentCompleteTitle => 'Cash Payment Complete';

  @override
  String get posMsgPaymentApprovedTitle => 'Payment Approved';

  @override
  String get posMsgSplitPaymentRecordedTitle => 'Split Payment Recorded';

  @override
  String get posMsgPaymentCanceledTitle => 'Payment Canceled';

  @override
  String get posMsgPaymentFailedTitle => 'Payment Failed';

  @override
  String get posMsgPaymentUpdateTitle => 'Payment Update';

  @override
  String posDiningTablePaidTitle(String table) {
    return '$table Paid';
  }

  @override
  String posDiningTicketPaidMessage(String ticket) {
    return 'Ticket #$ticket was paid successfully. Clear the table when it is ready for the next guest.';
  }

  @override
  String get posDiningPaidTotalLabel => 'Paid Total';

  @override
  String get posDiningFloorLabel => 'Floor';

  @override
  String get posDiningClearTableButton => 'Clear Table';

  @override
  String posDiningTableClearedTitle(String table) {
    return '$table Cleared';
  }

  @override
  String posDiningTableClearedMessage(String table) {
    return '$table is now available for the next guest.';
  }

  @override
  String get posDiscountSheetTitle => 'Apply a discount';

  @override
  String get posDiscountRedeemPointsOption => 'Redeem loyalty points';

  @override
  String posDiscountRedeemPointsSubtitle(int count, String rule) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points available',
      one: '1 point available',
    );
    return '$_temp0  ·  $rule';
  }

  @override
  String get posDiscountRedeemStampOption => 'Redeem stamp reward';

  @override
  String posDiscountStampRewardSubtitle(int count, String amount, String rule) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stamps',
      one: '1 stamp',
    );
    return '$_temp0 → $amount off  ·  $rule';
  }

  @override
  String get posDiscountManagerApprovalTag => 'manager approval';

  @override
  String get posDiscountCustomAmountOption => 'Custom amount';

  @override
  String get posDiscountRemoveOption => 'Remove discount';

  @override
  String get posDiscountClearedTitle => 'Discount Cleared';

  @override
  String get posDiscountClearedMessage =>
      'The order discount has been removed.';

  @override
  String posDiscountPercentOff(String percent) {
    return '$percent% off';
  }

  @override
  String posDiscountAmountOff(String amount) {
    return '$amount off';
  }

  @override
  String get posDiscountApproveSubtitle => 'Approve discount';

  @override
  String posDiscountApproveDescription(String name) {
    return 'Place the manager fingerprint to approve \"$name\".';
  }

  @override
  String get posDiscountApprovalRequiredTitle => 'Approval Required';

  @override
  String posDiscountApprovalDeniedMessage(String name) {
    return 'Manager approval was not granted for \"$name\".';
  }

  @override
  String get posDiscountAppliedTitle => 'Discount Applied';

  @override
  String posDiscountAppliedMessage(String name) {
    return '$name is now active.';
  }

  @override
  String get posDiscountDefaultLabel => 'Order discount';

  @override
  String get posSplitInProgressTitle => 'Split Payment In Progress';

  @override
  String get posSplitInProgressMessage =>
      'Finish all split payments before changing the guest count.';

  @override
  String get posSplitClearedTitle => 'Split Bill Cleared';

  @override
  String get posSplitClearedMessage => 'The order is back to a single payment.';

  @override
  String get posSplitReadyTitle => 'Split Bill Ready';

  @override
  String posSplitReadyMessage(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count shares',
      one: '1 share',
    );
    return 'The order is split into $_temp0 of $amount each.';
  }

  @override
  String get posCharityConfirmRoundUpTitle => 'Confirm Charity Round-Up';

  @override
  String get posCharityConfirmRoundUpBody =>
      'Choose whether to add the optional charity donation before the payment terminal opens. The customer display will show the same totals.';

  @override
  String get posCharityOrderTotal => 'Order Total';

  @override
  String get posCharityRoundUp => 'Round Up';

  @override
  String get posCharityNewTotal => 'New Total';

  @override
  String get posCharityKeepOriginalTotal => 'No, keep original total';

  @override
  String get posCharityRoundUpYes => 'Yes, round up for charity';

  @override
  String get posReconCardNotConfirmedTitle => 'Card charge not confirmed';

  @override
  String posReconCardNotConfirmedBody(String amount) {
    return 'The terminal did not confirm the $amount card charge (e.g. an NFC timeout).\n\nIf the customer was charged, record it as PENDING RECONCILIATION — it will be matched against the bank settlement file. Otherwise cancel and try the charge again.';
  }

  @override
  String get posReconCancelRetry => 'Cancel — retry charge';

  @override
  String get posReconMarkPaidPending => 'Mark paid — pending reconciliation';

  @override
  String get posPaymentPreparingTitle => 'Preparing Payment';

  @override
  String get posPaymentPreparingMessage =>
      'Please wait while the payment terminal opens.';

  @override
  String get posPaymentSecureCardBadge => 'SECURE CARD PAYMENT';

  @override
  String get posPaymentRecordingCashTitle => 'Recording Cash Payment';

  @override
  String get posPaymentRecordingCashMessage =>
      'Please wait while the cash payment is completed.';

  @override
  String get posPaymentCashCheckoutBadge => 'CASH CHECKOUT';

  @override
  String get posPaymentTitle => 'Payment';

  @override
  String get posPaymentNewOrder => 'New Order';

  @override
  String posPaymentOrderRef(String reference) {
    return 'Ref $reference';
  }

  @override
  String posPaymentTableChip(String table) {
    return 'Table $table';
  }

  @override
  String get posPaymentOrderItems => 'Order Items';

  @override
  String get posPaymentSubtotal => 'Subtotal';

  @override
  String get posPaymentDiscountFallback => 'Discount';

  @override
  String get posPaymentNetSubtotal => 'Net Subtotal';

  @override
  String posPaymentCompRow(String reason) {
    return 'Comp · $reason';
  }

  @override
  String posPaymentTaxLine(String name, String rate) {
    return '$name ($rate%)';
  }

  @override
  String posPaymentGuestShareRow(int n) {
    return 'Guest $n Share';
  }

  @override
  String get posPaymentShareDue => 'Share Due';

  @override
  String get posPaymentTotalDue => 'Total Due';

  @override
  String get posPaymentCustomerNumberLabel => 'Customer Number (Optional)';

  @override
  String get posPaymentCustomerNumberHint =>
      'Add a customer number for reference';

  @override
  String get posPaymentVehiclePlateLabel => 'Vehicle Plate (Optional)';

  @override
  String get posPaymentVehiclePlateHint => 'Add a vehicle plate for drive-thru';

  @override
  String get posPaymentDeliveryProviderLabel => 'Delivery Provider';

  @override
  String get posPaymentDeliveryProviderHint => 'Choose a delivery provider';

  @override
  String get posPaymentRedeemLoyalty => 'Redeem Loyalty';

  @override
  String get posPaymentAddDiscount => 'Add Discount';

  @override
  String get posPaymentSplitBill => 'Split Bill';

  @override
  String get posPaymentComp => 'Comp';

  @override
  String get posPaymentCompApplied => 'Comp ✓';

  @override
  String get posPaymentTendered => 'Tendered';

  @override
  String get posPaymentCardBalance => 'Card Balance';

  @override
  String get posPaymentChange => 'Change';

  @override
  String posPaymentQuickCash(int amount) {
    return '$amount OMR';
  }

  @override
  String posPaymentCollectingGuest(int n, int total, String amount) {
    return 'Collecting guest $n of $total: $amount.';
  }

  @override
  String get posPaymentCash => 'Cash';

  @override
  String get posPaymentCard => 'Card';

  @override
  String get posPaymentSplitPayment => 'Split\nPayment';

  @override
  String get posNavHome => 'Home';

  @override
  String get posNavReport => 'Report';

  @override
  String get posNavHistory => 'History';

  @override
  String get posNavReportsComingTitle => 'Reports Coming Next';

  @override
  String get posNavReportsComingBody =>
      'We will connect detailed reporting once the local order archive is fully connected to the database flow.';

  @override
  String get posNavAlreadyHomeBody => 'You are already on the main POS screen.';

  @override
  String get posNavBrandTagline => 'Better ordering';

  @override
  String get posNavStaffFallback => 'Staff';

  @override
  String get posNavOrderHistory => 'Order History';

  @override
  String get posNavHeldOrders => 'Held Orders';

  @override
  String get posNavLoyalty => 'Loyalty';

  @override
  String get posNavReceiptPrintedTitle => 'Receipt Printed';

  @override
  String get posNavReceiptPrintedBody =>
      'The current order receipt was sent to the printer.';

  @override
  String get posMenuCloseShift => 'Close shift';

  @override
  String get posMenuCloseShiftSub => 'Count the drawer and reconcile cash';

  @override
  String get posMenuLogExpense => 'Log expense';

  @override
  String get posMenuLogExpenseSub => 'Record a petty-cash expense';

  @override
  String get posMenuRequestRestock => 'Request restock';

  @override
  String get posMenuRequestRestockSub =>
      'Ask the branch to restock ingredients';

  @override
  String get posMenuStockCount => 'Day-end stock count';

  @override
  String get posMenuStockCountSub => 'Count the shelf and reconcile variances';

  @override
  String get posMenuShiftSummary => 'Shift summary (Z-report)';

  @override
  String get posMenuShiftSummarySub =>
      'Reprint the last closed shift — manager only';

  @override
  String get posMenuSettings => 'Settings';

  @override
  String get posMenuSettingsSub => 'Server address, printing';

  @override
  String get posMenuLogoutSub => 'Return to the staff PIN screen';

  @override
  String get posMenuNoShiftSummaryTitle => 'No Shift Summary Yet';

  @override
  String get posMenuNoShiftSummaryBody =>
      'Close a shift first — its summary is kept for reprinting.';

  @override
  String get posMenuShiftSummaryShort => 'Shift summary';

  @override
  String get posMenuShiftSummaryAuthDesc =>
      'Place the manager fingerprint to reprint the last shift summary.';

  @override
  String get posMenuApprovalRequiredTitle => 'Approval Required';

  @override
  String get posMenuApprovalNotGrantedBody =>
      'Manager approval was not granted for the shift summary.';

  @override
  String get posMenuShiftSummaryPrintedTitle => 'Shift Summary Printed';

  @override
  String get posMenuShiftSummaryPrintedBody =>
      'The last shift summary was sent to the printer.';

  @override
  String get posMenuLogoutConfirmTitle => 'Log out?';

  @override
  String get posMenuLogoutConfirmBody =>
      'You will return to the staff PIN screen. The device stays set up.';

  @override
  String get posOrderPanelTitle => 'Current Order';

  @override
  String get posOrderPanelNewOrder => 'New';

  @override
  String posOrderPanelRef(String reference) {
    return 'Ref $reference';
  }

  @override
  String posOrderPanelTableChip(String table) {
    return 'Table $table';
  }

  @override
  String get posOrderPanelFloorPlan => 'Floor Plan';

  @override
  String get posOrderPanelClear => 'Clear';

  @override
  String get posOrderPanelSubtotal => 'Subtotal';

  @override
  String get posOrderPanelDiscount => 'Discount';

  @override
  String get posOrderPanelNetSubtotal => 'Net Subtotal';

  @override
  String posOrderPanelComp(String reason) {
    return 'Comp · $reason';
  }

  @override
  String posOrderPanelPerShare(int count) {
    return 'Per Share ($count)';
  }

  @override
  String get posOrderPanelTotal => 'Total';

  @override
  String get posOrderPanelBackToFloor => 'Back To Floor';

  @override
  String get posOrderPanelHold => 'Hold';

  @override
  String get posOrderPanelClearTable => 'Clear Table';

  @override
  String get posOrderPanelVoid => 'Void';

  @override
  String get posCatalogCategories => 'Categories';

  @override
  String get posCatalogProducts => 'Products';

  @override
  String get posCatalogFavourites => 'Favourites';

  @override
  String get posCatalogFavouritesComingTitle => 'Favourites Coming Next';

  @override
  String get posCatalogFavouritesComingBody =>
      'We will wire favourite products to the local database in the next pass.';

  @override
  String get posCatalogSearchHint => 'Search';

  @override
  String get posCatalogViewList => 'List';

  @override
  String get posCatalogViewGrid => 'Grid';

  @override
  String get posClockAm => 'AM';

  @override
  String get posClockPm => 'PM';

  @override
  String get posClockMonthJan => 'Jan';

  @override
  String get posClockMonthFeb => 'Feb';

  @override
  String get posClockMonthMar => 'Mar';

  @override
  String get posClockMonthApr => 'Apr';

  @override
  String get posClockMonthMay => 'May';

  @override
  String get posClockMonthJun => 'Jun';

  @override
  String get posClockMonthJul => 'Jul';

  @override
  String get posClockMonthAug => 'Aug';

  @override
  String get posClockMonthSep => 'Sep';

  @override
  String get posClockMonthOct => 'Oct';

  @override
  String get posClockMonthNov => 'Nov';

  @override
  String get posClockMonthDec => 'Dec';

  @override
  String posClockDate(String month, int day, int year) {
    return '$month $day, $year';
  }

  @override
  String get posCartEmptyTitle => 'Tap any product to start the order';

  @override
  String get posCartEmptySubtitle =>
      'The cart, actions, and totals will appear here.';

  @override
  String get posCartAddOn => 'Add On';

  @override
  String posCartQtyTimesName(int qty, String name) {
    return '${qty}x $name';
  }

  @override
  String posCartQtyTimesPrice(int qty, String price) {
    return '$qty x $price';
  }

  @override
  String posCustomizeTitle(String name) {
    return 'Customize $name';
  }

  @override
  String get posCustomizeSubtitle =>
      'Select add-ons and leave notes for this order line.';

  @override
  String get posCustomizeNotesLabel => 'Notes';

  @override
  String get posCustomizeNotesHint =>
      'Add preparation notes for the kitchen or cashier';

  @override
  String posCustomizeApply(String amount) {
    return 'Apply $amount';
  }

  @override
  String get posProductsEmptySearchTitle => 'No products match your search.';

  @override
  String get posProductsEmptyCategoryTitle => 'No products available here yet.';

  @override
  String get posProductsEmptySearchSubtitle =>
      'Try another product name or clear the current search.';

  @override
  String get posProductsEmptyCategorySubtitle =>
      'Choose another category or add products to this category later.';

  @override
  String get posProductsClearSearch => 'Clear Search';

  @override
  String get posProductSoldOutBadge => 'SOLD OUT';

  @override
  String get posProductLowStockBadge => 'LOW STOCK';

  @override
  String get posProductOutsideHoursBadge => 'NOT AVAILABLE NOW';

  @override
  String get posProductAdd => 'Add';

  @override
  String get posPayBtnProcessing => 'Processing Payment';

  @override
  String get posPayBtnProcessToPay => 'Process to Pay';

  @override
  String get posPayBtnCompletingOrder => 'Completing order';

  @override
  String posPayBtnPayAmount(String amount) {
    return 'PAY $amount';
  }

  @override
  String posDiningTicketNumber(String number) {
    return 'Ticket #$number';
  }

  @override
  String posDiningRefNumber(String reference) {
    return 'Ref $reference';
  }

  @override
  String posDiningSeats(int count) {
    return 'Seats $count';
  }

  @override
  String get posDiningStatusAvailable => 'AVAILABLE';

  @override
  String get posDiningStatusOccupied => 'OCCUPIED';

  @override
  String get posDiningStatusPaidClear => 'PAID / CLEAR';

  @override
  String get posStorageHeldEmptyTitle => 'No held orders yet';

  @override
  String get posStorageHeldEmptyMessage =>
      'Any order you place on hold will appear here so the staff can continue it later.';

  @override
  String get posStorageHistoryEmptyTitle => 'No completed orders yet';

  @override
  String get posStorageHistoryEmptyMessage =>
      'Completed payments will be archived here so the staff can review them or print receipts again.';

  @override
  String get posFingerprintBannerTitle => 'Manager cancellation approval';

  @override
  String get posFingerprintBannerMessage =>
      'Register once, then use fingerprint approval before opening completed order cancellation.';

  @override
  String get posFingerprintRegisterManager => 'Register Manager';

  @override
  String get posFingerprintWaiting => 'Waiting for fingerprint';

  @override
  String posStorageHeldRef(String ref) {
    return 'Ref $ref';
  }

  @override
  String posStorageItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String posStorageSplitBadge(int n) {
    return 'Split $n';
  }

  @override
  String posStorageItemQtyName(int qty, String name) {
    return '${qty}x $name';
  }

  @override
  String get posStorageContinueOrder => 'Continue Order';

  @override
  String get posStorageDiscard => 'Discard';

  @override
  String posStorageOrderNumber(int n) {
    return 'Order #$n';
  }

  @override
  String posStorageSplitsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count splits',
      one: '1 split',
    );
    return '$_temp0';
  }

  @override
  String posStorageCanceledAmount(String amount) {
    return 'Canceled $amount';
  }

  @override
  String get posStorageKitchen => 'Kitchen';

  @override
  String get posStorageCanceled => 'Canceled';

  @override
  String posCancelPageTitle(int n) {
    return 'Cancel Order #$n';
  }

  @override
  String get posCancelPageSubtitle =>
      'Manager approved. Cancel the full order or select the completed items to cancel.';

  @override
  String get posCancelPageReasonRequired => 'Pick a cancellation reason first.';

  @override
  String get posCancelPageServerFullOnly =>
      'Synced orders can only be canceled in full.';

  @override
  String get posDiningTableActionsTooltip => 'Table actions';

  @override
  String get posManagerPinTitle => 'Manager PIN';

  @override
  String get posManagerPinSubtitle =>
      'Enter a manager\'s PIN to approve this action.';

  @override
  String get posManagerPinInvalid =>
      'PIN not accepted. Check it and try again.';

  @override
  String get posManagerPinOffline =>
      'PIN approval needs a connection — use the fingerprint instead.';

  @override
  String get posManagerPinVerify => 'Verify';

  @override
  String get posCustomerDetailsTooltip => 'Customer details';

  @override
  String get posCustomerDetailsWallet => 'Wallet';

  @override
  String get posCustomerDetailsPlates => 'Vehicle plates';

  @override
  String get posCustomerDetailsNoPlates => 'No plates registered yet.';

  @override
  String get posCustomerDetailsLoyalty => 'Loyalty';

  @override
  String get posCustomerDetailsRedeem => 'Redeem';

  @override
  String posCustomerDetailsStampProgress(int got, int needed) {
    return '$got/$needed stamps';
  }

  @override
  String get posPlateSearchTooltip => 'Find customers by plate';

  @override
  String get posPlateSearchTitle => 'Search by Plate';

  @override
  String posPlateSearchNoMatches(String plate) {
    return 'No customers linked to $plate.';
  }

  @override
  String posPlateSearchPickCustomer(String plate) {
    return 'Customers linked to $plate';
  }

  @override
  String get posEarnPickerTitle => 'Loyalty Program';

  @override
  String posEarnPickerSubtitle(String name) {
    return 'Which program(s) should this order earn under for $name?';
  }

  @override
  String get posEarnPickerConfirm => 'Confirm';

  @override
  String get posDiscountDlgCustomSection => 'Custom';

  @override
  String get posDiscountDlgCustomPercentHint => 'Percent (e.g. 7.5)';

  @override
  String get posDiscountDlgCustomAmountHint => 'Amount (OMR)';

  @override
  String get posDiscountDlgReasonHint => 'Reason (required for a custom value)';

  @override
  String get posDiscountDlgReasonRequired =>
      'Enter a reason for the custom discount.';

  @override
  String get posPaymentBankPos => 'Bank POS';

  @override
  String get displayMethodBankPos => 'Bank POS';

  @override
  String get ctrlMsgBankPosRecording => 'Recording the bank terminal payment…';

  @override
  String get ctrlMsgBankPosRecorded => 'Bank POS payment recorded.';

  @override
  String get ctrlMsgBankPosCompleted =>
      'Payment received on the bank terminal. Thank you!';

  @override
  String get posCartGift => 'Gift';

  @override
  String get posCartGifted => 'Gifted';

  @override
  String get posGiftItemApprovalMessage =>
      'Gifting an item needs a manager\'s approval.';

  @override
  String get posGiftItemBlockedTitle => 'Already Comped';

  @override
  String get posGiftItemBlockedMessage =>
      'The whole order is already comped — there is nothing left to gift.';

  @override
  String get posGiftItemGiftedTitle => 'Item Gifted';

  @override
  String get posGiftItemRemovedTitle => 'Gift Removed';

  @override
  String get reportsTitle => 'Branch Reports';

  @override
  String get reportsLoadFailed =>
      'Couldn\'t load the report. Check the connection and try again.';

  @override
  String get reportsRetry => 'Retry';

  @override
  String get reportsRangeToday => 'Today';

  @override
  String get reportsRange7d => '7 days';

  @override
  String get reportsRange30d => '30 days';

  @override
  String get reportsRangeCustom => 'Custom';

  @override
  String get reportsNoData => 'No data for this period.';

  @override
  String get reportsKpiGross => 'Gross Sales';

  @override
  String get reportsKpiOrders => 'Orders';

  @override
  String get reportsKpiAvgOrder => 'Avg Order';

  @override
  String get reportsKpiTax => 'Tax';

  @override
  String get reportsKpiDiscounts => 'Discounts';

  @override
  String get reportsKpiCompsGifts => 'Comps & Gifts';

  @override
  String get reportsKpiCustomers => 'Customers';

  @override
  String get reportsKpiPointsRedeemed => 'Points Redeemed';

  @override
  String get reportsSalesByDay => 'Sales by Day';

  @override
  String get reportsSalesByHour => 'Sales by Hour';

  @override
  String get reportsTenderMix => 'Payment Methods';

  @override
  String get reportsOrderTypes => 'Order Types';

  @override
  String get reportsTopProducts => 'Top Products';

  @override
  String get reportsStockConsumption => 'Stock Consumption';

  @override
  String get reportsLoyalty => 'Loyalty';

  @override
  String get reportsPointsEarned => 'Points earned';

  @override
  String get reportsPointsRedeemed => 'Points redeemed';

  @override
  String get reportsStampsEarned => 'Stamps earned';

  @override
  String get reportsStampsRedeemed => 'Stamps redeemed';

  @override
  String get reportsTopCustomers => 'Top Customers';

  @override
  String get reportsDiscounts => 'Discounts';

  @override
  String get reportsMethodLoyalty => 'Loyalty';

  @override
  String reportsQtyTimes(String qty) {
    return '×$qty';
  }

  @override
  String reportsOrdersCount(int count) {
    return '$count orders';
  }

  @override
  String reportsTimesUsed(int count) {
    return 'used $count×';
  }

  @override
  String get reportsNotAllowedTitle => 'Reports Locked';

  @override
  String get reportsNotAllowedBody =>
      'Your role is not permitted to view branch reports on this terminal.';

  @override
  String get reportsChooserDashboardSub =>
      'Sales, products, customers and stock for this branch.';

  @override
  String get reportsChooserXReportSub =>
      'Print the current shift\'s sales so far.';

  @override
  String get posMenuCloseShiftAndLogout => 'Close Shift & Log Out';

  @override
  String get posMenuCloseShiftAndLogoutSub =>
      'Count the drawer, print the shift summary, then sign out.';

  @override
  String get posMenuLogoutOnly => 'Just Log Out';

  @override
  String get posMenuLogoutOnlySub =>
      'The shift stays open — switching staff only.';

  @override
  String get posCancelPageOrderItems => 'Order Items';

  @override
  String posCancelPageCancellableCount(int count) {
    return '$count cancellable';
  }

  @override
  String get posCancelPageSaving => 'Saving...';

  @override
  String posCancelPageCancelSelected(int count) {
    return 'Cancel Selected ($count)';
  }

  @override
  String get posCancelPageCancelFullOrder => 'Cancel Full Order';

  @override
  String get posCancelPageOrderSummary => 'Order Summary';

  @override
  String get posCancelPagePaidTotal => 'Paid total';

  @override
  String get posCancelPageCanceledMetric => 'Canceled';

  @override
  String get posCancelPagePaymentMetric => 'Payment';

  @override
  String get posCancelPageCancellationLog => 'Cancellation Log';

  @override
  String get posCancelPageNoCancellations => 'No cancellations recorded.';

  @override
  String get posCancelPageItemFallback => 'Item';

  @override
  String posCancelPageItemQtyName(int qty, String name) {
    return '$qty x $name';
  }

  @override
  String get posDeliveryPickerTitle => 'Choose Delivery Provider';

  @override
  String get posDeliveryPickerSubtitle =>
      'Product prices update to the selected provider.';

  @override
  String get posKeyboardSpace => 'SPACE';

  @override
  String get posKeyboardClear => 'Clear';

  @override
  String get posKeyboardBackspace => 'Backspace';

  @override
  String get posCustomerSearchFailed => 'Search failed. Check the connection.';

  @override
  String get posCustomerSearchHint => 'Name, phone, or plate';

  @override
  String get posCustomerSearchButton => 'Search';

  @override
  String get posCustomerSearchNoResults => 'No customers found.';

  @override
  String posCustomerSearchPoints(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points',
      one: '1 point',
    );
    return '$_temp0';
  }

  @override
  String get posRedeemTitle => 'Redeem points';

  @override
  String posRedeemPerBlock(int points, String value) {
    return '$points points = $value per block';
  }

  @override
  String posRedeemSummary(int points, String value) {
    return '$points points  →  $value off';
  }

  @override
  String get posRedeemConfirm => 'Redeem';

  @override
  String get posDiscountDlgTitle => 'Add Discount';

  @override
  String get posDiscountDlgPercentageSection => 'Percentage Discounts';

  @override
  String get posDiscountDlgFixedSection => 'Fixed Discounts';

  @override
  String get posDiscountDlgClear => 'Clear Discount';

  @override
  String posDiscountDlgApply(String label) {
    return 'Apply $label';
  }

  @override
  String get posSplitDlgTitle => 'Split Bill';

  @override
  String get posSplitDlgSingleBill => 'Single Bill';

  @override
  String posSplitDlgGuests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Guests',
      one: '1 Guest',
    );
    return '$_temp0';
  }

  @override
  String get posSplitDlgEachGuestPays => 'Each guest pays';

  @override
  String get posSplitDlgSinglePaymentTotal => 'Single payment total';

  @override
  String get posSplitDlgApplySplit => 'Apply Split';

  @override
  String get posSplitDlgUseSingleBill => 'Use Single Bill';

  @override
  String get displayMethodCardShort => 'Card';

  @override
  String get displayMethodGift => 'Gift';

  @override
  String get ctrlMsgGiftRecorded => 'Gift order recorded — nothing charged.';

  @override
  String get ctrlMsgGiftCompleted => 'This order is our gift. Thank you!';

  @override
  String get posPaymentGift => 'Gift';

  @override
  String get posPayGiftConfirmTitle => 'Gift This Order?';

  @override
  String posPayGiftConfirmMessage(String amount) {
    return 'The whole order ($amount OMR) will be gifted — nothing is charged to the customer. Inventory still deducts.';
  }

  @override
  String get posPayGiftRegisterManagerMessage =>
      'Register the manager fingerprint once before gifting an order.';

  @override
  String get posPayGiftManagerApprovalMessage =>
      'Place the manager fingerprint to gift this order.';

  @override
  String get posPayGiftDeniedMessage =>
      'Manager approval was not granted for the gift.';

  @override
  String get posPrintFailedReceiptTitle => 'Receipt Didn\'t Print';

  @override
  String get posPrintFailedReceiptBody =>
      'Check the printer (paper / cover). The order is saved — reprint it from History.';

  @override
  String get posPrintFailedKitchenTitle => 'Kitchen Ticket Didn\'t Print';

  @override
  String get posPrintFailedKitchenBody =>
      'The order is saved. Reprint the kitchen copy from History.';

  @override
  String get posPrintFailedShiftTitle => 'Shift Summary Didn\'t Print';

  @override
  String get posPrintFailedShiftBody =>
      'Check the printer, then reprint from the staff menu.';

  @override
  String get shiftClosePrintFailed =>
      'The summary did not print — check the printer and try again.';

  @override
  String get posMidShiftReportTitle => 'Current Shift';

  @override
  String get posMidShiftThisDeviceOnly =>
      'This device only — live estimate, not the closing reconciliation.';

  @override
  String get posMidShiftNoOpenShiftTitle => 'No Open Shift';

  @override
  String get posMidShiftNoOpenShiftBody =>
      'Open a shift first — the report covers the current drawer session.';

  @override
  String get posMidShiftAuthSubtitle => 'Shift report';

  @override
  String get posMidShiftAuthDesc =>
      'Place the manager fingerprint to view the current shift report.';

  @override
  String get posMidShiftAuthDeniedBody =>
      'Manager approval was not granted for the shift report.';

  @override
  String get posMidShiftOrders => 'Orders';

  @override
  String get posMidShiftGross => 'Gross sales';

  @override
  String get posMidShiftDiscounts => 'Discounts';

  @override
  String get posMidShiftComps => 'Comps';

  @override
  String get posMidShiftTax => 'Tax';

  @override
  String get posMidShiftTotal => 'TOTAL';

  @override
  String get posMidShiftRoundUp => 'Round-up donations';

  @override
  String get posMidShiftVoids => 'Voids';

  @override
  String get posMidShiftOpeningFloat => 'Opening float';

  @override
  String get posMidShiftCashTaken => 'Cash taken (this device)';

  @override
  String posDiningActionsTitle(String table) {
    return 'Table $table';
  }

  @override
  String get posDiningActionOpen => 'Open table';

  @override
  String get posDiningActionMove => 'Move to another table';

  @override
  String get posDiningActionMoveHint =>
      'The party changed seats — the order follows.';

  @override
  String get posDiningActionMerge => 'Merge into another table';

  @override
  String get posDiningActionMergeHint =>
      'Combine this order into another occupied table.';

  @override
  String get posDiningPickFreeTable => 'Move to which free table?';

  @override
  String get posDiningPickMergeTarget => 'Merge into which table?';

  @override
  String get posDiningMergeConfirmTitle => 'Merge Tables?';

  @override
  String posDiningMergeConfirmBody(
    String source,
    String sourceTotal,
    String target,
    String targetTotal,
  ) {
    return '$source ($sourceTotal) will be merged into $target ($targetTotal). The source table becomes free; the target keeps its reference and discount.';
  }

  @override
  String get posDiningNoFreeTables => 'No free tables available right now.';

  @override
  String get posDiningNoMergeTargets =>
      'No other occupied tables to merge into.';

  @override
  String get posDiningActionFailed =>
      'The table state changed — refresh the floor plan and try again.';

  @override
  String get posDiningTableMovedTitle => 'Table Moved';

  @override
  String get posDiningTablesMergedTitle => 'Tables Merged';

  @override
  String ctrlMsgTableTransferred(String from, String to) {
    return 'Moved $from to $to — the order followed the party.';
  }

  @override
  String ctrlMsgTablesMerged(String source, String target) {
    return 'Merged $source into $target.';
  }

  @override
  String get posNavOffers => 'Offers';

  @override
  String get posOffersNone => 'No offers are active for this branch right now.';

  @override
  String posOffersAppliedTimes(int n) {
    return 'Applied ×$n';
  }

  @override
  String get posOfferTypeBogo => 'Buy & Get';

  @override
  String get posOfferTypeBundle => 'Bundle';

  @override
  String get posOfferTypeMultiBuy => 'Multi-Buy';

  @override
  String get posOfferTypeCheapestFree => 'Cheapest Free';

  @override
  String get posOfferTypeSpendGet => 'Spend & Get';

  @override
  String posOffersBundleNeed(int n) {
    return 'pick $n';
  }

  @override
  String get posOffersBundlePrice => 'Bundle price:';

  @override
  String get posOffersBundleAdd => 'Add Bundle';

  @override
  String posCustomizeMinHint(int n) {
    return 'Select at least $n';
  }
}
