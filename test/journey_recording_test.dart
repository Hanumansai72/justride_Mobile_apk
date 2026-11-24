import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/core/services/ride_history_service.dart';
import 'package:justride_ui/core/models/navigation_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('one total request deduplicates uploads and remains available offline',
      () async {
    SharedPreferences.setMockInitialValues({
      'justride_auth_token': 'ride-summary-test',
      'justride_user_data': '{"_id":"rider-a"}',
    });
    final api = ApiClient.instance;
    await api.init();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await api.init();
    });
    final dir = await Directory.systemTemp.createTemp('justride-summary-');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });
    final history = RideHistoryService.testing(dir);
    final ride = NavigationSession.start(origin: null, destination: null)
        .complete(
            distanceMeters: 500,
            averageSpeedKmh: 18,
            maxSpeedKmh: 20,
            activeDurationSeconds: 100);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_rides_rider-a', [ride.toJson()]);
    var summaryCalls = 0;
    await ApiClient.runWithClient(() async {
      final first = history.refreshTotalDistance();
      final second = history.refreshTotalDistance();
      expect(await first, 3500);
      expect(await second, 3500);
      expect(summaryCalls, 1);
      expect(await history.refreshTotalDistance(), 3500);
      expect(summaryCalls, 2);
      await api.saveUserData({'_id': 'rider-b'});
      expect(history.hasCurrentTotal, isFalse);
    },
        () => MockClient((request) async {
              summaryCalls++;
              expect(request.method, 'POST');
              expect(request.url.path, '/api/rides/summary');
              expect(jsonDecode(request.body), {
                'pendingSessionIds': [ride.sessionId]
              });
              return summaryCalls == 1
                  ? http.Response(
                      '{"success":true,"data":{"distanceMeters":3000}}', 200)
                  : http.Response('{"success":false,"message":"Offline"}', 503);
            }));
  });

  test('a late summary cannot replace the next account total', () async {
    SharedPreferences.setMockInitialValues({
      'justride_auth_token': 'token-a',
      'justride_user_data': '{"_id":"rider-a"}',
    });
    final api = ApiClient.instance;
    await api.init();
    addTearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await api.init();
    });
    final dir = await Directory.systemTemp.createTemp('justride-summary-race-');
    addTearDown(() async {
      await dir.delete(recursive: true);
    });
    final history = RideHistoryService.testing(dir);
    final requested = Completer<void>();
    final releaseOldResponse = Completer<void>();
    await ApiClient.runWithClient(() async {
      final old = history.refreshTotalDistance();
      await requested.future;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('justride_auth_token', 'token-b');
      await prefs.setString('justride_user_data', '{"_id":"rider-b"}');
      await api.init();
      expect(await history.refreshTotalDistance(), 2000);
      releaseOldResponse.complete();
      expect(await old, 0);
      expect(history.totalDistanceMeters.value, 2000);
      expect(prefs.containsKey('ride_distances_rider-a'), isFalse);
    },
        () => MockClient((request) async {
              if (request.headers['authorization'] == 'Bearer token-a') {
                requested.complete();
                await releaseOldResponse.future;
                return http.Response(
                    '{"success":true,"data":{"distanceMeters":1000}}', 200);
              }
              expect(request.headers['authorization'], 'Bearer token-b');
              return http.Response(
                  '{"success":true,"data":{"distanceMeters":2000}}', 200);
            }));
  });

  test('trail segments survive disk roundtrip; guest history remains local',
      () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('justride-recording-');
    final history = RideHistoryService.testing(dir);
    try {
      final session = NavigationSession.start(origin: null, destination: null);
      await history.appendTrail('guest', session.sessionId, [
        {'lat': 12, 'lon': 77, 'segment': true},
        {'lat': 12.001, 'lon': 77, 'segment': false},
        {'lat': 12.002, 'lon': 77, 'segment': true},
      ]);
      final done = session.complete(
          distanceMeters: 1000,
          averageSpeedKmh: 36,
          maxSpeedKmh: 50,
          activeDurationSeconds: 100);
      await history.save(done, 'guest');
      final rides = await history.localHistory('guest');
      expect(rides.single.sessionId, session.sessionId);
      expect(rides.single.durationSeconds, 100);
      expect(
          (await history.readTrail('guest', session.sessionId))
              .map((p) => p['segment']),
          [true, false, true]);
      expect(await history.localHistory('different_user'), isEmpty);
      expect(history.storageError.value, isNull);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
