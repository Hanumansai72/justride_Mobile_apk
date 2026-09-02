import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';

/// Four quick-destination shortcut chips: Home, Work, Places, Search.
class QuickShortcuts extends StatelessWidget {
  const QuickShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _ShortcutChip(
              shortcut: _Shortcut(
                icon: Icons.home_rounded,
                label: 'Home',
                subtitle: 'Saved',
                route: '/places',
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _ShortcutChip(
              shortcut: _Shortcut(
                icon: Icons.work_rounded,
                label: 'Work',
                subtitle: 'Office',
                route: '/places',
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _ShortcutChip(
              shortcut: _Shortcut(
                icon: Icons.bookmark_border_rounded,
                label: 'Places',
                subtitle: 'Saved',
                route: '/places',
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: _ShortcutChip(
              shortcut: _Shortcut(
                icon: Icons.history_rounded,
                label: 'Recent',
                subtitle: 'History',
                route: '/places',
              ),
            ),
          ),
        ),
      ],
    );
  }

}

// ── Shortcut data model ───────────────────────────────────────────────────────

class _Shortcut {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.route,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final String route;
}


// ── Individual chip ───────────────────────────────────────────────────────────

class _ShortcutChip extends StatefulWidget {
  const _ShortcutChip({required this.shortcut});
  final _Shortcut shortcut;

  @override
  State<_ShortcutChip> createState() => _ShortcutChipState();
}

class _ShortcutChipState extends State<_ShortcutChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        Navigator.of(context).pushNamed(widget.shortcut.route);
      },
      child: AnimatedContainer(

        duration: AppConstants.animFast,
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: _pressed ? AppColors.primaryContainer : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: _pressed ? AppColors.primary : AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(widget.shortcut.icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(
              widget.shortcut.label,
              style: AppTextStyles.labelLarge.copyWith(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(widget.shortcut.subtitle, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}
