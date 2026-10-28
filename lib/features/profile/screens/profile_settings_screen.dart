import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const itemBg = AppColors.surfaceElevated;
  static const surfContLow = AppColors.backgroundInset;
  static const primary = AppColors.primary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
}

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  bool _metricUnits = true;
  bool _pushNotifications = true;
  final int _navIndex = 3; // Profile tab is index 3 in 4-tab bar

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
          backgroundColor: _C.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            side: const BorderSide(color: _C.cardBorder),
          ),
          title: Text(
            'Edit Profile',
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: _C.onSurface,
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
                      color: _C.onSurface,
                      fontSize: 14),
                  cursorColor: _C.primary,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text', color: _C.textSec),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneCtrl,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: _C.onSurface,
                      fontSize: 14),
                  cursorColor: _C.primary,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text', color: _C.textSec),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('CANCEL',
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text', color: _C.textSec)),
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
                      if (mounted) {
                        Navigator.of(dialogCtx).pop();
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
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.bg,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _C.bg),
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
          backgroundColor: _C.cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            side: const BorderSide(color: _C.cardBorder),
          ),
          title: Text(
            'Change Password',
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              color: _C.onSurface,
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
                      color: _C.onSurface,
                      fontSize: 14),
                  cursorColor: _C.primary,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text', color: _C.textSec),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      color: _C.onSurface,
                      fontSize: 14),
                  cursorColor: _C.primary,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    labelStyle: TextStyle(
                        fontFamily: 'Stack Sans Text', color: _C.textSec),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.outlineVariant),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: _C.primary),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('CANCEL',
                  style: TextStyle(
                      fontFamily: 'Stack Sans Text', color: _C.textSec)),
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
                      if (mounted) {
                        Navigator.of(dialogCtx).pop();
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
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.primary,
                foregroundColor: _C.bg,
              ),
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _C.bg),
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
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: _C.primary))
          : _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/profile');
            return;
          }
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

  // ── App Bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _C.bg,
            border: Border(
              bottom: BorderSide(color: _C.outlineVariant, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.textSec, size: 24),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pushNamed('/profile'),
                icon: const Icon(Icons.person_outline_rounded,
                    color: _C.primary, size: 24),
                tooltip: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pagePadding,
        AppConstants.spacingLg,
        AppConstants.pagePadding,
        AppConstants.spacingSection,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Profile Header Card ─────────────────────────────────────────
          _buildProfileHeader(),
          const SizedBox(height: AppConstants.spacingLg),

          // ── Account section ─────────────────────────────────────────────
          _SettingsCard(
            sectionLabel: 'ACCOUNT',
            children: [
              _SettingsRow(
                icon: Icons.person_outline_rounded,
                label: 'Edit Profile',
                onTap: _showEditProfileDialog,
              ),
              _SettingsRow(
                icon: Icons.lock_outline_rounded,
                label: 'Change Password',
                onTap: _showChangePasswordDialog,
              ),
              _SettingsRow(
                icon: Icons.delete_forever_rounded,
                label: 'Delete Account',
                onTap: _showDeleteAccountDialog,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // ── Security & Devices ──────────────────────────────────────────
          _SettingsCard(
            sectionLabel: 'SECURITY & DEVICES',
            children: [
              _SettingsRow(
                icon: Icons.history_rounded,
                label: 'Active Sessions',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Current session is active.')),
                  );
                },
              ),
              _SettingsRow(
                icon: Icons.devices_rounded,
                label: 'Device Management',
                onTap: () => Navigator.of(context).pushNamed('/device'),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.spacingLg),

          // ── App Settings (full width with toggles) ──────────────────────
          _SettingsCard(
            sectionLabel: 'APP SETTINGS',
            children: [
              _ToggleRow(
                icon: Icons.straighten_rounded,
                label: 'Units (Metric)',
                value: _metricUnits,
                onChanged: (v) => setState(() => _metricUnits = v),
              ),
              _ToggleRow(
                icon: Icons.notifications_outlined,
                label: 'Push Notifications',
                value: _pushNotifications,
                onChanged: (v) => setState(() => _pushNotifications = v),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // ── Logout button ───────────────────────────────────────────────
          _buildLogoutButton(),
        ],
      ),
    );
  }

  // ── Profile Header ─────────────────────────────────────────────────────────
  Widget _buildProfileHeader() {
    final name = _user?.fullName.isNotEmpty == true ? _user!.fullName : 'Rider';
    final email =
        _user?.email.isNotEmpty == true ? _user!.email : 'user@justride.io';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'R';
    final shortId = _user?.id.isNotEmpty == true
        ? (_user!.id.length > 8
            ? _user!.id.substring(_user!.id.length - 8).toUpperCase()
            : _user!.id)
        : 'ACTIVE';

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: _C.surfContLow,
        border: Border.all(color: _C.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      child: Row(
        children: [
          // Avatar with green border ring
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _C.primary, width: 2),
            ),
            child: ClipOval(
              child: Container(
                color: _C.cardBg,
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontFamily: 'Stack Sans Text',
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: _C.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppTextStyles.headingLarge.copyWith(
                    fontSize: 20,
                    color: _C.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 13,
                    color: _C.textSec,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: JR-$shortId',
                  style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _C.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Logout Button ──────────────────────────────────────────────────────────
  Widget _buildLogoutButton() {
    return Center(
      child: OutlinedButton(
        onPressed: () async {
          await BackendService.instance.logout();
          if (mounted) {
            Navigator.of(context)
                .pushNamedAndRemoveUntil('/login', (r) => false);
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.errorText,
          side: const BorderSide(color: AppColors.errorText, width: 1.5),
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingXl,
            vertical: AppConstants.spacingMd,
          ),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          backgroundColor: Colors.transparent,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.logout_rounded, size: 20, color: AppColors.errorText),
            const SizedBox(width: AppConstants.spacingSm),
            Text(
              'LOGOUT',
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.errorText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Settings Card (section container) ─────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.sectionLabel,
    required this.children,
  });
  final String sectionLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: _C.cardBg,
        border: Border.all(color: _C.cardBorder),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sectionLabel,
            style: TextStyle(
              fontFamily: 'Stack Sans Text',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: _C.textSec,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),
          ...children.asMap().entries.map((e) {
            final isLast = e.key == children.length - 1;
            return Column(
              children: [
                e.value,
                if (!isLast)
                  Divider(
                    color: _C.cardBorder,
                    height: 1,
                    indent: 44,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ── Settings Row ──────────────────────────────────────────────────────────────
class _SettingsRow extends StatefulWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<_SettingsRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) {
        setState(() => _hovered = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _hovered = false),
      child: Container(
        color: _hovered ? _C.itemBg : Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(widget.icon, size: 20, color: _C.textSec),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _C.onSurface,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: _C.textSec,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toggle Row ────────────────────────────────────────────────────────────────
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _C.textSec),
          const SizedBox(width: AppConstants.spacingMd),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Stack Sans Text',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _C.onSurface,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _C.primary,
            activeTrackColor: _C.primary.withValues(alpha: 0.3),
            inactiveThumbColor: _C.textSec,
            inactiveTrackColor: _C.surfContLow,
          ),
        ],
      ),
    );
  }
}
