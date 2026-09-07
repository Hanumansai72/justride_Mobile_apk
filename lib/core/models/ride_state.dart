/// All possible states of a JustRide navigation session.
///
/// This enum replaces the loose `navigationStatus` String used previously,
/// providing compile-time safety and exhaustive pattern matching across
/// the UI, BLE service, and NavigationService.
enum RideState {
  /// App is idle, no destination selected.
  idle,

  /// Destination has been received (e.g. via share) but not confirmed.
  destinationSelected,

  /// Route preview is shown; user has not yet pressed START RIDE.
  routePreview,

  /// Route preview loaded; device ready for START RIDE action.
  readyToStart,

  /// START RIDE pressed; acquiring GPS fix and setting up navigation.
  starting,

  /// Active turn-by-turn navigation in progress.
  navigating,

  /// Rider has stopped (speed < 2.5 km/h) but navigation session is still
  /// alive. Maneuver instructions are preserved; distance does not change.
  stationary,

  /// Rider has deviated from route; recalculating.
  rerouting,

  /// Navigation temporarily paused.
  paused,

  /// Rider has reached the destination.
  arrived,

  /// User or system cancelled navigation.
  cancelled,

  /// GPS signal lost during active navigation.
  gpsLost,

  /// BLE device disconnected (navigation continues on phone).
  bleDisconnected,

  /// Navigation engine encountered an error.
  navigationError;

  /// Maps to the legacy `navigationStatus` String for backward compatibility
  /// with BLE packet serialization.
  String get legacyStatus {
    switch (this) {
      case RideState.idle:
        return 'WAITING';
      case RideState.destinationSelected:
      case RideState.routePreview:
      case RideState.readyToStart:
        return 'PREVIEW';
      case RideState.starting:
        return 'STARTING';
      case RideState.navigating:
        return 'NAVIGATING';
      case RideState.stationary:
        return 'STATIONARY';
      case RideState.rerouting:
        return 'REROUTING';
      case RideState.paused:
        return 'PAUSED';
      case RideState.arrived:
        return 'ARRIVED';
      case RideState.cancelled:
        return 'CANCELLED';
      case RideState.gpsLost:
        return 'GPS_LOST';
      case RideState.bleDisconnected:
        return 'NAVIGATING'; // Phone continues navigating
      case RideState.navigationError:
        return 'ERROR';
    }
  }

  /// Whether the ride is currently actively navigating (not idle, not arrived).
  bool get isActive =>
      this == RideState.navigating ||
      this == RideState.stationary ||
      this == RideState.rerouting ||
      this == RideState.paused ||
      this == RideState.gpsLost ||
      this == RideState.bleDisconnected;

  /// Whether navigation data should be transmitted to ESP32.
  bool get shouldSendToBle =>
      this == RideState.navigating ||
      this == RideState.stationary ||
      this == RideState.rerouting ||
      this == RideState.gpsLost;
}
