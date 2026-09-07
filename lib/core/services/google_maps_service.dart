import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import '../constants/google_maps_config.dart';
import '../models/destination.dart';
import '../utils/maneuver_mapper.dart';
import '../utils/maps_url_parser.dart';
import 'location_service.dart';

/// Represents a single maneuver step along the calculated route.
class RouteStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final double distanceMeters;
  final int durationSeconds;
  final String maneuver;
  final String instruction;
  final String streetName;
  final List<LatLng> points;

  const RouteStep({
    required this.startLocation,
    required this.endLocation,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuver,
    required this.instruction,
    required this.streetName,
    required this.points,
  });
}

/// Represents the calculated route with geometry, steps, and totals.
class NavigationRoute {
  final double totalDistanceMeters;
  final int totalDurationSeconds;
  final List<LatLng> polylinePoints;
  final List<RouteStep> steps;

  const NavigationRoute({
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.polylinePoints,
    required this.steps,
  });
}

/// Service communicating with Google Maps Platform (Routes API v2, Places, Geocoding)
class GoogleMapsService {
  GoogleMapsService._();
  static final GoogleMapsService instance = GoogleMapsService._();

  /// Searches for places/addresses given user query.
  /// First queries Google Places (New) if API key is provided and authorized.
  /// If Google Places fails or is restricted, it seamlessly falls back to Photon
  /// (Komoot OSM live geocoder) so suggestions always appear instantly beneath
  /// the Destination/Start fields.
  Future<List<Destination>> searchPlaces(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) return const [];

    // Reference coordinates for biasing searches towards the user's area
    final pos = LocationService.instance.currentPosition;
    final refLat = (pos != null && pos.latitude != 0.0) ? pos.latitude : 17.3850;
    final refLon = (pos != null && pos.longitude != 0.0) ? pos.longitude : 78.4867;

