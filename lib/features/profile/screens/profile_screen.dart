import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../widgets/profile_header.dart';

import '../widgets/profile_card.dart';
import '../widgets/profile_menu_item.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final int _navIndex = 3; // Profile is index 3
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getProfile();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success && res.data != null) {
          _user = res.data;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const ProfileHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchProfile,
                      color: AppColors.primary,
                      backgroundColor: AppColors.surface,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        children: [
                          ProfileCard(user: _user),
                          const SizedBox(height: AppConstants.spacingXl),
                          _buildMenuSection(),
                          const SizedBox(height: AppConstants.spacingXl),
                          _buildLogoutButton(),
                          const SizedBox(height: AppConstants.spacingXxl),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 3) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushReplacementNamed('/places');
          } else if (i == 2) {
            Navigator.of(context).pushReplacementNamed('/device');
          }
        },
      ),
    );
  }



  Widget _buildMenuSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ProfileMenuItem(
            icon: Icons.bluetooth_rounded,
            title: 'My Devices',
            subtitle: 'View and manage your JustRide devices',
            onTap: () => Navigator.of(context).pushNamed('/device'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.tune_rounded,
            title: 'Display & Device Settings',
            subtitle: 'Speedometer customization & telemetry settings',
            onTap: () => Navigator.of(context).pushNamed('/device-settings'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.notifications_outlined,
            title: 'Notifications & Alerts',
            subtitle: 'Firmware updates, device status alerts',
            onTap: () => Navigator.of(context).pushNamed('/notifications'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.confirmation_number_outlined,
            title: 'My Support Tickets',
            subtitle: 'Track active and resolved issue requests',
            onTap: () => Navigator.of(context).pushNamed('/my-tickets'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.headset_mic_outlined,
            title: 'Help & Support',
            subtitle: 'FAQs, report problems and connect with support',
            onTap: () => Navigator.of(context).pushNamed('/help'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.manage_accounts_outlined,
            title: 'Account Settings',
            subtitle: 'Profile security, password & preferences',
            onTap: () => Navigator.of(context).pushNamed('/profile-settings'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.info_outline_rounded,
            title: 'About JustRide',
            subtitle: 'App version, terms and privacy policy',
            trailing: Text('v1.2.3', style: AppTextStyles.bodySmall),
            onTap: () => Navigator.of(context).pushNamed('/about'),
          ),
        ],
      ),
    );
  }


  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
      child: OutlinedButton(
        onPressed: () {
          Navigator.of(context).pushNamed('/login');
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: Color(0xFF3D1616)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          backgroundColor: const Color(0xFF1A0A0A),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, size: 20),
            const SizedBox(width: 8),
            Text('Log Out', style: AppTextStyles.labelLarge.copyWith(color: AppColors.error)),
          ],
        ),
      ),
    );
  }
}
