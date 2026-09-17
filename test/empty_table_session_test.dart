import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/dine_in/dine_in_controller.dart';
import 'package:pos_machine/dine_in/dine_in_screen.dart';
import 'unified_dine_in_test.dart' show TableFake, TableMemory, tableFixture;

class EmptyGateway extends TableFake {
  String? clearedUuid;
  EmptyGateway() {
    value = tableFixture(selected: 1);
    value['bill'] = null;
    value['rounds'] = [];
    value['seating']['joined_table_ids'] = [];
  }
  @override
  Future<void> clear(int id, {String? seatingUuid}) async {
    clearedUuid = seatingUuid;
    value['occupied'] = false;
    value['seating'] = null;
  }
}

void main() {
  test('clear targets the observed session and refreshes occupancy', () async {
    final g = EmptyGateway();
    final c = DineInController(g, TableMemory(), 1);
    addTearDown(c.dispose);
    await c.start();
    final uuid = c.detail!.seatingUuid;
    await c.clear();
    expect(g.clearedUuid, uuid);
    expect(c.detail!.occupied, isFalse);
  });
  for (final kind in ['order', 'round', 'joined', 'offline', 'draft']) {
    test('refuses clear with $kind', () async {
      final g = EmptyGateway();
      if (kind == 'order') g.value['bill'] = tableFixture()['bill'];
      if (kind == 'round') g.value['rounds'] = tableFixture()['rounds'];
      if (kind == 'joined') g.value['seating']['joined_table_ids'] = [2];
      if (kind == 'offline') g.failRead = true;
      final c = DineInController(
        g,
        TableMemory(),
        1,
        localDraftTables: () => kind == 'draft' ? {1} : {},
      );
      addTearDown(c.dispose);
      await c.start();
      await c.clear();
      expect(g.clearedUuid, isNull);
    });
  }
  testWidgets('empty session requires confirmation before clearing', (
    tester,
  ) async {
    final g = EmptyGateway();
    final c = DineInController(g, TableMemory(), 1);
    await tester.pumpWidget(
      MaterialApp(
        home: DineInScreen(
          createController: () async => c,
          catalogue: () => [],
          label: 'Table 1',
          onPay: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('dine-clear')));
    await tester.tap(find.byKey(const ValueKey('dine-clear')));
    await tester.pumpAndSettle();
    expect(g.clearedUuid, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(g.clearedUuid, isNull);
    await tester.tap(find.byKey(const ValueKey('dine-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dine-clear-confirm')));
    await tester.pumpAndSettle();
    expect(g.clearedUuid, '11111111-1111-4111-8111-111111111111');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
