import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_round_printing.dart';
import 'package:pos_machine/services/qr_till_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('first enable seeds latest cursor and prints no history', () async {
    final preferences = await SharedPreferences.getInstance();
    final gateway = _Gateway([
      const QrAcceptedRoundsPage(
        rounds: [],
        latestCursor: 'cursor-10',
        skippedExpiredCount: 0,
      ),
    ]);
    final printer = _Printer();
    final controller = _controller(preferences, gateway, printer);

    await controller.setEnabled(true);

    expect(gateway.afterCalls, [null]);
    expect(gateway.limitCalls, [1]);
    expect(printer.ids, isEmpty);
    expect(preferences.getString('qr_round_print_cursor_KIOSK-1'), 'cursor-10');
  });

  test(
    'empty first seed still admits and prints the first future round',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final envelope = _round(1);
      final gateway = _Gateway([
        const QrAcceptedRoundsPage(
          rounds: [],
          latestCursor: 'genesis-cursor',
          skippedExpiredCount: 0,
        ),
        QrAcceptedRoundsPage(
          rounds: [envelope],
          nextCursor: 'cursor-1',
          latestCursor: 'cursor-1',
          skippedExpiredCount: 0,
        ),
      ]);
      final printer = _Printer();
      final controller = _controller(preferences, gateway, printer);

      await controller.setEnabled(true);
      await controller.pollNow();

      expect(gateway.afterCalls, [null, 'genesis-cursor']);
      expect(printer.ids, [1]);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'cursor-1',
      );
    },
  );

  test(
    'genesis cursor reports and retires a first round missed past horizon',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final notices = <QrRoundPrintNotice>[];
      final gateway = _Gateway([
        const QrAcceptedRoundsPage(
          rounds: [],
          latestCursor: 'genesis-cursor',
          skippedExpiredCount: 0,
        ),
        const QrAcceptedRoundsPage(
          rounds: [],
          latestCursor: 'cursor-1',
          skippedExpiredCount: 1,
        ),
      ]);
      final controller = _controller(
        preferences,
        gateway,
        _Printer(),
        notices: notices,
      );

      await controller.setEnabled(true);
      await controller.pollNow();

      expect(gateway.afterCalls, [null, 'genesis-cursor']);
      expect(notices.single.kind, QrRoundPrintNoticeKind.expiredUnprinted);
      expect(notices.single.count, 1);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'cursor-1',
      );
    },
  );

  test(
    'a missing server cursor is never persisted as an empty sentinel',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final controller = _controller(
        preferences,
        _Gateway([
          const QrAcceptedRoundsPage(rounds: [], skippedExpiredCount: 0),
        ]),
        _Printer(),
      );

      await controller.setEnabled(true);

      expect(preferences.containsKey('qr_round_print_cursor_KIOSK-1'), isFalse);
    },
  );

  test(
    'rebind or APP key rotation resets an invalid cursor without printing history',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'qr_round_print_cursor_KIOSK-1',
        'old-bound-cursor',
      );
      await preferences.setStringList('qr_round_printed_set_KIOSK-1', ['77']);
      final notices = <QrRoundPrintNotice>[];
      final statuses = <bool>[];
      final printer = _Printer();
      final gateway = _Gateway([
        ApiException(
          message: 'The accepted-round cursor was invalid.',
          statusCode: 422,
          code: 'validation_failed',
        ),
        QrAcceptedRoundsPage(
          rounds: [_round(90)],
          nextCursor: 'seed-page-next-is-not-used',
          latestCursor: 'new-branch-latest',
          skippedExpiredCount: 0,
        ),
        QrAcceptedRoundsPage(
          rounds: [_round(91)],
          nextCursor: 'new-branch-91',
          latestCursor: 'new-branch-91',
          skippedExpiredCount: 0,
        ),
      ]);
      final controller = _controller(
        preferences,
        gateway,
        printer,
        notices: notices,
        pollingStatuses: statuses,
      );

      await controller.setEnabled(true);

      expect(gateway.afterCalls, ['old-bound-cursor', null]);
      expect(gateway.limitCalls, [25, 1]);
      expect(printer.ids, isEmpty);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'new-branch-latest',
      );
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), ['77']);
      expect(notices.map((notice) => notice.kind), [
        QrRoundPrintNoticeKind.positionReset,
      ]);
      expect(statuses, isEmpty);

      await controller.pollNow();

      expect(gateway.afterCalls.last, 'new-branch-latest');
      expect(printer.ids, [91]);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'new-branch-91',
      );

      // S5 verification §8 carry-forward: a crash after persisting the reset
      // flag must deliver the notice exactly once after controller recreation.
      controller.stop();
      await preferences.setBool('qr_round_print_reset_pending_KIOSK-1', true);
      final restartedNotices = <QrRoundPrintNotice>[];
      final restarted = _controller(
        preferences,
        _Gateway([
          const QrAcceptedRoundsPage(
            rounds: [],
            latestCursor: 'new-branch-91',
            skippedExpiredCount: 0,
          ),
          const QrAcceptedRoundsPage(
            rounds: [],
            latestCursor: 'new-branch-91',
            skippedExpiredCount: 0,
          ),
        ]),
        _Printer(),
        notices: restartedNotices,
      );

      await restarted.setEnabled(true);

      expect(restartedNotices, hasLength(1));
      expect(
        restartedNotices.single.kind,
        QrRoundPrintNoticeKind.positionReset,
      );
      expect(
        preferences.containsKey('qr_round_print_reset_pending_KIOSK-1'),
        isFalse,
      );

      await restarted.pollNow();

      expect(restartedNotices, hasLength(1));
      restarted.stop();
    },
  );

  test(
    'an in-flight rebind cannot delete or overwrite the new device scope',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'qr_round_print_cursor_KIOSK-OLD',
        'old-invalid-cursor',
      );
      await preferences.setString(
        'qr_round_print_cursor_KIOSK-NEW',
        'new-device-cursor',
      );
      var deviceKey = 'KIOSK-OLD';
      final pending = Completer<QrAcceptedRoundsPage>();
      final notices = <QrRoundPrintNotice>[];
      final controller = _controller(
        preferences,
        _Gateway([pending.future]),
        _Printer(),
        notices: notices,
        deviceKey: () => deviceKey,
      );

      final poll = controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      deviceKey = 'KIOSK-NEW';
      pending.completeError(
        ApiException(
          message: 'The accepted-round cursor was invalid.',
          statusCode: 422,
          code: 'validation_failed',
        ),
      );
      await poll;

      expect(
        preferences.containsKey('qr_round_print_cursor_KIOSK-OLD'),
        isFalse,
      );
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-NEW'),
        'new-device-cursor',
      );
      expect(notices, isEmpty);
    },
  );

  test(
    'a late seed failure after disable does not poison feed health',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final pending = Completer<QrAcceptedRoundsPage>();
      final statuses = <bool>[];
      final controller = _controller(
        preferences,
        _Gateway([pending.future]),
        _Printer(),
        pollingStatuses: statuses,
      );

      final seed = controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      await controller.setEnabled(false);
      pending.completeError(ApiException(message: 'offline', isNetwork: true));
      await seed;

      expect(statuses, isEmpty);
      expect(preferences.containsKey('qr_round_print_cursor_KIOSK-1'), isFalse);
    },
  );

  test(
    'failed reset reseed stays cursorless and warns after retry succeeds',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        'qr_round_print_cursor_KIOSK-1',
        'rotated-cursor',
      );
      final notices = <QrRoundPrintNotice>[];
      final gateway = _Gateway([
        ApiException(
          message: 'The accepted-round cursor was invalid.',
          statusCode: 422,
          code: 'validation_failed',
        ),
        ApiException(message: 'offline', isNetwork: true),
        const QrAcceptedRoundsPage(
          rounds: [],
          latestCursor: 'fresh-latest',
          skippedExpiredCount: 0,
        ),
      ]);
      final controller = _controller(
        preferences,
        gateway,
        _Printer(),
        notices: notices,
      );

      await controller.setEnabled(true);

      expect(preferences.containsKey('qr_round_print_cursor_KIOSK-1'), isFalse);
      expect(notices, isEmpty);

      await controller.pollNow();

      expect(gateway.afterCalls, ['rotated-cursor', null, null]);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'fresh-latest',
      );
      expect(notices.single.kind, QrRoundPrintNoticeKind.positionReset);
    },
  );

  test(
    'three consecutive feed failures expose persistent health until success',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-4');
      final statuses = <bool>[];
      final failure = ApiException(message: 'offline', isNetwork: true);
      final controller = _controller(
        preferences,
        _Gateway([
          failure,
          failure,
          failure,
          failure,
          const QrAcceptedRoundsPage(
            rounds: [],
            latestCursor: 'cursor-4',
            skippedExpiredCount: 0,
          ),
          failure,
          failure,
          failure,
        ]),
        _Printer(),
        pollingStatuses: statuses,
      );

      await controller.setEnabled(true);
      await controller.pollNow();
      expect(statuses, isEmpty);

      await controller.pollNow();
      expect(statuses, [true]);

      await controller.pollNow();
      expect(statuses, [true]);

      await controller.pollNow();
      expect(statuses, [true, false]);

      await controller.pollNow();
      await controller.pollNow();
      expect(statuses, [true, false]);
      await controller.pollNow();
      expect(statuses, [true, false, true]);
    },
  );

  test(
    'unrelated failures preserve cursors and cursorless validation does not reset',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('qr_round_print_cursor_KIOSK-1', 'keep-me');
      final notices = <QrRoundPrintNotice>[];
      await _controller(
        preferences,
        _Gateway([
          ApiException(
            message: 'Server failed.',
            statusCode: 500,
            code: 'server_error',
          ),
        ]),
        _Printer(),
        notices: notices,
      ).setEnabled(true);

      expect(preferences.getString('qr_round_print_cursor_KIOSK-1'), 'keep-me');
      expect(notices, isEmpty);

      await preferences.remove('qr_round_print_cursor_KIOSK-1');
      await _controller(
        preferences,
        _Gateway([
          ApiException(
            message: 'Validation failed.',
            statusCode: 422,
            code: 'validation_failed',
          ),
        ]),
        _Printer(),
        notices: notices,
      ).setEnabled(true);

      expect(preferences.containsKey('qr_round_print_cursor_KIOSK-1'), isFalse);
      expect(notices, isEmpty);
    },
  );

  test('drains a 25-round gap and prints every round exactly once', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-0');
    final rounds = [for (var id = 1; id <= 25; id++) _round(id)];
    final gateway = _Gateway([
      QrAcceptedRoundsPage(
        rounds: rounds,
        nextCursor: 'cursor-25',
        latestCursor: 'cursor-25',
        skippedExpiredCount: 0,
      ),
      const QrAcceptedRoundsPage(
        rounds: [],
        latestCursor: 'cursor-25',
        skippedExpiredCount: 0,
      ),
    ]);
    final printer = _Printer();

    await _controller(preferences, gateway, printer).setEnabled(true);

    expect(printer.ids, [for (var id = 1; id <= 25; id++) id]);
    expect(printer.ids.toSet(), hasLength(25));
    expect(gateway.afterCalls, ['cursor-0', 'cursor-25']);
    expect(preferences.getString('qr_round_print_cursor_KIOSK-1'), 'cursor-25');
  });

  test(
    'printer failure leaves cursor behind and restart skips marked rows',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-0');
      final page = QrAcceptedRoundsPage(
        rounds: [_round(1), _round(2)],
        nextCursor: 'cursor-2',
        latestCursor: 'cursor-2',
        skippedExpiredCount: 0,
      );
      final firstPrinter = _Printer(outcomes: [true, false]);

      await _controller(
        preferences,
        _Gateway([page]),
        firstPrinter,
      ).setEnabled(true);

      expect(firstPrinter.ids, [1, 2]);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'cursor-0',
      );
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), ['1']);

      final restartPrinter = _Printer();
      await _controller(
        preferences,
        _Gateway([page]),
        restartPrinter,
      ).setEnabled(true);

      expect(restartPrinter.ids, [2]);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'cursor-2',
      );
      expect(
        preferences.getStringList('qr_round_printed_set_KIOSK-1'),
        isEmpty,
      );
    },
  );

  test('confirm print and feed share the durable printed mark', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-0');
    final envelope = _round(7);
    final gateway = _Gateway([
      QrAcceptedRoundsPage(
        rounds: [envelope],
        nextCursor: 'cursor-7',
        latestCursor: 'cursor-7',
        skippedExpiredCount: 0,
      ),
    ]);
    final printer = _Printer();
    final controller = _controller(preferences, gateway, printer);

    expect(await controller.printConfirmedRound(envelope), isTrue);
    await controller.setEnabled(true);

    expect(printer.ids, [7]);
    expect(preferences.getString('qr_round_print_cursor_KIOSK-1'), 'cursor-7');
  });

  test(
    'confirm printing prunes the durable mark set to its newest bound',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final existing = [
        for (
          var id = 0;
          id < QrRoundAutoPrintController.maxConfirmPrintedMarks + 2;
          id++
        )
          '$id',
      ];
      await preferences.setStringList('qr_round_printed_set_KIOSK-1', existing);
      final printer = _Printer();
      final controller = _controller(preferences, _Gateway(const []), printer);

      expect(await controller.printConfirmedRound(_round(0)), isTrue);
      var persisted = preferences.getStringList(
        'qr_round_printed_set_KIOSK-1',
      )!;
      expect(
        persisted,
        hasLength(QrRoundAutoPrintController.maxConfirmPrintedMarks),
      );
      expect(persisted, contains('0'));
      expect(persisted, isNot(contains('1')));
      expect(printer.ids, isEmpty);

      expect(await controller.printConfirmedRound(_round(5000)), isTrue);
      persisted = preferences.getStringList('qr_round_printed_set_KIOSK-1')!;
      expect(
        persisted,
        hasLength(QrRoundAutoPrintController.maxConfirmPrintedMarks),
      );
      expect(persisted, contains('5000'));
      expect(printer.ids, [5000]);
    },
  );

  test(
    'expired-only page notices once and advances to the high-water mark',
    () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-2');
      final notices = <QrRoundPrintNotice>[];
      final controller = _controller(
        preferences,
        _Gateway([
          const QrAcceptedRoundsPage(
            rounds: [],
            latestCursor: 'cursor-9',
            skippedExpiredCount: 7,
          ),
        ]),
        _Printer(),
        notices: notices,
      );

      await controller.setEnabled(true);

      expect(notices.single.kind, QrRoundPrintNoticeKind.expiredUnprinted);
      expect(notices.single.count, 7);
      expect(
        preferences.getString('qr_round_print_cursor_KIOSK-1'),
        'cursor-9',
      );
    },
  );

  test('QR kitchen ticket contains context and never contains prices', () {
    final ticket = buildQrKitchenTicket(_round(3), arabic: false);
    final rendered = buildKitchenTicketLines(
      ticket,
    ).map((line) => line.text).join('\n');

    expect(ticket.orderLabel, 'QR-0042');
    expect(ticket.orderTypeLabel, contains('ROUND 3'));
    expect(ticket.tableLabel, 'Table 12');
    expect(rendered, contains('2 x Coffee'));
    expect(rendered, contains('** No sugar'));
    expect(rendered, isNot(contains('4.750')));
    expect(rendered, isNot(contains('OMR')));
  });

  test('QR kitchen ticket uses the trimmed temporary reference before a receipt exists', () {
    final ticket = buildQrKitchenTicket(
      _round(3, receiptNumber: null, tempReference: '  T-0905-012  '),
      arabic: false,
    );
    expect(ticket.orderLabel, 'T-0905-012');
    final lines = buildKitchenTicketLines(ticket);
    expect(lines.where((line) => line.text == 'T-0905-012'), hasLength(1));
    expect(
      buildQrKitchenTicket(
        _round(3, receiptNumber: '  ', tempReference: 'T-0905-012'),
        arabic: true,
      ).orderLabel,
      'T-0905-012',
    );
  });

  test('QR kitchen ticket prefers a trimmed receipt over the temporary reference', () {
    expect(
      buildQrKitchenTicket(
        _round(3, receiptNumber: '  QR-0001  ', tempReference: 'T-0905-012'),
        arabic: false,
      ).orderLabel,
      'QR-0001',
    );
  });

  test('QR kitchen ticket retains the localized fallback when both references are absent', () {
    for (final reference in [null, '', '  ']) {
      final envelope = _round(3, receiptNumber: reference, tempReference: reference);
      expect(buildQrKitchenTicket(envelope, arabic: false).orderLabel, 'QR ORDER');
      expect(buildQrKitchenTicket(envelope, arabic: true).orderLabel, 'طلب QR');
    }
  });
}

