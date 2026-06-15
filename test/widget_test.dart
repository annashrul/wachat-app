import 'package:flutter_test/flutter_test.dart';

import 'package:wachat/main.dart';

void main() {
  testWidgets('App boots to auth gate', (WidgetTester tester) async {
    await tester.pumpWidget(const WaChatApp());
    expect(find.byType(WaChatApp), findsOneWidget);
  });
}
