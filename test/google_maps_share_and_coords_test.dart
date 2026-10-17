import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/utils/maps_url_parser.dart';
import 'package:justride_ui/core/services/share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapsUrlParser - High Accuracy DMS and Decimal Coordinate Parsing', () {
    test('converts standard DMS coordinates to high-precision decimal', () {
      final res = MapsUrlParser.parseDmsCoordinates('17°21\'41.6"N 78°28\'28.9"E');
      expect(res, isNotNull);
      final (lat, lng) = res!;
      // 17 + 21/60 + 41.6/3600 = 17.3615555...
      // 78 + 28/60 + 28.9/3600 = 78.4746944...
      expect(lat, closeTo(17.36155, 0.0001));
      expect(lng, closeTo(78.47469, 0.0001));
    });

    test('converts URL-encoded DMS coordinates', () {
      final res = MapsUrlParser.parseDmsCoordinates(
          '17%C2%B021\'41.6%22N+78%C2%B028\'28.9%22E');
      expect(res, isNotNull);
      final (lat, lng) = res!;
      expect(lat, closeTo(17.36155, 0.0001));
      expect(lng, closeTo(78.47469, 0.0001));
    });

    test('converts Degrees-Decimal-Minutes (DDM) format', () {
      final res = MapsUrlParser.parseDmsCoordinates('17°21.693\'N 78°28.482\'E');
      expect(res, isNotNull);
      final (lat, lng) = res!;
      expect(lat, closeTo(17.36155, 0.0001));
      expect(lng, closeTo(78.47469, 0.0001));
    });

    test('handles Southern and Western hemispheres correctly', () {
      final res = MapsUrlParser.parseDmsCoordinates('34°36\'12.0"S 58°22\'54.0"W');
      expect(res, isNotNull);
      final (lat, lng) = res!;
      expect(lat, closeTo(-34.60333, 0.0001));
      expect(lng, closeTo(-58.38166, 0.0001));
    });

    test('extracts high accuracy pin coordinates from Google Maps protobuf tokens', () async {
      const url =
          'https://www.google.com/maps/place/Charminar/@17.3615636,78.4721151,17z/data=!4m6!3m5!1s0x3bcb978a6e1a939b:0xcb5a69e4aa113fb7!8m2!3d17.3615636!4d78.47469';
      final dest = await MapsUrlParser.parseUrl(url);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.3615636, 0.00001));
      expect(dest.longitude, closeTo(78.47469, 0.00001));
      expect(dest.name, contains('Charminar'));
    });

    test('extracts pin coordinates when !3d and !4d are separated by other parameters', () async {
      const url =
          'https://www.google.com/maps/place/Test/@17.0,78.0,15z/data=!3d17.4485!1m2!2m1!4d78.3758';
      final dest = await MapsUrlParser.parseUrl(url);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.4485, 0.0001));
      expect(dest.longitude, closeTo(78.3758, 0.0001));
    });

    test('extracts destination coordinates from directions daddr parameter', () async {
      const url = 'https://maps.google.com/maps?saddr=17.4000,78.4000&daddr=17.4500,78.4800';
      final dest = await MapsUrlParser.parseUrl(url);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.4500, 0.0001));
      expect(dest.longitude, closeTo(78.4800, 0.0001));
    });

    test('extracts coordinates directly from URL path (/maps/place/lat,lng)', () async {
      const url = 'https://www.google.com/maps/place/17.3615636,78.47469';
      final dest = await MapsUrlParser.parseUrl(url);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.3615636, 0.00001));
      expect(dest.longitude, closeTo(78.47469, 0.00001));
    });

    test('parses dropped pin shared text containing DMS coordinates', () async {
      const shared = '''
Dropped pin
near 17°21'41.6"N 78°28'28.9"E
https://maps.app.goo.gl/nonexistent_mock_url
''';
      final dest = await MapsUrlParser.parseSharedText(shared);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.36155, 0.0001));
      expect(dest.longitude, closeTo(78.47469, 0.0001));
      expect(dest.name, contains('Dropped pin'));
    });

    test('parses geo: URI with label', () async {
      const geo = 'geo:0,0?q=17.36156,78.47469(Secret+Spot)';
      final dest = await MapsUrlParser.parseSharedText(geo);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.36156, 0.0001));
      expect(dest.longitude, closeTo(78.47469, 0.0001));
      expect(dest.name, equals('Secret Spot'));
    });

    test('parses standard geo:lat,lng URI', () async {
      const geo = 'geo:17.4485,78.3758?z=16';
      final dest = await MapsUrlParser.parseSharedText(geo);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.4485, 0.0001));
      expect(dest.longitude, closeTo(78.3758, 0.0001));
    });
  });

  group('ShareService - In-memory Processing & Deduplication', () {
    test('processes shared plain coordinate string and updates notifier', () async {
      final service = ShareService.instance;
      final dest = await service.handleSharedText('17.3615, 78.4746');
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(17.3615, 0.001));
      expect(dest.longitude, closeTo(78.4746, 0.001));
      expect(service.destinationSharedNotifier.value, equals(dest));

      service.clearSharedDestination();
      expect(service.destinationSharedNotifier.value, isNull);
    });

    test('deduplicates identical share text received in rapid succession', () async {
      final service = ShareService.instance;
      service.clearSharedDestination();

      final first = await service.handleSharedText('12.9716, 77.5946');
      expect(first, isNotNull);
      expect(service.destinationSharedNotifier.value, equals(first));

      service.clearSharedDestination();
      // Immediate second call with identical text should be deduplicated
      await service.handleSharedText('12.9716, 77.5946');
      expect(service.destinationSharedNotifier.value, isNull);
    });
  });

  group('MapsUrlParser - Google Maps Shared Route & Direction Parsing', () {
    test('extracts separate start and destination from standard Google Maps shared route text', () async {
      const shared = '''
Shared route
From Miyapur to Uppal via NH 163.

45 min (28 km)
For the best route in current traffic visit https://maps.app.goo.gl/mockroute
''';
      final result = await MapsUrlParser.parseSharedContent(shared);
      expect(result, isNotNull);
      expect(result!.startLocation, isNotNull);
      expect(result.startLocation!.name, equals('Miyapur'));
      expect(result.destination.name, equals('Uppal'));
    });

    test('treats "From Your location" as null start location so live GPS is used', () async {
      const shared = '''
Shared route
From Your location to Charminar via Inner Ring Rd.

30 min (15 km)
https://maps.app.goo.gl/mockroute2
''';
      final result = await MapsUrlParser.parseSharedContent(shared);
      expect(result, isNotNull);
      expect(result!.startLocation, isNull);
      expect(result.destination.name, equals('Charminar'));
    });

    test('cleanSearchQuery extracts destination name from route string for geocoder', () {
      const routeText = 'Shared route From Miyapur to Uppal via NH 163. 45 min (28 km)';
      final query = MapsUrlParser.cleanSearchQuery(routeText);
      expect(query, equals('Uppal'));
    });

    test('parses /maps/dir/ without assigning camera coordinates to destination', () async {
      const url =
          'https://www.google.com/maps/dir/Miyapur/Uppal/@17.4475475,78.4063717,12z/data=!3m1!4b1';
      final result = await MapsUrlParser.parseUrlDetailed(url);
      expect(result, isNotNull);
      expect(result!.startLocation, isNotNull);
      expect(result.startLocation!.name, equals('Miyapur'));
      expect(result.destination.name, equals('Uppal'));
      // Coordinates must be 0,0 so geocoder resolves real Uppal coords instead of camera/Miyapur coords
      expect(result.destination.latitude, equals(0.0));
      expect(result.destination.longitude, equals(0.0));
    });

    test('parses /maps/dir/ with explicit destination coordinates in path', () async {
      const url =
          'https://www.google.com/maps/dir/Miyapur/17.4020,78.5580/@17.4475475,78.4063717,12z';
      final result = await MapsUrlParser.parseUrlDetailed(url);
      expect(result, isNotNull);
      expect(result!.startLocation, isNotNull);
      expect(result.startLocation!.name, equals('Miyapur'));
      expect(result.destination.latitude, closeTo(17.4020, 0.0001));
      expect(result.destination.longitude, closeTo(78.5580, 0.0001));
    });
  });
}
