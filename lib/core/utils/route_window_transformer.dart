import 'dart:math' as math;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

/// A transformed 2D point on the 320x240 landscape HUD canvas.
class ScreenPoint {
  final int x;
  final int y;

  const ScreenPoint(this.x, this.y);

  @override
  String toString() => '($x, $y)';
}

/// A sliding route window segment ready for transmission to the ESP32.
class RouteWindowSegment {
  /// Ordered polyline points in local screen space (X: 0..320, Y: 0..240)
  final List<ScreenPoint> points;

  /// Number of leading line segments already travelled in this window.
  final int completedSegmentCount;
  final int progressPercent;
  final int routeIndex;

  /// Whether the final destination marker is within this ~500m window
  final bool isDestinationVisible;

  /// Screen coordinates of the final destination marker if visible
  final ScreenPoint? destinationScreenPoint;

  const RouteWindowSegment({
    required this.points,
    this.completedSegmentCount = 0,
    this.progressPercent = 0,
    this.routeIndex = 0,
    this.isDestinationVisible = false,
    this.destinationScreenPoint,
  });

  /// Empty / fallback segment
  const RouteWindowSegment.empty()
      : points = const [],
        completedSegmentCount = 0,
        progressPercent = 0,
        routeIndex = 0,
        isDestinationVisible = false,
        destinationScreenPoint = null;
}

/// Frames the current approach (up to 300 m) and transforms
/// it into a road-aligned local screen coordinate frame for the 320x240 TFT.
class RouteWindowTransformer {
  // Maximum look-ahead. The current maneuver sets a closer approach camera;
  // only a short exit is revealed near the current turn.
  static const double windowDistanceMeters = 300.0;
  static const int maxPointsToSend = 14;

  // TFT dimensions & rider anchor point
  static const int screenWidth = 320;
  static const int screenHeight = 240;
  static const int riderScreenX = 160;
  static const int riderScreenY = 160;

  // Scale the window into the usable road area above the rider marker.
  static const double metersPerPixel = 300.0 / 150.0;

  /// Transforms the route polyline into a local road-aligned screen segment.
  static RouteWindowSegment transform({
    required LatLng riderPosition,
    required double riderHeadingDeg,
    required List<LatLng> polylinePoints,
    required LatLng destination,
    int minimumRouteIndex = 0,
    double? distanceToManeuverMeters,
    double? followingLegDistanceMeters,
  }) {
    if (polylinePoints.isEmpty) return const RouteWindowSegment.empty();

    // Snap to the nearest road segment, not the nearest vertex. A sparse
    // polyline can place its next vertex at the turn 100 m away.
    int closestIdx = minimumRouteIndex.clamp(0, polylinePoints.length - 1);
    LatLng roadPosition = polylinePoints[closestIdx];
    double minDistanceSquared = double.infinity;
    final lngScale = math.cos(riderPosition.latitude * math.pi / 180.0);
    double searchMeters = 0;
    for (int i = closestIdx; i < polylinePoints.length - 1; i++) {
      if (searchMeters > 800) break;
      searchMeters += Geolocator.distanceBetween(
          polylinePoints[i].latitude,
          polylinePoints[i].longitude,
          polylinePoints[i + 1].latitude,
          polylinePoints[i + 1].longitude);
      final a = polylinePoints[i];
      final b = polylinePoints[i + 1];
      final ax = (a.longitude - riderPosition.longitude) * lngScale;
      final ay = a.latitude - riderPosition.latitude;
      final dx = (b.longitude - a.longitude) * lngScale;
      final dy = b.latitude - a.latitude;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (-(ax * dx + ay * dy) / lengthSquared).clamp(0.0, 1.0);
      final x = ax + t * dx;
      final y = ay + t * dy;
      final distanceSquared = x * x + y * y;
      if (distanceSquared < minDistanceSquared) {
        minDistanceSquared = distanceSquared;
        closestIdx = t >= 1.0 ? i + 1 : i;
        roadPosition = LatLng(a.latitude + t * (b.latitude - a.latitude),
            a.longitude + t * (b.longitude - a.longitude));
      }
    }
    final snappedRider = roadPosition;

    final approach = distanceToManeuverMeters != null &&
            distanceToManeuverMeters.isFinite &&
            distanceToManeuverMeters >= 0
        ? distanceToManeuverMeters
        : null;
    // Show the current approach first. Reveal a short exit only near this turn,
    // and stop before the following maneuver even when junctions are close.
    final exit = approach == null
        ? 0.0
        : math.min(
            (60.0 - approach).clamp(0.0, 30.0),
            followingLegDistanceMeters != null &&
                    followingLegDistanceMeters.isFinite
                ? math.max(0.0, followingLegDistanceMeters * .7)
                : 30.0);
    final drawDistance = approach == null
        ? windowDistanceMeters
        : (approach + exit).clamp(5.0, windowDistanceMeters);
    final cameraDistance = approach == null
        ? windowDistanceMeters
        : approach.clamp(70.0, windowDistanceMeters);
    final pixelMeters = cameraDistance / (riderScreenY - 8);

    // Keep a short travelled tail behind the fixed rider anchor. The phone
    // owns progress; the ESP32 only colors the transmitted segments.
    final past = <LatLng>[];
    double pastDistance = 0;
    for (int i = closestIdx; i >= 0 && past.length < 3; i--) {
      pastDistance += Geolocator.distanceBetween(
        polylinePoints[i].latitude,
        polylinePoints[i].longitude,
        roadPosition.latitude,
        roadPosition.longitude,
      );
      if (pastDistance > math.min(25.0, cameraDistance * .12)) break;
      past.insert(0, polylinePoints[i]);
      roadPosition = polylinePoints[i];
    }

    // Extract only the visible part of the current approach/turn.
    final List<LatLng> upcomingPoints = [snappedRider];
    double accumulatedDist = 0.0;
    LatLng prev = snappedRider;

    for (int i = closestIdx + 1; i < polylinePoints.length; i++) {
      final pt = polylinePoints[i];
      final segDist = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        pt.latitude,
        pt.longitude,
      );

      if (accumulatedDist + segDist > drawDistance) {
        // End the visible road at the requested approach horizon.
        final remaining = drawDistance - accumulatedDist;
        if (segDist > 0 && remaining > 0) {
          final ratio = remaining / segDist;
          final interpLat =
              prev.latitude + (pt.latitude - prev.latitude) * ratio;
          final interpLng =
              prev.longitude + (pt.longitude - prev.longitude) * ratio;
          upcomingPoints.add(LatLng(interpLat, interpLng));
        }
        break;
      }

      upcomingPoints.add(pt);
      accumulatedDist += segDist;
      prev = pt;
    }

