import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/draft_recovery/recovery_models.dart';

void main() {
  // Literal output of real API SQLite tests, not a client-specific fake server.
  for (final kind in ['legacy', 'staff']) {
    test('actual $kind API recovery preview preserves the shared bill', () {
      final envelope =
          jsonDecode(
                File(
                  'test/fixtures/draft_recovery_${kind}_server.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(envelope['errors'], isEmpty);
      final preview = RecoveryPreview(
        Map<String, dynamic>.from(envelope['data'] as Map),
      );
      final proof = preview.proof;
      final bill = Map<String, dynamic>.from(proof['bill'] as Map);
      expect(proof['archive_authorized'], isFalse);
      expect(proof['read_only'], isTrue);
      expect(bill['uuid'], proof['order_uuid']);
      expect(bill['source'], 'qr_web');
      expect(bill['grand_total_baisas'], 5000);
      expect(bill['items'], hasLength(2));
      final ack = (proof['acknowledged'] as List).single as Map;
      final original = (ack['lines'] as List).single as Map;
      expect(original['qty'], 2);
      expect(original['line_total_baisas'], 2000);
      expect(original['order_item_id'], (bill['items'] as List).first['id']);
      // The customer's three later items are not this device's acknowledged
      // local subset and must never be subtracted to derive its saved additions.
      expect((bill['items'] as List).last['qty'], 3);
      if (kind == 'legacy') expect(bill['temp_reference'], isNull);
    });
  }
}
