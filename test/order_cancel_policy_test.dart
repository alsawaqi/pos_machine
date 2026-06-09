import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// v2 #14 — the order-cancel position policy: parsed from /device/config
/// `settings.order_cancel_positions`, cached on SyncMeta, decoded into the
/// catalog, and enforced by PosController.positionCanCancelOrders.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('order-cancel policy — config mapper', () {
    test('parse encodes the policy onto the sync meta', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{
        'settings': {
          'order_cancel_positions': ['manager', 'supervisor'],
        },
      });

      expect(cfg.meta.orderCancelPositions.value, '["manager","supervisor"]');
    });

    test('parse encodes an empty list when settings are absent', () {
      final cfg = ConfigMapper.parse(<String, dynamic>{});
      expect(cfg.meta.orderCancelPositions.value, '[]');
    });

    test('toCatalog decodes the cached policy from the meta row', () {
      final meta = SyncMetaRow(id: 1, orderCancelPositions: '["manager","supervisor"]');
      final snap = ConfigMapper.toCatalog(
        null, const [], const [], const [], const [], const [],
        const [], const [], const [], const [], const [], const [],
        const [], const [], const [], meta,
      );

      expect(snap.cancelOrderPositions, ['manager', 'supervisor']);
    });

    test('toCatalog falls back to managers-only with no cached policy', () {
      final snap = ConfigMapper.toCatalog(
        null, const [], const [], const [], const [], const [],
      );
      expect(snap.cancelOrderPositions, ['manager']);
    });
  });

  group('PosController.positionCanCancelOrders', () {
    test('honours the configured positions, case-insensitively', () {
      final c = PosController();
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        cancelOrderPositions: const ['manager', 'supervisor'],
      );

      expect(c.positionCanCancelOrders('Manager'), isTrue);
      expect(c.positionCanCancelOrders('SUPERVISOR'), isTrue);
      expect(c.positionCanCancelOrders('cashier'), isFalse);
      expect(c.positionCanCancelOrders(null), isFalse);
      expect(c.positionCanCancelOrders(''), isFalse);
    });

    test('defaults to managers-only when the policy is empty', () {
      final c = PosController();
      c.applyCatalog(
        categories: const [],
        products: const [],
        floors: const [],
        tables: const [],
        cancelOrderPositions: const [],
      );

      expect(c.positionCanCancelOrders('manager'), isTrue);
      expect(c.positionCanCancelOrders('cashier'), isFalse);
    });
  });
}
