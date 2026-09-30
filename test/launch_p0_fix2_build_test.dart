import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('F11 release build number is distinguishable from candidate +1', () {
    final version = RegExp(
      r'^version: ([^\r\n]+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    expect(int.parse(version.split('+').last), greaterThan(1));
  });
}
