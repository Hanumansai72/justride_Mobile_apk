class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String role;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.role = 'USER',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? json['name']?.toString() ?? json['username']?.toString() ?? 'Rider',
      email: json['email']?.toString() ?? '',
      phone: json['phonenumber']?.toString() ?? json['phone']?.toString(),
      avatarUrl: json['avatarUrl']?.toString() ?? json['avatar']?.toString(),
      role: json['role']?.toString() ?? 'USER',
    );
  }


  Map<String, dynamic> toJson() => {
        '_id': id,
        'fullName': fullName,
        'email': email,
        if (phone != null) 'phone': phone,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        'role': role,
      };
}

class DeviceModel {
  final String id;
  final String deviceId;
  final String deviceName;
  final String model;
  final String firmwareVersion;
  final String latestFirmwareVersion;
  final bool hasUpdateAvailable;
  final int batteryLevel;
  final String connectionState;
  final bool isOnline;
  final bool isBlocked;
  final bool isActive;
  final bool isRetired;
  final String? blockReason;
  // BLE MAC address from backend – used to reconnect to the exact hardware
  final String? bleAddress;

  const DeviceModel({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.model,
    required this.firmwareVersion,
    this.latestFirmwareVersion = 'v2.2.0',
    this.hasUpdateAvailable = true,
    this.batteryLevel = 98,
    this.connectionState = 'Connected',
    this.isOnline = true,
    this.isBlocked = false,
    this.isActive = true,
    this.isRetired = false,
    this.blockReason,
    this.bleAddress,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    final devName = json['devicename']?.toString() ??
        json['deviceName']?.toString() ??
        json['name']?.toString() ??
        'JustRide Device';
    final devId = json['device_id']?.toString() ??
        json['deviceId']?.toString() ??
        json['BLE_ADDRESS']?.toString() ??
        json['serialnumber']?.toString() ??
        '';
    final fw = json['firmware_version']?.toString() ??
        json['device_version']?.toString() ??
        'v1.0.0';
    final latestFw = json['latest_firmware']?.toString() ??
        json['latestFirmwareVersion']?.toString() ??
        'v2.0.0';
    final hasUpdate = json['firmware_update_available'] == true ||
        json['hasUpdateAvailable'] == true;

    final isBlocked = json['is_blocked'] == true || json['isBlocked'] == true;
    final isActive = json['is_active'] != false && json['isActive'] != false;
    final isRetired = json['is_retired'] == true || json['isRetired'] == true;
    final blockReason = json['block_reason']?.toString();

    // Device is only paired/online if active, NOT blocked, and NOT retired
    final isPaired = (json['is_paired'] == true ||
            json['isPaired'] == true ||
            json['status'] == 'CONNECTED' ||
            json['connectionState'] == 'Connected') &&
        !isBlocked &&
        !isRetired &&
        isActive;

    final String connState;
    if (isBlocked) {
      connState = 'Blocked';
    } else if (isRetired) {
      connState = 'Retired';
    } else if (!isActive) {
      connState = 'Inactive';
    } else if (isPaired) {
      connState = 'Connected';
    } else {
      connState = 'Disconnected';
    }

    return DeviceModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      deviceId: devId,
      deviceName: devName,
      model: json['device_version']?.toString() ?? json['model']?.toString() ?? 'JustRide Pro HUD',
      firmwareVersion: fw,
      latestFirmwareVersion: latestFw,
      hasUpdateAvailable: hasUpdate,
      batteryLevel: (json['batteryLevel'] as num?)?.toInt() ?? 85,
      connectionState: connState,
      isOnline: isPaired,
      isBlocked: isBlocked,
      isActive: isActive,
      isRetired: isRetired,
      blockReason: blockReason,
      bleAddress: json['BLE_ADDRESS']?.toString() ?? json['bleAddress']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'devicename': deviceName,
      'device_version': model,
      'firmware_version': firmwareVersion,
      'latest_firmware': latestFirmwareVersion,
      'hasUpdateAvailable': hasUpdateAvailable,
      'batteryLevel': batteryLevel,
      'status': isOnline ? 'CONNECTED' : (isBlocked ? 'BLOCKED' : 'DISCONNECTED'),
      'is_paired': isOnline,
      'connectionState': connectionState,
      'isOnline': isOnline,
      'is_blocked': isBlocked,
      'is_active': isActive,
      'is_retired': isRetired,
      if (blockReason != null) 'block_reason': blockReason,
      if (bleAddress != null) 'BLE_ADDRESS': bleAddress,
    };
  }
}


