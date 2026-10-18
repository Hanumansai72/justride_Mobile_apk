/// Google mode remains available with --dart-define=LOCATIONIQ_DEVICE_MAPS=false.
/// The LocationIQ token belongs only in the backend environment.
abstract final class DeviceMapConfig {
  static const enabled =
      bool.fromEnvironment('LOCATIONIQ_DEVICE_MAPS', defaultValue: true);
  static const width = 198, height = 194;
  static const _refreshSeconds =
      int.fromEnvironment('DEVICE_MAP_MIN_REFRESH_SECONDS', defaultValue: 20);
  static Duration get minimumRefresh =>
      Duration(seconds: _refreshSeconds.clamp(10, 300));
  static const endpoint = String.fromEnvironment('DEVICE_MAP_ENDPOINT',
      defaultValue: 'https://backend.justride.cc/api/maps/static');
}
