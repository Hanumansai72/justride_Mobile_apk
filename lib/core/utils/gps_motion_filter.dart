import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'speed_filter.dart';

/// Holds a stopped rider at one anchor instead of summing GPS wander.
class GpsMotionFilter {
  final SpeedFilter _speed = SpeedFilter();
  Position? _last;
  bool _moving = false;
  Position? _displacedFix;

  Position? process(Position fix) {
    final last = _last;
    // Cached / duplicate fixes must not count as confirmation of movement.
    if (last != null && !fix.timestamp.isAfter(last.timestamp)) return null;
    if (last != null &&
        fix.timestamp.difference(last.timestamp) >
            const Duration(seconds: 10)) {
      reset();
    }
    var kmh = _speed.process(
          rawSpeedMs: fix.hasSpeed && fix.accuracy <= 25 ? fix.speed : null,
          speedAccuracy: fix.hasSpeedAccuracy ? fix.speedAccuracy : null,
        ) ??
        0;
    final anchor = _last;
    var hold = false;
    if (anchor != null) {
      final displacement = Geolocator.distanceBetween(
          anchor.latitude, anchor.longitude, fix.latitude, fix.longitude);
      // Keep a fixed anchor while stopped: small changes cannot accumulate.
      final uncertainty = math.max(
          3.0, math.max(anchor.accuracy, fix.accuracy).clamp(3.0, 15.0));
      hold = (!_moving || kmh == 0) && displacement <= uncertainty;
      // Until speed confirms motion, drift outside the radius is still drift.
      // Poor fixes cannot move the anchor or start the speedometer.
      if ((kmh == 0 && fix.hasSpeed) || fix.accuracy > 25) hold = true;
      if (hold &&
          fix.accuracy <= 25 &&
          displacement > math.max(20, 2 * fix.accuracy)) {
        final prior = _displacedFix;
        if (prior != null) {
          final seconds =
              fix.timestamp.difference(prior.timestamp).inMilliseconds / 1000;
          final separation = Geolocator.distanceBetween(
              prior.latitude, prior.longitude, fix.latitude, fix.longitude);
          final minimumProgress =
              math.max(5.0, (prior.accuracy + fix.accuracy) / 2);
          final priorDisplacement = Geolocator.distanceBetween(anchor.latitude,
              anchor.longitude, prior.latitude, prior.longitude);
          if (seconds > 0 &&
              seconds <= 5 &&
              separation <= 15 + 60 * seconds &&
              displacement - priorDisplacement >= minimumProgress) {
            hold = false;
          }
        }
        _displacedFix = hold ? fix : null;
      } else {
        _displacedFix = null;
      }
      if (hold) kmh = 0;
    }
    _moving = kmh > 0;
    // Preserve the fix's timestamp and accuracy so stationary updates remain
    // live and a weak signal still reports its real quality.
    final result = Position(
      latitude: hold ? anchor!.latitude : fix.latitude,
      longitude: hold ? anchor!.longitude : fix.longitude,
      timestamp: fix.timestamp,
      accuracy: fix.accuracy,
      altitude: fix.altitude,
      altitudeAccuracy: fix.altitudeAccuracy,
      heading: hold ? anchor!.heading : fix.heading,
      headingAccuracy: fix.headingAccuracy,
      speed: kmh / 3.6,
      speedAccuracy: fix.speedAccuracy,
      floor: fix.floor,
      isMocked: fix.isMocked,
      hasAccuracy: fix.hasAccuracy,
      hasAltitude: fix.hasAltitude,
      hasAltitudeAccuracy: fix.hasAltitudeAccuracy,
      hasHeading: fix.hasHeading,
      hasHeadingAccuracy: fix.hasHeadingAccuracy,
      hasSpeed: fix.hasSpeed,
      hasSpeedAccuracy: fix.hasSpeedAccuracy,
    );
    _last = result;
    return result;
  }

  void reset() {
    _last = null;
    _displacedFix = null;
    _moving = false;
    _speed.reset();
  }
}
