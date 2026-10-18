import 'dart:async';
import 'package:justride_ui/core/services/map_image_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justride_ui/core/constants/google_maps_config.dart';
import 'package:justride_ui/core/models/device_map_frame.dart';
import 'package:justride_ui/core/services/device_map_service.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const center = LatLng(17.437, 78.58);
  const route = NavigationRoute(
      provider: 'osrm',
      totalDistanceMeters: 100,
      totalDurationSeconds: 10,
      polylinePoints: [center, LatLng(17.438, 78.58)],
      steps: []);

  test('Web Mercator center, heading and antimeridian projection', () {
    expect(mapPixel(center, center, 16).dx, 99);
    expect(mapPixel(center, center, 16).dy, 97);
    expect(mapPixel(const LatLng(17.438, 78.58), center, 16).dy, lessThan(97));
    expect(mapPixel(const LatLng(0, -179.999), const LatLng(0, 179.999), 10).dx,
        closeTo(100.456, .01));
  });

  test('CRC matches standard CRC32 and RLE bounds/round trip', () {
    expect(mapCrc32(utf8.encode('123456789')), 0xcbf43926);
    final pixels =
        Uint8List.fromList([...List<int>.filled(600, 0), 255, 255, 0, 0]);
    final compressed = mapRle(pixels);
    expect(compressed.first, 255);
    final decoded = <int>[];
    for (var i = 0; i < compressed.length; i += 3) {
      expect(compressed[i], inInclusiveRange(1, 255));
      for (var n = 0; n < compressed[i]; n++) {
        decoded.addAll([compressed[i + 1], compressed[i + 2]]);
      }
    }
    expect(decoded, pixels);
    expect(() => mapRle(Uint8List(1)), throwsFormatException);
  });

  test('MTU chunking and marker never overwrite attribution', () {
    final f = DeviceMapFrame(
        id: 1025,
        revision: 1,
        zoom: 16,
        center: center,
        crc: 123,
        png: Uint8List(0),
        compressed: Uint8List.fromList(List.filled(600, 1)));
    for (final mtu in [23, 185, 247, 517]) {
      final packets = f.chunks(mtu).toList();
      expect(
          packets
              .every((p) => p.length + 5 <= mtu - 3 && (p.length - 5) % 3 == 0),
          isTrue);
      expect(packets.expand((p) => p.skip(5)).toList(), f.compressed);
      expect(packets[0].sublist(1, 5), [1, 4, 0, 0]);
    }
    expect(f.start.length, 11);
    expect(f.marker(center, 359)!.length, 9);
    expect(f.marker(const LatLng(0, 0), 0), isNull);
    expect(f.marker(center, double.nan), isNull);
    expect(
        f.marker(
            LatLng(
                center.latitude, center.longitude + 87.8 / (256 * 65536) * 360),
            0),
        isNull);
  });

  test(
      'image provider authenticates proxy and rejects HTTP/quota/network failures',
      () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'backend.justride.cc');
      expect(request.url.queryParameters.containsKey('key'), isFalse);
      expect(request.headers['Authorization'], 'Bearer test-auth');
      return http.Response.bytes([255, 216, 255, 217], 200,
          headers: {'content-type': 'image/jpeg'});
    });
    expect(
        await LocationIqMapImageProvider(client).fetch(center, 16, 'test-auth'),
        [255, 216, 255, 217]);
    for (final status in [401, 403, 429, 500, 503]) {
      final provider = LocationIqMapImageProvider(MockClient((_) async =>
          http.Response('error', status, headers: {'retry-after': '125'})));
      await expectLater(
          provider.fetch(center, 16, null),
          throwsA(isA<MapImageException>()
              .having((e) => e.status, 'status', status)
              .having((e) => e.retryAfter, 'retry', 125)));
    }
    for (final error in [
      const SocketException('Offline'),
      TimeoutException('Network timeout')
    ]) {
      await expectLater(
          LocationIqMapImageProvider(MockClient((_) async => throw error))
              .fetch(center, 16, null),
          throwsA(same(error)));
    }
    await expectLater(
        LocationIqMapImageProvider(client).fetch(center, 19, null),
        throwsFormatException);
    for (final response in [
      http.Response('html', 200, headers: {'content-type': 'text/html'}),
      http.Response.bytes(Uint8List(512001), 200,
          headers: {'content-type': 'image/jpeg'})
    ]) {
      await expectLater(
          LocationIqMapImageProvider(MockClient((_) async => response))
              .fetch(center, 16, null),
          throwsFormatException);
    }
  });

  test('Google routing remains available separately with explicit provenance',
      () async {
    GoogleMapsConfig.setApiKey('test-only-key');
    final maps = GoogleMapsService.testing(MockClient((request) async {
      expect(request.url.host, 'routes.googleapis.com');
      return http.Response(
          jsonEncode({
            'routes': [
              {
                'distanceMeters': 1000,
                'duration': '120s',
                'polyline': {'encodedPolyline': r'_p~iF~ps|U_ulLnnqC_mqNvxq`@'},
                'legs': [
                  {
                    'steps': [
                      {
                        'distanceMeters': 1000,
                        'staticDuration': '120s',
                        'navigationInstruction': {
                          'maneuver': 'STRAIGHT',
                          'instructions': 'Continue'
                        }
                      }
                    ]
                  }
                ]
              }
            ]
          }),
          200);
    }));
    final result = await maps.calculateRoute(
        origin: center,
        destination: const LatLng(17.44, 78.59),
        compatibleMapOnly: false);
    expect(result?.provider, 'google');
    expect(result?.polylinePoints.length, greaterThan(1));
    GoogleMapsConfig.setApiKey('');
  });

  test('LocationIQ mode never calls Google routing even when its key exists',
      () async {
    GoogleMapsConfig.setApiKey('test-only-key');
    final calls = <Uri>[];
    final service = GoogleMapsService.testing(MockClient((request) async {
      calls.add(request.url);
      return http.Response('{"code":"NoRoute"}', 200);
    }));
    expect(
        await service.calculateRoute(
            origin: center,
            destination: const LatLng(17.44, 78.59),
            compatibleMapOnly: true),
        isNull);
    expect(calls, hasLength(1));
    expect(calls.single.host, 'router.project-osrm.org');
    GoogleMapsConfig.setApiKey('');
  });

  test(
      'decode real native-size JPEG, retain footer, reject wrong provider/corruption',
      () async {
    // Live probe is ignored build output. This optional measurement is not a fixture
    // containing credentials or a persistent cache distributed with the application.
    final probe = File('build/locationiq-probe.jpg');

    final bytes = probe.readAsBytesSync();
    final timer = Stopwatch()..start();
    final f = await prepareDeviceMap(bytes, center, 16, route, 1, 1);
    timer.stop();
    // ignore: avoid_print
    print(
        'Map preprocessing: ${timer.elapsedMilliseconds}ms, jpeg=${bytes.length}, rle=${f.compressed.length}');
    expect(f.png, isNotEmpty);
    final decoded = <int>[];
    for (var i = 0; i < f.compressed.length; i += 3) {
      for (var n = 0; n < f.compressed[i]; n++) {
        decoded.addAll([f.compressed[i + 1], f.compressed[i + 2]]);
      }
    }
    expect(decoded.length, 198 * 194 * 2);
    expect(mapCrc32(decoded), f.crc);
    final blank = await prepareDeviceMap(
        bytes,
        center,
        16,
        const NavigationRoute(
            provider: 'osrm',
            totalDistanceMeters: 0,
            totalDurationSeconds: 0,
            polylinePoints: [],
            steps: []),
        1,
        2);
    final blankDecoded = <int>[];
    for (var i = 0; i < blank.compressed.length; i += 3) {
      for (var n = 0; n < blank.compressed[i]; n++) {
        blankDecoded.addAll([blank.compressed[i + 1], blank.compressed[i + 2]]);
      }
    }
    expect(decoded.sublist(198 * 170 * 2), blankDecoded.sublist(198 * 170 * 2),
        reason: 'Attribution strip must remain unchanged');
    final wrongSize = Uint8List.fromList(bytes);
    for (var i = 0; i < wrongSize.length - 10; i++) {
      if (wrongSize[i] == 255 && [192, 193, 194].contains(wrongSize[i + 1])) {
        wrongSize[i + 7] = 199;
        break;
      }
    }
    await expectLater(prepareDeviceMap(wrongSize, center, 16, route, 1, 1),
        throwsFormatException);
    await expectLater(
        prepareDeviceMap(
            Uint8List.fromList([137, 80, 78, 71]), center, 16, route, 1, 1),
        throwsFormatException);

    expect(
        prepareDeviceMap(
            Uint8List.fromList([255, 216, 255, 217]), center, 16, route, 1, 1),
        throwsA(anything));
    expect(
        prepareDeviceMap(
            bytes,
            center,
            16,
            const NavigationRoute(
                provider: 'google',
                totalDistanceMeters: 1,
                totalDurationSeconds: 1,
                polylinePoints: [],
                steps: []),
            1,
            1),
        throwsFormatException);
  }, skip: !File('build/locationiq-probe.jpg').existsSync());
}
