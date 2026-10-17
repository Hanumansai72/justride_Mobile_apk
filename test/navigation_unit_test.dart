import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/models/navigation_state.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/utils/route_window_transformer.dart';
import 'package:justride_ui/core/utils/maps_url_parser.dart';
import 'package:justride_ui/core/utils/maneuver_mapper.dart';

void main() {
  test('A sparse 100 m approach stays straight and shows its real turn', () {
    const start = LatLng(12.0, 77.0);
    const turn = LatLng(12.0009, 77.0);
    const exit = LatLng(12.0009, 77.0009);
    final window = RouteWindowTransformer.transform(
      riderPosition: const LatLng(12.00045, 77.0),
      riderHeadingDeg: 27, // GPS compass drift must not tilt the road.
      polylinePoints: const [start, turn, exit],
      destination: exit,
    );

    final rider = window.points[window.completedSegmentCount];
    final ahead = window.points[window.completedSegmentCount + 1];
    final afterTurn = window.points[window.completedSegmentCount + 2];
    expect(rider.x, 160);
    expect(rider.y, 160);
    expect(ahead.x, 160);
    expect(ahead.y, lessThan(rider.y));
    expect(afterTurn.x, greaterThan(ahead.x));
    expect(afterTurn.y, closeTo(ahead.y, 2));
  });

  test('Heading-up route follows GPS while the rider anchor stays fixed', () {
    final points = List.generate(5, (i) => LatLng(12.0 + i * 0.0003, 77.0));
    RouteWindowSegment at(int index) => RouteWindowTransformer.transform(
          riderPosition: points[index],
          riderHeadingDeg: 0,
          polylinePoints: points,
          destination: points.last,
        );

    final first = at(1);
    final second = at(2);
    expect(first.points[first.completedSegmentCount].x, 160);
    expect(first.points[first.completedSegmentCount].y, 160);
    expect(second.points[second.completedSegmentCount].x, 160);
    expect(second.points[second.completedSegmentCount].y, 160);
    expect(second.routeIndex, greaterThan(first.routeIndex));
    expect(second.progressPercent, greaterThan(first.progressPercent));
  });

  test('Route progress follows GPS, stays monotonic, and resets with new route',
      () {
    final points = List.generate(5, (i) => LatLng(12.0 + i * 0.0003, 77.0));
    RouteWindowSegment at(int index, {int floor = 0}) =>
        RouteWindowTransformer.transform(
          riderPosition: points[index],
          riderHeadingDeg: 0,
          polylinePoints: points,
          destination: points.last,
          minimumRouteIndex: floor,
        );

    expect(at(0).progressPercent, 0);
    final halfway = at(2);
    expect(halfway.progressPercent, 50);
    expect(halfway.completedSegmentCount, greaterThan(0));
    expect(at(1, floor: halfway.routeIndex).progressPercent, 50);
    expect(at(4).progressPercent, 100);
    expect(at(0).progressPercent, 0); // a new route starts without old progress
  });

  group('MapsUrlParser Tests', () {
    test('Parses raw latitude and longitude coordinate string', () async {
      final dest = await MapsUrlParser.parseSharedText('12.9716, 77.5946');
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(12.9716, 0.0001));
      expect(dest.longitude, closeTo(77.5946, 0.0001));
    });

    test('Does not use a Google Maps camera coordinate as a place destination',
        () async {
      const url =
          'https://www.google.com/maps/place/Cubbon+Park/@12.9763,77.5929,17z/data=!3m1!4b1';
      final dest = await MapsUrlParser.parseSharedText(url);
      expect(dest, isNotNull);
      expect(dest!.name, 'Cubbon Park');
      expect(dest.latitude, 0.0);
      expect(dest.longitude, 0.0);
    });

    test('Parses Google Maps search URL with ?q=lat,lng', () async {
      const url = 'https://maps.google.com/?q=13.0827,80.2707';
      final dest = await MapsUrlParser.parseSharedText(url);
      expect(dest, isNotNull);
      expect(dest!.latitude, closeTo(13.0827, 0.0001));
      expect(dest.longitude, closeTo(80.2707, 0.0001));
    });

    test('Parses plain text address query fallback', () async {
      const query = 'MG Road Metro Station Bangalore';
      final dest = await MapsUrlParser.parseSharedText(query);
      expect(dest, isNotNull);
      expect(dest!.displayTitle, query);
      expect(dest.latitude, 0.0);
    });
  });

  group('ManeuverMapper Tests', () {
    test('Maps Google maneuver strings to JustRide enums and HUD text', () {
      expect(ManeuverMapper.toJustRideManeuver('TURN_LEFT'), 'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver('TURN_SHARP_RIGHT'), 'SHARP_RIGHT');
      expect(ManeuverMapper.toJustRideManeuver('UTURN_LEFT'), 'U_TURN');
      expect(
          ManeuverMapper.toJustRideManeuver('ROUNDABOUT_ENTER'), 'ROUNDABOUT');
      expect(ManeuverMapper.toJustRideManeuver('STRAIGHT'), 'STRAIGHT');
      expect(ManeuverMapper.toJustRideManeuver('DESTINATION'), 'ARRIVE');

      expect(ManeuverMapper.toRiderActionText('LEFT'), 'TURN LEFT');
      expect(ManeuverMapper.toRiderActionText('RIGHT'), 'TURN RIGHT');
      expect(ManeuverMapper.toRiderActionText('U_TURN'), 'MAKE U-TURN');
      expect(ManeuverMapper.toRiderActionText('STRAIGHT'), 'CONTINUE STRAIGHT');
    });

    test('Parses Indian regional languages from instruction text correctly',
        () {
      // Assamese / Bengali (from real-world screenshot: The Hunger's Spotত বাওঁফালে ঘূৰক)
      expect(
          ManeuverMapper.toJustRideManeuver(
              null, "The Hunger's Spotত বাওঁফালে ঘূৰক"),
          'LEFT');
      expect(ManeuverMapper.toJustRideManeuver(null, "Dad houseত সোঁফালে ঘূৰক"),
          'RIGHT');
      // Hindi
      expect(ManeuverMapper.toJustRideManeuver(null, "एमजी रोड पर बाएं मुड़ें"),
          'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver(null, "ब्रिगेड रोड पर दाएं मुड़ें"),
          'RIGHT');
      // Telugu
      expect(
          ManeuverMapper.toJustRideManeuver(null, "ఎడమవైపు తిరగండి"), 'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver(null, "కుడివైపు తిరగండి"), 'RIGHT');
    });

    test('Maps maneuver to ESP32 nav_direction_t code', () {
      expect(ManeuverMapper.toManeuverCode('STRAIGHT').value, 1);
      expect(ManeuverMapper.toManeuverCode('LEFT').value, 4);
      expect(ManeuverMapper.toManeuverCode('RIGHT').value, 5);
      expect(ManeuverMapper.toManeuverCode('SHARP_LEFT').value, 6);
      expect(ManeuverMapper.toManeuverCode('SHARP_RIGHT').value, 7);
      expect(ManeuverMapper.toManeuverCode('U_TURN').value, 8);
      expect(ManeuverMapper.toManeuverCode('ARRIVE').value, 9);
    });
  });

  group('BleNavigationPacket Binary & JSON Tests', () {
    test('City and nearby-place context uses bounded optional packet', () {
      final bytes = const NavContextPacket(
        city: 'Hyderabad',
        poiType: 1,
        poiDistanceMeters: 500,
        poiName: 'Fuel Station',
        poiPoint: ScreenPoint(170, 110),
      ).toBinary();
      final data = ByteData.sublistView(bytes);
      final offset = 2 + bytes[1];
      expect(bytes[0], BleNavOpCode.navContext.value);
      expect(String.fromCharCodes(bytes.sublist(2, offset)), 'Hyderabad');
      expect(bytes[offset], 1);
      expect(data.getUint16(offset + 1, Endian.little), 500);
      expect(data.getUint16(offset + 3, Endian.little), 170);
      expect(data.getUint16(offset + 5, Endian.little), 110);
      expect(String.fromCharCodes(bytes.sublist(offset + 8)), 'Fuel Station');
    });

    test('Route segment bytes match the ESP32 polyline packet', () {
      const segment = RouteWindowSegment(
        points: [ScreenPoint(160, 160), ScreenPoint(190, 80)],
        completedSegmentCount: 1,
        progressPercent: 25,
        isDestinationVisible: true,
        destinationScreenPoint: ScreenPoint(190, 80),
      );
      final bytes = RouteSegmentPacket.fromWindow(segment).toBinary();
      final data = ByteData.sublistView(bytes);

      expect(bytes.length, 16);
      expect(bytes[0], BleNavOpCode.navRouteSegment.value);
      expect(bytes[1], 2);
      expect(bytes[2] & 1, 1);
      expect(bytes[2] >> 1, 1);
      expect(data.getUint16(3, Endian.little), 190);
      expect(data.getUint16(5, Endian.little), 80);
      expect(data.getUint16(7, Endian.little), 160);
      expect(data.getUint16(9, Endian.little), 160);
      expect(data.getUint16(11, Endian.little), 190);
      expect(data.getUint16(13, Endian.little), 80);
      expect(bytes[15], 25);
    });

    test('Binary packet serialization matches ESP32 layout', () {
      const state = NavigationState(
        currentLatitude: 12.9716,
        currentLongitude: 77.5946,
        speedKmh: 42.0,
        heading: 87.0,
        remainingDistanceMeters: 4200,
        remainingDurationSeconds: 720,
        maneuver: 'RIGHT',
        maneuverText: 'MG Road',
        maneuverDistanceMeters: 250,
        navigationStatus: 'NAVIGATING',
      );

      final packet = BleNavigationPacket.fromState(
        state,
        opCode: BleNavOpCode.navUpdate,
      );
      final binary = packet.toBinary();

      expect(binary.length, greaterThanOrEqualTo(18));

      // Byte 0: OpCode
      expect(binary[0], BleNavOpCode.navUpdate.value);
      // Byte 1: Maneuver RIGHT = 5
      expect(binary[1], JustRideManeuverCode.right.value);

      // Bytes 2-3: Maneuver distance (250m uint16 LE)
      final byteData = ByteData.sublistView(binary);
      expect(byteData.getUint16(2, Endian.little), 250);

      // Bytes 4-5: Speed (42 km/h uint16 LE)
      expect(byteData.getUint16(4, Endian.little), 42);

      // Bytes 6-7: Heading (87 deg uint16 LE)
      expect(byteData.getUint16(6, Endian.little), 87);

      // Bytes 8-11: Remaining distance (4200m uint32 LE)
      expect(byteData.getUint32(8, Endian.little), 4200);

      // Bytes 12-15: ETA (720s uint32 LE)
      expect(byteData.getUint32(12, Endian.little), 720);

      // Byte 16: isNavigating flag set
      expect(binary[16] & 0x01, 1);

      // Byte 17: Maneuver state
      // Bytes 18-19: Maneuver ID
      // Byte 20: Text length ("MG Road" = 7 bytes)
      expect(binary[20], 7);
    });

    test('JSON packet serialization matches expected format', () {
      const state = NavigationState(
        speedKmh: 54.0,
        heading: 180.0,
        remainingDistanceMeters: 3500,
        remainingDurationSeconds: 480,
        maneuver: 'LEFT',
        maneuverText: 'Indiranagar 100ft Rd',
        maneuverDistanceMeters: 150,
        navigationStatus: 'NAVIGATING',
      );

      final packet = BleNavigationPacket.fromState(state);
      final json = packet.toJsonString();

      expect(json, contains('"type":"NAVUPDATE"'));
      expect(json, contains('"maneuver":"LEFT"'));
      expect(json, contains('"maneuverDistance":150'));
      expect(json, contains('"speed":54'));
    });
  });

  group('NavigationState Formatting Tests', () {
    test('Formats distance, ETA, and arrival clock time accurately', () {
      const state = NavigationState(
        remainingDistanceMeters: 4250,
        maneuverDistanceMeters: 320,
        remainingDurationSeconds: 720,
      );

      expect(state.remainingDistanceFormatted, '4.3 km');
      expect(state.maneuverDistanceFormatted, '320 m');
      expect(state.remainingDurationFormatted, '12 min');
    });
  });
}
