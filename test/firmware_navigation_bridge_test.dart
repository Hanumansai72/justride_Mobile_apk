import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/core/models/ble_media_packet.dart';
import 'package:justride_ui/core/models/destination.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/services/navigation_service.dart';
import 'package:justride_ui/core/utils/gps_accuracy_filter.dart';
import 'package:justride_ui/core/utils/off_route_detector.dart';

Position fix(DateTime timestamp, {double accuracy = 5, double lng = 78}) =>
    Position(
      latitude: 17,
      longitude: lng,
      timestamp: timestamp,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 10,
      speedAccuracy: 1,
    );

class PhoneGps extends GeolocatorPlatform {
  final samples = StreamController<Position>.broadcast(sync: true);
  final base = DateTime.now().subtract(const Duration(seconds: 10));
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      fix(base);
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      samples.stream;
}

const destination = Destination(latitude: 17.01, longitude: 78);
const route = NavigationRoute(
    totalDistanceMeters: 1100,
    totalDurationSeconds: 300,
    polylinePoints: [
      LatLng(17, 78),
      LatLng(17.01, 78)
    ],
    steps: [
      RouteStep(
          startLocation: LatLng(17, 78),
          endLocation: LatLng(17.01, 78),
          distanceMeters: 1100,
          durationSeconds: 300,
          maneuver: 'ARRIVE',
          instruction: 'Arrive',
          streetName: 'Destination',
          points: [LatLng(17, 78), LatLng(17.01, 78)]),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'music packets expose actual unavailable states and bounded ASCII metadata',
      () {
    expect(encodeMediaSnapshot({}), [0x12, 0, 0, 0, 0, 0]);
    final bytes = encodeMediaSnapshot({
      'state': 4,
      'actions': 31,
      'volume': 500,
      'title': 'A' * 100,
      'artist': 'é' * 100
    });
    expect(bytes.length, 78);
    expect(bytes.sublist(0, 5), [0x12, 4, 31, 100, 40]);
    expect(bytes[45], 32);
    expect(bytes.sublist(46), everyElement(63));
    expect(encodeMediaSnapshot({'state': 1})[1], 1);
    expect(encodeMediaSnapshot({'state': 2})[1], 2);
  });

  test('GPS never admits repeated inaccurate/NaN or out-of-order fixes', () {
    final filter = GpsAccuracyFilter();
    final now = DateTime.now();
    for (var i = 0; i < 20; i++) {
      expect(filter.filter(fix(now, accuracy: 500)), isNull);
    }
    expect(filter.filter(fix(now, accuracy: double.nan)), isNull);
    expect(filter.filter(fix(now)), isNotNull);
    for (var i = 0; i < 20; i++) {
      expect(filter.filter(fix(now.add(const Duration(seconds: 1)), lng: 79)),
          isNull);
    }

    expect(
        filter.filter(fix(now.subtract(const Duration(seconds: 1)))), isNull);
  });

  test('off-route requires moving, accurate fixes sustained for four seconds',
      () {
    final detector = OffRouteDetector();
    final now = DateTime.now();
    OffRouteState sample(int seconds,
            {double accuracy = 5, double speed = 10}) =>
        detector.update(
            riderPosition: const LatLng(17, 78.001),
            speedMs: speed,
            accuracyMeters: accuracy,
            timestamp: now.add(Duration(seconds: seconds)),
            polylinePoints: route.polylinePoints);
    expect(sample(0), OffRouteState.possiblyOffRoute);
    expect(sample(1), OffRouteState.possiblyOffRoute);
    expect(sample(4, accuracy: 80), OffRouteState.onRoute);
    expect(sample(5), OffRouteState.possiblyOffRoute);
    expect(sample(7), OffRouteState.possiblyOffRoute);
    expect(sample(9), OffRouteState.offRoute);
    expect(sample(10, speed: 0), OffRouteState.onRoute);
  });

  test(
      'provider failure/empty road geometry never produces a direct fake route',
      () async {
    for (final response in [
      http.Response('', 503),
      http.Response(jsonEncode({'routes': [], 'code': 'Ok'}), 200)
    ]) {
      final maps = GoogleMapsService.testing(MockClient((_) async => response));
      expect(
          await maps.calculateRoute(
              origin: const LatLng(17, 78),
              destination: const LatLng(17.01, 78)),
          isNull);
    }
  });

  group('real navigation service lifecycle with isolated phone GPS', () {
    late PhoneGps gps;
    late GeolocatorPlatform previous;
    late NavigationService navigation;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      previous = GeolocatorPlatform.instance;
      gps = PhoneGps();
      GeolocatorPlatform.instance = gps;
    });
    tearDown(() async {
      await navigation.stopNavigation();
      await gps.samples.close();
      GeolocatorPlatform.instance = previous;
    });

    test(
        'duplicate start is rejected and cancellation rejects the late initial route',
        () async {
      final pending = Completer<NavigationRoute?>();
      var requests = 0;
      navigation = NavigationService.testing((_, __) {
        requests++;
        return pending.future;
      });
      final started = navigation.startNavigation(destination);
      await Future<void>.delayed(Duration.zero);
      expect(await navigation.startNavigation(destination), isFalse);
      expect(requests, 1);
      await navigation.stopNavigation();
      pending.complete(route);
      expect(await started, isFalse);
      expect(navigation.isNavigating, isFalse);
      expect(navigation.currentState.rideState, RideState.idle);
    });

    test('pause retains state and late reroute cannot resurrect a stopped ride',
        () async {
      final pending = Completer<NavigationRoute?>();
      var requests = 0;
      navigation = NavigationService.testing(
          (_, __) async => ++requests == 1 ? route : await pending.future);
      expect(await navigation.startNavigation(destination), isTrue);
      navigation.pauseNavigation();
      gps.samples
          .add(fix(gps.base.add(const Duration(seconds: 3)), lng: 78.001));
      expect(navigation.currentState.rideState, RideState.paused);
      expect(requests, 1);
      navigation.resumeNavigation();
      for (final second in [5, 7, 9]) {
        gps.samples
            .add(fix(gps.base.add(Duration(seconds: second)), lng: 78.001));
      }
      await Future<void>.delayed(Duration.zero);
      expect(requests, 2);
      expect(navigation.currentState.rerouting, isTrue);
      await navigation.stopNavigation();
      pending.complete(route);
      await Future<void>.delayed(Duration.zero);
      expect(navigation.currentState.rideState, RideState.idle);
      expect(navigation.isNavigating, isFalse);
      expect(navigation.activeRouteNotifier.value, isNull);
    });

    test(
        'failed reroute retains latest GPS and cooldown prevents request flooding',
        () async {
      final pending = Completer<NavigationRoute?>();
      var requests = 0;
      navigation = NavigationService.testing((_, __) async {
        requests++;
        return requests == 1 ? route : await pending.future;
      });
      expect(await navigation.startNavigation(destination), isTrue);
      for (final second in [5, 7, 9]) {
        gps.samples
            .add(fix(gps.base.add(Duration(seconds: second)), lng: 78.001));
      }
      gps.samples
          .add(fix(gps.base.add(const Duration(seconds: 10)), lng: 78.0011));
      pending.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(navigation.currentState.currentLongitude, 78.0011);
      expect(navigation.currentState.rerouting, isFalse);
      expect(navigation.activeRoute, same(route));
      for (final second in [11, 13, 15]) {
        gps.samples
            .add(fix(gps.base.add(Duration(seconds: second)), lng: 78.0011));
      }
      expect(requests, 2);
    });

    test('successful reroute publishes new totals and route revision',
        () async {
      final pending = Completer<NavigationRoute?>();
      var requests = 0;
      navigation = NavigationService.testing(
          (_, __) async => ++requests == 1 ? route : await pending.future);
      expect(await navigation.startNavigation(destination), isTrue);
      final revision = navigation.routeRevision;
      for (final second in [5, 7, 9]) {
        gps.samples
            .add(fix(gps.base.add(Duration(seconds: second)), lng: 78.001));
      }
      final updated = NavigationRoute(
          totalDistanceMeters: 1500,
          totalDurationSeconds: 450,
          polylinePoints: route.polylinePoints,
          steps: route.steps);
      pending.complete(updated);
      await Future<void>.delayed(Duration.zero);
      expect(navigation.routeRevision, revision + 1);
      expect(navigation.currentState.remainingDistanceMeters, 1500);
      expect(navigation.currentState.remainingDurationSeconds, 450);
      expect(navigation.currentState.rerouting, isFalse);
      expect(navigation.rideStateNotifier.value, RideState.navigating);
    });
  });
}
