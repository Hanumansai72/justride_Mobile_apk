import '../../../app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/widgets/app_logo.dart';

// ── Color tokens (consistent across all JustRide screens) ────────────────────
class _C {
  static const bg = AppColors.background;
  static const surfContHigh = AppColors.surfaceElevated;
  static const cardBg = AppColors.backgroundInset;
  static const primary = AppColors.primary;
  static const onPrimary = AppColors.onPrimary;
  static const textSec = AppColors.textSecondary;
  static const onSurface = AppColors.textPrimary;
  static const outlineVariant = AppColors.border;
  static const inputBorder = AppColors.border;
}

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  late final AnimationController _pingCtrl;
  late final Animation<double> _pingScale;
  late final Animation<double> _pingOpacity;

  @override
  void initState() {
    super.initState();
    _pingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
    _pingScale = Tween<double>(begin: 1.0, end: 1.6).animate(_pingCtrl);
    _pingOpacity = Tween<double>(begin: 0.3, end: 0.0).animate(_pingCtrl);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _pingCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          // Ambient background glow
          Positioned(
            top: -MediaQuery.of(context).size.height * 0.2,
            left: 0,
            right: 0,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.6,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    _C.primary.withValues(alpha: 0.05),
                    _C.bg.withValues(alpha: 0.0),
                  ],
                  radius: 0.7,
                ),
              ),
            ),
          ),
          _buildBody(context),
        ],
      ),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: _C.textSec, size: 24),
              ),
              // AppLogo — same as all screens
              const AppLogo(
                iconSize: 16,
                fontSize: 20,
                showTagline: false,
                isCentered: true,
              ),
              // Spacer to keep logo centred
              const SizedBox(width: 48),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Lock icon with pulsing ring ────────────────────────────
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pulsing ring
                    AnimatedBuilder(
                      animation: _pingCtrl,
                      builder: (_, __) => Transform.scale(
                        scale: _pingScale.value,
                        child: Opacity(
                          opacity: _pingOpacity.value,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: _C.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Icon container
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _C.surfContHigh,
                        border: Border.all(color: _C.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: _C.primary.withValues(alpha: 0.1),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: _C.primary,
                        size: 48,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingXl),

              // ── Title & subtitle ──────────────────────────────────────
              Text(
                'Forgot Password',
                style: AppTextStyles.headingLarge.copyWith(
                  fontSize: 24,
                  color: _C.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(
                'Enter your email address and we will send you instructions to reset your password.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: _C.textSec,
                  fontSize: 16,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacingXl),

              // ── Email input ───────────────────────────────────────────
              _EmailField(controller: _emailController),
              const SizedBox(height: AppConstants.spacingLg),

              // ── Continue button ───────────────────────────────────────
              _ContinueButton(onPressed: _onContinue),
              const SizedBox(height: AppConstants.spacingXl),

              // ── Support link ──────────────────────────────────────────
              GestureDetector(
                onTap: () {},
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.help_outline_rounded,
                        color: _C.textSec, size: 18),
                    const SizedBox(width: AppConstants.spacingXs),
                    Text(
                      'Need help? Contact support',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _C.textSec,
                        fontSize: 15,
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

  void _onContinue() {
    // Navigate to reset password screen
    Navigator.of(context).pushNamed('/reset-password');
  }
}

// ── Email Field ────────────────────────────────────────────────────────────────
class _EmailField extends StatefulWidget {
  const _EmailField({required this.controller});
  final TextEditingController controller;

  @override
  State<_EmailField> createState() => _EmailFieldState();
}

class _EmailFieldState extends State<_EmailField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (v) => setState(() => _focused = v),
      child: AnimatedContainer(
        duration: AppConstants.animFast,
        decoration: BoxDecoration(
          color: _C.cardBg,
          borderRadius: BorderRadius.circular(AppConstants.radiusMd),
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
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: AppConstants.spacingMd),
            Icon(Icons.mail_outline_rounded,
                color: _focused ? _C.primary : _C.textSec, size: 22),
            const SizedBox(width: AppConstants.spacingMd),
            Expanded(
              child: TextField(
                controller: widget.controller,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 16,
                  color: _C.onSurface,
                ),
                cursorColor: _C.primary,
                decoration: InputDecoration(
                  hintText: 'Enter email address',
                  hintStyle: TextStyle(
                    fontFamily: 'Stack Sans Text',
                    fontSize: 16,
                    color: _C.textSec.withValues(alpha: 0.5),
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

// ── Continue Button ────────────────────────────────────────────────────────────
class _ContinueButton extends StatefulWidget {
  const _ContinueButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  State<_ContinueButton> createState() => _ContinueButtonState();
}

class _ContinueButtonState extends State<_ContinueButton> {
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
                color: _C.primary.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Continue',
                style: TextStyle(
                  fontFamily: 'Stack Sans Text',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _C.onPrimary,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              const Icon(Icons.arrow_forward_rounded,
                  color: _C.onPrimary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
