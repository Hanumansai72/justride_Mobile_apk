import 'package:geolocator/geolocator.dart';

/// DTO representing a high-frequency simulation packet broadcast from
/// the JustRide Web Ride Simulator over WebSocket.
class SimulatedLocationPacket {
  final String type;
  final int timestamp;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double bearing;
  final double accuracy;
  final double routeProgress;
  final double distanceRemaining;
  final String maneuver;
  final double maneuverDistance;
  final String nextRoad;
  final bool destinationReached;
  final bool gpsAvailable;
  final String simStatus;
  final int maneuverId;
  final String maneuverState;
  final int nextManeuverId;
  final String nextManeuverType;
  final double outgoingRoadHeading;

  const SimulatedLocationPacket({
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.bearing,
    required this.accuracy,
    required this.routeProgress,
    required this.distanceRemaining,
    required this.maneuver,
    required this.maneuverDistance,
    required this.nextRoad,
    required this.destinationReached,
    required this.gpsAvailable,
    required this.simStatus,
    this.maneuverId = 0,
    this.maneuverState = 'NONE',
    this.nextManeuverId = 0,
    this.nextManeuverType = 'NONE',
    this.outgoingRoadHeading = 0.0,
  });

  factory SimulatedLocationPacket.fromJson(Map<String, dynamic> json) {
    return SimulatedLocationPacket(
      type: json['type'] as String? ?? 'SIM_LOCATION',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      speedKmh: (json['speedKmh'] as num?)?.toDouble() ?? 0.0,
      bearing: (json['bearing'] as num?)?.toDouble() ?? 0.0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 2.0,
      routeProgress: (json['routeProgress'] as num?)?.toDouble() ?? 0.0,
      distanceRemaining: (json['distanceRemaining'] as num?)?.toDouble() ?? 0.0,
      maneuver: json['maneuver'] as String? ?? 'STRAIGHT',
      maneuverDistance: (json['maneuverDistance'] as num?)?.toDouble() ?? 0.0,
      nextRoad: json['nextRoad'] as String? ?? '',
      destinationReached: json['destinationReached'] as bool? ?? false,
      gpsAvailable: json['gpsAvailable'] as bool? ?? true,
      simStatus: json['simStatus'] as String? ?? 'RUNNING',
      maneuverId: (json['maneuverId'] as num?)?.toInt() ?? 0,
      maneuverState: json['maneuverState'] as String? ?? 'NONE',
      nextManeuverId: (json['nextManeuverId'] as num?)?.toInt() ?? 0,
      nextManeuverType: json['nextManeuverType'] as String? ?? 'NONE',
      outgoingRoadHeading: (json['outgoingRoadHeading'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Converts the simulator telemetry into a standard Geolocator [Position]
  /// so that the Navigation Engine treats it seamlessly like real GPS.
  Position toPosition() {
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
      accuracy: accuracy,
      altitude: 500.0,
      altitudeAccuracy: 5.0,
      heading: bearing,
      headingAccuracy: 5.0,
      speed: speedKmh / 3.6, // km/h to m/s
      speedAccuracy: 0.5,
    );
  }
}
