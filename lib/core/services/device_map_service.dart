import 'map_image_provider.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../constants/device_map_config.dart';
import '../models/device_map_frame.dart';
import '../network/api_client.dart';
import 'navigation_service.dart';
import 'google_maps_service.dart';

/// One in-flight image, one retained frame, no persistent map cache.
class DeviceMapService {
  DeviceMapService._();
  static final instance = DeviceMapService._();
  final frame = ValueNotifier<DeviceMapFrame?>(null);
  final status = ValueNotifier<String>('Waiting for map');
  DateTime _nextAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false, _initialized = false;
  int _id = 0, _failures = 0, _generation = 0;
  int zoom = 16;
  LatLng? _cameraCenter;
  bool _manualZoom = false;
  Timer? _retry;
  http.Client? _activeClient;
  int? _requestRevision;

  void init() {
    if (_initialized || !DeviceMapConfig.enabled) return;
    _initialized = true;
    NavigationService.instance.navigationStateNotifier.addListener(refresh);
  }

  void recenter() {
    _cameraCenter = null;
    _manualZoom = false;
    ++_generation;
    _activeClient?.close();
    refresh();
  }

  void showOverview() {
    final points = NavigationService.instance.activeRoute?.polylinePoints;
    if (points == null || points.isEmpty) return;
    var minLat = 85.0, maxLat = -85.0, minLng = 180.0, maxLng = -180.0;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _cameraCenter = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    var fitZoom = 18;
    while (fitZoom > 0 &&
        points.any((p) {
          final pixel = mapPixel(p, _cameraCenter!, fitZoom);
          return pixel.dx < 12 ||
              pixel.dx > DeviceMapConfig.width - 12 ||
              pixel.dy < 12 ||
              pixel.dy > DeviceMapConfig.height - 24;
        })) {
      fitZoom--;
    }
    ++_generation;
    setZoom(fitZoom);
    refresh();
  }

  void setZoom(int value) {
    _manualZoom = true;
    final next = value.clamp(0, 18);
    if (next == zoom) return;
    zoom = next;
    ++_generation;
    _activeClient?.close();
    _retry?.cancel();
    _retry = Timer(const Duration(milliseconds: 600), () {
      _retry = null;
      refresh();
    });
  }

  void refresh() {
    if (!DeviceMapConfig.enabled) return;
    final nav = NavigationService.instance;
    if (!nav.isNavigating || !nav.currentState.rideState.isActive) {
      ++_generation;
      _activeClient?.close();
      _retry?.cancel();
      _retry = null;
      _manualZoom = false;
      _cameraCenter = null;
      frame.value = null;
      status.value = 'Waiting for navigation';
      return;
    }
    final route = nav.activeRoute;
    if (_busy && _requestRevision != nav.routeRevision) {
      ++_generation;
      _activeClient?.close();
    }
    if (_busy ||
        route == null ||
        !nav.currentState.gpsAvailable ||
        nav.currentState.rideState.name == 'paused') {
      return;
    }
    if (route.provider != 'google') {
      status.value = 'Google map requires a Google route';
      return;
    }
    final state = nav.currentState;
    if (!_manualZoom) {
      final speed = state.speedKmh;
      final target = speed > 90
          ? 14
          : speed > 45
              ? 15
              : speed < 30
                  ? 16
                  : zoom;
      if (zoom != target) {
        zoom = target;
        ++_generation;
      }
    }
    final position =
        _cameraCenter ?? LatLng(state.currentLatitude, state.currentLongitude);
    final previous = frame.value;
    if (previous != null &&
        previous.revision == nav.routeRevision &&
        previous.zoom == zoom) {
      if (_cameraCenter != null && previous.center == _cameraCenter) return;
      final p = mapPixel(position, previous.center, zoom);
      // Keep generous margins for the marker, transfer delay and attribution.
      if (_cameraCenter == null &&
          p.dx >= 45 &&
          p.dx <= DeviceMapConfig.width - 45 &&
          p.dy >= 45 &&
          p.dy <= DeviceMapConfig.height - 50) {
        return;
      }
    }
    final wait = _nextAttempt.difference(DateTime.now());
    if (wait > Duration.zero) {
      _retry ??= Timer(wait, () {
        _retry = null;
        refresh();
      });
      return;
    }
    _busy = true;
    final generation = _generation;
    final revision = nav.routeRevision;
    final requestedZoom = zoom;
    _nextAttempt = DateTime.now().add(DeviceMapConfig.minimumRefresh);
    unawaited(_load(position, route, revision, requestedZoom, generation));
  }

