import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/pos_models.dart';
import '../services/mosambee_payment_service.dart';
import '../services/presentation_service.dart';
import '../services/sunmi_receipt_service.dart';

class PosController extends ChangeNotifier {
  final PresentationService _presentation = PresentationService.instance;
  final MosambeePaymentService _paymentBridge = MosambeePaymentService();

  final List<String> categories = const [
    'Coffee',
    'Drinks',
    'Food',
    'Dessert',
    'Bakery',
    'Special',
  ];

  final List<Product> allProducts = const [
    Product(
      id: '1',
      name: 'Espresso',
      category: 'Coffee',
      price: 1.500,
      imageAsset: 'assets/images/espresso_blue.png',
      lowStock: true,
    ),
    Product(
      id: '2',
      name: 'Cappuccino',
      category: 'Coffee',
      price: 2.000,
      imageAsset: 'assets/images/cappuccino.png',
      lowStock: true,
    ),
    Product(
      id: '3',
      name: 'Latte',
      category: 'Coffee',
      price: 2.200,
      imageAsset: 'assets/images/latte.png',
      lowStock: true,
    ),
    Product(
      id: '4',
      name: 'Americano',
      category: 'Coffee',
      price: 1.800,
      imageAsset: 'assets/images/americano.png',
      lowStock: true,
    ),
    Product(id: '5', name: 'Orange Juice', category: 'Drinks', price: 1.700),
    Product(id: '6', name: 'Brownie', category: 'Dessert', price: 1.600),
  ];

  final List<CartItem> _cart = [];
  List<CartItem> get cart => List.unmodifiable(_cart);

  String selectedCategory = 'Coffee';
  String paymentStatus = 'Waiting';
  String selectedPaymentMethod = 'Cash';
  String lastCustomerEvent = '';
  String lastPaymentMessage = '';
  String displayNote = '';
  bool rearDisplayOpened = false;
  bool isProcessingPayment = false;
  bool showCharityRoundUpPrompt = false;
  bool showPaymentLaunchOverlay = false;
  bool charityRoundUpAccepted = false;
  double charityRoundUpAmount = 0;
  double charityRoundUpTotal = 0;

  bool _presentationEnabled =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool _isDisposed = false;
  Completer<bool>? _charityRoundUpCompleter;

  PosController() {
    _paymentBridge.setLaunchStateListener(_handlePaymentLaunchState);
  }

  Future<void> init() async {
    if (_presentationEnabled) {
      try {
        _presentation.listenFromCustomer((data) {
          if (data is Map && data['type'] == 'charity_round_up_response') {
            debugPrint(
              'PosController received charity round-up response: accepted=${data['accepted'] == true}',
            );
            _handleCharityRoundUpResponse(data['accepted'] == true);
            return;
          }

          if (data is Map && data['type'] == 'customer_event') {
            lastCustomerEvent = data['message']?.toString() ?? '';
            _notifySafely();
          }
        });
        await syncRearDisplay();
      } on MissingPluginException {
        _presentationEnabled = false;
      } catch (_) {
        _presentationEnabled = false;
      }
    }

    _notifySafely();
  }

  List<Product> get visibleProducts =>
      allProducts.where((p) => p.category == selectedCategory).toList();

