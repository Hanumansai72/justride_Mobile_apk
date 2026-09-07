import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Internal state of off-route detection.
enum OffRouteState {
  /// Rider is within acceptable corridor of the route.
  onRoute,

  /// Rider has deviated but detection has not yet confirmed an off-route event.
  /// Intermediate state to prevent false reroutes from GPS noise.
  possiblyOffRoute,

  /// Rider has definitively left the route and rerouting should be triggered.
  offRoute,
}

/// Three-state off-route detection with hysteresis and speed/heading guards.
///
/// Prevents false reroutes triggered by:
///   - Momentary GPS jumps while stationary (noise rejection)
///   - Short parallel-road mismatches (corridor margin)
///   - Slow GPS updates at high speed (time/count dual threshold)
class OffRouteDetector {
  /// Rider must be beyond this distance from ALL polyline points to count as
  /// a potential off-route sample. Wider than the old 40m to account for
  /// 15-20m typical GPS accuracy drift on phones.
  static const double _offRouteCorridorMeters = 50.0;

  /// Speed threshold below which we suppress rerouting. A stationary or very
  /// slow rider (< 5 km/h ≈ 1.4 m/s) is likely waiting at a junction — not
  /// actually off-route.
  static const double _minSpeedForRerouteMs = 1.4; // ~5 km/h

  /// How many consecutive GPS samples beyond the corridor are needed before
  /// transitioning from POSSIBLY_OFF_ROUTE → OFF_ROUTE.
  static const int _confirmationSamples = 3;

  /// How many seconds must elapse in POSSIBLY_OFF_ROUTE before confirming.
  /// Guards against a burst of bad GPS fixes at high speed.
  static const int _confirmationSeconds = 4;

  OffRouteState _state = OffRouteState.onRoute;
  int _offRouteSampleCount = 0;
  DateTime? _offRouteStartTime;

  OffRouteState get state => _state;

  /// Reset detector (call on new route start or after reroute completes).
  void reset() {
    _state = OffRouteState.onRoute;
    _offRouteSampleCount = 0;
    _offRouteStartTime = null;
  }

  /// Evaluate the current rider position against [polylinePoints].
  ///
  /// Returns [OffRouteState.offRoute] when a definitive deviation is confirmed.
  /// Call [reset] once rerouting has begun.
  OffRouteState update({
    required LatLng riderPosition,
    required double speedMs,
    required List<LatLng> polylinePoints,
  }) {
    if (polylinePoints.isEmpty) return _state;

    // 1. Find minimum distance from rider to any polyline point.
    double minDist = double.infinity;
    for (final pt in polylinePoints) {
      final d = Geolocator.distanceBetween(
        riderPosition.latitude,
        riderPosition.longitude,
        pt.latitude,
        pt.longitude,
      );
      if (d < minDist) minDist = d;
    }

    final isOutsideCorridor = minDist > _offRouteCorridorMeters;

    if (!isOutsideCorridor) {
      // Back inside corridor — reset to ON_ROUTE immediately.
      _state = OffRouteState.onRoute;
      _offRouteSampleCount = 0;
      _offRouteStartTime = null;
      return _state;
    }

    // Outside corridor: suppress if rider is nearly stationary.
    if (speedMs < _minSpeedForRerouteMs) {
      // Stay in current state but don't escalate.
      return _state;
    }

    // Transition ON_ROUTE → POSSIBLY_OFF_ROUTE on first outside-corridor sample.
    if (_state == OffRouteState.onRoute) {
      _state = OffRouteState.possiblyOffRoute;
      _offRouteSampleCount = 1;
      _offRouteStartTime = DateTime.now();
      return _state;
    }

    // Accumulate evidence in POSSIBLY_OFF_ROUTE.
    if (_state == OffRouteState.possiblyOffRoute) {
      _offRouteSampleCount++;
      final elapsed = _offRouteStartTime != null
          ? DateTime.now().difference(_offRouteStartTime!).inSeconds
          : 0;

      if (_offRouteSampleCount >= _confirmationSamples &&
          elapsed >= _confirmationSeconds) {
        _state = OffRouteState.offRoute;
      }
    }

    return _state;
  }
}
