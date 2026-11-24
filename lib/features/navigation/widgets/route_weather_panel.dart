import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/services/google_maps_service.dart';

typedef WeatherCheckpoint = ({LatLng position, Duration eta});

/// Derives checkpoints from the selected route and its existing step estimates.
/// All coordinates stay on the device.
List<WeatherCheckpoint> routeWeatherCheckpoints(NavigationRoute route) {
  final points = route.polylinePoints;
  if (points.isEmpty) return const [];
  final duration = route.totalDurationSeconds;
  if (duration <= 0 || points.length == 1) {
    return [(position: points.last, eta: Duration.zero)];
  }

  final count = duration > 90 * 60 || route.totalDistanceMeters >= 60000
      ? 4
      : duration > 30 * 60 || route.totalDistanceMeters >= 20000
          ? 3
          : 2;
  final timedSteps = route.steps.where((step) => step.durationSeconds > 0);
  final stepSeconds =
      timedSteps.fold(0, (sum, step) => sum + step.durationSeconds);

  LatLng positionAt(double fraction) {
    if (fraction == 0) return points.first;
    if (fraction == 1) return points.last;
    if (stepSeconds == 0) {
      return points[((points.length - 1) * fraction).round()];
    }
    var remaining = stepSeconds * fraction;
    for (final step in timedSteps) {
      if (remaining <= step.durationSeconds) {
        final geometry = step.points;
        if (geometry.isEmpty) {
          return remaining * 2 < step.durationSeconds
              ? step.startLocation
              : step.endLocation;
        }
        final index =
            ((geometry.length - 1) * remaining / step.durationSeconds).round();
        return geometry[index];
      }
      remaining -= step.durationSeconds;
    }
    return points.last;
  }

  return List.generate(count, (i) {
    final fraction = i / (count - 1);
    return (
      position: positionAt(fraction),
      eta: Duration(seconds: (duration * fraction).round()),
    );
  });
}

class RouteWeatherPanel extends StatelessWidget {
  const RouteWeatherPanel({super.key, required this.route});

  final NavigationRoute route;

  @override
  Widget build(BuildContext context) {
    final checkpoints = routeWeatherCheckpoints(route);
    if (checkpoints.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_outlined),
      title: const Text('Route weather'),
      subtitle: const Text('Forecast unavailable'),
      children: [
        for (final (index, checkpoint) in checkpoints.indexed)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(index == checkpoints.length - 1
                ? 'Destination'
                : index == 0
                    ? 'Departure'
                    : 'Checkpoint $index'),
            trailing: Text(checkpoint.eta == Duration.zero
                ? 'At departure'
                : 'In ${(checkpoint.eta.inSeconds / 60).ceil()} min'),
          ),
      ],
    );
  }
}