  double get subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);

  double get tax => subtotal * 0.05;
  double get total => subtotal + tax;
  double get payableTotal =>
      charityRoundUpAccepted ? charityRoundUpTotal : total;
  double get offeredCharityRoundUpTotal => _roundMoney(total.ceilToDouble());
  double get offeredCharityRoundUpAmount =>
      _roundMoney(offeredCharityRoundUpTotal - total);
  bool get canOfferCharityRoundUp =>
      selectedPaymentMethod == 'Credit Card' &&
      offeredCharityRoundUpAmount >= 0.001;

  OrderSnapshot snapshot({String? note}) {
    return OrderSnapshot(
      items: _cart.map((e) => e.toMap()).toList(),
      subtotal: subtotal,
      tax: tax,
      total: total,
      payableTotal: payableTotal,
      paymentStatus: paymentStatus,
      paymentMethod: selectedPaymentMethod,
      note: note ?? displayNote,
      showCharityRoundUpPrompt: showCharityRoundUpPrompt,
      showPaymentLaunchOverlay: showPaymentLaunchOverlay,
      charityRoundUpAccepted: charityRoundUpAccepted,
      charityRoundUpAmount: charityRoundUpAmount,
      charityRoundUpTotal: charityRoundUpTotal,
    );
  }

  Future<void> syncRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      await _presentation.sendOrder(snapshot());
    } on MissingPluginException {
      _presentationEnabled = false;
    } catch (_) {
      _presentationEnabled = false;
    }
  }

  void selectCategory(String category) {
    selectedCategory = category;
    _notifySafely();
  }

  void selectPaymentMethod(String paymentMethod) {
    selectedPaymentMethod = paymentMethod;
    _broadcast();
  }

  void addProduct(Product product) {
    final index = _cart.indexWhere((e) => e.product.id == product.id);
    if (index == -1) {
      _cart.add(CartItem(product: product));
    } else {
      _cart[index].qty++;
    }
    _broadcast();
  }

  void removeProduct(Product product) {
    _cart.removeWhere((item) => item.product.id == product.id);
    _broadcast();
  }

  void decreaseProduct(Product product) {
    final index = _cart.indexWhere((e) => e.product.id == product.id);
    if (index == -1) return;

    if (_cart[index].qty <= 1) {
      _cart.removeAt(index);
    } else {
      _cart[index].qty--;
    }
    _broadcast();
  }

  Future<void> openRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      rearDisplayOpened = await _presentation.openFirstRearDisplay();
      _notifySafely();
      if (rearDisplayOpened) {
        await Future.delayed(const Duration(milliseconds: 450));
        await syncRearDisplay();
      }
    } on MissingPluginException {
      _presentationEnabled = false;
      rearDisplayOpened = false;
    } catch (_) {
      rearDisplayOpened = false;
    }
  }

  Future<void> closeRearDisplay() async {
    if (!_presentationEnabled) return;

    try {
      await _presentation.closeRearDisplay();
    } on MissingPluginException {
      _presentationEnabled = false;
    } catch (_) {}

    rearDisplayOpened = false;
    _notifySafely();
  }

  Future<void> printOnly() async {
    if (_cart.isEmpty) return;
    await SunmiReceiptService.printReceipt(snapshot());
  }

  Future<String?> payAndPrint() async {
    if (_cart.isEmpty || isProcessingPayment) return null;

    _resetCharityRoundUp();
    showPaymentLaunchOverlay = false;
    isProcessingPayment = true;
    lastPaymentMessage = '';

    try {
      if (selectedPaymentMethod == 'Cash') {
        paymentStatus = 'Processing payment';
        displayNote = 'The cashier is completing a cash payment.';
        _broadcast();

        paymentStatus = 'Paid';
        lastPaymentMessage = 'Cash payment recorded successfully.';
        displayNote = 'Cash payment completed. Thank you.';
        _broadcast();

        await SunmiReceiptService.printReceipt(snapshot());
        await Future.delayed(const Duration(milliseconds: 700));
        final successMessage = lastPaymentMessage;
        clearForNextOrder();
        return successMessage;
      }

      if (canOfferCharityRoundUp) {
        final accepted = await _promptForCharityRoundUp();
        if (accepted == null) {
          showPaymentLaunchOverlay = false;
          paymentStatus = 'Payment canceled';
          lastPaymentMessage = 'Timed out waiting for the customer response.';
          displayNote = lastPaymentMessage;
          _broadcast();
          return lastPaymentMessage;
        }
      } else {
        _showPaymentLaunchOverlay();
      }

      // Transition to 'Processing payment' and clear the overlay before
      // invoking the Mosambee bridge so the customer display shows
      // "Tap to Pay" immediately — without depending on the Kotlin
      // notifyLaunchState callback which can be delayed across the
      // microtask boundary after the charity completer fires.
      showPaymentLaunchOverlay = false;
      paymentStatus = 'Processing payment';
      displayNote = charityRoundUpAccepted
          ? 'Thank you for rounding up for charity. Tap your card or phone on the rear NFC area to pay.'
          : 'Tap your card or phone on the rear NFC area to pay.';
      _broadcast();

      debugPrint(
        'PosController invoking Mosambee loginAndPay with amount=${payableTotal.toStringAsFixed(3)}',
      );

      final paymentResult = await _paymentBridge.loginAndPay(payableTotal);

      if (!paymentResult.isSuccess) {
        showPaymentLaunchOverlay = false;
        paymentStatus = paymentResult.isCanceled
            ? 'Payment canceled'
            : 'Payment failed';
        lastPaymentMessage = paymentResult.userMessage;
        displayNote = paymentResult.userMessage;
        _broadcast();
        return lastPaymentMessage;
      }

      showPaymentLaunchOverlay = false;
      paymentStatus = 'Paid';
      lastPaymentMessage = charityRoundUpAccepted
          ? '${paymentResult.userMessage} Thank you for supporting charity.'
          : paymentResult.userMessage;
      displayNote = charityRoundUpAccepted
          ? 'Payment approved. Your round-up donation will go to charity. Thank you.'
          : 'Payment approved. Thank you.';
      _broadcast();

      await SunmiReceiptService.printReceipt(snapshot());

      await Future.delayed(const Duration(milliseconds: 700));
      final successMessage = lastPaymentMessage;
      clearForNextOrder();
      return successMessage;
    } finally {
      showPaymentLaunchOverlay = false;
      isProcessingPayment = false;
      _broadcast();
    }
  }

  void clearForNextOrder() {
    _cart.clear();
    paymentStatus = 'Waiting';
    lastPaymentMessage = '';
    displayNote = '';
    isProcessingPayment = false;
    showPaymentLaunchOverlay = false;
    _resetCharityRoundUp();
    _broadcast();
  }

  Future<void> shutdown() async {
    await closeRearDisplay();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _broadcast() {
    _notifySafely();
    unawaited(syncRearDisplay());
  }

  Future<bool?> _promptForCharityRoundUp() async {
    if (_charityRoundUpCompleter != null &&
        !_charityRoundUpCompleter!.isCompleted) {
      _charityRoundUpCompleter!.complete(false);
    }
    _charityRoundUpCompleter = Completer<bool>();

    paymentStatus = 'Awaiting customer';
    showCharityRoundUpPrompt = true;
    showPaymentLaunchOverlay = false;
    charityRoundUpAccepted = false;
    charityRoundUpAmount = offeredCharityRoundUpAmount;
    charityRoundUpTotal = offeredCharityRoundUpTotal;
    displayNote =
        'Would you like to round up ${SunmiReceiptService.money(charityRoundUpAmount)} to charity?';
    _broadcast();
    debugPrint('PosController waiting for charity round-up response.');

    try {
      return await _charityRoundUpCompleter!.future.timeout(
        const Duration(minutes: 2),
      );
    } on TimeoutException {
      showCharityRoundUpPrompt = false;
      showPaymentLaunchOverlay = false;
      _broadcast();
      return null;
    } finally {
      _charityRoundUpCompleter = null;
    }
  }

  void _handleCharityRoundUpResponse(bool accepted) {
    if (_charityRoundUpCompleter == null ||
        _charityRoundUpCompleter!.isCompleted) {
      debugPrint(
        'PosController ignored charity response because no active prompt was waiting.',
      );
      return;
    }

    showCharityRoundUpPrompt = false;
    charityRoundUpAccepted = accepted;
    charityRoundUpAmount = accepted ? offeredCharityRoundUpAmount : 0;
    charityRoundUpTotal = accepted ? offeredCharityRoundUpTotal : total;
    _showPaymentLaunchOverlay();
    lastCustomerEvent = accepted
        ? 'Customer accepted the charity round-up.'
        : 'Customer declined the charity round-up.';
    debugPrint(lastCustomerEvent);
    _broadcast();
    _charityRoundUpCompleter!.complete(accepted);
  }

  void _resetCharityRoundUp() {
    showCharityRoundUpPrompt = false;
    showPaymentLaunchOverlay = false;
    charityRoundUpAccepted = false;
    charityRoundUpAmount = 0;
    charityRoundUpTotal = 0;
  }

  void _showPaymentLaunchOverlay() {
    showPaymentLaunchOverlay = true;
    paymentStatus = 'Preparing payment';
    displayNote = charityRoundUpAccepted
        ? 'Preparing the charitable card payment on the customer terminal...'
        : 'Preparing the card payment on the customer terminal...';
  }

  void _handlePaymentLaunchState(Map<String, dynamic> event) {
    final stage = event['stage']?.toString() ?? '';
    final surface = event['surface']?.toString() ?? 'unknown';

    if (!isProcessingPayment) return;
    if (stage != 'login_started' && stage != 'payment_started') return;

    debugPrint(
      'PosController received Mosambee launch event: $stage on $surface.',
    );

    showPaymentLaunchOverlay = false;
    paymentStatus = 'Processing payment';
    displayNote = charityRoundUpAccepted
        ? 'Thank you for rounding up for charity. Tap your card or phone on the rear NFC area to pay.'
        : 'Tap your card or phone on the rear NFC area to pay.';
    _broadcast();
  }

  double _roundMoney(double value) => double.parse(value.toStringAsFixed(3));

  void _notifySafely() {
    if (_isDisposed) return;
    notifyListeners();
  }
}
