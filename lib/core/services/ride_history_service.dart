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

  Future<List<NavigationSession>> localHistory(String owner,
      {int? recentLimit}) async {
    if (kIsWeb) return [];
    final prefs = await SharedPreferences.getInstance();
    final rides = <NavigationSession>[];
    final ids = prefs.getStringList('local_rides_$owner') ?? const <String>[];
    for (final id
        in recentLimit == null ? ids : ids.reversed.take(recentLimit)) {
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
  String? _totalRequestToken;
  int _rideRevision = 0;
  static const _cloudDistanceKey = ':cloud';
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

  static bool _countedRide(NavigationSession ride) => ride.isMeaningfulRide;

  /// Refresh the total without downloading full ride records.
  Future<double> refreshTotalDistance() {
    final owner = _accountOwner;
    final token = _api.token;
    if (_totalRequest != null &&
        _totalRequestOwner == owner &&
        _totalRequestToken == token) return _totalRequest!;
    _totalRequestOwner = owner;
    _totalRequestToken = token;
    late Future<double> request;
    request = _refreshTotalDistance(owner, token).whenComplete(() {
      if (identical(_totalRequest, request)) _totalRequest = null;
    });
    _totalRequest = request;
    return request;
  }

  Future<double> _refreshTotalDistance(String owner, String? token) async {
    bool current() => owner == _accountOwner && token == _api.token;
    if (_totalOwner != owner) totalDistanceMeters.value = null;
    final cached = await _cachedDistances(owner);
    if (!current()) return 0;
    final cachedTotal =
        cached.values.fold<double>(0, (sum, value) => sum + value);
    if (cached.isNotEmpty) {
      _totalOwner = owner;
      totalDistanceMeters.value = cachedTotal;
    }
    if (owner == 'guest' || token == null) return _refreshLegacyTotal(owner);

    final prefs = await SharedPreferences.getInstance();
    if (!current()) return 0;
    final revision = _rideRevision;
    final pending = <String, double>{};
    for (final json
        in prefs.getStringList('pending_rides_$owner') ?? const <String>[]) {
      try {
        final ride = NavigationSession.fromJson(json);
        if (_countedRide(ride)) pending[ride.sessionId] = ride.distanceMeters;
      } catch (_) {
        // A damaged local entry should not hide the rest of the total.
      }
    }
    if (pending.length > 100) return _refreshLegacyTotal(owner);

    final result = await _api.post<double>('/rides/summary',
        body: {'pendingSessionIds': pending.keys.toList()},
        headers: {'Authorization': 'Bearer $token'},
        fromJson: (json) => (json['distanceMeters'] as num).toDouble());
    if (!current()) return 0;
    if (result.statusCode == 404) return _refreshLegacyTotal(owner);
    final cloud = result.data;
    if (!result.success || cloud == null || !cloud.isFinite || cloud < 0) {
      return totalDistanceMeters.value ?? cachedTotal;
    }

    // The saved snapshot remains usable offline. A newer ride invalidates the
    // response, so it cannot replace a total already updated by a local save.
    final snapshot = {_cloudDistanceKey: cloud, ...pending};
    final total = snapshot.values.fold<double>(0, (sum, value) => sum + value);
    final write = _totalWrites.catchError((Object _) {}).then((_) async {
      if (!current() || revision != _rideRevision) return;
      await prefs.setString('ride_distances_$owner', jsonEncode(snapshot));
      if (current() && revision == _rideRevision) {
        _totalOwner = owner;
        totalDistanceMeters.value = total;
      }
    });
    _totalWrites = write;
    await write;
    return current() ? totalDistanceMeters.value ?? cachedTotal : 0;
  }

  Future<double> _refreshLegacyTotal(String owner) async {
    if (_totalOwner != owner) totalDistanceMeters.value = null;
    var distances = await _cachedDistances(owner);
    if (distances.containsKey(_cloudDistanceKey)) {
      return distances.values.fold<double>(0, (sum, value) => sum + value);
    }
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
    final id = (user?['_id'] ?? user?['id'])?.toString();
    return id != null && id.isNotEmpty ? id : null;
  }

  Future<void> _run(Future<void> Function() operation) {
    _serial = _serial.then((_) => operation()).catchError((Object error) {
      storageError.value =
          'Could not save the latest journey data. Check available phone storage.';
    });
    return _serial;
  }

  Future<void> save(NavigationSession ride, String owner) => _run(() async {
        final prefs = await SharedPreferences.getInstance();
        var alreadySaved = false;
        if (!kIsWeb) {
          final file = await _file(owner, ride.sessionId, 'json');
          await file.writeAsString(ride.toJson(), flush: true);
          final ids = prefs.getStringList('local_rides_$owner') ?? [];
          alreadySaved = ids.contains(ride.sessionId);
          if (!alreadySaved) {
            ids.add(ride.sessionId);
            await prefs.setStringList('local_rides_$owner', ids);
          }
        }
        if (owner != 'guest') {
          final key = 'pending_rides_$owner';
          final pending = prefs.getStringList(key) ?? [];
          if (!pending.any((json) =>
              NavigationSession.fromJson(json).sessionId == ride.sessionId)) {
            pending.add(ride.toJson());
            await prefs.setStringList(key, pending);
          }
        }
        _rideRevision++;
        if (!alreadySaved && _countedRide(ride)) {
          await _storeDistances(owner, {ride.sessionId: ride.distanceMeters});
        }
        if (!kIsWeb) changed.value++;
        if (owner == 'guest') return;
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
    bool hasDistance(NavigationSession ride) => ride.isMeaningfulRide;
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
