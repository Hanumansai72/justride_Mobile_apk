import 'dart:async';
import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../constants/device_map_config.dart';

abstract interface class MapImageProvider {
  Future<Uint8List> fetch(LatLng center, int zoom, String? authToken);
}

class MapImageException implements Exception {
  final int status, retryAfter;
  const MapImageException(this.status, this.retryAfter);
}

/// Uses the authenticated JustRide proxy. No Google server credential in the app.
class GoogleMapImageProvider implements MapImageProvider {
  final http.Client client;
  final Uri endpoint;
  GoogleMapImageProvider(this.client, {Uri? endpoint})
      : endpoint = endpoint ?? Uri.parse(DeviceMapConfig.endpoint);

  @override
  Future<Uint8List> fetch(LatLng center, int zoom, String? authToken) async {
    if (!center.latitude.isFinite ||
        center.latitude.abs() > 85 ||
        !center.longitude.isFinite ||
        center.longitude.abs() > 180 ||
        zoom < 0 ||
        zoom > 18) {
      throw const FormatException('Invalid map parameters');
    }
    final uri = endpoint.replace(queryParameters: {
      'latitude': '${center.latitude}',
      'longitude': '${center.longitude}',
      'zoom': '$zoom',
      'style': 'dark',
      'width': '${DeviceMapConfig.width}',
      'height': '${DeviceMapConfig.height}',
    });
    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'image/jpeg',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      });
    final response =
        await client.send(request).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      final seconds = int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
      throw MapImageException(response.statusCode, seconds.clamp(30, 3600));
    }
    if (response.headers['content-type']?.split(';').first != 'image/jpeg' ||
        (response.contentLength ?? 0) > 512000) {
      throw const FormatException('Invalid map response');
    }
    final builder = BytesBuilder(copy: false);
    await for (final bytes
        in response.stream.timeout(const Duration(seconds: 10))) {
      if (builder.length + bytes.length > 512000) {
        throw const FormatException('Map too large');
      }
      builder.add(bytes);
    }
    return builder.takeBytes();
  }
}
