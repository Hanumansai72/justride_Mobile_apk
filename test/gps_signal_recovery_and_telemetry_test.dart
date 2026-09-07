import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/models/navigation_state.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/utils/gps_accuracy_filter.dart';
import 'package:justride_ui/core/utils/route_window_transformer.dart';
import 'package:justride_ui/core/utils/speed_filter.dart';

void main() {
  group('GPS Signal Lost, Recovery & Sample Ride Progression Tests', () {
    late GpsAccuracyFilter filter;
    late SpeedFilter speedFilter;

    setUp(() {
      filter = GpsAccuracyFilter();
      speedFilter = SpeedFilter();
    });

    test('SpeedFilter processes live motorcycle speeds correctly', () {
      // Parked / zero speed
      expect(speedFilter.process(rawSpeedMs: 0.0), 0.0);
      expect(speedFilter.process(rawSpeedMs: 0.5), 0.0); // 1.8 km/h < 2.5 km/h deadband

      // Riding at 36 km/h (10 m/s)
      final ridingSpeed = speedFilter.process(rawSpeedMs: 10.0);
      expect(ridingSpeed, closeTo(36.0, 0.1));

      // Accelerating to 54 km/h (15 m/s)
      final higherSpeed = speedFilter.process(rawSpeedMs: 15.0);
      expect(higherSpeed, closeTo(54.0, 0.1));

      // GPS lost / invalid speed
      expect(speedFilter.process(rawSpeedMs: null), isNull);
    });

    test('NavigationState properly formats speed and banners on GPS loss & recovery', () {
      // Initial state during ride
      final activeState = NavigationState(
        currentLatitude: 17.4370,
        currentLongitude: 78.5800,
        speedKmh: 42.0,
        heading: 90.0,
        remainingDistanceMeters: 6300.0,
        remainingDurationSeconds: 900,
        maneuver: 'STRAIGHT',
        maneuverText: '2nd Ln',
        maneuverDistanceMeters: 60.0,
        gpsAvailable: true,
        rideState: RideState.navigating,
      );

      expect(activeState.gpsAvailable, isTrue);
      expect(activeState.speedDisplay, '42');
      expect(activeState.remainingDistanceFormatted, '6.3 km');

      // 1. Simulate GPS Signal Lost
      final lostState = NavigationState.gpsLost(activeState);
      expect(lostState.gpsAvailable, isFalse);
      expect(lostState.speedDisplay, '--'); // Matches HUD '--' display
      expect(lostState.rideState, RideState.gpsLost);

      // Verify BLE binary flags (Byte 16) clear bit 2 (GPS available) on GPS lost
      final lostPacket = BleNavigationPacket.fromState(lostState);
      final lostBytes = lostPacket.toBinary();
      final lostFlags = lostBytes[16];
      expect(lostPacket.gpsAvailable, isFalse);
      expect(lostFlags & (1 << 2), 0); // Bit 2 is 0 when lost

      // 2. Simulate GPS Recovery
      final recoveredState = lostState.copyWith(
        gpsAvailable: true,
        rideState: RideState.navigating,
        speedKmh: 28.0,
      );
      expect(recoveredState.gpsAvailable, isTrue);
      expect(recoveredState.speedDisplay, '28');
      expect(recoveredState.rideState, RideState.navigating);

      // Verify BLE binary flags (Byte 16) re-enable bit 2 on GPS recovery
      final recoveredPacket = BleNavigationPacket.fromState(recoveredState);
      final recoveredBytes = recoveredPacket.toBinary();
      final recoveredFlags = recoveredBytes[16];
      expect(recoveredPacket.gpsAvailable, isTrue);
      expect(recoveredFlags & (1 << 2), isNot(0)); // Bit 2 is 1 when restored
    });

    test('Simulate sample route progression along 2nd Ln & Chengicherla Rd', () {
      // Polyline points matching user ride path
      final sampleRoute = [
        const LatLng(17.437000, 78.580000), // Pt 0: 2nd Ln start
        const LatLng(17.437200, 78.580000), // Pt 1: moving north
        const LatLng(17.437400, 78.580000), // Pt 2: approaching turn
        const LatLng(17.437400, 78.580500), // Pt 3: turn east onto Chengicherla Rd
        const LatLng(17.437400, 78.581500), // Pt 4: along Chengicherla Rd
      ];
      final destination = const LatLng(17.440000, 78.590000);

      // Step 1: Rider at Pt 0 heading North (0 deg)
      final window0 = RouteWindowTransformer.transform(
        riderPosition: sampleRoute[0],
        riderHeadingDeg: 0.0,
        polylinePoints: sampleRoute,
        destination: destination,
      );
      expect(window0.points.isNotEmpty, isTrue);
      // Origin point should be mapped near rider position (160, 160)
      expect(window0.points.first.x, closeTo(160, 5));
      expect(window0.points.first.y, closeTo(160, 5));

      // Step 2: Rider moves to Pt 2 heading North (0 deg)
      final window1 = RouteWindowTransformer.transform(
        riderPosition: sampleRoute[2],
        riderHeadingDeg: 0.0,
        polylinePoints: sampleRoute,
        destination: destination,
      );
      expect(window1.points.isNotEmpty, isTrue);

      // Step 3: Rider turns East (90 deg) onto Chengicherla Rd
      final window2 = RouteWindowTransformer.transform(
        riderPosition: sampleRoute[3],
        riderHeadingDeg: 90.0,
        polylinePoints: sampleRoute,
        destination: destination,
      );
      expect(window2.points.isNotEmpty, isTrue);
      // The road ahead in rider's POV is projected upward on screen
      expect(window2.points.first.x, closeTo(160, 5));
      expect(window2.points.first.y, closeTo(160, 5));
    });

    test('GpsAccuracyFilter accepts urban GPS fixes up to 120m accuracy', () {
      final freshFix = Position(
        latitude: 17.4370,
        longitude: 78.5800,
        timestamp: DateTime.now(),
        accuracy: 95.0, // Typical urban multi-story building canyon
        altitude: 500.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );

      final accepted = filter.filter(freshFix);
      expect(accepted, isNotNull);
      expect(accepted!.latitude, closeTo(17.4370, 0.0001));

      // Unusable accuracy (> 120m) should be rejected
      final unusableFix = Position(
        latitude: 17.4370,
        longitude: 78.5800,
        timestamp: DateTime.now(),
        accuracy: 160.0,
        altitude: 500.0,
        altitudeAccuracy: 5.0,
        heading: 0.0,
        headingAccuracy: 5.0,
        speed: 10.0,
        speedAccuracy: 1.0,
      );
      expect(filter.filter(unusableFix), isNull);
    });
  });
}
