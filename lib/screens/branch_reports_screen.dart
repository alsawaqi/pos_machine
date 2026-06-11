import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/branch_report.dart';
import '../providers/providers.dart';
import '../services/sunmi_receipt_service.dart';

/// P-F6 — the BRANCH REPORTS dashboard: a full-screen, branch-scoped,
/// date-filterable analytics view for the staff positions the merchant
/// allows (settings.reports_positions; the POS gates entry). Everything is
/// fetched live from pos_api (`/device/reports/branch`) — reports are an
/// online view by nature. Money is OMR (converted from baisas in the model).
class BranchReportsScreen extends ConsumerStatefulWidget {
  const BranchReportsScreen({super.key, this.branchName = ''});

  final String branchName;

  @override
  ConsumerState<BranchReportsScreen> createState() =>
      _BranchReportsScreenState();
}

enum _RangePreset { today, week, month, custom }

class _BranchReportsScreenState extends ConsumerState<BranchReportsScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF0E1D26);
  static const _card = Color(0xFF16313B);
  static const _cardBorder = Color(0xFF1F4250);
  static const _accent = Color(0xFF35C28B);
  static const _palette = <Color>[
    Color(0xFF35C28B),
    Color(0xFF58AAE2),
    Color(0xFFFFB45D),
    Color(0xFFB07CD8),
    Color(0xFF4DD0C1),
    Color(0xFFFF6B6B),
    Color(0xFFE2C758),
  ];

  _RangePreset _preset = _RangePreset.today;
  late DateTime _from;
  late DateTime _to;
  BranchReport? _report;
  bool _loading = true;
  String? _error;

  // One entrance controller drives the staggered reveal + chart growth.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = _from;
    unawaited(_load());
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(apiServiceProvider)
          .fetchBranchReport(from: _from, to: _to);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
      _entrance.forward(from: 0);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = L10n.of(context).reportsLoadFailed;
      });
    }
  }

  Future<void> _pickPreset(_RangePreset preset) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case _RangePreset.today:
        _from = today;
        _to = today;
      case _RangePreset.week:
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case _RangePreset.month:
        _from = today.subtract(const Duration(days: 29));
        _to = today;
      case _RangePreset.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: today.subtract(const Duration(days: 365)),
          lastDate: today,
          initialDateRange: DateTimeRange(start: _from, end: _to),
          builder: (context, child) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: _accent,
                surface: _card,
              ),
            ),
            child: child!,
          ),
        );
        if (picked == null) return;
        _from = picked.start;
        _to = picked.end;
    }
    setState(() => _preset = preset);
    await _load();
  }

  String _money(double v) => SunmiReceiptService.money(v);

  String _methodLabel(L10n l10n, String method) => switch (method) {
        'cash' => l10n.displayMethodCash,
        'card' => l10n.displayMethodCard,
        'bank_pos' => l10n.displayMethodBankPos,
        'gift' => l10n.displayMethodGift,
        'loyalty' => l10n.reportsMethodLoyalty,
        'split_part' => l10n.displayMethodSplit,
        _ => method,
      };

  String _orderTypeLabel(L10n l10n, String orderType) => switch (orderType) {
        'dine_in' => l10n.displayOrderTypeDineIn,
        'to_go' => l10n.displayOrderTypeToGo,
        'delivery' => l10n.displayOrderTypeDelivery,
        'quick' || 'quick_order' => l10n.displayOrderTypeQuickOrder,
        _ => orderType,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(l10n),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : _error != null
                      ? _buildError(l10n)
                      : _buildDashboard(l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(L10n l10n) {
    final rangeLabel =
        _from == _to ? _date(_from) : '${_date(_from)} → ${_date(_to)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.insights_rounded, color: _accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.reportsTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  widget.branchName.isEmpty
                      ? rangeLabel
                      : '${widget.branchName}  ·  $rangeLabel',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _rangeChip(l10n.reportsRangeToday, _RangePreset.today),
          _rangeChip(l10n.reportsRange7d, _RangePreset.week),
          _rangeChip(l10n.reportsRange30d, _RangePreset.month),
          _rangeChip(l10n.reportsRangeCustom, _RangePreset.custom,
              icon: Icons.calendar_month_rounded),
        ],
      ),
    );
  }

  Widget _rangeChip(String label, _RangePreset preset, {IconData? icon}) {
    final selected = _preset == preset;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: ChoiceChip(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15, color: selected ? Colors.white : Colors.white70),
              const SizedBox(width: 4),
            ],
            Text(label),
          ],
        ),
        selected: selected,
        onSelected: (_) => unawaited(_pickPreset(preset)),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        selectedColor: _accent,
        backgroundColor: _card,
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
    );
  }

  Widget _buildError(L10n l10n) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 42),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => unawaited(_load()),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n.reportsRetry),
            ),
          ],
        ),
      );

  Widget _buildDashboard(L10n l10n) {
    final report = _report!;
    final s = report.summary;
    var revealIndex = 0;

    Widget reveal(Widget child) => _Reveal(
          animation: _entrance,
          index: revealIndex++,
          child: child,
        );

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        children: [
          // ---- KPI cards -------------------------------------------------
          reveal(Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _KpiCard(
                icon: Icons.payments_rounded,
                color: _accent,
                label: l10n.reportsKpiGross,
                value: _money(s.gross),
              ),
              _KpiCard(
                icon: Icons.receipt_long_rounded,
                color: const Color(0xFF58AAE2),
                label: l10n.reportsKpiOrders,
                value: '${s.orders}',
              ),
              _KpiCard(
                icon: Icons.straighten_rounded,
                color: const Color(0xFFE2C758),
                label: l10n.reportsKpiAvgOrder,
                value: _money(s.avgOrder),
              ),
              _KpiCard(
                icon: Icons.account_balance_wallet_rounded,
                color: const Color(0xFF4DD0C1),
                label: l10n.reportsKpiTax,
                value: _money(s.tax),
              ),
              _KpiCard(
                icon: Icons.percent_rounded,
                color: const Color(0xFFFFB45D),
                label: l10n.reportsKpiDiscounts,
                value: _money(s.discount),
              ),
              _KpiCard(
                icon: Icons.volunteer_activism_rounded,
                color: const Color(0xFFB07CD8),
                label: l10n.reportsKpiCompsGifts,
                value: _money(s.comp + s.gift),
              ),
              _KpiCard(
                icon: Icons.people_alt_rounded,
                color: const Color(0xFFFF8FAB),
                label: l10n.reportsKpiCustomers,
                value: '${s.distinctCustomers}',
              ),
              _KpiCard(
                icon: Icons.stars_rounded,
                color: const Color(0xFFE2C758),
                label: l10n.reportsKpiPointsRedeemed,
                value: '${s.loyaltyPointsRedeemed}',
              ),
            ],
          )),
          const SizedBox(height: 16),

          // ---- Sales by day + by hour ------------------------------------
          reveal(_twoUp(
            _SectionCard(
              title: l10n.reportsSalesByDay,
              icon: Icons.bar_chart_rounded,
              child: SizedBox(
                height: 220,
                child: report.byDay.isEmpty
                    ? _EmptyNote(l10n.reportsNoData)
                    : _DailyBars(
                        points: report.byDay, animation: _entrance),
              ),
            ),
            _SectionCard(
              title: l10n.reportsSalesByHour,
              icon: Icons.schedule_rounded,
              child: SizedBox(
                height: 220,
                child: report.byHour.isEmpty
                    ? _EmptyNote(l10n.reportsNoData)
                    : _HourlyLine(
                        points: report.byHour, animation: _entrance),
              ),
            ),
          )),
          const SizedBox(height: 12),

          // ---- Tender mix + order types ----------------------------------
          reveal(_twoUp(
            _SectionCard(
              title: l10n.reportsTenderMix,
              icon: Icons.credit_card_rounded,
              child: SizedBox(
                height: 200,
                child: report.byMethod.isEmpty
                    ? _EmptyNote(l10n.reportsNoData)
                    : _Donut(
                        animation: _entrance,
                        slices: [
                          for (var i = 0; i < report.byMethod.length; i++)
                            (
                              label: _methodLabel(
                                  l10n, report.byMethod[i].method),
                              value: report.byMethod[i].total,
                              color: _palette[i % _palette.length],
                            ),
                        ],
                        money: _money,
                      ),
              ),
            ),
            _SectionCard(
              title: l10n.reportsOrderTypes,
              icon: Icons.dashboard_customize_rounded,
              child: SizedBox(
                height: 200,
                child: report.byOrderType.isEmpty
                    ? _EmptyNote(l10n.reportsNoData)
                    : _Donut(
                        animation: _entrance,
                        slices: [
                          for (var i = 0;
                              i < report.byOrderType.length;
                              i++)
                            (
                              label: _orderTypeLabel(
                                  l10n, report.byOrderType[i].orderType),
                              value: report.byOrderType[i].total,
                              color: _palette[(i + 1) % _palette.length],
                            ),
                        ],
                        money: _money,
                      ),
              ),
            ),
          )),
          const SizedBox(height: 12),

          // ---- Top products + stock consumption --------------------------
          reveal(_twoUp(
            _SectionCard(
              title: l10n.reportsTopProducts,
              icon: Icons.local_cafe_rounded,
              child: report.topProducts.isEmpty
                  ? _EmptyNote(l10n.reportsNoData)
                  : _RankList(
                      animation: _entrance,
                      rows: [
                        for (final p in report.topProducts)
                          (
                            label: p.name,
                            sub: l10n.reportsQtyTimes(_trim(p.qty)),
                            value: p.total,
                            display: _money(p.total),
                          ),
                      ],
                      color: _accent,
                    ),
            ),
            _SectionCard(
              title: l10n.reportsStockConsumption,
              icon: Icons.inventory_2_rounded,
              child: report.stockConsumption.isEmpty
                  ? _EmptyNote(l10n.reportsNoData)
                  : _RankList(
                      animation: _entrance,
                      rows: [
                        for (final c in report.stockConsumption)
                          (
                            label: c.name,
                            sub: c.unit,
                            value: c.qty,
                            display: '${_trim(c.qty)} ${c.unit}',
                          ),
                      ],
                      color: const Color(0xFF58AAE2),
                    ),
            ),
          )),
          const SizedBox(height: 12),

          // ---- Loyalty + customers + discounts ---------------------------
          reveal(_twoUp(
            _SectionCard(
              title: l10n.reportsLoyalty,
              icon: Icons.stars_rounded,
              child: Column(
                children: [
                  _statRow(l10n.reportsPointsEarned,
                      '${s.loyaltyPointsEarned}', const Color(0xFF35C28B)),
                  _statRow(l10n.reportsPointsRedeemed,
                      '${s.loyaltyPointsRedeemed}', const Color(0xFFFFB45D)),
                  _statRow(l10n.reportsStampsEarned,
                      '${s.loyaltyStampsEarned}', const Color(0xFF58AAE2)),
                  _statRow(l10n.reportsStampsRedeemed,
                      '${s.loyaltyStampsRedeemed}', const Color(0xFFB07CD8)),
                ],
              ),
            ),
            _SectionCard(
              title: l10n.reportsTopCustomers,
              icon: Icons.emoji_events_rounded,
              child: report.topCustomers.isEmpty
                  ? _EmptyNote(l10n.reportsNoData)
                  : _RankList(
                      animation: _entrance,
                      rows: [
                        for (final c in report.topCustomers)
                          (
                            label: c.name,
                            sub: l10n.reportsOrdersCount(c.orders),
                            value: c.total,
                            display: _money(c.total),
                          ),
                      ],
                      color: const Color(0xFFB07CD8),
                    ),
            ),
          )),
          const SizedBox(height: 12),

          reveal(_SectionCard(
            title: l10n.reportsDiscounts,
            icon: Icons.percent_rounded,
            child: report.discounts.isEmpty
                ? _EmptyNote(l10n.reportsNoData)
                : _RankList(
                    animation: _entrance,
                    rows: [
                      for (final d in report.discounts)
                        (
                          label: d.name,
                          sub: l10n.reportsTimesUsed(d.count),
                          value: d.amount,
                          display: _money(d.amount),
                        ),
                    ],
                    color: const Color(0xFFFFB45D),
                  ),
          )),
        ],
      ),
    );
  }

  Widget _twoUp(Widget left, Widget right) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );

  Widget _statRow(String label, String value, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);
}

