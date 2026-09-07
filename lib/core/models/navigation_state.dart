import 'dart:convert';
import 'ride_state.dart';
import 'navigation_mode.dart';

/// Central single-source-of-truth navigation telemetry for JustRide.
///
/// Every navigation-related UI and BLE packet is driven exclusively from this
/// object. No other component may maintain its own copy of navigation data.
class NavigationState {
  final double currentLatitude;
  final double currentLongitude;

  /// Live speed from GPS/location service. Always 0.0 when stationary.
  /// Never a fabricated or demo value.
  final double speedKmh;
  final double heading;

  final double remainingDistanceMeters;
  final int remainingDurationSeconds;

  /// Current maneuver instruction (the turn the rider must make now / soon).
  final String maneuver;
  final String maneuverText;
  final double maneuverDistanceMeters;

  /// The *next* maneuver after the current one (lookahead preview).
  final String nextManeuver;
  final String nextManeuverText;

  final int maneuverId;
  final String maneuverState;

  final bool rerouting;
  final bool gpsAvailable;
  final bool bleConnected;

  /// Strongly-typed ride state — primary state indicator.
  final RideState rideState;

  /// Active navigation operating mode.
  final NavigationMode navigationMode;

  /// Legacy string for BLE packet backward compatibility.
  String get navigationStatus => rideState.legacyStatus;

  const NavigationState({
    this.currentLatitude = 0.0,
    this.currentLongitude = 0.0,
    this.speedKmh = 0.0,
    this.heading = 0.0,
    this.remainingDistanceMeters = 0.0,
    this.remainingDurationSeconds = 0,
    this.maneuver = 'STRAIGHT',
    this.maneuverText = '',
    this.maneuverDistanceMeters = 0.0,
    this.nextManeuver = 'STRAIGHT',
    this.nextManeuverText = '',
    this.maneuverId = 0,
    this.maneuverState = 'NONE',
    this.rerouting = false,
    this.gpsAvailable = true,
    this.bleConnected = false,
    RideState? rideState,
    this.navigationMode = NavigationMode.route,
    String? navigationStatus,
  }) : rideState = rideState ??
            (navigationStatus == 'NAVIGATING'
                ? RideState.navigating
                : navigationStatus == 'REROUTING'
                    ? RideState.rerouting
                    : navigationStatus == 'PAUSED'
                        ? RideState.paused
                        : navigationStatus == 'ARRIVED'
                            ? RideState.arrived
                            : navigationStatus == 'GPS_LOST'
                                ? RideState.gpsLost
                                : navigationStatus == 'PREVIEW'
                                    ? RideState.routePreview
                                    : navigationStatus == 'STARTING'
                                        ? RideState.starting
                                        : RideState.idle);

  /// Factory for idle / home state (no active navigation).
  factory NavigationState.idle({bool bleConnected = false}) {
    return NavigationState(
      speedKmh: 0,
      maneuverText: 'Ready to Navigate',
      bleConnected: bleConnected,
      rideState: RideState.idle,
    );
  }

  /// Factory for GPS LOST state — preserves position but marks data invalid.
  factory NavigationState.gpsLost(NavigationState previous) {
    return NavigationState(
      currentLatitude: previous.currentLatitude,
      currentLongitude: previous.currentLongitude,
      speedKmh: 0.0, // Never show stale speed when GPS is lost
      heading: previous.heading,
      remainingDistanceMeters: previous.remainingDistanceMeters,
      remainingDurationSeconds: previous.remainingDurationSeconds,
      maneuver: previous.maneuver,
      maneuverText: previous.maneuverText,
      maneuverDistanceMeters: previous.maneuverDistanceMeters,
      nextManeuver: previous.nextManeuver,
      nextManeuverText: previous.nextManeuverText,
      maneuverId: previous.maneuverId,
      maneuverState: previous.maneuverState,
      rerouting: previous.rerouting,
      gpsAvailable: false,
      bleConnected: previous.bleConnected,
      rideState: RideState.gpsLost,
    );
  }

  // ── Formatted getters ─────────────────────────────────────────────────────

