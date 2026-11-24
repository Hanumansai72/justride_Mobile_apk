import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/destination.dart';
import '../models/navigation_session.dart';
import '../utils/off_route_detector.dart';
import 'google_maps_service.dart';
import 'ride_planning_store.dart';

class OfflineTouringPack {
  const OfflineTouringPack._(this.id, this.title, this.points, this.seconds);
  static const provider = 'recorded-offline';
  final String id;
  final String title;
  final List<LatLng> points;
  final int seconds;

  Destination get destination => Destination(
      name: title,
      latitude: points.last.latitude,
      longitude: points.last.longitude);

  double get distanceMeters {
    var sum = 0.0;
    for (var i = 1; i < points.length; i++) {
      sum += _distance(points[i - 1], points[i]);
    }
    return sum;
  }

  bool canStartAt(LatLng point, {required bool resuming}) => resuming
      ? OffRouteDetector.distanceToRouteMeters(point, points) <= 35
      : _distance(point, points.first) <= 50;

  NavigationRoute toRoute() {
    final distance = distanceMeters;
    return NavigationRoute(
      provider: provider,
      totalDistanceMeters: distance,
      totalDurationSeconds: seconds,
      polylinePoints: points,
      steps: [
        RouteStep(
          startLocation: points.first,
          endLocation: points.last,
          distanceMeters: distance,
          durationSeconds: seconds,
          maneuver: 'STRAIGHT',
          instruction: 'Follow the recorded track',
          streetName: '',
          points: points,
        ),
      ],
    );
  }

  static bool validId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

  static double _distance(LatLng a, LatLng b) => Geolocator.distanceBetween(
      a.latitude, a.longitude, b.latitude, b.longitude);

  factory OfflineTouringPack.fromTrail(
      NavigationSession ride, List<Map<String, dynamic>> trail) {
    if (trail.length < 3 || trail.length > 7000 || !validId(ride.sessionId)) {
      throw const FormatException('This ride has no usable recorded track.');
    }
    final points = <LatLng>[];
    DateTime? previousTime;
    for (final fix in trail) {
      final lat = fix['lat'];
      final lon = fix['lon'];
      final time = DateTime.tryParse(fix['at']?.toString() ?? '');
      if (lat is! num ||
          lon is! num ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180 ||
          (lat == 0 && lon == 0) ||
          time == null) {
        throw const FormatException('This track contains an invalid GPS fix.');
      }
      final point = LatLng(lat.toDouble(), lon.toDouble());
      if (points.isNotEmpty &&
          (fix['segment'] == true ||
              !time.isAfter(previousTime!) ||
              time.difference(previousTime) > const Duration(seconds: 12) ||
              _distance(points.last, point) > 200)) {
        throw const FormatException(
            'This ride has GPS gaps and cannot be saved for offline guidance.');
      }
      points.add(point);
      previousTime = time;
    }
    final pack = OfflineTouringPack._(
        ride.sessionId,
        ride.destination?.displayTitle ?? 'Recorded ride',
        List.unmodifiable(points),
        ride.durationSeconds);
    if (pack.distanceMeters < 100) {
      throw const FormatException('The recorded track is too short.');
    }
    return pack;
  }

  String toJson() => jsonEncode({
        'version': 1,
        'id': id,
        'title': title,
        'seconds': seconds,
        'points': points.map((p) => [p.latitude, p.longitude]).toList(),
      });

  factory OfflineTouringPack.fromJson(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    final id = map['id'] as String;
    final points = map['points'] as List;
    final seconds = map['seconds'] as int;
    if (map['version'] != 1 ||
        !validId(id) ||
        points.length < 3 ||
        points.length > 7000 ||
        seconds < 0) {
      throw const FormatException('Invalid touring pack.');
    }
    final path = <LatLng>[];
    for (final item in points) {
      final point = item as List;
      if (point.length != 2) throw const FormatException('Invalid point.');
      final lat = (point[0] as num).toDouble();
      final lon = (point[1] as num).toDouble();
      if (!lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180 ||
          (lat == 0 && lon == 0)) {
        throw const FormatException('Invalid point.');
      }
      final location = LatLng(lat, lon);
      if (path.isNotEmpty && _distance(path.last, location) > 200) {
        throw const FormatException('This track contains a gap.');
      }
      path.add(location);
    }
    return OfflineTouringPack._(
        id, map['title'] as String, List.unmodifiable(path), seconds);
  }
}

class OfflineTouringService {
  static Future<Directory> _directory(String owner) async {
    if (!OfflineTouringPack.validId(owner)) throw ArgumentError.value(owner);
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/offline_tours/$owner');
  }

  static Future<void> save(String owner, OfflineTouringPack pack) async {
    if (owner != await RidePlanningStore.owner()) return;
    final dir = await _directory(owner);
    await dir.create(recursive: true);
    final file = File('${dir.path}/${pack.id}.json');
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(pack.toJson(), flush: true);
    await temp.rename(file.path);
  }

  static Future<OfflineTouringPack?> load(String owner, String id) async {
    if (!OfflineTouringPack.validId(id)) return null;
    final file = File('${(await _directory(owner)).path}/$id.json');
    if (!await file.exists()) return null;
    return OfflineTouringPack.fromJson(await file.readAsString());
  }

  static Future<List<OfflineTouringPack>> list(String owner) async {
    final dir = await _directory(owner);
    if (!await dir.exists()) return [];
    final packs = <OfflineTouringPack>[];
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        packs.add(OfflineTouringPack.fromJson(await file.readAsString()));
      } catch (_) {
        // An incomplete pack should not hide the others.
      }
    }
    packs.sort((a, b) => b.id.compareTo(a.id));
    return packs;
  }

  static Future<void> remove(String owner, String id) async {
    if (owner != await RidePlanningStore.owner() ||
        !OfflineTouringPack.validId(id)) return;
    final file = File('${(await _directory(owner)).path}/$id.json');
    if (await file.exists()) await file.delete();
  }
}
