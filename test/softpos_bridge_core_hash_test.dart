import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all three clients ship byte-identical bank bridge cores', () {
    const core =
        'android/app/src/main/kotlin/net/mithqal/softpos/SoftPosBridgeCore.kt';
    final roots =
        Platform.environment['PAY002_PEER_ROOTS']?.split(';') ??
        [
          'pos_machine',
          'pos_handheld',
          'pos_station',
        ].map((name) => '${Directory.current.parent.path}/$name').toList();
    expect(roots, hasLength(3));
    final own = File(core);
    expect(
      own.existsSync(),
      isTrue,
      reason: 'The tested export must contain its core',
    );
    final hash = sha256.convert(own.readAsBytesSync()).toString();
    for (final root in roots) {
      final peer = File('$root/$core');
      expect(
        peer.existsSync(),
        isTrue,
        reason:
            'Missing peer export: $root. Set PAY002_PEER_ROOTS to three exported repository roots separated by semicolons.',
      );
      expect(sha256.convert(peer.readAsBytesSync()).toString(), hash);
    }
    final source = own.readAsStringSync();
    expect(source, contains('resultCode == Activity.RESULT_OK'));
    expect(source, contains('90_000L'));
    expect(source, contains('5 * 60_000L'));
    expect(source, contains('"voidTransaction"'));
    expect(source, contains('"refundTransaction"'));
    expect(source, contains('"healthCheck"'));
  });

  test('manifest exposes both banks and health, void and refund actions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    for (final package in [
      'com.mosambee.dhofar.softpos',
      'com.mosambee.muscat.softpos',
    ]) {
      expect(manifest, contains(package));
    }
    for (final action in ['healthcheck', 'void', 'refund']) {
      expect(manifest, contains('com.mosambee.softpos.$action'));
    }
    expect(
      File(
        'android/app/src/main/kotlin/com/example/pos_machine/PaymentProxyActivity.kt',
      ).existsSync(),
      isFalse,
    );
  });
}
