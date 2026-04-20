import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_machine/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('staff POS screen renders after a terminal ID is restored', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'terminal_id': 'TERM-1001',
    });

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
    await tester.pumpAndSettle();

    expect(find.text('Current Order'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Process to Pay'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
  });

  testWidgets('terminal setup screen is shown before the POS unlocks', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const StaffApp());
    await tester.pumpAndSettle();

    expect(find.text('Connect This POS Terminal'), findsOneWidget);
    expect(find.text('Terminal ID'), findsOneWidget);
    expect(find.text('Continue To POS'), findsOneWidget);
  });
}