  Future<void> _load(LatLng center, NavigationRoute route, int revision,
      int requestedZoom, int generation) async {
    final client = http.Client();
    _activeClient = client;
    _requestRevision = revision;
    bool current() =>
        generation == _generation &&
        NavigationService.instance.isNavigating &&
        NavigationService.instance.routeRevision == revision &&
        zoom == requestedZoom;
    try {
      status.value = frame.value == null ? 'Loading map' : 'Updating map';
      final bytes = await GoogleMapImageProvider(client)
          .fetch(center, requestedZoom, ApiClient.instance.token);
      if (!current()) return;
      final prepared = await prepareDeviceMap(
          bytes, center, requestedZoom, route, revision, ++_id & 65535,
          routeIndex: NavigationService.instance.routeProgressIndex,
          overview: _cameraCenter != null);
      if (!current()) return;
      frame.value = prepared;
      _failures = 0;
      status.value = 'Map ready';
    } catch (e) {
      if (current()) {
        if (e is MapImageException && e.status == 429) {
          _nextAttempt = DateTime.now().add(Duration(seconds: e.retryAfter));
        }
        _failures = (_failures + 1).clamp(1, 6);
        final backoff =
            DateTime.now().add(Duration(seconds: 10 * (1 << _failures)));
        if (backoff.isAfter(_nextAttempt)) _nextAttempt = backoff;
        status.value = 'Map unavailable; retrying';
      }
    } finally {
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
      _busy = false;
      _retry?.cancel();
      _retry = null;
      if (NavigationService.instance.isNavigating) refresh();
    }
  }
}

/// Decode native size only. Draw compatible route outside the copyright strip.
Future<DeviceMapFrame> prepareDeviceMap(Uint8List bytes, LatLng center,
    int zoom, NavigationRoute route, int revision, int id,
    {int routeIndex = 0, bool overview = false}) async {
  if (route.provider != 'google') {
    throw const FormatException('Incompatible map route');
  }
  if (bytes.length < 4 ||
      bytes[0] != 255 ||
      bytes[1] != 216 ||
      bytes[bytes.length - 2] != 255 ||
      bytes.last != 217) {
    throw const FormatException('Invalid JPEG');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? source, image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width != DeviceMapConfig.width ||
        descriptor.height != DeviceMapConfig.height) {
      throw const FormatException('Unexpected map dimensions');
    }
    codec = await descriptor.instantiateCodec();
    source = (await codec.getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    canvas.save();
    canvas.clipRect(ui.Rect.fromLTWH(
        0, 0, DeviceMapConfig.width.toDouble(), DeviceMapConfig.height - 24));
    final path = ui.Path();
    final first =
        overview ? 0 : (routeIndex - 8).clamp(0, route.polylinePoints.length);
    final last = overview
        ? route.polylinePoints.length
        : (first + 512).clamp(0, route.polylinePoints.length);
    final stride = overview ? ((last + 510) ~/ 511).clamp(1, 1000000) : 1;
    for (var i = first; i < last; i += stride) {
      final p = mapPixel(route.polylinePoints[i], center, zoom);
      if (i == first) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (overview && last > first) {
      final endpoint = mapPixel(route.polylinePoints[last - 1], center, zoom);
      path.lineTo(endpoint.dx, endpoint.dy);
    }
    canvas.drawPath(
        path,
        ui.Paint()
          ..color = const ui.Color(0xff25d9a0)
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = ui.StrokeJoin.round);
    canvas.restore();
    final picture = recorder.endRecording();
    try {
      image =
          await picture.toImage(DeviceMapConfig.width, DeviceMapConfig.height);
    } finally {
      picture.dispose();
    }
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    final rgb = Uint8List(DeviceMapConfig.width * DeviceMapConfig.height * 2);
    for (var p = 0, i = 0; i < rgba.length; i += 4, p += 2) {
      final color = ((rgba[i] >> 3) << 11) |
          ((rgba[i + 1] >> 2) << 5) |
          (rgba[i + 2] >> 3);
      rgb[p] = color >> 8;
      rgb[p + 1] = color & 255;
    }
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    return DeviceMapFrame(
        id: id,
        revision: revision,
        zoom: zoom,
        center: center,
        crc: mapCrc32(rgb),
        png: png,
        compressed: mapRle(rgb));
  } finally {
    image?.dispose();
    source?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}
