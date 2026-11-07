import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../constants/device_map_config.dart';

/// North-up Web Mercator; same pixel scale as the Static Maps request.
Offset mapPixel(LatLng point, LatLng center, int zoom) {
  Offset world(LatLng p) {
    final sin = math.sin(p.latitude.clamp(-85.0, 85.0) * math.pi / 180);
    final scale = 256.0 * math.pow(2, zoom);
    return Offset((p.longitude + 180) / 360 * scale,
        (0.5 - math.log((1 + sin) / (1 - sin)) / (4 * math.pi)) * scale);
  }

  final delta = world(point) - world(center);
  final scale = 256.0 * math.pow(2, zoom);
  var dx = delta.dx;
  if (dx > scale / 2) dx -= scale;
  if (dx < -scale / 2) dx += scale;
  return Offset(
      DeviceMapConfig.width / 2 + dx, DeviceMapConfig.height / 2 + delta.dy);
}

LatLng mapCoordinate(Offset pixel, LatLng center, int zoom) {
  final scale = 256.0 * math.pow(2, zoom);
  final sin = math.sin(center.latitude.clamp(-85.0, 85.0) * math.pi / 180);
  final y = .5 -
      math.log((1 + sin) / (1 - sin)) / (4 * math.pi) +
      (pixel.dy - DeviceMapConfig.height / 2) / scale;
  final longitude =
      center.longitude + (pixel.dx - DeviceMapConfig.width / 2) * 360 / scale;
  final v = math.pi * (1 - 2 * y);
  return LatLng(math.atan((math.exp(v) - math.exp(-v)) / 2) * 180 / math.pi,
      (longitude + 180) % 360 - 180);
}

/// Same padded, north-up viewport for raster and vector overview. Reserve the
/// trip card, compass, attribution and marker radius of the existing 2.8" HUD.
({LatLng center, int zoom}) fitDeviceMapViewport(List<LatLng> points) {
  if (points.isEmpty) throw const FormatException('No route to fit');
  final origin = points.first;
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final point in points) {
    final p = mapPixel(point, origin, 0);
    minX = math.min(minX, p.dx);
    maxX = math.max(maxX, p.dx);
    minY = math.min(minY, p.dy);
    maxY = math.max(maxY, p.dy);
  }
  var zoom = 18;
  while (zoom > 0 &&
      ((maxX - minX) * math.pow(2, zoom) > 174 ||
          (maxY - minY) * math.pow(2, zoom) > 91)) {
    zoom--;
  }
  var center =
      mapCoordinate(Offset((minX + maxX) / 2, (minY + maxY) / 2), origin, 0);
  center = mapCoordinate(
      const Offset(
          DeviceMapConfig.width / 2 + 12, DeviceMapConfig.height / 2 - 1),
      center,
      zoom);
  return (center: center, zoom: zoom);
}

int mapCrc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final b in bytes) {
    crc ^= b;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

Uint8List mapRle(Uint8List rgb) {
  if (rgb.length.isOdd) {
    throw const FormatException('RGB565 requires pixel pairs');
  }
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < rgb.length;) {
    var count = 1;
    while (count < 255 &&
        i + count * 2 < rgb.length &&
        rgb[i] == rgb[i + count * 2] &&
        rgb[i + 1] == rgb[i + count * 2 + 1]) {
      count++;
    }
    out.add([count, rgb[i], rgb[i + 1]]);
    i += count * 2;
  }
  return out.takeBytes();
}

class DeviceMapFrame {
  final int id, revision, zoom, crc;
  final LatLng center;
  final Uint8List png, compressed;
  const DeviceMapFrame(
      {required this.id,
      required this.revision,
      required this.zoom,
      required this.center,
      required this.crc,
      required this.png,
      required this.compressed});

  List<int> get start => [
        0x14,
        ...word(id),
        ...word(DeviceMapConfig.width),
        ...word(DeviceMapConfig.height),
        crc & 255,
        (crc >> 8) & 255,
        (crc >> 16) & 255,
        (crc >> 24) & 255
      ];
  List<int> get commit => [0x16, ...word(id)];
  static List<int> word(int n) => [n & 255, (n >> 8) & 255];

  Iterable<List<int>> chunks(int mtu) sync* {
    // ATT header 3 + revision wrapper 5 + data header 5. RLE triples stay whole.
    final payload = ((math.min(240, mtu - 13)) ~/ 3) * 3;
    if (payload < 3) {
      throw const FormatException('MTU too small for map frames');
    }
    var seq = 0;
    for (var offset = 0; offset < compressed.length; offset += payload) {
      yield [
        0x15,
        ...word(id),
        ...word(seq++),
        ...compressed.sublist(
            offset, math.min(offset + payload, compressed.length))
      ];
    }
  }

  List<int>? marker(LatLng position, double heading) {
    final p = mapPixel(position, center, zoom);
    if (!p.dx.isFinite ||
        !p.dy.isFinite ||
        !heading.isFinite ||
        p.dx < 11 ||
        p.dx >= DeviceMapConfig.width - 11 ||
        p.dy < 11 ||
        p.dy >= DeviceMapConfig.height - 28) {
      return null;
    }
    final x = p.dx.round(), y = p.dy.round();
    if (x < 11 ||
        x >= DeviceMapConfig.width - 11 ||
        y < 11 ||
        y >= DeviceMapConfig.height - 28) {
      return null;
    }
    return [
      0x18,
      ...word(id),
      ...word(x),
      ...word(y),
      ...word(heading.round() % 360)
    ];
  }
}
