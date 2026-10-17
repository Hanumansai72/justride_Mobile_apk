import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/app/theme/app_theme.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'package:justride_ui/core/services/backend_service.dart';
import 'package:justride_ui/features/profile/screens/delete_account_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'pending_rides_rider': <String>['pending'],
      'justride_paired_device': '{}',
      'justride_saved_mac_address': 'AA:BB:CC:DD:EE:FF',
    });
    await ApiClient.instance.clearAuth();
    await ApiClient.instance.saveAuthToken('test-session');
    await ApiClient.instance.saveUserData({'_id': 'rider'});
  });

  test(
      'only successful OTP deletion clears credentials and local ride/device data',
      () async {
    var accepted = false;
    await http.runWithClient(() async {
      final backend = BackendService.instance;
      expect(
          (await backend.deleteAccount(password: 'current', otp: '123456'))
              .success,
          isFalse);
      expect(ApiClient.instance.isAuthenticated, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_rides_rider'), ['pending']);
      accepted = true;
      expect(
          (await backend.deleteAccount(password: 'current', otp: '654321'))
              .success,
          isTrue);
      expect(ApiClient.instance.isAuthenticated, isFalse);
      expect(prefs.containsKey('pending_rides_rider'), isFalse);
      expect(prefs.containsKey('justride_paired_device'), isFalse);
      expect(prefs.containsKey('justride_saved_mac_address'), isFalse);
    },
        () => MockClient((request) async {
              expect(request.method, 'DELETE');
              expect(request.url.path, '/api/users/delete-account');
              expect(jsonDecode(request.body), {
                'password': 'current',
                'otp': accepted ? '654321' : '123456'
              });
              return http.Response(
                  jsonEncode({
                    'success': accepted,
                    'message': accepted ? 'Deleted' : 'Incorrect deletion code.'
                  }),
                  accepted ? 200 : 400);
            }));
  });

  testWidgets(
      'linked-device popup blocks deletion until email unlink verification succeeds',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.reset);
    Future<void> pump() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var linked = true;
    var failUnlink = true;
    var otpRequests = 0;
    var deletes = 0;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: const DeleteAccountScreen(),
          routes: {'/login': (_) => const Scaffold(body: Text('Signed out'))}));
      await pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Current password'), 'current');
      await tester.ensureVisible(find.text('Send deletion code'));
      await tester.tap(find.text('Send deletion code'));
      await pump();
      expect(find.text('Unlink device first'), findsOneWidget);
      expect(otpRequests, 0);
      // Cancel does not send either OTP or delete anything.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await pump();
      expect(otpRequests, 0);
      await tester.tap(find.text('Send deletion code'));
      await pump();
      await tester.tap(find.text('Send unlink code'));
      await pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Unlink OTP'), '111111');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlink device'));
      await pump();
      expect(find.text('Incorrect unlink code.'), findsOneWidget);
      expect(otpRequests, 0);
      expect(deletes, 0);
      failUnlink = false;
      await tester.enterText(
          find.widgetWithText(TextField, 'Unlink OTP'), '222222');
      await tester.tap(find.widgetWithText(FilledButton, 'Unlink device'));
      await pump();
      expect(linked, isFalse);
      expect(otpRequests, 1);
      expect(find.text('Unlink device first'), findsNothing);
      await tester.enterText(
          find.widgetWithText(TextField, 'Account deletion OTP'), '333333');
      await tester
          .ensureVisible(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await pump();
      expect(find.text('Delete account permanently?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await pump();
      expect(deletes, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await pump();
      await tester.tap(find.text('Delete permanently'));
      await pump();
      expect(deletes, 1);
      expect(find.text('Signed out'), findsOneWidget);
      expect(ApiClient.instance.isAuthenticated, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                    jsonEncode({
                      'success': true,
                      'data': {
                        'requiresPassword': true,
                        'email': 'r***@example.invalid',
                        'linkedDevice': linked
                            ? {'_id': 'device-a', 'devicename': 'JustRide'}
                            : null,
                      }
                    }),
                    200);
              }
              if (request.url.path.endsWith('/request-unlink-otp')) {
                expect(jsonDecode(request.body), {'device_id': 'device-a'});
                return http.Response('{"success":true}', 200);
              }
              if (request.url.path.endsWith('/unlink')) {
                expect(jsonDecode(request.body), {
                  'device_id': 'device-a',
                  'otp_code': failUnlink ? '111111' : '222222'
                });
                if (failUnlink) {
                  return http.Response(
                      '{"success":false,"message":"Incorrect unlink code."}',
                      400);
                }
                linked = false;
                return http.Response('{"success":true}', 200);
              }
              if (request.url.path.endsWith('/delete-account/otp')) {
                expect(linked, isFalse);
                otpRequests++;
                return http.Response('{"success":true}', 200);
              }
              expect(request.method, 'DELETE');
              expect(linked, isFalse);
              expect(jsonDecode(request.body),
                  {'password': 'current', 'otp': '333333'});
              deletes++;
              return http.Response('{"success":true}', 200);
            }));
  });
}
