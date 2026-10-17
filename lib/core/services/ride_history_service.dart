import 'dart:convert';
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
  RideHistoryService._();
  static final instance = RideHistoryService._();
  final _api = ApiClient.instance;
  final changed = ValueNotifier<int>(0);
  Future<void> _serial = Future.value();

  Future<String?> currentUserId() async {
    if (!_api.isAuthenticated) return null;
    final user = await _api.getSavedUserData();
    final id = user?['_id']?.toString();
    return id != null && id.isNotEmpty ? id : null;
  }

  Future<void> _run(Future<void> Function() operation) {
    _serial = _serial.then((_) => operation()).catchError((Object error) {
      debugPrint(
          '[RideHistory] Could not sync ride history: ${error.runtimeType}');
    });
    return _serial;
  }

  Future<void> save(NavigationSession ride, String owner) => _run(() async {
        final prefs = await SharedPreferences.getInstance();
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
          {int page = 1, int limit = 10}) =>
      _api.get<RideHistoryPage>('/rides?page=$page&limit=$limit',
          fromJson: (json) =>
              RideHistoryPage.fromMap(Map<String, dynamic>.from(json as Map)));
}
