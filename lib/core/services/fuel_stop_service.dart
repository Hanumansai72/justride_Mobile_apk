import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/bike_route_preferences.dart';
import '../models/destination.dart';
import 'google_maps_service.dart';

enum FuelRidingStyle {
  steady('Steady', 1),
  mixed('Mixed', .9),
  heavy('Stop-and-go or brisk', .75);

  const FuelRidingStyle(this.label, this.factor);
  final String label;
  final double factor;
}

double plannedFuelRangeKm({
  required double baseKmPerLitre,
  required double litres,
  required double reserveLitres,
  required FuelRidingStyle style,
}) =>
    math.max(0.0, litres - reserveLitres) * baseKmPerLitre * style.factor;

class FuelStopPlan {
  const FuelStopPlan(this.station, this.toStation, this.detourSeconds);
  final Destination station;
  final NavigationRoute toStation;
  final int detourSeconds;
}

class FuelStopService {
  Future<FuelStopPlan?> find({
    required NavigationRoute route,
    required LatLng origin,
    required LatLng destination,
    required double rangeKm,
    required BikeRoutePreferences preferences,
  }) async {
    final budget = rangeKm * 1000;
    if (budget < 200 || route.polylinePoints.length < 2) return null;
    final points = route.polylinePoints;
    final distances = <double>[0];
    for (var i = 1; i < points.length; i++) {
      distances.add(distances.last + _distance(points[i - 1], points[i]));
    }
    final target = math.min(budget * .7, distances.last);
    final targetIndex = distances.indexWhere((distance) => distance >= target);
    final maps = GoogleMapsService.instance;
    final candidates = await maps.searchPlaces(
      'petrol station',
      near: points[targetIndex < 0 ? points.length - 1 : targetIndex],
      searchRadiusMeters: math.min(10000, math.max(1500, budget * .4)),
    );
    final shortlist = <(Destination, double)>[];
    for (final candidate in candidates) {
      if (candidate.latitude == 0 && candidate.longitude == 0) continue;
      final pin = LatLng(candidate.latitude, candidate.longitude);
      var nearest = double.infinity;
      var along = 0.0;
      for (var i = 1; i < points.length; i++) {
        final a = _distance(points[i - 1], pin);
        final b = _distance(points[i], pin);
        final length = distances[i] - distances[i - 1];
        if (length <= 0) continue;
        final alongLine = (a * a + length * length - b * b) / (2 * length);
        final projection = alongLine.clamp(0.0, length);
        final lateral = math.sqrt(math.max(
            0, a * a - 2 * projection * alongLine + projection * projection));
        if (lateral < nearest) {
          nearest = lateral;
          along = distances[i - 1] + projection;
        }
      }
      if (nearest <= 1000 && along + nearest <= budget) {
        shortlist.add((candidate, (along - target).abs() + nearest * 3));
      }
    }
    shortlist.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (station, _) in shortlist.take(2)) {
      final pin = LatLng(station.latitude, station.longitude);
      final first = await maps.calculateRoute(
          origin: origin,
          destination: pin,
          preferences: preferences,
          bikeOnly: true);
      if (first == null || first.totalDistanceMeters > budget) continue;
      final onward = await maps.calculateRoute(
          origin: pin,
          destination: destination,
          preferences: preferences,
          bikeOnly: true);
      if (onward == null) continue;
      return FuelStopPlan(
          station,
          first,
          math.max(
              0,
              first.totalDurationSeconds +
                  onward.totalDurationSeconds -
                  route.totalDurationSeconds));
    }
    return null;
  }

  double _distance(LatLng a, LatLng b) => Geolocator.distanceBetween(
      a.latitude, a.longitude, b.latitude, b.longitude);
}
