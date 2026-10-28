/// App-wide constant values used across the JustRide UI.
abstract final class AppConstants {
  // ── Spacing ───────────────────────────────────────────────────────────────
  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 12.0;
  static const double spacingLg = 16.0;
  static const double spacingXl = 20.0;
  static const double spacingXxl = 24.0;
  static const double spacingSection = 32.0;

  // ── Border Radius ─────────────────────────────────────────────────────────
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusCircle = 100.0;

  // ── Horizontal page padding ───────────────────────────────────────────────
  static const double pagePadding = 16.0;

  // ── Animation durations ───────────────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 400);

  // ── Dummy data ────────────────────────────────────────────────────────────
  static const String deviceName = 'JustRide Device';
  static const int batteryPercent = 0;
  static const String lastRouteName = 'HITEC City';
  static const String lastRouteVia = 'via Gachibowli';
  static const String lastRouteDistance = '12.4 km';
  static const String lastRouteEta = '25 min';
  static const String firmwareVersion = 'v1.2.3';
  static const String tripDistance = '0.0 km';
  static const String tripTime = '0 min';
  static const String tripSpeed = '0 km/h';
  static const String batteryRemaining = '2h 15m remaining';
  static const String homeTime = '12 min';
  static const String workTime = '24 min';
  static const int favCount = 3;
  static const int recentCount = 5;

  // ── App Release & Version ──────────────────────────────────────────────────
  static const String appVersion = 'v1.2.2';
  static const int appBuildNumber = 8;

  // ── Google OAuth ──────────────────────────────────────────────────────────
  static const String googleClientId =
      '445835744041-sst8cp392ski2jtbkno6p16438kq8r0d.apps.googleusercontent.com';
}
