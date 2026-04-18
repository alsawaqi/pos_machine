class Product {
  final String id;
  final String name;
  final String category;
  final double price;

  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
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
    };
  }
}

class OrderSnapshot {
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double tax;
  final double total;
  final String paymentStatus;
  final String note;

  const OrderSnapshot({
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paymentStatus,
    required this.note,
  });

  factory OrderSnapshot.initial() {
    return const OrderSnapshot(
      items: [],
      subtotal: 0,
      tax: 0,
      total: 0,
      paymentStatus: 'Waiting',
      note: '',
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
      paymentStatus: map['paymentStatus']?.toString() ?? 'Waiting',
      note: map['note']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'items': items,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'paymentStatus': paymentStatus,
      'note': note,
    };
  }
}
