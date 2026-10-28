/// Route-focused follow camera by default; Google imagery is opt-in.
abstract final class DeviceMapConfig {
  static const enabled =
      bool.fromEnvironment('GOOGLE_DEVICE_MAPS', defaultValue: false);
  static const width = 226, height = 177;
  static const _refreshSeconds =
      int.fromEnvironment('DEVICE_MAP_MIN_REFRESH_SECONDS', defaultValue: 10);
  static Duration get minimumRefresh =>
      Duration(seconds: _refreshSeconds.clamp(10, 300));
  static const endpoint = String.fromEnvironment('DEVICE_MAP_ENDPOINT',
      defaultValue: 'https://backend.justride.cc/api/maps/google-static');
}
