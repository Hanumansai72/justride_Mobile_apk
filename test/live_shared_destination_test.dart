import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:justride_ui/core/constants/google_maps_config.dart';
import 'package:justride_ui/core/models/destination.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';

class _LiveHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('live full resolver: reported link and Indian destinations', () async {
    final properties = File('android/local.properties').readAsLinesSync();
    final key = properties
        .where((line) => line.startsWith('GOOGLE_MAPS_API_KEY='))
        .map((line) => line.substring(line.indexOf('=') + 1).trim())
        .firstOrNull;
    expect(key, isNotNull,
        reason: 'Configure the local API key; never commit it in this test.');
    GoogleMapsConfig.setApiKey(key!);
    addTearDown(() => GoogleMapsConfig.setApiKey(''));
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = http.Client();
      addTearDown(client.close);
      final service = GoogleMapsService.testing(client);
      final cases = <String, (double, double, double, double)>{
        'https://maps.app.goo.gl/uw4KxBvHWU2Mx7MUA': (
          17.4170,
          17.4174,
          78.5844,
          78.5849
        ),
        'Charminar, Hyderabad, Telangana, India': (17.35, 17.38, 78.46, 78.49),
        'Secunderabad Railway Station, Hyderabad, India': (
          17.42,
          17.45,
          78.49,
          78.52
        ),
        'Durgam Cheruvu, Hyderabad, India': (17.42, 17.45, 78.38, 78.41),
        'India Gate, New Delhi, India': (28.60, 28.63, 77.21, 77.24),
        'Gateway of India, Mumbai, India': (18.91, 18.94, 72.82, 72.85),
      };
      final failed = <String>[];
      for (final entry in cases.entries) {
        final watch = Stopwatch()..start();
        final result = await service.resolveDestination(Destination(
            name: entry.key,
            address: entry.key,
            rawQuery: entry.key,
            latitude: 0,
            longitude: 0));
        print(
            '${entry.key}: ${result?.latitude}, ${result?.longitude}; ${watch.elapsedMilliseconds}ms');
        final bounds = entry.value;
        if (result == null ||
            result.latitude < bounds.$1 ||
            result.latitude > bounds.$2 ||
            result.longitude < bounds.$3 ||
            result.longitude > bounds.$4) failed.add(entry.key);
      }
      expect(failed, isEmpty,
          reason:
              'These destinations did not resolve to their expected region.');
    }, _LiveHttp());
  },
      skip: !const bool.fromEnvironment('RUN_LIVE_MAPS_CHECKS'),
      timeout: const Timeout(Duration(minutes: 3)));
}
