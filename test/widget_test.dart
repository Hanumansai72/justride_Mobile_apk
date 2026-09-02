import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/app/app.dart';

void main() {
  testWidgets('Dashboard smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const JustRideApp());
    expect(find.text('Where to?'), findsOneWidget);
  });
}
