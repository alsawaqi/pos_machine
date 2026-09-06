import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/qr_board_feed.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'package:pos_machine/services/qr_till_messages.dart';
import 'package:pos_machine/services/qr_till_service.dart';

const _floors = [DiningFloor(id: '1', label: 'Main floor')];
const _tables = [
  DiningTableDefinition(
    id: '3',
    floorId: '1',
    name: 'Table 3',
    sizeLabel: '4 seats',
    seats: 4,
    sortOrder: 3,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'constructor is lazy and fixed configured selection survives empty boards',
    () async {
      final service = _Gateway();
      final feed = QrBoardFeed(service, floors: _floors, tables: _tables)
        ..select('3');
      addTearDown(feed.dispose);

      expect(service.calls, isEmpty);
      expect(feed.selectedKey, '3');
      expect(feed.selectedRow, isNull);
      await feed.refresh();
      expect(feed.selectedKey, '3');
      expect(feed.selectedTable!.label, 'Table 3');
      expect(feed.selectedRow, isNull);
      expect(service.calls, ['board']);

      service.board = [_row(4)];
      await feed.forceRefresh();
      expect(feed.selectedKey, '3');
      expect(feed.selectedRow, isNull);
      expect(service.calls, ['board', 'board']);
    },
  );

  testWidgets('polls only in foreground and honors Retry-After', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final service = _Gateway()
      ..boardErrors.add(
        ApiException(
          message: 'slow down',
          statusCode: 429,
          code: 'rate_limited',
          retryAfter: const Duration(seconds: 30),
        ),
      );
    final feed = QrBoardFeed(service, clock: () => now);
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(service.boardCalls, 1);
    now = now.add(const Duration(seconds: 11));
    await tester.pump(const Duration(seconds: 11));
    await feed.refresh();
    expect(service.boardCalls, 1);

    feed.setForeground(false);
    now = now.add(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));
    feed.setForeground(true);
    await tester.pump();
    expect(service.boardCalls, 1);

    now = now.add(const Duration(seconds: 13));
    await tester.pump(const Duration(seconds: 13));
    expect(service.boardCalls, 1);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(service.boardCalls, 2);

    feed.setForeground(false);
    now = now.add(const Duration(seconds: 20));
    await tester.pump(const Duration(seconds: 20));
    expect(service.boardCalls, 2);
    feed.setForeground(true);
    await tester.pump();
    expect(service.boardCalls, 3);
    expect(feed.error, isNull);
    expect(feed.updatedAt, now);
    feed.setForeground(false);
  });

  testWidgets('short Retry-After is clamped to the ten-second budget', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final service = _Gateway()
      ..boardErrors.add(
        ApiException(
          message: 'slow down',
          statusCode: 429,
          retryAfter: const Duration(seconds: 1),
        ),
      );
    final feed = QrBoardFeed(service, clock: () => now);
    addTearDown(feed.dispose);

    await feed.refresh();
    now = now.add(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 9));
    await feed.forceRefresh();
    expect(service.boardCalls, 1);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(service.boardCalls, 2);
    feed.setForeground(false);
  });

  testWidgets('board and active detail each keep their own ten-second budget', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final service = _Gateway(board: [_row(3)], active: [_active(3)]);
    final feed = QrBoardFeed(
      service,
      clock: () => now,
      floors: _floors,
      tables: _tables,
    )..select('3');
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(service.calls, ['board', 'active']);
    await feed.refresh();
    feed.select('3');
    await tester.pump();
    expect(service.calls, ['board', 'active']);

    now = now.add(const Duration(seconds: 9));
    await tester.pump(const Duration(seconds: 9));
    await feed.refresh();
    expect(service.calls, ['board', 'active']);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await feed.refresh();
    expect(service.calls, ['board', 'active', 'board', 'active']);
    await feed.forceRefresh();
    expect(service.calls, [
      'board',
      'active',
      'board',
      'active',
      'board',
      'active',
    ]);
    feed.setForeground(false);
  });

  testWidgets(
    'host interval clock and service bindings remain live after configuration changes',
    (tester) async {
      final start = DateTime.utc(2026, 8, 30, 12);
      DateTime Function() hostClock = () => start;
      final first = _Gateway();
      final second = _Gateway();
      var hostService = first;
      final feed = QrBoardFeed(
        first,
        clock: () => hostClock(),
        readService: () => hostService,
        floors: _floors,
        tables: _tables,
      );
      addTearDown(feed.dispose);
      await feed.refresh();
      expect(first.boardCalls, 1);

      hostService = second;
      hostClock = () => start.add(const Duration(seconds: 10));
      feed.updateConfiguration(
        floors: _floors,
        tables: _tables,
        pollInterval: const Duration(seconds: 20),
      );
      expect(second.boardCalls, 0);
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(first.boardCalls, 1);
      expect(second.boardCalls, 0);
      expect(feed.updatedAt, start.add(const Duration(seconds: 10)));

      hostClock = () => start.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 20));
      await tester.pump();
      expect(first.boardCalls, 1);
      expect(second.boardCalls, 1);
      expect(feed.updatedAt, start.add(const Duration(seconds: 30)));
      feed.setForeground(false);
    },
  );

  testWidgets('overlapping refreshes do not issue a second in-flight request', (
    tester,
  ) async {
    final delayed = Completer<List<QrTableBoardRow>>();
    final service = _Gateway()..delayedBoard = delayed;
    final feed = QrBoardFeed(service, floors: _floors, tables: _tables)
      ..select('3');
    addTearDown(feed.dispose);

    final first = feed.refresh();
    expect(feed.refreshing, isTrue);
    await feed.refresh();
    await feed.forceRefresh();
    expect(service.boardCalls, 1);
    delayed.complete([_row(3)]);
    await first;
    expect(service.calls, ['board', 'active']);
    expect(feed.refreshing, isFalse);
    expect(feed.selectedRow!.tableId, 3);
    feed.setForeground(false);
  });

  testWidgets('fresh awaiting board status wins over stale active detail', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 8, 30, 12);
    final stale = _active(3);
    final service = _Gateway(board: [_row(3)], active: [stale]);
    final feed = QrBoardFeed(
      service,
      clock: () => now,
      floors: _floors,
      tables: _tables,
    )..select('3');
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(feed.selectedRow!.order!.status, 'open');
    expect(feed.active['order-3'], same(stale));

    service.board = [
      _row(3, orderStatus: 'awaiting_payment', sessionStatus: 'ordered'),
    ];
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();

    expect(feed.selectedRow!.order!.status, 'awaiting_payment');
    expect(feed.selectedRow!.sessionStatus, 'ordered');
    expect(feed.active['order-3'], same(stale));
    expect(service.calls, ['board', 'active', 'board']);
    feed.setForeground(false);
  });

  test('active detail seam excludes main_pos orders', () async {
    final customer = _active(3);
    final service = _Gateway(
      board: [_row(3)],
      active: [
        customer,
        _active(4, source: 'main_pos'),
      ],
    );
    final feed = QrBoardFeed(service, floors: _floors, tables: _tables)
      ..select('3');
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(feed.active, {'order-3': same(customer)});
    expect(service.calls, ['board', 'active']);
  });

  test('applyOrderAction rewrites one row and leaves the other row and active map alone', () async {
    final original = _row(3);
    final other = _row(4);
    final detail = _active(3);
    final service = _Gateway(board: [original, other], active: [detail]);
    final feed = QrBoardFeed(service, floors: _floors, tables: _tables)
      ..select('3');
    addTearDown(feed.dispose);
    await feed.refresh();
    final activeBefore = feed.active;
    final updatedBefore = feed.updatedAt;
    var notifications = 0;
    feed.addListener(() => notifications++);

    feed.applyOrderAction(
      const QrOrderActionResult(
        orderUuid: 'order-3',
        status: 'held',
        sessionStatus: 'ordered',
        receiptNumber: 'QR-003',
        tempReference: 'T-0906-012',
      ),
    );

    final changed = feed.board.first;
    expect(changed.tableId, original.tableId);
    expect(changed.tableLabel, original.tableLabel);
    expect(changed.tableStatus, original.tableStatus);
    expect(changed.tableDeleted, original.tableDeleted);
    expect(changed.orphaned, original.orphaned);
    expect(changed.pendingRounds, same(original.pendingRounds));
    expect(changed.sessionUuid, original.sessionUuid);
    expect(changed.expiresAt, original.expiresAt);
    expect(changed.sessionStatus, 'ordered');
    expect(changed.order!.uuid, original.order!.uuid);
    expect(changed.order!.status, 'held');
    expect(changed.order!.receiptNumber, 'QR-003');
    expect(changed.order!.tempReference, 'T-0906-012');
    expect(
      changed.order!.acceptedTotalBaisas,
      original.order!.acceptedTotalBaisas,
    );
    expect(feed.board[1], same(other));
    expect(feed.active, same(activeBefore));
    expect(feed.active['order-3'], same(detail));
    expect(feed.updatedAt, updatedBefore);
    expect(service.calls, ['board', 'active']);
    expect(notifications, 1);

    feed.applyOrderAction(
      const QrOrderActionResult(orderUuid: 'missing', status: 'paid'),
    );
    expect(feed.board.first, same(changed));
    expect(feed.board[1], same(other));
    expect(feed.active, same(activeBefore));
  });

  test('selection repair retains configured tables and repairs removed archive selection', () async {
    final archived = _row(8, deleted: true, orderStatus: 'awaiting_payment');
    final service = _Gateway(board: [archived]);
    final feed = QrBoardFeed(service, floors: _floors, tables: _tables);
    addTearDown(feed.dispose);
    await feed.refresh();

    expect(feed.tableViews.map((row) => (row.key, row.floorId)), [
      ('3', '1'),
      ('8', '__archived_qr_tables__'),
    ]);
    expect(feed.floorViews, [
      ('1', 'Main floor'),
      ('__archived_qr_tables__', 'Archived tables'),
    ]);
    feed.selectFloor('__archived_qr_tables__');
    feed.select('8');
    expect(feed.selectedKey, '8');
    expect(feed.floorId, '__archived_qr_tables__');
    service.board = const [];
    await feed.forceRefresh();
    expect(feed.selectedKey, isNull);
    expect(feed.floorId, '1');

    feed.select('3');
    feed.updateConfiguration(floors: const [], tables: const []);
    expect(feed.selectedKey, '3');
    expect(feed.floorId, '1');
    await feed.forceRefresh();
    expect(feed.selectedKey, isNull);
    expect(feed.floorId, isNull);
  });

  test('mapped error copy follows the host language callback', () async {
    var arabic = false;
    final error = ApiException(
      message: 'raw server copy',
      code: 'qr_order_not_reopenable',
    );
    final service = _Gateway()..boardErrors.addAll([error, error]);
    final feed = QrBoardFeed(service, arabic: () => arabic);
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(feed.error, qrTillMessageForCode(error.code, arabic: false));
    arabic = true;
    await feed.forceRefresh();
    expect(feed.error, qrTillMessageForCode(error.code, arabic: true));
    expect(feed.error, isNot('raw server copy'));
  });

  test('unmapped and non-API errors preserve the tab copy verbatim', () async {
    final service = _Gateway()
      ..boardErrors.addAll([
        ApiException(message: 'Readable server detail'),
        StateError('offline'),
      ]);
    final feed = QrBoardFeed(service);
    addTearDown(feed.dispose);

    await feed.refresh();
    expect(feed.error, 'Readable server detail');
    await feed.forceRefresh();
    expect(feed.error, 'Could not refresh QR tables. Bad state: offline');
  });

  testWidgets(
    'dispose cancels normal polling and ignores a late successful board',
    (tester) async {
      var now = DateTime.utc(2026, 8, 30, 12);
      final service = _Gateway();
      final feed = QrBoardFeed(service, clock: () => now);
      await feed.refresh();
      feed.dispose();
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      expect(service.boardCalls, 1);
      await feed.refresh();
      expect(service.boardCalls, 1);

      final delayed = Completer<List<QrTableBoardRow>>();
      final lateService = _Gateway()..delayedBoard = delayed;
      final lateFeed = QrBoardFeed(lateService);
      var notifications = 0;
      lateFeed.addListener(() => notifications++);
      final pending = lateFeed.refresh();
      expect(notifications, 1);
      lateFeed.dispose();
      delayed.complete([_row(3)]);
      await pending;
      expect(lateFeed.board, isEmpty);
      expect(notifications, 1);
      await tester.pump(const Duration(seconds: 20));
      expect(lateService.boardCalls, 1);
    },
  );
}

