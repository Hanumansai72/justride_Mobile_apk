import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/utils/gps_accuracy_filter.dart';
import 'package:justride_ui/core/utils/maneuver_state_machine.dart';
import 'package:justride_ui/core/utils/route_window_transformer.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';

Position createPos({
  required double lat,
  required double lng,
  double accuracy = 5.0,
  double speed = 10.0,
  DateTime? timestamp,
}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: timestamp ?? DateTime.now(),
    accuracy: accuracy,
    altitude: 0.0,
    altitudeAccuracy: 0.0,
    heading: 0.0,
    headingAccuracy: 0.0,
    speed: speed,
    speedAccuracy: 0.0,
  );
}

void main() {
  group('GpsAccuracyFilter Tests', () {
    late GpsAccuracyFilter filter;

    setUp(() {
      filter = GpsAccuracyFilter();
    });

    test('Accepts valid fresh GPS position', () {
      final pos = createPos(lat: 12.9716, lng: 77.5946, accuracy: 10.0);
      final accepted = filter.filter(pos);
      expect(accepted, isNotNull);
      expect(accepted!.latitude, closeTo(12.9716, 0.0001));
    });

    test('Rejects stale GPS position (> 30 seconds old)', () {
      final oldPos = createPos(
        lat: 12.9716,
        lng: 77.5946,
        timestamp: DateTime.now().subtract(const Duration(seconds: 45)),
      );
      final accepted = filter.filter(oldPos);
      expect(accepted, isNull);
    });

    test('Rejects GPS fix with poor accuracy (> 120m)', () {
      final poorAccuracyPos = createPos(
        lat: 12.9716,
        lng: 77.5946,
        accuracy: 150.0,
      );
      final accepted = filter.filter(poorAccuracyPos);
      expect(accepted, isNull);
    });

    test('Rejects impossible teleportation jump while stationary', () {
      // Parked fix
      final parked = createPos(lat: 12.9716, lng: 77.5946, speed: 0.0);
      expect(filter.filter(parked), isNotNull);

      // Sudden jump 300 meters away while speed is 0
      final jump = createPos(lat: 12.9745, lng: 77.5946, speed: 0.0);
      expect(filter.filter(jump), isNull);
    });
  });

  group('ManeuverStateMachine Tests', () {
    late ManeuverStateMachine fsm;
    late List<RouteStep> steps;

    setUp(() {
      fsm = ManeuverStateMachine();
      steps = [
        const RouteStep(
          startLocation: LatLng(12.9716, 77.5946),
          endLocation: LatLng(12.9730, 77.5946), // ~155m North
          distanceMeters: 155.0,
          durationSeconds: 20,
          maneuver: 'RIGHT',
          instruction: 'Turn right on MG Road',
          streetName: 'MG Road',
          points: [],
        ),
        const RouteStep(
          startLocation: LatLng(12.9730, 77.5946),
          endLocation: LatLng(12.9730, 77.5980), // ~370m East
          distanceMeters: 370.0,
          durationSeconds: 45,
          maneuver: 'ARRIVE',
          instruction: 'Destination Reached',
          streetName: 'Cubbon Park',
          points: [],
        ),
      ];
      fsm.reset(initialStepIndex: 0, initialManeuver: 'RIGHT');
    });

    test('Transitions from approaching to immediate as rider draws near', () {
      // 100m away -> within lookahead window -> approaching
      fsm.update(
        riderPosition: const LatLng(12.9721, 77.5946), // ~100m away
        riderHeading: 0.0,
        steps: steps,
      );
      expect(fsm.stage, ManeuverStage.approaching);

      // 35m away -> <= 40m -> immediate (TURN_PREVIEW)
      fsm.update(
        riderPosition: const LatLng(12.97268, 77.5946), // ~35m away
        riderHeading: 0.0,
        steps: steps,
      );
      expect(fsm.stage, ManeuverStage.immediate);
    });

    test('Enters turning stage near junction and advances upon completion', () {
      // Near junction (~11m away) -> turning (TURN_ACTIVE)
      fsm.update(
        riderPosition: const LatLng(12.9729, 77.5946), // ~11m away
        riderHeading: 0.0,
        steps: steps,
      );
      expect(fsm.stage, ManeuverStage.turning);

      // Traverses turn onto MG Road (heading 90° East, ~16m past turn point) -> advances to step 1
      fsm.update(
        riderPosition: const LatLng(12.9730, 77.59475), // ~16m East
        riderHeading: 90.0, // Aligned with outgoing road
        steps: steps,
      );
      expect(fsm.activeStepIndex, 1);
    });
  });

  group('RouteWindowTransformer Tests', () {
    test('Transforms polyline points to local 320x240 screen coordinates', () {
      const rider = LatLng(12.9716, 77.5946);
      const dest = LatLng(12.9740, 77.5946); // ~266m North
      final polyline = [
        const LatLng(12.9716, 77.5946),
        const LatLng(12.9726, 77.5946),
        const LatLng(12.9740, 77.5946),
      ];

      final window = RouteWindowTransformer.transform(
        riderPosition: rider,
        riderHeadingDeg: 0.0, // Heading North
        polylinePoints: polyline,
        destination: dest,
      );

      expect(window.points.length, greaterThanOrEqualTo(2));
      // First point is near rider anchor (X=160, Y=160)
      expect(window.points.first.x, closeTo(160, 2));
      expect(window.points.first.y, closeTo(160, 2));

      // Destination is ~266m ahead, so it falls within the 500m window
      expect(window.isDestinationVisible, isTrue);
      expect(window.destinationScreenPoint, isNotNull);
      // Traveling North (heading 0), upcoming point is UP on screen (smaller Y)
      expect(window.destinationScreenPoint!.y, lessThan(160));
    });

    test('Keeps an eastbound route ahead when the rider heads east', () {
      const rider = LatLng(12.9716, 77.5946);
      const destination = LatLng(12.9716, 77.5986);
      final window = RouteWindowTransformer.transform(
        riderPosition: rider,
        riderHeadingDeg: 90.0,
        polylinePoints: const [rider, destination],
        destination: destination,
      );

      // Heading-up means an eastbound road is above the fixed rider pointer,
      // not behind it or to the side.
      expect(window.points.last.y, lessThan(160));
      expect(window.points.last.x, closeTo(160, 2));
    });
  });

  group('RouteSegmentPacket Binary Tests', () {
    test('Serializes route segment packet with opcode 0x0B', () {
      final packet = RouteSegmentPacket(
        points: const [
          ScreenPoint(160, 145),
          ScreenPoint(160, 100),
          ScreenPoint(200, 60),
        ],
        isDestinationVisible: true,
        destinationScreenPoint: const ScreenPoint(200, 60),
      );

      final binary = packet.toBinary();
      expect(binary.length, 8 + 3 * 4); // 20 bytes, including progress
      expect(binary[0], BleNavOpCode.navRouteSegment.value); // 0x0B
      expect(binary[1], 3); // 3 points
      expect(binary[2], 1); // Destination visible flag
      expect(binary.last, 0); // No completed progress yet
    });
  });
}
