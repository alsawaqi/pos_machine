import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

void main() {
  for (final language in ['en', 'ar']) {
    testWidgets('staff-opened table label $language', (tester) async {
      final clock = ValueNotifier(DateTime.utc(2026, 9, 18));
      addTearDown(clock.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 550,
                height: 300,
                child: buildDiningTableCardForTest(
                  table: const DiningTableDefinition(
                    id: '1',
                    floorId: 'f',
                    name: 'Table 1',
                    sizeLabel: 'square',
                    seats: 4,
                    sortOrder: 1,
                  ),
                  status: DiningTableStatus.available,
                  clock: clock,
                  onTap: () {},
                  customerOccupied: true,
                  remote: RemoteTableState(
                    tableId: 1,
                    fetchedAt: clock.value,
                    seatingUuid: 'seat',
                    origin: 'main_pos',
                    tempReference: 'T-0918-010',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        find.text(
          language == 'en'
              ? 'Occupied · opened by staff'
              : 'مشغولة · فتحها الموظف',
        ),
        findsOneWidget,
      );
      expect(find.text('Occupied by customer'), findsNothing);
      expect(find.byIcon(Icons.phone_android_rounded), findsNothing);
    });
  }
}
