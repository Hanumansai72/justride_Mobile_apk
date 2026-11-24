/// Route preferences are advisory and do not guarantee avoidance.
class BikeRoutePreferences {
  const BikeRoutePreferences({
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.avoidFerries = false,
  });

  final bool avoidTolls;
  final bool avoidHighways;
  final bool avoidFerries;

  bool get hasAvoidances => avoidTolls || avoidHighways || avoidFerries;

  Map<String, bool> toMap() => {
        'avoidTolls': avoidTolls,
        'avoidHighways': avoidHighways,
        'avoidFerries': avoidFerries,
      };

  // SharedPreferences representation for defaults and the active ride.
  int get flags =>
      (avoidTolls ? 1 : 0) | (avoidHighways ? 2 : 0) | (avoidFerries ? 4 : 0);

  factory BikeRoutePreferences.fromFlags(int flags) => BikeRoutePreferences(
        avoidTolls: flags & 1 != 0,
        avoidHighways: flags & 2 != 0,
        avoidFerries: flags & 4 != 0,
      );
}
