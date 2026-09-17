import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';
import 'package:pos_machine/qr_checkout/qr_checkout_widgets.dart';
import 'package:pos_machine/l10n/l10n.dart';

class _LocationPlatform extends GeolocatorPlatform {
  final responses = <Object>[];
  final requests = <LocationSettings?>[];
  int cachedReads = 0;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    requests.add(locationSettings);
    final response = responses.removeAt(0);
    if (response is Position) return response;
    throw response;
  }

  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async {
    cachedReads++;
    throw StateError('Checkout must never use a cached position');
  }
}

Position _fix({Duration age = Duration.zero}) => Position(
  latitude: 23.5,
  longitude: 58.3,
  timestamp: DateTime.now().subtract(age),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });
  test('fresh default fix is used once with a cancellable timeout', () async {
    platform.responses.add(_fix());
    expect(await const GeolocatorQrLocation().currentFix(), (
      lat: 23.5,
      lng: 58.3,
    ));
    expect(platform.requests, hasLength(1));
    expect(platform.requests.single!.timeLimit, const Duration(seconds: 5));
    expect(platform.cachedReads, 0);
  });
  test(
    'Android retries a failed fused fix through the native provider',
    () async {
      platform.responses.addAll([TimeoutException('no fused fix'), _fix()]);
      expect(await const GeolocatorQrLocation().currentFix(), (
        lat: 23.5,
        lng: 58.3,
      ));
      expect(platform.requests, hasLength(2));
      final fallback = platform.requests.last as AndroidSettings;
      expect(fallback.forceLocationManager, true);
      expect(fallback.timeLimit, const Duration(seconds: 15));
      expect(platform.cachedReads, 0);
    },
  );
  test(
    'old positions are rejected instead of becoming checkout coordinates',
    () async {
      platform.responses.addAll([
        _fix(age: const Duration(minutes: 4)),
        _fix(age: const Duration(minutes: 2)),
      ]);
      expect(await const GeolocatorQrLocation().currentFix(), null);
      expect(platform.requests, hasLength(2));
      expect(platform.cachedReads, 0);
    },
  );
  test(
    'failed Android fallback still omits location and leaves server guard authoritative',
    () async {
      platform.responses.addAll([
        StateError('fused unavailable'),
        StateError('native unavailable'),
      ]);
      expect(await const GeolocatorQrLocation().currentFix(), null);
      expect(platform.requests, hasLength(2));
      expect(platform.cachedReads, 0);
    },
  );
  test('other platforms do not call the Android location manager', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    platform.responses.add(StateError('no fix'));
    expect(await const GeolocatorQrLocation().currentFix(), null);
    expect(platform.requests, hasLength(1));
    expect(platform.cachedReads, 0);
  });
  for (final ar in [false, true]) {
    testWidgets('checkout explains the location refusal ${ar ? 'AR' : 'EN'}', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(ar ? 'ar' : 'en'),
          supportedLocales: L10n.supportedLocales,
          localizationsDelegates: L10n.localizationsDelegates,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  Text(checkoutText(context, 'geofence_fix_required')),
                  Text(checkoutText(context, 'geofence_outside')),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining(ar ? 'الموقع' : 'location'), findsWidgets);
      expect(find.textContaining(ar ? 'نطاق الفرع' : 'branch'), findsWidgets);
      expect(
        find.textContaining('The bill could not be reserved'),
        findsNothing,
      );
      expect(tester.takeException(), null);
    });
  }
}
