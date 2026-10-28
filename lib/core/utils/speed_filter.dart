/// Filters phone GPS speed. Coordinate drift and device tilt are not speed.
class SpeedFilter {
  static const double _stationaryThresholdKmh = 3.5;
  static const double _absMaxSpeedKmh = 250;
  static const double _maxSpeedJumpKmh = 80;
  double? _lastValidKmh;
  int _movingSamples = 0;

  double? process({required double? rawSpeedMs, double? speedAccuracy}) {
    if (rawSpeedMs == null ||
        !rawSpeedMs.isFinite ||
        rawSpeedMs < 0 ||
        (speedAccuracy != null &&
            (!speedAccuracy.isFinite ||
                speedAccuracy < 0 ||
                speedAccuracy > 5))) {
      reset();
      return null;
    }
    final kmh = rawSpeedMs * 3.6;
    // A reading whose uncertainty includes zero is not evidence of motion.
    if (kmh < _stationaryThresholdKmh ||
        (speedAccuracy != null && rawSpeedMs <= speedAccuracy)) {
      _lastValidKmh = 0;
      _movingSamples = 0;
      return 0;
    }
    if (kmh > _absMaxSpeedKmh) return _lastValidKmh ?? 0;
    if ((_lastValidKmh ?? 0) > 0 &&
        (kmh - _lastValidKmh!).abs() > _maxSpeedJumpKmh) {
      return _lastValidKmh;
    }
    // One isolated noisy fix must not start the speedometer while parked.
    if ((_lastValidKmh ?? 0) == 0 && ++_movingSamples < 2) return 0;
    _lastValidKmh = kmh;
    return kmh;
  }

  void reset() {
    _lastValidKmh = null;
    _movingSamples = 0;
  }
}
