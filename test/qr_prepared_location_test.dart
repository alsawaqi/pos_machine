import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:pos_machine/services/qr_settlement_coordinator.dart';

class PreparingPlatform extends GeolocatorPlatform {
  final next = Completer<Position>();
  int reads = 0;
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    reads++;
    expect((locationSettings as AndroidSettings).forceLocationManager, true);
    return next.future;
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) =>
      throw StateError('No last-known or configured location may be used');
}

Position position(Duration age) => Position(
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
  late GeolocatorPlatform old;
  late PreparingPlatform platform;
  setUp(() {
    old = GeolocatorPlatform.instance;
    platform = PreparingPlatform();
    GeolocatorPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() {
    GeolocatorPlatform.instance = old;
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'review warming and checkout share one real in-flight native request',
    () async {
      final location = PreparedQrLocation();
      final warming = location.prepare();
      final checkout = location.currentFix();
      expect(platform.reads, 1);
      platform.next.complete(position(Duration.zero));
      await warming;
      expect(await checkout, (lat: 23.5, lng: 58.3));
      expect(await location.currentFix(), (lat: 23.5, lng: 58.3));
      expect(platform.reads, 1);
    },
  );
  test(
    'warming cannot turn a stale position into a valid checkout fix',
    () async {
      final location = PreparedQrLocation();
      final checkout = location.currentFix();
      platform.next.complete(position(const Duration(minutes: 2)));
      expect(await checkout, null);
      expect(platform.reads, 1);
    },
  );
}
