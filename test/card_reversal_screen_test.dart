import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithqal_softpos/mithqal_softpos.dart';
import 'package:pos_machine/state/card_reversal_controller.dart';
import 'package:pos_machine/screens/card_reversal_sheet.dart';
import 'package:pos_machine/l10n/l10n.dart';

void main() {
  testWidgets('restart banner opens server recovery without a bank launch', (
    tester,
  ) async {
    var bankCalls = 0;
    CardReversalController create() => CardReversalController(
      request: (method, path, body) async {
        expect(method, 'GET');
        return {
          'reversals': [
            {
              'reversal_uuid': 'R',
              'status': 'pending',
              'kind': 'refund',
              'amount_baisas': 4750,
              'currency': '0512',
              'description': 'Order O',
            },
          ],
        };
      },
      bank: (_, _) async {
        bankCalls++;
        throw StateError('No restart launch');
      },
      printSlip: (_) async => true,
      verifyManager: (_) async => 'Manager',
      profile: const SoftPosProfile(),
    );
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: CardReversalRecoveryGate(
          createController: create,
          child: const Scaffold(body: Text('Home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Card reversal in progress'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Report observed result'));
    await tester.pumpAndSettle();
    expect(find.byType(CardReversalScreen), findsOneWidget);
    expect(find.textContaining('Order O'), findsWidgets);
    expect(bankCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('blocked setup displays reason and manual launch help', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SoftposTerminalPanel(
            profile: SoftPosProfile.fromJson({
              'provider': 'mosambee_muscat',
              'package': 'com.mosambee.muscat.softpos',
              'requires_manual_first_launch': true,
            }),
            reason: 'no_terminal_credentials',
            check: () async =>
                SoftPosOutcome.fromRaw('{"code":"SOFTPOS_NOT_INSTALLED"}'),
          ),
        ),
      ),
    );
    expect(find.textContaining('Bank Muscat'), findsOneWidget);
    expect(find.textContaining('No terminal credentials'), findsOneWidget);
    expect(find.textContaining('Open the bank'), findsOneWidget);
    await tester.tap(find.text('Check card terminal'));
    await tester.pumpAndSettle();
    expect(find.text('SOFTPOS_NOT_INSTALLED'), findsOneWidget);
  });
}
