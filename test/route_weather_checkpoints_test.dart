import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/features/navigation/widgets/route_weather_panel.dart';

void main() {
  test('weather checkpoints follow the selected route and estimated time', () {
    const start = LatLng(17.4, 78.4);
    const middle = LatLng(17.5, 78.5);
    const finish = LatLng(17.6, 78.6);
    final route = NavigationRoute(
      totalDistanceMeters: 25000,
      totalDurationSeconds: 3600,
      polylinePoints: const [start, middle, finish],
      steps: const [],
    );

    expect(routeWeatherCheckpoints(route), [
      (position: start, eta: Duration.zero),
      (position: middle, eta: const Duration(minutes: 30)),
      (position: finish, eta: const Duration(hours: 1)),
    ]);
  });

  test('a long route uses at most four checkpoints', () {
    const route = NavigationRoute(
      totalDistanceMeters: 150000,
      totalDurationSeconds: 9000,
      polylinePoints: [
        LatLng(17.4, 78.4),
        LatLng(17.5, 78.5),
        LatLng(17.6, 78.6),
        LatLng(17.7, 78.7),
      ],
      steps: [],
    );
    final checkpoints = routeWeatherCheckpoints(route);
    expect(checkpoints.length, 4);
    expect(checkpoints.last.eta, const Duration(minutes: 150));
  });
}
