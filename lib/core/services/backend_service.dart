import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../models/app_models.dart';
import 'bluetooth_service.dart';

/// Senior-Grade Service Layer bridging Flutter UI Controllers to the Node.js / Express Backend
class BackendService {
  BackendService._();
  static final BackendService instance = BackendService._();

  final ApiClient _api = ApiClient.instance;

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // 1. AUTHENTICATION & USER (/api/users)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<ApiResponse<UserModel>> login({
    required String email,
    required String password,
  }) async {
    final res = await _api.post<UserModel>(
      ApiEndpoints.login,
      body: {'email': email, 'password': password},
      fromJson: (json) => UserModel.fromJson(json['user'] ?? json),
    );
    if (res.success && res.data != null) {
      if (res.data is Map && (res.data as dynamic)['token'] != null) {
        await _api.saveAuthToken((res.data as dynamic)['token']);
      }
      await _api.saveUserData(res.data!.toJson());
    }
    return res;
  }

  Future<void> logout() async {
    try {
      await _api.post<void>(ApiEndpoints.logout);
    } catch (_) {}
    await _api.clearAuth();
  }


  Future<ApiResponse<UserModel>> register({
    required String name,
    required String email,
    required String password,
    required String phonenumber,
  }) async {
    return _api.post<UserModel>(
      ApiEndpoints.register,
      body: {
        'name': name,
        'email': email,
        'password': password,
        'phonenumber': phonenumber,
      },
      fromJson: (json) => UserModel.fromJson(json['user'] ?? json),
    );
  }


  Future<ApiResponse<void>> forgotPassword(String email) async {
    return _api.post<void>(
      ApiEndpoints.forgotPassword,
      body: {'email': email},
    );
  }

  Future<ApiResponse<void>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return _api.post<void>(
      ApiEndpoints.resetPassword,
      body: {'token': token, 'password': newPassword},
    );
  }

  Future<ApiResponse<UserModel>> updateProfile({
    String? name,
    String? phonenumber,
    String? email,
  }) async {
    return _api.put<UserModel>(
      ApiEndpoints.updateProfile,
      body: {
        if (name != null) 'name': name,
        if (phonenumber != null) 'phonenumber': phonenumber,
        if (email != null) 'email': email,
      },
      fromJson: (json) => UserModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : (json is Map && json.containsKey('user') ? json['user'] : json)),
    );
  }

  Future<ApiResponse<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    return _api.put<void>(
      ApiEndpoints.changePassword,
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  Future<ApiResponse<UserModel>> getProfile() async {
    return _api.get<UserModel>(
      ApiEndpoints.getMe,
      fromJson: (json) => UserModel.fromJson(json['user'] ?? json),
    );
  }

  Future<ApiResponse<void>> deleteAccount([String? password]) async {
    final res = await _api.delete<void>(
      ApiEndpoints.deleteAccount,
      body: password != null ? {'password': password} : null,
    );
    if (res.success) {
      await _api.clearAuth();
    }
    return res;
  }


  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // 2. DEVICE & FIRMWARE (/api/devices)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<void> saveLocalDevice(DeviceModel device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('justride_paired_device', jsonEncode(device.toJson()));
  }

  Future<void> unpairLocalDevice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('justride_paired_device');
  }

  Future<ApiResponse<DeviceModel>> getMyDevice() async {
    final res = await _api.get<DeviceModel>(
      ApiEndpoints.myDevice,
      fromJson: (json) {
        if (json == null || (json is Map && json.isEmpty)) return null as dynamic;
        final data = json is Map && json.containsKey('device')
            ? json['device']
            : (json is Map && json.containsKey('data') ? json['data'] : json);
        if (data == null || (data is Map && data.isEmpty)) return null as dynamic;
        if (data is Map &&
            data['devicename'] == null &&
            data['deviceName'] == null &&
            data['name'] == null &&
            data['_id'] == null &&
            data['id'] == null &&
            data['device_id'] == null) {
          return null as dynamic;
        }
        return DeviceModel.fromJson(data is Map ? Map<String, dynamic>.from(data) : {});
      },
    );

    if (res.success) {
      final dev = res.data;
      // If no device is paired, or device is blocked / inactive / retired on the server:
      if (dev == null || dev.isBlocked || !dev.isActive || dev.isRetired) {
        await unpairLocalDevice();
        await JustRideBleService.instance.disconnectDevice();
        if (dev != null && dev.isBlocked) {
          return ApiResponse(
            success: false,
            message: dev.blockReason?.isNotEmpty == true
                ? 'Device blocked: ${dev.blockReason}'
                : 'This device is blocked and cannot be used.',
            errors: {'reason': 'DEVICE_BLOCKED'},
            data: null,
          );
        }
        return ApiResponse.success(data: null);
      }

      // Active and valid device
      await saveLocalDevice(dev);
      return res;
    }

    // Fallback to local stored device ONLY if offline and cached device is NOT blocked
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('justride_paired_device');
    if (raw != null) {
      try {
        final dev = DeviceModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (!dev.isBlocked && dev.isActive && !dev.isRetired) {
          return ApiResponse.success(data: dev);
        } else {
          await unpairLocalDevice();
          await JustRideBleService.instance.disconnectDevice();
        }
      } catch (_) {}
    }
    return res;
  }

  /// Verifies if current device is still active and valid.
  /// If blocked or unlinked, automatically disconnects Bluetooth and wipes local cache.
  Future<bool> checkAndEnforceDeviceStatus() async {
    final res = await getMyDevice();
    return res.success && res.data != null && !res.data!.isBlocked && res.data!.isActive;
  }


  /// Step 1 â€“ Pre-check: verify the device is registered in backend and available to pair.
  /// Returns success=true + can_pair=true if the device is claimable.
  Future<ApiResponse<Map<String, dynamic>>> checkDeviceAccess({
    required String bleAddress,
    String? deviceId,
  }) async {
    return _api.post<Map<String, dynamic>>(
      ApiEndpoints.checkPairing,
      body: {
        'BLE_ADDRESS': bleAddress,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      },
      fromJson: (json) => (json is Map ? Map<String, dynamic>.from(json) : {}),
    );
  }

  /// Step 2 â€“ Official pairing: register device to the logged-in user's account.
  /// Returns the DeviceModel with backend-issued pairing_code & device_hash.
  Future<ApiResponse<DeviceModel>> pairDevice({
    required String bleAddress,
    required String deviceName,
    String? deviceId,
    String? deviceVersion,
  }) async {
    final res = await _api.post<DeviceModel>(
      ApiEndpoints.pairDevice,
      body: {
        'BLE_ADDRESS': bleAddress,
        'devicename': deviceName,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        if (deviceVersion != null) 'device_version': deviceVersion,
      },
      fromJson: (json) {
        final data = json is Map && json.containsKey('data')
            ? Map<String, dynamic>.from(json['data'] as Map)
            : (json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{});
        return DeviceModel.fromJson(data);
      },
    );
    // Persist locally if backend pairing succeeded
    if (res.success && res.data != null) {
      await saveLocalDevice(res.data!);
    }
    return res;
  }

  Future<ApiResponse<Map<String, dynamic>>> checkFirmwareUpdate(String deviceId) async {
    return _api.get<Map<String, dynamic>>(
      ApiEndpoints.deviceCheckFirmware(deviceId),
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Get the active firmware release selected in Admin panel for device OTA
  Future<ApiResponse<Map<String, dynamic>>> getLatestFirmwareRelease() async {
    return _api.get<Map<String, dynamic>>(
      ApiEndpoints.latestFirmware,
      fromJson: (json) => json is Map && json.containsKey('data') ? json['data'] as Map<String, dynamic> : json as Map<String, dynamic>,
    );
  }

  /// Check for new mobile app APK updates published in Admin panel
  Future<ApiResponse<Map<String, dynamic>>> getLatestAppRelease({int currentBuild = 2}) async {
    return _api.get<Map<String, dynamic>>(
      '\?platform=android&current_build=\',
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // 3. SAVED PLACES (/api/addresses)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<ApiResponse<List<SavedPlaceModel>>> getSavedAddresses() async {
    return _api.get<List<SavedPlaceModel>>(
      ApiEndpoints.addresses,
      fromJson: (json) {
        final list = (json is List) ? json : (json['addresses'] as List? ?? []);
        return list.map((e) => SavedPlaceModel.fromJson(e)).toList();
      },
    );
  }

  Future<ApiResponse<SavedPlaceModel>> createSavedAddress({
    required String label,
    required String address,
    double latitude = 17.3850,
    double longitude = 78.4867,
  }) async {
    return _api.post<SavedPlaceModel>(
      ApiEndpoints.addresses,
      body: {
        'label': label,
        'address': address,
        'coords': {
          'type': 'Point',
          'coordinates': [longitude, latitude],
        },
      },
      fromJson: (json) => SavedPlaceModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : (json is Map && json.containsKey('address') ? json['address'] : json)),
    );
  }


  Future<ApiResponse<void>> deleteSavedAddress(String id) async {
    return _api.delete<void>(ApiEndpoints.addressById(id));
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // 4. NOTIFICATIONS (/api/notifications)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<ApiResponse<List<NotificationModel>>> getNotifications() async {
    return _api.get<List<NotificationModel>>(
      ApiEndpoints.notifications,
      fromJson: (json) {
        final list = (json is List) ? json : (json['notifications'] as List? ?? []);
        return list.map((e) => NotificationModel.fromJson(e)).toList();
      },
    );
  }

  Future<ApiResponse<void>> markNotificationAsRead(String id) async {
    return _api.patch<void>(ApiEndpoints.markNotificationAsRead(id));
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  // 5. SUPPORT & TICKETS (/api/support & /api/chat)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  Future<ApiResponse<List<SupportTicketModel>>> getMyTickets() async {
    return _api.get<List<SupportTicketModel>>(
      ApiEndpoints.myTickets,
      fromJson: (json) {
        final list = (json is List) ? json : (json['tickets'] as List? ?? []);
        return list.map((e) => SupportTicketModel.fromJson(e as Map<String, dynamic>)).toList();
      },
    );
  }

  Future<ApiResponse<SupportTicketModel>> getTicketDetails(String ticketId) async {
    return _api.get<SupportTicketModel>(
      ApiEndpoints.ticketDetails(ticketId),
      fromJson: (json) => SupportTicketModel.fromJson(json is Map && json.containsKey('ticket') ? json['ticket'] : json),
    );
  }

  Future<ApiResponse<SupportTicketModel>> createSupportTicket({
    required String subject,
    required String message,
    String category = 'contact_support',
    String priority = 'medium',
    String? deviceId,
  }) async {
    if (category == 'device_problem') {
      return _api.post<SupportTicketModel>(
        ApiEndpoints.reportDeviceProblem,
        body: {
          'subject': subject,
          'description': message,
          'priority': priority,
          if (deviceId != null) 'device_id': deviceId,
        },
        fromJson: (json) => SupportTicketModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : json),
      );
    } else if (category == 'connection_issue') {
      return _api.post<SupportTicketModel>(
        ApiEndpoints.reportConnectionIssue,
        body: {
          'description': message,
          if (deviceId != null) 'device_id': deviceId,
        },
        fromJson: (json) => SupportTicketModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : json),
      );
    } else {
      return _api.post<SupportTicketModel>(
        ApiEndpoints.contactSupport,
        body: {
          'subject': subject,
          'message': message,
          'priority': priority,
        },
        fromJson: (json) => SupportTicketModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : json),
      );
    }
  }

  Future<ApiResponse<ChatMessageModel>> sendTicketMessage({
    required String ticketId,
    required String message,
    List<String>? attachments,
  }) async {
    return _api.post<ChatMessageModel>(
      ApiEndpoints.addTicketMessage(ticketId),
      body: {
        'message': message,
        'body': message,
        if (attachments != null) 'attachments': attachments,
      },
      fromJson: (json) {
        if (json is Map && json.containsKey('messages') && json['messages'] is List && (json['messages'] as List).isNotEmpty) {
          return ChatMessageModel.fromJson((json['messages'] as List).last as Map<String, dynamic>);
        }
        return ChatMessageModel.fromJson(json is Map && json.containsKey('data') ? json['data'] : json);
      },
    );
  }
}

