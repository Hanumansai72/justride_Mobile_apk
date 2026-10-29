import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../models/app_models.dart';
import 'backend_service.dart';

/// One update check serves startup, resume, notification taps, and About.
class AppUpdateService extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdateService._();
  static final instance = AppUpdateService._();
  static const _platform = MethodChannel('com.justride.app/diagnostics');
  static const _requiredKey = 'justride_required_app_update';
  AppReleaseModel? release;
  int? installedBuild;
  String? installedVersion;
  String? error;
  bool verified = false;
  bool checking = false;
  bool opening = false;
  bool _initialized = false;
  bool startupComplete = false;
  bool _optionalDismissed = false;
  Future<void>? _request;

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get hasUpdate =>
      release != null &&
      installedBuild != null &&
      release!.buildNumber > installedBuild!;
  bool get required => hasUpdate && release!.isMandatory;
  bool get showOptionalUpdate => hasUpdate && !required && !_optionalDismissed;
  bool get blockAccess =>
      supported && (!startupComplete || required || showOptionalUpdate);

  void dismissOptionalUpdate() {
    if (required || !startupComplete) return;
    _optionalDismissed = true;
    notifyListeners();
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    if (supported) check();
  }

  Future<void> check() =>
      _request ??= _check().whenComplete(() => _request = null);

  Future<void> _check() async {
    checking = true;
    error = null;
    notifyListeners();
    try {
      installedBuild = AppConstants.appBuildNumber;
      installedVersion = AppConstants.appVersion;
      if (supported) {
        try {
          final info = await _platform
              .invokeMapMethod<String, dynamic>('appInfo')
              .timeout(const Duration(seconds: 3));
          installedBuild = (info?['build'] as num?)?.toInt() ?? installedBuild;
          installedVersion = info?['version'] as String? ?? installedVersion;
        } catch (_) {
          // The compiled build still permits a check if Android's bridge is busy.
        }
      }
      // An installed update clears the old in-memory mandatory gate on resume.
      if (release != null && release!.buildNumber <= installedBuild!) {
        release = null;
      }
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_requiredKey);
      if (cached != null) {
        try {
          final saved = AppReleaseModel.fromJson(jsonDecode(cached));
          if (saved.buildNumber > installedBuild!) release = saved;
        } catch (_) {
          /* The server response replaces an invalid cached record. */
        }
      }
      final response = await BackendService.instance
          .getLatestAppRelease(currentBuild: installedBuild!)
          .timeout(const Duration(seconds: 6));
      if (!response.success) {
        error = response.message;
        return;
      }
      release = response.data?.id.isNotEmpty == true ? response.data : null;
      verified = true;
      if (required) {
        await prefs.setString(
            _requiredKey,
            jsonEncode({
              'id': release!.id,
              'version': release!.version,
              'build_number': release!.buildNumber,
              'platform': 'android',
              'is_mandatory': true,
              'download_url': release!.downloadUrl,
            }));
      } else {
        await prefs.remove(_requiredKey);
      }
    } catch (_) {
      error =
          'Could not check for updates. Check your connection and try again.';
    } finally {
      // Network failure must not trap startup. A previously confirmed mandatory
      // release still blocks access, including while offline.
      startupComplete = true;
      checking = false;
      notifyListeners();
    }
  }

  Future<void> install() async {
    if (opening || !hasUpdate) return;
    final uri = Uri.tryParse(release?.downloadUrl ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      error = 'The update download is unavailable. Please try again later.';
      notifyListeners();
      return;
    }
    opening = true;
    error = null;
    notifyListeners();
    try {
      await _platform.invokeMethod('openApkDownload', {'url': uri.toString()});
    } catch (_) {
      error =
          'Could not open the update. Please try again on your Android phone.';
    } finally {
      opening = false;
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && supported) check();
  }
}
