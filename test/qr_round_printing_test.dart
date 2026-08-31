import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/kitchen_ticket.dart';
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

  test('a missing server cursor is never persisted as an empty sentinel', () async {
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
  });

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
}

QrRoundAutoPrintController _controller(
  SharedPreferences preferences,
  _Gateway gateway,
  _Printer printer, {
  List<QrRoundPrintNotice>? notices,
}) => QrRoundAutoPrintController(
  gateway: gateway,
  preferences: preferences,
  printer: printer,
  deviceKey: () => 'KIOSK-1',
  arabic: () => false,
  onNotice: (notice) => notices?.add(notice),
  pollInterval: const Duration(days: 1),
);

QrRoundEnvelope _round(int id) => QrRoundEnvelope(
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
  receiptNumber: 'QR-0042',
);

class _Gateway implements QrRoundGateway {
  _Gateway(this.pages);

  final List<QrAcceptedRoundsPage> pages;
  final List<String?> afterCalls = [];
  final List<int> limitCalls = [];

  @override
  Future<QrAcceptedRoundsPage> fetchAcceptedRounds({
    String? after,
    int limit = 25,
  }) async {
    afterCalls.add(after);
    limitCalls.add(limit);
    return pages.removeAt(0);
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
