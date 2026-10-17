import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/screens/host_screen.dart';
import 'package:teachview/services/signaling.dart';

class FakeSignalingClient implements SignalingClient {
  final List<Map<String, dynamic>> sentMessages = [];
  final StreamController<Map<String, dynamic>> _controller = StreamController<Map<String, dynamic>>.broadcast();
  bool shouldFailConnect = false;
  bool isClosed = false;

  @override
  Future<void> connect(String url) async {
    if (shouldFailConnect) {
      throw Exception('Connection refused');
    }
  }

  @override
  void send(Map<String, dynamic> message) {
    sentMessages.add(message);
  }

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  void emitMessage(Map<String, dynamic> message) {
    _controller.add(message);
  }

  @override
  void close() {
    isClosed = true;
    _controller.close();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HostScreen connects, sends create, shows code, and handles Stop', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(signalingClient: fakeClient),
    ));

    // Initially loading
    expect(find.text('Connecting to signaling server...'), findsOneWidget);

    // Let initState and _initSession complete connect & send
    await tester.pump();

    // Verify create message sent
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'create'), isTrue);

    // Emit 'created' event
    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    // Verify UI shows code, label, status and Stop button
    expect(find.text('Your code'), findsOneWidget);
    expect(find.text('849201'), findsOneWidget);
    expect(find.text('Waiting for viewer...'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Tap Stop button
    await tester.tap(find.text('Stop'));
    await tester.pump();

    // Verify end message sent
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isTrue);
  });

  testWidgets('HostScreen shows friendly error on connection failure', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient()..shouldFailConnect = true;

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(signalingClient: fakeClient),
    ));

    await tester.pump();

    expect(find.textContaining('Could not connect to signaling server'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });
}
