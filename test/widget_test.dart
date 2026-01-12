import 'package:flutter_test/flutter_test.dart';
import 'package:even_g2_app/main.dart';

void main() {
  testWidgets('App launches without error', (WidgetTester tester) async {
    await tester.pumpWidget(const EvenG2App());
    expect(find.text('Even G2 Scanner'), findsOneWidget);
  });
}
