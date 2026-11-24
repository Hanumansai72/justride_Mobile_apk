import '../../../shared/widgets/device_connection_gate.dart';
import 'help_support_screen.dart';
import 'subscription_screen.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../widgets/profile_header.dart';

import '../widgets/profile_card.dart';
import '../widgets/profile_menu_item.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _user?.fullName ?? '');
    final phoneCtrl = TextEditingController(text: _user?.phone ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text(
            'Edit profile',
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textPrimary,
                      fontSize: 14),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textPrimary,
                      fontSize: 14),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      final res = await BackendService.instance.updateProfile(
                        name: nameCtrl.text.trim(),
                        phonenumber: phoneCtrl.text.trim(),
                      );
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                      }
                      if (!mounted) return;
                      if (res.success && res.data != null) {
                        setState(() => _user = res.data);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile updated successfully!'),
                            backgroundColor: AppColors.primaryContainer,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res.message),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Text('SAVE',
                      style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Text(
            'Change password',
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textPrimary,
                      fontSize: 14),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textPrimary,
                      fontSize: 14),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text',
                        color: AppColors.textSecondary),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (currentCtrl.text.isEmpty || newCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Please fill all fields')),
                        );
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      final res = await BackendService.instance.changePassword(
                        currentPassword: currentCtrl.text.trim(),
                        newPassword: newCtrl.text.trim(),
                      );
                      if (dialogCtx.mounted) {
                        Navigator.of(dialogCtx).pop();
                      }
                      if (!mounted) return;
                      if (res.success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Password changed successfully!'),
                            backgroundColor: AppColors.primaryContainer,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(res.message),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onPrimary,
                      ),
                    )
                  : Text('UPDATE',
                      style: TextStyle(
                          fontFamily: 'Stack Sans Text',
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog() {
    Navigator.of(context).pushNamed('/delete-account');
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
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
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
                          ProfileCard(
                            user: _user,
                            onEdit: _showEditProfileDialog,
                          ),
                          const SizedBox(height: AppConstants.spacingMd),
                          _buildAccountActionsSection(),
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
    );
  }

  Widget _buildAccountActionsSection() {
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
            icon: Icons.edit_note_rounded,
            title: 'Edit profile',
            subtitle: 'Update your name and phone number',
            onTap: _showEditProfileDialog,
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.lock_reset_rounded,
            title: 'Change password',
            subtitle: 'Update your login password and security',
            onTap: _showChangePasswordDialog,
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.delete_forever_outlined,
            title: 'Delete account',
            subtitle: 'Permanently remove your account and data',
            onTap: _showDeleteAccountDialog,
          ),
        ],
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
            icon: Icons.tune_rounded,
            title: 'Device settings',
            subtitle: 'Display and riding preferences',
            onTap: () => Navigator.of(context).pushNamed('/device-settings'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscription',
            subtitle: 'View your plan and Premium access',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const SubscriptionScreen())),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.confirmation_number_outlined,
            title: 'Support requests',
            subtitle: 'Track active and resolved issue requests',
            onTap: () => Navigator.of(context).pushNamed('/my-tickets'),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.headset_mic_outlined,
            title: 'Help and support',
            subtitle: 'FAQs, report problems and connect with support',
            onTap: () => Navigator.of(context).push(DevicePageRoute(
                builder: (_) =>
                    const HelpSupportScreen(initialCategory: 'Account'))),
          ),
          const Divider(color: AppColors.divider, height: 1, indent: 56),
          ProfileMenuItem(
            icon: Icons.info_outline_rounded,
            title: 'About JustRide',
            subtitle: 'App version, terms and privacy policy',
            trailing:
                Text(AppConstants.appVersion, style: AppTextStyles.bodySmall),
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
          foregroundColor: AppColors.errorText,
          side: const BorderSide(color: AppColors.errorSurface),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMd)),
          backgroundColor: AppColors.errorSurface,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, size: 20),
            const SizedBox(width: 8),
            Text('Sign out',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.errorText)),
          ],
        ),
      ),
    );
  }
}