class SavedPlaceModel {
  final String id;
  final String title;
  final String address;
  final String type; // HOME, WORK, GYM, CAFE, OTHER
  final double? latitude;
  final double? longitude;

  const SavedPlaceModel({
    required this.id,
    required this.title,
    required this.address,
    required this.type,
    this.latitude,
    this.longitude,
  });

  factory SavedPlaceModel.fromJson(Map<String, dynamic> json) {
    double? lat;
    double? lng;

    if (json['coords'] is Map && json['coords']['coordinates'] is List) {
      final List coords = json['coords']['coordinates'];
      if (coords.length >= 2) {
        lng = (coords[0] as num?)?.toDouble();
        lat = (coords[1] as num?)?.toDouble();
      }
    } else {
      lat = (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble();
      lng = (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble();
    }

    final label = json['label']?.toString() ?? json['title']?.toString() ?? json['name']?.toString() ?? 'Saved Place';

    return SavedPlaceModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: label,
      address: json['address']?.toString() ?? '',
      type: label.toUpperCase(),
      latitude: lat,
      longitude: lng,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': title,
        'address': address,
        if (latitude != null && longitude != null)
          'coords': {
            'type': 'Point',
            'coordinates': [longitude, latitude],
          },
      };
}


class NotificationModel {
  final String id;
  final String title;
  final String message;
  final String type; // SYSTEM, FIRMWARE, SECURITY, TRIP
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'SYSTEM',
      isRead: json['isRead'] == true || json['read'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class ChatMessageModel {
  final String id;
  final String senderId;
  final String senderRole;
  final String senderName;
  final String body;
  final List<String> attachments;
  final DateTime createdAt;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    required this.attachments,
    required this.createdAt,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    String name = 'Support Agent';
    String sId = '';
    if (json['sender_id'] is Map) {
      name = json['sender_id']['name']?.toString() ?? 'Support Agent';
      sId = json['sender_id']['_id']?.toString() ?? '';
    } else if (json['sender_id'] != null) {
      sId = json['sender_id'].toString();
    }

    return ChatMessageModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      senderId: sId,
      senderRole: json['sender_role']?.toString().toUpperCase() ?? 'USER',
      senderName: name,
      body: json['body']?.toString() ?? json['message']?.toString() ?? '',
      attachments: (json['attachments'] as List?)?.map((e) => e.toString()).toList() ?? [],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class SupportTicketModel {
  final String id;
  final String ticketNumber;
  final String title;
  final String description;
  final String status; // OPEN, IN_PROGRESS, RESOLVED, CLOSED
  final String category; // device_problem, connection_issue, contact_support, feedback, general
  final List<ChatMessageModel> messages;
  final DateTime createdAt;

  const SupportTicketModel({
    required this.id,
    required this.ticketNumber,
    required this.title,
    required this.description,
    required this.status,
    required this.category,
    this.messages = const [],
    required this.createdAt,
  });

  factory SupportTicketModel.fromJson(Map<String, dynamic> json) {
    final rawMsgs = json['messages'] as List? ?? [];
    return SupportTicketModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      ticketNumber: json['ticket_number']?.toString() ?? json['ticketNumber']?.toString() ?? 'TKT-001',
      title: json['subject']?.toString() ?? json['title']?.toString() ?? 'Support Ticket',
      description: json['description']?.toString() ?? '',
      status: json['status']?.toString().toUpperCase() ?? 'OPEN',
      category: json['category']?.toString() ?? 'general',
      messages: rawMsgs.map((m) => ChatMessageModel.fromJson(m as Map<String, dynamic>)).toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

