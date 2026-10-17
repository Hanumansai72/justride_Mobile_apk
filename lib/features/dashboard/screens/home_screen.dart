import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../core/utils/maps_url_parser.dart';
import '../../../core/services/navigation_service.dart';
import '../../../shared/widgets/require_device_connection.dart';
import '../../navigation/widgets/destination_confirm_sheet.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const surfCont = AppColors.surface;
  static const surfBright = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
  static const blueAccent = AppColors.primary;
  static const inputBg = AppColors.backgroundInset;
  static const iconCircleBg = AppColors.surfaceElevated;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _navIndex = 0;
  final _startController = TextEditingController();
  final _destinationController = TextEditingController();
  Destination? _selectedStart;
  Destination? _selectedDestination;

  // Pulsing glow animation for Start Ride button
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseRadius;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pulseRadius = Tween<double>(begin: 0, end: 20).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _pulseOpacity = Tween<double>(begin: 0.5, end: 0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _startController.dispose();
    _destinationController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _openRoutePlan() async {
    if (!await requireDeviceConnection(context) || !mounted) return;
    final destinationQuery = _destinationController.text.trim();
    if (destinationQuery.isEmpty) {
      // Directly redirect to the inbuilt app maps page
      Navigator.of(context).pushNamed('/active-navigation');
      return;
    }

    final startQuery = _startController.text.trim();
    final parsedDestination = _selectedDestination ??
        await MapsUrlParser.parseSharedText(destinationQuery);
    final parsedStart = _selectedStart ??
        (startQuery.isEmpty
            ? null
            : await MapsUrlParser.parseSharedText(startQuery));
    if (!mounted) return;

    final dest = parsedDestination ?? _destinationFromQuery(destinationQuery);
    final start = startQuery.isEmpty
        ? null
        : (parsedStart ?? _destinationFromQuery(startQuery));

    NavigationService.instance.startNavigation(
      dest,
      startLocation: start,
    );
    Navigator.of(context).pushNamed('/active-navigation');
  }

  Destination _destinationFromQuery(String query) => Destination(
        name: query,
        address: query,
        latitude: 0,
        longitude: 0,
        rawQuery: query,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 1) {
            Navigator.of(context).pushNamed('/places');
          } else if (i == 2) {
            Navigator.of(context).pushNamed('/pair-device');
          } else if (i == 3) {
            Navigator.of(context).pushNamed('/notifications');
          } else if (i == 4) {
            Navigator.of(context).pushNamed('/profile');
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
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacementNamed('/dashboard');
                  }
                },
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.primary, size: 24),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/profile-settings'),
                icon: const Icon(Icons.settings_outlined,
                    color: _C.textSec, size: 24),
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
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppConstants.spacingMd),

          // Device Card
          GestureDetector(
            onTap: () => Navigator.of(context).pushNamed('/device'),
            child: _DeviceCard(),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // Route planner — phone resolves the two places, then the live
          // navigation service streams compact manoeuvres to the HUD.
          Text(
            'Plan your ride',
            style: AppTextStyles.headingLarge.copyWith(
              fontSize: 22,
              color: _C.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          Text(
            'Enter destination to see instant suggestions down below, or leave Start empty to use your live phone GPS.',
            style: GoogleFonts.inter(fontSize: 13, color: _C.textSec),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          _SearchField(
            controller: _startController,
            label: 'START',
            icon: Icons.trip_origin_rounded,
            hintText: 'Current location (or enter start)',
            onSubmitted: (_) => _openRoutePlan(),
            onSelected: (place) => _selectedStart = place,
            onTextChanged: () => _selectedStart = null,
          ),
          const SizedBox(height: 10),
          _SearchField(
            controller: _destinationController,
            label: 'DESTINATION',
            icon: Icons.location_on_rounded,
            hintText: 'Search destination...',
            onSubmitted: (_) => _openRoutePlan(),
            onSelected: (place) => _selectedDestination = place,
            onTextChanged: () => _selectedDestination = null,
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Home + Work quick shortcuts
          Row(
            children: [
              Expanded(
                child: _QuickShortcut(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  subtitle: 'QUICK ROUTE',
                  onTap: () => DestinationConfirmSheet.show(
                    context,
                    const Destination(
                      name: 'Home',
                      address: 'Saved Home Location',
                      latitude: 0,
                      longitude: 0,
                      rawQuery: 'Home',
                    ),
                    startLocation: _selectedStart ??
                        (_startController.text.trim().isEmpty
                            ? null
                            : _destinationFromQuery(
                                _startController.text.trim())),
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: _QuickShortcut(
                  icon: Icons.work_outline_rounded,
                  label: 'Work',
                  subtitle: 'QUICK ROUTE',
                  onTap: () => DestinationConfirmSheet.show(
                    context,
                    const Destination(
                      name: 'Work',
                      address: 'Office Location',
                      latitude: 0,
                      longitude: 0,
                      rawQuery: 'Work',
                    ),
                    startLocation: _selectedStart ??
                        (_startController.text.trim().isEmpty
                            ? null
                            : _destinationFromQuery(
                                _startController.text.trim())),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppConstants.spacingXl),

          // Start Ride button (pulsing glow)
          _StartRideButton(
            pulseRadius: _pulseRadius,
            pulseOpacity: _pulseOpacity,
            onTap: () {
              _openRoutePlan();
            },
          ),

          const SizedBox(height: AppConstants.spacingXl),
        ],
      ),
    );
  }
}

// ── Device Card ───────────────────────────────────────────────────────────────
class _DeviceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: _C.cardBg,
        border: Border.all(color: _C.cardBorder),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Top green accent line
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 2,
            child: Container(color: _C.primary.withValues(alpha: 0.5)),
          ),
          Column(
            children: [
              // Title row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bluetooth_connected_rounded,
                          color: _C.blueAccent, size: 22),
                      const SizedBox(width: AppConstants.spacingSm),
                      Text(
                        'JustRide Device',
                        style: AppTextStyles.headingSmall.copyWith(
                          color: _C.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _C.primary.withValues(alpha: 0.1),
                      border:
                          Border.all(color: _C.primary.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'CONNECTED',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _C.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingSm),
              Image.asset(
                'assets/justride-device.webp',
                height: 170,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppConstants.spacingSm),
              // Stats row
              Container(
                padding: const EdgeInsets.only(top: AppConstants.spacingSm),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: _C.outlineVariant.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCell(
                        label: 'BATTERY',
                        value: '0%',
                        icon: Icons.battery_5_bar_rounded,
                        iconColor: _C.primary,
                      ),
                    ),
                    Expanded(
                      child: _StatCell(
                        label: 'SIGNAL',
                        value: 'Strong',
                        icon: Icons.signal_cellular_4_bar_rounded,
                        iconColor: _C.blueAccent,
                      ),
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Synced 2m ago',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: _C.textSec,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _C.textSec,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(icon, color: iconColor, size: 14),
            const SizedBox(width: 4),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _C.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Search Field ──────────────────────────────────────────────────────────────
class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.hintText,
    this.onSubmitted,
    this.onSelected,
    this.onTextChanged,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String hintText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<Destination>? onSelected;
  final VoidCallback? onTextChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _focused = false;
  bool _isLoadingSuggestions = false;
  Timer? _placesDebounce;
  List<Destination> _suggestions = const [];

  @override
  void dispose() {
    _placesDebounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _placesDebounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      if (mounted) {
        setState(() {
          _suggestions = const [];
          _isLoadingSuggestions = false;
        });
      }
      return;
    }

    setState(() => _isLoadingSuggestions = true);
    _placesDebounce = Timer(const Duration(milliseconds: 250), () async {
      final matches = await GoogleMapsService.instance.searchPlaces(trimmed);
      if (mounted && widget.controller.text.trim() == trimmed) {
        setState(() {
          _suggestions = matches;
          _isLoadingSuggestions = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedContainer(
            duration: AppConstants.animFast,
            height: 64,
            decoration: BoxDecoration(
              color: _C.inputBg,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(
                color: _focused ? _C.primary : _C.outlineVariant,
                width: _focused ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: AppConstants.spacingMd),
                Icon(widget.icon,
                    color: _focused ? _C.primary : _C.textSec, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.label,
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: _focused ? _C.primary : _C.textSec)),
                      TextField(
                        controller: widget.controller,
                        style: GoogleFonts.inter(
                            fontSize: 15, color: _C.onSurface),
                        cursorColor: _C.primary,
                        textInputAction: TextInputAction.next,
                        onSubmitted: widget.onSubmitted,
                        onChanged: (value) {
                          widget.onTextChanged?.call();
                          _onChanged(value);
                        },
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          hintStyle: GoogleFonts.inter(
                              fontSize: 14,
                              color: _C.textSec.withValues(alpha: 0.5)),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isLoadingSuggestions)
                  const Padding(
                    padding: EdgeInsets.only(right: 14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _C.primary,
                      ),
                    ),
                  )
                else if (widget.controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 18, color: _C.textSec),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onTextChanged?.call();
                      setState(() {
                        _suggestions = const [];
                        _isLoadingSuggestions = false;
                      });
                    },
                  ),
              ],
            ),
          ),
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                color: _C.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _C.primary.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  children: _suggestions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final place = entry.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (index > 0)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: _C.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _C.iconCircleBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.place_rounded,
                                color: _C.primary, size: 18),
                          ),
                          title: Text(
                            place.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _C.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            place.displaySubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: _C.textSec,
                            ),
                          ),
                          trailing: const Icon(Icons.north_west_rounded,
                              size: 14, color: _C.textSec),
                          onTap: () {
                            widget.controller.text = place.displayTitle;
                            setState(() {
                              _suggestions = const [];
                              _isLoadingSuggestions = false;
                            });
                            widget.onSelected?.call(place);
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Quick Shortcut Card ───────────────────────────────────────────────────────
class _QuickShortcut extends StatefulWidget {
  const _QuickShortcut({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_QuickShortcut> createState() => _QuickShortcutState();
}

class _QuickShortcutState extends State<_QuickShortcut> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        padding: const EdgeInsets.all(AppConstants.spacingMd),
        decoration: BoxDecoration(
          color: _C.surfCont,
          border: Border.all(
            color: _pressed
                ? _C.primary.withValues(alpha: 0.5)
                : _C.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.surfBright,
              ),
              child: Icon(widget.icon, color: _C.onSurface, size: 20),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: _C.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: _C.textSec,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Start Ride Button (pulsing glow) ──────────────────────────────────────────
class _StartRideButton extends StatefulWidget {
  const _StartRideButton({
    required this.pulseRadius,
    required this.pulseOpacity,
    required this.onTap,
  });
  final Animation<double> pulseRadius;
  final Animation<double> pulseOpacity;
  final VoidCallback onTap;

  @override
  State<_StartRideButton> createState() => _StartRideButtonState();
}

class _StartRideButtonState extends State<_StartRideButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppConstants.animFast,
        child: AnimatedBuilder(
          animation: widget.pulseRadius,
          builder: (_, child) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              boxShadow: [
                // Pulsing outer ring
                BoxShadow(
                  color: _C.primary
                      .withValues(alpha: widget.pulseOpacity.value * 0.5),
                  blurRadius: widget.pulseRadius.value,
                  spreadRadius: widget.pulseRadius.value * 0.3,
                ),
                // Static glow
                BoxShadow(
                  color: _C.primary.withValues(alpha: 0.2),
                  blurRadius: 20,
                ),
              ],
            ),
            child: child,
          ),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: _C.primary,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.two_wheeler_rounded,
                    color: _C.onPrimary, size: 28),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  'Start Ride',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _C.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
