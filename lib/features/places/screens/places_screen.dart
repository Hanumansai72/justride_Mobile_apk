import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/app_models.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../navigation/widgets/destination_confirm_sheet.dart';

// ── Colour tokens matching Master App Theme ──────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const iconCircleBg = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
  static const outlineVariant = AppColors.border;
}

class _PlaceItem {
  const _PlaceItem({
    required this.id,
    required this.icon,
    required this.name,
    required this.address,
    this.hasAccentBorder = false,
  });

  final String id;
  final IconData icon;
  final String name;
  final String address;
  final bool hasAccentBorder;
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  final _searchController = TextEditingController();
  final int _navIndex = 1; // Places tab index
  List<SavedPlaceModel> _places = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPlaces();
  }

  Future<void> _fetchPlaces() async {
    setState(() => _isLoading = true);
    final res = await BackendService.instance.getSavedAddresses();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (res.success && res.data != null) {
          _places = res.data!;
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : RefreshIndicator(
              onRefresh: _fetchPlaces,
              color: _C.primary,
              backgroundColor: _C.cardBg,
              child: _buildBody(),
            ),
      floatingActionButton: _buildFab(),
      bottomNavigationBar: JustRideBottomNavBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 1) return;
          if (i == 0) {
            Navigator.of(context).pushReplacementNamed('/dashboard');
          } else if (i == 2) {
            Navigator.of(context).pushReplacementNamed('/device');
          } else if (i == 3) {
            Navigator.of(context).pushReplacementNamed('/profile');
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
                onPressed: () {},
                icon:
                    const Icon(Icons.menu_rounded, color: _C.textSec, size: 24),
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
    final query = _searchController.text.trim().toLowerCase();
    final filtered = _places.where((p) {
      if (query.isEmpty) return true;
      return p.title.toLowerCase().contains(query) ||
          p.address.toLowerCase().contains(query);
    }).toList();

    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        AppConstants.pagePadding,
        AppConstants.spacingMd,
        AppConstants.pagePadding,
        90, // room for FAB and bottom nav
      ),
      children: [
        // Search bar
        _buildSearchBar(),
        const SizedBox(height: AppConstants.spacingLg),

        if (filtered.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.location_off_outlined,
                      color: _C.textSec, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    query.isEmpty
                        ? 'No saved places yet'
                        : 'No matching places found',
                    style: GoogleFonts.inter(color: _C.textSec, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ] else ...[
          // Live Places Cards
          ...filtered.map((place) {
            IconData icon = Icons.place_outlined;
            if (place.type.toUpperCase().contains('HOME')) {
              icon = Icons.home_outlined;
            } else if (place.type.toUpperCase().contains('WORK')) {
              icon = Icons.work_outline_rounded;
            } else if (place.type.toUpperCase().contains('GYM')) {
              icon = Icons.fitness_center_rounded;
            } else if (place.type.toUpperCase().contains('CAFE')) {
              icon = Icons.local_cafe_outlined;
            }

            final item = _PlaceItem(
              id: place.id,
              icon: icon,
              name: place.title,
              address: place.address,
              hasAccentBorder: place.type.toUpperCase().contains('CAFE'),
            );

            return Padding(
              padding: const EdgeInsets.only(bottom: AppConstants.spacingMd),
              child: _PlaceCard(
                place: item,
                onNavigate: () {
                  final dest = Destination(
                    name: item.name,
                    address: item.address,
                    latitude: 0,
                    longitude: 0,
                    rawQuery:
                        item.address.isNotEmpty ? item.address : item.name,
                  );
                  DestinationConfirmSheet.show(context, dest);
                },
                onEdit: () {},
                onDelete: () async {
                  await BackendService.instance.deleteSavedAddress(item.id);
                  _fetchPlaces();
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingMd),
      child: Row(
        children: [
          const Icon(Icons.search_rounded,
              color: AppColors.textMuted, size: 22),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
              cursorColor: _C.primary,
              decoration: InputDecoration(
                hintText: 'Search saved places...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textMuted,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () async {
          final added = await Navigator.of(context).pushNamed('/add-place');
          if (added == true) {
            _fetchPlaces();
          }
        },
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _C.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_location_alt_outlined,
                color: _C.onPrimary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'ADD PLACE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _C.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Place Card ─────────────────────────────────────────────────────────────────
class _PlaceCard extends StatefulWidget {
  const _PlaceCard({
    required this.place,
    required this.onNavigate,
    required this.onEdit,
    required this.onDelete,
  });

  final _PlaceItem place;
  final VoidCallback onNavigate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard> {
  @override
  Widget build(BuildContext context) {
    final p = widget.place;

    return Container(
      decoration: BoxDecoration(
        color: _C.cardBg,
        border: Border.all(
          color: p.hasAccentBorder ? _C.primary : _C.outlineVariant,
          width: p.hasAccentBorder ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      ),
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Icon + Name + Address
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.iconCircleBg,
                ),
                child: Icon(
                  p.icon,
                  color: _C.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppConstants.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _C.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      p.address,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        color: _C.textSec,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Divider
          const Divider(color: _C.outlineVariant, height: 1),
          const SizedBox(height: AppConstants.spacingSm),

          // Row 2: NAVIGATE action + Edit & Delete icons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: widget.onNavigate,
                child: Row(
                  children: [
                    const Icon(
                      Icons.navigation_rounded,
                      color: _C.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'NAVIGATE',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: _C.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      color: _C.textSec,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: _C.textSec,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
