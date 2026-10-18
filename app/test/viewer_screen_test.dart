import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/screens/viewer_screen.dart';
import 'package:teachview/services/signaling.dart';

class FakeMediaStreamTrack implements MediaStreamTrack {
  @override
  String get kind => 'video';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaStream implements MediaStream {
  bool isDisposed = false;
  final List<MediaStreamTrack> tracks;

  FakeMediaStream([List<MediaStreamTrack>? customTracks])
      : tracks = customTracks ?? [FakeMediaStreamTrack()];

  @override
  String get id => 'fake_remote_stream';

  @override
  List<MediaStreamTrack> getTracks() => tracks;

  @override
  Future<void> dispose() async {
    isDisposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCVideoRenderer extends ValueNotifier<RTCVideoValue> implements RTCVideoRenderer {
  FakeRTCVideoRenderer() : super(RTCVideoValue.empty);

  bool isInitialized = false;
  bool isDisposed = false;
  MediaStream? src;

  @override
  bool get renderVideo => false;

  @override
  int? get textureId => null;

  @override
  Future<void> initialize() async {
    isInitialized = true;
    value = const RTCVideoValue(width: 1920, height: 1080);
  }

  @override
  set srcObject(MediaStream? stream) {
    src = stream;
  }

  @override
  MediaStream? get srcObject => src;

  @override
  Future<void> dispose() async {
    isDisposed = true;
    super.dispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRTCPeerConnection implements RTCPeerConnection {
  RTCSessionDescription? remoteDesc;
  RTCSessionDescription? localDesc;
  final List<RTCIceCandidate> candidatesAdded = [];
  bool isClosed = false;

  @override
  Function(RTCIceCandidate candidate)? onIceCandidate;

  @override
  Function(RTCIceConnectionState state)? onIceConnectionState;

  @override
  Function(RTCPeerConnectionState state)? onConnectionState;

  @override
  Function(RTCTrackEvent event)? onTrack;

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    remoteDesc = description;
  }

  @override
  Future<RTCSessionDescription> createAnswer([Map<String, dynamic>? constraints]) async {
    return RTCSessionDescription('v=0\r\no=viewer 67890\r\ns=answer', 'answer');
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    localDesc = description;
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

  testWidgets('ViewerScreen initial UI has textfield and Join button is disabled until 6 digits', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    expect(find.text('Enter 6-digit Code'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final joinButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join'));
    expect(joinButton.onPressed, isNull);

    // Enter 3 digits
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();
    final joinButton3 = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join'));
    expect(joinButton3.onPressed, isNull);

    // Enter 6 digits
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    final joinButton6 = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join'));
    expect(joinButton6.onPressed, isNotNull);
  });

  testWidgets('ViewerScreen joins and handles waiting then accepted states', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'join' && m['code'] == '654321'), isTrue);

    // Server sends waiting
    fakeClient.emitMessage({'type': 'waiting'});
    await tester.pump();

    expect(find.text('Waiting for host to accept...'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Server sends accepted
    fakeClient.emitMessage({'type': 'accepted'});
    await tester.pump();

    expect(find.text('Host accepted!'), findsOneWidget);
  });

  testWidgets('ViewerScreen handles host declined state', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    await tester.enterText(find.byType(TextField), '112233');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    fakeClient.emitMessage({'type': 'waiting'});
    await tester.pump();

    // Server sends declined
    fakeClient.emitMessage({'type': 'declined'});
    await tester.pump();

    expect(find.text('Host declined'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    // Tap Try Again
    await tester.tap(find.text('Try Again'));
    await tester.pump();

    expect(find.text('Enter 6-digit Code'), findsOneWidget);
  });

  testWidgets('ViewerScreen shows specific error texts for invalid_code, room_busy, too_many_attempts', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    // 1. invalid_code
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    fakeClient.emitMessage({'type': 'error', 'message': 'invalid_code'});
    await tester.pump();

    expect(find.text('Invalid code. Please check and try again.'), findsOneWidget);

    // 2. room_busy
    fakeClient.emitMessage({'type': 'error', 'message': 'room_busy'});
    await tester.pump();

    expect(find.text('Room is busy. Another viewer is already connected.'), findsOneWidget);

    // 3. too_many_attempts
    fakeClient.emitMessage({'type': 'error', 'message': 'too_many_attempts'});
    await tester.pump();

    expect(find.text('Too many failed attempts. You have been locked out.'), findsOneWidget);
  });

  testWidgets('ViewerScreen handles incoming WebRTC offer, creates answer, exchanges ICE and handles track', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();
    Map<String, dynamic>? capturedConfig;

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (config) async {
          capturedConfig = config;
          return fakePC;
        },
      ),
    ));

    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    // Verify WebRTC initialized on Join
    expect(fakeRenderer.isInitialized, isTrue);
    expect(capturedConfig?['iceServers'][0]['urls'], 'stun:stun.l.google.com:19302');

    // Simulate offer from host
    fakeClient.emitMessage({
      'type': 'offer',
      'sdp': 'v=0\r\nhost-offer-sdp',
    });
    await tester.pump();

    // Verify remote description set & answer sent
    expect(fakePC.remoteDesc?.sdp, 'v=0\r\nhost-offer-sdp');
    expect(fakePC.localDesc?.type, 'answer');
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'answer' && m['sdp'] != null), isTrue);

    // Simulate local ICE candidate generated by PC
    fakePC.onIceCandidate?.call(RTCIceCandidate('candidate:1 1 UDP ...', 'video', 0));
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'ice' && m['candidate'] != null), isTrue);

    // Simulate incoming ICE candidate from host
    fakeClient.emitMessage({
      'type': 'ice',
      'candidate': {
        'candidate': 'candidate:2 1 UDP ...',
        'sdpMid': 'video',
        'sdpMLineIndex': 0,
      },
    });
    await tester.pump();
    expect(fakePC.candidatesAdded.length, 1);
    expect(fakePC.candidatesAdded.first.candidate, 'candidate:2 1 UDP ...');

    // Simulate incoming track
    final fakeStream = FakeMediaStream();
    fakePC.onTrack?.call(RTCTrackEvent(
      receiver: null as dynamic,
      streams: [fakeStream],
      track: fakeStream.tracks.first,
      transceiver: null as dynamic,
    ));
    await tester.pump();

    expect(fakeRenderer.srcObject, equals(fakeStream));
    expect(find.byType(RTCVideoView), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);

    // Tap Leave button
    await tester.tap(find.text('Leave'));
    await tester.pump();

    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isTrue);
    expect(fakeClient.isClosed, isTrue);
    expect(fakePC.isClosed, isTrue);
    expect(fakeRenderer.isDisposed, isTrue);
  });

  testWidgets('ViewerScreen handles ended message by cleaning up and showing Session ended SnackBar', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    fakeClient.emitMessage({'type': 'accepted'});
    await tester.pump();

    // Remote side ends session
    fakeClient.emitMessage({'type': 'ended'});
    await tester.pump();

    // Verify cleanup
    expect(fakeClient.sentMessages.any((m) => m['type'] == 'end'), isFalse);
    expect(fakeClient.isClosed, isTrue);
    expect(fakePC.isClosed, isTrue);
    expect(fakeRenderer.isDisposed, isTrue);
    expect(find.widgetWithText(SnackBar, 'Session ended'), findsOneWidget);
  });

  testWidgets('ViewerScreen handles peer-left and connection loss with SnackBar', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    fakeClient.emitMessage({'type': 'peer-left'});
    await tester.pump();

    expect(fakeClient.isClosed, isTrue);
    expect(fakePC.isClosed, isTrue);
    expect(find.widgetWithText(SnackBar, 'Session ended'), findsOneWidget);
  });

  testWidgets('ViewerScreen displays connection status indicator (Connecting, Connected, Disconnected)', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();
    final fakeRenderer = FakeRTCVideoRenderer();
    final fakePC = FakeRTCPeerConnection();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        signalingClient: fakeClient,
        rendererFactory: () async => fakeRenderer,
        peerConnectionFactory: (_) async => fakePC,
      ),
    ));

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pump();

    // After joining, WebRTC initializes and connection status is Connecting
    expect(find.byKey(const Key('viewer_appbar_connection_status')), findsOneWidget);
    expect(find.text('Connecting'), findsOneWidget);

    // Simulate state transition to Connected
    fakePC.onConnectionState?.call(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);

    // Simulate state transition to Disconnected
    fakePC.onConnectionState?.call(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
    await tester.pump();
    expect(find.text('Disconnected'), findsOneWidget);
  });
}
