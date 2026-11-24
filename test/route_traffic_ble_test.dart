import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/models/device_map_frame.dart';
import 'package:justride_ui/core/utils/route_window_transformer.dart';

void main() {
  test('traffic is packed per road edge and omitted for older displays', () {
    final points = List.generate(6, (i) => LatLng(17.4 + i * 0.001, 78.6));
    final window = RouteWindowTransformer.transform(
      riderPosition: points.first,
      riderHeadingDeg: 0,
      polylinePoints: points,
      destination: points.last,
      overviewViewport: fitDeviceMapViewport(points),
      trafficByEdge: const [1, 2, 3, 0, 1],
    );
    expect(window.traffic, [1, 2, 3, 0, 1]);

    final packet = RouteSegmentPacket.fromWindow(window);
    final legacy = packet.toBinary();
    final extended = packet.toBinary(includeTraffic: true);
    expect(legacy.length, 8 + points.length * 4);
    expect(legacy[2] & 0x80, 0);
    expect(extended[2] & 0x80, 0x80);
    expect(extended.sublist(legacy.length), [0x39, 0x01]);
    extended[2] &= 0x7f;
    expect(extended.sublist(0, legacy.length), legacy);
  });

  test(
      'simplification preserves traffic boundaries and uses the right edge after progress',
      () {
    final points = List.generate(30, (i) => LatLng(17.4 + i * 0.001, 78.6));
    final traffic = List.generate(
        29,
        (i) => i < 7
            ? 1
            : i < 9
                ? 3
                : 2);
    final overview = RouteWindowTransformer.transform(
      riderPosition: points.first,
      riderHeadingDeg: 0,
      polylinePoints: points,
      destination: points.last,
      overviewViewport: fitDeviceMapViewport(points),
      trafficByEdge: traffic,
    );
    expect(overview.points.length, lessThanOrEqualTo(14));
    expect(overview.traffic.length, overview.points.length - 1);
    expect(overview.traffic.toSet().toList(), [1, 3, 2]);

    final detail = RouteWindowTransformer.transform(
      riderPosition: points[7],
      riderHeadingDeg: 0,
      polylinePoints: points,
      destination: points.last,
      minimumRouteIndex: 7,
      windowMeters: 50,
      focusManeuver: false,
      trafficByEdge: traffic,
    );
    expect(detail.routeIndex, 7);
    expect(detail.traffic.skip(detail.completedSegmentCount), [3]);
  });
}
