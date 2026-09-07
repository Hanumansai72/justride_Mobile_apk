import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/models/navigation_state.dart';
import 'package:justride_ui/core/models/ble_navigation_packet.dart';
import 'package:justride_ui/core/utils/maps_url_parser.dart';
import 'package:justride_ui/core/utils/maneuver_mapper.dart';

void main() {
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

    test('Parses Indian regional languages from instruction text correctly', () {
      // Assamese / Bengali (from real-world screenshot: The Hunger's Spotত বাওঁফালে ঘূৰক)
      expect(
          ManeuverMapper.toJustRideManeuver(null, "The Hunger's Spotত বাওঁফালে ঘূৰক"),
          'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver(null, "Dad houseত সোঁফালে ঘূৰক"),
          'RIGHT');
      // Hindi
      expect(
          ManeuverMapper.toJustRideManeuver(null, "एमजी रोड पर बाएं मुड़ें"),
          'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver(null, "ब्रिगेड रोड पर दाएं मुड़ें"),
          'RIGHT');
      // Telugu
      expect(
          ManeuverMapper.toJustRideManeuver(null, "ఎడమవైపు తిరగండి"),
          'LEFT');
      expect(
          ManeuverMapper.toJustRideManeuver(null, "కుడివైపు తిరగండి"),
          'RIGHT');
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
