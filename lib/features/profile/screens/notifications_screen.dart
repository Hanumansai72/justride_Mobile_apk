import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/app_logo.dart';


// â”€â”€ Colour tokens â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const surfContLow = Color(0xFF101E22);
  static const surfContHighest = Color(0xFF29373B);
  static const surfVariant = Color(0xFF29373B);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const primaryCont = Color(0xFF22C55E);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outline = Color(0xFF869585);
  static const outlineVariant = Color(0xFF3D4A3D);
}

// â”€â”€ Data models â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
enum _NotifState { unreadHigh, read }

class _Notif {
  const _Notif({
    required this.icon,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.state,
  });
  final IconData icon;
  final String title;
  final String body;
  final String timestamp;
  final _NotifState state;
}

const _chips = ['ALL', 'APP & APK', 'FIRMWARE', 'DEVICE', 'SECURITY'];


// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  int _selectedChip = 0;
  List<NotificationModel> _backendNotifications = [];
  bool _isLoading = true;


  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getNotifications();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success && res.data != null) {
          _backendNotifications = res.data!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : RefreshIndicator(
              onRefresh: _fetchNotifications,
              color: _C.primary,
              backgroundColor: _C.surfCont,
              child: _buildBody(),
            ),
    );
  }



  // â”€â”€ App Bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacementNamed('/dashboard');
                  }
                },
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
                onPressed: () => Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _C.textSec, size: 24),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // â”€â”€ Body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page header
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppConstants.pagePadding,
            AppConstants.spacingLg,
            AppConstants.pagePadding,
            0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Notifications',
                style: AppTextStyles.headingLarge.copyWith(
                  fontSize: 24,
                  color: _C.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              GestureDetector(
                onTap: () {},
                child: Text(
                  'MARK ALL READ',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: _C.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppConstants.spacingMd),

        // Filter chips (horizontally scrollable)
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.pagePadding),
            itemCount: _chips.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppConstants.spacingSm),
            itemBuilder: (_, i) => _FilterChip(
              label: _chips[i],
              // Show green dot on FIRMWARE chip
              hasDot: i == 2,
              selected: _selectedChip == i,
              onTap: () => setState(() => _selectedChip = i),
            ),
          ),
        ),
        const SizedBox(height: AppConstants.spacingMd),

        // Notifications list
        Expanded(
          child: _backendNotifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.notifications_off_outlined, color: _C.textSec, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'No notifications at the moment',
                        style: GoogleFonts.inter(color: _C.textSec, fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.pagePadding,
                    vertical: AppConstants.spacingMd,
                  ),
                  itemCount: _backendNotifications.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppConstants.spacingMd),
                  itemBuilder: (_, i) {
                    final n = _backendNotifications[i];
                    IconData icon = Icons.notifications_outlined;
                    if (n.type.toUpperCase().contains('FIRMWARE')) {
                      icon = Icons.system_update_alt_rounded;
                    } else if (n.type.toUpperCase().contains('DEVICE') ||
                        n.type.toUpperCase().contains('SECURITY')) {
                      icon = Icons.security_rounded;
                    }

                    final notifItem = _Notif(
                      icon: icon,
                      title: n.title,
                      body: n.message,
                      timestamp: 'RECENT',
                      state: n.isRead ? _NotifState.read : _NotifState.unreadHigh,
                    );

                    return _NotificationCard(
                      notif: notifItem,
                      onTap: () async {
                        await BackendService.instance.markNotificationAsRead(n.id);
                        _fetchNotifications();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

}

// â”€â”€ Filter Chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.hasDot = false,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool hasDot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: selected ? _C.primary : _C.surfCont,
          border: Border.all(
            color: selected ? _C.primary : _C.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusCircle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: selected ? _C.onPrimary : _C.textSec,
              ),
            ),
            if (hasDot && !selected) ...[
              const SizedBox(width: 6),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.primary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Notification Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _NotificationCard extends StatefulWidget {
  const _NotificationCard({required this.notif, this.onTap});
  final _Notif notif;
  final VoidCallback? onTap;

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.notif;
    final isUnreadHigh = n.state == _NotifState.unreadHigh;
    final isRead = n.state == _NotifState.read;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _hovered = true),
      onTapUp: (_) => setState(() => _hovered = false),
      onTapCancel: () => setState(() => _hovered = false),

      child: AnimatedOpacity(
        duration: AppConstants.animNormal,
        opacity: isRead && !_hovered ? 0.7 : 1.0,
        child: AnimatedContainer(
          duration: AppConstants.animFast,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(AppConstants.spacingMd),
          decoration: BoxDecoration(
            color: _C.surfContLow,
            border: Border.all(
              color: isUnreadHigh
                  ? (_hovered
                      ? _C.primary
                      : _C.primary.withValues(alpha: 0.4))
                  : (_hovered ? _C.outline : _C.outlineVariant),
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Left green accent bar for unread high-priority
              if (isUnreadHigh)
                Positioned(
                  left: -AppConstants.spacingMd,
                  top: -AppConstants.spacingMd,
                  bottom: -AppConstants.spacingMd,
                  width: 4,
                  child: Container(color: _C.primary),
                ),

              // Content
              Padding(
                padding: EdgeInsets.only(
                    left: isUnreadHigh ? AppConstants.spacingSm : 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon circle
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isUnreadHigh
                            ? _C.primaryCont.withValues(alpha: 0.2)
                            : (isRead
                                ? _C.surfContHighest
                                : _C.surfVariant),
                      ),
                      child: Icon(
                        n.icon,
                        color: isUnreadHigh ? _C.primary : _C.textSec,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingMd),

                    // Text content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  n.title,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    fontSize: 16,
                                    fontWeight: isUnreadHigh
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color: _C.onSurface,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                n.timestamp,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: isUnreadHigh
                                      ? _C.primary
                                      : _C.textSec,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            n.body,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontSize: 14,
                              color: _C.textSec,
                              height: 1.4,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),

                    // Chevron
                    Icon(
                      Icons.chevron_right_rounded,
                      color: _hovered ? _C.primary : _C.textSec,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
