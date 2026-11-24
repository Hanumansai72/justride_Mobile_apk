import 'package:justride_ui/core/models/navigation_session.dart';
import 'package:justride_ui/core/services/offline_touring_service.dart';
import 'package:justride_ui/core/utils/off_route_detector.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/core/models/destination.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/services/navigation_service.dart';
import 'package:justride_ui/core/services/location_service.dart';

Position sample(DateTime at, double longitude,
        {double latitude = 12.001, double speed = 10}) =>
    Position(
        longitude: longitude,
        latitude: latitude,
        timestamp: at,
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        hasSpeed: true,
        hasAccuracy: true,
        hasSpeedAccuracy: true,
        speed: speed,
        speedAccuracy: 0);

class FakeGps extends GeolocatorPlatform {
  final started = DateTime.now().subtract(const Duration(seconds: 16));
  final fixes = StreamController<Position>.broadcast(sync: true);
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.whileInUse;
  @override
  Future<Position> getCurrentPosition(
          {LocationSettings? locationSettings}) async =>
      sample(started, 77);
  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) =>
      fixes.stream;
  Future<void> deviate() async {
    const longitudes = [77.00015, 77.00035, 77.00055, 77.0007, 77.0008];
    for (var i = 0; i < longitudes.length; i++) {
      fixes.add(
          sample(started.add(Duration(seconds: (i + 1) * 2)), longitudes[i]));
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

NavigationRoute route({double longitude = 77, String action = 'STRAIGHT'}) {
  final start = LatLng(12.001, longitude), end = const LatLng(12.02, 77);
  return NavigationRoute(
      totalDistanceMeters: 2200,
      totalDurationSeconds: 300,
      polylinePoints: [
        start,
        end
      ],
      steps: [
        RouteStep(
            startLocation: start,
            endLocation: end,
            distanceMeters: 2200,
            durationSeconds: 300,
            maneuver: action,
            instruction: 'Follow the selected road',
            streetName: 'Selected road',
            points: [start, end])
      ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GeolocatorPlatform original;
  late FakeGps gps;
  NavigationService? navigation;
  setUp(() {
    LocationService.instance.resetFixForTesting();
    SharedPreferences.setMockInitialValues({});
    original = GeolocatorPlatform.instance;
    gps = FakeGps();
    GeolocatorPlatform.instance = gps;
  });
  tearDown(() async {
    if (navigation != null) await navigation!.stopNavigation();
    await LocationService.instance.stopTracking();
    await gps.fixes.close();
    GeolocatorPlatform.instance = original;
    navigation = null;
  });
  Future<NavigationService> start(
      Future<NavigationRoute?> Function(LatLng, LatLng) load) async {
    final nav =
        NavigationService.testing(load, startDisplay: (_) async => true);
    navigation = nav;
    expect(
        await nav.startNavigation(
            const Destination(name: 'Finish', latitude: 12.02, longitude: 77)),
        isTrue);
    return nav;
  }

  test('offline ride keeps its track and does not call an online rerouter',
      () async {
    var onlineRequests = 0;
    final nav = NavigationService.testing((_, __) async {
      onlineRequests++;
      return null;
    }, startDisplay: (_) async => true);
    navigation = nav;
    final recordedAt = DateTime.utc(2026, 11, 23);
    final recorded = NavigationSession(
      sessionId: 'offline_ride',
      startTime: recordedAt,
      durationSeconds: 60,
      destination:
          const Destination(name: 'End', latitude: 12.003, longitude: 77),
    );
    final pack = OfflineTouringPack.fromTrail(recorded, [
      for (var i = 0; i <= 5; i++)
        {
          'lat': 12.001 + i * .0004,
          'lon': 77,
          'at': recordedAt.add(Duration(seconds: i * 5)).toIso8601String(),
          'segment': i == 0
        },
    ]);
    expect(
        await nav.startNavigation(pack.destination, offlineTour: pack), isTrue);
    expect(nav.activeRoute?.provider, OfflineTouringPack.provider);
    await gps.deviate();
    expect(nav.currentState.rerouting, isTrue);
    expect(nav.currentState.maneuverText, 'Off track - rejoin safely');
    expect(onlineRequests, 0);
  });

  test('confirmed accurate deviation triggers after 1.5 seconds', () {
    final detector = OffRouteDetector();
    final start = DateTime(2026, 11, 23);
    const route = [LatLng(17.4, 78.5), LatLng(17.42, 78.5)];
    OffRouteState sampleAt(int milliseconds, double accuracy) =>
        detector.update(
          riderPosition: const LatLng(17.41, 78.50035),
          speedMs: 8,
          accuracyMeters: accuracy,
          timestamp: start.add(Duration(milliseconds: milliseconds)),
          polylinePoints: route,
        );
    expect(sampleAt(0, 25), OffRouteState.onRoute);
    expect(sampleAt(100, 5), OffRouteState.possiblyOffRoute);
    expect(sampleAt(600, 5), OffRouteState.possiblyOffRoute);
    expect(sampleAt(1500, 5), OffRouteState.possiblyOffRoute);
    expect(sampleAt(1600, 5), OffRouteState.offRoute);
  });

  test(
      'failed reroute keeps off-route alert, backs off, then installs the new route',
      () async {
    var requests = 0;
    final replacement = route(longitude: 77.0008, action: 'LEFT');
    final nav = await start((_, __) async {
      requests++;
      if (requests == 1) return route();
      if (requests == 2) throw StateError('Network unavailable');
      return replacement;
    });
    await gps.deviate();
    expect(requests, 2);
    expect(nav.currentState.rerouting, isTrue);
    expect(nav.currentState.maneuverText, 'Off route - retrying');
    gps.fixes.add(sample(DateTime.now(), 77.0008));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(requests, 2); // No immediate request storm during backoff.
    expect(nav.currentState.rerouting, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 2150));
    gps.fixes.add(sample(DateTime.now(), 77.0008));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(requests, 3);
    expect(nav.activeRoute, same(replacement));
    expect(nav.currentState.rerouting, isFalse);
    expect(nav.currentState.maneuver, 'LEFT');
  }, timeout: const Timeout(Duration(seconds: 45)));

  test(
      'returning to the route clears a failed alert without another API request',
      () async {
    var requests = 0;
    final nav = await start((_, __) async => ++requests == 1 ? route() : null);
    await gps.deviate();
    expect(nav.currentState.rerouting, isTrue);
    gps.fixes.add(sample(DateTime.now(), 77));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(requests, 2);
    expect(nav.currentState.rerouting, isFalse);
    expect(nav.currentState.maneuverText, 'Follow the selected road');
  });

  test('a response arriving after stop cannot restart guidance', () async {
    var requests = 0;
    final waiting = Completer<NavigationRoute?>();
    final nav = await start(
        (_, __) => ++requests == 1 ? Future.value(route()) : waiting.future);
    await gps.deviate();
    expect(nav.currentState.rerouting, isTrue);
    await nav.stopNavigation();
    waiting.complete(route(longitude: 77.0008));
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(nav.currentState.rideState, RideState.idle);
    expect(nav.isNavigating, isFalse);
  });
  test('future stops edit locally; skipping fetches only the new active leg',
      () async {
    var requests = 0;
    final nav = await start((_, __) async {
      requests++;
      return route();
    });
    const second = Destination(name: 'Second', latitude: 12.03, longitude: 77);
    const third = Destination(name: 'Third', latitude: 12.04, longitude: 77);
    await nav.addStop(second);
    await nav.addStop(third);
    await nav.moveStop(2, 1);
    expect(
        nav.remainingStops.map((s) => s.name), ['Finish', 'Third', 'Second']);
    expect(requests, 1);
    await nav.skipStop();
    expect(requests, 2);
    expect(nav.currentDestination, third);
    expect(nav.currentState.rerouting, isFalse);
    await nav.removeStop(1);
    expect(nav.remainingStops, [third]);
    expect(requests, 2);
  });

  test('next-stop failure stays pending even on the previous route', () async {
    var requests = 0;
    final nav = await start((_, __) async => ++requests == 1 ? route() : null);
    await nav.addStop(
        const Destination(name: 'Second', latitude: 12.03, longitude: 77));
    await nav.skipStop();
    expect(nav.currentDestination!.name, 'Second');
    gps.fixes.add(sample(DateTime.now(), 77));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(nav.currentState.rerouting, isTrue);
    expect(nav.currentState.maneuverText, 'Next stop - retrying');
    expect(requests, 2);
  });

  test(
      'confirmed intermediate arrival advances exactly once without ending the ride',
      () async {
    var requests = 0;
    final nav = NavigationService.testing((_, __) async {
      requests++;
      if (requests > 1) return route();
      const point = LatLng(12.001, 77);
      return const NavigationRoute(
          totalDistanceMeters: 0,
          totalDurationSeconds: 0,
          polylinePoints: [
            point,
            point
          ],
          steps: [
            RouteStep(
                startLocation: point,
                endLocation: point,
                distanceMeters: 0,
                durationSeconds: 0,
                maneuver: 'ARRIVE',
                instruction: 'Arrive',
                streetName: '',
                points: [point, point])
          ]);
    }, startDisplay: (_) async => true);
    navigation = nav;
    expect(
        await nav.startNavigation(
            const Destination(name: 'First', latitude: 12.001, longitude: 77)),
        isTrue);
    await nav.addStop(
        const Destination(name: 'Second', latitude: 12.02, longitude: 77));
    final start = DateTime.now().subtract(const Duration(seconds: 7));
    for (var i = 0; i < 7; i++) {
      gps.fixes.add(sample(start.add(Duration(seconds: i)), 77, speed: 0));
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(requests, 2);
    expect(nav.currentDestination!.name, 'Second');
    expect(nav.isNavigating, isTrue);
    expect(nav.remainingStops.length, 1);
  });
}
