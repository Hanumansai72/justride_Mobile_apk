import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/services/ride_history_service.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/navigation_session.dart';

class RideHistoryCard extends StatelessWidget {
  const RideHistoryCard({super.key, required this.ride});
  final NavigationSession ride;

  @override
  Widget build(BuildContext context) {
    final date = (ride.endTime ?? ride.startTime).toLocal();
    final dateText =
        '${MaterialLocalizations.of(context).formatMediumDate(date)} · '
        '${TimeOfDay.fromDateTime(date).format(context)}';
    return InkWell(
        onTap: () async {
          final history = RideHistoryService.instance;
          final owner = await history.currentUserId() ?? 'guest';
          try {
            final points = await history.readTrail(owner, ride.sessionId);
            if (!context.mounted ||
                owner != (await history.currentUserId() ?? 'guest')) return;
            if (!context.mounted) return;
            await showModalBottomSheet<void>(
                context: context,
                builder: (context) => SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(ride.summary, textAlign: TextAlign.center),
                          Text(
                              'Average ${ride.averageSpeedKmh.toStringAsFixed(1)} km/h'),
                          const SizedBox(height: 16),
                          if (points.length < 2)
                            const Text(
                                'GPS trail unavailable for this journey.')
                          else
                            SizedBox(
                                height: 240,
                                width: double.infinity,
                                child: CustomPaint(
                                    painter: _TrailPainter(points))),
                          const Text(
                              'Recorded GPS trail · gaps are left unconnected'),
                        ]))));
          } catch (_) {
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Could not read the saved GPS trail.')));
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(16),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.route_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(ride.destination?.displayTitle ?? 'Destination',
                      style: AppTextStyles.headingSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            Text('From ${ride.origin?.displayTitle ?? 'Start'}',
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 6, children: [
              Text('${ride.distanceKm.toStringAsFixed(1)} km',
                  style: AppTextStyles.labelLarge),
              Text('${(ride.durationSeconds / 60).ceil()} min',
                  style: AppTextStyles.labelLarge),
              Text(ride.status == 'stopped' ? 'Ended early' : 'Completed',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primary)),
            ]),
            const SizedBox(height: 10),
            Text(dateText, style: AppTextStyles.bodySmall),
          ]),
        ));
  }
}

class _TrailPainter extends CustomPainter {
  final List<Map<String, dynamic>> points;
  _TrailPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final valid = points
        .where((p) =>
            p['lat'] is num &&
            p['lon'] is num &&
            (p['lat'] as num).isFinite &&
            (p['lon'] as num).isFinite)
        .toList();
    if (valid.length < 2) return;
    final latitude = (valid.first['lat'] as num).toDouble();
    final factor = math.cos(latitude * math.pi / 180).abs().clamp(.01, 1.0);
    final xs = valid.map((p) => (p['lon'] as num).toDouble() * factor).toList();
    final ys = valid.map((p) => -(p['lat'] as num).toDouble()).toList();
    final minX = xs.reduce(math.min), minY = ys.reduce(math.min);
    final spanX = math.max(xs.reduce(math.max) - minX, .000001);
    final spanY = math.max(ys.reduce(math.max) - minY, .000001);
    final scale =
        math.min((size.width - 24) / spanX, (size.height - 24) / spanY);
    final path = Path();
    for (var i = 0; i < valid.length; i++) {
      final x = (size.width - spanX * scale) / 2 + (xs[i] - minX) * scale;
      final y = (size.height - spanY * scale) / 2 + (ys[i] - minY) * scale;
      if (i == 0 || valid[i]['segment'] == true) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = AppColors.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) =>
      oldDelegate.points != points;
}
