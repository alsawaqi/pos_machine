import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/core/render_error_logging.dart';

void main() {
  test('F13 render errors reach local console and existing reporter', () {
    final oldHandler = FlutterError.onError, oldPrint = debugPrint;
    addTearDown(() {
      FlutterError.onError = oldHandler;
      debugPrint = oldPrint;
    });
    final logs = <String>[];
    FlutterErrorDetails? received;
    FlutterError.onError = (d) => received = d;
    debugPrint = (String? s, {int? wrapWidth}) {
      if (s != null) logs.add(s);
    };
    installRenderErrorLogging();
    final details = FlutterErrorDetails(
      exception: StateError('held render fixture'),
      stack: StackTrace.current,
    );
    FlutterError.onError!(details);
    expect(received, same(details));
    expect(logs.join('\n'), contains('held render fixture'));
    expect(logs.join('\n'), contains('f13_render_logging_test.dart'));
  });
}
