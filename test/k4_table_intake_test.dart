import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_kitchen_core/mithqal_kitchen_core.dart';
import 'package:pos_machine/kitchen/kitchen_domain_store.dart';
import 'package:pos_machine/tenancy/business_identity.dart';
import 'send_to_kitchen_test.dart' show B3Harness;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline table Send commits kitchen intent with original order UUID and no legacy print evidence',
    () async {
      BusinessBoundary.resetForTest();
      final h = B3Harness();
      await h.init();

      addTearDown(BusinessBoundary.resetForTest);
      h.online = false;
      h.controller.managedKitchen = () => true;
      h.outbox.kitchenIntentBuilder = (event) => kitchenDomainIntent(
        event: event,
        source: 'main_pos',
        settings: {
          'mode': 'active',
          'epoch': 1,
          'applied_version': 1,
          'identity': {
            'company_id': 1,
            'branch_id': 2,
            'device_id': 3,
            'assignment': 'test',
          },
        },
        products: {
          '10': {'name': 'Coffee', 'category_id': 1},
        },
      );
      await h.bridge.send(h.memory.tables['5']!);
      final domain = TillKitchenDomainStore(h.outbox);
      final request = (await domain.pendingKitchen()).single;
      expect(request['error'], isNull);
      expect(request['intent'], isNotNull);
      final original = object(jsonDecode(request['original_json']));
      expect(original['event_type'], 'table.session.round');
      expect(
        request['intent']['order_uuid'],
        original['payload']['order_uuid'],
      );
      expect(original['payload']['printed_at'], isNull);
      expect(request['intent']['order_uuid'], isNotEmpty);
      expect(h.tickets, isEmpty);
      expect(h.printedIds, isEmpty);
      expect(h.memory.rounds.values.single.printedAt, isNull);
      final batches = await h.outbox.allRows();
      final sent = batches
          .expand((r) => (jsonDecode(r.eventsJson) as List))
          .where((e) => e['event_type'] == 'table.session.round')
          .single;
      expect(sent['payload'], original['payload']);
      await h.bridge.send(h.memory.tables['5']!);
      expect(await domain.pendingKitchen(), hasLength(1));
    },
  );
}
