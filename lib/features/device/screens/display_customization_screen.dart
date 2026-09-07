// lib/features/device/screens/display_customization_screen.dart
//
// Full-featured Display Customization screen:
//   - Pick image from gallery or camera (supports QR codes, photos, logos)
//   - Preview at exact 320x240 (4:3 landscape) TFT aspect ratio with crisp nearest-neighbor rendering
//   - Uploads to Backend /api/upload/image to persist in user's cloud account
//   - Converts to RGB565 (nearest-neighbour, QR-code safe) for direct hardware display
//   - Streams to connected JustRide ESP32 via BLE Image Transfer Service (0xFF20)
//   - Progress dialog during upload and transmission

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/image_converter.dart';
import '../../../core/services/image_transfer_service.dart';
import '../../../core/services/bluetooth_service.dart';
import '../../../core/services/backend_service.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const surfContHigh = Color(0xFF1E2C30);
  static const surfContLow = Color(0xFF101E22);
  static const surfVariant = Color(0xFF29373B);
  static const primary = Color(0xFF4BE277);
  static const onPrimary = Color(0xFF003915);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outlineVariant = Color(0xFF3D4A3D);
  static const errorContainer = Color(0xFF93000A);
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
}

class DisplayCustomizationScreen extends StatefulWidget {
  const DisplayCustomizationScreen({super.key});

  @override
  State<DisplayCustomizationScreen> createState() =>
      _DisplayCustomizationScreenState();
}

