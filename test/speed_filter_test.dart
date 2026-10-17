import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/utils/speed_filter.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/models/navigation_session.dart';
import 'package:justride_ui/core/models/destination.dart';

void main() {
  group('SpeedFilter Tests', () {
    late SpeedFilter filter;

    setUp(() {
      filter = SpeedFilter();
    });

    test('Returns 0.0 when parked (raw speed < 2.5 km/h)', () {
      // 0.5 m/s = 1.8 km/h (< 2.5 km/h deadband threshold)
      final speed = filter.process(rawSpeedMs: 0.5);
      expect(speed, 0.0);
    });

    test('Returns 0.0 when stationary (0.0 m/s)', () {
      final speed = filter.process(rawSpeedMs: 0.0);
      expect(speed, 0.0);
    });

    test('Returns converted km/h when riding normally', () {
      // 10.0 m/s = 36.0 km/h
      final speed = filter.process(rawSpeedMs: 10.0);
      expect(speed, closeTo(36.0, 0.1));
    });

    test('Returns null when GPS unavailable (null input)', () {
      final speed = filter.process(rawSpeedMs: null);
      expect(speed, isNull);
    });

    test('Returns 0.0 when negative speed reported by Android (-1.0)', () {
      final speed = filter.process(rawSpeedMs: -1.0);
      expect(speed, 0.0);
    });

    test('Rejects impossible GPS jump (> 80 km/h leap in single sample)', () {
      // Start at 40 km/h (11.11 m/s)
      filter.process(rawSpeedMs: 11.11);

      // Sudden jump to 150 km/h (41.67 m/s) -> jump is 110 km/h > 80 km/h
      final rejected = filter.process(rawSpeedMs: 41.67);
      expect(rejected, closeTo(40.0, 0.5));
    });

    test('Static helper toKmh converts and applies deadband', () {
      expect(SpeedFilter.toKmh(0.5), 0.0); // 1.8 km/h -> 0.0
      expect(SpeedFilter.toKmh(10.0), closeTo(36.0, 0.1)); // 36 km/h
      expect(SpeedFilter.toKmh(-1.0), 0.0);
    });
  });

  group('RideState Tests', () {
    test('Correctly identifies active vs inactive riding states', () {
      expect(RideState.navigating.isActive, isTrue);
      expect(RideState.rerouting.isActive, isTrue);
      expect(RideState.gpsLost.isActive, isTrue);
      expect(RideState.paused.isActive, isTrue);
      expect(RideState.idle.isActive, isFalse);
      expect(RideState.arrived.isActive, isFalse);
    });

    test('Correctly maps to legacyStatus for BLE packets', () {
      expect(RideState.idle.legacyStatus, 'WAITING');
      expect(RideState.navigating.legacyStatus, 'NAVIGATING');
      expect(RideState.rerouting.legacyStatus, 'REROUTING');
      expect(RideState.paused.legacyStatus, 'PAUSED');
      expect(RideState.arrived.legacyStatus, 'ARRIVED');
      expect(RideState.gpsLost.legacyStatus, 'GPS_LOST');
    });
  });

  group('NavigationSession Tests', () {
    test('Creates and completes session tracking correctly', () {
      final session = NavigationSession.start(
        origin:
            const Destination(name: 'Home', latitude: 12.97, longitude: 77.59),
        destination: const Destination(
            name: 'Office', latitude: 12.93, longitude: 77.62),
      );

      final completed = session.complete(
        distanceMeters: 5200,
        maxSpeedKmh: 65.0,
        averageSpeedKmh: 38.0,
      );

      expect(completed.distanceKm, closeTo(5.2, 0.1));
      expect(completed.maxSpeedKmh, 65.0);
      expect(completed.averageSpeedKmh, 38.0);
      expect(completed.isCompleted, isTrue);
    });

    test('Restored active ride keeps its session ID and destination', () {
      final original = NavigationSession.start(
        origin:
            const Destination(name: 'Home', latitude: 12.97, longitude: 77.59),
        destination: const Destination(
            name: 'Office', latitude: 12.93, longitude: 77.62),
      );
      final restored = NavigationSession.fromJson(original.toJson());

      expect(restored.sessionId, original.sessionId);
      expect(restored.startTime, original.startTime);
      expect(restored.destination!.latitude, original.destination!.latitude);
      expect(restored.destination!.longitude, original.destination!.longitude);
      expect(restored.isCompleted, isFalse);
    });
  });
}
