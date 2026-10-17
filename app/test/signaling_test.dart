import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:teachview/services/signaling.dart';

void main() {
  test('SignalingClient connects, sends, receives messages and closes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completer = Completer<Map<String, dynamic>>();

    server.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((data) {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          if (decoded['type'] == 'create') {
            socket.add(jsonEncode({'type': 'created', 'code': '123456'}));
          }
        });
      }
    });

    final client = SignalingClient();
    final url = 'ws://${server.address.address}:${server.port}';

    await client.connect(url);

    final sub = client.messages.listen((msg) {
      if (msg['type'] == 'created') {
        completer.complete(msg);
      }
    });

    client.send({'type': 'create'});

    final received = await completer.future.timeout(const Duration(seconds: 5));
    expect(received['type'], equals('created'));
    expect(received['code'], equals('123456'));

    await sub.cancel();
    client.close();
    await server.close(force: true);
  });
}
