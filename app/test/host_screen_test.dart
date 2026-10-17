import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/screens/host_screen.dart';
import 'package:teachview/services/signaling.dart';

class FakeMediaStream implements MediaStream {
  bool isDisposed = false;

  @override
  String get id => 'fake_stream_id';

  @override
  List<MediaStreamTrack> getTracks() => [];

  @override
  List<MediaStreamTrack> getAudioTracks() => [];

  @override
  List<MediaStreamTrack> getVideoTracks() => [];

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

    fakeClient.emitMessage({'type': 'join-request'});
    await tester.pump();

    expect(find.text('Viewer Request'), findsOneWidget);
    expect(find.text('Someone wants to view your screen.'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'decline'), isTrue);
    expect(find.text('Viewer Request'), findsNothing);
    expect(find.text('Waiting for viewer...'), findsOneWidget);
  });

  testWidgets('HostScreen Accept starts screen capture and shows Starting...', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeStream = FakeMediaStream();
    bool captureCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (constraints) async {
          captureCalled = true;
          return fakeStream;
        },
      ),
    ));
    await tester.pump();

    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    fakeClient.emitMessage({'type': 'join-request'});
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Accept'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'accept'), isTrue);
    expect(captureCalled, isTrue);
    expect(find.text('Starting...'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('Cancelling Android screen capture dialog sends end and stops session', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (constraints) async {
          throw Exception('User cancelled system screen capture dialog');
        },
      ),
    ));
    await tester.pump();

    fakeClient.emitMessage({'type': 'created', 'code': '849201'});
    await tester.pump();

    fakeClient.emitMessage({'type': 'join-request'});
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Accept'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    // Verify end message was sent when system dialog was cancelled
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
