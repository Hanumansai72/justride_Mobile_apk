import 'dart:async';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../widgets/device_info_card.dart';
import '../widgets/device_shortcuts.dart';
import '../widgets/device_action_tile.dart';
import '../widgets/device_health_card.dart';
import '../widgets/find_device_card.dart';
import 'device_pairing_screen.dart';

class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final int _navIndex = 2; // Device is index 2
  DeviceModel? _device;
  bool _isLoading = true;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    _fetchDevice();
    // Periodically verify device status with backend every 20s
    _statusPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _device != null) {
        _verifyDeviceStatus();
      }
    });
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDevice() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getMyDevice();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success && res.data != null) {
          _device = res.data;
        } else {
          _device = null;
          if (res.errors?['reason'] == 'DEVICE_BLOCKED' || res.message.contains('blocked')) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.error,
                duration: const Duration(seconds: 5),
                content: Row(
                  children: [
                    const Icon(Icons.block_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        res.message.isNotEmpty
                            ? res.message
                            : 'Device has been blocked and disconnected.',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        }
      });
    }
  }

  Future<void> _verifyDeviceStatus() async {
    final res = await BackendService.instance.getMyDevice();
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _device = null;
      });
      if (res.errors?['reason'] == 'DEVICE_BLOCKED' || res.message.contains('blocked')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            content: Row(
              children: [
                const Icon(Icons.block_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    res.message.isNotEmpty
                        ? res.message
                        : 'Device has been blocked by administrator. Disconnected.',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } else {
      setState(() {
        _device = res.data;
      });
    }
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

    // If no device is connected or device is blocked, show the radar scanning/pairing screen
    if (_device == null) {
      return const DevicePairingScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _DeviceAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 2) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/profile');
          }
        },
      ),
    );
  }



  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _fetchDevice,
      color: AppColors.primary,
      backgroundColor: AppColors.surface,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Device Info Card (live backend data)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(
              child: DeviceInfoCard(
                deviceName: _device!.deviceName,
                batteryPercent: _device!.batteryLevel,
                hasUpdate: _device!.hasUpdateAvailable,
                firmwareVersion: _device!.firmwareVersion,
                newVersion: _device!.latestFirmwareVersion,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Device Shortcuts
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(child: DeviceShortcuts()),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Customize Screens
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(
              child: DeviceActionTile(
                icon: Icons.display_settings_rounded,
                title: 'Customize Screens',
                subtitle: 'Choose what to show on your device',
                onTap: () => Navigator.of(context).pushNamed('/display-customization'),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Device Settings
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(
              child: DeviceActionTile(
                icon: Icons.tune_rounded,
                title: 'Hardware & Audio Settings',
                subtitle: 'Brightness, HUD, volume and shift lights',
                onTap: () => Navigator.of(context).pushNamed('/device-settings'),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Device Health Card
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(child: DeviceHealthCard()),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingMd)),

          // Find Device Card
          const SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
            sliver: SliverToBoxAdapter(child: FindDeviceCard()),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: AppConstants.spacingSection)),
        ],
      ),
    );
  }
}

class _DeviceAppBar extends StatelessWidget implements PreferredSizeWidget {

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
                Text('Device', style: AppTextStyles.headingLarge),
                Text(
                  'Manage your JustRide device',
                  style: AppTextStyles.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/notifications'),
            icon: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => Navigator.of(context).pushNamed('/device-settings'),
            icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary, size: 24),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

