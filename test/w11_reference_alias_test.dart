import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/staff_pos_screen.dart';

void main() {
  testWidgets('local REF alias is not a conflicting server reference', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 18);
    Future<void> show(String local) => tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: DiningServerBadge(
            remote: RemoteTableState(
              tableId: 1,
              fetchedAt: now,
              seatingUuid: 'seat',
              seatingStatus: 'open',
              origin: 'main_pos',
              tempReference: 'T-0918-010',
            ),
            localStatus: DiningTableStatus.occupied,
            localReference: local,
            now: now,
          ),
        ),
      ),
    );
    await show('REF-1234567890');
    expect(find.textContaining('reference differs'), findsNothing);
    expect(find.textContaining('Server: occupied'), findsOneWidget);
    await show('T-0918-009');
    expect(find.textContaining('reference differs'), findsOneWidget);
  });
}