    // 3. Subsample if more than maxPointsToSend
    final List<LatLng> sampledPoints = [
      ...past,
      ..._subsample(upcomingPoints, maxPointsToSend - past.length),
    ];

    double completedMeters = 0;
    double totalMeters = 0;
    for (int i = 1; i < polylinePoints.length; i++) {
      final meters = Geolocator.distanceBetween(
        polylinePoints[i - 1].latitude,
        polylinePoints[i - 1].longitude,
        polylinePoints[i].latitude,
        polylinePoints[i].longitude,
      );
      totalMeters += meters;
      if (i <= closestIdx) completedMeters += meters;
    }
    if (closestIdx < polylinePoints.length - 1) {
      completedMeters += Geolocator.distanceBetween(
        polylinePoints[closestIdx].latitude,
        polylinePoints[closestIdx].longitude,
        snappedRider.latitude,
        snappedRider.longitude,
      );
    }
    final progressPercent = totalMeters <= 0
        ? 0
        : (100 * completedMeters / totalMeters).round().clamp(0, 100);

    // 4. Transform to road-aligned screen coordinates
    final routeHeading = closestIdx < polylinePoints.length - 1
        ? _bearing(polylinePoints[closestIdx], polylinePoints[closestIdx + 1])
        : riderHeadingDeg;
    // Lock to the road near the route to suppress compass drift. Once the
    // GPS fix is meaningfully off-route, preserve the actual rider heading.
    final offRouteMeters = math.sqrt(minDistanceSquared) * 111139.0;
    final viewHeading = offRouteMeters > 25 && riderHeadingDeg.isFinite
        ? riderHeadingDeg
        : routeHeading;
    final headingRad = viewHeading * math.pi / 180.0;

    final cosHeading = math.cos(headingRad);
    final sinHeading = math.sin(headingRad);

    // Anchor to the projected road while GPS is within the existing 25 m
    // tolerance. Route and rider must share the same origin.
    final viewOrigin = offRouteMeters <= 25 ? snappedRider : riderPosition;
    final List<ScreenPoint> projectedPoints = [];
    for (final pt in sampledPoints) {
      final sp = _latLngToScreen(
        viewOrigin,
        pt,
        cosHeading,
        sinHeading,
        pixelMeters,
      );
      projectedPoints.add(sp);
    }

