import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/screens/host_screen.dart';
import 'package:teachview/services/signaling.dart';

class FakeMediaStreamTrack implements MediaStreamTrack {
  bool isStopped = false;

  @override
  Future<bool> stop() async {
    isStopped = true;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream implements MediaStream {
  bool isDisposed = false;
  final List<MediaStreamTrack> tracks;

  FakeMediaStream([List<MediaStreamTrack>? customTracks])
      : tracks = customTracks ?? [FakeMediaStreamTrack()];

  @override
  String get id => 'fake_stream_id';

  @override
  List<MediaStreamTrack> getTracks() => tracks;

  @override
  List<MediaStreamTrack> getAudioTracks() => [];

  @override
  List<MediaStreamTrack> getVideoTracks() => tracks;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCPeerConnection implements RTCPeerConnection {
  RTCSessionDescription? localDesc;
  RTCSessionDescription? remoteDesc;
  final List<RTCIceCandidate> candidatesAdded = [];
  bool isClosed = false;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Future<RTCRtpSender> addTrack(MediaStreamTrack track, [MediaStream? stream]) async {
    return FakeRtpSender();
  }

  @override
  Future<RTCSessionDescription> createOffer([Map<String, dynamic>? constraints]) async {
    return RTCSessionDescription('v=0\r\no=mock 12345\r\ns=test', 'offer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDesc = description;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteDesc = description;
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {
    candidatesAdded.add(candidate);
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<void> dispose() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRtpSender implements RTCRtpSender {
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

  testWidgets('HostScreen Accept creates WebRTC offer and exchanges ICE/answer', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeStream = FakeMediaStream();
    final fakePC = FakeRTCPeerConnection();
    bool captureCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (constraints) async {
          captureCalled = true;
          return fakeStream;
        },
        peerConnectionFactory: (config) async {
          return fakePC;
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

    // Verify accept and offer sent
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'accept'), isTrue);
    expect(captureCalled, isTrue);
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'offer'), isTrue);

    // Simulate local ICE candidate from peer connection
    fakePC.onIceCandidate?.call(RTCIceCandidate('candidate:1 1 UDP 1234', 'video', 0));
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'ice'), isTrue);

    // Simulate answer received from viewer
    fakeClient.emitMessage({
      'type': 'answer',
      'sdp': 'v=0\r\no=viewer 67890\r\ns=test',
    });
    await tester.pump();
    expect(fakePC.remoteDesc?.sdp, contains('viewer 67890'));

    // Simulate ICE candidate received from viewer
    fakeClient.emitMessage({
      'type': 'ice',
      'candidate': {
        'candidate': 'candidate:2 1 UDP 5678',
        'sdpMid': 'video',
        'sdpMLineIndex': 0,
      },
    });
    await tester.pump();
    expect(fakePC.candidatesAdded.length, equals(1));
    expect(fakePC.candidatesAdded.first.candidate, equals('candidate:2 1 UDP 5678'));

    // Verify Stop button terminates peer connection
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(fakePC.isClosed, isTrue);
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

  testWidgets('HostScreen Stop button cleanly disposes tracks, closes PC, sends end, and closes socket', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeStream = FakeMediaStream();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (_) async => fakeStream,
        peerConnectionFactory: (_) async => fakePC,
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

    // Verify stream & PC active
    expect(fakeStream.isDisposed, isFalse);
    expect(fakePC.isClosed, isFalse);

    // Now tap Stop
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isTrue);
    expect(fakeClient.isClosed, isTrue);
    expect(fakePC.isClosed, isTrue);
    expect(fakeStream.isDisposed, isTrue);
    expect((fakeStream.tracks.first as FakeMediaStreamTrack).isStopped, isTrue);
  });

  testWidgets('HostScreen cleans up when peer-left or ended arrives', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeStream = FakeMediaStream();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (_) async => fakeStream,
        peerConnectionFactory: (_) async => fakePC,
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

    // Emit ended from remote side
    fakeClient.emitMessage({'type': 'ended'});
    await tester.pump();

    // Cleaned up, but did NOT send 'end' back
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isFalse);
    expect(fakeClient.isClosed, isTrue);
    expect(fakePC.isClosed, isTrue);
    expect(fakeStream.isDisposed, isTrue);
    expect(find.text('Session ended'), findsOneWidget);
  });

  testWidgets('HostScreen displays connection status indicator (Connecting, Connected, Disconnected)', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeStream = FakeMediaStream();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: HostScreen(
        signalingClient: fakeClient,
        screenCapture: (_) async => fakeStream,
        peerConnectionFactory: (_) async => fakePC,
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

    // While starting WebRTC, status is Connecting
    expect(find.text('Connecting'), findsWidgets);

    // Simulate connection state changing to Connected
    fakePC.onConnectionState?.call(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
    await tester.pump();
    expect(find.text('Connected'), findsWidgets);

    // Simulate connection state changing to Disconnected
    fakePC.onConnectionState?.call(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
    await tester.pump();
    expect(find.text('Disconnected'), findsWidgets);
  });
}
