import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/models/destination.dart';
import 'package:justride_ui/core/models/navigation_session.dart';
import 'package:justride_ui/core/services/fuel_stop_service.dart';
import 'package:justride_ui/core/services/offline_touring_service.dart';
import 'package:justride_ui/core/services/ride_planning_store.dart';

void main() {
  test('style buffers and reserve reduce the usable range', () {
    double range(FuelRidingStyle style, double fuel) => plannedFuelRangeKm(
        baseKmPerLitre: 40, litres: fuel, reserveLitres: 1, style: style);
    expect(range(FuelRidingStyle.steady, 5), 160);
    expect(range(FuelRidingStyle.mixed, 5), 144);
    expect(range(FuelRidingStyle.heavy, 5), 120);
    expect(range(FuelRidingStyle.heavy, .5), 0);
  });

  test(
      'commute stores lookup labels and place IDs, not downloaded route points',
      () {
    final saved = SavedCommute.fromJson(const SavedCommute(
      destination: Destination(
          name: 'Work', latitude: 17.43, longitude: 78.41, placeId: 'place-id'),
    ).toJson());
    expect(saved.destination.name, 'Work');
    expect(saved.destination.placeId, 'place-id');
    expect(saved.destination.latitude, 0);
    expect(saved.destination.longitude, 0);
  });

  test('offline pack round trips and rejects gaps instead of inventing roads',
      () {
    final start = DateTime.utc(2026, 11, 23);
    final ride = NavigationSession(
      sessionId: 'local_ride',
      startTime: start,
      durationSeconds: 15,
      destination:
          const Destination(name: 'End', latitude: 17.4012, longitude: 78.5),
    );
    final trail = [
      for (var i = 0; i < 4; i++)
        {
          'lat': 17.4 + i * .0004,
          'lon': 78.5,
          'at': start.add(Duration(seconds: i * 5)).toIso8601String(),
          'segment': i == 0
        },
    ];
    final pack = OfflineTouringPack.fromJson(
        OfflineTouringPack.fromTrail(ride, trail).toJson());
    expect(pack.toRoute().provider, OfflineTouringPack.provider);
    expect(pack.distanceMeters, greaterThan(100));
    expect(pack.canStartAt(const LatLng(17.4, 78.5), resuming: false), isTrue);
    expect(pack.canStartAt(const LatLng(17.42, 78.5), resuming: true), isFalse);
    trail[2]['segment'] = true;
    expect(
        () => OfflineTouringPack.fromTrail(ride, trail), throwsFormatException);
  });
}
