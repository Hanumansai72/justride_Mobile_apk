import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/routes/app_routes.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/features/navigation/screens/go_screen.dart';
import 'package:justride_ui/features/navigation/widgets/voice_assistant_sheet.dart';
import 'package:justride_ui/features/dashboard/widgets/stats_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoScreen & Route Registry Tests', () {
    test('AppRoutes registers /go route correctly', () {
      expect(AppRoutes.go, equals('/go'));
      expect(AppRoutes.routes.containsKey('/go'), isTrue);
      expect(AppRoutes.routes[AppRoutes.go], isNotNull);
    });

    test('GoogleMapsService.searchPlaces rejects single-char queries', () async {
      final results = await GoogleMapsService.instance.searchPlaces('a');
      expect(results, isEmpty);
    });

    testWidgets('GoScreen renders route inputs and the preview button',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: GoScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Plan a ride'), findsOneWidget);
      expect(find.text('Current location'), findsOneWidget);
      expect(find.text('Destination'), findsOneWidget);
      expect(find.text('Preview route'), findsOneWidget);
    });

    testWidgets('VoiceAssistantSheet renders mic and quick destinations',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VoiceAssistantSheet(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Voice Assistant'), findsOneWidget);
      expect(find.text('Uppal Bus Stop'), findsOneWidget);
      expect(find.text('Secunderabad Railway Station'), findsOneWidget);
    });

    testWidgets('StatsRow renders Battery and Device Status cards',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatsRow(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DEVICE BATTERY'), findsOneWidget);
      expect(find.text('DEVICE STATUS'), findsOneWidget);
      // Verify "THIS TRIP" is removed as requested
      expect(find.text('THIS TRIP'), findsNothing);
    });
  });
}