// ---------------------------------------------------------------------------
// Building blocks
// ---------------------------------------------------------------------------

/// Staggered entrance: each indexed child fades + slides up as the shared
/// controller plays.
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.animation,
    required this.index,
    required this.child,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = (index * 0.12).clamp(0.0, 0.6);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - curved.value)),
          child: child,
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 196,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _BranchReportsScreenState._card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _BranchReportsScreenState._cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _BranchReportsScreenState._card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _BranchReportsScreenState._cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: _BranchReportsScreenState._accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white38, fontSize: 13),
          ),
        ),
      );
}

/// Sales-by-day bars; values grow with the entrance animation.
class _DailyBars extends StatelessWidget {
  const _DailyBars({required this.points, required this.animation});

  final List<DayPoint> points;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final maxY =
        points.fold(0.0, (m, p) => math.max(m, p.total)).clamp(0.001, 1e12);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return BarChart(
          BarChartData(
            maxY: maxY * 1.15,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => const FlLine(
                color: Color(0xFF1F4250),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= points.length) {
                      return const SizedBox.shrink();
                    }
                    // Show ~6 labels max (day-of-month).
                    final every = (points.length / 6).ceil().clamp(1, 31);
                    if (i % every != 0) return const SizedBox.shrink();
                    final day = points[i].date.length >= 10
                        ? points[i].date.substring(8, 10)
                        : points[i].date;
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        day,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0B161D),
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                  '${points[group.x].date}\n'
                  '${SunmiReceiptService.money(points[group.x].total)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            barGroups: [
              for (var i = 0; i < points.length; i++)
                BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: points[i].total * t,
                      width: math.max(
                          4, 180 / math.max(points.length, 1)).toDouble(),
                      borderRadius: BorderRadius.circular(4),
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF1E8D54), Color(0xFF35C28B)],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Sales-by-hour curve; sweeps in with the entrance animation.
class _HourlyLine extends StatelessWidget {
  const _HourlyLine({required this.points, required this.animation});

