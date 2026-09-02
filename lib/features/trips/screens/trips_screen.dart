import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../models/trip_model.dart';
import '../widgets/trips_tab_bar.dart';
import '../widgets/overview_card.dart';
import '../widgets/streak_banner.dart';
import '../widgets/trip_card.dart';
import '../widgets/insights_banner.dart';

/// Trips screen — ride history, overview stats, streak, and insights.
class TripsScreen extends StatefulWidget {
  const TripsScreen({super.key});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  int _navIndex = 1; // Trips is index 1

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _TripsAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 1) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 2) {
            Navigator.of(context).pushNamed('/pair-device');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/notifications');
          } else if (i == 4) {
            Navigator.of(context).pushReplacementNamed('/profile');
          }
        },
      ),


    );
  }

  Widget _buildBody() {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

        // ── Tab bar ───────────────────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: TripsTabBar()),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

        // ── Overview stats card ───────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: OverviewCard()),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

        // ── Streak banner ─────────────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: StreakBanner(streakDays: 7)),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingXl)),

        // ── Recent Trips header ───────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent Trips', style: AppTextStyles.headingMedium),
                GestureDetector(
                  onTap: () {},
                  child: Text('View all', style: AppTextStyles.accentMedium),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

        // ── Trip cards list ───────────────────────────────────────────────────
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => TripCard(trip: TripModel.dummyTrips[i]),
              childCount: TripModel.dummyTrips.length,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

        // ── Trip Insights banner ──────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: InsightsBanner()),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingSection)),
      ],
    );
  }
}

// ── Custom AppBar ─────────────────────────────────────────────────────────────

class _TripsAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top,
        left: AppConstants.pagePadding,
        right: AppConstants.pagePadding,
        bottom: AppConstants.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Trips', style: AppTextStyles.headingLarge),
                Text(
                  'Your ride history and insights',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          // Filter icon button
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.filter_list_rounded,
                  color: AppColors.textSecondary, size: 20),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
