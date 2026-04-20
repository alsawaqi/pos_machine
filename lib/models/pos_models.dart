class Product {
  final String id;
  final String name;
  final String category;
  final double price;
  final String? imageAsset;
  final bool lowStock;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.imageAsset,
    this.lowStock = false,
  });
}

class CartItem {
  final Product product;
  int qty;

  CartItem({required this.product, this.qty = 1});

  double get lineTotal => product.price * qty;

  Map<String, dynamic> toMap() {
    return {
      'name': product.name,
      'qty': qty,
      'unitPrice': product.price,
      'lineTotal': lineTotal,
      'imageAsset': product.imageAsset,
      'lowStock': product.lowStock,
    };
  }
}

class OrderSnapshot {
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double tax;
  final double total;
  final double payableTotal;
  final String paymentStatus;
  final String paymentMethod;
  final String note;
  final bool showCharityRoundUpPrompt;
  final bool showPaymentLaunchOverlay;
  final bool charityRoundUpAccepted;
  final double charityRoundUpAmount;
  final double charityRoundUpTotal;

  const OrderSnapshot({
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.payableTotal,
    required this.paymentStatus,
    required this.paymentMethod,
    required this.note,
    required this.showCharityRoundUpPrompt,
    required this.showPaymentLaunchOverlay,
    required this.charityRoundUpAccepted,
    required this.charityRoundUpAmount,
    required this.charityRoundUpTotal,
  });

  factory OrderSnapshot.initial() {
    return const OrderSnapshot(
      items: [],
      subtotal: 0,
      tax: 0,
      total: 0,
      payableTotal: 0,
      paymentStatus: 'Waiting',
      paymentMethod: 'Cash',
      note: '',
      showCharityRoundUpPrompt: false,
      showPaymentLaunchOverlay: false,
      charityRoundUpAccepted: false,
      charityRoundUpAmount: 0,
      charityRoundUpTotal: 0,
    );
  }

  factory OrderSnapshot.fromMap(Map<String, dynamic> map) {
    return OrderSnapshot(
      items: ((map['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      tax: (map['tax'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      payableTotal:
          (map['payableTotal'] as num?)?.toDouble() ??
          (map['total'] as num?)?.toDouble() ??
          0,
      paymentStatus: map['paymentStatus']?.toString() ?? 'Waiting',
      paymentMethod: map['paymentMethod']?.toString() ?? 'Cash',
      note: map['note']?.toString() ?? '',
      showCharityRoundUpPrompt: map['showCharityRoundUpPrompt'] == true,
      showPaymentLaunchOverlay: map['showPaymentLaunchOverlay'] == true,
      charityRoundUpAccepted: map['charityRoundUpAccepted'] == true,
      charityRoundUpAmount:
          (map['charityRoundUpAmount'] as num?)?.toDouble() ?? 0,
      charityRoundUpTotal:
          (map['charityRoundUpTotal'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'payableTotal': payableTotal,
      'paymentStatus': paymentStatus,
      'paymentMethod': paymentMethod,
      'note': note,
      'showCharityRoundUpPrompt': showCharityRoundUpPrompt,
      'showPaymentLaunchOverlay': showPaymentLaunchOverlay,
      'charityRoundUpAccepted': charityRoundUpAccepted,
      'charityRoundUpAmount': charityRoundUpAmount,
      'charityRoundUpTotal': charityRoundUpTotal,
    };
  }
}
