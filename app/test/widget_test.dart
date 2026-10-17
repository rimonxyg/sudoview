import 'package:flutter_test/flutter_test.dart';
import 'package:teachview/main.dart';

void main() {
  testWidgets('HomeScreen smoke test shows both action buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const TeachViewApp());

    expect(find.text('Share my screen'), findsOneWidget);
    expect(find.text('Watch a screen'), findsOneWidget);
  });
}
