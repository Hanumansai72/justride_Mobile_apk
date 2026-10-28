import '../../../core/services/app_update_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/ride_history_service.dart';
import '../../../core/network/api_client.dart';
import '../../trips/widgets/ride_history_card.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../device/screens/device_pairing_screen.dart';

import '../../../core/services/share_service.dart';
import '../../../core/services/bluetooth_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../../../shared/widgets/hardware_prompt_sheet.dart';
import '../../navigation/widgets/destination_confirm_sheet.dart';

import '../widgets/app_header.dart';

import '../../navigation/widgets/voice_assistant_sheet.dart';
import '../widgets/device_card.dart';
import '../widgets/active_navigation_dashboard_card.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/quick_shortcuts.dart';
import '../widgets/stats_row.dart';

/// Main dashboard screen — the entry point of the JustRide app.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final int _navIndex = 0;
  UserModel? _user;
  DeviceModel? _device;
  bool _isLoading = true;
  Timer? _statusPollTimer;
  bool _isHardwareSheetShowing = false;
  AppReleaseModel? _latestRelease;
  late Future<ApiResponse<RideHistoryPage>> _historyFuture;

  void _reloadHistory() {
    if (mounted) {
      setState(() {
        _historyFuture = RideHistoryService.instance.getPage(limit: 1);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    RideHistoryService.instance.changed.addListener(_reloadHistory);
    _checkAppRelease();
    // Periodically verify device status with backend every 20s
    _statusPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _device != null) {
        _verifyDeviceStatus();
      }
    });

    // Listen for destinations shared from Google Maps while user is on Dashboard
    ShareService.instance.destinationSharedNotifier
        .addListener(_onDestinationShared);

    // Listen to Bluetooth adapter changes; if Bluetooth is off, prompt user immediately
    JustRideBleService.instance.adapterStateNotifier
        .addListener(_onBleStateChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onDestinationShared();
      _checkHardwareAndPrompt();
    });
  }

  void _onBleStateChanged() {
    final state = JustRideBleService.instance.adapterStateNotifier.value;
    if (state == BluetoothAdapterState.off &&
        mounted &&
        !_isHardwareSheetShowing) {
      _checkHardwareAndPrompt();
    }
  }

  Future<void> _checkHardwareAndPrompt() async {
    if (_isHardwareSheetShowing || !mounted) return;

    try {
      final btState = JustRideBleService.instance.adapterStateNotifier.value;
      final isBtOff = btState != BluetoothAdapterState.on;

      final isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      final isGpsOff = !isGpsEnabled;

      if ((isBtOff || isGpsOff) && mounted) {
        _isHardwareSheetShowing = true;
        await HardwarePromptSheet.show(
          context,
          btOff: isBtOff,
          gpsOff: isGpsOff,
        );
        _isHardwareSheetShowing = false;
      }
    } catch (e) {
      debugPrint('[DashboardScreen] Hardware check error: $e');
      _isHardwareSheetShowing = false;
    }
  }

  void _onDestinationShared() {
    final dest = ShareService.instance.destinationSharedNotifier.value;
    if (dest != null && mounted) {
      final startLoc = ShareService.instance.currentSharedStartLocation;
      ShareService.instance.clearSharedDestination();
      DestinationConfirmSheet.show(context, dest, startLocation: startLoc);
    }
  }

  @override
  void dispose() {
    RideHistoryService.instance.changed.removeListener(_reloadHistory);
    JustRideBleService.instance.adapterStateNotifier
        .removeListener(_onBleStateChanged);
    ShareService.instance.destinationSharedNotifier
        .removeListener(_onDestinationShared);
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    unawaited(RideHistoryService.instance.syncPending());
    setState(() {
      _isLoading = true;
      _historyFuture = RideHistoryService.instance.getPage(limit: 1);
    });
    final (userRes, devRes) = await (
      BackendService.instance.getProfile(),
      BackendService.instance.getMyDevice(),
    ).wait;

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (userRes.success && userRes.data != null) {
          _user = userRes.data;
        }
        if ((devRes.success || devRes.isTransientFailure) &&
            devRes.data != null &&
            !devRes.data!.isBlocked) {
          _device = devRes.data;
        } else {
          _device = null;
        }
      });
      if (devRes.isTransientFailure) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(devRes.message)));
      }
    }
  }

  Future<void> _verifyDeviceStatus() async {
    final devRes = await BackendService.instance.getMyDevice();
    if (devRes.isTransientFailure) return;
    if (!mounted) return;
    setState(() {
      if (devRes.success && devRes.data != null && !devRes.data!.isBlocked) {
        _device = devRes.data;
      } else {
        _device = null;
      }
    });
  }

  Future<void> _checkAppRelease() async {
    if (!AppUpdateService.instance.verified)
      await AppUpdateService.instance.check();
    if (mounted)
      setState(() => _latestRelease = AppUpdateService.instance.hasUpdate
          ? AppUpdateService.instance.release
          : null);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // If no device is paired with this account, show the scan device radar page directly on Dashboard!
    if (_device == null) {
      return const DevicePairingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AppHeader(),
      body: RefreshIndicator(
        onRefresh: _fetchDashboardData,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: _buildBody(),
      ),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 0) return;
          if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 2) {
            Navigator.of(context).pushReplacementNamed('/device');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/profile');
          }
        },
      ),
    );
  }

  Widget _buildBody() {
    return CustomScrollView(
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
        // ── In-App Release Update Alert Banner ────────────────────────────
        if (_latestRelease != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppConstants.pagePadding,
              AppConstants.spacingSm,
              AppConstants.pagePadding,
              AppConstants.spacingSm,
            ),
            sliver: SliverToBoxAdapter(
              child: _buildReleaseNotificationBanner(),
            ),
          ),

        // ── "Where to?" header row ─────────────────────────────────────────
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                    child: Text(
                  _user != null && _user!.fullName.isNotEmpty
                      ? 'Hello, ${_user!.fullName.split(" ").first}'
                      : 'Where to?',
                  style: AppTextStyles.headingLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )),
                GestureDetector(
                  onTap: () => Navigator.of(context).pushNamed('/places'),
                  child: Row(
                    children: [
                      Text('View Map', style: AppTextStyles.accentMedium),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded,
                          color: AppColors.primary, size: 18),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.spacingMd)),

        // ── Route planner entry ───────────────────────────────────────────
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(
            child: SearchBarWidget(
              onTap: () => Navigator.of(context).pushNamed('/go'),
              onMicTap: () => VoiceAssistantSheet.show(context),
            ),
          ),
        ),

        const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.spacingMd)),

        // ── Quick shortcuts ───────────────────────────────────────────────
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: QuickShortcuts()),
        ),

        const SliverToBoxAdapter(
            child: SizedBox(height: AppConstants.spacingLg)),

        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: ActiveNavigationDashboardCard()),
        ),
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: _buildLatestRide()),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: DeviceCard(device: _device)),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),

        // ── Stats row ─────────────────────────────────────────────────────
        SliverPadding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
          sliver: SliverToBoxAdapter(child: StatsRow(device: _device)),
        ),

        // Bottom breathing room
        const SliverToBoxAdapter(
          child: SizedBox(height: AppConstants.spacingSection),
        ),
      ],
    );
  }

  Widget _buildLatestRide() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('Latest ride', style: AppTextStyles.headingSmall)),
            TextButton(
                onPressed: () => Navigator.of(context).pushNamed('/trips'),
                child: const Text('View history')),
          ]),
          const SizedBox(height: 4),
          FutureBuilder<ApiResponse<RideHistoryPage>>(
            future: _historyFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        LinearProgressIndicator(color: AppColors.primary));
              }
              final result = snapshot.data;
              if (result == null || !result.success || result.data == null) {
                return Row(children: [
                  Expanded(
                      child: Text('Could not load your latest ride.',
                          style: AppTextStyles.bodySmall)),
                  TextButton(
                      onPressed: _reloadHistory, child: const Text('Retry')),
                ]);
              }
              final rides = result.data!.items;
              if (rides.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                      'No rides yet. Your latest ride will appear here when navigation ends.',
                      style: AppTextStyles.bodyMedium),
                );
              }
              return RideHistoryCard(ride: rides.first);
            },
          ),
        ],
      );

  Widget _buildReleaseNotificationBanner() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(20)),
        child: Row(children: [
          const Icon(Icons.system_update_rounded, color: AppColors.primary),
          const SizedBox(width: 14),
          const Expanded(
              child: Text('A new app update is ready.',
                  style: TextStyle(fontWeight: FontWeight.w600))),
          TextButton(
              onPressed: () => Navigator.of(context).pushNamed('/app-update'),
              child: const Text('Update')),
        ]),
      );
}
