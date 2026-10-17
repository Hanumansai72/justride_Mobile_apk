import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/app/theme/app_theme.dart';
import 'package:justride_ui/core/models/navigation_session.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'package:justride_ui/core/services/ride_history_service.dart';
import 'package:justride_ui/core/services/backend_service.dart';
import 'package:justride_ui/features/auth/widgets/login_form.dart';
import 'package:justride_ui/features/auth/screens/signup_screen.dart';
import 'package:justride_ui/features/dashboard/screens/dashboard_screen.dart';
import 'package:justride_ui/features/trips/screens/trips_screen.dart';
import 'package:justride_ui/features/places/screens/places_screen.dart';

Map<String, dynamic> ride(String id, String title) => {
      'sessionId': id,
      'startTime': '2026-10-17T08:00:00Z',
      'endTime': '2026-10-17T08:20:00Z',
      'status': 'completed',
      'origin': {'name': 'Home', 'latitude': 17.4, 'longitude': 78.4},
      'destination': {'name': title, 'latitude': 17.5, 'longitude': 78.5},
      'distanceMeters': 5000,
      'durationSeconds': 1200,
      'averageSpeedKmh': 15,
      'maxSpeedKmh': 32,
    };

Widget app(Widget home) => MaterialApp(theme: buildAppTheme(), home: home);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.clearAuth();
    await ApiClient.instance.saveAuthToken('test-user-a');
    await ApiClient.instance.saveUserData({'_id': 'a', 'fullName': 'Rider'});
  });

  test('ride upload retries persist per user and parse the backend response',
      () async {
    final service = RideHistoryService.instance;
    var offline = true;
    final posted = <String>[];
    await http.runWithClient(() async {
      final session = NavigationSession.fromMap(ride('same-session', 'Office'));
      await service.save(session, 'a');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('pending_rides_a'), hasLength(1));
      await service.save(session, 'a');
      expect(prefs.getStringList('pending_rides_a'), hasLength(1));
      await ApiClient.instance.saveUserData({'_id': 'b'});
      await ApiClient.instance.saveAuthToken('test-user-b');
      offline = false;
      await service.syncPending();
      expect(posted, isEmpty);
      await ApiClient.instance.saveUserData({'_id': 'a'});
      await ApiClient.instance.saveAuthToken('test-user-a');
      await service.syncPending();
      expect(posted, ['same-session']);
      expect(prefs.getStringList('pending_rides_a'), isEmpty);
      final page = await service.getPage(limit: 1);
      expect(page.success, isTrue);
      expect(page.data!.items.single.destination!.name, 'Office');
      expect(page.data!.items.single.distanceKm, 5);
    },
        () => MockClient((request) async {
              if (request.method == 'POST') {
                if (offline) return http.Response('{"success":false}', 503);
                expect(request.headers['Authorization'], 'Bearer test-user-a');
                posted.add(
                    (jsonDecode(request.body) as Map)['sessionId'] as String);
                return http.Response(
                    jsonEncode({
                      'success': true,
                      'data': ride('same-session', 'Office')
                    }),
                    200);
              }
              expect(request.url.queryParameters['limit'], '1');
              return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': {
                      'items': [ride('same-session', 'Office')],
                      'total': 1,
                      'page': 1,
                      'limit': 1,
                    }
                  }),
                  200);
            }));
  });

  test('signup binds new ride history to the newly registered user', () async {
    await http.runWithClient(() async {
      final result = await BackendService.instance.register(
        name: 'New rider',
        email: 'test@example.invalid',
        password: 'test-only',
        phonenumber: '9000000000',
      );
      expect(result.success, isTrue);
      expect(await RideHistoryService.instance.currentUserId(), 'new-user');
    },
        () => MockClient((_) async => http.Response(
            jsonEncode({
              'success': true,
              'accessToken': 'new-user-test-token',
              'user': {'_id': 'new-user', 'name': 'New rider'},
            }),
            201)));
  });

  for (final size in [const Size(320, 740), const Size(480, 900)]) {
    testWidgets('login aligned and Google signup above fields at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const Scaffold(
          body: Padding(
        padding: EdgeInsets.all(16),
        child: LoginForm(),
      ))));
      await tester.pumpAndSettle();
      final remember = tester.getCenter(find.text('Remember me'));
      final forgot = tester.getCenter(find.text('Forgot Password?'));
      expect((remember.dy - forgot.dy).abs(), lessThan(2));
      expect(remember.dx, lessThan(forgot.dx));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(const SignupScreen()));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('Continue with Google')).dy,
          lessThan(tester.getTopLeft(find.text('Full Name')).dy));
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'dashboard latest ride, history pagination and dark places search use API data',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(480, 1100);
    addTearDown(tester.view.reset);
    final reads = <Uri>[];
    await http.runWithClient(() async {
      await tester.pumpWidget(app(const DashboardScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Latest ride'), findsOneWidget);
      expect(find.text('Verified latest ride'), findsOneWidget);
      expect(
          tester.getTopLeft(find.text('Latest ride')).dy,
          greaterThan(
              tester.getTopLeft(find.text('Enter Start & Destination')).dy));
      expect(
          reads.any((uri) =>
              uri.path.endsWith('/rides') &&
              uri.queryParameters['limit'] == '1'),
          isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(app(const TripsScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Verified latest ride'), findsOneWidget);
      expect(find.text('HITEC City, Hyderabad'), findsNothing);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier ride'), findsOneWidget);
      await tester.pumpWidget(app(const PlacesScreen()));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.color, const Color(0xFFF5F7F5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
        () => MockClient((request) async {
              reads.add(request.url);
              final path = request.url.path;
              dynamic data;
              if (path.endsWith('/rides')) {
                final page = int.parse(request.url.queryParameters['page']!);
                final limit = int.parse(request.url.queryParameters['limit']!);
                data = {
                  'items': [
                    ride('ride-$page',
                        page == 1 ? 'Verified latest ride' : 'Earlier ride')
                  ],
                  'total': limit == 1 ? 1 : 11,
                  'page': page,
                  'limit': limit
                };
              } else if (path.endsWith('/me')) {
                data = {'_id': 'a', 'name': 'Rider'};
              } else if (path.endsWith('/my-device')) {
                data = {
                  '_id': 'device',
                  'devicename': 'JUSTRIDE',
                  'is_active': true,
                  'is_paired': true
                };
              } else if (path.endsWith('/addresses')) {
                data = [];
              } else {
                return http.Response('{"success":false}', 404);
              }
              return http.Response(
                  jsonEncode({'success': true, 'data': data}), 200);
            }));
  });
}
