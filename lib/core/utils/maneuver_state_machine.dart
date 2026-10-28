import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/google_maps_service.dart';

/// Explicit lifecycle stages for an active maneuver.
enum ManeuverStage {
  /// Distance to turn > lookahead window: riding along current road
  currentStraight,

  /// Within lookahead window (e.g. 120m–150m): upcoming turn displayed with countdown
  approaching,

  /// Close approach (80m – 150m legacy compatibility)
  upcoming,

  /// High-contrast turn preview (25m – 40m)
  immediate,

  /// Rider traversing the junction / executing the turn (< 12m - 15m)
  turning,

  /// Turn successfully completed onto outgoing road
  completed,

  /// Rider passed the turn without turning
  missed,
}

/// Evaluates turn progress, applies speed-adaptive lookahead,
/// geometric completion hysteresis, and detects missed turns.
class ManeuverStateMachine {
  ManeuverStage _stage = ManeuverStage.approaching;
  int _activeStepIndex = 0;
  String _lockedManeuver = 'STRAIGHT';
  double _lastDistanceMeters = double.infinity;
  double _minDistanceToTurn = double.infinity;
  int _increasingDistanceCount = 0;
  double _lastRiderDistToTurn = double.infinity;

  ManeuverStage get stage => _stage;
  int get activeStepIndex => _activeStepIndex;
  String get lockedManeuver => _lockedManeuver;

  /// Canonical maneuver state string matching the BLE protocol:
  /// 'CURRENT_STRAIGHT', 'APPROACHING', 'TURN_PREVIEW', 'TURN_ACTIVE', 'TURN_COMPLETED'
  String get maneuverStateString {
    switch (_stage) {
      case ManeuverStage.currentStraight:
        return 'CURRENT_STRAIGHT';
      case ManeuverStage.approaching:
      case ManeuverStage.upcoming:
        return 'APPROACHING';
      case ManeuverStage.immediate:
        return 'TURN_PREVIEW';
      case ManeuverStage.turning:
        return 'TURN_ACTIVE';
      case ManeuverStage.completed:
        return 'TURN_COMPLETED';
      case ManeuverStage.missed:
        return 'MISSED';
    }
  }

  /// Displayed maneuver string for HUD & TFT:
  /// Always displays the active / upcoming turn maneuver (e.g. 'LEFT', 'RIGHT', 'U_TURN')
  /// so the rider always knows the upcoming action in advance.
  String get displayManeuver {
    return _lockedManeuver;
  }

  /// Countdown distance in meters to display on TFT & HUD.
  /// During TURN_ACTIVE at the junction, clamps to 0.0 to show 'NOW' / 0m.
  double get displayDistanceMeters {
    if (_stage == ManeuverStage.turning && _lastRiderDistToTurn <= 10.0) {
      return 0.0;
    }
    return _lastRiderDistToTurn;
  }

  /// Resets the state machine for a new route or step.
  void reset({int initialStepIndex = 0, String initialManeuver = 'STRAIGHT'}) {
    _stage = ManeuverStage.approaching;
    _activeStepIndex = initialStepIndex;
    _lockedManeuver = initialManeuver;
    _lastDistanceMeters = double.infinity;
    _minDistanceToTurn = double.infinity;
    _increasingDistanceCount = 0;
    _lastRiderDistToTurn = double.infinity;
  }

  /// Explicitly syncs the state machine to a specific step index
  /// (e.g. when rider makes a U-turn and returns to an earlier step).
  void setStepIndex(int index, String maneuver) {
    _activeStepIndex = index;
    _lockedManeuver = maneuver;
    _stage = ManeuverStage.approaching;
    _lastDistanceMeters = double.infinity;
    _minDistanceToTurn = double.infinity;
    _increasingDistanceCount = 0;
    _lastRiderDistToTurn = double.infinity;
  }

