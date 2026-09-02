import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/backend_service.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const cardBg = Color(0xFF142226);
  static const cardBorder = Color(0xFF3D4A3D);
  static const inputBg = Color(0xFF1E2C30);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
}


class AddPlaceScreen extends StatefulWidget {
  const AddPlaceScreen({super.key});

  @override
  State<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends State<AddPlaceScreen> {
  final _labelController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController(text: '17.3850');
  final _lngController = TextEditingController(text: '78.4867');

  String _selectedPreset = 'Home';
  bool _isSaving = false;

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
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _handleSavePlace() async {
    final label = _labelController.text.trim();
    final address = _addressController.text.trim();

    if (label.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a place label (e.g. Home, Work)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter an address or landmark'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final double lat = double.tryParse(_latController.text) ?? 17.3850;
    final double lng = double.tryParse(_lngController.text) ?? 78.4867;

    setState(() => _isSaving = true);

    final res = await BackendService.instance.createSavedAddress(
      label: label,
      address: address,
      latitude: lat,
      longitude: lng,
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
        Navigator.of(context).pop(true); // return true to refresh
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message),
            backgroundColor: Colors.redAccent,
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

            // ── Address Input ─────────────────────────────────────────────────
            _buildInputField(
              controller: _addressController,
              label: 'STREET ADDRESS / LANDMARK',
              hint: 'e.g. Cyber Towers, HITEC City, Hyderabad',
              icon: Icons.map_outlined,
              maxLines: 2,
            ),
            const SizedBox(height: AppConstants.spacingLg),

            // ── Coordinates (Lat/Lng) ─────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _buildInputField(
                    controller: _latController,
                    label: 'LATITUDE',
                    hint: '17.3850',
                    icon: Icons.explore_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Expanded(
                  child: _buildInputField(
                    controller: _lngController,
                    label: 'LONGITUDE',
                    hint: '78.4867',
                    icon: Icons.explore_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
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
    TextInputType keyboardType = TextInputType.text,
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
                  keyboardType: keyboardType,
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
