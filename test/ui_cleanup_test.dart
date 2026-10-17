import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/app/theme/app_theme.dart';
import 'package:justride_ui/core/routes/app_routes.dart';
import 'package:justride_ui/features/auth/screens/login_screen.dart';
import 'package:justride_ui/features/device/widgets/device_info_card.dart';
import 'package:justride_ui/features/profile/screens/about_screen.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget home) => MaterialApp(
        theme: buildAppTheme(),
        routes: AppRoutes.routes..remove('/'),
        home: home,
      );

  for (final size in [const Size(320, 640), const Size(430, 932)]) {
    testWidgets('About legal links scroll and return at $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await http.runWithClient(() async {
        await tester.pumpWidget(app(const AboutScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Open Source Licenses'), findsNothing);
        expect(find.textContaining('2024'), findsNothing);
        expect(find.textContaining('2026'), findsNothing);
        expect(find.byIcon(Icons.two_wheeler_rounded), findsNothing);
        for (final image in tester.widgetList<Image>(find.byType(Image))) {
          expect((image.image as AssetImage).assetName,
              'assets/justride-logo-horizontal.png');
        }

        for (final entry in [
          ('Terms & Conditions', '14. Contact and support'),
          ('Privacy Policy', '15. Contact information'),
        ]) {
          await tester.ensureVisible(find.text(entry.$1));
          await tester.tap(find.text(entry.$1));
          await tester.pumpAndSettle();
          expect(find.textContaining('Draft for legal review'), findsOneWidget);
          await tester.scrollUntilVisible(find.text(entry.$2), 500);
          expect(find.text(entry.$2).hitTestable(), findsOneWidget);
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.byType(AboutScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
          () =>
              MockClient((_) async => http.Response('{"success":false}', 200)));
    });
  }

  testWidgets('Login stays scrollable with keyboard and retains validation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();
    final imageAssets = tester.widgetList<Image>(find.byType(Image))
        .map((image) => (image.image as AssetImage).assetName);
    expect(imageAssets, contains('assets/justride-logo-horizontal.png'));
    expect(imageAssets, contains('assets/brands/google-g.png'));
    expect(find.text('Welcome back!'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(find.text('Please enter both email and password'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Continue with Google').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Product asset and connection controls fit compact screen',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const Scaffold(
      body: SafeArea(
          child: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: DeviceInfoCard(deviceName: 'JUSTRIDE', hasUpdate: false),
      )),
    )));
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image));
    expect(
        (image.image as AssetImage).assetName, 'assets/justride-device.webp');
    expect(image.fit, BoxFit.contain);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Device Shortcuts'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
