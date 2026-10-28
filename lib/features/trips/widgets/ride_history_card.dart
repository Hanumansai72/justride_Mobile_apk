import 'package:flutter/material.dart';
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    );
  }
}