class _DisplayCustomizationScreenState
    extends State<DisplayCustomizationScreen> {
  // ── State ──────────────────────────────────────────────────────────────────
  ui.Image? _previewImage; // 320x240 rendered preview
  Uint8List? _rgb565Bytes; // converted, ready to send to device
  bool _isConverting = false;
  bool _isBackingUpToBackend = false;
  String? _backendUploadedUrl;

  final _imagePicker = ImagePicker();
  final _imageTransferSvc = ImageTransferService();

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _imageTransferSvc.dispose();
    super.dispose();
  }

  // ── Image Pick ────────────────────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 100, // 100% quality - we do nearest-neighbor scaling for QR safety
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _processImage(bytes, picked.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open image: $e'),
            backgroundColor: _C.error,
          ),
        );
      }
    }
  }

  Future<void> _processImage(Uint8List bytes, String filename) async {
    setState(() {
      _isConverting = true;
      _previewImage = null;
      _rgb565Bytes = null;
      _backendUploadedUrl = null;
    });

    try {
      // 1. Process image locally with QR-safe nearest-neighbor conversion
      final results = await Future.wait([
        ImageConverter.buildPreviewImage(bytes),
        ImageConverter.convertToRgb565(bytes),
      ]);

      if (!mounted) return;

      setState(() {
        _previewImage = results[0] as ui.Image;
        _rgb565Bytes = results[1] as Uint8List;
        _isConverting = false;
      });

      // 2. Asynchronously backup to backend cloud storage
      _backupImageToBackend(bytes, filename);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConverting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image processing error: $e'),
          backgroundColor: _C.error,
        ),
      );
    }
  }

  Future<void> _backupImageToBackend(Uint8List bytes, String filename) async {
    setState(() => _isBackingUpToBackend = true);
    try {
      final res = await BackendService.instance.uploadCustomDisplayImage(
        imageBytes: bytes,
        filename: filename.isNotEmpty ? filename : 'custom_display.png',
      );
      if (mounted && res.success && res.data != null) {
        setState(() {
          _backendUploadedUrl = res.data!['url'] as String? ?? res.data!['secure_url'] as String?;
          _isBackingUpToBackend = false;
        });
      } else {
        if (mounted) setState(() => _isBackingUpToBackend = false);
      }
    } catch (err) {
      if (mounted) setState(() => _isBackingUpToBackend = false);
    }
  }

  // ── Send to Device ────────────────────────────────────────────────────────
  Future<void> _sendToDevice() async {
    if (_rgb565Bytes == null) return;

    final device = JustRideBleService.instance.connectedDevice;
    if (device == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No device connected. Please pair your JustRide device first.'),
          backgroundColor: _C.error,
        ),
      );
      return;
    }

    // Show transfer progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransferProgressDialog(service: _imageTransferSvc),
    );

    final ok = await _imageTransferSvc.sendImage(
      device: device,
      rgb565Bytes: _rgb565Bytes!,
    );

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop(); // close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Image uploaded to JustRide! Swipe RIGHT on your device screen to view it.'
                : 'Transfer failed. Please check Bluetooth connection and retry.',
          ),
          backgroundColor: ok ? _C.primary : _C.error,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _previewImage = null;
      _rgb565Bytes = null;
      _backendUploadedUrl = null;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          decoration: const BoxDecoration(
            color: _C.bg,
            border: Border(bottom: BorderSide(color: _C.outlineVariant)),
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
              Text(
                'Display Customization',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: _C.primary,
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(AppConstants.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live Preview Card (320:240 = 4:3 TFT display ratio)
                _buildLivePreviewCard(),
                const SizedBox(height: AppConstants.spacingLg),

                // Upload card OR Replace / Remove buttons
                if (_rgb565Bytes == null && !_isConverting) ...[
                  _buildUploadCard(),
                ] else if (_isConverting) ...[
                  _buildConvertingCard(),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.swap_horiz_rounded,
                          label: 'Replace',
                          onTap: () => _showPickerSheet(context),
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingMd),
                      Expanded(
                        child: _ActionCard(
                          icon: Icons.delete_outline_rounded,
                          label: 'Remove',
                          isDestructive: true,
                          onTap: _removeImage,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppConstants.spacingMd),

                // Device and Cloud Status Cards
                if (_rgb565Bytes != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _C.surfCont,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _C.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: _C.primary, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Hardware-Optimized: 320×240 (4:3), 150 KB RGB565',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _C.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              _isBackingUpToBackend
                                  ? Icons.sync_rounded
                                  : Icons.cloud_done_outlined,
                              color: _isBackingUpToBackend
                                  ? _C.textSec
                                  : _C.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isBackingUpToBackend
                                  ? 'Syncing to JustRide cloud...'
                                  : (_backendUploadedUrl != null
                                      ? 'Cloud backup synced'
                                      : 'Ready for device transfer'),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: _C.textSec,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: AppConstants.spacingSm),
                // Helpful instructions hint
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _C.surfContLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _C.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app_outlined,
                          color: _C.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Swipe RIGHT on your JustRide screen anytime to view this picture. '
                          'Swipe LEFT or TAP to return to navigation.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _C.textSec,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Apply button pinned at bottom
        Container(
          padding: EdgeInsets.fromLTRB(
            AppConstants.pagePadding,
            AppConstants.spacingMd,
            AppConstants.pagePadding,
            MediaQuery.of(context).padding.bottom + AppConstants.spacingMd,
          ),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: _C.outlineVariant)),
          ),
          child: _ApplyButton(
            enabled: _rgb565Bytes != null && !_isConverting,
            onTap: _sendToDevice,
          ),
        ),
      ],
    );
  }

  // ── Live Preview Card (maintains exact 320:240 = 4:3 ratio) ─────────────
  Widget _buildLivePreviewCard() {
    return Container(
      decoration: BoxDecoration(
        color: _C.surfCont,
        border: Border.all(color: _C.outlineVariant),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 320 / 240, // 4:3 TFT display proportion
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _C.surfContHigh.withValues(alpha: 0.5),
                      _C.surfContLow.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ),
            // Header label
            Positioned(
              top: 10,
              left: 12,
              child: Text(
                'LIVE PREVIEW 320×240 (4:3)',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _C.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            // Image preview or default HUD display
            _previewImage != null
                ? Positioned.fill(
                    child: RawImage(
                      image: _previewImage,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none, // Pixel-perfect QR display
                    ),
                  )
                : _buildHudMock(),
            // Converting overlay
            if (_isConverting)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: _C.primary,
                      strokeWidth: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Default screen HUD mock ──────────────────────────────────────────────
  Widget _buildHudMock() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SPEED',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  color: _C.primary,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '48',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: _C.onSurface,
                  letterSpacing: -1,
                ),
              ),
              Text(
                'KM/H',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8,
                  color: _C.textSec,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'JUST RIDE HUD DISPLAY',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _C.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Upload your custom image or QR code below.',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: _C.textSec,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '↑ Swipe Right on device to toggle this view',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    color: _C.primary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: () => _showPickerSheet(context),
      child: CustomPaint(
        painter: _DashedRectPainter(
          color: _C.outlineVariant,
          strokeWidth: 1.5,
          gap: 6,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            color: _C.surfCont,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          ),
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: _C.surfVariant,
                ),
                child: const Icon(
                  Icons.cloud_upload_outlined,
                  color: _C.textSec,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(
                'Upload Your Pic or QR Code',
                style: AppTextStyles.headingSmall.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _C.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Supports QR codes, graphics, photos & documents\n'
                'Auto-scaled to 320×240 px without distortion or pixel blur',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontSize: 12,
                  color: _C.textSec,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConvertingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _C.surfCont,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: _C.outlineVariant),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: _C.primary,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Optimising pixels for JustRide display...',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 13,
                color: _C.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPickerSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surfCont,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _C.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: _C.primary),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.inter(color: _C.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: _C.primary),
              title: Text(
                'Take a Photo',
                style: GoogleFonts.inter(color: _C.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Transfer Progress Dialog ──────────────────────────────────────────────────
class _TransferProgressDialog extends StatefulWidget {
  const _TransferProgressDialog({required this.service});
  final ImageTransferService service;

  @override
  State<_TransferProgressDialog> createState() =>
      _TransferProgressDialogState();
}

class _TransferProgressDialogState extends State<_TransferProgressDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _C.surfCont,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<ImageTransferProgress>(
          valueListenable: widget.service.progressNotifier,
          builder: (_, prog, __) {
            final pct = (prog.progress * 100).toInt();
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sending Image to Device',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _C.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: prog.progress,
                  backgroundColor: _C.surfVariant,
                  valueColor: const AlwaysStoppedAnimation<Color>(_C.primary),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
                const SizedBox(height: 12),
                Text(
                  '$pct% — ${prog.statusMessage}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: _C.textSec,
                  ),
                ),
                const SizedBox(height: 16),
                if (prog.state == ImageTransferState.transferring ||
                    prog.state == ImageTransferState.preparing)
                  TextButton(
                    onPressed: () {
                      widget.service.cancelTransfer();
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.inter(color: _C.error),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Reusable Action Card & Buttons ───────────────────────────────────────────
class _ActionCard extends StatefulWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  State<_ActionCard> createState() => _ActionCardState();
}

class _ActionCardState extends State<_ActionCard> {
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
        height: 84,
        decoration: BoxDecoration(
          color: _pressed
              ? (widget.isDestructive ? _C.errorContainer : _C.surfVariant)
              : _C.surfCont,
          border: Border.all(
            color: widget.isDestructive && _pressed
                ? _C.error
                : _C.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.icon,
              color: _pressed
                  ? (widget.isDestructive ? _C.onError : _C.onSurface)
                  : _C.textSec,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _pressed
                    ? (widget.isDestructive ? _C.onError : _C.onSurface)
                    : _C.textSec,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplyButton extends StatefulWidget {
  const _ApplyButton({required this.onTap, required this.enabled});
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_ApplyButton> createState() => _ApplyButtonState();
}

class _ApplyButtonState extends State<_ApplyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onTap();
            }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: AppConstants.animFast,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.4,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: _C.primary,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              boxShadow: widget.enabled
                  ? [
                      BoxShadow(
                        color: _C.primary.withValues(alpha: 0.25),
                        blurRadius: 15,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.send_to_mobile_rounded,
                  color: _C.onPrimary,
                  size: 22,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Text(
                  widget.enabled
                      ? 'Upload to Device (Swipe Right on Screen)'
                      : 'Pick an image first',
                  style: GoogleFonts.inter(
                    fontSize: 15,
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

// ── Custom Painter for Dashed Outline ─────────────────────────────────────────
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.gap = 5.0,
  });

  final Color color;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(AppConstants.radiusLg),
    );

    final path = Path()..addRRect(rrect);
    final dashPath = Path();

    double distance = 0;
    for (final metric in path.computeMetrics()) {
      while (distance < metric.length) {
        final len = gap;
        if (distance + len > metric.length) {
          dashPath.addPath(
              metric.extractPath(distance, metric.length), Offset.zero);
          break;
        }
        dashPath.addPath(
            metric.extractPath(distance, distance + len), Offset.zero);
        distance += len * 2;
      }
      distance = 0;
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth || old.gap != gap;
}