QrRoundAutoPrintController _controller(
  SharedPreferences preferences,
  _Gateway gateway,
  _Printer printer, {
  List<QrRoundPrintNotice>? notices,
  List<bool>? pollingStatuses,
  String Function()? deviceKey,
}) => QrRoundAutoPrintController(
  gateway: gateway,
  preferences: preferences,
  printer: printer,
  deviceKey: deviceKey ?? () => 'KIOSK-1',
  arabic: () => false,
  onNotice: (notice) => notices?.add(notice),
  onPollingStatus: (unavailable) => pollingStatuses?.add(unavailable),
  pollInterval: const Duration(days: 1),
);

QrRoundEnvelope _round(
  int id, {
  String? receiptNumber = 'QR-0042',
  String? tempReference,
}) => QrRoundEnvelope(
  round: QrDeviceRound(
    id: id,
    roundNo: id,
    status: 'accepted',
    lines: const [
      QrRoundDisplayLine(
        name: 'Coffee',
        nameAr: 'قهوة',
        quantity: 2,
        unitPriceBaisas: 2375,
        lineDiscountBaisas: 0,
        lineTotalBaisas: 4750,
        notes: 'No sugar',
        addons: [],
      ),
    ],
    subtotalBaisas: 4750,
    taxBaisas: 0,
    totalBaisas: 4750,
    resolvedAt: DateTime.utc(2026, 8, 31, 12),
  ),
  orderUuid: 'order-$id',
  sessionUuid: 'session-$id',
  tableLabel: 'Table 12',
  receiptNumber: receiptNumber,
  tempReference: tempReference,
);

