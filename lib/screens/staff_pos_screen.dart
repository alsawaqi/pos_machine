import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pos_models.dart';
import '../services/sunmi_receipt_service.dart';
import '../state/pos_controller.dart';

class StaffPosScreen extends StatefulWidget {
  const StaffPosScreen({super.key});

  @override
  State<StaffPosScreen> createState() => _StaffPosScreenState();
}

class _StaffPosScreenState extends State<StaffPosScreen> {
  late final PosController controller;

  static const _navItems = <_NavItemData>[
    _NavItemData('Quick Order', Icons.tune_rounded, true),
    _NavItemData('Dine In', Icons.storefront_outlined, false),
    _NavItemData('To Go', Icons.shopping_bag_outlined, false),
    _NavItemData('Delivery', Icons.delivery_dining_outlined, false),
    _NavItemData('Home', Icons.home_outlined, false),
    _NavItemData('Report', Icons.description_outlined, false),
    _NavItemData('History', Icons.history, false),
  ];

  static const _categoryIcons = <String, IconData>{
    'Coffee': Icons.coffee_outlined,
    'Drinks': Icons.local_bar_outlined,
    'Food': Icons.restaurant_outlined,
    'Dessert': Icons.cake_outlined,
    'Bakery': Icons.bakery_dining_outlined,
    'Special': Icons.star_border_rounded,
  };

