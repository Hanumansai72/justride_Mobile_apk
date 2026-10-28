import '../../../app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Color tokens (consistent across all JustRide screens) ────────────────────
class _C {
  static const bg = AppColors.background;
  static const cardBgInput = AppColors.surface;
  static const surfContHigh = AppColors.surfaceElevated;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const textSec = AppColors.textSecondary;
  static const onSurface = AppColors.textPrimary;
  static const outlineVariant = AppColors.border;
  static const inputBorder = AppColors.border;
  static const surfaceVariant = AppColors.surfaceElevated;
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // Simulated strength based on length (0–4 bars)
  int get _strength {
    final len = _newPasswordCtrl.text.length;
    if (len == 0) return 0;
    if (len < 6) return 1;
    if (len < 10) return 2;
    if (len < 14) return 3;
    return 4;
  }

  String get _strengthLabel {
    switch (_strength) {
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Strong';
      case 4:
        return 'Very Strong';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
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
              IconButton(
                onPressed: () {},
                icon:
                    const Icon(Icons.menu_rounded, color: _C.textSec, size: 24),
              ),
              // AppLogo identical to all other screens
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              IconButton(
                onPressed: () {},
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Page title ────────────────────────────────────────────
              Text(
                'Reset Password',
                style: AppTextStyles.headingLarge.copyWith(
                  fontSize: 24,
                  color: _C.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              Text(
                'Secure your cockpit. Enter a new password for your JustRide account.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _C.textSec,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXl),

              // ── Form card ─────────────────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: _C.surfContHigh,
                  border: Border.all(color: _C.outlineVariant),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(AppConstants.spacingLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── New Password ─────────────────────────────────
                    _FieldLabel(text: 'New Password'),
                    const SizedBox(height: AppConstants.spacingXs),
                    _PasswordField(
                      controller: _newPasswordCtrl,
                      hint: '••••••••',
                      obscure: _obscureNew,
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // ── Strength indicator ───────────────────────────
                    if (_newPasswordCtrl.text.isNotEmpty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Security Level',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: _C.textSec,
                            ),
                          ),
                          Text(
                            _strengthLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: _C.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppConstants.spacingXs),
                      _StrengthBar(strength: _strength),
                      const SizedBox(height: AppConstants.spacingMd),
                    ],

                    // ── Confirm Password ─────────────────────────────
                    _FieldLabel(text: 'Confirm New Password'),
                    const SizedBox(height: AppConstants.spacingXs),
                    _PasswordField(
                      controller: _confirmPasswordCtrl,
                      hint: '••••••••',
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    const SizedBox(height: AppConstants.spacingLg),

                    // ── Reset Button ─────────────────────────────────
                    _ResetButton(onPressed: _onReset),
                    const SizedBox(height: AppConstants.spacingMd),

                    // ── Back to Login ────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.arrow_back_rounded,
                                color: _C.textSec, size: 16),
                            const SizedBox(width: AppConstants.spacingXs),
                            Text(
                              'Back to Login',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: _C.textSec,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingSection),
            ],
          ),
        ),
      ),
    );
  }

  void _onReset() {
    // Navigate back to login or success screen
    Navigator.of(context).pushReplacementNamed('/login');
  }
}

// ── Field Label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: _C.textSec,
      ),
    );
  }
}

// ── Password Field ─────────────────────────────────────────────────────────────
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.onChanged,
  });
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;

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
          color: _C.cardBgInput,
          borderRadius: BorderRadius.circular(AppConstants.radiusSm),
          border: Border.all(
            color: _focused ? _C.primary : _C.inputBorder,
            width: _focused ? 1.5 : 1.0,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: _C.primary.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: TextField(
                controller: widget.controller,
                obscureText: widget.obscure,
                onChanged: widget.onChanged,
                style: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 16,
                    color: _C.onSurface),
                cursorColor: _C.primary,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 16,
                    color: _C.textSec.withValues(alpha: 0.4),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: widget.onToggle,
              icon: Icon(
                widget.obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _focused ? _C.primary : _C.textSec,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Strength Bar ───────────────────────────────────────────────────────────────
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.strength});
  final int strength; // 0–4

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(4, (i) {
        final active = i < strength;
        return Expanded(
          child: AnimatedContainer(
            duration: AppConstants.animNormal,
            height: 6,
            margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
            decoration: BoxDecoration(
              color: active ? _C.primary : _C.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.radiusCircle),
            ),
          ),
        );
      }),
    );
  }
}

// ── Reset Button ───────────────────────────────────────────────────────────────
class _ResetButton extends StatefulWidget {
  const _ResetButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: AppConstants.animFast,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: _C.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: [
              BoxShadow(
                color: _C.primary.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.refresh_rounded, color: _C.onPrimary, size: 20),
              const SizedBox(width: AppConstants.spacingSm),
              Text(
                'Reset Password',
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
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
