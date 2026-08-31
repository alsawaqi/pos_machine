import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/qr_till_models.dart';
import 'kitchen_ticket.dart';
import 'qr_till_service.dart';
import 'sunmi_receipt_service.dart';

abstract interface class QrKitchenRoundPrinter {
  Future<bool> printRound(QrRoundEnvelope envelope, {required bool arabic});
}

class SunmiQrKitchenRoundPrinter implements QrKitchenRoundPrinter {
  const SunmiQrKitchenRoundPrinter();

  @override
  Future<bool> printRound(QrRoundEnvelope envelope, {required bool arabic}) =>
      SunmiReceiptService.printKitchenTicket(
        buildQrKitchenTicket(envelope, arabic: arabic),
      );
}

KitchenTicketData buildQrKitchenTicket(
  QrRoundEnvelope envelope, {
  required bool arabic,
}) {
  final round = envelope.round;
  final receipt = envelope.receiptNumber?.trim();
  return KitchenTicketData(
    orderLabel: receipt == null || receipt.isEmpty
        ? (arabic ? 'طلب QR' : 'QR ORDER')
        : receipt,
    orderTypeLabel: arabic
        ? 'طلب طاولة QR · الجولة ${round.roundNo}'
        : 'QR DINE-IN · ROUND ${round.roundNo}',
    tableLabel: envelope.tableLabel ?? '',
    time: round.resolvedAt ?? round.submittedAt ?? DateTime.now().toUtc(),
    items: [for (final line in round.lines) line.toKitchenItem(arabic: arabic)],
  );
}

enum QrRoundPrintNoticeKind { expiredUnprinted, printerFailed }

class QrRoundPrintNotice {
  const QrRoundPrintNotice(this.kind, {this.count = 0});

  final QrRoundPrintNoticeKind kind;
  final int count;
}

/// App-level, foreground-only accepted-round feed consumer. Its cursor and
/// printed set are scoped to the activated device and persisted after each
/// crash-sensitive step.
class QrRoundAutoPrintController with WidgetsBindingObserver {
  QrRoundAutoPrintController({
    required QrRoundGateway gateway,
    required SharedPreferences preferences,
    required QrKitchenRoundPrinter printer,
    required String Function() deviceKey,
    required bool Function() arabic,
    required void Function(QrRoundPrintNotice notice) onNotice,
    this.pollInterval = QrPollingPolicy.acceptedRoundsInterval,
  }) : _gateway = gateway,
       _preferences = preferences,
       _printer = printer,
       _deviceKey = deviceKey,
       _arabic = arabic,
       _onNotice = onNotice;

  static const int pageSize = 25;

  final QrRoundGateway _gateway;
  final SharedPreferences _preferences;
  final QrKitchenRoundPrinter _printer;
  final String Function() _deviceKey;
  final bool Function() _arabic;
  final void Function(QrRoundPrintNotice notice) _onNotice;
  final Duration pollInterval;

  Timer? _timer;
  bool _started = false;
  bool _enabled = false;
  bool _foreground = true;
  bool _polling = false;

  String get _scope {
    final value = _deviceKey().trim();
    return value.isEmpty ? 'unpaired' : value;
  }

  String get _cursorKey => 'qr_round_print_cursor_$_scope';
  String get _printedKey => 'qr_round_printed_set_$_scope';

  void start({required bool enabled}) {
    if (!_started) {
      WidgetsBinding.instance.addObserver(this);
      _started = true;
    }
    unawaited(setEnabled(enabled));
  }

  void stop() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    if (_started) WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _timer?.cancel();
    _timer = null;
    if (_foreground && _enabled) unawaited(pollNow());
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    _timer?.cancel();
    _timer = null;
    if (!enabled || !_foreground) return;

    if (!_preferences.containsKey(_cursorKey)) {
      await _seedAtLatest();
    } else {
      await pollNow();
    }
  }

  Future<void> _seedAtLatest() async {
    try {
      final page = await _gateway.fetchAcceptedRounds(limit: 1);
      // The server returns a tenant/branch-bound sequence-zero cursor when the
      // branch has no acceptances yet. Never replace it with an empty local
      // sentinel: only a real server cursor lets a later poll account for a
      // first acceptance that has already crossed the print horizon.
      final latestCursor = page.latestCursor?.trim();
      if (latestCursor != null && latestCursor.isNotEmpty) {
        await _preferences.setString(_cursorKey, latestCursor);
      }
    } catch (_) {
      // Best-effort background service. The scheduled poll retries without
      // interrupting the active till surface.
    } finally {
      _schedule();
    }
  }

  Future<void> pollNow() async {
    if (!_enabled || !_foreground || _polling) return;
    _timer?.cancel();
    _timer = null;
    _polling = true;
    try {
      var cursor = _preferences.getString(_cursorKey);
      if (cursor == null) {
        await _seedAtLatest();
        return;
      }
      var after = cursor.isEmpty ? null : cursor;

      while (_enabled && _foreground) {
        final page = await _gateway.fetchAcceptedRounds(
          after: after,
          limit: pageSize,
        );
        if (page.skippedExpiredCount > 0) {
          _onNotice(
            QrRoundPrintNotice(
              QrRoundPrintNoticeKind.expiredUnprinted,
              count: page.skippedExpiredCount,
            ),
          );
        }

        if (page.rounds.isEmpty) {
          // r4 leaves next_cursor null when every row after the cursor expired.
          // Advancing to the high-water mark after surfacing the explicit loss
          // notice is the only way to avoid reporting the same stale rows on
          // every five-second poll.
          if (page.skippedExpiredCount > 0 && page.latestCursor != null) {
            await _preferences.setString(_cursorKey, page.latestCursor!);
          }
          break;
        }

        final printed = _printedIds();
        var pageComplete = true;
        for (final envelope in page.rounds) {
          if (!_enabled || !_foreground) {
            pageComplete = false;
            break;
          }
          final key = envelope.round.id.toString();
          if (printed.contains(key)) continue;
          final ok = await _printer.printRound(envelope, arabic: _arabic());
          if (!ok) {
            pageComplete = false;
            _onNotice(
              const QrRoundPrintNotice(QrRoundPrintNoticeKind.printerFailed),
            );
            break;
          }
          printed.add(key);
          await _persistPrinted(printed);
        }
        if (!pageComplete) break;

        final next = page.nextCursor;
        if (next == null || next.isEmpty) break;
        await _preferences.setString(_cursorKey, next);

        // Once the cursor is durable, these page ids cannot be replayed and no
        // longer need printed-set space. Confirm-printed ids ahead of the cursor
        // remain until their feed page is durably acknowledged.
        printed.removeAll(page.rounds.map((row) => row.round.id.toString()));
        await _persistPrinted(printed);
        after = next;

        if (page.rounds.length < pageSize) break;
      }
    } catch (_) {
      // Transport/server failures are retried on the normal foreground cadence.
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<bool> printConfirmedRound(QrRoundEnvelope envelope) async {
    final printed = _printedIds();
    final key = envelope.round.id.toString();
    if (printed.contains(key)) return true;
    final ok = await _printer.printRound(envelope, arabic: _arabic());
    if (ok) {
      printed.add(key);
      await _persistPrinted(printed);
    }
    return ok;
  }

  Set<String> _printedIds() =>
      (_preferences.getStringList(_printedKey) ?? const <String>[]).toSet();

  Future<void> _persistPrinted(Set<String> ids) =>
      _preferences.setStringList(_printedKey, ids.toList(growable: false));

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_enabled || !_foreground) return;
    _timer = Timer(pollInterval, () => unawaited(pollNow()));
  }
}
