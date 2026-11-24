import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/models/device_map_frame.dart';
import 'package:justride_ui/core/services/navigation_service.dart';
import 'package:justride_ui/core/utils/route_window_transformer.dart';

// Geographic route-coordinate fixture, NOT downloaded road imagery or live GPS.
const route = [
  LatLng(12.971, 77.5946),
  LatLng(12.9728, 77.5946),
  LatLng(12.9728, 77.59506),
  LatLng(12.975, 77.59506),
  LatLng(12.975, 77.600),
  LatLng(12.9773, 77.600)
];
RouteWindowSegment window(double meters,
        {({LatLng center, int zoom})? viewport,
        LatLng? rider,
        int floor = 0}) =>
    RouteWindowTransformer.transform(
        riderPosition: rider ?? route.first,
        riderHeadingDeg: 0,
        polylinePoints: route,
        destination: route.last,
        minimumRouteIndex: floor,
        windowMeters: meters,
        focusManeuver: false,
        overviewViewport: viewport);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Mercator inverse and date-line overview preserve coordinates', () {
    for (final center in [route.first, const LatLng(70, 179.999)]) {
      const pixel = Offset(100, 110);
      final roundTrip = mapPixel(mapCoordinate(pixel, center, 15), center, 15);
      expect(roundTrip.dx, closeTo(pixel.dx, 1e-5));
      expect(roundTrip.dy, closeTo(pixel.dy, 1e-5));
    }
    final fit = fitDeviceMapViewport(
        [const LatLng(12, 179.999), const LatLng(12, -179.999)]);
    expect(fit.zoom, greaterThan(10));
  });
  test('Remaining route fits clear of HUD cards, compass and attribution', () {
    final fit = fitDeviceMapViewport(route);
    for (final point in route) {
      final p = mapPixel(point, fit.center, fit.zoom);
      expect(p.dx, inInclusiveRange(13, 189));
      expect(p.dy, inInclusiveRange(43, 136));
    }
    final full = window(1800, viewport: fit);
    expect(full.isDestinationVisible, isTrue);
    expect(full.points.length, lessThanOrEqualTo(14));
    expect(full.cameraProjected, isTrue);
    expect(full.overview, isTrue);
  });
  test('A wider level shows more real route, not a scaled short window', () {
    final detail = window(150), mid = window(700);
    expect(detail.isDestinationVisible, isFalse);
    expect(mid.points.length, greaterThan(detail.points.length));
    expect(detail.points.first.x, 160);
    expect(detail.points.first.y, 160);
    expect(mid.points.first.x, 160);
    expect(mid.points.first.y, 160);
  });
  test('Overview destination stays fixed while rider/progress moves', () {
    final fit = fitDeviceMapViewport(route);
    final first = window(1800, viewport: fit);
    final moved = window(1800, viewport: fit, rider: route[1], floor: 1);
    expect(moved.destinationScreenPoint!.x, first.destinationScreenPoint!.x);
    expect(moved.destinationScreenPoint!.y, first.destinationScreenPoint!.y);
    expect(moved.points.first.y, isNot(first.points.first.y));
    expect(moved.routeIndex, greaterThanOrEqualTo(1));
    final rerouteFit = fitDeviceMapViewport([...route, const LatLng(13, 78)]);
    expect(rerouteFit, isNot(fit));
  });
  test('Invalid commands cannot escape five levels; selected level persists',
      () {
    final nav = NavigationService.testing((_, __) async => null);
    nav.selectDeviceView(17);
    expect(nav.deviceViewLevel, 1);
    final generation = nav.deviceCameraGeneration;
    for (final command in [-1, 0, 13, 18, 256]) {
      nav.selectDeviceView(command);
    }
    expect(nav.deviceViewLevel, 1);
    expect(nav.deviceCameraGeneration, generation);
    nav.selectDeviceView(255);
    expect(nav.deviceViewLevel, 5);
    nav.selectDeviceView(14);
    expect(nav.deviceViewLevel, 4);
    nav.selectDeviceView(254);
    expect(nav.deviceViewLevel, 2);
  });
  test('Export actual phone packets for production firmware render checks', () {
    final fit = fitDeviceMapViewport(route);
    final packets = [window(150), window(700), window(1800, viewport: fit)]
        .map((w) => RouteSegmentPacket.fromWindow(w).toBinary().toList())
        .toList();
    expect(packets[0][2] & 0x40, 0x40);
    expect(packets[2][2] & 0x60, 0x60);
    final file = File(Platform.environment['JR_ZOOM_FIXTURE_OUT'] ??
        'build/touch-zoom-packets.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(packets));
  });
}
