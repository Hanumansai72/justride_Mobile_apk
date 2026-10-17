import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'maps_loader_stub.dart'
    if (dart.library.js_interop) 'maps_loader_web.dart' as maps_loader;

/// Secure configuration manager for Google Maps Platform APIs.
/// Keys are never hard-coded in Dart source files.
///
/// Provide keys at build/run time:
/// ```bash
/// flutter run --dart-define=GOOGLE_MAPS_API_KEY=YOUR_RESTRICTED_KEY
/// ```
abstract final class GoogleMapsConfig {
  static const String _envApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static String _runtimeApiKey = '';
  static bool webMapsLoaded = false;

  /// Sets runtime API key (useful for dynamic settings or testing)
  static void setApiKey(String key) {
    _runtimeApiKey = key.trim();
  }

  /// Reads the Android build-time key from its local Gradle configuration.
  /// A dart-define still takes precedence, so CI and other platforms can
  /// provide a key without relying on this Android bridge.
  static Future<void> loadPlatformApiKey() async {
    if (kIsWeb) {
      if (hasApiKey) {
        try {
          await maps_loader.load(apiKey);
          webMapsLoaded = true;
        } catch (_) {
          debugPrint(
              '[Maps] Browser map could not load. Other app features remain available.');
        }
      }
      return;
    }
    if (_envApiKey.isNotEmpty || _runtimeApiKey.isNotEmpty) return;
    try {
      final key = await const MethodChannel('com.justride.app/maps_config')
          .invokeMethod<String>('getApiKey');
      if (key != null && key.trim().isNotEmpty) setApiKey(key);
    } on MissingPluginException {
      // Non-Android platform: caller may use --dart-define instead.
    } on PlatformException {
      // Keep hasApiKey false; GoogleMapsService reports configuration errors.
    }
  }

  /// Active Google Maps API key (prefer runtime override, then dart-define)
  static String get apiKey {
    if (_runtimeApiKey.isNotEmpty) return _runtimeApiKey;
    return _envApiKey;
  }

  /// Whether an API key has been configured
  static bool get hasApiKey => apiKey.isNotEmpty;

  // ── Endpoint URLs ──────────────────────────────────────────────────────────
  /// Google Routes API v2 (Supports TWO_WHEELER travel mode for motorcycles)
  static const String routesApiEndpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  /// Google Geocoding API for address/coord lookup
  static const String geocodingApiEndpoint =
      'https://maps.googleapis.com/maps/api/geocode/json';

  /// Google Places API (New) Text Search
  static const String placesTextSearchEndpoint =
      'https://places.googleapis.com/v1/places:searchText';

  /// Google Places API (New) Details lookup
  static String placeDetailsEndpoint(String placeId) =>
      'https://places.googleapis.com/v1/places/$placeId';
}
