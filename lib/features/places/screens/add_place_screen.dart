import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/models/destination.dart';
import '../../../core/services/backend_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/google_maps_service.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Colour tokens matching Master App Theme ──────────────────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBg = AppColors.surface;
  static const cardBorder = AppColors.border;
  static const inputBg = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = Color(0xFF003915);
  static const onSurface = AppColors.textPrimary;
  static const textSec = AppColors.textSecondary;
}

class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key});

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();

  double _selectedLat = 17.3850;
  double _selectedLng = 78.4867;
  bool _hasResolvedCoordinates = false;

  String _selectedPreset = 'Home';
  bool _isSaving = false;
  bool _isLocatingCurrent = false;

  List<Destination> _searchSuggestions = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  final List<Map<String, dynamic>> _presets = [
    {'label': 'Home', 'icon': Icons.home_rounded},
    {'label': 'Work', 'icon': Icons.work_rounded},
    {'label': 'Gym', 'icon': Icons.fitness_center_rounded},
    {'label': 'Cafe', 'icon': Icons.local_cafe_rounded},
    {'label': 'Other', 'icon': Icons.location_on_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _labelController.text = 'Home';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onAddressChanged(String query) {
    _debounceTimer?.cancel();
    final clean = query.trim();
    if (clean.length < 2) {
      if (mounted) {
        setState(() {
          _searchSuggestions = [];
          _isSearching = false;
        });
      }
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final results = await GoogleMapsService.instance.searchPlaces(clean);
        if (mounted) {
          setState(() {
            _searchSuggestions = results;
            _isSearching = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _selectSuggestion(Destination place) {
    setState(() {
      _addressController.text = place.displayTitle;
      _selectedLat = place.latitude;
      _selectedLng = place.longitude;
      _hasResolvedCoordinates = true;
      _searchSuggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocatingCurrent = true);
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos != null) {
        setState(() {
          _selectedLat = pos.latitude;
          _selectedLng = pos.longitude;
          _hasResolvedCoordinates = true;
          _addressController.text =
              'Current Location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
          _searchSuggestions = [];
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Current GPS coordinates captured!'),
              backgroundColor: _C.primary,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not obtain current GPS position.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingCurrent = false);
    }
  }

  Future<void> _handleSavePlace() async {
    final label = _labelController.text.trim();
    final address = _addressController.text.trim();

    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a place label (e.g. Home, Work)'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or search an address or landmark'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final res = await BackendService.instance.createSavedAddress(
      label: label,
      address: address,
      latitude: _selectedLat,
      longitude: _selectedLng,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (res.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label saved successfully!'),
            backgroundColor: _C.primary,
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePadding,
          vertical: AppConstants.spacingLg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Saved Place',
              style: AppTextStyles.headingLarge.copyWith(
                fontSize: 24,
                color: _C.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Save your frequent destinations to quickly navigate with HUD navigation.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: _C.textSec,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: AppConstants.spacingXl),

            // ── Preset quick tags ─────────────────────────────────────────────
            Text(
              'CATEGORY PRESET',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _C.textSec,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final isSelected = _selectedPreset == p['label'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPreset = p['label'] as String;
                      if (_selectedPreset != 'Other') {
                        _labelController.text = _selectedPreset;
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: AppConstants.animFast,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? _C.primary.withValues(alpha: 0.15) : _C.cardBg,
                      border: Border.all(
                        color: isSelected ? _C.primary : _C.cardBorder,
                        width: isSelected ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          p['icon'] as IconData,
                          size: 16,
                          color: isSelected ? _C.primary : _C.textSec,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          p['label'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? _C.primary : _C.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: AppConstants.spacingXl),

            // ── Label Input ───────────────────────────────────────────────────
            _buildInputField(
              controller: _labelController,
              label: 'PLACE LABEL',
              hint: 'e.g. Home, Office, Gym, Mom\'s House',
              icon: Icons.label_outline_rounded,
            ),
            const SizedBox(height: AppConstants.spacingLg),

            // ── Search Address / Street Input ──────────────────────────────────
            Text(
              'SEARCH ADDRESS / LOCATION',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _C.textSec,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: _C.inputBg,
                border: Border.all(color: _C.cardBorder),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, color: _C.primary, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _addressController,
                      onChanged: _onAddressChanged,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: _C.onSurface,
                      ),
                      cursorColor: _C.primary,
                      decoration: InputDecoration(
                        hintText: 'Type address (e.g. Uppal, HITEC City)...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 14,
                          color: _C.textSec.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        suffixIcon: _isSearching
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _C.primary,
                                  ),
                                ),
                              )
                            : _addressController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, size: 18, color: _C.textSec),
                                    onPressed: () {
                                      _addressController.clear();
                                      setState(() => _searchSuggestions = []);
                                    },
                                  )
                                : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Autocomplete suggestions list
            if (_searchSuggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: _C.cardBg,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  border: Border.all(color: _C.cardBorder),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _searchSuggestions.length > 5 ? 5 : _searchSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, i) {
                    final item = _searchSuggestions[i];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_rounded, color: _C.primary, size: 18),
                      title: Text(
                        item.displayTitle,
                        style: GoogleFonts.inter(color: _C.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: item.address != null
                          ? Text(
                              item.address!,
                              style: GoogleFonts.inter(color: _C.textSec, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : null,
                      onTap: () => _selectSuggestion(item),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: AppConstants.spacingMd),

            // ── Use Current Location Button ────────────────────────────────────
            InkWell(
              onTap: _isLocatingCurrent ? null : _useCurrentLocation,
              borderRadius: BorderRadius.circular(AppConstants.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _C.cardBg,
                  border: Border.all(color: _C.primary.withValues(alpha: 0.4)),
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Row(
                  children: [
                    _isLocatingCurrent
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _C.primary,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, color: _C.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Use Current GPS Location',
                            style: GoogleFonts.inter(
                              color: _C.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'Store current device latitude & longitude automatically',
                            style: GoogleFonts.inter(
                              color: _C.textSec,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, color: _C.textSec, size: 14),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppConstants.spacingMd),

            // Coordinates Status Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _hasResolvedCoordinates
                    ? _C.primary.withValues(alpha: 0.1)
                    : _C.cardBg,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(
                  color: _hasResolvedCoordinates
                      ? _C.primary.withValues(alpha: 0.3)
                      : _C.cardBorder,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _hasResolvedCoordinates
                        ? Icons.check_circle_rounded
                        : Icons.location_searching_rounded,
                    color: _hasResolvedCoordinates ? _C.primary : _C.textSec,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Coordinates: ${_selectedLat.toStringAsFixed(4)}, ${_selectedLng.toStringAsFixed(4)} ${_hasResolvedCoordinates ? '(Resolved)' : '(Default)'}',
                    style: GoogleFonts.jetBrainsMono(
                      color: _hasResolvedCoordinates ? _C.primary : _C.textSec,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.spacingSection),

            // ── Save Button ───────────────────────────────────────────────────
            GestureDetector(
              onTap: _isSaving ? null : _handleSavePlace,
              child: AnimatedContainer(
                duration: AppConstants.animFast,
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  color: _C.primary,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  boxShadow: [
                    BoxShadow(
                      color: _C.primary.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: _C.onPrimary,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bookmark_add_rounded, color: _C.onPrimary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'SAVE ADDRESS',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _C.onPrimary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _C.textSec,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: _C.inputBg,
            border: Border.all(color: _C.cardBorder),
            borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Row(
            crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: maxLines > 1 ? 12 : 0),
                child: Icon(icon, color: _C.textSec, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: _C.onSurface,
                  ),
                  cursorColor: _C.primary,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.inter(
                      fontSize: 14,
                      color: _C.textSec.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
              bottom: BorderSide(color: _C.cardBorder, width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, color: _C.onSurface),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              const SizedBox(width: 48), // Spacer
            ],
          ),
        ),
      ),
    );
  }
}