  /// Human-readable remaining distance (e.g. "4.2 km" or "850 m")
  String get remainingDistanceFormatted {
    if (remainingDistanceMeters >= 1000) {
      final km = remainingDistanceMeters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
    return '${remainingDistanceMeters.round()} m';
  }

  /// Human-readable distance to next maneuver (e.g. "250 m" or "1.5 km")
  String get maneuverDistanceFormatted {
    if (maneuverDistanceMeters >= 1000) {
      final km = maneuverDistanceMeters / 1000.0;
      return '${km.toStringAsFixed(1)} km';
    }
    return '${maneuverDistanceMeters.round()} m';
  }

  /// Human-readable ETA (e.g. "12 min" or "1 hr 15 min")
  String get remainingDurationFormatted {
    if (remainingDurationSeconds <= 60) return '1 min';
    final mins = (remainingDurationSeconds / 60).round();
    if (mins < 60) return '$mins min';
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    return remMins == 0 ? '$hours hr' : '$hours hr $remMins min';
  }

  /// Formatted arrival clock time (e.g. "12:45 PM")
  String get arrivalTimeFormatted {
    final eta = DateTime.now().add(Duration(seconds: remainingDurationSeconds));
    final hour = eta.hour == 0
        ? 12
        : eta.hour > 12
            ? eta.hour - 12
            : eta.hour;
    final minute = eta.minute.toString().padLeft(2, '0');
    final period = eta.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  /// Whether the rider is currently stationary (stopped, navigation still active).
  bool get isStationary => rideState == RideState.stationary;

  /// Speed display string — returns "--" when GPS is unavailable.
  String get speedDisplay {
    if (!gpsAvailable) return '--';
    return speedKmh.round().toString();
  }

  // ── copyWith ──────────────────────────────────────────────────────────────

  NavigationState copyWith({
    double? currentLatitude,
    double? currentLongitude,
    double? speedKmh,
    double? heading,
    double? remainingDistanceMeters,
    int? remainingDurationSeconds,
    String? maneuver,
    String? maneuverText,
    double? maneuverDistanceMeters,
    String? nextManeuver,
    String? nextManeuverText,
    int? maneuverId,
    String? maneuverState,
    bool? rerouting,
    bool? gpsAvailable,
    bool? bleConnected,
    RideState? rideState,
    NavigationMode? navigationMode,
  }) {
    return NavigationState(
      currentLatitude: currentLatitude ?? this.currentLatitude,
      currentLongitude: currentLongitude ?? this.currentLongitude,
      speedKmh: speedKmh ?? this.speedKmh,
      heading: heading ?? this.heading,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
      remainingDurationSeconds:
          remainingDurationSeconds ?? this.remainingDurationSeconds,
      maneuver: maneuver ?? this.maneuver,
      maneuverText: maneuverText ?? this.maneuverText,
      maneuverDistanceMeters:
          maneuverDistanceMeters ?? this.maneuverDistanceMeters,
      nextManeuver: nextManeuver ?? this.nextManeuver,
      nextManeuverText: nextManeuverText ?? this.nextManeuverText,
      maneuverId: maneuverId ?? this.maneuverId,
      maneuverState: maneuverState ?? this.maneuverState,
      rerouting: rerouting ?? this.rerouting,
      gpsAvailable: gpsAvailable ?? this.gpsAvailable,
      bleConnected: bleConnected ?? this.bleConnected,
      rideState: rideState ?? this.rideState,
      navigationMode: navigationMode ?? this.navigationMode,
    );
  }

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'currentLatitude': currentLatitude,
      'currentLongitude': currentLongitude,
      'speedKmh': speedKmh,
      'heading': heading,
      'remainingDistanceMeters': remainingDistanceMeters,
      'remainingDurationSeconds': remainingDurationSeconds,
      'maneuver': maneuver,
      'maneuverText': maneuverText,
      'maneuverDistanceMeters': maneuverDistanceMeters,
      'nextManeuver': nextManeuver,
      'nextManeuverText': nextManeuverText,
      'maneuverId': maneuverId,
      'maneuverState': maneuverState,
      'rerouting': rerouting,
      'gpsAvailable': gpsAvailable,
      'bleConnected': bleConnected,
      'navigationStatus': navigationStatus,
    };
  }

  factory NavigationState.fromMap(Map<String, dynamic> map) {
    return NavigationState(
      currentLatitude: (map['currentLatitude'] as num?)?.toDouble() ?? 0.0,
      currentLongitude: (map['currentLongitude'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (map['speedKmh'] as num?)?.toDouble() ?? 0.0,
      heading: (map['heading'] as num?)?.toDouble() ?? 0.0,
      remainingDistanceMeters:
          (map['remainingDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      remainingDurationSeconds:
          (map['remainingDurationSeconds'] as num?)?.toInt() ?? 0,
      maneuver: map['maneuver'] as String? ?? 'STRAIGHT',
      maneuverText: map['maneuverText'] as String? ?? '',
      maneuverDistanceMeters:
          (map['maneuverDistanceMeters'] as num?)?.toDouble() ?? 0.0,
      nextManeuver: map['nextManeuver'] as String? ?? 'STRAIGHT',
      nextManeuverText: map['nextManeuverText'] as String? ?? '',
      maneuverId: (map['maneuverId'] as num?)?.toInt() ?? 0,
      maneuverState: map['maneuverState'] as String? ?? 'NONE',
      rerouting: map['rerouting'] as bool? ?? false,
      gpsAvailable: map['gpsAvailable'] as bool? ?? true,
      bleConnected: map['bleConnected'] as bool? ?? false,
      rideState: RideState.idle,
    );
  }

  String toJson() => jsonEncode(toMap());
}
