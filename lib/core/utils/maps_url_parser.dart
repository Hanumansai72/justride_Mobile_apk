import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/destination.dart';

/// Comprehensive parser for text and URLs shared from Google Maps and other apps.
class MapsUrlParser {
  static final RegExp _latLngRegex = RegExp(
    r'([-+]?\d{1,2}\.\d{3,})[,\s]+([-+]?\d{1,3}\.\d{3,})',
  );

  static final RegExp _atCoordsRegex = RegExp(
    r'@([-+]?\d{1,2}\.\d+),([-+]?\d{1,3}\.\d+)',
  );

  static final RegExp _dataCoordsRegex = RegExp(
    r'!3d([-+]?\d{1,2}\.\d+)!4d([-+]?\d{1,3}\.\d+)',
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

  /// Strips any URL out of query text to obtain the human-readable place name.
  static String cleanSearchQuery(String raw) {
    var cleaned = raw.replaceAll(_urlRegex, ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ');
    return cleaned.trim();
  }

  /// Analyzes any text shared into JustRide to extract a Destination.
  /// If coordinates cannot be directly extracted, returns a partial Destination
  /// containing the name, address, or placeId so the caller can resolve it via Google Places/Geocoding.
  static Future<Destination?> parseSharedText(String sharedText) async {
    final text = sharedText.trim();
    if (text.isEmpty) return null;

    // 1. Check for a URL inside the text
    final match = _urlRegex.firstMatch(text);
    if (match != null) {
      final foundUrl = match.group(0)!;
      final extraText = cleanSearchQuery(text);

      Destination? parsedFromUrl;
      try {
        parsedFromUrl = await parseUrl(foundUrl);
      } catch (e) {
        debugPrint('[MapsUrlParser] Error parsing URL $foundUrl: $e');
      }

      if (parsedFromUrl != null) {
        // If the URL yielded coordinates, prioritize them
        if (parsedFromUrl.latitude != 0.0 && parsedFromUrl.longitude != 0.0) {
          if (extraText.isNotEmpty &&
              (parsedFromUrl.name == null ||
                  parsedFromUrl.name!.isEmpty ||
                  parsedFromUrl.name == 'Selected Location' ||
                  parsedFromUrl.name == 'Destination')) {
            return parsedFromUrl.copyWith(name: extraText, address: extraText);
          }
          return parsedFromUrl;
        }

        // If URL had a place name extracted
        if (parsedFromUrl.name != null &&
            parsedFromUrl.name!.isNotEmpty &&
            !parsedFromUrl.name!.startsWith('http')) {
          return parsedFromUrl;
        }
      }

      // If URL parsing failed or returned 0,0, but we have clean extraText (e.g. "UIDAI Regional Office - Hyderabad")
      if (extraText.isNotEmpty) {
        debugPrint(
            '[MapsUrlParser] Fallback to extracted place name: "$extraText"');
        return Destination(
          name: extraText,
          address: extraText,
          latitude: 0,
          longitude: 0,
          rawQuery: extraText,
        );
      }

      // If only raw URL was present and could not be resolved
      return Destination(
        name: 'Shared Map Link',
        address: foundUrl,
        latitude: 0,
        longitude: 0,
        rawQuery: foundUrl,
      );
    }

    // 2. Direct coordinate string check e.g. "12.9716, 77.5946"
    final coordMatch = _latLngRegex.firstMatch(text);
    if (coordMatch != null) {
      final lat = double.tryParse(coordMatch.group(1)!);
      final lng = double.tryParse(coordMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoord(lat, lng)) {
        final label = text.replaceAll(coordMatch.group(0)!, '').trim();
        return Destination(
          name: label.isNotEmpty ? label : 'Dropped Pin',
          address: '$lat, $lng',
          latitude: lat,
          longitude: lng,
          rawQuery: text,
        );
      }
    }

    // 3. Address or location name search query fallback
    return Destination(
      name: text,
      address: text,
      latitude: 0,
      longitude: 0,
      rawQuery: text,
    );
  }

  /// Parses a Google Maps URL, following shortened link redirects if needed.
  static Future<Destination?> parseUrl(String inputUrl) async {
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

    // Extract place name from path if available
    // e.g. /maps/place/Cubbon+Park/... or /maps/search/... or /maps/dir/.../Moosapet/...
    String? placeName;
    final placeMatch = _placeNameFromUrlRegex.firstMatch(finalUrl);
    if (placeMatch != null) {
      placeName =
          Uri.decodeComponent(placeMatch.group(1)!).replaceAll('+', ' ');
    } else {
      final searchMatch = _searchNameFromUrlRegex.firstMatch(finalUrl);
      if (searchMatch != null) {
        placeName =
            Uri.decodeComponent(searchMatch.group(1)!).replaceAll('+', ' ');
      } else if (finalUrl.contains('/maps/dir/')) {
        final segments = uri.pathSegments
            .where((s) =>
                s.isNotEmpty &&
                !s.startsWith('data=') &&
                s != 'dir' &&
                s != 'maps')
            .toList();
        if (segments.isNotEmpty) {
          final candidate =
              Uri.decodeComponent(segments.last).replaceAll('+', ' ');
          if (!_latLngRegex.hasMatch(candidate)) {
            placeName = candidate;
          }
        }
      }
    }

    // Check 1: !3d(lat)!4d(lng) identifies the selected pin in a standard
    // Google Maps URL.  It is a destination coordinate, unlike @lat,lng.
    final dataMatch = _dataCoordsRegex.firstMatch(finalUrl);
    if (dataMatch != null) {
      final lat = double.tryParse(dataMatch.group(1)!);
      final lng = double.tryParse(dataMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoord(lat, lng)) {
        return Destination(
          name: placeName ?? 'Selected Location',
          address: placeName,
          latitude: lat,
          longitude: lng,
          rawQuery: finalUrl,
        );
      }
    }

    // Check 2: Check query parameters (q, query, destination, ll, sll)
    final q = uri.queryParameters['q'] ??
        uri.queryParameters['query'] ??
        uri.queryParameters['destination'] ??
        uri.queryParameters['ll'] ??
        uri.queryParameters['sll'];

    if (q != null && q.isNotEmpty) {
      final qMatch = _latLngRegex.firstMatch(q);
      if (qMatch != null) {
        final lat = double.tryParse(qMatch.group(1)!);
        final lng = double.tryParse(qMatch.group(2)!);
        if (lat != null && lng != null && _isValidCoord(lat, lng)) {
          return Destination(
            name: placeName ?? 'Destination',
            address: q,
            latitude: lat,
            longitude: lng,
            rawQuery: finalUrl,
          );
        }
      } else {
        // Query is an address / place string
        return Destination(
          name: placeName ?? q,
          address: q,
          latitude: 0,
          longitude: 0,
          rawQuery: q,
        );
      }
    }

    // Check 3: Check for place_id query parameter
    final placeId = uri.queryParameters['place_id'] ??
        uri.queryParameters['query_place_id'];
    if (placeId != null && placeId.isNotEmpty) {
      return Destination(
        name: placeName ?? 'Google Maps Place',
        placeId: placeId,
        latitude: 0,
        longitude: 0,
        rawQuery: finalUrl,
      );
    }

    // If placeName was extracted from /maps/place/..., return it as an address query to resolve
    if (placeName != null && placeName.isNotEmpty) {
      return Destination(
        name: placeName,
        address: placeName,
        latitude: 0,
        longitude: 0,
        rawQuery: placeName,
      );
    }

    // @lat,lng is normally Google Maps' camera position.  Only use it as a
    // last resort when the link contains neither a selected pin, query nor
    // readable place name; otherwise "Koti/@17.40154,78.56817" routes to the
    // map viewport instead of Koti itself.
    final atMatch = _atCoordsRegex.firstMatch(finalUrl);
    if (atMatch != null) {
      final lat = double.tryParse(atMatch.group(1)!);
      final lng = double.tryParse(atMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoord(lat, lng)) {
        return Destination(
          name: 'Selected Location',
          latitude: lat,
          longitude: lng,
          rawQuery: finalUrl,
        );
      }
    }

    return null;
  }

  /// Follows HTTP 301/302/307 redirects across multiple hops up to 6 steps,
  /// also parsing HTML meta-refresh / og:url tags if an HTML landing page is returned.
  static Future<String?> _resolveRedirectChain(String initialUrl) async {
    final client = http.Client();
    try {
      var currentUrl = initialUrl;
      for (int hop = 0; hop < 6; hop++) {
        final request = http.Request('GET', Uri.parse(currentUrl))
          ..followRedirects = false
          ..headers['User-Agent'] =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

        final response =
            await client.send(request).timeout(const Duration(seconds: 12));
        final status = response.statusCode;
        final location = response.headers['location'];

        // 3xx Redirection
        if (status >= 300 &&
            status < 400 &&
            location != null &&
            location.isNotEmpty) {
          final nextUri = Uri.parse(currentUrl).resolve(location);
          currentUrl = nextUri.toString();
          // If we reached a full maps URL with coords, we can stop early
          if (currentUrl.contains('@') || currentUrl.contains('!3d')) {
            return currentUrl;
          }
          continue;
        }

        // 200 OK — check HTML body for canonical or og:url
        if (status == 200) {
          final body = await response.stream.bytesToString();

          // Check HTML meta refresh tag
          final metaRefresh = RegExp(
            r'<meta[^>]*http-equiv=["\x27]refresh["\x27][^>]*content=["\x27]\d+;\s*url=([^"\x27]+)["\x27]',
            caseSensitive: false,
          ).firstMatch(body);
          if (metaRefresh != null) {
            final nextUrl = metaRefresh.group(1)!;
            currentUrl = Uri.parse(currentUrl).resolve(nextUrl).toString();
            continue;
          }

          // Check OpenGraph URL
          final ogUrl = RegExp(
            r'<meta[^>]*property=["\x27]og:url["\x27][^>]*content=["\x27]([^"\x27]+)["\x27]',
            caseSensitive: false,
          ).firstMatch(body);
          if (ogUrl != null) {
            return ogUrl.group(1);
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
