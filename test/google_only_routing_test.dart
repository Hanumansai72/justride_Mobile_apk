import 'package:justride_ui/core/models/bike_route_preferences.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justride_ui/core/constants/google_maps_config.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/features/navigation/widgets/route_preview_map.dart';
import 'package:justride_ui/app/theme/app_colors.dart';
import 'dart:ui' show Color;

void main() {
  const origin = LatLng(38.5, -120.2);
  const destination = LatLng(43.252, -126.453);

  tearDown(() => GoogleMapsConfig.setApiKey(''));

  test('phone routing does not contact alternate providers without a key',
      () async {
    GoogleMapsConfig.setApiKey('');
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{}', 403);
    });
    addTearDown(client.close);
    final route = await GoogleMapsService.testing(client)
        .calculateRoute(origin: origin, destination: destination);
    expect(route, isNull);
    expect(requests, isEmpty);
  });

  test('Google errors try Directions but never OSRM for phone navigation',
      () async {
    GoogleMapsConfig.setApiKey('test-key');
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      return http.Response('{}', 403);
    });
    addTearDown(client.close);
    final route = await GoogleMapsService.testing(client)
        .calculateRoute(origin: origin, destination: destination);
    expect(route, isNull);
    expect(hosts, ['routes.googleapis.com', 'maps.googleapis.com']);
  });

  test(
      'bike preferences stay applied when requesting alternatives and rerouting',
      () async {
    GoogleMapsConfig.setApiKey('test-key');
    const preferences = BikeRoutePreferences(
        avoidTolls: true, avoidHighways: true, avoidFerries: true);
    final requests = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.url.host, 'routes.googleapis.com');
      requests.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{}', 503);
    });
    addTearDown(client.close);
    final service = GoogleMapsService.testing(client);
    expect(
        await service.bikeRouteOptions(
            origin: origin, destination: destination, preferences: preferences),
        isEmpty);
    expect(
        await service.calculateRoute(
            origin: origin,
            destination: destination,
            preferences: preferences,
            isReroute: true),
        isNull);
    expect(requests.map((request) => request['computeAlternativeRoutes']),
        [true, false, false]);
    for (final request in requests) {
      expect(request['travelMode'], 'TWO_WHEELER');
      expect(request['routeModifiers'], preferences.toMap());
    }
    expect(BikeRoutePreferences.fromFlags(preferences.flags).toMap(),
        preferences.toMap());
  });

  test('phone uses Google route geometry and maneuver instructions', () async {
    GoogleMapsConfig.setApiKey('test-key');
    const encoded = '_p~iF~ps|U_ulLnnqC_mqNvxq`@gEgE';
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.url.host, 'routes.googleapis.com');
      expect(jsonDecode(request.body)['travelMode'], 'TWO_WHEELER');
      expect(jsonDecode(request.body)['extraComputations'],
          ['TRAFFIC_ON_POLYLINE']);
      expect(request.headers['X-Goog-FieldMask'],
          contains('routes.travelAdvisory.speedReadingIntervals'));
      return http.Response(
          jsonEncode({
            'routes': [
              {
                'distanceMeters': 1000,
                'duration': '120s',
                'polyline': {'encodedPolyline': encoded},
                'travelAdvisory': {
                  'speedReadingIntervals': [
                    {'endPolylinePointIndex': 1, 'speed': 'NORMAL'},
                    {
                      'startPolylinePointIndex': 1,
                      'endPolylinePointIndex': 2,
                      'speed': 'SLOW',
                    },
                    {
                      'startPolylinePointIndex': 2,
                      'endPolylinePointIndex': 3,
                      'speed': 'TRAFFIC_JAM',
                    },
                    {'endPolylinePointIndex': 100, 'speed': 'NORMAL'},
                  ],
                },
                'legs': [
                  {
                    'steps': [
                      {
                        'startLocation': {
                          'latLng': {
                            'latitude': origin.latitude,
                            'longitude': origin.longitude
                          }
                        },
                        'endLocation': {
                          'latLng': {
                            'latitude': destination.latitude,
                            'longitude': destination.longitude
                          }
                        },
                        'distanceMeters': 1000,
                        'staticDuration': '120s',
                        'navigationInstruction': {
                          'maneuver': 'TURN_RIGHT',
                          'instructions': 'Turn right onto Main Road'
                        },
                        'polyline': {'encodedPolyline': encoded},
                      }
                    ],
                  }
                ],
              }
            ],
          }),
          200);
    });
    addTearDown(client.close);
    final route = await GoogleMapsService.testing(client)
        .calculateRoute(origin: origin, destination: destination);
    expect(route, isNotNull);
    expect(route!.provider, 'google');
    expect(route.polylinePoints, hasLength(4));
    expect(calls, 1);
    final traffic = selectedRoutePolylines(route, width: 6).skip(1).toList();
    expect(traffic.map((line) => line.color), [
      AppColors.primary,
      const Color(0xFFFFA041),
      const Color(0xFFFF5252),
    ]);
    expect(traffic[1].points, route.polylinePoints.sublist(1, 3));
    expect(traffic[0].points.last, traffic[1].points.first);
    expect(traffic[1].points.last, traffic[2].points.first);
    expect(route.steps.any((step) => step.streetName.contains('Main Road')),
        isTrue);
    expect(route.steps.last.instruction, 'Arrive at destination');
  });
}
