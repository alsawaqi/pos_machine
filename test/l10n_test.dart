import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/l10n/l10n.dart';

/// Phase C4 — the localization pipeline: Arabic must flip the widget tree to
/// RTL (blueprint §9.8 "full RTL flipping") and serve the Arabic strings;
/// lookupL10n covers the context-free consumers (controller messages).
void main() {
  Widget app(Locale locale, void Function(BuildContext) capture) {
    return MaterialApp(
      locale: locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: L10n.localizationsDelegates,
      home: Builder(
        builder: (context) {
          capture(context);
          return const Scaffold();
        },
      ),
    );
  }

  testWidgets('ar locale flips direction and serves Arabic strings', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(app(const Locale('ar'), (c) => captured = c));
    await tester.pumpAndSettle();

    expect(Directionality.of(captured), TextDirection.rtl);
    expect(L10n.of(captured).settingsTitle, 'الإعدادات');
    expect(L10n.of(captured).settingsSaved, 'تم حفظ الإعدادات.');
  });

  testWidgets('en locale stays LTR with English strings', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(app(const Locale('en'), (c) => captured = c));
    await tester.pumpAndSettle();

    expect(Directionality.of(captured), TextDirection.ltr);
    expect(L10n.of(captured).settingsTitle, 'Settings');
  });

  test('lookupL10n serves strings without a BuildContext', () {
    expect(lookupL10n(const Locale('ar')).commonCancel, 'إلغاء');
    expect(lookupL10n(const Locale('en')).commonCancel, 'Cancel');
    // Placeholders work through the generated methods.
    expect(
      lookupL10n(const Locale('en')).settingsServerReachable('http://x:1'),
      'Server reachable at http://x:1',
    );
  });
}
