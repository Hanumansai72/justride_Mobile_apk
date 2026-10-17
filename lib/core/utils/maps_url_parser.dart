import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/destination.dart';

/// Represents the result of parsing shared text/URLs from Google Maps or other navigation apps.
/// May contain both an explicit destination and an optional start location (for shared routes/directions).
class ParsedShareResult {
  final Destination destination;
  final Destination? startLocation;

  const ParsedShareResult({
    required this.destination,
    this.startLocation,
  });

  @override
  String toString() =>
      'ParsedShareResult(dest: ${destination.displayTitle}, start: ${startLocation?.displayTitle})';
}

/// Comprehensive parser for text and URLs shared from Google Maps and other apps.
/// Engineered for high accuracy, handling DMS coordinates, protobuf tokens,
/// redirect chains, query parameters, HTML metadata, and geo: URIs.
class MapsUrlParser {
  static final RegExp _latLngRegex = RegExp(
    r'([-+]?\d{1,2}\.\d{3,})[,\s]+([-+]?\d{1,3}\.\d{3,})',
  );

  static final RegExp _dmsDmmRegex = RegExp(
    r'''(\d{1,2})[°\s]+(?:(\d{1,2})['\s]+([\d.]+)(?:["\s]*)?|([\d.]+)['\s]*)([NSns])[,;\s]+(\d{1,3})[°\s]+(?:(\d{1,2})['\s]+([\d.]+)(?:["\s]*)?|([\d.]+)['\s]*)([EWew])''',
  );

  static final RegExp _atCoordsRegex = RegExp(
    r'@([-+]?\d{1,2}\.\d+),([-+]?\d{1,3}\.\d+)',
  );

  static final RegExp _latProtobufRegex = RegExp(
    r'!3d([-+]?\d{1,2}\.\d+)',
  );

  static final RegExp _lngProtobufRegex = RegExp(
    r'!4d([-+]?\d{1,3}\.\d+)',
  );

  static final RegExp _placeNameFromUrlRegex = RegExp(
    r'/maps/place/([^/@?]+)',
  );

  static final RegExp _searchNameFromUrlRegex = RegExp(
    r'/maps/search/([^/@?]+)',
  );

  static final RegExp _urlRegex = RegExp(
    r'https?://[^\s]+',
  );

  static final RegExp _geoUriRegex = RegExp(
    r'^geo:([-+]?\d{1,2}\.\d+),([-+]?\d{1,3}\.\d+)(?:\?.*)?$',
    caseSensitive: false,
  );

  static final RegExp _ogImageMarkerRegex = RegExp(
    r'markers=(?:color:[^%|&]+%7C)?([-+]?\d{1,2}\.\d+)(?:%2C|,)([-+]?\d{1,3}\.\d+)',
    caseSensitive: false,
  );

  static final RegExp _staticMapCenterRegex = RegExp(
    r'center=([-+]?\d{1,2}\.\d+)(?:%2C|,)([-+]?\d{1,3}\.\d+)',
    caseSensitive: false,
  );

  static final RegExp _appStateCoordsRegex = RegExp(
    r'\[null,null,([-+]?\d{1,2}\.\d{3,}),([-+]?\d{1,3}\.\d{3,})\]',
  );

  static final RegExp _sharedRouteRegex = RegExp(
    r'(?:Shared\s+route\s+)?From[:\s]+(.+?)\s+(?:to|->)[:\s]+(.+?)(?:\s+via\b|\.(?:\s*[\r\n]|$)|[\r\n]|$)',
    caseSensitive: false,
  );

