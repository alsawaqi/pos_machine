import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/data/qr_pending_feed.dart';
import 'package:pos_machine/models/qr_pending_order.dart';
import 'package:pos_machine/models/qr_till_models.dart';
import 'package:pos_machine/services/pos_api_service.dart';
import 'support/qr_pending_fakes.dart';

void main() {
  testWidgets('lazy feed obeys ten-second budget, visibility and disposal', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 8, 12);
    final gateway = PendingGateway();
    final feed = QrPendingFeed(gateway, clock: () => now);
    expect(feed.readOnly, isTrue);
    await feed.refresh();
    expect(gateway.calls, isEmpty);
    feed.setForeground(true);
    await tester.pump();
    expect(gateway.calls, ['fetch']);
    expect(feed.orders.single.active.grandTotalBaisas, 4750);
    expect(feed.readOnly, isFalse);
    await feed.refresh();
    expect(gateway.calls, ['fetch']);
    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(gateway.calls, ['fetch', 'fetch']);
    feed.setForeground(false);
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(gateway.calls.length, 2);
    feed.setForeground(true);
    await tester.pump();
    expect(gateway.calls.length, 3);
    feed.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(gateway.calls.length, 3);
  });

  testWidgets(
    'Retry-After survives hiding, resume and force refresh as clock only',
    (tester) async {
      var now = DateTime.utc(2026, 9, 8, 12);
      final gateway = PendingGateway()
        ..fetchError = ApiException(
          message: 'wait',
          code: 'rate_limited',
          statusCode: 429,
          retryAfter: const Duration(seconds: 30),
        );
      final feed = QrPendingFeed(gateway, clock: () => now);
      feed.setForeground(true);
      await tester.pump();
      gateway.fetchError = null;
      feed.setForeground(false);
      now = now.add(const Duration(seconds: 20));
      await tester.pump(const Duration(seconds: 20));
      feed.setForeground(true);
      await feed.forceRefresh();
      expect(gateway.calls.length, 1);
      feed.setForeground(false);
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(gateway.calls.length, 1);
      feed.setForeground(true);
      await tester.pump();
      expect(gateway.calls.length, 2);
      expect(feed.error, isNull);
      feed.dispose();
    },
  );

  testWidgets(
    'failed refresh preserves last rows and successful timestamp; budget cannot clear stale',
    (tester) async {
      var now = DateTime.utc(2026, 9, 8, 12);
      final gateway = PendingGateway();
      final feed = QrPendingFeed(gateway, clock: () => now);
      feed.setForeground(true);
      await tester.pump();
      final snapshot = feed.orders;
      final successTime = feed.updatedAt;
      gateway.fetchError = ApiException(message: 'offline', isNetwork: true);
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(feed.orders, same(snapshot));
      expect(feed.updatedAt, successTime);
      expect(feed.readOnly, isTrue);
      await feed.refresh();
      expect(feed.readOnly, isTrue);
      expect(feed.updatedAt, successTime);
      feed.dispose();
    },
  );

  testWidgets(
    'overlapping refresh and disposal while awaiting cannot duplicate or notify',
    (tester) async {
      final gateway = PendingGateway()
        ..fetchPending = Completer<List<QrPendingOrder>>();
      final feed = QrPendingFeed(gateway);
      var notifications = 0;
      feed.addListener(() => notifications++);
      feed.setForeground(true);
      await feed.forceRefresh();
      expect(gateway.calls, ['fetch']);
      feed.dispose();
      gateway.fetchPending!.complete([pendingOrder()]);
      await tester.pump();
      expect(notifications, 1);
    },
  );

  testWidgets('paid and manager-voided orders leave the read-only feed', (
    tester,
  ) async {
    final gateway = PendingGateway([
      pendingOrder(uuid: 'paid'),
      pendingOrder(uuid: 'voided'),
    ]);
    final feed = QrPendingFeed(gateway);
    feed.setForeground(true);
    await tester.pump();
    feed.applyOrderAction(
      const QrOrderActionResult(orderUuid: 'paid', status: 'paid'),
    );
    expect(feed.orders.single.uuid, 'voided');
    feed.applyOrderAction(
      const QrOrderActionResult(orderUuid: 'voided', status: 'voided'),
    );
    expect(feed.orders, isEmpty);
    feed.dispose();
  });
}
