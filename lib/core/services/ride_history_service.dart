import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/navigation_session.dart';
import '../network/api_client.dart';

class RideHistoryPage {
  final List<NavigationSession> items;
  final int total;
  final int page;
  final int limit;
  const RideHistoryPage(this.items, this.total, this.page, this.limit);
  bool get hasMore => page * limit < total;

  factory RideHistoryPage.fromMap(Map<String, dynamic> map) => RideHistoryPage(
        (map['items'] as List)
            .map((item) => NavigationSession.fromMap(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
        map['total'] as int,
        map['page'] as int,
        map['limit'] as int,
      );
}

/// Backend owns displayed history. Failed uploads stay on this user's device
/// until the next history/home refresh; a stable session ID makes retries safe.
class RideHistoryService {
  RideHistoryService._() : _directory = null;
  @visibleForTesting
  RideHistoryService.testing(Directory directory) : _directory = directory;
  final Directory? _directory;
  final storageError = ValueNotifier<String?>(null);

  Future<File> _file(String owner, String id, String extension) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(owner) ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,160}$').hasMatch(id))
      throw ArgumentError('Invalid journey identifier');
    final root = _directory ?? await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/journeys/$owner');
    await dir.create(recursive: true);
    return File('${dir.path}/$id.$extension');
  }

  Future<void> appendTrail(
          String owner, String id, List<Map<String, dynamic>> points) =>
      _run(() async {
        if (kIsWeb || points.isEmpty) return;
        final file = await _file(owner, id, 'jsonl');
        await file.writeAsString('${points.map(jsonEncode).join("\n")}\n',
            mode: FileMode.append, flush: true);
      });