  final List<HourPoint> points;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    // Zero-fill the 24 hours so the curve spans the day.
    final byHour = {for (final p in points) p.hour: p.total};
    final values = [for (var h = 0; h < 24; h++) byHour[h] ?? 0.0];
    final maxY = values.fold(0.0, math.max).clamp(0.001, 1e12);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY * 1.15,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (v) => const FlLine(
                color: Color(0xFF1F4250),
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: 4,
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${value.toInt()}:00',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => const Color(0xFF0B161D),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                curveSmoothness: 0.3,
                barWidth: 3,
                color: const Color(0xFF58AAE2),
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF58AAE2).withValues(alpha: 0.30),
                      const Color(0xFF58AAE2).withValues(alpha: 0.02),
                    ],
                  ),
                ),
                spots: [
                  for (var h = 0; h < 24; h++)
                    FlSpot(h.toDouble(), values[h] * t),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Donut chart + legend (tender mix / order types).
class _Donut extends StatelessWidget {
  const _Donut({
    required this.slices,
    required this.animation,
    required this.money,
  });

  final List<({String label, double value, Color color})> slices;
  final Animation<double> animation;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold(0.0, (s, e) => s + e.value);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Row(
          children: [
            SizedBox(
              width: 150,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 34 + 8 * (1 - t),
                  startDegreeOffset: -90 + 60 * (1 - t),
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(
                        value: math.max(s.value, 0.0001),
                        color: s.color.withValues(alpha: 0.55 + 0.45 * t),
                        radius: 26 + 8 * t,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final s in slices)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            total <= 0
                                ? money(s.value)
                                : '${money(s.value)} · ${(s.value / total * 100).toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Ranked rows with animated proportion bars (top products / customers /
/// discounts / stock consumption).
class _RankList extends StatelessWidget {
  const _RankList({
    required this.rows,
    required this.animation,
    required this.color,
  });

  final List<({String label, String sub, double value, String display})> rows;
  final Animation<double> animation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxValue =
        rows.fold(0.0, (m, r) => math.max(m, r.value)).clamp(0.001, 1e12);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(animation.value);
        return Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (r.sub.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsetsDirectional.only(end: 8),
                            child: Text(
                              r.sub,
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        Text(
                          r.display,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (r.value / maxValue) * t,
                        minHeight: 5,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
