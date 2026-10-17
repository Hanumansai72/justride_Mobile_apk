import 'package:flutter/material.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/google_auth_service.dart';
import '../../../shared/widgets/app_logo.dart';
import '../../../shared/widgets/google_logo.dart';
import '../widgets/login_form.dart';
import '../widgets/social_login_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isGoogleLoading = false;

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleLoading) return;
    setState(() => _isGoogleLoading = true);

    try {
      final result = await GoogleAuthService.instance.signIn();

      if (!mounted) return;
      setState(() => _isGoogleLoading = false);

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, ${result.user?.fullName ?? "Rider"}!'),
            backgroundColor: AppColors.primaryContainer,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/dashboard');
      } else if (!result.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Google Sign-In failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGoogleLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.pagePadding),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        // Logo
                        const Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AppLogo(
                              iconSize: 32,
                              fontSize: 28,
                              showTagline: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        // Titles
                        Text('Welcome back!',
                            style: AppTextStyles.displayMedium),
                        const SizedBox(height: 8),
                        Text(
                          'Login to continue your journey',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 40),
                        // Login Form
                        const LoginForm(),
                        const SizedBox(height: 24),
                        // Divider
                        Row(
                          children: [
                            const Expanded(
                                child: Divider(color: AppColors.border)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child:
                                  Text('OR', style: AppTextStyles.labelSmall),
                            ),
                            const Expanded(
                                child: Divider(color: AppColors.border)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // Social Login Buttons
                        SocialLoginButton(
                          icon: _isGoogleLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textPrimary),
                                )
                              : const GoogleLogoWidget(size: 22),
                          label: _isGoogleLoading
                              ? 'Connecting to Google...'
                              : 'Continue with Google',
                          onPressed:
                              _isGoogleLoading ? () {} : _handleGoogleSignIn,
                        ),
                        const SizedBox(height: 32),
                        // Footer
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            Text(
                              "Don't have an account? ",
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondary),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context)
                                  .pushReplacementNamed('/signup'),
                              child: Text(
                                'Sign Up',
                                style: AppTextStyles.accentMedium
                                    .copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
