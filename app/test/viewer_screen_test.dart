import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/screens/viewer_screen.dart';
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

  testWidgets('ViewerScreen initial UI has textfield and Join button is disabled until 6 digits', (WidgetTester tester) async {
    final fakeClient = FakeSignalingClient();

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(signalingClient: fakeClient),
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

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(signalingClient: fakeClient),
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

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(signalingClient: fakeClient),
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

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(signalingClient: fakeClient),
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
}
