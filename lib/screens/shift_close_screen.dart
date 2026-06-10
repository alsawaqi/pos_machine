import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/local_order_storage_service.dart';
import '../services/shift_payload.dart';
import '../services/shift_service.dart';
import '../services/shift_summary.dart';
import '../services/sunmi_receipt_service.dart';

/// Close the device's open cash-drawer shift: the cashier counts the drawer,
/// the server computes expected cash (opening + cash sales on this device) and
/// the variance, then the result is shown and the shift cleared. Pushed over
/// the POS; on Done the gate returns to the open-shift screen.
class ShiftCloseScreen extends ConsumerStatefulWidget {
  const ShiftCloseScreen({super.key});

  @override
  ConsumerState<ShiftCloseScreen> createState() => _ShiftCloseScreenState();
}

class _ShiftCloseScreenState extends ConsumerState<ShiftCloseScreen> {
  int _closingBaisas = 0;
  bool _busy = false;
  String? _error;
  ShiftCloseResult? _result;

  static String _money(int baisas) {
    final omr = baisas / 1000;
    final sign = baisas < 0 ? '-' : '';
    return '$sign${omr.abs().toStringAsFixed(3)}';
  }

  void _tap(String digit) {
    if (_busy) return;
    final next = _closingBaisas * 10 + int.parse(digit);
    if (next > 9999999999) return;
    setState(() {
      _closingBaisas = next;
      _error = null;
    });
  }

  void _backspace() {
    if (_busy || _closingBaisas == 0) return;
    setState(() => _closingBaisas ~/= 10);
  }

  ShiftSummaryTicket? _ticket;

  Future<void> _close() async {
    final shift = ref.read(sessionControllerProvider).openShift;
    if (shift == null) {
      setState(() => _error = 'No open shift on this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(shiftServiceProvider).close(
            shiftUuid: shift.uuid,
            closingCashBaisas: _closingBaisas,
          );
      // Phase C6 — assemble the Z-report: server numbers when present (same
      // transaction as the close), the device-local fold as the fallback.
      final closedAt = DateTime.now();
      var summary = ShiftSalesSummary.fromServerResult(result.summaryJson);
      if (summary == null) {
        final localHistory =
            await LocalOrderStorageService.instance.loadOrderHistory();
        summary = buildLocalShiftSummary(
          localHistory,
          openedAt: shift.openedAt,
          closedAt: closedAt,
        );
      }
      final session = ref.read(sessionServiceProvider);
      final ticket = ShiftSummaryTicket(
        deviceCode: session.kioskId ?? '',
        staffName: session.staff?.name ?? '',
        openedAt: shift.openedAt,
        closedAt: closedAt,
        openingBaisas: shift.openingCashBaisas,
        expectedBaisas: result.expectedCashBaisas,
        countedBaisas: _closingBaisas,
        varianceBaisas: result.varianceBaisas,
        summary: summary,
      );
      // Persist the reprint snapshot BEFORE markShiftClosed erases the
      // device's only record of the shift window.
      await session.saveLastShiftSummary(ticket.toJson());
      if (ref.read(settingsControllerProvider).printReceipts) {
        // Auto-print once; fail-safe inside the service.
        unawaited(SunmiReceiptService.printShiftSummary(ticket));
      }
      if (mounted) {
        setState(() {
          _result = result;
          _ticket = ticket;
        });
      }
    } on ShiftException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not close the shift. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _done() async {
    await ref.read(sessionControllerProvider.notifier).markShiftClosed();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final shift = ref.watch(sessionControllerProvider).openShift;
    return Scaffold(
      backgroundColor: const Color(0xFF102028),
      appBar: AppBar(
        backgroundColor: const Color(0xFF102028),
        foregroundColor: Colors.white,
        title: const Text('Close shift'),
        leading: _result == null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _result == null
                ? _buildCountStep(shift?.openingCashBaisas ?? 0)
                : _buildResultStep(_result!),
          ),
        ),
      ),
    );
  }

  Widget _buildCountStep(int openingBaisas) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _amountCard('Opening float (OMR)', _money(openingBaisas),
            muted: true),
        const SizedBox(height: 12),
        _amountCard('Counted drawer cash (OMR)', _money(_closingBaisas)),
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 14),
          ),
        ],
        const SizedBox(height: 18),
        _keypad(),
        const SizedBox(height: 18),
        SizedBox(
          width: 260,
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _close,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Close shift'),
          ),
        ),
      ],
    );
  }

  Widget _buildResultStep(ShiftCloseResult result) {
    final variance = result.varianceBaisas;
    final (label, color) = variance == 0
        ? ('Drawer balanced', const Color(0xFF35C28B))
        : variance < 0
            ? ('Drawer short', const Color(0xFFFF6B6B))
            : ('Drawer over', const Color(0xFFE0A93B));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          variance == 0 ? Icons.check_circle_rounded : Icons.info_rounded,
          color: color,
          size: 56,
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        _resultRow('Expected cash', _money(result.expectedCashBaisas)),
        _resultRow('Counted cash', _money(_closingBaisas)),
        const Divider(color: Colors.white24, height: 28),
        _resultRow('Variance', _money(variance), color: color, bold: true),
        const SizedBox(height: 24),
        if (_ticket != null) ...[
          SizedBox(
            width: 260,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () => SunmiReceiptService.printShiftSummary(_ticket!),
              icon: const Icon(Icons.print_outlined, color: Colors.white70),
              label: const Text(
                'Print summary',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: 260,
          height: 52,
          child: FilledButton(
            onPressed: _done,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _amountCard(String label, String value, {bool muted = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF16313B),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: muted ? Colors.white70 : Colors.white,
              fontSize: muted ? 24 : 32,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value,
      {Color color = Colors.white, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 15)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: bold ? 20 : 16,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _keypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '00', '0', '<'];
    return SizedBox(
      width: 300,
      child: GridView.count(
        shrinkWrap: true,
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        physics: const NeverScrollableScrollPhysics(),
        children: keys.map((k) {
          return Material(
            color: const Color(0xFF1B3540),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                if (k == '<') {
                  _backspace();
                } else if (k == '00') {
                  _tap('0');
                  _tap('0');
                } else {
                  _tap(k);
                }
              },
              child: Center(
                child: k == '<'
                    ? const Icon(Icons.backspace_outlined, color: Colors.white70)
                    : Text(
                        k,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
