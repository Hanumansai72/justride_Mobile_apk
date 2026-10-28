import '../services/push_notification_service.dart';
import '../services/bluetooth_service.dart';
import '../utils/user_facing_error.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/app.dart';
import '../routes/app_routes.dart';

/// Senior-Grade HTTP Client for JustRide Backend
/// Features:
/// - Base URL configuration for local / stage / prod
/// - Automatic JWT Bearer token injection
/// - Response standardisation matching Backend apiResponse wrapper
/// - Automatic Session Expiration detection (401/403) with instant redirect to Login
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();
  // Reuse HTTP connections instead of opening a new client for each request.
  final http.Client _client = http.Client();

  // Production / Staging Backend Host
  static const String baseUrl = 'https://backend.justride.cc/api';

  static const Duration timeoutDuration = Duration(seconds: 15);

  static const String _tokenKey = 'justride_auth_token';
  static const String _userKey = 'justride_user_data';

  String? _authToken;
  bool _isRedirectingToLogin = false;

  /// Initialize token from local storage on app start
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(_tokenKey);
  }

  String? get token => _authToken;
  bool get isAuthenticated => _authToken != null && _authToken!.isNotEmpty;

  Future<void> saveAuthToken(String token) async {
    _authToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    unawaited(PushNotificationService.instance.syncRegistration());
  }

  Future<void> saveUserData(Map<String, dynamic> userJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userJson));
  }

  Future<Map<String, dynamic>?> getSavedUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw != null) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> clearAuth() async {
    final oldToken = _authToken;
    _authToken = null;
    final fid = await PushNotificationService.instance.disable();
    if (fid != null && oldToken != null) {
      unawaited(_client
          .delete(
            Uri.parse('$baseUrl/notifications/push-registration'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $oldToken'
            },
            body: jsonEncode({'fid': fid}),
          )
          .timeout(const Duration(seconds: 3))
          .then<void>((_) {}, onError: (Object _) {}));
    }
    await JustRideBleService.instance.disableCompanion();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove('resume_active_session');
    await prefs.remove('resume_destination');
  }

  /// Handle session expiration: clears auth and forces user back to login screen
  void handleSessionExpired() {
    if (_isRedirectingToLogin) return;
    _isRedirectingToLogin = true;

    clearAuth().then((_) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil(
          AppRoutes.login,
          (route) => false,
        );
      }
      Future.delayed(const Duration(seconds: 2), () {
        _isRedirectingToLogin = false;
      });
    });
  }

  Map<String, String> _headers([Map<String, String>? extra]) {
    final map = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_authToken != null && _authToken!.isNotEmpty) {
      map['Authorization'] = 'Bearer $_authToken';
    }
    if (extra != null) {
      map.addAll(extra);
    }
    return map;
  }

  // ── GET ────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client
          .get(uri, headers: _headers(headers))
          .timeout(timeoutDuration);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  // ── POST ───────────────────────────────────────────────────────────
  Future<ApiResponse<T>> post<T>(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client
          .post(
            uri,
            headers: _headers(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  // ── PUT ────────────────────────────────────────────────────────────
  Future<ApiResponse<T>> put<T>(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client
          .put(
            uri,
            headers: _headers(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  // ── PATCH ──────────────────────────────────────────────────────────
  Future<ApiResponse<T>> patch<T>(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client
          .patch(
            uri,
            headers: _headers(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  // ── DELETE ─────────────────────────────────────────────────────────
  Future<ApiResponse<T>> delete<T>(
    String path, {
    dynamic body,
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final response = await _client
          .delete(
            uri,
            headers: _headers(headers),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeoutDuration);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  // ── MULTIPART UPLOAD ────────────────────────────────────────────────
  Future<ApiResponse<T>> uploadMultipart<T>(
    String path, {
    required List<int> fileBytes,
    required String filename,
    String fieldName = 'image',
    String? fileContentType,
    Map<String, String>? fields,
    Map<String, String>? headers,
    T Function(dynamic data)? fromJson,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl$path');
      final request = http.MultipartRequest('POST', uri);

      if (_authToken != null && _authToken!.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }
      if (headers != null) {
        request.headers.addAll(headers);
      }
      if (fields != null) {
        request.fields.addAll(fields);
      }

      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          fileBytes,
          filename: filename,
          contentType:
              fileContentType == null ? null : MediaType.parse(fileContentType),
        ),
      );

      final streamedResponse =
          await _client.send(request).timeout(timeoutDuration);
      final response = await http.Response.fromStream(streamedResponse);
      return _handleResponse<T>(response, fromJson);
    } catch (e) {
      return ApiResponse.error(
          'Unable to connect. Check your internet connection and try again.');
    }
  }

  ApiResponse<T> _handleResponse<T>(
    http.Response res,
    T Function(dynamic data)? fromJson,
  ) {
    try {
      // Check 401 Unauthorized or 403 Session Invalidation
      if (res.statusCode == 401) {
        debugPrint(
            '[ApiClient] 401 Unauthorized encountered. Redirecting to Login...');
        handleSessionExpired();
      }

      final Map<String, dynamic> body =
          res.body.isNotEmpty ? jsonDecode(res.body) : {};
      final bool success = (res.statusCode >= 200 && res.statusCode < 300) &&
          (body['success'] == true || !body.containsKey('success'));

      if (success) {
        // Automatically capture and persist accessToken / token if returned by backend
        final String? token = body['accessToken'] as String? ??
            body['token'] as String? ??
            (body['data'] is Map
                ? (body['data'] as Map)['accessToken'] ??
                    (body['data'] as Map)['token']
                : null);
        if (token != null && token.isNotEmpty) {
          saveAuthToken(token);
        }

        final dynamic rawData = body.containsKey('data') ? body['data'] : body;
        final T? parsedData = (fromJson != null && rawData != null)
            ? fromJson(rawData)
            : rawData as T?;
        return ApiResponse.success(
          data: parsedData,
          message: body['message'] as String? ?? 'Success',
          statusCode: res.statusCode,
        );
      } else {
        return ApiResponse.error(
          body['message'] as String? ??
              'Unable to complete the request. Please try again.',
          statusCode: res.statusCode,
          errors: body['errors'],
          retryAfterSeconds: int.tryParse(res.headers['retry-after'] ?? ''),
        );
      }
    } catch (e) {
      return ApiResponse.error(
          'Unable to complete the request. Please try again.',
          statusCode: res.statusCode);
    }
  }
}

/// Standard Generic API Response container
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String message;
  final int? statusCode;
  final dynamic errors;
  final int? retryAfterSeconds;

  bool get isTransientFailure =>
      !success &&
      (statusCode == null || statusCode == 429 || statusCode! >= 500);

  ApiResponse({
    required this.success,
    this.data,
    required this.message,
    this.statusCode,
    this.errors,
    this.retryAfterSeconds,
  });

  factory ApiResponse.success({
    T? data,
    String message = 'Success',
    int? statusCode,
  }) =>
      ApiResponse(
        success: true,
        data: data,
        message: message,
        statusCode: statusCode,
      );

  factory ApiResponse.error(
    String message, {
    int? statusCode,
    dynamic errors,
    int? retryAfterSeconds,
  }) =>
      ApiResponse(
        success: false,
        message: statusCode != null && statusCode >= 500
            ? 'The service is temporarily unavailable. Please try again later.'
            : userFacingError(message),
        statusCode: statusCode,
        errors: errors,
        retryAfterSeconds: retryAfterSeconds,
      );
}
