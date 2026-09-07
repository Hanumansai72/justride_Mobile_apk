/// Defines the three navigation operating modes supported by the JustRide HUD.
enum NavigationMode {
  /// Full turn-by-turn route guidance with maneuver instructions.
  route,

  /// Compass mode: shows bearing and straight-line distance to destination.
  /// No turn-by-turn steps — just point towards the destination.
  compass,

  /// Ride tracking mode: records speed, distance, and elapsed time.
  /// No destination required; useful for free-ride logging.
  tracking,
}
