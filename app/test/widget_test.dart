import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teachview/main.dart';
import 'package:teachview/services/settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('HomeScreen smoke test shows both action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const TeachViewApp());

    expect(find.text('Share my screen'), findsOneWidget);
    expect(find.text('Watch a screen'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('Settings dialog edits and persists server URL', (WidgetTester tester) async {
    await tester.pumpWidget(const TeachViewApp());

    // Tap settings icon
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    // Verify dialog opened with default URL
    expect(find.text('Server Settings'), findsOneWidget);
    expect(find.text(defaultServerUrl), findsOneWidget);

    // Enter a new URL
    const newUrl = 'ws://192.168.1.99:8082';
    await tester.enterText(find.byType(TextField), newUrl);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Dialog should be dismissed
    expect(find.text('Server Settings'), findsNothing);

    // Verify SharedPreferences has the new URL
    final savedUrl = await getServerUrl();
    expect(savedUrl, equals(newUrl));

    // Reopen dialog to verify it loads the saved URL
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(find.text(newUrl), findsOneWidget);
  });
}

