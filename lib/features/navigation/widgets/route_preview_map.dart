import '../../../core/services/offline_touring_service.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/constants/google_maps_config.dart';
import '../../../core/services/google_maps_service.dart';

const _unknownTraffic = Color(0xFFBBC3BD);

const _trafficColors = {
  RouteTrafficSpeed.normal: AppColors.primary,
  RouteTrafficSpeed.slow: Color(0xFFFFA041),
  RouteTrafficSpeed.jam: Color(0xFFFF5252),
};

Set<Polyline> selectedRoutePolylines(NavigationRoute route, {required int width}) => {
      Polyline(
        polylineId: const PolylineId('selected_route'),
        points: route.polylinePoints,
        color: route.provider == 'google' || route.trafficSections.isNotEmpty
            ? _unknownTraffic
            : AppColors.primary,
        width: width,
        zIndex: 1,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      for (final (index, section) in route.trafficSections.indexed)
        Polyline(
          polylineId: PolylineId('traffic_$index'),
          points: section.points,
          color: _trafficColors[section.speed]!,
          width: width,
          zIndex: 2,
          jointType: JointType.round,
        ),
    };

class RouteTrafficLegend extends StatelessWidget {
  const RouteTrafficLegend({super.key, required this.route});
  final NavigationRoute route;

  @override
  Widget build(BuildContext context) {
    if (route.provider != 'google' && route.trafficSections.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: route.trafficSections.isEmpty
          ? const Text('Traffic data unavailable')
          : Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final (label, color) in [
                  ('Clear', _trafficColors[RouteTrafficSpeed.normal]!),
                  ('Slow', _trafficColors[RouteTrafficSpeed.slow]!),
                  ('Heavy', _trafficColors[RouteTrafficSpeed.jam]!),
                  ('Unknown', _unknownTraffic),
                ])
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 9, color: color),
                      const SizedBox(width: 4),
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// Preview the actual provider route. Offline map tiles fall back to its geometry.
class RoutePreviewMap extends StatelessWidget {
  const RoutePreviewMap({
    super.key,
    required this.route,
    this.alternatives = const [],
    this.height = 190,
  });
  final NavigationRoute route;
  final List<NavigationRoute> alternatives;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = route.polylinePoints;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
          height: height,
          child: ColoredBox(
            color: AppColors.backgroundInset,
            child: points.isEmpty ||
                    route.provider == OfflineTouringPack.provider ||
                    !GoogleMapsConfig.hasApiKey
                ? InteractiveViewer(
                    maxScale: 5,
                    child: CustomPaint(
                        painter: _RoutePainter(points), size: Size.infinite),
                  )
                : GoogleMap(
                    style:
                        '[{"elementType":"geometry","stylers":[{"color":"#151917"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#BBC3BD"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#151917"}]},{"featureType":"road","elementType":"geometry","stylers":[{"color":"#27322B"}]}]',
                    initialCameraPosition:
                        CameraPosition(target: points.first, zoom: 13),
                    onMapCreated: (controller) async {
                      double south = points.first.latitude, north = south;
                      double west = points.first.longitude, east = west;
                      for (final p in [
                        ...points,
                        for (final option in alternatives)
                          ...option.polylinePoints,
                      ]) {
                        south = math.min(south, p.latitude);
                        north = math.max(north, p.latitude);
                        west = math.min(west, p.longitude);
                        east = math.max(east, p.longitude);
                      }
                      if (north - south > 0.00001 || east - west > 0.00001) {
                        await controller.moveCamera(
                            CameraUpdate.newLatLngBounds(
                                LatLngBounds(
                                    southwest: LatLng(south, west),
                                    northeast: LatLng(north, east)),
                                32));
                      }
                    },
                    polylines: {
                      for (final (index, option) in alternatives.indexed)
                        if (!identical(option, route))
                          Polyline(
                            polylineId: PolylineId('alternative_$index'),
                            points: option.polylinePoints,
                            color: const Color(0xFF8A98AA),
                            width: 5,
                          ),
                      ...selectedRoutePolylines(route, width: 6),
                    },
                    markers: {
                      Marker(
                          markerId: const MarkerId('start'),
                          position: points.first),
                      Marker(
                          markerId: const MarkerId('destination'),
                          position: points.last),
                    },
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                          EagerGestureRecognizer.new),
                    },
                    zoomControlsEnabled: true,
                    myLocationButtonEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                  ),
          )),
    );
  }
}

class RecordedTrackMap extends StatelessWidget {
  const RecordedTrackMap({super.key, required this.route, required this.rider});
  final NavigationRoute route;
  final LatLng rider;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: AppColors.backgroundInset,
      child: CustomPaint(
          painter: _RoutePainter(route.polylinePoints, rider: rider),
          size: Size.infinite));
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.points, {this.rider});
  final LatLng? rider;
  final List<LatLng> points;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final latitude = points.first.latitude * math.pi / 180;
    final projected = points
        .map((p) => Offset(p.longitude * math.cos(latitude), -p.latitude))
        .toList();
    final bounds = projected.skip(1).fold(
        Rect.fromLTWH(projected.first.dx, projected.first.dy, 0, 0),
        (box, p) => box.expandToInclude(Rect.fromLTWH(p.dx, p.dy, 0, 0)));
    final scale = math.min((size.width - 64) / math.max(bounds.width, 0.00001),
        (size.height - 48) / math.max(bounds.height, 0.00001));
    Offset place(Offset p) =>
        (p - bounds.center) * scale + Offset(size.width / 2, size.height / 2);
    final path = Path()
      ..moveTo(place(projected.first).dx, place(projected.first).dy);
    for (final p in projected.skip(1)) {
      final q = place(p);
      path.lineTo(q.dx, q.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.primary
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(
        place(projected.first), 6, Paint()..color = AppColors.textPrimary);
    canvas.drawCircle(
        place(projected.last), 7, Paint()..color = AppColors.primary);
    canvas.drawCircle(
        place(projected.last), 3, Paint()..color = AppColors.background);
    if (rider case final position?) {
      final marker = place(
          Offset(position.longitude * math.cos(latitude), -position.latitude));
      if ((Offset.zero & size).contains(marker)) {
        canvas.drawCircle(marker, 8, Paint()..color = AppColors.textPrimary);
        canvas.drawCircle(marker, 5, Paint()..color = AppColors.primary);
      }
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.points != points || old.rider != rider;
}
