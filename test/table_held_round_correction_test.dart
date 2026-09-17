import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/services/table_round_validation.dart';
import 'table_required_size_safety_test.dart' show fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'normal',
    'lost-response',
    'wrong-seat',
    'wrong-bill',
    'wrong-request',
    'accepted',
    'charge',
    'context',
  ]) {
    test(
      'held round correction $scenario preserves evidence and never resends',
      () async {
        final h = await fixture(valid: true);
        await h.bridge.send(h.bridge.activeSession()!);
        final original = h.memory.rounds.values.single;
        final held = original.withChanges({
          'status': 'held',
          'held_lines_json':
              '[{"line_index":0,"reason":"addon_selection_invalid"}]',
        });
        await h.memory.saveLocalTableRound(held);
        final session = h.coordinator.cachedSession('5')!;
        var status = scenario == 'accepted'
            ? 'accepted'
            : 'pending_confirmation';
        var rejects = 0;
        final beforeEvents = h.events.length;
        final beforeTickets = h.tickets.length;
        var lose = scenario == 'lost-response';
        Future<Map<String, dynamic>> read() async => {
          'seating': {
            'uuid': scenario == 'wrong-seat'
                ? 'new-party'
                : session.seatingUuid,
            'status': 'open',
          },
          'bill': {
            'uuid': scenario == 'wrong-bill'
                ? 'other'
                : session.serverOrderUuid,
            'status': 'open',
            'charge': scenario == 'charge' ? 'uncertain' : 'none',
          },
          'rounds': [
            {
              'id': held.serverRoundId,
              'entered_by': 'staff',
              'client_request_id': scenario == 'wrong-request'
                  ? 'other-request'
                  : held.clientRequestId,
              'status': status,
            },
          ],
        };
        Future<void> reject(String seat, int id) async {
          expect(seat, session.seatingUuid);
          expect(id, held.serverRoundId);
          rejects++;
          status = 'rejected';
          if (lose) {
            lose = false;
            throw StateError('reply lost');
          }
        }

        Future<void> correct() => h.coordinator.rejectHeldRounds(
          session,
          readDetail: read,
          reject: reject,
          isCurrent: () => scenario != 'context',
        );
        await expectLater(
          h.bridge.validatePending(h.bridge.activeSession()!),
          throwsA(isA<TableRoundReviewRequired>()),
        );
        await expectLater(
          h.bridge.send(h.bridge.activeSession()!),
          throwsA(isA<TableRoundReviewRequired>()),
        );
        if (scenario == 'normal') {
          await correct();
          await correct();
        } else {
          await expectLater(correct(), throwsStateError);
          expect(h.memory.rounds.values.single.toRow(), held.toRow());
          if (scenario == 'lost-response') await correct();
        }
        final success = ['normal', 'lost-response'].contains(scenario);
        expect(rejects, success ? 1 : 0);
        final after = h.memory.rounds.values.single;
        expect(after.status, success ? 'rejected' : 'held');
        expect({...after.toRow(), 'status': held.status}, held.toRow());
        expect(h.events.length, beforeEvents);
        expect(h.tickets.length, beforeTickets);
        expect(h.controller.cart.single.qty, 1);
        if (success) {
          expect(
            (await h.coordinator.delta(
              h.bridge.activeSession()!,
            )).single['qty'],
            1,
          );
          await h.bridge.validatePending(h.bridge.activeSession()!);
          final originalEvent = h.events.firstWhere(
            (event) => event['event_type'] == 'table.session.round',
          );
          await h.outbox.enqueueEvent('duplicate-old-ack', originalEvent);
          expect(h.memory.rounds.values.single.status, 'rejected');
          expect(h.memory.rounds.values.single.printedAt, held.printedAt);
          // No auto-send during correction; explicit Send is a new round on the same bill.
          await h.bridge.send(h.bridge.activeSession()!);
          expect(h.memory.rounds, hasLength(2));
          expect(h.memory.rounds.values.last.orderUuid, held.orderUuid);
          expect(h.tickets.length, beforeTickets + 1);
        }
      },
    );
  }
}
