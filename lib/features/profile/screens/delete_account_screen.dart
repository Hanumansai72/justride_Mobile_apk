import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Colour tokens ─────────────────────────────────────────────────────────────
class _C {
  static const bg = Color(0xFF071519);
  static const surfCont = Color(0xFF142226);
  static const surfContLow = Color(0xFF101E22);
  static const primary = Color(0xFF4BE277);
  static const onSurface = Color(0xFFD6E5EA);
  static const textSec = Color(0xFFBCCBB9);
  static const outlineVariant = Color(0xFF3D4A3D);
  static const surfaceVariant = Color(0xFF29373B);
  static const outline = Color(0xFF869585);
  // Error palette
  static const error = Color(0xFFFFB4AB);
  static const onError = Color(0xFF690005);
  static const errorContainer = Color(0xFF93000A);
}

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
              // Green back arrow (matches HTML: text-primary)
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.primary, size: 24),
              ),
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              const SizedBox(width: 48), // balance spacer
            ],
          ),
        ),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────
  Widget _buildBody(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.pagePadding,
          vertical: AppConstants.spacingXl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            decoration: BoxDecoration(
              color: _C.surfCont,
              border: Border.all(color: _C.outlineVariant),
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Red accent bar at top
                Container(
                  height: 4,
                  color: _C.error,
                ),

                Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingLg),
                  child: Column(
                    children: [
                      // ── Icon + Title ────────────────────────────────
                      const SizedBox(height: AppConstants.spacingMd),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _C.errorContainer,
                          border: Border.all(
                              color: _C.error.withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.warning_rounded,
                            color: _C.error, size: 32),
                      ),
                      const SizedBox(height: AppConstants.spacingMd),
                      Text(
                        'Delete Account',
                        style: AppTextStyles.headingLarge.copyWith(
                          fontSize: 24,
                          color: _C.error,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppConstants.spacingSm),
                      Text(
                        'This action is permanent and cannot be undone.',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: _C.textSec,
                          fontSize: 16,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppConstants.spacingXl),

                      // ── What happens next ───────────────────────────
                      Container(
                        padding: const EdgeInsets.all(AppConstants.spacingMd),
                        decoration: BoxDecoration(
                          color: _C.surfContLow,
                          border: Border.all(color: _C.outlineVariant),
                          borderRadius:
                              BorderRadius.circular(AppConstants.radiusMd),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WHAT HAPPENS NEXT',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: _C.textSec,
                              ),
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.delete_forever_rounded,
                                      color: _C.error, size: 18),
                                ),
                                const SizedBox(width: AppConstants.spacingSm),
                                Expanded(
                                  child: Text(
                                    'Deleting your account will remove all saved places, device associations, and support history.',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: _C.onSurface,
                                      fontSize: 14,
                                      height: 1.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXl),

                      // ── Password Field ──────────────────────────────
                      _buildPasswordLabel(),
                      const SizedBox(height: AppConstants.spacingSm),
                      _PasswordField(
                        controller: _passwordController,
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),
                      const SizedBox(height: AppConstants.spacingXl),

                      // ── Delete Button ───────────────────────────────
                      _DeleteButton(onTap: _onDelete),
                      const SizedBox(height: AppConstants.spacingMd),

                      // ── Cancel Button ───────────────────────────────
                      _CancelButton(
                          onTap: () => Navigator.of(context).pop()),
                      const SizedBox(height: AppConstants.spacingMd),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordLabel() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        'SECURITY VERIFICATION',
        style: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: _C.textSec,
        ),
      ),
    );
  }

  void _onDelete() {
    // TODO: implement actual deletion
  }
}

// ── Password Field ─────────────────────────────────────────────────────────────
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        height: 56,
        decoration: BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          border: Border.all(
            color: _focused
                ? _C.error.withValues(alpha: 0.8)
                : _C.outlineVariant,
            width: _focused ? 1.5 : 1,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: _C.error.withValues(alpha: 0.08),
                    blurRadius: 8,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            const SizedBox(width: AppConstants.spacingMd),
            Icon(
              Icons.lock_outline_rounded,
              color: _focused ? _C.error : _C.outline,
              size: 22,
            ),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: TextField(
                controller: widget.controller,
                obscureText: widget.obscure,
                style: GoogleFonts.inter(
                    fontSize: 15, color: _C.onSurface),
                cursorColor: _C.error,
                decoration: InputDecoration(
                  hintText: 'Enter your password to confirm',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 15,
                    color: _C.outline.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Delete Button ─────────────────────────────────────────────────────────────
class _DeleteButton extends StatefulWidget {
  const _DeleteButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_DeleteButton> createState() => _DeleteButtonState();
}

class _DeleteButtonState extends State<_DeleteButton> {
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
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: _C.error,
            border: Border.all(color: _C.errorContainer),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: [
              BoxShadow(
                color: _C.error.withValues(alpha: 0.2),
                blurRadius: 15,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delete_outline_rounded,
                  color: _C.onError, size: 18),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                'DELETE ACCOUNT',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: _C.onError,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cancel Button ─────────────────────────────────────────────────────────────
class _CancelButton extends StatefulWidget {
  const _CancelButton({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_CancelButton> createState() => _CancelButtonState();
}

class _CancelButtonState extends State<_CancelButton> {
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
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: _pressed
                ? _C.surfaceVariant
                : Colors.transparent,
            border: Border.all(color: _C.outlineVariant),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
          ),
          alignment: Alignment.center,
          child: Text(
            'CANCEL',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: _C.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
