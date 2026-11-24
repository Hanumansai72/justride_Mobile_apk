import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/utils/maneuver_state_machine.dart';
import 'package:geolocator/geolocator.dart';
import 'package:justride_ui/core/utils/gps_motion_filter.dart';
import 'package:justride_ui/core/utils/maneuver_mapper.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';

Position fix(int second, double northMeters,
        {double speed = 0, double accuracy = 6, bool hasSpeed = true}) =>
    Position(
      latitude: 17 + northMeters / 111195,
      longitude: 78,
      timestamp: DateTime.utc(2026, 11, 9).add(Duration(seconds: second)),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: speed,
      speedAccuracy: 0.3,
      hasAccuracy: true,
      hasSpeed: hasSpeed,
      hasSpeedAccuracy: true,
    );

RouteStep step(String maneuver, LatLng start, LatLng end) => RouteStep(
    startLocation: start,
    endLocation: end,
    distanceMeters: 5000,
    durationSeconds: 300,
    maneuver: maneuver,
    instruction: maneuver,
    streetName: 'Selected road',
    points: [start, end]);
void main() {
  test('provider branch directions survive mapping and BLE encoding', () {
    const cases = {
      'ramp-left': 18, 'ramp-right': 19,
      'fork-left': 16, 'fork-right': 17,
      'exit-left': 14, 'exit-right': 15,
      'uturn-left': 8, 'uturn-right': 8,
      'turn-left': 4, 'turn-right': 5,
    };
    for (final entry in cases.entries) {
      final maneuver = ManeuverMapper.toJustRideManeuver(entry.key);
      expect(JustRideManeuverCode.fromString(maneuver).value, entry.value,
          reason: entry.key);
      expect(ManeuverMapper.toIcon(maneuver), isNotNull);
    }
  });
  group('Stationary GPS drift', () {
    test(
        'stationary wander and repeated noisy speeds do not move or add distance',
        () {
      final filter = GpsMotionFilter();
      final start = filter.process(fix(0, 0))!;
      for (var i = 1; i <= 120; i++) {
        final result = filter.process(
            fix(i, (i % 9 - 4).toDouble(), speed: i % 5 == 0 ? 0 : 1.4))!;
        expect(result.latitude, start.latitude);
        expect(result.speed, 0);
        expect(result.timestamp, fix(i, 0).timestamp);
      }
    });
    test('real slow movement escapes the fixed anchor and stopping holds again',
        () {
      final filter = GpsMotionFilter();
      filter.process(fix(0, 0));
      for (var i = 1; i <= 8; i++) {
        filter.process(fix(i, i * 1.5, speed: 1.5));
      }
      final moving = filter.process(fix(9, 13.5, speed: 1.5))!;
      expect(moving.latitude, greaterThan(17));
      expect(moving.speed, closeTo(1.5, 0.001));
      final stopped = filter.process(fix(10, 14))!;
      for (var i = 11; i < 20; i++) {
        final parked = filter.process(fix(i, 14 + i % 3))!;
        expect(parked.latitude, stopped.latitude);
        expect(parked.speed, 0);
      }
    });
    test('duplicate fixes cannot confirm movement and poor speed is suppressed',
        () {
      final filter = GpsMotionFilter();
      filter.process(fix(0, 0));
      filter.process(fix(1, 4, speed: 3));
      expect(filter.process(fix(1, 20, speed: 3)), isNull);
      expect(filter.process(fix(0, 20, speed: 3)), isNull);
      expect(filter.process(fix(2, 2, speed: 4, accuracy: 60))!.speed, 0);
      expect(filter.process(fix(3, 2, speed: 4, hasSpeed: false))!.speed, 0);
    });
    test('recovery after an outage is not locked to the old location', () {
      final filter = GpsMotionFilter();
      filter.process(fix(0, 0));
      final recovered = filter.process(fix(20, 100))!;
      expect(recovered.latitude, closeTo(fix(20, 100).latitude, 1e-9));
      expect(recovered.speed, 0);
    });
    test('low-speed noise outside the anchor radius still stays stopped', () {
      final filter = GpsMotionFilter();
      final start = filter.process(fix(0, 0))!;
      for (var i = 1; i < 30; i++) {
        final result = filter.process(fix(i, 20 + i % 4, speed: 0.6))!;
        expect(result.latitude, start.latitude);
        expect(result.speed, 0);
      }
    });
  });
  const start = LatLng(17, 78),
      end = LatLng(17.02, 78),
      next = LatLng(17.02, 78.02);
  for (final distance in [500.0, 1800.0, 5000.0]) {
    test('Straight $distance m does not inherit next right turn', () {
      final fsm = ManeuverStateMachine();
      fsm.update(
          riderPosition: start,
          riderHeading: 0,
          steps: [step('STRAIGHT', start, end), step('RIGHT', end, next)],
          remainingAlongRouteMeters: distance);
      expect(fsm.displayManeuver, 'STRAIGHT');
      expect(fsm.displayDistanceMeters, distance);
    });
  }
  test('Nearby endpoint does not trigger turn across a long loop', () {
    final fsm = ManeuverStateMachine();
    fsm.update(
        riderPosition: const LatLng(17.01999, 78),
        riderHeading: 0,
        steps: [step('RIGHT', start, end)],
        remainingAlongRouteMeters: 1800);
    expect(fsm.stage, ManeuverStage.currentStraight);
  });
  test('Provider ramp instruction is preserved', () {
    final fsm = ManeuverStateMachine();
    fsm.update(
        riderPosition: start,
        riderHeading: 0,
        steps: [step('RAMP_LEFT', start, end), step('RIGHT', end, next)],
        remainingAlongRouteMeters: 300);
    expect(fsm.displayManeuver, 'RAMP_LEFT');
  });
}
