import 'dart:convert';
import 'destination.dart';

/// Stores per-ride telemetry for optional ride history tracking.
///
/// Collected during an active navigation session and saved when the ride ends.
/// Raw high-frequency GPS coordinates are NOT stored (as per master prompt §30).
class NavigationSession {
  final String sessionId;
  final DateTime startTime;
  final DateTime? endTime;
  final Destination? origin;
  final Destination? destination;
  final double distanceMeters;
  final int durationSeconds;
  final double averageSpeedKmh;
  final double maxSpeedKmh;

  const NavigationSession({
    required this.sessionId,
    required this.startTime,
    this.endTime,
    this.origin,
    this.destination,
    this.distanceMeters = 0.0,
    this.durationSeconds = 0,
    this.averageSpeedKmh = 0.0,
    this.maxSpeedKmh = 0.0,
  });

  /// Creates an in-progress session with start metadata.
  factory NavigationSession.start({
    required Destination? origin,
    required Destination? destination,
  }) {
    return NavigationSession(
      sessionId: 'jr_${DateTime.now().millisecondsSinceEpoch}',
      startTime: DateTime.now(),
      origin: origin,
      destination: destination,
    );
  }

  /// Returns a completed session from the in-progress one.
  NavigationSession complete({
    required double distanceMeters,
    required double averageSpeedKmh,
    required double maxSpeedKmh,
  }) {
    final now = DateTime.now();
    final secs = now.difference(startTime).inSeconds;
    return NavigationSession(
      sessionId: sessionId,
      startTime: startTime,
      endTime: now,
      origin: origin,
      destination: destination,
      distanceMeters: distanceMeters,
      durationSeconds: secs,
      averageSpeedKmh: averageSpeedKmh,
      maxSpeedKmh: maxSpeedKmh,
    );
  }

  /// Distance in kilometres.
  double get distanceKm => distanceMeters / 1000.0;

  /// Whether this session has completed.
  bool get isCompleted => endTime != null;

  /// Formatted summary string for display / logging.
  String get summary {
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    final mins = (durationSeconds / 60).round();
    return '$km km in $mins min · avg ${averageSpeedKmh.round()} km/h · max ${maxSpeedKmh.round()} km/h';
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'origin': origin?.toMap(),
      'destination': destination?.toMap(),
      'distanceMeters': distanceMeters,
      'durationSeconds': durationSeconds,
      'averageSpeedKmh': averageSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
    };
  }

  factory NavigationSession.fromMap(Map<String, dynamic> map) {
    return NavigationSession(
      sessionId: map['sessionId'] as String,
      startTime: DateTime.parse(map['startTime'] as String),
      endTime:
          map['endTime'] != null ? DateTime.parse(map['endTime'] as String) : null,
      origin: map['origin'] != null
          ? Destination.fromMap(map['origin'] as Map<String, dynamic>)
          : null,
      destination: map['destination'] != null
          ? Destination.fromMap(map['destination'] as Map<String, dynamic>)
          : null,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      averageSpeedKmh: (map['averageSpeedKmh'] as num?)?.toDouble() ?? 0.0,
      maxSpeedKmh: (map['maxSpeedKmh'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory NavigationSession.fromJson(String source) =>
      NavigationSession.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