  /// Calculates outgoing road heading (0..359) for a given step.
  double calculateOutgoingHeading(int stepIdx, List<RouteStep> steps) {
    if (stepIdx + 1 < steps.length) {
      final nextStep = steps[stepIdx + 1];
      if (nextStep.points.length > 1) {
        final b = Geolocator.bearingBetween(
          nextStep.points[0].latitude,
          nextStep.points[0].longitude,
          nextStep.points[1].latitude,
          nextStep.points[1].longitude,
        );
        return (b + 360.0) % 360.0;
      } else {
        final b = Geolocator.bearingBetween(
          steps[stepIdx].endLocation.latitude,
          steps[stepIdx].endLocation.longitude,
          nextStep.endLocation.latitude,
          nextStep.endLocation.longitude,
        );
        return (b + 360.0) % 360.0;
      }
    }
    // Fallback if no next step or for U-turn on final leg
    if (stepIdx < steps.length) {
      final cur = steps[stepIdx];
      if (cur.points.length >= 2) {
        final inBearing = Geolocator.bearingBetween(
          cur.points[cur.points.length - 2].latitude,
          cur.points[cur.points.length - 2].longitude,
          cur.points[cur.points.length - 1].latitude,
          cur.points[cur.points.length - 1].longitude,
        );
        final isUTurn = cur.maneuver.toUpperCase().contains('U_TURN') ||
            cur.maneuver.toUpperCase().contains('UTURN');
        return isUTurn
            ? (inBearing + 180.0 + 360.0) % 360.0
            : (inBearing + 360.0) % 360.0;
      }
    }
    return 0.0;
  }

