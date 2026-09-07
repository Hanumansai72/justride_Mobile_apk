import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/shared/widgets/app_logo.dart';

void main() {
  testWidgets('AppLogo renders correctly with name and tagline', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLogo(
            showTagline: true,
            isStacked: true,
          ),
        ),
      ),
    );
    expect(find.text('JustRide'), findsOneWidget);
    expect(find.text('Your Journey, Elevated.'), findsOneWidget);
  });
}
