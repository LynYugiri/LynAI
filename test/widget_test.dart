import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const LynAIApp());
    expect(find.byType(LynAIApp), findsOneWidget);
  });
}
