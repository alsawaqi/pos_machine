import 'dart:async';

import 'package:dio/dio.dart';

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

  test('rebind or APP key rotation resets an invalid cursor without printing history', () async {
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
    expect(restartedNotices.single.kind, QrRoundPrintNoticeKind.positionReset);
    expect(
      preferences.containsKey('qr_round_print_reset_pending_KIOSK-1'),
      isFalse,
    );

    await restarted.pollNow();

    expect(restartedNotices, hasLength(1));
    restarted.stop();
  });

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

  test('unrelated failures preserve cursors and cursorless validation does not reset', () async {
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

  for (final replayed in [false, true]) {
    test('B4 201 replayed=$replayed claims then prints then reports', () async {
      final preferences = await SharedPreferences.getInstance();
      final printer = _Printer();
      final kitchen = _KitchenGateway()
        ..ticket = QrKitchenTicket(
          ticketKey: 'round:1',
          roundId: 1,
          orderUuid: 'order-1',
          replayed: replayed,
          pricedLines: const [],
        )
        ..onReport = () => expect(printer.ids, [1]);
      final controller = _controller(
        preferences,
        _Gateway([]),
        printer,
        kitchenGateway: kitchen,
      );
      expect(await controller.printConfirmedRound(_round(1)), isTrue);
      expect(kitchen.claims, ['round:1']);
      expect(kitchen.reports.single.key, 'round:1');
      expect(kitchen.reports.single.result, 'printed');
      expect(kitchen.reports.single.at, isNotNull);
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), ['1']);
      expect(await controller.printConfirmedRound(_round(1)), isTrue);
      expect(printer.ids, [1]);
      expect(kitchen.claims, ['round:1']);
    });
  }

  test(
    'B4 failed physical print reports failed with null stamp and no local mark',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final printer = _Printer(outcomes: [false, true]);
      final kitchen = _KitchenGateway()
        ..onReport = () => expect(printer.ids, isNotEmpty);
      final controller = _controller(
        preferences,
        _Gateway([]),
        printer,
        kitchenGateway: kitchen,
      );
      expect(await controller.printConfirmedRound(_round(1)), isFalse);
      expect(kitchen.reports.single.result, 'failed');
      expect(kitchen.reports.single.at, isNull);
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), isNull);
      expect(await controller.printConfirmedRound(_round(1)), isTrue);
      expect(kitchen.reports.last.result, 'printed');
      expect(kitchen.claims, ['round:1', 'round:1']);
    },
  );

  for (final code in [
    'kitchen_ticket_claimed',
    'kitchen_round_not_printable',
  ]) {
    for (final automatic in [false, true]) {
      test(
        'B4 409 $code automatic=$automatic skips with no local mark',
        () async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(
            'qr_round_print_cursor_KIOSK-1',
            'cursor-0',
          );
          final printer = _Printer();
          final notices = <QrRoundPrintNotice>[];
          final kitchen = _KitchenGateway()
            ..claimError = ApiException(
              message: code,
              code: code,
              statusCode: 409,
            );
          final controller = _controller(
            preferences,
            _Gateway([_page(1)]),
            printer,
            kitchenGateway: kitchen,
            notices: notices,
          );
          if (automatic) {
            await controller.setEnabled(true);
            expect(
              preferences.getString('qr_round_print_cursor_KIOSK-1'),
              'cursor-1',
            );
          } else {
            expect(await controller.printConfirmedRound(_round(1)), isTrue);
          }
          expect(printer.ids, isEmpty);
          expect(kitchen.reports, isEmpty);
          expect(
            preferences.getStringList('qr_round_printed_set_KIOSK-1') ?? [],
            isEmpty,
          );
          expect(
            notices.map((n) => n.kind).toList(),
            code == 'kitchen_ticket_claimed'
                ? []
                : [QrRoundPrintNoticeKind.heldForReview],
          );
        },
      );
    }
  }

  for (final error in [
    ApiException(message: 'offline', isNetwork: true),
    ApiException(message: 'server', statusCode: 500),
    ApiException(message: 'rate limited', statusCode: 429),
    ApiException(
      message: 'round missing',
      statusCode: 404,
      code: 'kitchen_round_not_found',
    ),
    ApiException(message: 'unauthorized', statusCode: 401),
  ]) {
    test(
      'B4 claim failure ${error.statusCode ?? 'network'} never prints or advances and retries',
      () async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setString(
          'qr_round_print_cursor_KIOSK-1',
          'cursor-0',
        );
        final printer = _Printer();
        final kitchen = _KitchenGateway()..claimError = error;
        final controller = _controller(
          preferences,
          _Gateway([_page(1), _page(1)]),
          printer,
          kitchenGateway: kitchen,
        );
        await controller.setEnabled(true);
        expect(printer.ids, isEmpty);
        expect(kitchen.reports, isEmpty);
        expect(
          preferences.getString('qr_round_print_cursor_KIOSK-1'),
          'cursor-0',
        );
        expect(await controller.printConfirmedRound(_round(1)), isFalse);
        expect(printer.ids, isEmpty);
        kitchen.claimError = null;
        await controller.pollNow();
        expect(printer.ids, [1]);
        expect(kitchen.reports.single.result, 'printed');
        expect(
          preferences.getString('qr_round_print_cursor_KIOSK-1'),
          'cursor-1',
        );
      },
    );
  }

  test(
    'B4 route-missing 404 alone uses legacy printing with no result call',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final printer = _Printer(outcomes: [false, true]);
      final kitchen = _KitchenGateway()
        ..claimError = ApiException(message: 'route missing', statusCode: 404);
      final controller = _controller(
        preferences,
        _Gateway([]),
        printer,
        kitchenGateway: kitchen,
      );
      expect(await controller.printConfirmedRound(_round(1)), isFalse);
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), isNull);
      expect(await controller.printConfirmedRound(_round(1)), isTrue);
      expect(await controller.printConfirmedRound(_round(1)), isTrue);
      expect(printer.ids, [1, 1]);
      expect(kitchen.reports, isEmpty);
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), ['1']);
    },
  );

  test('B4 result failure survives restart and retries stamp without reprinting or needing feed row', () async {
    final preferences = await SharedPreferences.getInstance();
    final printer = _Printer();
    final kitchen = _KitchenGateway()
      ..reportError = ApiException(message: 'lost ack', isNetwork: true);
    final first = _controller(
      preferences,
      _Gateway([]),
      printer,
      kitchenGateway: kitchen,
    );
    expect(await first.printConfirmedRound(_round(1)), isFalse);
    expect(printer.ids, [1]);
    expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), ['1']);
    expect(preferences.containsKey('qr_round_print_result_KIOSK-1_1'), isTrue);
    first.stop();
    kitchen.reportError = null;
    await preferences.setString('qr_round_print_cursor_KIOSK-1', 'cursor-0');
    final restarted = _controller(
      preferences,
      _Gateway([
        const QrAcceptedRoundsPage(rounds: [], skippedExpiredCount: 0),
      ]),
      printer,
      kitchenGateway: kitchen,
    );
    await restarted.setEnabled(true);
    expect(kitchen.reports.single.result, 'printed');
    expect(printer.ids, [1]);
    expect(kitchen.claims, ['round:1']);
    expect(preferences.containsKey('qr_round_print_result_KIOSK-1_1'), isFalse);
  });

  test('B4 reviewed confirmation prints claim accepted lines only; ordinary feed stays unchanged', () async {
    final preferences = await SharedPreferences.getInstance();
    final printer = _Printer();
    final accepted = QrRoundDisplayLine.fromJson({
      'product_name': 'Accepted tea',
      'qty': 1,
      'unit_price_baisas': 500,
    });
    final kitchen = _KitchenGateway()
      ..ticket = QrKitchenTicket(
        ticketKey: 'round:1',
        roundId: 1,
        orderUuid: 'order-1',
        replayed: false,
        pricedLines: [accepted],
        printPending: true,
      );
    final controller = _controller(
      preferences,
      _Gateway([]),
      printer,
      kitchenGateway: kitchen,
    );
    expect(await controller.printConfirmedRound(_round(1)), isTrue);
    expect(printer.envelopes.single.round.lines.single.name, 'Accepted tea');
    expect(printer.envelopes.single.orderUuid, 'order-1');
    kitchen.ticket = null;
    expect(await controller.printConfirmedRound(_round(2)), isTrue);
    expect(printer.envelopes.last.round.lines.single.name, 'Coffee');
  });

  test('B4 mismatched claim identity fails closed', () async {
    final preferences = await SharedPreferences.getInstance();
    final printer = _Printer();
    final kitchen = _KitchenGateway()
      ..ticket = const QrKitchenTicket(
        ticketKey: 'round:99',
        roundId: 99,
        orderUuid: 'other',
        replayed: false,
        pricedLines: [],
      );
    final controller = _controller(
      preferences,
      _Gateway([]),
      printer,
      kitchenGateway: kitchen,
    );
    expect(await controller.printConfirmedRound(_round(1)), isFalse);
    expect(printer.ids, isEmpty);
    expect(kitchen.reports, isEmpty);
  });

  test(
    'B4 two devices and one server yield exactly one physical print',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final owners = <String, String>{};
      final firstPrinter = _Printer();
      final secondPrinter = _Printer();
      final first = _controller(
        preferences,
        _Gateway([]),
        firstPrinter,
        kitchenGateway: _DeviceKitchenGateway('A', owners),
        deviceKey: () => 'A',
      );
      final second = _controller(
        preferences,
        _Gateway([]),
        secondPrinter,
        kitchenGateway: _DeviceKitchenGateway('B', owners),
        deviceKey: () => 'B',
      );
      expect(
        await Future.wait([
          first.printConfirmedRound(_round(1)),
          second.printConfirmedRound(_round(1)),
        ]),
        [true, true],
      );
      expect([...firstPrinter.ids, ...secondPrinter.ids], [1]);
      expect(owners, {'round:1': 'A'});
      expect(preferences.getStringList('qr_round_printed_set_B'), isNull);
    },
  );

  test(
    'B4 concurrent confirmation calls share a single print attempt',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final printer = _Printer();
      final kitchen = _KitchenGateway();
      final controller = _controller(
        preferences,
        _Gateway([]),
        printer,
        kitchenGateway: kitchen,
      );
      expect(
        await Future.wait([
          controller.printConfirmedRound(_round(1)),
          controller.printConfirmedRound(_round(1)),
        ]),
        [true, true],
      );
      expect(printer.ids, [1]);
      expect(kitchen.claims, ['round:1']);
      expect(kitchen.reports, hasLength(1));
    },
  );

  test('B4 HTTP claim/result payloads and additive accepted feed parse at the API seam', () async {
    final requests = <RequestOptions>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://mock.invalid/api/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          requests.add(request);
          final isFeed = request.path.endsWith('accepted-rounds');
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: isFeed ? 200 : 201,
              data: {
                'data': isFeed
                    ? {
                        'rounds': [
                          {
                            'id': 1,
                            'round_no': 1,
                            'order_uuid': 'order-1',
                            'ticket_key': 'round:1',
                            'claimed_by_device_id': null,
                            'printed_at': null,
                            'needs_review': false,
                            'priced_lines': [],
                          },
                        ],
                      }
                    : {
                        'ticket_key': 'round:1',
                        'round_id': 1,
                        'order_uuid': 'order-1',
                        'claimed_by_device_id': 10,
                        'claimed_at': '2026-09-06T10:00:00Z',
                        'print_result': null,
                        'printed_at': null,
                        'replayed': false,
                        'print_pending': false,
                        'priced_lines': [],
                      },
                'meta': {'next_cursor': 'cursor-1'},
              },
            ),
          );
        },
      ),
    );
    final api = PosApiService(tokenGetter: () => 'fake', dio: dio);
    final gateway = ApiKitchenPrintGateway(api);
    final ticket = await gateway.claim('round:1');
    expect(ticket.roundId, 1);
    expect(ticket.claimedByDeviceId, 10);
    expect(ticket.replayed, isFalse);
    final at = DateTime.utc(2026, 9, 6, 11);
    await gateway.recordResult(
      ticketKey: 'round:1',
      printResult: 'printed',
      printedAt: at,
    );
    await gateway.recordResult(
      ticketKey: 'round:1',
      printResult: 'failed',
      printedAt: null,
    );
    final feed = await api.fetchAcceptedQrRounds(after: 'cursor-0');
    expect(feed.rounds.single.needsReview, isFalse);
    expect(feed.rounds.single.ticketKey, 'round:1');
    expect(feed.rounds.single.claimedByDeviceId, isNull);
    expect(feed.rounds.single.printedAt, isNull);
    expect(requests[0].path, '/device/kitchen/claim-print');
    expect(requests[0].data, {'ticket_key': 'round:1'});
    expect(requests[1].path, '/device/kitchen/print-result');
    expect(requests[1].data, {
      'ticket_key': 'round:1',
      'print_result': 'printed',
      'printed_at': '2026-09-06T11:00:00.000Z',
    });
    expect(requests[2].data, {
      'ticket_key': 'round:1',
      'print_result': 'failed',
      'printed_at': null,
    });
    final old = QrRoundEnvelope.fromFeedJson({
      'id': 2,
      'order_uuid': 'order-2',
    });
    expect(old.ticketKey, isNull);
    expect(old.claimedByDeviceId, isNull);
    expect(old.printedAt, isNull);
    expect(old.needsReview, isFalse);
    final reviewed = QrRoundEnvelope.fromFeedJson({
      'id': 3,
      'needs_review': true,
      'claimed_by_device_id': 12,
      'printed_at': '2026-09-06T11:00:00Z',
    });
    expect(reviewed.needsReview, isTrue);
    expect(reviewed.claimedByDeviceId, 12);
    expect(reviewed.printedAt, at);
  });

  test('B4 a late claim after device rebind never prints or reports in the new scope', () async {
    final preferences = await SharedPreferences.getInstance();
    final printer = _Printer();
    final pending = Completer<QrKitchenTicket>();
    final kitchen = _KitchenGateway()..claimHandler = (_) => pending.future;
    var scope = 'A';
    final controller = _controller(
      preferences,
      _Gateway([]),
      printer,
      kitchenGateway: kitchen,
      deviceKey: () => scope,
    );
    final result = controller.printConfirmedRound(_round(1));
    scope = 'B';
    pending.complete(
      const QrKitchenTicket(
        ticketKey: 'round:1',
        roundId: 1,
        orderUuid: 'order-1',
        replayed: false,
        pricedLines: [],
      ),
    );
    expect(await result, isFalse);
    expect(printer.ids, isEmpty);
    expect(kitchen.reports, isEmpty);
    expect(preferences.getStringList('qr_round_printed_set_A'), isNull);
    expect(preferences.getStringList('qr_round_printed_set_B'), isNull);
  });

  test(
    'B4 printer exception is a failed result and claim precedes printer entry',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final kitchen = _KitchenGateway();
      final printer = _Printer()
        ..onPrint = () {
          expect(kitchen.claims, ['round:1']);
          throw StateError('printer fault');
        };
      final controller = _controller(
        preferences,
        _Gateway([]),
        printer,
        kitchenGateway: kitchen,
      );
      expect(await controller.printConfirmedRound(_round(1)), isFalse);
      expect(kitchen.reports.single.result, 'failed');
      expect(kitchen.reports.single.at, isNull);
      expect(preferences.getStringList('qr_round_printed_set_KIOSK-1'), isNull);
    },
  );

  test('B4 only HTTP 201 is a successful claim authorization', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://mock.invalid/api/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: {
                'data': {
                  'ticket_key': 'round:1',
                  'round_id': 1,
                  'order_uuid': 'order-1',
                  'replayed': false,
                  'priced_lines': [],
                },
              },
            ),
          );
        },
      ),
    );
    final api = PosApiService(tokenGetter: () => 'fake', dio: dio);
    await expectLater(api.claimKitchenPrint('round:1'), throwsFormatException);
  });

  test('B4 malformed claim JSON never becomes a print authorization', () {
    expect(() => QrKitchenTicket.fromJson({}), throwsFormatException);
    expect(
      () => QrKitchenTicket.fromJson({
        'ticket_key': 'round:1',
        'round_id': 1,
        'order_uuid': 'order-1',
        'replayed': 'false',
        'priced_lines': [],
      }),
      throwsFormatException,
    );
  });

  test('QR kitchen ticket contains context and never contains prices', () {
    final ticket = buildQrKitchenTicket(_round(3), arabic: false);
    final rendered = buildKitchenTicketLines(ticket)
        .map((line) => line.text)
        .join('\n');

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

  test(
    'QR kitchen ticket prefers a trimmed receipt over the temporary reference',
    () {
      expect(
        buildQrKitchenTicket(
          _round(3, receiptNumber: '  QR-0001  ', tempReference: 'T-0905-012'),
          arabic: false,
        ).orderLabel,
        'QR-0001',
      );
    },
  );

  test('QR kitchen ticket retains the localized fallback when both references are absent', () {
    for (final reference in [null, '', '  ']) {
      final envelope = _round(
        3,
        receiptNumber: reference,
        tempReference: reference,
      );
      expect(
        buildQrKitchenTicket(envelope, arabic: false).orderLabel,
        'QR ORDER',
      );
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
  KitchenPrintGateway? kitchenGateway,
}) => QrRoundAutoPrintController(
  gateway: gateway,
  kitchenGateway: kitchenGateway ?? _KitchenGateway(),
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
  final List<QrRoundEnvelope> envelopes = [];
  void Function()? onPrint;

  @override
  Future<bool> printRound(
    QrRoundEnvelope envelope, {
    required bool arabic,
  }) async {
    ids.add(envelope.round.id);
    envelopes.add(envelope);
    onPrint?.call();
    return _outcomes.isEmpty ? true : _outcomes.removeAt(0);
  }
}

QrAcceptedRoundsPage _page(int id) => QrAcceptedRoundsPage(
  rounds: [_round(id)],
  nextCursor: 'cursor-$id',
  latestCursor: 'cursor-$id',
  skippedExpiredCount: 0,
);

class _DeviceKitchenGateway extends _KitchenGateway {
  _DeviceKitchenGateway(this.device, this.owners);
  final String device;
  final Map<String, String> owners;

  @override
  Future<QrKitchenTicket> claim(String ticketKey) {
    final owner = owners.putIfAbsent(ticketKey, () => device);
    if (owner != device) {
      throw ApiException(
        message: 'claimed',
        statusCode: 409,
        code: 'kitchen_ticket_claimed',
      );
    }
    return super.claim(ticketKey);
  }
}

class _KitchenGateway implements KitchenPrintGateway {
  final List<String> claims = [];
  final List<({String key, String result, DateTime? at})> reports = [];
  Object? claimError;
  Object? reportError;
  QrKitchenTicket? ticket;
  Future<QrKitchenTicket> Function(String)? claimHandler;
  void Function()? onReport;

  @override
  Future<QrKitchenTicket> claim(String ticketKey) async {
    claims.add(ticketKey);
    if (claimHandler case final handler?) return handler(ticketKey);
    if (claimError case final error?) throw error;
    final id = int.parse(ticketKey.split(':').last);
    return ticket ??
        QrKitchenTicket(
          ticketKey: ticketKey,
          roundId: id,
          orderUuid: 'order-$id',
          replayed: false,
          pricedLines: _round(id).round.lines,
        );
  }

  @override
  Future<void> recordResult({
    required String ticketKey,
    required String printResult,
    required DateTime? printedAt,
  }) async {
    onReport?.call();
    if (reportError case final error?) throw error;
    reports.add((key: ticketKey, result: printResult, at: printedAt));
  }
}
