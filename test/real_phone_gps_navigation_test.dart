import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/utils/maneuver_state_machine.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/models/navigation_state.dart';
import 'package:justride_ui/core/models/ride_state.dart';
import 'package:justride_ui/core/utils/maneuver_mapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Real Phone GPS Maneuver Progression & Lifecycle Tests', () {
    late ManeuverStateMachine fsm;
    late List<RouteStep> steps;

    setUp(() {
      fsm = ManeuverStateMachine();
      steps = [
        // Step 0: Straight road 200m North to a RIGHT turn onto MG Road
        const RouteStep(
          startLocation: LatLng(12.9710, 77.5946),
          endLocation: LatLng(12.9728, 77.5946), // 200m North
          distanceMeters: 200.0,
          durationSeconds: 25,
          maneuver: 'RIGHT',
          instruction: 'Turn right onto MG Road',
          streetName: 'Brigade Road',
          points: [
            LatLng(12.9710, 77.5946),
            LatLng(12.9728, 77.5946),
          ],
        ),
        // Step 1: Close successive LEFT turn 50m East onto Church St
        const RouteStep(
          startLocation: LatLng(12.9728, 77.5946),
          endLocation: LatLng(12.9728, 77.59506), // ~50m East
          distanceMeters: 50.0,
          durationSeconds: 8,
          maneuver: 'LEFT',
          instruction: 'Turn left onto Church Street',
          streetName: 'MG Road',
          points: [
            LatLng(12.9728, 77.5946),
            LatLng(12.9728, 77.59506),
          ],
        ),
        // Step 2: Straight 500m North to destination
        const RouteStep(
          startLocation: LatLng(12.9728, 77.59506),
          endLocation: LatLng(12.9773, 77.59506), // ~500m North
          distanceMeters: 500.0,
          durationSeconds: 60,
          maneuver: 'ARRIVE',
          instruction: 'Arrive at destination',
          streetName: 'Church Street',
          points: [
            LatLng(12.9728, 77.59506),
            LatLng(12.9773, 77.59506),
          ],
        ),
      ];
      fsm.reset(initialStepIndex: 0, initialManeuver: 'RIGHT');
    });

    test('1. At 180m (> lookahead), displays CURRENT_STRAIGHT while retaining upcoming RIGHT turn maneuver', () {
      // 180m away from endLocation at 0 km/h (lookahead is 120m)
      fsm.update(
        riderPosition: const LatLng(12.97118, 77.5946), // ~180m away
        riderHeading: 0.0,
        steps: steps,
        riderSpeedKmh: 30.0,
      );

      expect(fsm.stage, ManeuverStage.currentStraight);
      expect(fsm.maneuverStateString, 'CURRENT_STRAIGHT');
      expect(fsm.displayManeuver, 'RIGHT');
      expect(fsm.displayDistanceMeters, greaterThan(150.0));
    });

    test('2. At 100m (<= lookahead), transitions to APPROACHING with RIGHT maneuver', () {
      fsm.update(
        riderPosition: const LatLng(12.9719, 77.5946), // ~100m away
        riderHeading: 0.0,
        steps: steps,
        riderSpeedKmh: 40.0,
      );

      expect(fsm.stage, ManeuverStage.approaching);
      expect(fsm.maneuverStateString, 'APPROACHING');
      expect(fsm.displayManeuver, 'RIGHT');
      expect(fsm.displayDistanceMeters, closeTo(100.0, 5.0));
    });

    test('3. At 35m (<= 40m), transitions to TURN_PREVIEW (immediate)', () {
      fsm.update(
        riderPosition: const LatLng(12.97248, 77.5946), // ~35m away
        riderHeading: 0.0,
        steps: steps,
        riderSpeedKmh: 35.0,
      );

      expect(fsm.stage, ManeuverStage.immediate);
      expect(fsm.maneuverStateString, 'TURN_PREVIEW');
      expect(fsm.displayManeuver, 'RIGHT');
    });

    test('4. At 8m (<= 12m), locks in TURN_ACTIVE (turning)', () {
      fsm.update(
        riderPosition: const LatLng(12.97273, 77.5946), // ~8m away
        riderHeading: 10.0,
        steps: steps,
        riderSpeedKmh: 20.0,
      );

      expect(fsm.stage, ManeuverStage.turning);
      expect(fsm.maneuverStateString, 'TURN_ACTIVE');
      expect(fsm.displayManeuver, 'RIGHT');
      // Within 10m clamps to 0.0 for TFT 'NOW' display
      expect(fsm.displayDistanceMeters, 0.0);
    });

    test('5. Traversing turn with heading alignment (90° East) completes turn', () {
      // Enter turning first
      fsm.update(
        riderPosition: const LatLng(12.97273, 77.5946), // ~8m South
        riderHeading: 10.0,
        steps: steps,
        riderSpeedKmh: 20.0,
      );
      expect(fsm.stage, ManeuverStage.turning);

      // Motorcycle turns right onto MG Road, reaches 17m East with heading 90°
      fsm.update(
        riderPosition: const LatLng(12.9728, 77.59476), // ~17m East of turn
        riderHeading: 88.0, // Aligned within 35° of 90° East
        steps: steps,
        riderSpeedKmh: 25.0,
      );

      // Advances to Step 1!
      expect(fsm.activeStepIndex, 1);
    });

    test('6. Close successive turn (50m) queues directly to TURN_PREVIEW without STRAIGHT flash', () {
      // Traverse step 0
      fsm.update(
        riderPosition: const LatLng(12.97273, 77.5946),
        riderHeading: 10.0,
        steps: steps,
      );
      // Exit turn onto MG Road (Step 1 is only 50m long!)
      fsm.update(
        riderPosition: const LatLng(12.9728, 77.59476),
        riderHeading: 88.0,
        steps: steps,
      );

      expect(fsm.activeStepIndex, 1);
      // Because Step 1 is <= 70m, it immediately preloads into TURN_PREVIEW (immediate)!
      expect(fsm.stage, ManeuverStage.immediate);
      expect(fsm.maneuverStateString, 'TURN_PREVIEW');
      expect(fsm.displayManeuver, 'LEFT');
    });

    test('7. Speed-adaptive lookahead: expands at 60 km/h', () {
      // At 60 km/h (16.67 m/s), lookahead is 60 + 16.67*5 = 143.3m
      // A point at 135m away is within 143.3m -> APPROACHING
      fsm.update(
        riderPosition: const LatLng(12.97158, 77.5946), // ~135m away
        riderHeading: 0.0,
        steps: steps,
        riderSpeedKmh: 60.0,
      );

      expect(fsm.stage, ManeuverStage.approaching);
      expect(fsm.displayManeuver, 'RIGHT');

      // But at 0 km/h, lookahead is 120m -> 135m is outside lookahead -> CURRENT_STRAIGHT
      final fsmSlow = ManeuverStateMachine();
      fsmSlow.reset(initialStepIndex: 0, initialManeuver: 'RIGHT');
      fsmSlow.update(
        riderPosition: const LatLng(12.97158, 77.5946), // ~135m away
        riderHeading: 0.0,
        steps: steps,
        riderSpeedKmh: 0.0,
      );

      expect(fsmSlow.stage, ManeuverStage.currentStraight);
      expect(fsmSlow.displayManeuver, 'RIGHT'); // Always shows upcoming turn
    });

    test('8. Real phone BLE packet correctly encodes 21-byte header with maneuverState & maneuverId', () {
      const state = NavigationState(
        currentLatitude: 12.9720,
        currentLongitude: 77.5946,
        speedKmh: 42.0,
        heading: 88.0,
        remainingDistanceMeters: 750.0,
        remainingDurationSeconds: 70,
        maneuver: 'RIGHT',
        maneuverText: 'MG Road',
        maneuverDistanceMeters: 80.0,
        nextManeuver: 'LEFT',
        nextManeuverText: 'Church Street',
        maneuverId: 1,
        maneuverState: 'TURN_PREVIEW',
        gpsAvailable: true,
        bleConnected: true,
        rideState: RideState.navigating,
      );

      final packet = BleNavigationPacket.fromState(
        state,
        opCode: BleNavOpCode.navUpdate,
      );

      final binary = packet.toBinary();

      expect(binary.length, 21 + 'MG Road'.length + 4 + 'Church Street'.length);
      expect(binary[0], 0x02); // OpCode update
      expect(binary[1], 5);    // JustRideManeuverCode right = 5
      expect(binary[16] & 0x01, 1); // isNavigating
      expect(binary[17], 3);   // parseManeuverStateCode('TURN_PREVIEW') = 3
      expect(binary[18], 1);   // maneuverId = 1
      expect(binary[19], 0);   // maneuverId high byte = 0
      expect(binary[20], 7);   // text length = 7
    });

    test('9. U-turn progression, countdown display, and completion upon 180° reversal', () {
      final uturnSteps = [
        const RouteStep(
          startLocation: LatLng(12.9710, 77.5946),
          endLocation: LatLng(12.9725, 77.5946), // ~166m North
          distanceMeters: 166.0,
          durationSeconds: 20,
          maneuver: 'U_TURN',
          instruction: 'Make a U-turn at Junction',
          streetName: 'Outer Ring Road',
          points: [
            LatLng(12.9710, 77.5946),
            LatLng(12.9725, 77.5946),
          ],
        ),
        const RouteStep(
          startLocation: LatLng(12.9725, 77.5946),
          endLocation: LatLng(12.9700, 77.5946), // Heading South after U-turn
          distanceMeters: 277.0,
          durationSeconds: 30,
          maneuver: 'STRAIGHT',
          instruction: 'Continue on Outer Ring Road',
          streetName: 'Outer Ring Road',
          points: [
            LatLng(12.9725, 77.5946),
            LatLng(12.9700, 77.5946),
          ],
        ),
      ];

      final uturnFsm = ManeuverStateMachine();
      uturnFsm.reset(initialStepIndex: 0, initialManeuver: 'U_TURN');

      // Approaching at 80m
      uturnFsm.update(
        riderPosition: const LatLng(12.97178, 77.5946), // ~80m South of turn
        riderHeading: 0.0, // Moving North
        steps: uturnSteps,
        riderSpeedKmh: 40.0,
      );
      expect(uturnFsm.stage, ManeuverStage.approaching);
      expect(uturnFsm.displayManeuver, 'U_TURN');
      expect(uturnFsm.displayDistanceMeters, closeTo(80.0, 5.0));

      // Immediate preview at 30m
      uturnFsm.update(
        riderPosition: const LatLng(12.97223, 77.5946), // ~30m South
        riderHeading: 0.0,
        steps: uturnSteps,
        riderSpeedKmh: 30.0,
      );
      expect(uturnFsm.stage, ManeuverStage.immediate);
      expect(uturnFsm.displayManeuver, 'U_TURN');

      // Turning active at junction (8m away)
      uturnFsm.update(
        riderPosition: const LatLng(12.97243, 77.5946), // ~8m South
        riderHeading: 10.0,
        steps: uturnSteps,
        riderSpeedKmh: 15.0,
      );
      expect(uturnFsm.stage, ManeuverStage.turning);
      expect(uturnFsm.displayManeuver, 'U_TURN');
      expect(uturnFsm.displayDistanceMeters, 0.0); // Shows 'NOW'

      // Complete U-turn: heading reverses to South (~180°) and bike is 18m South of junction
      uturnFsm.update(
        riderPosition: const LatLng(12.97234, 77.5946), // ~18m South of turn point
        riderHeading: 185.0, // Reversed heading (~180° South, within ±45°)
        steps: uturnSteps,
        riderSpeedKmh: 20.0,
      );
      expect(uturnFsm.activeStepIndex, 1);
    });

    test('10. ManeuverMapper parses U-turns and turns from instruction text fallback', () {
      // Maneuver tag null or empty, but instruction text contains maneuver
      expect(ManeuverMapper.toJustRideManeuver(null, 'Make a U-turn at Main Street'), 'U_TURN');
      expect(ManeuverMapper.toJustRideManeuver('', 'Take the U-turn'), 'U_TURN');
      expect(ManeuverMapper.toJustRideManeuver(null, 'Turn left onto 2nd Avenue'), 'LEFT');
      expect(ManeuverMapper.toJustRideManeuver(null, 'Turn right onto MG Road'), 'RIGHT');
      expect(ManeuverMapper.toJustRideManeuver(null, 'Take sharp left onto Hill Rd'), 'SHARP_LEFT');
      expect(ManeuverMapper.toJustRideManeuver(null, 'Bear right towards airport'), 'SLIGHT_RIGHT');
    });

    test('11. U-turn at junction: reversing back down current road does NOT advance step index', () {
      // Rider approaches turn at 125m, enters junction zone (< 10m)
      fsm.update(
        riderPosition: const LatLng(12.97273, 77.5946), // ~8m away
        riderHeading: 10.0,
        steps: steps,
        riderSpeedKmh: 15.0,
      );
      expect(fsm.stage, ManeuverStage.turning);
      expect(fsm.activeStepIndex, 0);

      // Rider makes a U-turn at the junction and heads South (180°) back down the same road
      // (NOT taking the East 90° right turn onto MG Road)
      fsm.update(
        riderPosition: const LatLng(12.9725, 77.5946), // ~30m South of turn point
        riderHeading: 180.0, // Heading away from MG Road
        steps: steps,
        riderSpeedKmh: 20.0,
      );

      // Step index MUST NOT advance to Step 1!
      expect(fsm.activeStepIndex, 0);
      expect(fsm.displayManeuver, 'RIGHT');
    });

    test('12. setStepIndex enables step snapping when returning to original start position', () {
      // Manually set or advance step
      fsm.setStepIndex(1, 'LEFT');
      expect(fsm.activeStepIndex, 1);

      // When rider returns to step 0 coordinates, setStepIndex snaps back to step 0
      fsm.setStepIndex(0, 'RIGHT');
      expect(fsm.activeStepIndex, 0);
      expect(fsm.displayManeuver, 'RIGHT');
    });
  });
}
