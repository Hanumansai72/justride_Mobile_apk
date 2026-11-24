import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:justride_ui/core/utils/user_facing_error.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:justride_ui/core/constants/google_maps_config.dart';
import 'package:justride_ui/core/models/destination.dart';
import 'package:justride_ui/core/services/google_maps_service.dart';
import 'package:justride_ui/core/utils/maps_url_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const exactLink =
      'https://www.google.com/maps/place/Sri+Vasavi+Aquariums/data=!1s0x3bcb9ebc3dafaf71:0xc70b1be704f21717';
  const shared = Destination(latitude: 0, longitude: 0, rawQuery: exactLink);
  const nativeConfig = MethodChannel('com.justride.app/maps_config');
  test('cold-start share retries the native key lookup before resolving CID',
      () async {
    GoogleMapsConfig.setApiKey('');
    var loads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeConfig, (_) async {
      loads++;
      return 'test-key';
    });
    addTearDown(() {
      GoogleMapsConfig.setApiKey('');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeConfig, null);
    });
    final client = MockClient((request) async {
      expect(request.headers['X-Goog-Api-Key'], 'test-key');
      return http.Response(
          '{"places":[{"id":"ChIJca-vPbyeyzsRFxfyBOcbC8c","displayName":{"text":"Sri Vasavi Aquariums"},"googleMapsUri":"https://maps.google.com/?cid=14342588117325846295","location":{"latitude":17.41718,"longitude":78.584679}}]}',
          200);
    });
    addTearDown(client.close);
    final result =
        await GoogleMapsService.testing(client).resolveDestination(shared);
    expect(loads, 1);
    expect(result!.latitude, 17.41718);
    expect(result.longitude, 78.584679);
  });
  for (final entry
      in {403: 'denied', 429: 'busy', 503: 'could not complete'}.entries) {
    test(
        'CID HTTP ${entry.key} reports the service cause, not destination not found',
        () async {
      GoogleMapsConfig.setApiKey('test-key');
      addTearDown(() => GoogleMapsConfig.setApiKey(''));
      final client = MockClient((_) async => http.Response('{}', entry.key));
      addTearDown(client.close);
      try {
        await GoogleMapsService.testing(client).resolveDestination(shared);
        fail('The service error must be surfaced.');
      } on StateError catch (error) {
        expect(error.message, contains(entry.value));
        expect(
            userFacingError(error.message.toString()), contains(entry.value));
      }
    });
  }
  for (final offline in [false, true]) {
    test(
        offline
            ? 'offline lookup reports connectivity'
            : 'slow lookup reports timeout', () async {
      GoogleMapsConfig.setApiKey('test-key');
      addTearDown(() => GoogleMapsConfig.setApiKey(''));
      final client = MockClient((_) async {
        if (offline) throw http.ClientException('offline');
        throw TimeoutException('slow request');
      });
      addTearDown(client.close);
      await expectLater(
          GoogleMapsService.testing(client).resolveDestination(shared),
          throwsA(isA<StateError>().having(
              (e) => userFacingError(e.message.toString()),
              'actionable message',
              contains(offline ? 'mobile data' : 'too long'))));
    });
  }
  test('CID resolution never selects a different Hyderabad business', () async {
    GoogleMapsConfig.setApiKey('test-key');
    addTearDown(() => GoogleMapsConfig.setApiKey(''));
    final client = MockClient((_) async => http.Response(
        '{"places":[{"googleMapsUri":"https://maps.google.com/?cid=123","location":{"latitude":17.4,"longitude":78.5}}]}',
        200));
    addTearDown(client.close);
    expect(await GoogleMapsService.testing(client).resolveDestination(shared),
        isNull);
  });
  test('resolves an explicit named destination without a CID or place ID',
      () async {
    GoogleMapsConfig.setApiKey('test-key');
    addTearDown(() => GoogleMapsConfig.setApiKey(''));
    final client = MockClient((request) async {
      expect(request.url.queryParameters['address'], 'Uppal');
      return http.Response(
          '{"status":"OK","results":[{"geometry":{"location":{"lat":17.402,"lng":78.558}},"formatted_address":"Uppal"}]}',
          200);
    });
    addTearDown(client.close);
    final destination = await GoogleMapsService.testing(client)
        .resolveDestination(const Destination(
            name: 'Shared Map Link',
            latitude: 0,
            longitude: 0,
            rawQuery: 'https://www.google.com/maps/place/Uppal/'));
    expect(destination, isNotNull);
    expect(destination!.latitude, 17.402);
    expect(destination.longitude, 78.558);
  });
  test('preserves the exact business from the reported short-link redirect',
      () async {
    const target =
        'https://www.google.com/maps/place/Sri+Vasavi+Aquariums,+9,+Boduppal+Rd/data=!4m2!3m1!1s0x3bcb9ebc3dafaf71:0xc70b1be704f21717!18m1!1e1';
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      if (request.url.host == 'maps.app.goo.gl') {
        return http.Response('', 302, headers: {'location': target});
      }
      return http.Response(
          '<meta property="og:url" content="https://www.google.com/maps"><title>Google Maps</title>',
          200);
    });
    addTearDown(client.close);
    final result = await MapsUrlParser.parseSharedContent(
        'https://maps.app.goo.gl/uw4KxBvHWU2Mx7MUA',
        client: client);
    expect(result, isNotNull);
    expect(result!.destination.name, contains('Sri Vasavi Aquariums'));
    expect(MapsUrlParser.googleCid(result.destination.rawQuery!),
        MapsUrlParser.googleCid(target));
    expect(requests, 1);
    expect(
        result.destination.latitude, 0); // Never use the map camera as the pin.
  });
}