  /// Updates state based on current rider position, heading, speed, and the active route steps.
  ///
  /// Returns `true` if a missed turn was detected and rerouting is needed.
  bool update({
    required LatLng riderPosition,
    required double riderHeading,
    required List<RouteStep> steps,
    double riderSpeedKmh = 0.0,
    double? remainingAlongRouteMeters,
  }) {
    if (steps.isEmpty || _activeStepIndex >= steps.length) return false;

    final currentStep = steps[_activeStepIndex];
    final nextStep = (_activeStepIndex + 1 < steps.length)
        ? steps[_activeStepIndex + 1]
        : null;

    final directDistance = Geolocator.distanceBetween(
      riderPosition.latitude,
      riderPosition.longitude,
      currentStep.endLocation.latitude,
      currentStep.endLocation.longitude,
    );
    final distToTurn = remainingAlongRouteMeters ?? directDistance;
    _lastRiderDistToTurn = distToTurn;

    // Steps already describe the maneuver at their end; never look ahead twice.
    _lockedManeuver =
        currentStep.maneuver.isEmpty ? 'STRAIGHT' : currentStep.maneuver;

    // Speed-adaptive lookahead: L(v) = max(120, 60 + v_ms * 5)
    final double lookaheadMeters =
        math.max(120.0, 60.0 + (riderSpeedKmh / 3.6) * 5.0);

    final bool isArrive = _lockedManeuver.toUpperCase().contains('ARRIVE') ||
        _lockedManeuver.toUpperCase().contains('REACHED');

    // Track minimum distance to turn point
    if (distToTurn < _minDistanceToTurn) {
      _minDistanceToTurn = distToTurn;
    }

    // ── STAGE 4: TURN_ACTIVE / TURNING (Traversing Junction) ──────────────────
    if (_stage == ManeuverStage.turning) {
      final outgoingHeading = calculateOutgoingHeading(_activeStepIndex, steps);
      final distFromTurnPoint = Geolocator.distanceBetween(
        riderPosition.latitude,
        riderPosition.longitude,
        currentStep.endLocation.latitude,
        currentStep.endLocation.longitude,
      );

      // Heading alignment check: within ±35° of outgoing road (±45° for U-turns)
      final double headingDiff =
          ((riderHeading - outgoingHeading + 540) % 360) - 180;
      final bool isUTurn = _lockedManeuver.toUpperCase().contains('U_TURN') ||
          _lockedManeuver.toUpperCase().contains('UTURN');
      final double headingTolerance = isUTurn ? 45.0 : 35.0;
      final bool headingAligned = headingDiff.abs() <= headingTolerance;

      // Distance to the NEXT step's polyline (must be on outgoing road)
      double distToNextRoad = double.infinity;
      if (nextStep != null) {
        if (nextStep.points.isNotEmpty) {
          for (final pt in nextStep.points) {
            final d = Geolocator.distanceBetween(
              riderPosition.latitude,
              riderPosition.longitude,
              pt.latitude,
              pt.longitude,
            );
            if (d < distToNextRoad) distToNextRoad = d;
          }
        } else {
          final d = Geolocator.distanceBetween(
            riderPosition.latitude,
            riderPosition.longitude,
            nextStep.startLocation.latitude,
            nextStep.startLocation.longitude,
          );
          distToNextRoad = (d <= 50.0) ? 0.0 : d;
        }
      }

      // Turn completed criteria:
      // Must be >= 10m past turn point AND heading MUST be aligned with outgoing road
      // AND must be physically close to next step's polyline (<= 25m).
      // Reversing/U-turn away from the junction will NOT advance the step!
      final bool completed = (_activeStepIndex < steps.length - 1) &&
          distFromTurnPoint >= 10.0 &&
          headingAligned &&
          distToNextRoad <= 25.0;

      if (completed) {
        _stage = ManeuverStage.completed;
        _activeStepIndex++;
        _minDistanceToTurn = double.infinity;
        _lastDistanceMeters = double.infinity;
        _increasingDistanceCount = 0;

        if (_activeStepIndex < steps.length) {
          final cur = steps[_activeStepIndex];
          _lockedManeuver = cur.maneuver.isEmpty ? 'STRAIGHT' : cur.maneuver;
          final stepDist = cur.distanceMeters;
          // Close successive turn handling: if <= 70m, directly queue into TURN_PREVIEW!
          if (stepDist <= 70.0) {
            _stage = ManeuverStage.immediate;
          } else if (stepDist <= lookaheadMeters) {
            _stage = ManeuverStage.approaching;
          } else {
            _stage = ManeuverStage.currentStraight;
          }
        }
        return false;
      }

      // Wrong turn / missed turn check during junction traversal:
      // If the rider has travelled > 25m past the turn point without heading alignment,
      // verify if they are merely returning on the current incoming road (e.g. U-turn back)
      // before declaring a missed turn reroute.
      if (distFromTurnPoint > 25.0 && !headingAligned) {
        double distToCurrentRoad = double.infinity;
        for (final pt in currentStep.points) {
          final d = Geolocator.distanceBetween(
            riderPosition.latitude,
            riderPosition.longitude,
            pt.latitude,
            pt.longitude,
          );
          if (d < distToCurrentRoad) distToCurrentRoad = d;
        }

        if (distToCurrentRoad > 30.0) {
          _stage = ManeuverStage.missed;
          return true; // REROUTE!
        }
      }

      if (distToTurn > _lastDistanceMeters && _minDistanceToTurn <= 25.0) {
        if (distToTurn > 35.0 && !headingAligned) {
          _increasingDistanceCount++;
          if (_increasingDistanceCount >= 2) {
            double distToCurrentRoad = double.infinity;
            for (final pt in currentStep.points) {
              final d = Geolocator.distanceBetween(
                riderPosition.latitude,
                riderPosition.longitude,
                pt.latitude,
                pt.longitude,
              );
              if (d < distToCurrentRoad) distToCurrentRoad = d;
            }
            if (distToCurrentRoad > 30.0) {
              _stage = ManeuverStage.missed;
              return true; // REROUTE!
            }
          }
        }
      }
      _lastDistanceMeters = distToTurn;
      return false;
    }

    // ── STAGE PROGRESSION (CURRENT_STRAIGHT -> APPROACHING -> PREVIEW -> ACTIVE) ──
    if (distToTurn <= 14.0) {
      _stage = ManeuverStage.turning; // TURN_ACTIVE
    } else if (distToTurn <= 40.0) {
      _stage = ManeuverStage.immediate; // TURN_PREVIEW
    } else if (distToTurn <= lookaheadMeters) {
      _stage = ManeuverStage.approaching; // APPROACHING
    } else {
      // If the step maneuver is STRAIGHT, keep approaching/straight
      if (currentStep.maneuver.toUpperCase() == 'STRAIGHT') {
        _stage = ManeuverStage.approaching;
      } else {
        _stage = ManeuverStage.currentStraight;
      }
    }

    // Missed Turn Detection:
    // If rider approached the turn (< 30m) and is now moving away (> 35m) without having turned:
    if (distToTurn > _lastDistanceMeters &&
        _minDistanceToTurn <= 30.0 &&
        distToTurn > 35.0) {
      _increasingDistanceCount++;
      if (_increasingDistanceCount >= 2 && !isArrive) {
        _stage = ManeuverStage.missed;
        return true; // Trigger reroute!
      }
    } else if (distToTurn < _lastDistanceMeters) {
      _increasingDistanceCount = 0;
    }

    _lastDistanceMeters = distToTurn;
    return false;
  }

  /// Manually advance step (e.g. upon successful step completion)
  void advanceStep() {
    _activeStepIndex++;
    _stage = ManeuverStage.approaching;
    _lastDistanceMeters = double.infinity;
    _minDistanceToTurn = double.infinity;
    _increasingDistanceCount = 0;
    _lastRiderDistToTurn = double.infinity;
  }
}
