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

    expect(find.text('Connecting to signaling server...'), findsOneWidget);
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'create'), isTrue);

    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    expect(find.text('Your code'), findsOneWidget);
    expect(find.text('849201'), findsOneWidget);
    expect(find.text('Waiting for viewer...'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isTrue);
  });

  testWidgets('HostScreen shows consent dialog on join-request and handles Decline', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(signalingClient: fakeClient),
    ));
    await tester.pump();

    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    // Viewer sends join -> Server sends join-request to Host
    fakeClient.emitMessage({'type': 'join-request'});
    await tester.pump();

    // Verify dialog appears
    expect(find.text('Viewer Request'), findsOneWidget);
    expect(find.text('Someone wants to view your screen.'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);

    // Tap Decline
    await tester.tap(find.text('Decline'));
    await tester.pump();

    // Verify decline message sent to server
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'decline'), isTrue);

    // Dialog is closed and back to waiting
    expect(find.text('Viewer Request'), findsNothing);
    expect(find.text('Waiting for viewer...'), findsOneWidget);
  });

  testWidgets('HostScreen shows consent dialog on join-request and handles Accept', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(signalingClient: fakeClient),
    ));
    await tester.pump();

    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    fakeClient.emitMessage({'type': 'join-request'});
    await tester.pump();

    // Tap Accept
    await tester.tap(find.text('Accept'));
    await tester.pump();

    // Verify accept message sent to server
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'accept'), isTrue);

    // Screen moves to Starting... state with Stop button
    expect(find.text('Viewer Request'), findsNothing);
    expect(find.text('Starting...'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
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