  /// Converts Degrees-Minutes-Seconds (DMS) or Degrees-Decimal-Minutes (DDM) string
  /// (e.g. 17°21'41.6"N 78°28'28.9"E or 17°21.693'N 78°28.482'E) into exact decimal coordinates.
  static (double, double)? parseDmsCoordinates(String raw) {
    var text = raw;
    try {
      text = Uri.decodeComponent(text);
    } catch (_) {}
    text = text.replaceAll('+', ' ');

    final match = _dmsDmmRegex.firstMatch(text);
    if (match == null) return null;

    final latDeg = double.tryParse(match.group(1) ?? '');
    final latMin = double.tryParse(match.group(2) ?? '');
    final latSec = double.tryParse(match.group(3) ?? '');
    final latDecMin = double.tryParse(match.group(4) ?? '');
    final latHem = (match.group(5) ?? 'N').toUpperCase();

    final lngDeg = double.tryParse(match.group(6) ?? '');
    final lngMin = double.tryParse(match.group(7) ?? '');
    final lngSec = double.tryParse(match.group(8) ?? '');
    final lngDecMin = double.tryParse(match.group(9) ?? '');
    final lngHem = (match.group(10) ?? 'E').toUpperCase();

    if (latDeg == null || lngDeg == null) return null;

    double lat;
    if (latMin != null && latSec != null) {
      lat = latDeg + (latMin / 60.0) + (latSec / 3600.0);
    } else if (latDecMin != null) {
      lat = latDeg + (latDecMin / 60.0);
    } else {
      lat = latDeg;
    }
    if (latHem == 'S') lat = -lat;

    double lng;
    if (lngMin != null && lngSec != null) {
      lng = lngDeg + (lngMin / 60.0) + (lngSec / 3600.0);
    } else if (lngDecMin != null) {
      lng = lngDeg + (lngDecMin / 60.0);
    } else {
      lng = lngDeg;
    }
    if (lngHem == 'W') lng = -lng;

    if (_isValidCoord(lat, lng)) {
      return (lat, lng);
    }
    return null;
  }

  /// Strips URLs and route sharing boilerplate to obtain the clean destination or place name.
  static String cleanSearchQuery(String raw) {
    var cleaned = raw.replaceAll(_urlRegex, ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^\s*Shared\s+route\s*', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'For the best route.*$', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\d+\s*(?:min|mins|hr|hrs|hour|hours|km|m)\b.*$', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ');
    cleaned = cleaned.trim();

    // If this is a route string ("From <origin> to <destination>"), extract the destination!
    // Never send "From Miyapur to Uppal" to a geocoder, because it resolves the first word (Miyapur).
    final routeMatch = _sharedRouteRegex.firstMatch(cleaned);
    if (routeMatch != null) {
      final destPart = routeMatch.group(2)?.trim();
      if (destPart != null && destPart.isNotEmpty) {
        final parsedDest = _parseEndpointString(destPart);
        if (parsedDest != null && parsedDest.name != null && parsedDest.name!.isNotEmpty) {
          return parsedDest.name!;
        }
      }
    }

    return cleaned;
  }

  /// Parses an individual endpoint string (origin or destination) from route directions.
  static Destination? _parseEndpointString(String raw) {
    var s = raw.trim();
    s = s.replaceAll(RegExp(r'[\.,;]+$'), '').trim();
    s = s.replaceAll(RegExp(r'\s+via\s+.*$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'\d+\s*(?:min|mins|hr|hrs|hour|hours|km|m)\b.*$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'^(?:From|To)[:\s]+', caseSensitive: false), '').trim();
    if (s.isEmpty) return null;

    final lower = s.toLowerCase();
    if (lower == 'your location' ||
        lower == 'current location' ||
        lower == 'my location' ||
        lower == 'selected location') {
      return null;
    }

    // Check DMS format
    final dms = parseDmsCoordinates(s);
    if (dms != null) {
      return Destination(
        name: 'Selected Location',
        address: '${dms.$1}, ${dms.$2}',
        latitude: dms.$1,
        longitude: dms.$2,
        rawQuery: s,
      );
    }

    // Check lat,lng format e.g. (17.5102, 78.3204)
    final coordMatch = _latLngRegex.firstMatch(s);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoord(lat, lng)) {
        final label = s
            .replaceAll(coordMatch.group(0)!, '')
            .replaceAll(RegExp(r'[()]'), '')
            .trim();
        return Destination(
          name: label.isNotEmpty ? label : 'Selected Location',
          address: '$lat, $lng',
          latitude: lat,
          longitude: lng,
          rawQuery: s,
        );
      }
    }

