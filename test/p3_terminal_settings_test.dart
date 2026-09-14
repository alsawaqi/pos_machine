import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_machine/l10n/l10n.dart';
import 'package:pos_machine/providers/providers.dart';
import 'package:pos_machine/screens/settings_screen.dart';

void main() {
  testWidgets(
    'P3-002 enrolled till settings can check the assigned bank without re-enrolment',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'terminal_id': 'TEST-TERM',
        'softpos_profile': jsonEncode({
          'provider': 'mosambee_muscat',
          'package': 'com.mosambee.muscat.softpos',
          'requires_manual_first_launch': true,
        }),
      });
      FlutterSecureStorage.setMockInitialValues({
        'device_token': 'synthetic-token',
        'terminal_pin': '1234',
      });
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.example.mosambee'),
        (call) async {
          calls.add(call);
          return '{"code":"00","description":"HEALTH OK"}';
        },
      );
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            releaseBuildProvider.overrideWithValue(true),
            orderSyncAttentionProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: SettingsScreen(showOperations: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Card terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Check card terminal'), findsOneWidget);
      expect(
        find.textContaining('com.mosambee.muscat.softpos'),
        findsOneWidget,
      );
      expect(find.textContaining('Open the bank'), findsOneWidget);
      await tester.ensureVisible(find.text('Check card terminal'));
      await tester.tap(find.text('Check card terminal'));
      await tester.pumpAndSettle();
      expect(find.text('HEALTH OK'), findsOneWidget);
      expect(calls.map((call) => call.method), ['healthCheck']);
      expect(
        (calls.single.arguments as Map)['packageName'],
        'com.mosambee.muscat.softpos',
      );
      expect(find.text('1234'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
