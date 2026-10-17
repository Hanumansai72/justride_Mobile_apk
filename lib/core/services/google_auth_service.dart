import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants/app_constants.dart';
import 'backend_service.dart';
import '../models/app_models.dart';
import '../network/api_client.dart';

/// Result container for Google Sign-In attempts
class GoogleAuthResult {
  final bool success;
  final String? message;
  final UserModel? user;
  final bool cancelled;

  const GoogleAuthResult({
    required this.success,
    this.message,
    this.user,
    this.cancelled = false,
  });
}

/// Dedicated service managing native Google Sign-In and backend session exchange
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: kIsWeb ? AppConstants.googleClientId : null,
    serverClientId: kIsWeb ? null : AppConstants.googleClientId,
    scopes: const ['email', 'profile'],
  );

  /// Performs Google Sign-In, retrieves OAuth credentials, and exchanges with backend
  Future<GoogleAuthResult> signIn() async {
    try {
      // Disconnect previous cached session to always allow account selection
      try {
        await _googleSignIn.signOut();
      } catch (_) {}

      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // User aborted the account picker dialog
        return const GoogleAuthResult(
          success: false,
          cancelled: true,
          message: 'Sign-in cancelled',
        );
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;
      final String? accessToken = auth.accessToken;

      debugPrint('[GoogleAuthService] Signed in: ${account.email}');

      if ((idToken == null || idToken.isEmpty) &&
          (accessToken == null || accessToken.isEmpty)) {
        return const GoogleAuthResult(
          success: false,
          message: 'Failed to retrieve Google credentials from device.',
        );
      }

      // Exchange token with JustRide Express Backend
      final ApiResponse<UserModel> res =
          await BackendService.instance.loginWithGoogle(
        idToken: idToken,
        accessToken: accessToken,
      );

      if (res.success && res.data != null) {
        return GoogleAuthResult(
          success: true,
          user: res.data,
          message: res.message,
        );
      } else {
        return GoogleAuthResult(
          success: false,
          message: res.message.isNotEmpty
              ? res.message
              : 'Backend authentication failed.',
        );
      }
    } catch (e, stack) {
      debugPrint('[GoogleAuthService] Exception: $e\n$stack');
      return GoogleAuthResult(
        success: false,
        message: 'Google Sign-In error: $e',
      );
    }
  }

  /// Sign out of Google session
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }
}