    return Destination(
      name: s,
      address: s,
      latitude: 0,
      longitude: 0,
      rawQuery: s,
    );
  }

  /// Analyzes any text shared into JustRide to extract a Destination and optional Start location.
  /// Handles "Shared route From <origin> to <destination>" as well as single place shares,
  /// dropped pins, DMS coordinates, and shortened/full Google Maps links.
  static Future<ParsedShareResult?> parseSharedContent(String sharedText) async {
    final text = sharedText.trim();
    if (text.isEmpty) return null;

    // 1. Check for geo: URI scheme (e.g. geo:17.3615,78.4746 or geo:0,0?q=...)
    if (text.startsWith('geo:')) {
      final geoParsed = _parseGeoUri(text);
      if (geoParsed != null) {
        return ParsedShareResult(destination: geoParsed);
      }
    }

    // 2. Check for route sharing pattern ("From <Origin> to <Destination>")
    Destination? routeOrigin;
    Destination? routeDest;

    final routeMatch = _sharedRouteRegex.firstMatch(text);
    if (routeMatch != null) {
      final rawOrigin = routeMatch.group(1)!.trim();
      final rawDest = routeMatch.group(2)!.trim();

      routeOrigin = _parseEndpointString(rawOrigin);
      routeDest = _parseEndpointString(rawDest);
      debugPrint('[MapsUrlParser] Detected shared route - Origin: "${routeOrigin?.displayTitle}", Destination: "${routeDest?.displayTitle}"');
    }

    // 3. Check for DMS coordinates in text before URL parsing
    final dmsCoords = parseDmsCoordinates(text);

    // 4. Check for a URL inside the text
    final match = _urlRegex.firstMatch(text);
    if (match != null) {
      final foundUrl = match.group(0)!;
      final extraText = cleanSearchQuery(text);

      ParsedShareResult? parsedResultFromUrl;
      try {
        parsedResultFromUrl = await parseUrlDetailed(foundUrl);
      } catch (e) {
        debugPrint('[MapsUrlParser] Error parsing URL $foundUrl: $e');
      }

      if (parsedResultFromUrl != null) {
        final parsedDest = parsedResultFromUrl.destination;
        if (routeOrigin == null && parsedResultFromUrl.startLocation != null) {
          routeOrigin = parsedResultFromUrl.startLocation;
        }

        // If the URL yielded coordinates, prioritize them
        if (parsedDest.latitude != 0.0 && parsedDest.longitude != 0.0) {
          final targetDest = routeDest != null
              ? routeDest.copyWith(
                  latitude: parsedDest.latitude,
                  longitude: parsedDest.longitude,
                )
              : (extraText.isNotEmpty &&
                      (parsedDest.name == null ||
                          parsedDest.name!.isEmpty ||
                          parsedDest.name == 'Selected Location' ||
                          parsedDest.name == 'Destination')
                  ? parsedDest.copyWith(name: extraText, address: extraText)
                  : parsedDest);

          return ParsedShareResult(
            destination: targetDest,
            startLocation: routeOrigin,
          );
        }

        // If URL had a place name extracted
        if (parsedDest.name != null &&
            parsedDest.name!.isNotEmpty &&
            !parsedDest.name!.startsWith('http')) {
          // If extraText contains DMS coords, apply them directly
          if (dmsCoords != null) {
            return ParsedShareResult(
              destination: parsedDest.copyWith(
                latitude: dmsCoords.$1,
                longitude: dmsCoords.$2,
              ),
              startLocation: routeOrigin,
            );
          }
          return ParsedShareResult(
            destination: routeDest ?? parsedDest,
            startLocation: routeOrigin,
          );
        }
      }

      // If URL did not give coords, but route destination was extracted
      if (routeDest != null) {
        return ParsedShareResult(
          destination: routeDest,
          startLocation: routeOrigin,
        );
      }

      // If URL did not give coords, but DMS coordinates were in the shared text
      if (dmsCoords != null) {
        final label = extraText.isNotEmpty ? extraText : 'Dropped Pin';
        return ParsedShareResult(
          destination: Destination(
            name: label,
            address: '${dmsCoords.$1}, ${dmsCoords.$2}',
            latitude: dmsCoords.$1,
            longitude: dmsCoords.$2,
            rawQuery: text,
          ),
        );
      }

      // Direct coordinate check in extraText (e.g. "Dropped pin near 17.3615, 78.4746")
      final extraCoordMatch = _latLngRegex.firstMatch(extraText);
      if (extraCoordMatch != null) {
        final lat = double.tryParse(extraCoordMatch.group(1)!);
        final lng = double.tryParse(extraCoordMatch.group(2)!);
        if (lat != null && lng != null && _isValidCoord(lat, lng)) {
          final label =
              extraText.replaceAll(extraCoordMatch.group(0)!, '').trim();
          return ParsedShareResult(
            destination: Destination(
              name: label.isNotEmpty ? label : 'Dropped Pin',
              address: '$lat, $lng',
              latitude: lat,
              longitude: lng,
              rawQuery: text,
            ),
          );
        }
      }

      // If URL parsing failed or returned 0,0, but we have clean extraText
      if (extraText.isNotEmpty) {
        debugPrint(
            '[MapsUrlParser] Fallback to extracted place name: "$extraText"');
        return ParsedShareResult(
          destination: Destination(
            name: extraText,
            address: extraText,
            latitude: 0,
            longitude: 0,
            rawQuery: extraText,
          ),
          startLocation: routeOrigin,
        );
      }

      // If only raw URL was present and could not be resolved
      return ParsedShareResult(
        destination: Destination(
          name: 'Shared Map Link',
          address: foundUrl,
          latitude: 0,
          longitude: 0,
          rawQuery: foundUrl,
        ),
      );
    }

    // 5. Shared route without a URL
    if (routeDest != null) {
      return ParsedShareResult(
        destination: routeDest,
        startLocation: routeOrigin,
      );
    }

    // 6. Direct DMS coordinate check without URL e.g. "17°21'41.6\"N 78°28'28.9\"E"
    if (dmsCoords != null) {
      return ParsedShareResult(
        destination: Destination(
          name: 'Dropped Pin',
          address: '${dmsCoords.$1}, ${dmsCoords.$2}',
          latitude: dmsCoords.$1,
          longitude: dmsCoords.$2,
          rawQuery: text,
        ),
      );
    }

    // 7. Direct coordinate string check e.g. "17.3615, 78.4746"
    final coordMatch = _latLngRegex.firstMatch(text);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoord(lat, lng)) {
        final label = text.replaceAll(coordMatch.group(0)!, '').trim();
        return ParsedShareResult(
          destination: Destination(
            name: label.isNotEmpty ? label : 'Dropped Pin',
            address: '$lat, $lng',
            latitude: lat,
            longitude: lng,
            rawQuery: text,
          ),
        );
      }
    }

    // 8. Address or location name search query fallback
    return ParsedShareResult(
      destination: Destination(
        name: text,
        address: text,
        latitude: 0,
        longitude: 0,
        rawQuery: text,
      ),
    );
  }

  /// Analyzes any text shared into JustRide to extract a Destination.
  /// Maintained for backwards compatibility. Delegates to [parseSharedContent].
  static Future<Destination?> parseSharedText(String sharedText) async {
    final result = await parseSharedContent(sharedText);
    return result?.destination;
  }

  /// Parses a Google Maps URL and extracts both destination and optional origin (for /maps/dir/ routes).
  static Future<ParsedShareResult?> parseUrlDetailed(String inputUrl) async {
    String finalUrl = inputUrl.trim();

    // If it's a shortened URL (goo.gl / maps.app.goo.gl), resolve the redirect chain
    if (finalUrl.contains('goo.gl') || finalUrl.contains('maps.app.goo.gl')) {
      try {
        final resolved = await _resolveRedirectChain(finalUrl);
        if (resolved != null && resolved.isNotEmpty) {
          finalUrl = resolved;
        }
      } catch (e) {
        debugPrint('[MapsUrlParser] Redirect resolution exception: $e');
      }
    }

    final uri = Uri.tryParse(finalUrl);
    if (uri == null) return null;

    final isDirectionUrl = finalUrl.contains('/maps/dir/');
    String? placeName;
    (double, double)? pathCoords;
    Destination? routeOrigin;

    final placeMatch = _placeNameFromUrlRegex.firstMatch(finalUrl);
    if (placeMatch != null) {
      final rawSegment = Uri.decodeComponent(placeMatch.group(1)!).replaceAll('+', ' ');
      final dms = parseDmsCoordinates(rawSegment);
      if (dms != null) {
        pathCoords = dms;
      } else {
        final match = _latLngRegex.firstMatch(rawSegment);
        if (match != null) {
          final lat = double.tryParse(match.group(1)!);
          final lng = double.tryParse(match.group(2)!);
          if (lat != null && lng != null && _isValidCoord(lat, lng)) {
            pathCoords = (lat, lng);
          }
        }
      }
      if (pathCoords == null) {
        placeName = rawSegment;
      }
    } else {
      final searchMatch = _searchNameFromUrlRegex.firstMatch(finalUrl);
      if (searchMatch != null) {
        final rawSegment = Uri.decodeComponent(searchMatch.group(1)!).replaceAll('+', ' ');
        final dms = parseDmsCoordinates(rawSegment);
        if (dms != null) {
          pathCoords = dms;
        } else {
          final match = _latLngRegex.firstMatch(rawSegment);
          if (match != null) {
            final lat = double.tryParse(match.group(1)!);
            final lng = double.tryParse(match.group(2)!);
            if (lat != null && lng != null && _isValidCoord(lat, lng)) {
              pathCoords = (lat, lng);
            }
          }
        }
        if (pathCoords == null) {
          placeName = rawSegment;
        }
      } else if (isDirectionUrl) {
        final segments = uri.pathSegments
            .where((s) =>
                s.isNotEmpty &&
                !s.startsWith('data=') &&
                !s.startsWith('@') &&
                s != 'dir' &&
                s != 'maps')
            .toList();
        if (segments.isNotEmpty) {
          if (segments.length >= 2) {
            final originCandidate =
                Uri.decodeComponent(segments.first).replaceAll('+', ' ');
            routeOrigin = _parseEndpointString(originCandidate);
          }
          final candidate =
              Uri.decodeComponent(segments.last).replaceAll('+', ' ');
          final dms = parseDmsCoordinates(candidate);
          if (dms != null) {
            pathCoords = dms;
          } else {
            final match = _latLngRegex.firstMatch(candidate);
            if (match != null) {
              final lat = double.tryParse(match.group(1)!);
              final lng = double.tryParse(match.group(2)!);
              if (lat != null && lng != null && _isValidCoord(lat, lng)) {
                pathCoords = (lat, lng);
              }
            } else {
              placeName = candidate;
            }
          }
        }
      }
    }

    // Check query parameters for origin
    final originQuery = uri.queryParameters['origin'] ?? uri.queryParameters['saddr'];
    if (originQuery != null && originQuery.isNotEmpty && routeOrigin == null) {
      routeOrigin = _parseEndpointString(originQuery);
    }

    Destination? dest;

    // Check 1: Decoupled !3d(lat) and !4d(lng) identifies the selected pin
    // in Google Maps URLs. Decoupled so order or intervening parameters never fail.
    // NOTE: For /maps/dir/ URLs, protobuf coordinates can correspond to the origin/waypoint
    // and must not be used to override the destination name.
    if (!isDirectionUrl) {
      final latMatch = _latProtobufRegex.firstMatch(finalUrl);
      final lngMatch = _lngProtobufRegex.firstMatch(finalUrl);
      if (latMatch != null && lngMatch != null) {
        final lat = double.tryParse(latMatch.group(1)!);
        final lng = double.tryParse(lngMatch.group(1)!);
        if (lat != null && lng != null && _isValidCoord(lat, lng)) {
          dest = Destination(
            name: placeName ?? 'Selected Location',
            address: placeName ?? '$lat, $lng',
            latitude: lat,
            longitude: lng,
            rawQuery: finalUrl,
          );
        }
      }
    }

    // Check 2: If path segment itself was coordinates (e.g. /maps/place/17.3615,78.4746)
    if (dest == null && pathCoords != null) {
      dest = Destination(
        name: placeName ?? 'Selected Location',
        address: '${pathCoords.$1}, ${pathCoords.$2}',
        latitude: pathCoords.$1,
        longitude: pathCoords.$2,
        rawQuery: finalUrl,
      );
    }

    // Check 3: Check query parameters (q, query, destination, daddr, ll, sll, center, near)
    if (dest == null) {
      final q = uri.queryParameters['q'] ??
          uri.queryParameters['query'] ??
          uri.queryParameters['destination'] ??
          uri.queryParameters['daddr'] ??
          uri.queryParameters['ll'] ??
          uri.queryParameters['sll'] ??
          uri.queryParameters['center'] ??
          uri.queryParameters['near'];

      if (q != null && q.isNotEmpty) {
        final dms = parseDmsCoordinates(q);
        if (dms != null) {
          dest = Destination(
            name: placeName ?? 'Selected Location',
            address: '${dms.$1}, ${dms.$2}',
            latitude: dms.$1,
            longitude: dms.$2,
            rawQuery: finalUrl,
          );
        } else {
          final qMatch = _latLngRegex.firstMatch(q);
          if (qMatch != null) {
            final lat = double.tryParse(qMatch.group(1)!);
            final lng = double.tryParse(qMatch.group(2)!);
            if (lat != null && lng != null && _isValidCoord(lat, lng)) {
              dest = Destination(
                name: placeName ?? 'Destination',
                address: q,
                latitude: lat,
                longitude: lng,
                rawQuery: finalUrl,
              );
            }
          } else {
            // Query is an address / place string
            dest = Destination(
              name: placeName ?? q,
              address: q,
              latitude: 0,
              longitude: 0,
              rawQuery: q,
            );
          }
        }
      }
    }

    // Check 4: Check for place_id query parameter
    if (dest == null) {
      final placeId = uri.queryParameters['place_id'] ??
          uri.queryParameters['query_place_id'];
      if (placeId != null && placeId.isNotEmpty) {
        dest = Destination(
          name: placeName ?? 'Google Maps Place',
          placeId: placeId,
          latitude: 0,
          longitude: 0,
          rawQuery: finalUrl,
        );
      }
    }

    // Check 5: If placeName was extracted from /maps/place/... or /maps/dir/..., return it as an address query to resolve
    if (dest == null && placeName != null && placeName.isNotEmpty) {
      dest = Destination(
        name: placeName,
        address: placeName,
        latitude: 0,
        longitude: 0,
        rawQuery: placeName,
      );
    }

    // Check 6: @lat,lng in URL path or query (Camera / map center position fallback when no place name is found)
    // NOTE: In /maps/dir/ URLs, @lat,lng is the camera/viewport center between origin & destination
    // (often centered on the origin e.g. Miyapur), NOT the destination coordinate!
    // Never assign camera coordinates to the destination in direction/route URLs.
    if (dest == null && !isDirectionUrl) {
      final atMatch = _atCoordsRegex.firstMatch(finalUrl);
      if (atMatch != null) {
        final lat = double.tryParse(atMatch.group(1)!);
        final lng = double.tryParse(atMatch.group(2)!);
        if (lat != null && lng != null && _isValidCoord(lat, lng)) {
          dest = Destination(
            name: 'Selected Location',
            address: '$lat, $lng',
            latitude: lat,
            longitude: lng,
            rawQuery: finalUrl,
          );
        }
      }
    }

    if (dest == null) return null;

    return ParsedShareResult(
      destination: dest,
      startLocation: routeOrigin,
    );
  }

  /// Parses a Google Maps URL, following shortened link redirects if needed.
  /// Delegates to [parseUrlDetailed] for full parsing.
  static Future<Destination?> parseUrl(String inputUrl) async {
    final res = await parseUrlDetailed(inputUrl);
    return res?.destination;
  }

  /// Parses a geo: URI (e.g. geo:17.3615,78.4746?z=16 or geo:0,0?q=17.3615,78.4746(Label))
  static Destination? _parseGeoUri(String geoUri) {
    final uri = Uri.tryParse(geoUri);
    if (uri == null || uri.scheme != 'geo') return null;

    final q = uri.queryParameters['q'];
    if (q != null && q.isNotEmpty) {
      final labelMatch = RegExp(r'^(.*?)\((.*)\)$').firstMatch(q);
      final target = labelMatch != null ? labelMatch.group(1)!.trim() : q;
      final label = labelMatch != null ? labelMatch.group(2)!.trim() : null;

      final coordMatch = _latLngRegex.firstMatch(target);
      if (coordMatch != null) {
        final lat = double.tryParse(coordMatch.group(1)!);
        final lng = double.tryParse(coordMatch.group(2)!);
        if (lat != null && lng != null && _isValidCoord(lat, lng)) {
          return Destination(
            name: label ?? 'Selected Location',
            address: '$lat, $lng',
            latitude: lat,
            longitude: lng,
            rawQuery: geoUri,
          );
        }
      }
      return Destination(
        name: label ?? target,
        address: target,
        latitude: 0,
        longitude: 0,
        rawQuery: geoUri,
      );
    }

    // Parse geo:lat,lng
    final match = _geoUriRegex.firstMatch(geoUri);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && (lat != 0.0 || lng != 0.0) && _isValidCoord(lat, lng)) {
        return Destination(
          name: 'Selected Location',
          address: '$lat, $lng',
          latitude: lat,
          longitude: lng,
          rawQuery: geoUri,
        );
      }
    }

    return null;
  }

  /// Follows HTTP redirects up to 6 hops, parsing final URL and HTML body
  /// (OG image markers, staticmap centers, and app initialization state).
  static Future<String?> _resolveRedirectChain(String initialUrl) async {
    final client = http.Client();
    try {
      var currentUrl = initialUrl;
      for (int hop = 0; hop < 6; hop++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

        final response =
            await client.send(request).timeout(const Duration(seconds: 10));
        final status = response.statusCode;
        final location = response.headers['location'];

        // 3xx Redirection
        if (status >= 300 &&
            status < 400 &&
            location != null &&
            location.isNotEmpty) {
          final nextUri = Uri.parse(currentUrl).resolve(location);
          currentUrl = nextUri.toString();

          // Handle Google cookie consent gate by extracting target URL from 'continue' parameter
          if (currentUrl.contains('consent.google.com')) {
            final continueParam = nextUri.queryParameters['continue'];
            if (continueParam != null && continueParam.isNotEmpty) {
              currentUrl = Uri.decodeFull(continueParam);
              debugPrint('[MapsUrlParser] Extracted target URL from consent page: $currentUrl');
            }
          }

          // Stop early if the redirect URL already contains full place/route coordinates or parameters
          if ((currentUrl.contains('!3d') && currentUrl.contains('!4d')) ||
              (currentUrl.contains('/maps/place/') && currentUrl.contains('@')) ||
              currentUrl.contains('/maps/dir/') ||
              nextUri.queryParameters.containsKey('q') ||
              nextUri.queryParameters.containsKey('destination') ||
              nextUri.queryParameters.containsKey('daddr')) {
            return currentUrl;
          }
          continue;
        }

        // 200 OK — check HTML body for canonical or og:url and embedded coordinates
        if (status == 200) {
          final body = await response.stream.bytesToString();

          // 1. Check HTML meta refresh tag
          final metaRefresh = RegExp(
            r'<meta[^>]*http-equiv=["\x27]refresh["\x27][^>]*content=["\x27]\d+;\s*url=([^"\x27]+)["\x27]',
            caseSensitive: false,
          ).firstMatch(body);
          if (metaRefresh != null) {
            final nextUrl = metaRefresh.group(1)!;
            currentUrl = Uri.parse(currentUrl).resolve(nextUrl).toString();
            if (currentUrl.contains('!3d') && currentUrl.contains('!4d')) {
              return currentUrl;
            }
            continue;
          }

          // 2. Check OpenGraph URL
          final ogUrl = RegExp(
            r'<meta[^>]*property=["\x27]og:url["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
            caseSensitive: false,
          ).firstMatch(body);
          if (ogUrl != null) {
            final content = ogUrl.group(1)!;
            if (content.contains('!3d') && content.contains('!4d')) {
              return content;
            }
            currentUrl = content;
          }

          // 3. Check OpenGraph image markers (Exact pin coordinates in staticmap marker URL)
          final ogImageMatch = _ogImageMarkerRegex.firstMatch(body);
          if (ogImageMatch != null) {
            final lat = double.tryParse(ogImageMatch.group(1)!);
            final lng = double.tryParse(ogImageMatch.group(2)!);
            if (lat != null && lng != null && _isValidCoord(lat, lng)) {
              return '$currentUrl&q=$lat,$lng!3d$lat!4d$lng';
            }
          }

          // 4. Check staticmap center
          final centerMatch = _staticMapCenterRegex.firstMatch(body);
          if (centerMatch != null) {
            final lat = double.tryParse(centerMatch.group(1)!);
            final lng = double.tryParse(centerMatch.group(2)!);
            if (lat != null && lng != null && _isValidCoord(lat, lng)) {
              return '$currentUrl&q=$lat,$lng!3d$lat!4d$lng';
            }
          }

          // 5. Check window.APP_INITIALIZATION_STATE
          final appStateMatch = _appStateCoordsRegex.firstMatch(body);
          if (appStateMatch != null) {
            final lat = double.tryParse(appStateMatch.group(1)!);
            final lng = double.tryParse(appStateMatch.group(2)!);
            if (lat != null && lng != null && _isValidCoord(lat, lng)) {
              return '$currentUrl&q=$lat,$lng!3d$lat!4d$lng';
            }
          }

          return currentUrl;
        }

        break;
      }
      return currentUrl;
    } catch (e) {
      debugPrint('[MapsUrlParser] _resolveRedirectChain error: $e');
      return initialUrl;
    } finally {
      client.close();
    }
  }

  static bool _isValidCoord(double lat, double lng) {
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }
}
