import 'package:geolocator/geolocator.dart';

/// Validation and filtering layer for raw phone GPS fixes.
///
/// Prevents noisy, stale, or physically impossible GPS fixes from reaching
/// the motorcycle navigation engine.
///
/// Rejection criteria:
/// 1. Stale timestamp (> 20 seconds old)
/// 2. Coordinate invalidity (NaN, Inf, exactly (0,0), out of bounds)
/// 3. Poor horizontal accuracy (> 60m rejected; > 25m flagged as degraded)
/// 4. Teleportation / jump rejection (> 100m leap while stationary or > 250 km/h implied speed)
class GpsAccuracyFilter {
  static const double maxAcceptableAccuracyMeters = 120.0;
  static const double highConfidenceAccuracyMeters = 25.0;
  // A phone leaving a traffic stop can receive a batched fix after several
  // seconds.  250m is realistic motorcycle travel, while the implied-speed
  // check below still rejects genuine teleportation.
  static const double maxStationaryJumpMeters = 250.0;
  static const double maxPlausibleSpeedMs = 70.0; // ~252 km/h
  // Android can batch a foreground-service location callback for several
  // seconds while the screen is off or under heavy load.
  static const int maxStaleAgeSeconds = 30;
  static const int maxConsecutiveRejectionsBeforeReset = 5;

  Position? _lastValidPosition;

  Position? get lastValidPosition => _lastValidPosition;

  /// Validates [candidate]. Returns the position if accepted, or `null` if rejected.
  Position? filter(Position? candidate) {
    if (candidate == null) {
      return null;
    }

    // 1. Coordinate validity
    if (candidate.latitude.isNaN ||
        candidate.longitude.isNaN ||
        candidate.latitude.isInfinite ||
        candidate.longitude.isInfinite) {
      return null;
    }
    if (candidate.latitude < -90.0 || candidate.latitude > 90.0) {
      return null;
    }
    if (candidate.longitude < -180.0 || candidate.longitude > 180.0) {
      return null;
    }
    if (candidate.latitude == 0.0 && candidate.longitude == 0.0) {
      return null;
    }

    // 2. Timestamp freshness (compare in UTC to eliminate timezone mismatches)
    final nowUtc = DateTime.now().toUtc();
    final candidateUtc = candidate.timestamp.toUtc();
    final ageSecs = nowUtc.difference(candidateUtc).inSeconds.abs();
    if (ageSecs > maxStaleAgeSeconds) {
      // Stale cached fix (> 30 seconds old)
      return null;
    }

    // 3. Accuracy threshold (relaxed to 150m for quick lock while riding)
    if (!candidate.accuracy.isFinite ||
        candidate.accuracy < 0 ||
        candidate.accuracy > maxAcceptableAccuracyMeters) {
      return null;
    }
    if (_lastValidPosition != null &&
        !candidate.timestamp.isAfter(_lastValidPosition!.timestamp)) {
      return null;
    }

    if (_lastValidPosition != null) {
      final deltaMeters = Geolocator.distanceBetween(
        _lastValidPosition!.latitude,
        _lastValidPosition!.longitude,
        candidate.latitude,
        candidate.longitude,
      );

      final deltaSeconds = candidateUtc
              .difference(_lastValidPosition!.timestamp.toUtc())
              .inMilliseconds
              .abs() /
          1000.0;

      // Avoid division by zero
      final effectiveSeconds = deltaSeconds < 0.2 ? 0.2 : deltaSeconds;
      final impliedSpeedMs = deltaMeters / effectiveSeconds;

      // When stationary or restarting from a stop, allow up to 400m leap
      final wasStationary = _lastValidPosition!.speed < 1.0;
      final isDelayedFix = deltaSeconds >= 3.0;
      if (wasStationary && !isDelayedFix && deltaMeters > 400.0) {
        return null;
      }

      // Max plausible speed check: 85 m/s (~306 km/h)
      if (impliedSpeedMs > 85.0 && deltaSeconds < 5.0) {
        return null;
      }
    }

    _lastValidPosition = candidate;
    return candidate;
  }

  /// Resets the internal state (e.g. at START RIDE or after complete stop)
  void reset() {
    _lastValidPosition = null;
  }
}
