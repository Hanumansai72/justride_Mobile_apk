import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/destination.dart';
import 'ride_history_service.dart';

class SavedCommute {
  const SavedCommute({required this.destination, this.start});

  final Destination destination;
  final Destination? start;

  String get title => destination.displayTitle;

  // Keep rider-visible labels and place IDs. Resolve fresh routes at opening.
  static Map<String, dynamic> _place(Destination place) => {
        'name': place.displayTitle,
        'address': place.address,
        'placeId': place.placeId,
        'latitude': 0.0,
        'longitude': 0.0,
      };

  String toJson() => jsonEncode({
        'destination': _place(destination),
        if (start != null) 'start': _place(start!),
      });

  factory SavedCommute.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return SavedCommute(
      destination:
          Destination.fromMap(map['destination'] as Map<String, dynamic>),
      start: map['start'] is Map<String, dynamic>
          ? Destination.fromMap(map['start'] as Map<String, dynamic>)
          : null,
    );
  }
}

class RidePlanningStore {
  static Future<String> owner() async =>
      await RideHistoryService.instance.currentUserId() ?? 'guest';

  static Future<List<SavedCommute>> commutes(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final result = <SavedCommute>[];
    for (final record
        in prefs.getStringList('saved_commutes_$owner') ?? const <String>[]) {
      try {
        result.add(SavedCommute.fromJson(record));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return result;
  }

  static Future<bool> saveCommutes(
      String owner, List<SavedCommute> commutes) async {
    final prefs = await SharedPreferences.getInstance();
    if (owner != await RidePlanningStore.owner()) return false;
    return prefs.setStringList('saved_commutes_$owner',
        commutes.map((item) => item.toJson()).toList());
  }
}
