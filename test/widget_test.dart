import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/shared/widgets/app_logo.dart';

void main() {
  testWidgets('AppLogo renders correctly with name and tagline in stacked mode',
      (WidgetTester tester) async {
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
    expect(find.byType(Image), findsOneWidget);
    expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/justride-logo-horizontal.png');
    expect(find.text('Made for Bikers'), findsOneWidget);
  });

  testWidgets(
      'AppLogo renders correctly with logo on left and tagline in inline mode',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppLogo(
            showTagline: true,
            isStacked: false,
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(
        (tester.widget<Image>(find.byType(Image)).image as AssetImage)
            .assetName,
        'assets/justride-logo-horizontal.png');
    expect(find.text('Made for Bikers'), findsOneWidget);
  });
}
