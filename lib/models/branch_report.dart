/// P-F6 — the branch report bundle from GET /device/reports/branch.
/// Money arrives as integer BAISAS and is converted to OMR doubles here
/// (display-only — nothing is pushed back). All sections are branch-scoped
/// server-side; absent/sparse sections decode to empty lists / zeros.
library;

double _omr(dynamic v) => ((v as num?)?.toDouble() ?? 0) / 1000.0;
int _int(dynamic v) => (v as num?)?.toInt() ?? 0;
double _num(dynamic v) => (v as num?)?.toDouble() ?? 0;
String _str(dynamic v) => v?.toString() ?? '';

List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) decode) =>
    ((v as List?) ?? const [])
        .whereType<Map>()
        .map((m) => decode(m.cast<String, dynamic>()))
        .toList();

class BranchReport {
  final String from;
  final String to;
  final BranchReportSummary summary;
  final List<DayPoint> byDay;
  final List<HourPoint> byHour;
  final List<MethodSlice> byMethod;
  final List<OrderTypeSlice> byOrderType;
  final List<TopProduct> topProducts;
  final List<TopCustomer> topCustomers;
  final List<DiscountLine> discounts;
  final List<ConsumptionLine> stockConsumption;

  const BranchReport({
    required this.from,
    required this.to,
    required this.summary,
    this.byDay = const [],
    this.byHour = const [],
    this.byMethod = const [],
    this.byOrderType = const [],
    this.topProducts = const [],
    this.topCustomers = const [],
    this.discounts = const [],
    this.stockConsumption = const [],
  });

  factory BranchReport.fromJson(Map<String, dynamic> j) => BranchReport(
        from: _str(j['from']),
        to: _str(j['to']),
        summary: BranchReportSummary.fromJson(
            (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
        byDay: _list(j['by_day'], DayPoint.fromJson),
        byHour: _list(j['by_hour'], HourPoint.fromJson),
        byMethod: _list(j['by_method'], MethodSlice.fromJson),
        byOrderType: _list(j['by_order_type'], OrderTypeSlice.fromJson),
        topProducts: _list(j['top_products'], TopProduct.fromJson),
        topCustomers: _list(j['top_customers'], TopCustomer.fromJson),
        discounts: _list(j['discounts'], DiscountLine.fromJson),
        stockConsumption:
            _list(j['stock_consumption'], ConsumptionLine.fromJson),
      );

  bool get isEmpty => summary.orders == 0;
}

class BranchReportSummary {
  final int orders;
  final double gross;
  final double discount;
  final double comp;
  final double gift;
  final double tax;
  final double avgOrder;
  final int distinctCustomers;
  final int loyaltyPointsEarned;
  final int loyaltyPointsRedeemed;
  final int loyaltyStampsEarned;
  final int loyaltyStampsRedeemed;

  const BranchReportSummary({
    this.orders = 0,
    this.gross = 0,
    this.discount = 0,
    this.comp = 0,
    this.gift = 0,
    this.tax = 0,
    this.avgOrder = 0,
    this.distinctCustomers = 0,
    this.loyaltyPointsEarned = 0,
    this.loyaltyPointsRedeemed = 0,
    this.loyaltyStampsEarned = 0,
    this.loyaltyStampsRedeemed = 0,
  });

  factory BranchReportSummary.fromJson(Map<String, dynamic> j) =>
      BranchReportSummary(
        orders: _int(j['orders']),
        gross: _omr(j['gross_baisas']),
        discount: _omr(j['discount_baisas']),
        comp: _omr(j['comp_baisas']),
        gift: _omr(j['gift_baisas']),
        tax: _omr(j['tax_baisas']),
        avgOrder: _omr(j['avg_order_baisas']),
        distinctCustomers: _int(j['distinct_customers']),
        loyaltyPointsEarned: _int(j['loyalty_points_earned']),
        loyaltyPointsRedeemed: _int(j['loyalty_points_redeemed']),
        loyaltyStampsEarned: _int(j['loyalty_stamps_earned']),
        loyaltyStampsRedeemed: _int(j['loyalty_stamps_redeemed']),
      );
}

class DayPoint {
  final String date; // YYYY-MM-DD
  final double total;
  final int orders;
  const DayPoint({required this.date, this.total = 0, this.orders = 0});
  factory DayPoint.fromJson(Map<String, dynamic> j) => DayPoint(
      date: _str(j['date']), total: _omr(j['total_baisas']), orders: _int(j['orders']));
}

class HourPoint {
  final int hour; // 0-23
  final double total;
  final int orders;
  const HourPoint({required this.hour, this.total = 0, this.orders = 0});
  factory HourPoint.fromJson(Map<String, dynamic> j) => HourPoint(
      hour: _int(j['hour']), total: _omr(j['total_baisas']), orders: _int(j['orders']));
}

class MethodSlice {
  final String method; // raw wire method (cash / card / bank_pos / gift / …)
  final double total;
  final int count;
  const MethodSlice({required this.method, this.total = 0, this.count = 0});
  factory MethodSlice.fromJson(Map<String, dynamic> j) => MethodSlice(
      method: _str(j['method']), total: _omr(j['total_baisas']), count: _int(j['count']));
}

class OrderTypeSlice {
  final String orderType;
  final double total;
  final int count;
  const OrderTypeSlice({required this.orderType, this.total = 0, this.count = 0});
  factory OrderTypeSlice.fromJson(Map<String, dynamic> j) => OrderTypeSlice(
      orderType: _str(j['order_type']),
      total: _omr(j['total_baisas']),
      count: _int(j['count']));
}

class TopProduct {
  final String name;
  final double qty;
  final double total;
  const TopProduct({required this.name, this.qty = 0, this.total = 0});
  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
      name: _str(j['name']), qty: _num(j['qty']), total: _omr(j['total_baisas']));
}

class TopCustomer {
  final String name;
  final int orders;
  final double total;
  const TopCustomer({required this.name, this.orders = 0, this.total = 0});
  factory TopCustomer.fromJson(Map<String, dynamic> j) => TopCustomer(
      name: _str(j['name']), orders: _int(j['orders']), total: _omr(j['total_baisas']));
}

class DiscountLine {
  final String name;
  final double amount;
  final int count;
  const DiscountLine({required this.name, this.amount = 0, this.count = 0});
  factory DiscountLine.fromJson(Map<String, dynamic> j) => DiscountLine(
      name: _str(j['name']), amount: _omr(j['amount_baisas']), count: _int(j['count']));
}

class ConsumptionLine {
  final String name;
  final double qty;
  final String unit;
  const ConsumptionLine({required this.name, this.qty = 0, this.unit = ''});
  factory ConsumptionLine.fromJson(Map<String, dynamic> j) => ConsumptionLine(
      name: _str(j['name']), qty: _num(j['qty']), unit: _str(j['unit']));
}