    final key = GoogleMapsConfig.apiKey;
    if (key.isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse(GoogleMapsConfig.placesTextSearchEndpoint),
              headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': key,
                'X-Goog-FieldMask':
                    'places.id,places.displayName,places.formattedAddress,places.location',
              },
              body: jsonEncode({
                'textQuery': cleanQuery,
                'languageCode': 'en',
                'locationBias': {
                  'circle': {
                    'center': {'latitude': refLat, 'longitude': refLon},
                    'radius': 50000.0,
                  }
                }
              }),
            )
            .timeout(const Duration(seconds: 4));
        if (response.statusCode == 200) {
          final places =
              (jsonDecode(response.body)['places'] as List?) ?? const [];
          final list = places
              .map((place) {
                final location = place['location'] as Map<String, dynamic>?;
                final lat = (location?['latitude'] as num?)?.toDouble() ?? 0.0;
                final lng = (location?['longitude'] as num?)?.toDouble() ?? 0.0;
                final displayName =
                    (place['displayName'] as Map<String, dynamic>?)?['text']
                            ?.toString() ??
                        place['formattedAddress']?.toString() ??
                        cleanQuery;
                return Destination(
                  name: displayName,
                  address: place['formattedAddress']?.toString() ?? displayName,
                  latitude: lat,
                  longitude: lng,
                  placeId: place['id']?.toString(),
                  rawQuery: cleanQuery,
                );
              })
              .where((place) => place.latitude != 0.0 && place.longitude != 0.0)
              .take(6)
              .toList(growable: false);

          if (list.isNotEmpty) {
            return list;
          }
        } else {
          debugPrint(
              '[PLACES] Google Places returned ${response.statusCode}, falling back to Photon & Nominatim');
        }
      } catch (e) {
        debugPrint('[PLACES] Google Places search error: $e, falling back to Photon & Nominatim');
      }
    }

    final suggestions = <Destination>[];

    // High-performance Photon Komoot fallback with coordinate biasing & type decoration
    try {
      final photonUrl = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(cleanQuery)}&lat=$refLat&lon=$refLon&limit=10&lang=en',
      );
      final photonRes = await http.get(photonUrl, headers: {
        'User-Agent': 'JustRide-App/1.0',
      }).timeout(const Duration(seconds: 4));

      if (photonRes.statusCode == 200) {
        final data = jsonDecode(photonRes.body);
        final features = (data['features'] as List?) ?? const [];

        for (final feature in features) {
          final geometry = feature['geometry'];
          final coords = geometry?['coordinates'] as List?;
          if (coords == null || coords.length < 2) continue;

          final lon = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();
          if (lat == 0.0 && lon == 0.0) continue;

          final props = (feature['properties'] as Map<String, dynamic>?) ?? {};
          var name = props['name']?.toString() ?? cleanQuery;
          final osmKey = (props['osm_key']?.toString() ?? '').toLowerCase();
          final osmValue = (props['osm_value']?.toString() ?? '').toLowerCase();

          // Smart category annotation for bus stops, metro stations, localities
          final lowerName = name.toLowerCase();
          if ((osmValue == 'bus_stop' || osmKey == 'bus_stop') && !lowerName.contains('bus')) {
            name = '$name Bus Stop';
          } else if (osmValue == 'bus_station' && !lowerName.contains('bus')) {
            name = '$name Bus Station';
          } else if (osmValue == 'station' && osmKey == 'railway' && !lowerName.contains('station') && !lowerName.contains('metro')) {
            name = '$name Metro / Station';
          }

          final street = props['street']?.toString();
          final locality = props['locality']?.toString();
          final district = props['district']?.toString();
          final city = props['city']?.toString() ??
              props['town']?.toString() ??
              props['county']?.toString();
          final state = props['state']?.toString();
          final country = props['country']?.toString();

          final addressParts = [street, locality, district, city, state, country]
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty && s.toLowerCase() != name.toLowerCase())
              .toSet()
              .toList();

          final formattedAddress = addressParts.isNotEmpty
              ? addressParts.join(', ')
              : (props['country']?.toString() ?? name);

          // Avoid duplicate coordinates
          final isDuplicate = suggestions.any((s) =>
              (s.latitude - lat).abs() < 0.0003 &&
              (s.longitude - lon).abs() < 0.0003);

          if (!isDuplicate) {
            suggestions.add(Destination(
              name: name,
              address: formattedAddress,
              latitude: lat,
              longitude: lon,
              rawQuery: cleanQuery,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[PLACES] Photon fallback error: $e');
    }

    // Supplementary Nominatim query for Indian public transit (bus stops, metro stations, junctions)
    final lowerQ = cleanQuery.toLowerCase();
    final isTransitQuery = lowerQ.contains('bus') ||
        lowerQ.contains('stop') ||
        lowerQ.contains('stand') ||
        lowerQ.contains('station') ||
        lowerQ.contains('metro') ||
        lowerQ.contains('junction');

    if (suggestions.length < 3 || isTransitQuery) {
      try {
        final nominatimUrl = Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&limit=6&addressdetails=1&countrycodes=in',
        );
        final nomRes = await http.get(nominatimUrl, headers: {
          'User-Agent': 'JustRide-App/1.0 (contact@justride.app)',
        }).timeout(const Duration(seconds: 4));

        if (nomRes.statusCode == 200) {
          final nomList = (jsonDecode(nomRes.body) as List?) ?? const [];
          for (final item in nomList) {
            final lat = double.tryParse(item['lat']?.toString() ?? '');
            final lon = double.tryParse(item['lon']?.toString() ?? '');
            if (lat == null || lon == null || (lat == 0.0 && lon == 0.0)) continue;

            var name = item['name']?.toString() ?? cleanQuery;
            final type = (item['type']?.toString() ?? '').toLowerCase();

            if (type == 'bus_stop' && !name.toLowerCase().contains('bus')) {
              name = '$name Bus Stop';
            } else if (type == 'bus_station' && !name.toLowerCase().contains('bus')) {
              name = '$name Bus Station';
            } else if (type == 'station' && !name.toLowerCase().contains('station')) {
              name = '$name Station';
            }

            final displayName = item['display_name']?.toString() ?? name;
            final addressParts = displayName.split(',').map((s) => s.trim()).toList();
            // Shorten address to 3 readable components
            final shortAddress = addressParts.length > 3
                ? addressParts.skip(1).take(3).join(', ')
                : displayName;

            final isDuplicate = suggestions.any((s) =>
                (s.latitude - lat).abs() < 0.0003 &&
                (s.longitude - lon).abs() < 0.0003);

            if (!isDuplicate) {
              suggestions.add(Destination(
                name: name,
                address: shortAddress,
                latitude: lat,
                longitude: lon,
                rawQuery: cleanQuery,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('[PLACES] Nominatim transit fallback error: $e');
      }
    }

    return suggestions.take(8).toList(growable: false);
  }

  /// Resolves any missing coordinates in a Destination using Google Geocoding / Places,
  /// followed by Photon (Komoot OSM geocoder) and OpenStreetMap Nominatim with debug logging.
  Future<Destination?> resolveDestination(Destination destination) async {
    if (destination.latitude != 0.0 && destination.longitude != 0.0) {
      debugPrint(
          '[GEOCODE] Destination already has valid coordinates: (${destination.latitude}, ${destination.longitude})');
      return destination;
    }

    // If the destination contains a URL in rawQuery, address, or name, resolve with MapsUrlParser first
    final candidateUrl =
        destination.rawQuery ?? destination.address ?? destination.name ?? '';
    if (candidateUrl.contains('http://') || candidateUrl.contains('https://')) {
      final parsed = await MapsUrlParser.parseSharedText(candidateUrl);
      if (parsed != null) {
        if (parsed.latitude != 0.0 && parsed.longitude != 0.0) {
          debugPrint(
              '[GEOCODE] ✓ Successfully resolved coordinates from URL: ${parsed.latitude}, ${parsed.longitude}');
          return parsed;
        }
        if (parsed.name != null && !parsed.name!.startsWith('http')) {
          destination = destination.copyWith(
            name: parsed.name,
            address: parsed.address,
            rawQuery: parsed.rawQuery,
          );
        }
      }
    }

    final rawQueryText =
        destination.name ?? destination.address ?? destination.rawQuery ?? '';
    final queryText = MapsUrlParser.cleanSearchQuery(rawQueryText);
    debugPrint(
        '[GEOCODE] Attempting to resolve coordinates for query: "$queryText" (placeId: ${destination.placeId})');

    final key = GoogleMapsConfig.apiKey;
    if (key.isNotEmpty) {
      // 1. If we have a Place ID, query details
      if (destination.placeId != null && destination.placeId!.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse(
                GoogleMapsConfig.placeDetailsEndpoint(destination.placeId!)),
            headers: {
              'X-Goog-Api-Key': key,
              'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
            },
          );
          debugPrint(
              '[GEOCODE] Google Place Details HTTP status: ${res.statusCode}');
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final loc = data['location'] as Map<String, dynamic>?;
            if (loc != null) {
              final lat = (loc['latitude'] as num).toDouble();
              final lng = (loc['longitude'] as num).toDouble();
              debugPrint(
                  '[GEOCODE] ✓ Google Place Details resolved: $lat, $lng');
              return destination.copyWith(
                name: (data['displayName'] as Map<String, dynamic>?)?['text']
                        ?.toString() ??
                    destination.name,
                address:
                    data['formattedAddress']?.toString() ?? destination.address,
                latitude: lat,
                longitude: lng,
              );
            } else {
              debugPrint(
                  '[GEOCODE] Google Place Details returned no location.');
            }
          }
        } catch (e) {
          debugPrint('[GEOCODE] Google Place Details exception: $e');
        }
      }

      // 2. Query Google Geocoding with rawQuery / name / address
      if (queryText.isNotEmpty && !queryText.startsWith('http')) {
        try {
          final geoUrl = Uri.parse(
            '${GoogleMapsConfig.geocodingApiEndpoint}?address=${Uri.encodeComponent(queryText)}&key=$key',
          );
          final geoRes = await http.get(geoUrl);
          debugPrint(
              '[GEOCODE] Google Geocoding HTTP status: ${geoRes.statusCode}');
          if (geoRes.statusCode == 200) {
            final geoData = jsonDecode(geoRes.body);
            final status = geoData['status'];
            debugPrint('[GEOCODE] Google Geocoding status: $status');
            if (status == 'OK' && (geoData['results'] as List).isNotEmpty) {
              final first = geoData['results'][0];
              final loc = first['geometry']['location'];
              final lat = (loc['lat'] as num).toDouble();
              final lng = (loc['lng'] as num).toDouble();
              debugPrint(
                  '[GEOCODE] ✓ Google Geocoding resolved: $lat, $lng (${first['formatted_address']})');
              return destination.copyWith(
                address: first['formatted_address'],
                latitude: lat,
                longitude: lng,
              );
            }
          }
        } catch (e) {
          debugPrint('[GEOCODE] Google Geocoding exception: $e');
        }
      }
    } else {
      debugPrint(
          '[GEOCODE] No Google Maps API key provided. Skipping Google APIs.');
    }

    // Clean query text for open-source geocoders (strip coordinates or strange symbols if any)
    String cleanQuery = queryText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleanQuery.isEmpty) {
      debugPrint('[GEOCODE] Query text is empty, cannot geocode.');
      return null;
    }

    final refPos = LocationService.instance.currentPosition;
    final refLat = (refPos != null && refPos.latitude != 0.0) ? refPos.latitude : 17.3850;
    final refLon = (refPos != null && refPos.longitude != 0.0) ? refPos.longitude : 78.4867;

    // 3. Photon by Komoot geocoder (High performance, global OSM index, no API key needed, never rate-limited)
    try {
      debugPrint('[GEOCODE] Trying Photon Geocoder for: "$cleanQuery"...');
      final photonUrl = Uri.parse(
        'https://photon.komoot.io/api/?q=${Uri.encodeComponent(cleanQuery)}&lat=$refLat&lon=$refLon&limit=1&lang=en',
      );
      final photonRes = await http.get(photonUrl, headers: {
        'User-Agent': 'JustRide-App/1.0',
      }).timeout(const Duration(seconds: 5));

      debugPrint('[GEOCODE] Photon HTTP status: ${photonRes.statusCode}');
      if (photonRes.statusCode == 200) {
        final data = jsonDecode(photonRes.body);
        final features = data['features'] as List?;
        if (features != null && features.isNotEmpty) {
          final first = features[0];
          final geometry = first['geometry'];
          final coords = geometry?['coordinates'] as List?;
          if (coords != null && coords.length >= 2) {
            // Note: GeoJSON coordinates are [lon, lat]!
            final lon = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final props = first['properties'] as Map<String, dynamic>? ?? {};
            final placeName = props['name']?.toString() ?? cleanQuery;
            final state = props['state']?.toString();
            final country = props['country']?.toString();
            final fullAddr = [placeName, state, country]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(', ');

            debugPrint(
                '[GEOCODE] ✓ Photon resolved coordinates: lat=$lat, lon=$lon ($fullAddr)');
            return destination.copyWith(
              name: destination.name ?? placeName,
              address: destination.address ?? fullAddr,
              latitude: lat,
              longitude: lon,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[GEOCODE] Photon geocoding exception: $e');
    }

    // 4. OpenStreetMap Nominatim fallback
    try {
      debugPrint(
          '[GEOCODE] Trying OpenStreetMap Nominatim fallback for: "$cleanQuery"...');
      final osmUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(cleanQuery)}&format=json&limit=1&countrycodes=in',
      );
      final osmRes = await http.get(osmUrl, headers: {
        'User-Agent': 'JustRide-App/1.0 (contact@justride.app)',
      }).timeout(const Duration(seconds: 5));

      debugPrint('[GEOCODE] Nominatim HTTP status: ${osmRes.statusCode}');
      if (osmRes.statusCode == 200) {
        final list = jsonDecode(osmRes.body) as List;
        if (list.isNotEmpty) {
          final first = list[0];
          final lat = double.tryParse(first['lat']?.toString() ?? '');
          final lon = double.tryParse(first['lon']?.toString() ?? '');
          if (lat != null && lon != null) {
            debugPrint(
                '[GEOCODE] ✓ OSM Nominatim resolved coordinates: lat=$lat, lon=$lon');
            return destination.copyWith(
              name: destination.name ?? first['name'] ?? cleanQuery,
              address: first['display_name'] ?? destination.address,
              latitude: lat,
              longitude: lon,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[GEOCODE] OSM fallback exception: $e');
    }

    debugPrint('[GEOCODE] ✗ All geocoding providers failed for "$cleanQuery"');
    return null;
  }

  /// Calculates optimal motorcycle route between origin and destination.
  /// Uses Google Routes API v2 with TWO_WHEELER travel mode, with Directions API fallback,
  /// followed by high-speed OSRM routing fallback.
  Future<NavigationRoute?> calculateRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final key = GoogleMapsConfig.apiKey;
    if (key.isNotEmpty) {
      // Try Google Routes API v2 first
      try {
        final routesV2 = await _fetchRoutesApiV2(origin, destination, key);
        if (routesV2 != null && routesV2.steps.isNotEmpty) return routesV2;
      } catch (e) {
        debugPrint(
            '[GoogleMapsService] Routes API v2 error: $e, falling back to Directions API');
      }

      // Fallback: Google Directions API
      try {
        final directions = await _fetchDirectionsApi(origin, destination, key);
        if (directions != null && directions.steps.isNotEmpty) {
          return directions;
        }
      } catch (e) {
        debugPrint('[GoogleMapsService] Directions API error: $e');
      }
    }

    // High-fidelity fallback: OSRM Turn-by-Turn Motorcycle/Driving Routing
    try {
      final osrmRoute = await _fetchOsrmRoute(origin, destination);
      if (osrmRoute != null && osrmRoute.steps.isNotEmpty) {
        debugPrint(
            '[GoogleMapsService] ✓ OSRM route calculated successfully: ${osrmRoute.totalDistanceMeters}m, ${osrmRoute.steps.length} steps');
        return osrmRoute;
      }
    } catch (e) {
      debugPrint('[GoogleMapsService] OSRM routing error: $e');
    }

    return _generateDirectRouteFallback(origin, destination);
  }

  /// Google Routes API v2 Implementation
  Future<NavigationRoute?> _fetchRoutesApiV2(
    LatLng origin,
    LatLng destination,
    String key,
  ) async {
    final body = jsonEncode({
      'origin': {
        'location': {
          'latLng': {
            'latitude': origin.latitude,
            'longitude': origin.longitude,
          }
        }
      },
      'destination': {
        'location': {
          'latLng': {
            'latitude': destination.latitude,
            'longitude': destination.longitude,
          }
        }
      },
      'travelMode': 'TWO_WHEELER',
      'routingPreference': 'TRAFFIC_AWARE',
      'computeAlternativeRoutes': false,
      'languageCode': 'en',
    });

    final response = await http.post(
      Uri.parse(GoogleMapsConfig.routesApiEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': key,
        'X-Goog-FieldMask':
            'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      debugPrint(
          '[GoogleMapsService] Routes v2 failed: ${response.statusCode} - ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes[0];
    final totalDistance = (route['distanceMeters'] as num?)?.toDouble() ?? 0.0;
    final durationStr = route['duration'] as String? ?? '0s';
    final totalDuration = int.tryParse(durationStr.replaceAll('s', '')) ?? 0;

    final encodedPoly = route['polyline']?['encodedPolyline'] as String? ?? '';
    final polyPoints = _decodePolyline(encodedPoly);

    final rawStepsList = <RouteStep>[];
    final legs = route['legs'] as List? ?? [];
    if (legs.isNotEmpty) {
      final rawSteps = legs[0]['steps'] as List? ?? [];
      for (final s in rawSteps) {
        final startLat =
            (s['startLocation']?['latLng']?['latitude'] as num?)?.toDouble() ??
                origin.latitude;
        final startLng =
            (s['startLocation']?['latLng']?['longitude'] as num?)?.toDouble() ??
                origin.longitude;
        final endLat =
            (s['endLocation']?['latLng']?['latitude'] as num?)?.toDouble() ??
                destination.latitude;
        final endLng =
            (s['endLocation']?['latLng']?['longitude'] as num?)?.toDouble() ??
                destination.longitude;

        final stepDist = (s['distanceMeters'] as num?)?.toDouble() ?? 0.0;
        final stepDurStr = s['staticDuration'] as String? ?? '0s';
        final stepDur = int.tryParse(stepDurStr.replaceAll('s', '')) ?? 0;

        final rawManeuver =
            s['navigationInstruction']?['maneuver'] as String? ?? 'STRAIGHT';
        final instruction =
            s['navigationInstruction']?['instructions'] as String? ?? '';
        final stepPoly = s['polyline']?['encodedPolyline'] as String? ?? '';

        rawStepsList.add(RouteStep(
          startLocation: LatLng(startLat, startLng),
          endLocation: LatLng(endLat, endLng),
          distanceMeters: stepDist,
          durationSeconds: stepDur,
          maneuver: ManeuverMapper.toJustRideManeuver(rawManeuver, instruction),
          instruction: instruction.isNotEmpty
              ? instruction
              : ManeuverMapper.toRiderActionText(rawManeuver),
          streetName: _extractStreetName(instruction),
          points: stepPoly.isNotEmpty
              ? _decodePolyline(stepPoly)
              : [LatLng(startLat, startLng), LatLng(endLat, endLng)],
        ));
      }
    }

    final steps = _normalizeSteps(rawStepsList, origin, destination);

    return NavigationRoute(
      totalDistanceMeters: totalDistance,
      totalDurationSeconds: totalDuration,
      polylinePoints:
          polyPoints.isNotEmpty ? polyPoints : [origin, destination],
      steps: steps,
    );
  }

  /// Google Directions API Implementation (Standard Fallback)
  Future<NavigationRoute?> _fetchDirectionsApi(
    LatLng origin,
    LatLng destination,
    String key,
  ) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=driving&language=en&key=$key',
    );

    final res = await http.get(url);
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data['status'] != 'OK') return null;

    final routes = data['routes'] as List;
    if (routes.isEmpty) return null;

    final route = routes[0];
    final legs = route['legs'] as List;
    if (legs.isEmpty) return null;

    final leg = legs[0];
    final totalDistance =
        (leg['distance']?['value'] as num?)?.toDouble() ?? 0.0;
    final totalDuration = (leg['duration']?['value'] as num?)?.toInt() ?? 0;

    final overviewPoly = route['overview_polyline']?['points'] as String? ?? '';
    final polyline = _decodePolyline(overviewPoly);

    final rawStepsList = <RouteStep>[];
    final rawSteps = leg['steps'] as List? ?? [];
    for (final s in rawSteps) {
      final startLat = (s['start_location']?['lat'] as num).toDouble();
      final startLng = (s['start_location']?['lng'] as num).toDouble();
      final endLat = (s['end_location']?['lat'] as num).toDouble();
      final endLng = (s['end_location']?['lng'] as num).toDouble();

      final stepDist = (s['distance']?['value'] as num?)?.toDouble() ?? 0.0;
      final stepDur = (s['duration']?['value'] as num?)?.toInt() ?? 0;
      final rawManeuver = s['maneuver'] as String? ?? 'STRAIGHT';
      final rawHtml = s['html_instructions'] as String? ?? '';
      final cleanText = rawHtml
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final stepPoints =
          _decodePolyline(s['polyline']?['points'] as String? ?? '');

      rawStepsList.add(RouteStep(
        startLocation: LatLng(startLat, startLng),
        endLocation: LatLng(endLat, endLng),
        distanceMeters: stepDist,
        durationSeconds: stepDur,
        maneuver: ManeuverMapper.toJustRideManeuver(rawManeuver, cleanText),
        instruction: cleanText,
        streetName: _extractStreetName(cleanText),
        points: stepPoints.isNotEmpty
            ? stepPoints
            : [LatLng(startLat, startLng), LatLng(endLat, endLng)],
      ));
    }

    final steps = _normalizeSteps(rawStepsList, origin, destination);

    return NavigationRoute(
      totalDistanceMeters: totalDistance,
      totalDurationSeconds: totalDuration,
      polylinePoints: polyline.isNotEmpty ? polyline : [origin, destination],
      steps: steps,
    );
  }

  /// High-speed OSRM Turn-by-Turn routing implementation
  Future<NavigationRoute?> _fetchOsrmRoute(
      LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}?steps=true&overview=full&geometries=polyline',
    );

    final res = await http.get(url, headers: {'User-Agent': 'JustRide/1.0'});
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data['code'] != 'Ok') return null;

    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes[0];
    final totalDistance = (route['distance'] as num?)?.toDouble() ?? 0.0;
    final totalDuration = (route['duration'] as num?)?.toInt() ?? 0;

    // Calibrate duration for motorcycle / two-wheeler travel profile in Indian road conditions:
    // Dense urban (< 5km): ~20 km/h
    // City traffic (5-15km): ~22 km/h
    // Suburban / mixed (15-40km): ~28 km/h
    // Semi-Highway (40-100km): ~36 km/h
    // Long-distance Highway (> 100km): ~43.5 km/h (e.g. 190km = 4h 22m, matching Google Two-Wheeler)
    final distanceKm = totalDistance / 1000.0;
    double avgSpeedKmh;
    if (distanceKm <= 5.0) {
      avgSpeedKmh = 20.0;
    } else if (distanceKm <= 15.0) {
      avgSpeedKmh = 22.0;
    } else if (distanceKm <= 40.0) {
      avgSpeedKmh = 28.0;
    } else if (distanceKm <= 100.0) {
      avgSpeedKmh = 36.0;
    } else {
      avgSpeedKmh = 43.5;
    }

    final calibratedTotalDuration =
        (totalDistance / (avgSpeedKmh * 1000.0 / 3600.0)).round();
    final double durationScale =
        (totalDuration > 0 && calibratedTotalDuration > 0)
            ? (calibratedTotalDuration / totalDuration)
            : 1.0;

    final encodedPoly = route['geometry'] as String? ?? '';
    final polyline = _decodePolyline(encodedPoly);

    final rawStepsList = <RouteStep>[];
    final legs = route['legs'] as List? ?? [];
    if (legs.isNotEmpty) {
      final rawSteps = legs[0]['steps'] as List? ?? [];
      for (final s in rawSteps) {
        final stepDist = (s['distance'] as num?)?.toDouble() ?? 0.0;
        final rawStepDur = (s['duration'] as num?)?.toInt() ?? 0;
        final stepDur = (rawStepDur * durationScale).round();
        final name = (s['name'] as String?) ?? '';
        final maneuverObj = s['maneuver'] as Map<String, dynamic>? ?? {};
        final mType = (maneuverObj['type'] as String?) ?? 'turn';
        final mModifier = (maneuverObj['modifier'] as String?) ?? '';

        String justRideManeuver = 'STRAIGHT';
        if (mType == 'depart') {
          justRideManeuver = 'STRAIGHT';
        } else if (mType == 'arrive') {
          justRideManeuver = 'ARRIVE';
        } else if (mModifier.contains('sharp left')) {
          justRideManeuver = 'SHARP_LEFT';
        } else if (mModifier.contains('sharp right')) {
          justRideManeuver = 'SHARP_RIGHT';
        } else if (mModifier.contains('slight left')) {
          justRideManeuver = 'SLIGHT_LEFT';
        } else if (mModifier.contains('slight right')) {
          justRideManeuver = 'SLIGHT_RIGHT';
        } else if (mModifier.contains('u-turn') ||
            mModifier.contains('uturn')) {
          justRideManeuver = 'U_TURN';
        } else if (mType.contains('roundabout')) {
          justRideManeuver = 'ROUNDABOUT';
        } else if (mModifier.contains('left')) {
          justRideManeuver = 'LEFT';
        } else if (mModifier.contains('right')) {
          justRideManeuver = 'RIGHT';
        }

        final stepPoly = s['geometry'] as String? ?? '';
        final stepPoints = _decodePolyline(stepPoly);
        final startPt = stepPoints.isNotEmpty ? stepPoints.first : origin;
        final endPt = stepPoints.isNotEmpty ? stepPoints.last : destination;

        final instructionText = name.isNotEmpty
            ? '${ManeuverMapper.toRiderActionText(justRideManeuver)} on $name'
            : ManeuverMapper.toRiderActionText(justRideManeuver);

        rawStepsList.add(RouteStep(
          startLocation: startPt,
          endLocation: endPt,
          distanceMeters: stepDist,
          durationSeconds: stepDur,
          maneuver: justRideManeuver,
          instruction: instructionText,
          streetName: name.isNotEmpty ? name : 'Main Road',
          points: stepPoints.isNotEmpty ? stepPoints : [startPt, endPt],
        ));
      }
    }

    final steps = _normalizeSteps(rawStepsList, origin, destination);

    final finalDuration =
        calibratedTotalDuration > 0 ? calibratedTotalDuration : totalDuration;

    return NavigationRoute(
      totalDistanceMeters: totalDistance,
      totalDurationSeconds: finalDuration,
      polylinePoints: polyline.isNotEmpty ? polyline : [origin, destination],
      steps: steps.isNotEmpty
          ? steps
          : [
              RouteStep(
                startLocation: origin,
                endLocation: destination,
                distanceMeters: totalDistance,
                durationSeconds: finalDuration,
                maneuver: 'STRAIGHT',
                instruction: 'Proceed to destination',
                streetName: 'Main Road',
                points: polyline.isNotEmpty ? polyline : [origin, destination],
              ),
            ],
    );
  }

  /// Direct straight-line fallback when offline or no API key available.
  /// Uses the haversine distance between origin and destination so the
  /// preview is at least in the right ballpark.
  NavigationRoute _generateDirectRouteFallback(
      LatLng origin, LatLng destination) {
    // Simplified: degree-to-metre conversion (~111km per degree lat)
    final latDiff = (destination.latitude - origin.latitude).abs() * 111000;
    final lngDiff = (destination.longitude - origin.longitude).abs() *
        111000 *
        _cosDeg((origin.latitude + destination.latitude) / 2);
    final distSquared = latDiff * latDiff + lngDiff * lngDiff;
    final distMeters = distSquared <= 0 ? 1000.0 : _sqrt(distSquared);

    // ETA at 25 km/h urban baseline
    final etaSecs = (distMeters / 6.94).round().clamp(60, 86400);

    return NavigationRoute(
      totalDistanceMeters: distMeters > 0 ? distMeters : 1000.0,
      totalDurationSeconds: etaSecs,
      polylinePoints: [origin, destination],
      steps: [
        RouteStep(
          startLocation: origin,
          endLocation: destination,
          distanceMeters: distMeters > 0 ? distMeters : 1000.0,
          durationSeconds: etaSecs,
          maneuver: 'STRAIGHT',
          instruction: 'Ride toward destination',
          streetName: 'Direct Route',
          points: [origin, destination],
        ),
        RouteStep(
          startLocation: destination,
          endLocation: destination,
          distanceMeters: 0.0,
          durationSeconds: 0,
          maneuver: 'ARRIVE',
          instruction: 'Arrive at destination',
          streetName: 'Destination',
          points: [destination],
        ),
      ],
    );
  }

  static double _cosDeg(double deg) {
    final rad = deg * (3.14159265358979 / 180.0);
    // Simple Taylor approximation for small angles — good enough for coord math
    return 1.0 - (rad * rad / 2.0) + (rad * rad * rad * rad / 24.0);
  }

  static double _sqrt(double v) {
    if (v <= 0) return 0;
    double x = v;
    double last;
    do {
      last = x;
      x = (x + v / x) / 2;
    } while ((x - last).abs() > 0.001);
    return x;
  }

  List<LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return [];
    try {
      final points = PolylinePoints.decodePolyline(encoded);
      return points.map((p) => LatLng(p.latitude, p.longitude)).toList();
    } catch (_) {
      return [];
    }
  }

  String _extractStreetName(String instruction) {
    if (instruction.isEmpty) return 'Main Road';
    final onMatch =
        RegExp(r'(?:onto|on|along)\s+([^,.]+)', caseSensitive: false)
            .firstMatch(instruction);
    if (onMatch != null) {
      return onMatch.group(1)!.trim();
    }
    return instruction.length > 28
        ? '${instruction.substring(0, 25)}...'
        : instruction;
  }

  /// Calculates incoming vs outgoing bearing difference at a junction in range [-180, +180].
  /// Negative values correspond to LEFT turns; positive values correspond to RIGHT turns.
  static double _computeTurnAngle(List<LatLng> curPoints, List<LatLng> nextPoints) {
    if (curPoints.isEmpty || nextPoints.isEmpty) return 0.0;

    // Incoming bearing: from the last 2 distinct points of curPoints
    final pEnd = curPoints.last;
    LatLng pBefore = curPoints.first;
    for (int j = curPoints.length - 2; j >= 0; j--) {
      final pt = curPoints[j];
      final d = Geolocator.distanceBetween(pt.latitude, pt.longitude, pEnd.latitude, pEnd.longitude);
      if (d >= 2.0) {
        pBefore = pt;
        break;
      }
    }
    final inBearing = Geolocator.bearingBetween(pBefore.latitude, pBefore.longitude, pEnd.latitude, pEnd.longitude);

    // Outgoing bearing: from the first 2 distinct points of nextPoints
    final qStart = nextPoints.first;
    LatLng qAfter = nextPoints.last;
    for (int j = 1; j < nextPoints.length; j++) {
      final pt = nextPoints[j];
      final d = Geolocator.distanceBetween(qStart.latitude, qStart.longitude, pt.latitude, pt.longitude);
      if (d >= 2.0) {
        qAfter = pt;
        break;
      }
    }
    final outBearing = Geolocator.bearingBetween(qStart.latitude, qStart.longitude, qAfter.latitude, qAfter.longitude);

    return ((outBearing - inBearing + 540.0) % 360.0) - 180.0;
  }

  /// Normalizes route steps so that each step's maneuver and instruction describe
  /// the turn the rider will execute when approaching that step's endLocation (the upcoming junction).
  /// Road geometry serves as ground truth to verify and correct any contradictory API maneuver tags.
  static List<RouteStep> _normalizeSteps(List<RouteStep> rawSteps, LatLng origin, LatLng destination) {
    if (rawSteps.isEmpty) return rawSteps;
    if (rawSteps.length == 1) {
      final s = rawSteps[0];
      return [
        RouteStep(
          startLocation: s.startLocation,
          endLocation: s.endLocation,
          distanceMeters: s.distanceMeters,
          durationSeconds: s.durationSeconds,
          maneuver: 'ARRIVE',
          instruction: s.instruction.isNotEmpty ? s.instruction : 'Arrive at destination',
          streetName: s.streetName.isNotEmpty ? s.streetName : 'Destination',
          points: s.points,
        )
      ];
    }

    final normalized = <RouteStep>[];

    for (int i = 0; i < rawSteps.length; i++) {
      final cur = rawSteps[i];
      final nxt = (i + 1 < rawSteps.length) ? rawSteps[i + 1] : null;

      if (nxt == null) {
        // Final leg to destination
        normalized.add(RouteStep(
          startLocation: cur.startLocation,
          endLocation: cur.endLocation,
          distanceMeters: cur.distanceMeters,
          durationSeconds: cur.durationSeconds,
          maneuver: 'ARRIVE',
          instruction: cur.instruction.isNotEmpty ? cur.instruction : 'Arrive at destination',
          streetName: cur.streetName.isNotEmpty ? cur.streetName : 'Destination',
          points: cur.points,
        ));
      } else {
        // Immediate U-turn edge case at the very start of navigation
        final bool isImmediateUTurn = (i == 0) &&
            (cur.maneuver.toUpperCase().contains('U_TURN') ||
             cur.maneuver.toUpperCase().contains('UTURN'));

        String upcomingManeuver = isImmediateUTurn ? cur.maneuver : nxt.maneuver;
        String upcomingInstruction = isImmediateUTurn ? cur.instruction : nxt.instruction;
        String upcomingStreet = isImmediateUTurn ? cur.streetName : nxt.streetName;

        // Ground-truth geometry validation
        final turnAngle = _computeTurnAngle(cur.points, nxt.points);

        // If turnAngle indicates a clear LEFT turn (<= -25 deg) but maneuver says RIGHT:
        if (turnAngle <= -25.0 && upcomingManeuver.toUpperCase().contains('RIGHT')) {
          debugPrint(
              '[GoogleMapsService] ⚠ Overriding contradictory RIGHT maneuver to LEFT based on geometry (angle: ${turnAngle.toStringAsFixed(1)}°)');
          upcomingManeuver = (turnAngle <= -135.0)
              ? 'SHARP_LEFT'
              : (turnAngle <= -45.0 ? 'LEFT' : 'SLIGHT_LEFT');
        } else if (turnAngle >= 25.0 && upcomingManeuver.toUpperCase().contains('LEFT')) {
          debugPrint(
              '[GoogleMapsService] ⚠ Overriding contradictory LEFT maneuver to RIGHT based on geometry (angle: ${turnAngle.toStringAsFixed(1)}°)');
          upcomingManeuver = (turnAngle >= 135.0)
              ? 'SHARP_RIGHT'
              : (turnAngle >= 45.0 ? 'RIGHT' : 'SLIGHT_RIGHT');
        } else if ((upcomingManeuver == 'STRAIGHT' || upcomingManeuver.isEmpty) && !isImmediateUTurn) {
          // If maneuver was unspecified or straight but geometry indicates a clear turn:
          if (turnAngle <= -30.0) {
            upcomingManeuver = (turnAngle <= -135.0) ? 'SHARP_LEFT' : (turnAngle <= -45.0 ? 'LEFT' : 'SLIGHT_LEFT');
          } else if (turnAngle >= 30.0) {
            upcomingManeuver = (turnAngle >= 135.0) ? 'SHARP_RIGHT' : (turnAngle >= 45.0 ? 'RIGHT' : 'SLIGHT_RIGHT');
          }
        }

        normalized.add(RouteStep(
          startLocation: cur.startLocation,
          endLocation: cur.endLocation,
          distanceMeters: cur.distanceMeters,
          durationSeconds: cur.durationSeconds,
          maneuver: upcomingManeuver,
          instruction: upcomingInstruction.isNotEmpty
              ? upcomingInstruction
              : ManeuverMapper.toRiderActionText(upcomingManeuver),
          streetName: upcomingStreet.isNotEmpty ? upcomingStreet : 'Main Road',
          points: cur.points,
        ));
      }
    }

    return normalized;
  }
}