QrTableBoardRow _row(
  int id, {
  String orderStatus = 'open',
  String sessionStatus = 'active',
  bool deleted = false,
}) => QrTableBoardRow(
  tableId: id,
  tableLabel: 'Table $id',
  tableStatus: 'available',
  tableDeleted: deleted,
  orphaned: false,
  pendingRounds: const [
    QrPendingRound(
      id: 41,
      roundNo: 2,
      subtotalBaisas: 1000,
      taxBaisas: 0,
      totalBaisas: 1000,
    ),
  ],
  sessionUuid: 'session-$id',
  sessionStatus: sessionStatus,
  expiresAt: DateTime.utc(2026, 9, 6, 18),
  order: QrBoardOrder(
    uuid: 'order-$id',
    status: orderStatus,
    acceptedTotalBaisas: 4750,
  ),
);

QrActiveOrder _active(int id, {String source = 'qr_web'}) => QrActiveOrder(
  uuid: 'order-$id',
  status: 'open',
  source: source,
  tableId: id,
  customerId: 42,
  subtotalBaisas: 4500,
  discountTotalBaisas: 0,
  compTotalBaisas: 0,
  taxTotalBaisas: 250,
  grandTotalBaisas: 4750,
  items: const [],
);

class _Gateway implements QrTillGateway {
  _Gateway({this.board = const [], this.active = const []});

  List<QrTableBoardRow> board;
  List<QrActiveOrder> active;
  final List<Object> boardErrors = [];
  final List<String> calls = [];
  Completer<List<QrTableBoardRow>>? delayedBoard;
  int get boardCalls => calls.where((call) => call == 'board').length;

  @override
  Future<List<QrTableBoardRow>> fetchTableBoard() async {
    calls.add('board');
    if (boardErrors.isNotEmpty) throw boardErrors.removeAt(0);
    return delayedBoard?.future ?? board;
  }

  @override
  Future<List<QrActiveOrder>> fetchActiveQrOrders() async {
    calls.add('active');
    return active;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected gateway call: ${invocation.memberName}');
}
