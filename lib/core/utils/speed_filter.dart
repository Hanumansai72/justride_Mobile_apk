/// Dedicated speed processing layer for JustRide motorcycle HUD.
///
/// Responsibilities:
///   - Convert raw GPS speed (m/s) → km/h
///   - Apply stationary deadband (< 2.5 km/h → 0.0)
///   - Reject impossible GPS spikes (> 80 km/h jump in one sample)
///   - Displacement fallback: compute speed from Δdist/Δtime when Android
///     Doppler reading is zero or inaccurate (Bug B fix).
///   - Return null when GPS is unavailable (display as "--")
class SpeedFilter {
  /// Minimum speed threshold below which we treat the rider as stationary.
  /// Prevents GPS jitter showing 1–3 km/h when parked.
  static const double _stationaryThresholdKmh = 3.5;

  /// Maximum plausible speed increase between two consecutive samples (km/h).
  /// Rejects GPS spikes caused by satellite multipath / urban canyons.
  static const double _maxSpeedJumpKmh = 80.0;

  /// Maximum plausible absolute speed for a motorcycle (km/h).
  static const double _absMaxSpeedKmh = 250.0;

  double? _lastValidKmh;
  // Displacement-based fallback state (Bug B)
  double? _lastDisplacementKmh;

  /// Process a raw GPS speed value and return display-ready km/h.
  ///
  /// [rawSpeedMs]        — speed in metres/second from [Position.speed].
  ///                       Pass `null` or negative when GPS is unavailable.
  /// [speedAccuracy]     — GPS speed accuracy in m/s; relaxed threshold 8.0.
  /// [displacementKmh]   — optional speed computed from coordinate Δdist/Δtime
  ///                       by the caller (LocationService). Used as fallback
  ///                       when Doppler is 0 or unreliable.
  ///
  /// Returns:
  ///   - `0.0`  when stationary (below deadband)
  ///   - `null` when GPS data is entirely unavailable / invalid
  ///   - real km/h value otherwise
  double? process({
    required double? rawSpeedMs,
    double? speedAccuracy,
    double? displacementKmh,
  }) {
    // No data — GPS unavailable
    if (rawSpeedMs == null || rawSpeedMs.isNaN || rawSpeedMs.isInfinite) {
      return null;
    }

    // Android can report –1 when speed is unknown
    if (rawSpeedMs < 0) {
      // If displacement speed is reliable, use it
      if (displacementKmh != null &&
          displacementKmh > _stationaryThresholdKmh) {
        final clamped = displacementKmh.clamp(0.0, _absMaxSpeedKmh);
        _lastValidKmh = clamped;
        return clamped;
      }
      _lastValidKmh = 0.0;
      return 0.0;
    }

    // Unreliable fix (poor accuracy) — relaxed to 8.0 m/s (Bug B fix):
    // strict 5.0 m/s caused zero speed on motorcycles in urban canyons.
    if (speedAccuracy != null && !speedAccuracy.isNaN && speedAccuracy > 8.0) {
      // Try displacement fallback before returning 0
      if (displacementKmh != null &&
          displacementKmh > _stationaryThresholdKmh) {
        final clamped = displacementKmh.clamp(0.0, _absMaxSpeedKmh);
        _lastValidKmh = clamped;
        return clamped;
      }
      _lastValidKmh = 0.0;
      return 0.0;
    }

    double kmh = rawSpeedMs * 3.6;

    // If Doppler reads 0 but we know we're moving from displacement, trust it
    if (kmh < _stationaryThresholdKmh &&
        displacementKmh != null &&
        displacementKmh >= _stationaryThresholdKmh) {
      kmh = displacementKmh.clamp(0.0, _absMaxSpeedKmh);
    }

    if (kmh > _absMaxSpeedKmh) {
      // Return last valid instead of the bad spike
      return _lastValidKmh ?? 0.0;
    }

    // Spike rejection: if jump from last value is > 80 km/h, reject
    if (_lastValidKmh != null &&
        (kmh - _lastValidKmh!).abs() > _maxSpeedJumpKmh) {
      return _lastValidKmh;
    }

    // Stationary deadband
    final display = kmh < _stationaryThresholdKmh ? 0.0 : kmh;
    _lastValidKmh = display;
    return display;
  }

  /// Resets internal state (call when navigation stops or GPS is lost).
  void reset() {
    _lastValidKmh = null;
    _lastDisplacementKmh = null;
  }

  /// Convenience static helper: convert m/s → km/h with only the deadband
  /// applied (no spike filter). Useful for one-shot calls.
  static double toKmh(double speedMs) {
    if (speedMs < 0 || speedMs.isNaN) return 0.0;
    final kmh = speedMs * 3.6;
    return kmh < _stationaryThresholdKmh ? 0.0 : kmh;
  }
}
