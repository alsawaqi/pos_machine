import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/state/pos_controller.dart';

/// P-F2 — customer vehicle plates on the device: the search/show payloads
/// carry plates[], the config bundle caches them per customer (offline), and
/// the cached search matches plates so a drive-thru lookup works offline.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CustomerSearchResult.fromJson parses plates', () {
    final c = CustomerSearchResult.fromJson(<String, dynamic>{
      'id': 7,
      'name': 'Ali',
      'phone': '96915872',
      'wallet_balance_baisas': 0,
      'plates': ['1234AB', '777XY'],
      'loyalty': [
        {'rule_id': 1, 'points': 50, 'stamps': 3},
      ],
    });
    expect(c.plates, ['1234AB', '777XY']);
    // Absent plates default empty (older servers).
    final bare = CustomerSearchResult.fromJson(
        <String, dynamic>{'id': 8, 'name': 'Sara'});
    expect(bare.plates, isEmpty);
  });

  test('parse() caches customer plates as JSON for Drift', () {
    final parsed = ConfigMapper.parse(<String, dynamic>{
      'customers': [
        {
          'id': 7,
          'name': 'Ali',
          'phone': '96915872',
          'wallet_balance_baisas': 0,
          'plates': ['1234AB'],
          'loyalty': const [],
        },
      ],
    });
    expect(parsed.customers.single.platesJson.value, '["1234AB"]');
  });

  test('offline cached search matches by plate', () {
    final controller = PosController();
    addTearDown(controller.dispose);
    controller.cachedCustomers = const [
      CustomerRef(id: 1, name: 'Ali', phone: '96915872', plates: ['1234AB']),
      CustomerRef(id: 2, name: 'Sara', phone: '96900000', plates: ['777XY']),
    ];

    final byPlate = controller.searchCachedCustomers('1234');
    expect(byPlate, hasLength(1));
    expect(byPlate.single.name, 'Ali');
    expect(byPlate.single.plates, ['1234AB']);

    // Phone + name matching is unchanged.
    expect(controller.searchCachedCustomers('96900000').single.name, 'Sara');
    expect(controller.searchCachedCustomers('ali').single.id, 1);
  });
}
