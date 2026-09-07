/// Endpoint constants matching JustRide Express Backend routes
abstract final class ApiEndpoints {
  // â”€â”€ Auth & Users (/api/users) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const String register = '/users/register';
  static const String login = '/users/login';
  static const String googleAuth = '/users/google';
  static const String refreshToken = '/users/refresh-token';
  static const String logout = '/users/logout';
  static const String forgotPassword = '/users/forgot-password';
  static const String resetPassword = '/users/reset-password';
  static const String getMe = '/users/me';
  static const String updateProfile = '/users/profile';
  static const String changePassword = '/users/change-password';
  static const String deleteAccount = '/users/delete-account';

  // â”€â”€ Devices & Firmware (/api/devices) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const String myDevice = '/devices/my-device';
  static const String checkPairing = '/devices/check-pairing';
  static const String pairDevice = '/devices/pair';
  static const String unlinkDevice = '/devices/unlink';
  static const String requestUnlinkOtp = '/devices/request-unlink-otp';
  static const String latestFirmware = '/firmware/latest';
  static const String appReleaseLatest = '/app-releases/latest';
  static String deviceCheckFirmware(String deviceId) => '/devices/$deviceId/firmware/check';
  static String deviceFirmwareHistory(String deviceId) => '/devices/$deviceId/firmware/history';
  static String deviceRecordFirmwareUpdate(String deviceId) => '/devices/$deviceId/firmware/update';

  // â”€â”€ Saved Addresses / Places (/api/addresses) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const String addresses = '/addresses';
  static String addressById(String id) => '/addresses/$id';

  // â”€â”€ Notifications (/api/notifications) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const String notifications = '/notifications';
  static String markNotificationAsRead(String id) => '/notifications/$id/read';
  static String deleteNotification(String id) => '/notifications/$id';

  // â”€â”€ Support & Tickets (/api/support) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const String myTickets = '/support/my-tickets';
  static String ticketDetails(String id) => '/support/tickets/$id';
  static String addTicketMessage(String id) => '/support/tickets/$id/messages';
  static const String reportDeviceProblem = '/support/device-problem';
  static const String reportConnectionIssue = '/support/connection-issue';
  static const String contactSupport = '/support/contact';
  static const String submitFeedback = '/support/feedback';

  // ── Media & Uploads (/api/upload) ──────────────────────────────────────────
  static const String uploadImage = '/upload/image';
}
