// Phase C3 dev tool ? verify the Reverb handshake from this machine.
// Usage: dart tool/reverb_smoke.dart <app_key> [host] [port]
// (The app key is REVERB_APP_KEY in pos_api/src/.env.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart tool/reverb_smoke.dart <app_key> [host] [port]');
    exit(64);
  }
  final key = args[0];
  final host = args.length > 1 ? args[1] : 'localhost';
  final port = args.length > 2 ? args[2] : '8085';
  final url = 'ws://' + host + ':' + port + '/app/' + key +
      '?protocol=7&client=pos_machine&version=1.0&flash=false';
  print('Dialing: ' + url);
  final socket = await WebSocket.connect(url).timeout(const Duration(seconds: 8));
  final completer = Completer<void>();
  socket.listen((raw) {
    final map = jsonDecode(raw as String) as Map;
    if (map['event'] == 'pusher:connection_established') {
      final data = jsonDecode(map['data'] as String) as Map;
      print('OK connection_established socket_id=' + data['socket_id'].toString() +
          ' activity_timeout=' + data['activity_timeout'].toString());
      completer.complete();
    }
  });
  await completer.future.timeout(const Duration(seconds: 8));
  await socket.close();
  exit(0);
}