  @override
  void initState() {
    super.initState();
    controller = PosController();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.init();
      await controller.openRearDisplay();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bg = const Color(0xFFF4F4F4);

        return Scaffold(
          backgroundColor: bg,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth < 1100
                    ? 14.0
                    : 18.0;
                final verticalPadding = constraints.maxHeight < 760
                    ? 12.0
                    : 16.0;
                final gap = constraints.maxWidth < 1100 ? 10.0 : 14.0;

                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  child: Column(
                    children: [
                      _buildTopBar(),
                      SizedBox(height: gap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 34,
                              child: _buildCurrentOrderPanel(),
                            ),
                            SizedBox(width: gap),
                            Expanded(flex: 24, child: _buildCategoriesPanel()),
                            SizedBox(width: gap),
                            Expanded(flex: 42, child: _buildProductsPanel()),
                          ],
                        ),
                      ),
                      SizedBox(height: gap),
                      _buildBottomActions(),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar() {
    return _surface(
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildBrandBlock(),
          const SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _navItems
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _HeaderNavChip(item: item),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(width: 16),
          _buildTimeBlock(),
          const SizedBox(width: 10),
          _topIconButton(Icons.settings_outlined),
          const SizedBox(width: 10),
          _buildProfileBlock(),
        ],
      ),
    );
  }

  Widget _buildBrandBlock() {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Text(
            'MITHQAL 2.0',
            style: TextStyle(
              color: Color(0xFF6B85AD),
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Multiple Payment For One Order',
            style: TextStyle(
              color: Color(0xFFC6C6C6),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBlock() {
    return const SizedBox(
      width: 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '05:38 PM',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D2D2D),
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Mar 15, 2026',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8B8B8B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topIconButton(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(21),
        boxShadow: _softShadow,
      ),
      child: Icon(icon, color: const Color(0xFF6E6E6E), size: 20),
    );
  }

  Widget _buildProfileBlock() {
    return _surface(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F1F1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: Color(0xFF9A9A9A)),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ahmad',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2C2C2C),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manager',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF9B9B9B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrderPanel() {
    final orderRows = _expandedOrderRows();

    return _surface(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Current Order',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202020),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: orderRows.isEmpty
                ? Center(
                    child: Text(
                      'Tap any product to start order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: orderRows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _OrderCard(
                      product: orderRows[index],
                      onAdd: () => controller.addProduct(orderRows[index]),
                      onRemove: () =>
                          controller.decreaseProduct(orderRows[index]),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          _surface(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              children: [
                _summaryRow(
                  'Subtotal',
                  controller.subtotal,
                  const Color(0xFF8C8C8C),
                ),
                const SizedBox(height: 8),
                _summaryRow(
                  'Tax (5%)',
                  controller.tax,
                  const Color(0xFF8C8C8C),
                ),
                const SizedBox(height: 12),
                _summaryRow(
                  'Total',
                  controller.total,
                  const Color(0xFF363636),
                  bold: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(
                child: _PaymentMethodCard(
                  icon: Icons.payments_outlined,
                  title: 'Cash',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _PaymentMethodCard(
                  icon: Icons.credit_card_outlined,
                  title: 'Credit Card',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    return _surface(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categories',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202020),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: controller.categories.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final category = controller.categories[index];
                final selected = category == controller.selectedCategory;
                return _CategoryCard(
                  title: category,
                  icon: _categoryIcons[category] ?? Icons.category_outlined,
                  selected: selected,
                  onTap: () => controller.selectCategory(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsPanel() {
    final products = _displayProducts();

    return _surface(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Products',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF202020),
                  ),
                ),
              ),
              const _TinyToggleChip(
                icon: Icons.format_list_bulleted_rounded,
                label: 'List',
              ),
              const SizedBox(width: 8),
              const _TinyToggleChip(
                icon: Icons.grid_view_rounded,
                label: 'Grid',
                selected: true,
              ),
              const SizedBox(width: 10),
              Container(
                width: 168,
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: _softShadow,
                ),
                child: Row(
                  children: const [
                    Icon(Icons.search, color: Color(0xFF666666), size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Search',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFA0A0A0),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: GridView.builder(
              itemCount: products.length,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 14,
                childAspectRatio: 1.26,
              ),
              itemBuilder: (context, index) {
                final product = products[index];
                return _ProductTile(
                  product: product,
                  imagePath: _productImage(product),
                  onAdd: () => controller.addProduct(product),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return SizedBox(
      height: 108,
      child: Row(
        children: [
          const _FooterActionCard(icon: Icons.pause_rounded, title: 'Save'),
          const SizedBox(width: 12),
          const _FooterActionCard(
            icon: Icons.call_split_rounded,
            title: 'Split',
          ),
          const SizedBox(width: 12),
          const _FooterActionCard(icon: Icons.redeem_outlined, title: 'Gift'),
          const Spacer(),
          SizedBox(
            width: 300,
            child: _surface(
              radius: 22,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: controller.payAndPrint,
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 26,
                        color: Color(0xFF111111),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Procees to Pay',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF222222),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    String title,
    double value,
    Color color, {
    bool bold = false,
  }) {
    final style = TextStyle(
      fontSize: bold ? 18 : 16,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: color,
    );

    return Row(
      children: [
        Expanded(child: Text(title, style: style)),
        Text(SunmiReceiptService.money(value), style: style),
      ],
    );
  }

  List<Product> _displayProducts() {
    final visible = List<Product>.from(controller.visibleProducts);
    if (controller.selectedCategory == 'Coffee' && visible.isNotEmpty) {
      visible.add(visible.first);
    }
    return visible;
  }

  List<Product> _expandedOrderRows() {
    final rows = <Product>[];
    for (final item in controller.cart) {
      for (int i = 0; i < math.max(1, item.qty); i++) {
        rows.add(item.product);
      }
    }
    return rows;
  }

  String _productImage(Product product) {
    switch (product.name) {
      case 'Espresso':
        return 'assets/images/espresso_blue.png';
      case 'Cappuccino':
        return 'assets/images/cappuccino.png';
      case 'Latte':
        return 'assets/images/latte.png';
      case 'Americano':
        return 'assets/images/americano.png';
      default:
        return 'assets/images/espresso_white.png';
    }
  }
}

class _NavItemData {
  final String title;
  final IconData icon;
  final bool selected;

  const _NavItemData(this.title, this.icon, this.selected);
}

class _HeaderNavChip extends StatelessWidget {
  final _NavItemData item;

  const _HeaderNavChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: item.selected
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ]
            : _softShadow,
      ),
      child: Row(
        children: [
          Icon(item.icon, size: 20, color: const Color(0xFF363636)),
          const SizedBox(width: 10),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: item.selected ? FontWeight.w800 : FontWeight.w600,
              color: const Color(0xFF333333),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _OrderCard({
    required this.product,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: _softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              'assets/images/order_item.png',
              width: 84,
              height: 84,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        product.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2A2A2A),
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFF808080),
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Small',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF9C9C9C),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _CounterButton(icon: Icons.remove_rounded, onTap: onRemove),
                    const SizedBox(width: 10),
                    const Text(
                      '1',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF323232),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _CounterButton(icon: Icons.add_rounded, onTap: onAdd),
                    const Spacer(),
                    Text(
                      SunmiReceiptService.money(product.price),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF7D7D7D),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CounterButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: _softShadow,
        ),
        child: Icon(icon, color: const Color(0xFF8A8A8A), size: 20),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? const Color(0xFFDCE8F6) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: _softShadow,
        ),
        child: Row(
          children: [
            Icon(icon, size: 34, color: const Color(0xFF787878)),
            const SizedBox(width: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF303030),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyToggleChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _TinyToggleChip({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: selected
            ? Border.all(color: const Color(0xFFE4E4E4))
            : Border.all(color: Colors.transparent),
        boxShadow: _softShadow,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF3F3F3F)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF444444),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final String imagePath;
  final VoidCallback onAdd;

  const _ProductTile({
    required this.product,
    required this.imagePath,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                imagePath,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF242424),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SunmiReceiptService.money(product.price),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF878787),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(21),
                    boxShadow: _softShadow,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 24,
                    color: Color(0xFF292929),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PaymentMethodCard({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return _surface(
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: const Color(0xFF6C6C6C)),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B2B2B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterActionCard extends StatelessWidget {
  final IconData icon;
  final String title;

  const _FooterActionCard({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: _surface(
        radius: 20,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30, color: const Color(0xFF6A6A6A)),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2A2A2A),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _surface({
  required Widget child,
  double radius = 20,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _softShadow,
    ),
    child: child,
  );
}

const _softShadow = <BoxShadow>[
  BoxShadow(color: Color(0x10000000), blurRadius: 18, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x08FFFFFF), blurRadius: 1, offset: Offset(0, 1)),
];
