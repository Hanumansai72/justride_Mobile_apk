import 'dart:convert';

/// Represents a validated navigation destination in JustRide.
class Destination {
  final String? name;
  final String? address;
  final String? placeId;
  final double latitude;
  final double longitude;
  final String? rawQuery;

  const Destination({
    this.name,
    this.address,
    this.placeId,
    required this.latitude,
    required this.longitude,
    this.rawQuery,
  });

  /// Displays the best readable title for the destination
  String get displayTitle {
    if (name != null && name!.trim().isNotEmpty) return name!.trim();
    if (address != null && address!.trim().isNotEmpty) return address!.trim();
    return '${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
  }

  /// Displays the best subtitle / address
  String get displaySubtitle {
    if (address != null && address!.trim().isNotEmpty && address != name) {
      return address!.trim();
    }
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  Destination copyWith({
    String? name,
    String? address,
    String? placeId,
    double? latitude,
    double? longitude,
    String? rawQuery,
  }) {
    return Destination(
      name: name ?? this.name,
      address: address ?? this.address,
      placeId: placeId ?? this.placeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rawQuery: rawQuery ?? this.rawQuery,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'placeId': placeId,
      'latitude': latitude,
      'longitude': longitude,
      'rawQuery': rawQuery,
    };
  }

  factory Destination.fromMap(Map<String, dynamic> map) {
    return Destination(
      name: map['name'] as String?,
      address: map['address'] as String?,
      placeId: map['placeId'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      rawQuery: map['rawQuery'] as String?,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory Destination.fromJson(String source) =>
      Destination.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'Destination(name: $name, lat: $latitude, lng: $longitude, addr: $address)';
}
