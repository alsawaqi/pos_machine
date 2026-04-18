import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/pos_models.dart';
import '../services/presentation_service.dart';
import '../services/sunmi_receipt_service.dart';

class PosController extends ChangeNotifier {
  final PresentationService _presentation = PresentationService.instance;

  final List<String> categories = const [
    'Coffee',
    'Drinks',
    'Food',
    'Dessert',
    'Bakery',
    'Special',
  ];

  final List<Product> allProducts = const [
    Product(id: '1', name: 'Espresso', category: 'Coffee', price: 1.500),
    Product(id: '2', name: 'Cappuccino', category: 'Coffee', price: 2.000),
    Product(id: '3', name: 'Latte', category: 'Coffee', price: 2.200),
    Product(id: '4', name: 'Americano', category: 'Coffee', price: 1.800),
    Product(id: '5', name: 'Orange Juice', category: 'Drinks', price: 1.700),
    Product(id: '6', name: 'Brownie', category: 'Dessert', price: 1.600),
  ];

  final List<CartItem> _cart = [];
  List<CartItem> get cart => List.unmodifiable(_cart);

  String selectedCategory = 'Coffee';
  String paymentStatus = 'Waiting';
  String lastCustomerEvent = '';
  bool rearDisplayOpened = false;

  Future<void> init() async {
    _presentation.listenFromCustomer((data) {
      if (data is Map && data['type'] == 'customer_event') {
        lastCustomerEvent = data['message']?.toString() ?? '';
        notifyListeners();
      }
    });

    if (_cart.isEmpty) {
      _cart.add(CartItem(product: allProducts.first, qty: 2));
    }

    await syncRearDisplay();
    notifyListeners();
  }

  List<Product> get visibleProducts =>
      allProducts.where((p) => p.category == selectedCategory).toList();

  double get subtotal => _cart.fold(0, (sum, item) => sum + item.lineTotal);

  double get tax => subtotal * 0.05;
  double get total => subtotal + tax;

  OrderSnapshot snapshot({String note = ''}) {
    return OrderSnapshot(
      items: _cart.map((e) => e.toMap()).toList(),
      subtotal: subtotal,
      tax: tax,
      total: total,
      paymentStatus: paymentStatus,
      note: note,
    );
  }

  Future<void> syncRearDisplay() async {
    await _presentation.sendOrder(
      OrderSnapshot(
        items: _cart.map((e) => e.toMap()).toList(),
        subtotal: subtotal,
        tax: tax,
        total: total,
        paymentStatus: paymentStatus,
        note: '',
      ),
    );
  }

  void selectCategory(String category) {
    selectedCategory = category;
    notifyListeners();
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
    rearDisplayOpened = await _presentation.openFirstRearDisplay();
    notifyListeners();
    await syncRearDisplay();
  }

  Future<void> closeRearDisplay() async {
    await _presentation.closeRearDisplay();
    rearDisplayOpened = false;
    notifyListeners();
  }

  Future<void> printOnly() async {
    if (_cart.isEmpty) return;
    await SunmiReceiptService.printReceipt(snapshot());
  }

  Future<void> payAndPrint() async {
    if (_cart.isEmpty) return;

    paymentStatus = 'Processing payment';
    _broadcast();

    await Future.delayed(const Duration(seconds: 1));

    paymentStatus = 'Paid';
    _broadcast();

    await SunmiReceiptService.printReceipt(snapshot(note: 'Thank you'));

    await Future.delayed(const Duration(seconds: 1));
    clearForNextOrder();
  }

  void clearForNextOrder() {
    _cart.clear();
    paymentStatus = 'Waiting';
    _broadcast();
  }

  void _broadcast() {
    notifyListeners();
    unawaited(_presentation.sendOrder(snapshot()));
  }
}
