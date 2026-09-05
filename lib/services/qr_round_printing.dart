import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/qr_till_models.dart';
import 'kitchen_ticket.dart';
import 'pos_api_service.dart';
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
  final tempReference = envelope.tempReference?.trim();
  final reference = receipt != null && receipt.isNotEmpty
      ? receipt
      : tempReference;
  return KitchenTicketData(
    orderLabel: reference == null || reference.isEmpty
        ? (arabic ? 'طلب QR' : 'QR ORDER')
        : reference,
    orderTypeLabel: arabic
        ? 'طلب طاولة QR · الجولة ${round.roundNo}'
        : 'QR DINE-IN · ROUND ${round.roundNo}',
    tableLabel: envelope.tableLabel ?? '',
    time: round.resolvedAt ?? round.submittedAt ?? DateTime.now().toUtc(),
    items: [for (final line in round.lines) line.toKitchenItem(arabic: arabic)],
  );
}

enum QrRoundPrintNoticeKind { expiredUnprinted, printerFailed, positionReset }

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
    required void Function(bool unavailable) onPollingStatus,
    this.pollInterval = QrPollingPolicy.acceptedRoundsInterval,
  }) : _gateway = gateway,
       _preferences = preferences,
       _printer = printer,
       _deviceKey = deviceKey,
       _arabic = arabic,
       _onNotice = onNotice,
       _onPollingStatus = onPollingStatus;

  static const int pageSize = 25;
  static const int consecutiveFailureThreshold = 3;
  static const int maxConfirmPrintedMarks = 1024;

  final QrRoundGateway _gateway;
  final SharedPreferences _preferences;
  final QrKitchenRoundPrinter _printer;
  final String Function() _deviceKey;
  final bool Function() _arabic;
  final void Function(QrRoundPrintNotice notice) _onNotice;
  final void Function(bool unavailable) _onPollingStatus;
  final Duration pollInterval;

  Timer? _timer;
  bool _started = false;
  bool _enabled = false;
  bool _foreground = true;
  bool _polling = false;
  int _consecutivePollFailures = 0;
  bool _pollingUnavailable = false;

  String get _scope {
    final value = _deviceKey().trim();
    return value.isEmpty ? 'unpaired' : value;
  }

  String _cursorKeyFor(String scope) => 'qr_round_print_cursor_$scope';
  String _printedKeyFor(String scope) => 'qr_round_printed_set_$scope';
  String _resetPendingKeyFor(String scope) =>
      'qr_round_print_reset_pending_$scope';

  void start({required bool enabled}) {
    if (!_started) {
      WidgetsBinding.instance.addObserver(this);
      _started = true;
    }
    unawaited(setEnabled(enabled));
  }

  void stop() {
    _enabled = false;
    _resetPollingHealth();
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
    if (!enabled) {
      _resetPollingHealth();
      return;
    }
    if (!_foreground) return;

    final scope = _scope;
    if (!_preferences.containsKey(_cursorKeyFor(scope))) {
      await _seedAtLatest(scope: scope);
    } else {
      await _deliverPendingResetNotice(scope);
      await pollNow();
    }
  }

  Future<bool> _seedAtLatest({
    required String scope,
    bool schedule = true,
  }) async {
    try {
      final page = await _gateway.fetchAcceptedRounds(limit: 1);
      if (!_isActiveScope(scope)) return false;
      // The server returns a tenant/branch-bound sequence-zero cursor when the
      // branch has no acceptances yet. Never replace it with an empty local
      // sentinel: only a real server cursor lets a later poll account for a
      // first acceptance that has already crossed the print horizon.
      final latestCursor = page.latestCursor?.trim();
      if (latestCursor == null || latestCursor.isEmpty) {
        throw StateError('The accepted-round feed returned no latest cursor.');
      }
      final cursorKey = _cursorKeyFor(scope);
      await _preferences.setString(cursorKey, latestCursor);
      if (!_isActiveScope(scope)) {
        await _preferences.remove(cursorKey);
        return false;
      }
      _recordPollSuccess();
      await _deliverPendingResetNotice(scope);
      return true;
    } catch (_) {
      if (_isActiveScope(scope)) _recordPollFailure();
      return false;
    } finally {
      if (schedule) _schedule();
    }
  }

  Future<void> pollNow() async {
    if (!_enabled || !_foreground || _polling) return;
    _timer?.cancel();
    _timer = null;
    _polling = true;
    final scope = _scope;
    final cursorKey = _cursorKeyFor(scope);
    final printedKey = _printedKeyFor(scope);
    String? requestAfter;
    try {
      var cursor = _preferences.getString(cursorKey);
      if (cursor == null) {
        await _seedAtLatest(scope: scope, schedule: false);
        return;
      }
      await _deliverPendingResetNotice(scope);
      if (cursor.trim().isEmpty) {
        await _preferences.remove(cursorKey);
        await _seedAtLatest(scope: scope, schedule: false);
        return;
      }
      var after = cursor;

      while (_enabled && _foreground) {
        requestAfter = after;
        final page = await _gateway.fetchAcceptedRounds(
          after: after,
          limit: pageSize,
        );
        requestAfter = null;
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
            await _preferences.setString(cursorKey, page.latestCursor!);
          }
          _recordPollSuccess();
          break;
        }

        final printed = _printedIds(printedKey);
        var pageComplete = true;
        for (final envelope in page.rounds) {
          if (!_enabled || !_foreground) {
            pageComplete = false;
            break;
          }
          final key = envelope.round.id.toString();
          if (printed.contains(key)) continue;
          var ok = false;
          try {
            ok = await _printer.printRound(envelope, arabic: _arabic());
          } catch (_) {
            // Printer faults have their own recovery surface and must not
            // masquerade as accepted-round feed connectivity failures.
          }
          if (!ok) {
            pageComplete = false;
            _recordPollSuccess();
            _onNotice(
              const QrRoundPrintNotice(QrRoundPrintNoticeKind.printerFailed),
            );
            break;
          }
          printed.add(key);
          await _persistPrinted(printedKey, printed);
        }
        if (!pageComplete) break;

        final next = page.nextCursor;
        if (next == null || next.isEmpty) {
          _recordPollSuccess();
          break;
        }
        await _preferences.setString(cursorKey, next);

        // Once the cursor is durable, these page ids cannot be replayed and no
        // longer need printed-set space. Confirm-printed ids ahead of the cursor
        // remain until their feed page is durably acknowledged.
        printed.removeAll(page.rounds.map((row) => row.round.id.toString()));
        await _persistPrinted(printedKey, printed);
        _recordPollSuccess();
        after = next;

        if (page.rounds.length < pageSize) break;
      }
    } on ApiException catch (error) {
      if (!_enabled || !_foreground) return;
      final cursorBearingRequest =
          requestAfter != null && requestAfter.trim().isNotEmpty;
      if (cursorBearingRequest && error.code == 'validation_failed') {
        await _recoverInvalidCursor(scope: scope, cursorKey: cursorKey);
      } else {
        _recordPollFailure();
      }
    } catch (_) {
      if (!_enabled || !_foreground) return;
      _recordPollFailure();
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<bool> printConfirmedRound(QrRoundEnvelope envelope) async {
    final printedKey = _printedKeyFor(_scope);
    final printed = _printedIds(printedKey);
    final key = envelope.round.id.toString();
    if (printed.contains(key)) {
      printed.remove(key);
      printed.add(key);
      await _persistConfirmPrinted(printedKey, printed);
      return true;
    }
    final ok = await _printer.printRound(envelope, arabic: _arabic());
    if (ok) {
      printed.add(key);
      await _persistConfirmPrinted(printedKey, printed);
    }
    return ok;
  }

  Future<void> _recoverInvalidCursor({
    required String scope,
    required String cursorKey,
  }) async {
    if (!_enabled || !_foreground) return;
    try {
      await _preferences.remove(cursorKey);
      if (!_isActiveScope(scope)) return;
      await _preferences.setBool(_resetPendingKeyFor(scope), true);
      if (!_isActiveScope(scope)) return;
    } catch (_) {
      if (_isActiveScope(scope)) _recordPollFailure();
      return;
    }

    await _seedAtLatest(scope: scope, schedule: false);
  }

  Future<void> _deliverPendingResetNotice(String scope) async {
    final key = _resetPendingKeyFor(scope);
    if (!(_preferences.getBool(key) ?? false)) return;
    _onNotice(const QrRoundPrintNotice(QrRoundPrintNoticeKind.positionReset));
    await _preferences.remove(key);
  }

  void _recordPollFailure() {
    _consecutivePollFailures += 1;
    if (_consecutivePollFailures < consecutiveFailureThreshold ||
        _pollingUnavailable) {
      return;
    }
    _pollingUnavailable = true;
    _onPollingStatus(true);
  }

  void _recordPollSuccess() {
    _consecutivePollFailures = 0;
    if (!_pollingUnavailable) return;
    _pollingUnavailable = false;
    _onPollingStatus(false);
  }

  void _resetPollingHealth() {
    _consecutivePollFailures = 0;
    if (!_pollingUnavailable) return;
    _pollingUnavailable = false;
    _onPollingStatus(false);
  }

  bool _isActiveScope(String scope) =>
      _enabled && _foreground && _scope == scope;

  Set<String> _printedIds(String printedKey) =>
      (_preferences.getStringList(printedKey) ?? const <String>[]).toSet();

  Future<void> _persistPrinted(String printedKey, Set<String> ids) =>
      _preferences.setStringList(printedKey, ids.toList(growable: false));

  Future<void> _persistConfirmPrinted(String printedKey, Set<String> ids) {
    while (ids.length > maxConfirmPrintedMarks) {
      ids.remove(ids.first);
    }
    return _persistPrinted(printedKey, ids);
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_started || !_enabled || !_foreground) return;
    _timer = Timer(pollInterval, () => unawaited(pollNow()));
  }
}
