// Diagnostic reproductions of current gaps, not assertions of navigation correctness.
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:justride_ui/core/utils/maneuver_mapper.dart';
import 'package:justride_ui/core/utils/off_route_detector.dart';

void main() {
  test('current mapping loses ramp direction and flyover-specific instruction',
      () {
    expect(
        ManeuverMapper.toJustRideManeuver(
            'RAMP_LEFT', 'Take the flyover on the left'),
        'EXIT');
    expect(
        ManeuverMapper.toJustRideManeuver(
            'RAMP_RIGHT', 'Take the flyover on the right'),
        'EXIT');
  });
  test('left and right U-turns currently share one maneuver code', () {
    final left = ManeuverMapper.toJustRideManeuver('UTURN_LEFT');
    final right = ManeuverMapper.toJustRideManeuver('UTURN_RIGHT');
    expect(left, 'U_TURN');
    expect(right, left);
    expect(ManeuverMapper.toManeuverCode(right).value, 8);
  });
  test('roundabout exit currently matches roundabout before exit', () {
    expect(ManeuverMapper.toJustRideManeuver('ROUNDABOUT_EXIT'), 'ROUNDABOUT');
  });
  test('parallel road roughly 22m away remains in the 50m corridor', () {
    final detector = OffRouteDetector();
    final started = DateTime(2026, 11, 4);
    for (var i = 0; i < 8; i++) {
      expect(
          detector.update(
              riderPosition: const LatLng(12.005, 77.0002),
              speedMs: 10,
              accuracyMeters: 5,
              timestamp: started.add(Duration(seconds: i)),
              polylinePoints: const [LatLng(12, 77), LatLng(12.01, 77)]),
          OffRouteState.onRoute);
    }
  });
}