class _Gateway implements QrRoundGateway {
  _Gateway(this.results);

  final List<Object> results;
  final List<String?> afterCalls = [];
  final List<int> limitCalls = [];

  @override
  Future<QrAcceptedRoundsPage> fetchAcceptedRounds({
    String? after,
    int limit = 25,
  }) async {
    afterCalls.add(after);
    limitCalls.add(limit);
    final result = results.removeAt(0);
    if (result is QrAcceptedRoundsPage) return result;
    if (result is Future<QrAcceptedRoundsPage>) return result;
    throw result;
  }

  @override
  Future<QrRoundEnvelope> confirmRound(int roundId) =>
      throw UnimplementedError();

  @override
  Future<QrRoundEnvelope> fetchRound(int roundId) => throw UnimplementedError();

  @override
  Future<QrRoundEnvelope> rejectRound(int roundId) =>
      throw UnimplementedError();
}

class _Printer implements QrKitchenRoundPrinter {
  _Printer({List<bool>? outcomes}) : _outcomes = outcomes ?? <bool>[];

  final List<bool> _outcomes;
  final List<int> ids = [];

  @override
  Future<bool> printRound(
    QrRoundEnvelope envelope, {
    required bool arabic,
  }) async {
    ids.add(envelope.round.id);
    return _outcomes.isEmpty ? true : _outcomes.removeAt(0);
  }
}
