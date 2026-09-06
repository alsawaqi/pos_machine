import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/widgets/sent_line_cancel_dialog.dart';

import 'send_to_kitchen_test.dart' show B3Harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final approved in [false, true]) {
    testWidgets('manager approval=$approved precedes the prepared question', (
      tester,
    ) async {
      var approvals = 0;
      SentLineCancellationApproval? result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await requestSentLineCancellation(
                  context,
                  authorizeManager: () async {
                    approvals++;
                    return approved;
                  },
                );
              },
              child: const Text('reduce'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('reduce'));
      await tester.pumpAndSettle();
      expect(approvals, 1);
      expect(
        find.text('Was it prepared?'),
        approved ? findsOneWidget : findsNothing,
      );
      expect(result, isNull);
      if (approved) {
        await tester.tap(find.text('Yes — record waste'));
        await tester.pumpAndSettle();
        expect(result!.prepared, true);
      }
    });
  }

  for (final locale in ['en', 'ar']) {
    testWidgets('cancel dialog $locale supports no and dismissal', (
      tester,
    ) async {
      SentLineCancellationApproval? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await requestSentLineCancellation(
                  context,
                  authorizeManager: () async => true,
                );
              },
              child: const Text('reduce'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('reduce'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Customer changed mind');
      await tester.tap(
        find.text(locale == 'en' ? 'No — cancel only' : 'لا — إلغاء فقط'),
      );
      await tester.pumpAndSettle();
      expect(result!.prepared, false);
      expect(result!.reason, 'Customer changed mind');
      result = null;
      await tester.tap(find.text('reduce'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });
  }

  for (final prepared in [false, true]) {
    test(
      'offline prepared=$prepared queues exact cancel/waste intent order',
      () async {
        final h = B3Harness();
        await h.init();
        await h.bridge.send(h.bridge.activeSession()!);
        h.online = false;
        await h.coordinator.cancelLine(
          h.bridge.activeSession()!,
          line: {'product_id': 10},
          qty: 1,
          prepared: prepared,
          authorizedBy: 'Manager',
        );
        final rows = await h.outbox.pendingRows();
        final events = rows
            .map((r) => (jsonDecode(r.eventsJson) as List).single as Map)
            .toList();
        expect(events.map((e) => e['event_type']), [
          'table.session.cancel_line',
          if (prepared) 'product.waste',
        ]);
        expect((events.first['payload'] as Map)['queued_offline'], true);
        expect((events.first['payload'] as Map)['qty'], 1);
        expect((events.first['payload'] as Map)['authorized_by'], 'Manager');
        expect(h.memory.cancellations.values.single.status, 'queued');
        h.online = true;
        await h.outbox.flush();
        expect(h.memory.cancellations.values.single.cancelledQty, 1);
        expect(h.memory.cancellations.values.single.status, 'cancelled');
        expect(await h.outbox.pendingRows(), isEmpty);
      },
    );
  }

  test(
    'short fulfilment is recorded without rolling back the cashier cart',
    () async {
      final h = B3Harness()..cancelledQty = 1;
      await h.init();
      await h.bridge.send(h.bridge.activeSession()!);
      await h.coordinator.cancelLine(
        h.bridge.activeSession()!,
        line: {'product_id': 10},
        qty: 2,
        prepared: false,
        authorizedBy: 'Manager',
      );
      expect(h.memory.cancellations.values.single.cancelledQty, 1);
      expect(h.memory.verdicts.single.outcome, 'cancelled');
      expect(h.controller.cart.single.qty, 2);
      expect(h.tickets, hasLength(1), reason: 'A cancellation never reprints.');
    },
  );
}
