import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/models/remote_table_state.dart';
import 'package:pos_machine/screens/settings_screen.dart';

void main() {
  testWidgets('settings renders readable table states instead of raw TSV', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: TableSoakPanel(
            mode: 'live',
            meta: const RemoteSyncMeta(),
            rows: const [
              {
                'table_id': 2,
                'local_status': 'available',
                'server_status': 'open',
                'kind': 'server_occupied_local_free',
              },
            ],
          ),
        ),
      ),
    );
    expect(
      find.text('Table 2 · Local: Free · Server: Occupied'),
      findsOneWidget,
    );
    expect(find.textContaining('server_occupied_local_free'), findsNothing);
    expect(find.byKey(const ValueKey('table-soak-copy')), findsOneWidget);
  });
}
