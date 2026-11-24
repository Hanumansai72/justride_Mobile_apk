import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'package:justride_ui/core/utils/user_facing_error.dart';
import 'package:justride_ui/features/profile/screens/legal_screen.dart';

void main() {
  for (final privacy in [true, false]) {
    testWidgets(
        'legal draft keeps disclosures without internal review notes ($privacy)',
        (tester) async {
      await tester
          .pumpWidget(MaterialApp(home: LegalScreen(isPrivacy: privacy)));
      expect(find.textContaining('Draft for legal review'), findsOneWidget);
      expect(find.textContaining('Review before publication:'), findsNothing);
      expect(find.textContaining('SharedPreferences'), findsNothing);
      expect(find.textContaining('backend'), findsNothing);
      if (privacy) {
        expect(find.textContaining('notification titles and text'),
            findsOneWidget);
        expect(find.textContaining('coordinates'), findsWidgets);
      }
      expect(tester.takeException(), isNull);
    });
  }
  test(
      'technical details are replaced without echoing addresses or credentials',
      () {
    for (final message in [
      'SocketException: Failed host lookup',
      'Connect failed at https://internal.example/api/login',
      'Cannot POST /api/login',
      'Connect failed for 192.168.1.20',
      r'Unable to load C:\private\update.bin',
      'MongoDB connection failed',
      'GATT write failed on ESP32',
      'Bearer private-credential',
      'api_key=private-credential',
      'eyJhbGciOiJIUzI1NiJ9.private.signature',
      'Error\nstack trace details',
    ]) {
      expect(userFacingError(message, fallback: 'Please try again.'),
          'Please try again.');
    }
  });

  test('actionable validation and device restrictions remain visible', () {
    for (final message in [
      'Please enter a valid email address.',
      'Incorrect password.',
      'This device is blocked and cannot be paired.',
      'Please wait before requesting another code.',
    ]) {
      expect(ApiResponse.error(message, statusCode: 400).message, message);
    }
  });

  test('server failures hide response details and preserve retry metadata', () {
    final response = ApiResponse.error('Private deployment details',
        statusCode: 503, retryAfterSeconds: 30);
    expect(response.message,
        'The service is temporarily unavailable. Please try again later.');
    expect(response.statusCode, 503);
    expect(response.retryAfterSeconds, 30);
    expect(response.isTransientFailure, isTrue);
    expect(ApiResponse.success(message: 'Saved').message, 'Saved');
  });
}