    // Fit uniformly instead of clamping vertices, which invents edge bends.
    var fit = 1.0;
    for (final p in projectedPoints) {
      final dx = p.x - riderScreenX, dy = p.y - riderScreenY;
      if (dx != 0) fit = math.min(fit, 120.0 / dx.abs());
      if (dy < 0) fit = math.min(fit, (riderScreenY - 8) / -dy);
      if (dy > 0) fit = math.min(fit, 24.0 / dy);
    }
    ScreenPoint fitted(ScreenPoint p) => ScreenPoint(
        (riderScreenX + (p.x - riderScreenX) * fit).round(),
        (riderScreenY + (p.y - riderScreenY) * fit).round());
    final screenPoints = projectedPoints.map(fitted).toList();

    // 5. Check if destination is within the ~300m window
    final distToDest = Geolocator.distanceBetween(
      riderPosition.latitude,
      riderPosition.longitude,
      destination.latitude,
      destination.longitude,
    );

    final destVisible = upcomingPoints.last == polylinePoints.last &&
        distToDest <= drawDistance + 2;
    ScreenPoint? destPoint;
    if (destVisible) {
      destPoint = fitted(_latLngToScreen(
        viewOrigin,
        destination,
        cosHeading,
        sinHeading,
        pixelMeters,
      ));
    }

    return RouteWindowSegment(
      points: screenPoints,
      completedSegmentCount: past.length,
      progressPercent: progressPercent,
      routeIndex: closestIdx,
      isDestinationVisible: destVisible,
      destinationScreenPoint: destPoint,
    );
  }

  static ScreenPoint _latLngToScreen(
    LatLng rider,
    LatLng target,
    double cosH,
    double sinH, [
    double pixelMeters = metersPerPixel,
  ]) {
    // Convert lat/lng delta to local meters (North, East)
    final dLat = (target.latitude - rider.latitude) * 111139.0;
    final dLng = (target.longitude - rider.longitude) *
        111139.0 *
        math.cos((rider.latitude * math.pi) / 180.0);

    // Rotate heading-up:
    // Forward (along heading): yLocal = dLat * cos + dLng * sin
    // Right:                   xLocal = -dLat * sin + dLng * cos
    final forwardMeters = dLat * cosH + dLng * sinH;
    final rightMeters = -dLat * sinH + dLng * cosH;

    // Convert meters to screen pixels
    // Forward is UP on screen (smaller Y)
    // Right is RIGHT on screen (larger X)
    final pxX = (riderScreenX + (rightMeters / pixelMeters)).round();
    final pxY = (riderScreenY - (forwardMeters / pixelMeters)).round();

    return ScreenPoint(pxX, pxY);
  }

  static ScreenPoint projectPoint({
    required LatLng rider,
    required LatLng target,
    required double headingDeg,
  }) {
    final radians = headingDeg * math.pi / 180.0;
    final p =
        _latLngToScreen(rider, target, math.cos(radians), math.sin(radians));
    return ScreenPoint(p.x.clamp(0, screenWidth), p.y.clamp(0, screenHeight));
  }

  static List<LatLng> _subsample(List<LatLng> points, int maxCount) {
    if (points.length <= maxCount) return points;

    // Preserve real road corners before filling the remainder evenly.  A
    // uniform sample can discard the one point that represents a right/left
    // turn, making the HUD draw a straight road when the route actually bends.
    final keep = <int>{0, points.length - 1};
    for (var i = 1; i < points.length - 1; i++) {
      final first = _bearing(points[i - 1], points[i]);
      final second = _bearing(points[i], points[i + 1]);
      var delta = (second - first).abs();
      if (delta > 180.0) delta = 360.0 - delta;
      if (delta >= 18.0) keep.add(i);
    }

    // If a very curvy road has more corners than BLE can carry, retain evenly
    // distributed corners.  The first and last are always retained.
    final cornerIndices = keep.toList()..sort();
    final selected = <int>{0, points.length - 1};
    if (cornerIndices.length <= maxCount) {
      selected.addAll(cornerIndices);
    } else {
      final step = (cornerIndices.length - 1) / (maxCount - 1);
      for (var i = 0; i < maxCount; i++) {
        selected.add(cornerIndices[(i * step).round()]);
      }
    }

    // Fill unused BLE point slots with regular samples to keep long straights
    // smooth and visibly continuous.
    for (var i = 1; selected.length < maxCount && i < points.length - 1; i++) {
      final index = (i * (points.length - 1) / (maxCount - 1)).round();
      selected.add(index);
    }
    final indices = selected.toList()..sort();
    return indices.map((index) => points[index]).toList();
  }

  static double _bearing(LatLng from, LatLng to) {
    final dLat = to.latitude - from.latitude;
    final dLng = (to.longitude - from.longitude) *
        math.cos(from.latitude * math.pi / 180.0);
    return math.atan2(dLng, dLat) * 180.0 / math.pi;
  }
}
