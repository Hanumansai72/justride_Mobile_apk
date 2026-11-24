import 'package:flutter/foundation.dart';
import '../../../core/services/offline_touring_service.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/services/ride_history_service.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/models/destination.dart';
import '../../../core/models/navigation_session.dart';
import '../../navigation/widgets/destination_confirm_sheet.dart';
import '../../community/community_explore_screen.dart';

class RideHistoryCard extends StatelessWidget {
  const RideHistoryCard({super.key, required this.ride});
  final NavigationSession ride;

  @override
  Widget build(BuildContext context) {
    final dateText = _dateTime(context, ride.startTime);
    return InkWell(
        onTap: () async {
          final history = RideHistoryService.instance;
          final owner = await history.currentUserId() ?? 'guest';
          try {
            final points = await history.readTrail(owner, ride.sessionId);
            if (!context.mounted ||
                owner != (await history.currentUserId() ?? 'guest')) return;
            if (!context.mounted) return;
            final cleanPoints = _cleanTrail(points);
            await showModalBottomSheet<void>(
                context: context,
                builder: (sheetContext) => SafeArea(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                              '${_place(ride.origin, start: true)} → ${_place(ride.destination)}',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.headingSmall),
                          const SizedBox(height: 12),
                          Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _historyMetric('Distance',
                                    '${ride.distanceKm.toStringAsFixed(1)} km'),
                                _historyMetric('Duration',
                                    '${(ride.durationSeconds / 60).round()} min'),
                                _historyMetric('Average',
                                    '${ride.averageSpeedKmh.toStringAsFixed(1)} km/h'),
                                _historyMetric('Top speed',
                                    '${ride.maxSpeedKmh.toStringAsFixed(1)} km/h'),
                              ]),
                          const SizedBox(height: 8),
                          Text('Started ${_dateTime(context, ride.startTime)}',
                              style: AppTextStyles.bodySmall),
                          if (ride.endTime != null)
                            Text('Ended ${_dateTime(context, ride.endTime!)}',
                                style: AppTextStyles.bodySmall),
                          const SizedBox(height: 16),
                          if (!ride.isMeaningfulRide || cleanPoints.length < 2)
                            const Text(
                                'No reliable GPS trail was recorded for this ride.')
                          else
                            SizedBox(
                                height: 200,
                                width: double.infinity,
                                child: CustomPaint(
                                    painter: _TrailPainter(cleanPoints))),
                          if (ride.destination != null &&
                              _hasCoordinates(ride.destination!))
                            FilledButton.icon(
                              icon: const Icon(Icons.navigation_outlined),
                              label:
                                  const Text('Navigate to destination again'),
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                DestinationConfirmSheet.show(
                                    context, ride.destination!);
                              },
                            ),
                          if (ride.status == 'completed')
                            TextButton.icon(
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Write a ride experience'),
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                Navigator.of(context)
                                    .push(MaterialPageRoute<bool>(
                                  builder: (_) =>
                                      CommunityExperienceEditor(ride: ride),
                                ));
                              },
                            ),
                          if (!kIsWeb &&
                              ride.isMeaningfulRide &&
                              cleanPoints.length >= 3)
                            TextButton.icon(
                              icon: const Icon(Icons.offline_pin_outlined),
                              label: const Text('Save for offline touring'),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  final pack = OfflineTouringPack.fromTrail(
                                      ride, cleanPoints);
                                  await OfflineTouringService.save(owner, pack);
                                  if (!context.mounted) return;
                                  Navigator.pop(sheetContext);
                                  messenger.showSnackBar(const SnackBar(
                                      content: Text(
                                          'Saved in Ride tools → Offline touring')));
                                } on FormatException catch (error) {
                                  if (context.mounted)
                                    messenger.showSnackBar(
                                        SnackBar(content: Text(error.message)));
                                } catch (_) {
                                  if (context.mounted)
                                    messenger.showSnackBar(const SnackBar(
                                        content: Text(
                                            'Could not save the offline track.')));
                                }
                              },
                            ),
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
            Text('From ${_place(ride.origin, start: true)}',
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 6, children: [
              Text('${ride.distanceKm.toStringAsFixed(1)} km',
                  style: AppTextStyles.labelLarge),
              Text('${(ride.durationSeconds / 60).ceil()} min',
                  style: AppTextStyles.labelLarge),
              Text('Avg ${ride.averageSpeedKmh.toStringAsFixed(1)} km/h',
                  style: AppTextStyles.labelLarge),
              Text('Max ${ride.maxSpeedKmh.toStringAsFixed(1)} km/h',
                  style: AppTextStyles.labelLarge),
              Text(ride.status == 'stopped' ? 'Ended early' : 'Completed',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.primary)),
            ]),
            const SizedBox(height: 10),
            Text('Started $dateText', style: AppTextStyles.bodySmall),
            if (ride.endTime != null)
              Text('Ended ${_dateTime(context, ride.endTime!)}',
                  style: AppTextStyles.bodySmall),
            if (ride.destination != null && _hasCoordinates(ride.destination!))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      DestinationConfirmSheet.show(context, ride.destination!),
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navigate to this destination again'),
                ),
              ),
          ]),
        ));
  }
}

String _place(Destination? place, {bool start = false}) {
  if (place == null) {
    return start ? 'Starting point not recorded' : 'Destination not recorded';
  }
  if (start &&
      (place.name == 'Start' || place.name?.trim().isEmpty == true) &&
      _hasCoordinates(place)) {
    return 'Start · ${place.latitude.toStringAsFixed(4)}, ${place.longitude.toStringAsFixed(4)}';
  }
  return place.displayTitle;
}

Widget _historyMetric(String label, String value) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.bodySmall),
        const SizedBox(height: 3),
        Text(value, style: AppTextStyles.labelLarge),
      ],
    );

String _dateTime(BuildContext context, DateTime value) {
  final date = value.toLocal();
  return '${MaterialLocalizations.of(context).formatMediumDate(date)} · ${TimeOfDay.fromDateTime(date).format(context)}';
}

bool _hasCoordinates(Destination destination) =>
    destination.latitude.isFinite &&
    destination.longitude.isFinite &&
    destination.latitude.abs() <= 90 &&
    destination.longitude.abs() <= 180 &&
    (destination.latitude != 0 || destination.longitude != 0);

List<Map<String, dynamic>> _cleanTrail(List<Map<String, dynamic>> points) {
  final clean = <Map<String, dynamic>>[];
  var breakNext = true;
  for (final raw in points) {
    final lat = raw['lat'], lon = raw['lon'];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lon < -180 ||
        lon > 180 ||
        (raw['accuracy'] is num && (raw['accuracy'] as num) > 35)) {
      breakNext = true;
      continue;
    }
    var segment = breakNext || raw['segment'] == true || clean.isEmpty;
    if (clean.isNotEmpty && !segment) {
      final previous = clean.last;
      final priorAt = DateTime.tryParse(previous['at']?.toString() ?? '');
      final currentAt = DateTime.tryParse(raw['at']?.toString() ?? '');
      if (priorAt != null && currentAt != null) {
        final seconds = currentAt.difference(priorAt).inMilliseconds / 1000;
        final meters = Geolocator.distanceBetween(
            (previous['lat'] as num).toDouble(),
            (previous['lon'] as num).toDouble(),
            lat.toDouble(),
            lon.toDouble());
        if (seconds <= 0 || meters / seconds > 55) {
          segment = true;
        } else if (meters < 7) {
          continue;
        }
      }
    }
    clean.add({...raw, 'segment': segment});
    breakNext = false;
  }
  return clean;
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
