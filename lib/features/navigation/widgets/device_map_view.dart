import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/maps_loader_stub.dart'
    if (dart.library.js_interop) '../../../core/constants/maps_loader_web.dart'
    as maps_loader;
import '../../../core/constants/device_map_config.dart';
import '../../../core/models/device_map_frame.dart';
import '../../../core/models/navigation_state.dart';
import '../../../core/services/device_map_service.dart';

class DeviceMapView extends StatelessWidget {
  final NavigationState state;
  const DeviceMapView({super.key, required this.state});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 175, 65, 190),
        child: Column(children: [
          Expanded(
              child: Center(
                  child: ValueListenableBuilder<DeviceMapFrame?>(
            valueListenable: DeviceMapService.instance.frame,
            builder: (context, frame, _) => frame == null
                ? const Text('Waiting for map', textAlign: TextAlign.center)
                : AspectRatio(
                    aspectRatio: DeviceMapConfig.width / DeviceMapConfig.height,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(frame.png,
                          gaplessPlayback: true,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium),
                      if (state.gpsAvailable)
                        CustomPaint(
                            painter: _RiderPainter(
                                mapPixel(
                                    LatLng(state.currentLatitude,
                                        state.currentLongitude),
                                    frame.center,
                                    frame.zoom),
                                state.heading)),
                    ])),
          ))),
          ValueListenableBuilder<String>(
              valueListenable: DeviceMapService.instance.status,
              builder: (context, value, _) =>
                  Text(value, style: const TextStyle(fontSize: 11))),
          const TextButton(
              onPressed: maps_loader.openAttribution,
              child: Text('Search by LocationIQ.com',
                  style: TextStyle(fontSize: 11))),
        ]),
      );
}

class _RiderPainter extends CustomPainter {
  final Offset point;
  final double heading;
  const _RiderPainter(this.point, this.heading);
  @override
  void paint(Canvas canvas, Size size) {
    if (point.dx < 10 ||
        point.dx > DeviceMapConfig.width - 10 ||
        point.dy < 10 ||
        point.dy > DeviceMapConfig.height - 28) {
      return;
    }
    canvas.scale(size.width / DeviceMapConfig.width,
        size.height / DeviceMapConfig.height);
    canvas.translate(point.dx, point.dy);
    canvas.rotate(heading * math.pi / 180);
    canvas.drawCircle(Offset.zero, 8, Paint()..color = Colors.white);
    canvas.drawPath(
        Path()
          ..moveTo(0, -8)
          ..lineTo(6, 6)
          ..lineTo(0, 3)
          ..lineTo(-6, 6)
          ..close(),
        Paint()..color = const Color(0xff00d99b));
  }

  @override
  bool shouldRepaint(covariant _RiderPainter old) =>
      old.point != point || old.heading != heading;
}
