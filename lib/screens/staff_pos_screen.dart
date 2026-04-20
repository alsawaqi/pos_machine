import 'dart:async';
import 'dart:ui';

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
  late DateTime _now;
  Timer? _clockTimer;

  static const double _designWidth = 1600;
  static const double _designHeight = 900;
  static const double _topBarHeight = 104;
  static const double _bottomBarHeight = 120;
  static const double _panelGap = 16;
  static const double _middlePanelWidth = 284;
  static const double _productsPanelWidth = 624;

  static const _navItems = <_NavItemData>[
    _NavItemData('Quick Order', Icons.tune_rounded, true),
    _NavItemData('Dine In', Icons.storefront_outlined, false),
    _NavItemData('To Go', Icons.shopping_bag_outlined, false),
    _NavItemData('Delivery', Icons.delivery_dining_outlined, false),
    _NavItemData('Home', Icons.home_outlined, false),
    _NavItemData('Report', Icons.description_outlined, false),
    _NavItemData('History', Icons.history_rounded, false),
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
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await controller.init();
      await controller.openRearDisplay();
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    unawaited(controller.shutdown());
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF12232B),
          body: Stack(
            children: [
              Positioned.fill(child: _BackgroundScene()),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.34),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final outerPadding = constraints.maxWidth < 1400
                        ? 10.0
                        : 16.0;
                    final availableWidth =
                        constraints.maxWidth - (outerPadding * 2);
                    final availableHeight =
                        constraints.maxHeight - (outerPadding * 2);
                    final contentHeight =
                        _designHeight -
                        _topBarHeight -
                        _bottomBarHeight -
                        (_panelGap * 2);

                    return Padding(
                      padding: EdgeInsets.all(outerPadding),
                      child: SizedBox(
                        width: availableWidth,
                        height: availableHeight,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: _designWidth,
                            height: _designHeight,
                            child: Column(
                              children: [
                                SizedBox(
                                  height: _topBarHeight,
                                  child: _buildTopBar(),
                                ),
                                const SizedBox(height: _panelGap),
                                SizedBox(
                                  height: contentHeight,
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _buildCurrentOrderPanel(),
                                      ),
                                      const SizedBox(width: _panelGap),
                                      SizedBox(
                                        width: _middlePanelWidth,
                                        child: _buildCategoriesPanel(),
                                      ),
                                      const SizedBox(width: _panelGap),
                                      SizedBox(
                                        width: _productsPanelWidth,
                                        child: _buildProductsPanel(),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: _panelGap),
                                SizedBox(
                                  height: _bottomBarHeight,
                                  child: _buildBottomBar(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handlePay() async {
    final message = await controller.payAndPrint();
    if (!mounted || message == null || message.isEmpty) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildTopBar() {
    return _glassPanel(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
          const SizedBox(width: 12),
          _buildTimeBlock(),
          const SizedBox(width: 12),
          _CircleGlassButton(icon: Icons.settings_outlined, onTap: () {}),
          const SizedBox(width: 10),
          _buildProfileBlock(),
        ],
      ),
    );
  }

  Widget _buildBrandBlock() {
    return Container(
      width: 170,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: _chipDecoration(selected: false),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'MITHQAL 2.0',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF65789C),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Better ordering',
              maxLines: 1,
              style: TextStyle(
                color: Color(0xFF9EA7B0),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeBlock() {
    return SizedBox(
      width: 118,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatTime(_now),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF20252A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDate(_now),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4D555D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: _chipDecoration(selected: false),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 36,
              height: 36,
              child: Image.asset(
                'assets/images/staff_avatar.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFE6EBF0), Color(0xFFC7D2DA)],
                      ),
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF5A6772),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ahmad',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF21262C),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Manager',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4F5860),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentOrderPanel() {
    return _glassPanel(
      tint: const Color(0xCCB9F1F4),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      'Current Order',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16252A),
                      ),
                    ),
                    Text(
                      'Ticket #1450',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF24353B).withValues(alpha: 0.96),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _OutlinePillButton(
                icon: Icons.delete_outline_rounded,
                label: 'Clear Cart',
                onTap: controller.clearForNextOrder,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: controller.cart.isEmpty
                ? const _EmptyOrderState()
                : Scrollbar(
                    thumbVisibility: controller.cart.length > 3,
                    child: ListView.separated(
                      itemCount: controller.cart.length,
                      physics: const BouncingScrollPhysics(),
                      separatorBuilder: (_, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = controller.cart[index];
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          switchInCurve: Curves.easeOutBack,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.04, 0.08),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: _OrderItemCard(
                            key: ValueKey(
                              '${item.product.id}_${item.qty}_${item.lineTotal}',
                            ),
                            item: item,
                            onAdd: () => controller.addProduct(item.product),
                            onRemove: () =>
                                controller.decreaseProduct(item.product),
                            onDelete: () =>
                                controller.removeProduct(item.product),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _glassInsetCard(
            child: Column(
              children: [
                _summaryRow('Subtotal', controller.subtotal),
                const SizedBox(height: 6),
                _summaryRow('Tax (5%)', controller.tax),
                const SizedBox(height: 6),
                _summaryRow('Total', controller.total, emphasize: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Order Management',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF15242A),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: const [
              Expanded(
                child: _ActionSquareCard(
                  icon: Icons.pause_circle_outline_rounded,
                  title: 'HOLD ORDER',
                  tint: Color(0xFFFFD7A4),
                  iconColor: Color(0xFFA56A15),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _ActionSquareCard(
                  icon: Icons.close_rounded,
                  title: 'VOID ORDER',
                  tint: Color(0xFFC52720),
                  foreground: Colors.white,
                  iconColor: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _ActionSquareCard(
                  icon: Icons.alt_route_rounded,
                  title: 'SPLIT BILL',
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _ActionSquareCard(
                  icon: Icons.redeem_outlined,
                  title: 'GIFT',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _PaymentMethodCard(
                  icon: Icons.payments_outlined,
                  title: 'Cash',
                  selected: controller.selectedPaymentMethod == 'Cash',
                  onTap: () => controller.selectPaymentMethod('Cash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PaymentMethodCard(
                  icon: Icons.credit_card_outlined,
                  title: 'Credit Card',
                  selected: controller.selectedPaymentMethod == 'Credit Card',
                  onTap: () => controller.selectPaymentMethod('Credit Card'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesPanel() {
    return _glassPanel(
      padding: const EdgeInsets.all(16),
      tint: const Color(0x1CFFFFFF),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.20),
          Colors.white.withValues(alpha: 0.08),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Categories',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF131C24),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.separated(
              itemCount: controller.categories.length,
              physics: const BouncingScrollPhysics(),
              separatorBuilder: (_, index) => const SizedBox(height: 10),
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
    final products = controller.visibleProducts;

    return _glassPanel(
      padding: const EdgeInsets.all(14),
      tint: const Color(0x18FFFFFF),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.06),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Products',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF131C24),
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
              _SearchPill(width: 176, hint: 'Search', onTap: () {}),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth < 520 ? 1 : 2;
                return GridView.builder(
                  itemCount: products.length,
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: constraints.maxWidth < 520 ? 1.36 : 1.56,
                  ),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductTile(
                      product: product,
                      onAdd: () => controller.addProduct(product),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final cashAmount = controller.selectedPaymentMethod == 'Cash'
        ? controller.total
        : 0.0;
    final cardAmount = controller.selectedPaymentMethod == 'Credit Card'
        ? controller.total
        : 0.0;

    return _glassPanel(
      height: 120,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const _FooterActionCard(
            icon: Icons.print_outlined,
            title: 'REPRINT LAST',
          ),
          const SizedBox(width: 12),
          const _FooterActionCard(icon: Icons.tune_rounded, title: 'REPRINT'),
          const SizedBox(width: 12),
          const _FooterActionCard(
            icon: Icons.person_outline_rounded,
            title: 'MANAGER',
          ),
          const Spacer(),
          _BottomAmountCard(title: 'CASH', amount: cashAmount),
          const SizedBox(width: 12),
          _BottomAmountCard(title: 'CARD', amount: cardAmount),
          const SizedBox(width: 12),
          Expanded(
            child: _PayButton(
              total: controller.total,
              busy: controller.isProcessingPayment,
              onTap: () {
                unawaited(_handlePay());
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String title, double value, {bool emphasize = false}) {
    final style = TextStyle(
      fontSize: emphasize ? 15 : 13,
      fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
      color: emphasize ? const Color(0xFF16252A) : const Color(0xFF284149),
    );

    return Row(
      children: [
        Expanded(child: Text(title, style: style)),
        Text(SunmiReceiptService.money(value), style: style),
      ],
    );
  }

  String _formatTime(DateTime value) {
    final hour = value.hour == 0
        ? 12
        : (value.hour > 12 ? value.hour - 12 : value.hour);
    final minute = value.minute.toString().padLeft(2, '0');
    final meridiem = value.hour >= 12 ? 'PM' : 'AM';
    return '${hour.toString().padLeft(2, '0')}:$minute $meridiem';
  }

  String _formatDate(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${months[value.month - 1]} ${value.day}, ${value.year}';
  }
}

class _NavItemData {
  final String title;
  final IconData icon;
  final bool selected;

  const _NavItemData(this.title, this.icon, this.selected);
}

class _BackgroundScene extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Image.asset(
            'assets/images/front_pos_background.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF182830),
                      Color(0xFF2B3132),
                      Color(0xFF6A5444),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.25, -0.55),
              radius: 1.1,
              colors: [
                Colors.white.withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderNavChip extends StatelessWidget {
  final _NavItemData item;

  const _HeaderNavChip({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: _chipDecoration(selected: item.selected),
      child: Row(
        children: [
          Icon(item.icon, size: 18, color: const Color(0xFF242B31)),
          const SizedBox(width: 8),
          Text(
            item.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: item.selected ? FontWeight.w800 : FontWeight.w700,
              color: const Color(0xFF252C31),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: _chipDecoration(selected: false),
        child: Icon(icon, color: const Color(0xFF2A3136)),
      ),
    );
  }
}

class _OutlinePillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlinePillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF516068)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E3E46),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.receipt_long_rounded,
                  size: 34,
                  color: Color(0xFF35505A),
                ),
                SizedBox(height: 8),
                Text(
                  'Tap any product to start the order',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A3F48),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'The cart, actions, and totals will appear here.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4A5E68),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderItemCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onDelete;

  const _OrderItemCard({
    super.key,
    required this.item,
    required this.onAdd,
    required this.onRemove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: _softShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductArtwork(
            imageAsset: item.product.imageAsset,
            width: 84,
            height: 84,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.product.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF19262E),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFF5A6871),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Small',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4F6069),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: const [
                    _TinyOrderAction(label: 'EDIT', icon: Icons.edit_outlined),
                    _TinyOrderAction(
                      label: 'DISC. %',
                      icon: Icons.percent_rounded,
                    ),
                    _TinyOrderAction(
                      label: 'REPEAT',
                      icon: Icons.repeat_rounded,
                    ),
                    _TinyOrderAction(
                      label: 'VOID',
                      icon: Icons.remove_shopping_cart_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _CounterButton(icon: Icons.remove_rounded, onTap: onRemove),
                    const SizedBox(width: 8),
                    Container(
                      width: 24,
                      alignment: Alignment.center,
                      child: Text(
                        '${item.qty}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1C2730),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _CounterButton(icon: Icons.add_rounded, onTap: onAdd),
                    const Spacer(),
                    Text(
                      SunmiReceiptService.money(item.lineTotal),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1C2C34),
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

class _TinyOrderAction extends StatelessWidget {
  final String label;
  final IconData icon;

  const _TinyOrderAction({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF24333A),
          ),
        ),
        const SizedBox(width: 3),
        Icon(icon, size: 12, color: const Color(0xFF495760)),
      ],
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
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6F8),
          borderRadius: BorderRadius.circular(16),
          boxShadow: _softShadow,
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF2E3D45)),
      ),
    );
  }
}

class _ActionSquareCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color tint;
  final Color foreground;
  final Color iconColor;

  const _ActionSquareCard({
    required this.icon,
    required this.title,
    this.tint = const Color(0xFFE8F3F5),
    this.foreground = const Color(0xFF102028),
    this.iconColor = const Color(0xFF203038),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.65),
          width: 1.2,
        ),
        boxShadow: _softShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(height: 3),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: foreground,
            ),
          ),
        ],
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xA854AFBB)
                  : Colors.white.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.32),
                width: 1.2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x18FFFFFF),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
                BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 18,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: selected ? Colors.white : const Color(0xFF202B31),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : const Color(0xFF202B31),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: _chipDecoration(selected: selected),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF202B31)),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202B31),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  final double width;
  final String hint;
  final VoidCallback onTap;

  const _SearchPill({
    required this.width,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: width,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: _chipDecoration(selected: false),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Color(0xFF283038)),
            const SizedBox(width: 10),
            Text(
              hint,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF5B6770),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback onAdd;

  const _ProductTile({required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.90),
          width: 1.2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22FFFFFF),
            blurRadius: 2,
            offset: Offset(0, -1),
          ),
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _ProductArtwork(
                imageAsset: product.imageAsset,
                width: double.infinity,
                height: 104,
              ),
              if (product.lowStock)
                Positioned(
                  top: 8,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC84C),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Color(0xFF24211B),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'LOW STOCK',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF24211B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF17232B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      SunmiReceiptService.money(product.price),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF34454E),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBFC),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _softShadow,
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    size: 22,
                    color: Color(0xFF1E2C33),
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

class _ProductArtwork extends StatelessWidget {
  final String? imageAsset;
  final double width;
  final double height;

  const _ProductArtwork({
    required this.imageAsset,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        color: const Color(0xFF243640),
        child: imageAsset == null
            ? _placeholderArtwork()
            : Image.asset(
                imageAsset!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _placeholderArtwork();
                },
              ),
      ),
    );
  }

  Widget _placeholderArtwork() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF324C57), Color(0xFF111D24)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.white70, size: 30),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF78B7C2)
                : Colors.white.withValues(alpha: 0.62),
            width: 1.3,
          ),
          boxShadow: _softShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: const Color(0xFF213139)),
            const SizedBox(height: 5),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1B2A32),
              ),
            ),
          ],
        ),
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
    return Container(
      width: 142,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
        boxShadow: _softShadow,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: const Color(0xFF223038)),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF14212A),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomAmountCard extends StatelessWidget {
  final String title;
  final double amount;

  const _BottomAmountCard({required this.title, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0C6D8A), Color(0xFF0F4960)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: _softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            SunmiReceiptService.money(amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  final double total;
  final bool busy;
  final VoidCallback onTap;

  const _PayButton({
    required this.total,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: busy
                ? const [Color(0xFF5E8995), Color(0xFF48656F)]
                : const [Color(0xFF0B6D8A), Color(0xFF0F5167)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: _softShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                busy
                    ? Icons.hourglass_top_rounded
                    : Icons.account_balance_wallet_outlined,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy ? 'Processing Payment' : 'Process to Pay',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    busy
                        ? 'Completing order'
                        : 'PAY ${SunmiReceiptService.money(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _glassPanel({
  required Widget child,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  double? height,
  Color tint = const Color(0x66FFFFFF),
  Gradient? gradient,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: gradient == null ? tint : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withValues(alpha: 0.32)),
          boxShadow: _softShadow,
        ),
        child: child,
      ),
    ),
  );
}

Widget _glassInsetCard({required Widget child}) {
  return Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: 0.66)),
      boxShadow: _softShadow,
    ),
    child: child,
  );
}

BoxDecoration _chipDecoration({required bool selected}) {
  return BoxDecoration(
    color: selected
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.68),
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: Colors.white.withValues(alpha: selected ? 0.88 : 0.62),
      width: 1.1,
    ),
    boxShadow: _softShadow,
  );
}

const _softShadow = <BoxShadow>[
  BoxShadow(color: Color(0x19000000), blurRadius: 22, offset: Offset(0, 12)),
  BoxShadow(color: Color(0x14FFFFFF), blurRadius: 1, offset: Offset(0, 1)),
];
