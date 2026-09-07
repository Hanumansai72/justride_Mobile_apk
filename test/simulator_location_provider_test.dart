import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/models/simulated_location_packet.dart';
import 'package:justride_ui/core/services/location_service.dart';

void main() {
  group('Simulator Location Provider & Packet Tests', () {
    test('SimulatedLocationPacket parses JSON and converts to valid Position', () {
      final json = {
        'type': 'SIM_LOCATION',
        'timestamp': 1757160000000,
        'latitude': 17.437012,
        'longitude': 78.580045,
        'speedKmh': 45.0,
        'bearing': 90.0,
        'accuracy': 2.5,
        'routeProgress': 0.15,
        'distanceRemaining': 5400.0,
        'maneuver': 'TURN_RIGHT',
        'maneuverDistance': 120.0,
        'nextRoad': 'Chengicherla Rd',
        'destinationReached': false,
        'gpsAvailable': true,
        'simStatus': 'RUNNING'
      };

      final packet = SimulatedLocationPacket.fromJson(json);
      expect(packet.latitude, 17.437012);
      expect(packet.longitude, 78.580045);
      expect(packet.speedKmh, 45.0);
      expect(packet.bearing, 90.0);
      expect(packet.maneuver, 'TURN_RIGHT');
      expect(packet.maneuverDistance, 120.0);

      final pos = packet.toPosition();
      expect(pos.latitude, 17.437012);
      expect(pos.longitude, 78.580045);
      expect(pos.heading, 90.0);
      expect(pos.speed, closeTo(12.5, 0.01)); // 45 km/h = 12.5 m/s
      expect(pos.accuracy, 2.5);
    });

    test('LocationService toggles location sources cleanly', () {
      final loc = LocationService.instance;
      expect(loc.locationSource, LocationSource.realGps);

      loc.setLocationSource(LocationSource.simulator);
      expect(loc.locationSource, LocationSource.simulator);

      loc.setLocationSource(LocationSource.realGps);
      expect(loc.locationSource, LocationSource.realGps);
    });
  });
}
