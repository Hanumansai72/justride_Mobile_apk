import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../network/api_client.dart';

class RideSubscription {
  RideSubscription.fromJson(Map<String, dynamic> json)
      : premium = json['premium'] == true,
        premiumUntil = DateTime.tryParse(json['premiumUntil'] as String? ?? '');

  final bool premium;
  final DateTime? premiumUntil;
}

class GroupRider {
  GroupRider.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        isYou = json['isYou'] == true,
        locationUpdatedAt =
            DateTime.tryParse(json['lastLocationUpdatedAt'] as String? ?? '')
                ?.toLocal(),
        location = switch (json['location']) {
          {'lat': final num lat, 'lng': final num lng} =>
            LatLng(lat.toDouble(), lng.toDouble()),
          _ => null,
        };

  final String id, name;
  final bool isYou;
  final LatLng? location;
  final DateTime? locationUpdatedAt;
}

class GroupRide {
  GroupRide.fromJson(dynamic data)
      : id = data['id'] as String,
        code = data['code'] as String,
        isHost = data['isHost'] == true,
        expiresAt = DateTime.parse(data['expiresAt'] as String),
        members = (data['members'] as List)
            .map(
                (member) => GroupRider.fromJson(member as Map<String, dynamic>))
            .toList(growable: false);

  final String id, code;
  final bool isHost;
  final DateTime expiresAt;
  final List<GroupRider> members;
}

class GroupRideService {
  static const _path = '/group-rides';
  static final _api = ApiClient.instance;

  static Future<ApiResponse<RideSubscription>> subscription() =>
      _api.get('$_path/subscription',
          fromJson: (data) => RideSubscription.fromJson(data));

  static Future<ApiResponse<GroupRide>> current() =>
      _api.get('$_path/current', fromJson: GroupRide.fromJson);

  static Future<ApiResponse<GroupRide>> create() =>
      _api.post(_path, fromJson: GroupRide.fromJson);

  static Future<ApiResponse<GroupRide>> join(String code) => _api.post(
        '$_path/join',
        body: {'code': code},
        fromJson: GroupRide.fromJson,
      );

  static Future<ApiResponse<GroupRide>> updateLocation(String id, LatLng? p) =>
      _api.put('$_path/$id/location',
          body: {
            'location':
                p == null ? null : {'lat': p.latitude, 'lng': p.longitude}
          },
          fromJson: GroupRide.fromJson);

  static Future<ApiResponse<void>> leave(String id) =>
      _api.delete('$_path/$id');
}
