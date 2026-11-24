import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justride_ui/core/constants/google_maps_config.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';

void main() {
  setUp(() => GoogleMapsConfig.setApiKey('test-key'));
  tearDown(() => GoogleMapsConfig.setApiKey(''));

  test('four typing pauses and a selection use five Google requests', () async {
    final token = GoogleMapsService.newPlacesSessionToken();
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v1/places:autocomplete') {
        return http.Response(
            jsonEncode({
              'suggestions': [
                {
                  'placePrediction': {
                    'placeId': 'uppal-cinema',
                    'text': {'text': 'Cineverse Multiplex Uppal'},
                  },
                },
              ],
            }),
            200);
      }
      return http.Response(
          '{"location":{"latitude":17.4,"longitude":78.6}}', 200);
    });
    addTearDown(client.close);
    final service = GoogleMapsService.testing(client);

    for (final query in ['Ci', 'Cine', 'Cineverse', 'Cineverse Uppal']) {
      final results = await service.searchPlaces(
        query,
        autocomplete: true,
        sessionToken: token,
      );
      if (query == 'Cineverse Uppal') {
        final place = await service.resolveDestination(results.single,
            sessionToken: token);
        expect(place?.latitude, 17.4);
        expect(place?.name, 'Cineverse Multiplex Uppal');
      }
    }

    expect(requests.map((request) => request.url.path), [
      ...List.filled(4, '/v1/places:autocomplete'),
      '/v1/places/uppal-cinema',
    ]);
    for (final request in requests.take(4)) {
      expect(jsonDecode(request.body)['sessionToken'], token);
    }
    expect(requests.last.url.queryParameters['sessionToken'], token);
    expect(
        requests.last.headers['X-Goog-FieldMask'], 'formattedAddress,location');
  });

  test('explicit search sends one Text Search request', () async {
    final requests = <String>[];
    final client = MockClient((request) async {
      requests.add(request.url.path);
      return http.Response(
          '{"places":[{"id":"uppal-cinema","location":'
          '{"latitude":17.4,"longitude":78.6}}]}',
          200);
    });
    addTearDown(client.close);
    final service = GoogleMapsService.testing(client);

    final results = await service.searchPlaces('Cineverse Uppal');

    expect(results.single.latitude, 17.4);
    expect(requests, ['/v1/places:searchText']);
  });
}
