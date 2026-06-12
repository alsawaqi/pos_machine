import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-G6 — staff announcements on the device: the config `staff_messages`
/// slice parses into Drift companions, the cached rows map back into domain
/// [StaffMessage]s (newest first, server read receipts as a set), retraction
/// rides the delta `deleted` map, and PosController resolves per-staff
/// visibility + the unread badge (server receipts ∪ local read overrides).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('config mapper — staff_messages parse', () {
    test('maps the API slice into companions', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{
        'staff_messages': [
          {
            'id': 11,
            'target_type': 'branch',
            'target_staff_id': null,
            'title': 'Closing early',
            'body': 'We close at 9 tonight.',
            'created_by_name': 'Huda',
            'created_at': '2026-06-12T08:30:00+04:00',
            'read_staff_ids': [4, 7],
          },
          {
            'id': 12,
            'target_type': 'staff',
            'target_staff_id': 4,
            'title': null,
            'body': 'See me before your shift.',
            'created_by_name': null,
            'created_at': '2026-06-12T09:00:00+04:00',
            'read_staff_ids': <int>[],
          },
        ],
      });

      expect(cfg.staffMessages.length, 2);
      final first = cfg.staffMessages.first;
      expect(first.id.value, 11);
      expect(first.targetType.value, 'branch');
      expect(first.targetStaffId.value, isNull);
      expect(first.title.value, 'Closing early');
      expect(first.body.value, 'We close at 9 tonight.');
      expect(first.createdByName.value, 'Huda');
      expect(first.createdAt.value, isNotNull);
      expect(first.readStaffIdsJson.value, '[4,7]');

      final second = cfg.staffMessages[1];
      expect(second.targetType.value, 'staff');
      expect(second.targetStaffId.value, 4);
      expect(second.title.value, isNull);
      expect(second.readStaffIdsJson.value, '[]');
    });

    test('absent slice parses to an empty list', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{});
      expect(cfg.staffMessages, isEmpty);
    });

    test('retraction ids ride the delta deleted map', () {
      final delta = ConfigMapper.parseDelta(<String, dynamic>{
        'deleted': {
          'staff_messages': [11, 12],
        },
      }, cursor: 'C');

      expect(delta.deleted.staffMessages, [11, 12]);
      // Absent → empty (never null).
      final none = ConfigMapper.parseDelta(<String, dynamic>{}, cursor: 'C');
      expect(none.deleted.staffMessages, isEmpty);
    });
  });

  group('config mapper — toCatalog', () {
    StaffMessageRow row({
      required int id,
      String targetType = 'company',
      int? targetStaffId,
      String? title,
      String body = 'b',
      DateTime? createdAt,
      String readStaffIdsJson = '[]',
    }) =>
        StaffMessageRow(
          id: id,
          targetType: targetType,
          targetStaffId: targetStaffId,
          title: title,
          body: body,
          createdByName: null,
          createdAt: createdAt,
          readStaffIdsJson: readStaffIdsJson,
        );

    test('maps rows to domain messages, newest first, receipts as a set', () {
      final snap = ConfigMapper.toCatalog(
        null, const [], const [], const [], const [], const [],
        const [], const [], const [], const [], const [], const [],
        const [], const [], const [], null, const [], const [], const [],
        [
          row(
            id: 1,
            createdAt: DateTime(2026, 6, 10),
            readStaffIdsJson: '[4]',
          ),
          row(
            id: 2,
            targetType: 'staff',
            targetStaffId: 9,
            title: 'Private',
            createdAt: DateTime(2026, 6, 12),
          ),
        ],
      );

      expect(snap.staffMessages.length, 2);
      // Newest first regardless of row order.
      expect(snap.staffMessages.first.id, 2);
      expect(snap.staffMessages.first.targetType, 'staff');
      expect(snap.staffMessages.first.targetStaffId, 9);
      expect(snap.staffMessages.first.title, 'Private');
      expect(snap.staffMessages[1].readStaffIds, {4});
    });

    test('visibleTo: broadcasts for everyone, staff targets only theirs', () {
      const broadcast = StaffMessage(id: 1, targetType: 'branch');
      const private = StaffMessage(
        id: 2,
        targetType: 'staff',
        targetStaffId: 9,
      );

      expect(broadcast.visibleTo(4), isTrue);
      expect(broadcast.visibleTo(9), isTrue);
      expect(private.visibleTo(9), isTrue);
      expect(private.visibleTo(4), isFalse);
    });
  });

  group('PosController — visibility + unread + local reads', () {
    PosController seeded() {
      final c = PosController();
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        staffMessages: const [
          StaffMessage(id: 1, targetType: 'company', body: 'all hands'),
          StaffMessage(
            id: 2,
            targetType: 'staff',
            targetStaffId: 4,
            body: 'for #4',
          ),
          StaffMessage(
            id: 3,
            targetType: 'branch',
            body: 'branch note',
            readStaffIds: {4},
          ),
        ],
      );
      return c;
    }

    test('visibleMessagesFor filters staff-targeted messages', () {
      final c = seeded();
      expect(c.visibleMessagesFor(4).map((m) => m.id), [1, 2, 3]);
      expect(c.visibleMessagesFor(7).map((m) => m.id), [1, 3]);
    });

    test('unread counts respect server receipts per staff member', () {
      final c = seeded();
      // #4: 1 + 2 unread (3 already receipted server-side).
      expect(c.unreadMessageCountFor(4), 2);
      // #7: 1 + 3 unread (2 is not theirs).
      expect(c.unreadMessageCountFor(7), 2);
    });

    test('local reads clear the badge for THAT staff member only', () {
      final c = seeded();
      c.markMessagesReadLocal(4, [1, 2]);

      expect(c.unreadMessageCountFor(4), 0);
      // Another cashier's badge is untouched.
      expect(c.unreadMessageCountFor(7), 2);

      final msg1 = c.staffMessages.firstWhere((m) => m.id == 1);
      expect(c.isMessageReadBy(msg1, 4), isTrue);
      expect(c.isMessageReadBy(msg1, 7), isFalse);
    });

    test('local reads stay pending until the server ACKs the receipt', () {
      final c = seeded();
      c.markMessagesReadLocal(4, [1, 2]);

      // Both await an ACK (a failed POST leaves them here for a retry).
      expect(c.pendingMessageReceiptIds(4), containsAll([1, 2]));
      expect(c.pendingMessageReceiptIds(7), isEmpty);

      // The POST landed for one of them.
      c.markMessageReceiptsAcked(4, [1]);
      expect(c.pendingMessageReceiptIds(4), [2]);

      // The badge stayed clear throughout — pending is retry state, not
      // unread state.
      expect(c.unreadMessageCountFor(4), 0);
    });

    test('a catalog refresh prunes receipts the server already has', () {
      final c = seeded();
      c.markMessagesReadLocal(4, [1, 3]);
      expect(c.pendingMessageReceiptIds(4), containsAll([1, 3]));

      // The next sync shows message 1 receipted server-side for #4 (this
      // till's POST landed, or another till recorded it) — no retry needed.
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        staffMessages: const [
          StaffMessage(
            id: 1,
            targetType: 'company',
            body: 'all hands',
            readStaffIds: {4},
          ),
          StaffMessage(
            id: 3,
            targetType: 'branch',
            body: 'branch note',
            readStaffIds: {4},
          ),
        ],
      );

      expect(c.pendingMessageReceiptIds(4), isEmpty);
    });

    test('a catalog refresh keeps local reads (overrides survive)', () {
      final c = seeded();
      c.markMessagesReadLocal(4, [1, 2]);

      // Re-apply the same catalog (e.g. a delta sync re-emission with the
      // receipt not yet round-tripped).
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        staffMessages: const [
          StaffMessage(id: 1, targetType: 'company', body: 'all hands'),
          StaffMessage(
            id: 2,
            targetType: 'staff',
            targetStaffId: 4,
            body: 'for #4',
          ),
        ],
      );

      expect(c.unreadMessageCountFor(4), 0);
    });
  });
}