  Future<List<Map<String, dynamic>>> readTrail(String owner, String id) async {
    if (kIsWeb) return [];
    final file = await _file(owner, id, 'jsonl');
    if (!await file.exists()) return [];
    final points = <Map<String, dynamic>>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      try {
        points.add(Map<String, dynamic>.from(jsonDecode(line) as Map));
      } catch (_) {/* A power loss can leave one incomplete final line. */}
    }
    return points;
  }

  Future<List<NavigationSession>> localHistory(String owner) async {
    if (kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    final rides = <NavigationSession>[];
    for (final id in prefs.getStringList('local_rides_$owner') ?? <String>[]) {
      try {
        final file = await _file(owner, id, 'json');
        if (await file.exists())
          rides.add(NavigationSession.fromJson(await file.readAsString()));
      } catch (_) {
        /* Keep other rides available if one file was interrupted. */
      }
    }
    rides.sort((a, b) => b.startTime.compareTo(a.startTime));
    return rides;
  }

  static final instance = RideHistoryService._();
  final _api = ApiClient.instance;
  final changed = ValueNotifier<int>(0);
  final totalDistanceMeters = ValueNotifier<double?>(null);
  Future<void> _totalWrites = Future<void>.value();
  String? _totalOwner, _totalRequestOwner;
  Future<double>? _totalRequest;
  String get _accountOwner => _api.isAuthenticated
      ? (_api.savedUser.value?['_id'] ?? _api.savedUser.value?['id'] ?? 'guest')
          .toString()
      : 'guest';
  bool get hasCurrentTotal =>
      _totalOwner == _accountOwner && totalDistanceMeters.value != null;

  Future<Map<String, double>> _cachedDistances(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw =
          jsonDecode(prefs.getString('ride_distances_$owner') ?? '{}') as Map;
      return raw.map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _storeDistances(String owner, Map<String, double> distances) {
    return _totalWrites =
        _totalWrites.catchError((Object _) {}).then((_) async {
      final merged = {...await _cachedDistances(owner), ...distances};
      await (await SharedPreferences.getInstance())
          .setString('ride_distances_$owner', jsonEncode(merged));
      if (owner == _accountOwner) {
        _totalOwner = owner;
        totalDistanceMeters.value =
            merged.values.fold<double>(0, (sum, value) => sum + value);
      }
    });
  }

  static bool _countedRide(NavigationSession ride) =>
      ride.endTime != null &&
      (ride.status == 'completed' || ride.status == 'stopped') &&
      ride.distanceMeters.isFinite &&
      ride.distanceMeters >= 0;

  /// All pages, keyed by session ID: synced and local copies count only once.
  Future<double> refreshTotalDistance() {
    final owner = _accountOwner;
    if (_totalRequest != null && _totalRequestOwner == owner)
      return _totalRequest!;
    _totalRequestOwner = owner;
    late Future<double> request;
    request = _refreshTotalDistance(owner).whenComplete(() {
      if (identical(_totalRequest, request)) _totalRequest = null;
    });
    _totalRequest = request;
    return request;
  }

  Future<double> _refreshTotalDistance(String owner) async {
    if (_totalOwner != owner) totalDistanceMeters.value = null;
    var distances = await _cachedDistances(owner);
    for (final ride in await localHistory(owner)) {
      if (_countedRide(ride)) distances[ride.sessionId] = ride.distanceMeters;
    }
    if (owner != _accountOwner) return 0;
    await _storeDistances(owner, distances);
    if (owner != 'guest') {
      final remoteDistances = <String, double>{};
      var page = 1;
      while (owner == _accountOwner) {
        final response = await _api.get<RideHistoryPage>(
            '/rides?page=$page&limit=100',
            fromJson: (json) => RideHistoryPage.fromMap(
                Map<String, dynamic>.from(json as Map)));
        if (owner != _accountOwner) return 0;
        final data = response.data;
        if (!response.success || data == null) break;
        for (final ride in data.items) {
          if (_countedRide(ride))
            remoteDistances[ride.sessionId] = ride.distanceMeters;
        }
        if (!data.hasMore) {
          distances = remoteDistances;
          break;
        }
        if (data.items.isEmpty) break;
        page++;
      }
      // Include a ride saved while the network request was running.
      for (final ride in await localHistory(owner)) {
        if (_countedRide(ride)) distances[ride.sessionId] = ride.distanceMeters;
      }
      if (owner != _accountOwner) return 0;
      await _storeDistances(owner, distances);
    }
    return (await _cachedDistances(owner))
        .values
        .fold<double>(0, (sum, value) => sum + value);
  }

  Future<void> _serial = Future.value();

  Future<String?> currentUserId() async {
    if (!_api.isAuthenticated) return null;
    final user = await _api.getSavedUserData();
    final id = user?['_id']?.toString();
    return id != null && id.isNotEmpty ? id : null;
  }

  Future<void> _run(Future<void> Function() operation) {
    _serial = _serial.then((_) => operation()).catchError((Object error) {
      storageError.value =
          'Could not save the latest journey data. Check available phone storage.';
      debugPrint(
          '[RideHistory] Could not save/sync ride: ${error.runtimeType}');
    });
    return _serial;
  }

  Future<void> save(NavigationSession ride, String owner) => _run(() async {
        final prefs = await SharedPreferences.getInstance();
        if (!kIsWeb) {
          final file = await _file(owner, ride.sessionId, 'json');
          await file.writeAsString(ride.toJson(), flush: true);
          final ids = prefs.getStringList('local_rides_$owner') ?? [];
          if (!ids.contains(ride.sessionId)) {
            ids.add(ride.sessionId);
            await prefs.setStringList('local_rides_$owner', ids);
          }
          final distances = await _cachedDistances(owner);
          if (_countedRide(ride))
            distances[ride.sessionId] = ride.distanceMeters;
          await _storeDistances(owner, distances);
          changed.value++;
        }
        if (owner == 'guest') return;
        final key = 'pending_rides_$owner';
        final pending = prefs.getStringList(key) ?? [];
        if (!pending.any((json) =>
            NavigationSession.fromJson(json).sessionId == ride.sessionId)) {
          pending.add(ride.toJson());
          await prefs.setStringList(key, pending);
        }
        await _flush(owner);
      });

  Future<void> syncPending() => _run(() async {
        final owner = await currentUserId();
        if (owner != null) await _flush(owner);
      });

  Future<void> _flush(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending_rides_$owner';
    final pending = prefs.getStringList(key) ?? [];
    while (pending.isNotEmpty) {
      final token = _api.token;
      if (token == null ||
          await currentUserId() != owner ||
          _api.token != token) {
        break;
      }
      final response = await _api.post<void>('/rides',
          body: jsonDecode(pending.first),
          headers: {'Authorization': 'Bearer $token'});
      if (!response.success) break;
      pending.removeAt(0);
      await prefs.setStringList(key, pending);
      changed.value++;
    }
  }

  Future<ApiResponse<RideHistoryPage>> getPage(
      {int page = 1, int limit = 10}) async {
    final owner = await currentUserId() ?? 'guest';
    bool hasDistance(NavigationSession ride) =>
        ride.distanceMeters.isFinite && ride.distanceMeters > 0;
    final local = (await localHistory(owner)).where(hasDistance).toList();
    RideHistoryPage? data;
    if (owner != 'guest') {
      var nextPage = page;
      while (true) {
        final response = await _api.get<RideHistoryPage>(
            '/rides?page=$nextPage&limit=$limit',
            fromJson: (json) => RideHistoryPage.fromMap(
                Map<String, dynamic>.from(json as Map)));
        if (owner != (await currentUserId() ?? 'guest')) {
          return ApiResponse.error('Account changed. Refresh ride history.');
        }
        if (!response.success || response.data == null) break;
        data = response.data!;
        // Skip empty visible pages so zero-distance rides cannot hide older rides.
        if (data.items.any(hasDistance) ||
            !data.hasMore ||
            data.items.isEmpty) {
          break;
        }
        nextPage = data.page + 1;
      }
    }
    if (owner != (await currentUserId() ?? 'guest')) {
      return ApiResponse.error('Account changed. Refresh ride history.');
    }
    if (data != null) {
      final merged = {
        for (final ride in data.items.where(hasDistance)) ride.sessionId: ride
      };
      if (page == 1) {
        for (final ride in local) {
          merged[ride.sessionId] = ride;
        }
      }
      final items = merged.values.toList()
        ..sort((a, b) => b.startTime.compareTo(a.startTime));
      return ApiResponse.success(
          data: RideHistoryPage(items, data.total, data.page, data.limit));
    }
    return ApiResponse.success(
        data: RideHistoryPage(
            local.skip((page - 1) * limit).take(limit).toList(),
            local.length,
            page,
            limit),
        message: 'Saved on this phone');
  }
}
