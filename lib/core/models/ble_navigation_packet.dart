import 'dart:convert';
import 'dart:typed_data';
import 'navigation_state.dart';
import '../utils/route_window_transformer.dart';

/// Opcodes for JustRide BLE Navigation Protocol
enum BleNavOpCode {
  navStart(0x01),
  navUpdate(0x02),
  navReroute(0x03),
  navPause(0x04),
  navResume(0x05),
  navCancel(0x06),
  navArrived(0x07),
  navStop(0x08),
  deviceStatus(0x09),
  syncState(0x0A),
  navRouteSegment(0x0B),
  setBrightness(0x0C),
  restartDevice(0x0D),
  resetDevice(0x0E),
  latestNotification(0x0F),
  navContext(0x11);

  final int value;
  const BleNavOpCode(this.value);

  static BleNavOpCode fromValue(int val) {
    return BleNavOpCode.values.firstWhere(
      (e) => e.value == val,
      orElse: () => BleNavOpCode.navUpdate,
    );
  }
}

/// Maneuver code directly mapped to ESP32 nav_direction_t
enum JustRideManeuverCode {
  none(0),
  straight(1),
  slightLeft(2),
  slightRight(3),
  left(4),
  right(5),
  sharpLeft(6),
  sharpRight(7),
  uTurn(8),
  arrive(9),
  roundabout(10),
  roundaboutExit(11),
  merge(12),
  fork(13);

  final int value;
  const JustRideManeuverCode(this.value);

  static JustRideManeuverCode fromString(String str) {
    switch (str.toUpperCase()) {
      case 'STRAIGHT':
        return JustRideManeuverCode.straight;
      case 'SLIGHT_LEFT':
        return JustRideManeuverCode.slightLeft;
      case 'SLIGHT_RIGHT':
        return JustRideManeuverCode.slightRight;
      case 'LEFT':
      case 'TURN_LEFT':
        return JustRideManeuverCode.left;
      case 'RIGHT':
      case 'TURN_RIGHT':
        return JustRideManeuverCode.right;
      case 'SHARP_LEFT':
        return JustRideManeuverCode.sharpLeft;
      case 'SHARP_RIGHT':
        return JustRideManeuverCode.sharpRight;
      case 'U_TURN':
      case 'UTURN':
        return JustRideManeuverCode.uTurn;
      case 'ROUNDABOUT':
        return JustRideManeuverCode.roundabout;
      case 'ROUNDABOUT_EXIT':
      case 'EXIT':
        return JustRideManeuverCode.roundaboutExit;
      case 'MERGE':
        return JustRideManeuverCode.merge;
      case 'FORK':
      case 'FORK_LEFT':
      case 'FORK_RIGHT':
        return JustRideManeuverCode.fork;
      case 'ARRIVE':
      case 'REACHED':
        return JustRideManeuverCode.arrive;
      default:
        return JustRideManeuverCode.straight;
    }
  }
}

/// Helper to convert maneuver state string to byte code
int parseManeuverStateCode(String state) {
  switch (state.toUpperCase()) {
    case 'CURRENT_STRAIGHT':
    case 'STRAIGHT':
      return 1;
    case 'APPROACHING':
      return 2;
    case 'TURN_PREVIEW':
    case 'PREVIEW':
      return 3;
    case 'TURN_ACTIVE':
    case 'ACTIVE':
    case 'TURNING':
      return 4;
    case 'TURN_COMPLETED':
    case 'COMPLETED':
      return 5;
    default:
      return 0; // NONE
  }
}

/// BLE Navigation Packet encoder/decoder supporting both compact binary
/// and JSON development formats.
class BleNavigationPacket {
  final BleNavOpCode opCode;
  final JustRideManeuverCode maneuver;
  final int maneuverDistanceMeters;
  final int speedKmh;
  final int headingDeg;
  final int remainingDistanceMeters;
  final int remainingDurationSeconds;
  final String navigationStatus;
  final String streetName;
  final bool isNavigating;
  final bool isRerouting;
  final bool gpsAvailable;
  final bool bleConnected;
  final int maneuverId;
  final int maneuverState;
  final JustRideManeuverCode nextManeuver;
  final int nextManeuverDistanceMeters;
  final String nextManeuverText;

  const BleNavigationPacket({
    required this.opCode,
    required this.maneuver,
    required this.maneuverDistanceMeters,
    required this.speedKmh,
    required this.headingDeg,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    required this.navigationStatus,
    required this.streetName,
    this.isNavigating = true,
    this.isRerouting = false,
    this.gpsAvailable = true,
    this.bleConnected = true,
    this.maneuverId = 0,
    this.maneuverState = 0,
    this.nextManeuver = JustRideManeuverCode.straight,
    this.nextManeuverDistanceMeters = 0,
    this.nextManeuverText = '',
  });

  /// Factory helper from NavigationState
  factory BleNavigationPacket.fromState(
    NavigationState state, {
    BleNavOpCode opCode = BleNavOpCode.navUpdate,
  }) {
    return BleNavigationPacket(
      opCode: opCode,
      maneuver: JustRideManeuverCode.fromString(state.maneuver),
      maneuverDistanceMeters:
          state.maneuverDistanceMeters.clamp(0, 65535).round(),
      speedKmh: state.speedKmh.clamp(0, 300).round(),
      headingDeg: state.heading.clamp(0, 359).round(),
      remainingDistanceMeters:
          state.remainingDistanceMeters.clamp(0, 4294967295).round(),
      remainingDurationSeconds:
          state.remainingDurationSeconds.clamp(0, 4294967295),
      navigationStatus: state.navigationStatus,
      streetName: state.maneuverText,
      isNavigating: state.rideState.isActive,
      isRerouting: state.rerouting,
      gpsAvailable: state.gpsAvailable,
      bleConnected: state.bleConnected,
      maneuverId: state.maneuverId.clamp(0, 65535),
      maneuverState: parseManeuverStateCode(state.maneuverState),
      nextManeuver: JustRideManeuverCode.fromString(state.nextManeuver),
      nextManeuverDistanceMeters:
          state.nextManeuverDistanceMeters.clamp(0, 65535).round(),
      nextManeuverText: state.nextManeuverText,
    );
  }

  /// Compact Binary Serialization with 21-byte Header and Secondary Maneuver Extension
  Uint8List toBinary() {
    final cleanStreet = streetName.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    final textBytes = utf8.encode(
      cleanStreet.length > 31 ? cleanStreet.substring(0, 31) : cleanStreet,
    );
    final cleanNextStreet =
        nextManeuverText.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    final nextTextBytes = utf8.encode(
      cleanNextStreet.length > 31
          ? cleanNextStreet.substring(0, 31)
          : cleanNextStreet,
    );

    final totalLen = 21 + textBytes.length + 4 + nextTextBytes.length;
    final data = ByteData(totalLen);

    // Byte 0: OpCode
    data.setUint8(0, opCode.value);
    // Byte 1: Maneuver
    data.setUint8(1, maneuver.value);
    // Bytes 2-3: Maneuver Distance (uint16 LE)
    data.setUint16(2, maneuverDistanceMeters, Endian.little);
    // Bytes 4-5: Speed km/h (uint16 LE)
    data.setUint16(4, speedKmh, Endian.little);
    // Bytes 6-7: Heading degrees (uint16 LE)
    data.setUint16(6, headingDeg, Endian.little);
    // Bytes 8-11: Remaining Distance meters (uint32 LE)
    data.setUint32(8, remainingDistanceMeters, Endian.little);
    // Bytes 12-15: Remaining Duration seconds (uint32 LE)
    data.setUint32(12, remainingDurationSeconds, Endian.little);

    // Byte 16: Status flags
    int flags = 0;
    if (isNavigating) flags |= (1 << 0);
    if (isRerouting) flags |= (1 << 1);
    if (gpsAvailable) flags |= (1 << 2);
    if (bleConnected) flags |= (1 << 3);
    data.setUint8(16, flags);

    // Byte 17: Maneuver State code (0: none, 1: straight, 2: approaching, 3: preview, 4: active, 5: completed)
    data.setUint8(17, maneuverState);

    // Bytes 18-19: Maneuver ID (uint16 LE)
    data.setUint16(18, maneuverId, Endian.little);

    // Byte 20: Text length
    data.setUint8(20, textBytes.length);

    // Bytes 21..N: Street Name ASCII/UTF-8
    final result = data.buffer.asUint8List();
    result.setRange(21, 21 + textBytes.length, textBytes);

    // Secondary / Lookahead Maneuver extension:
    final nextOffset = 21 + textBytes.length;
    data.setUint8(nextOffset, nextManeuver.value);
    data.setUint16(nextOffset + 1, nextManeuverDistanceMeters.clamp(0, 65535),
        Endian.little);
    data.setUint8(nextOffset + 3, nextTextBytes.length);
    result.setRange(
        nextOffset + 4, nextOffset + 4 + nextTextBytes.length, nextTextBytes);
    return result;
  }

  /// Development JSON Serialization
  String toJsonString() {
    return jsonEncode({
      'type': opCode.name.toUpperCase(),
      'maneuver': maneuver.name.toUpperCase(),
      'maneuverId': maneuverId,
      'maneuverState': maneuverState,
      'maneuverDistance': maneuverDistanceMeters,
      'speed': speedKmh,
      'heading': headingDeg,
      'remainingDistance': remainingDistanceMeters,
      'eta': remainingDurationSeconds,
      'navigationStatus': navigationStatus,
      'street': streetName,
      'nextManeuver': nextManeuver.name.toUpperCase(),
      'nextManeuverDistance': nextManeuverDistanceMeters,
      'nextStreet': nextManeuverText,
    });
  }

  Uint8List toJsonBytes() => Uint8List.fromList(utf8.encode(toJsonString()));
}

/// Compact binary packet representing a sliding route window segment (OpCode 0x0B).
class RouteSegmentPacket {
  final List<ScreenPoint> points;
  final int completedSegmentCount;
  final int progressPercent;
  final bool isDestinationVisible;
  final ScreenPoint? destinationScreenPoint;

  const RouteSegmentPacket({
    required this.points,
    this.completedSegmentCount = 0,
    this.progressPercent = 0,
    this.isDestinationVisible = false,
    this.destinationScreenPoint,
  });

  factory RouteSegmentPacket.fromWindow(RouteWindowSegment segment) {
    return RouteSegmentPacket(
      points: segment.points,
      completedSegmentCount: segment.completedSegmentCount,
      progressPercent: segment.progressPercent,
      isDestinationVisible: segment.isDestinationVisible,
      destinationScreenPoint: segment.destinationScreenPoint,
    );
  }

  Uint8List toBinary() {
    final count = points.length.clamp(0, 16);
    final totalLen = 8 + count * 4;
    final data = ByteData(totalLen);

    // Byte 0: OpCode
    data.setUint8(0, BleNavOpCode.navRouteSegment.value);
    // Byte 1: Point count
    data.setUint8(1, count);
    // Byte 2: destination flag and count of completed leading segments.
    data.setUint8(
        2,
        (isDestinationVisible ? 1 : 0) |
            (completedSegmentCount.clamp(0, 15) << 1));
    // Bytes 3-4: Dest X (uint16 LE)
    data.setUint16(
        3, (destinationScreenPoint?.x ?? 0).clamp(0, 320), Endian.little);
    // Bytes 5-6: Dest Y (uint16 LE)
    data.setUint16(
        5, (destinationScreenPoint?.y ?? 0).clamp(0, 240), Endian.little);

    // Bytes 7..: Points [x0, y0, x1, y1, ...]
    int offset = 7;
    for (int i = 0; i < count; i++) {
      data.setUint16(offset, points[i].x.clamp(0, 320), Endian.little);
      data.setUint16(offset + 2, points[i].y.clamp(0, 240), Endian.little);
      offset += 4;
    }

    data.setUint8(offset, progressPercent.clamp(0, 100));

    return data.buffer.asUint8List();
  }
}

/// Optional low-rate city/POI context. Never used for turn guidance.
class NavContextPacket {
  final String city;
  final int poiType; // 0 none, 1 fuel, 2 motorcycle repair
  final int poiDistanceMeters;
  final String poiName;
  final ScreenPoint? poiPoint;

  const NavContextPacket({
    required this.city,
    this.poiType = 0,
    this.poiDistanceMeters = 0,
    this.poiName = '',
    this.poiPoint,
  });

  Uint8List toBinary() {
    List<int> ascii(String text, int max) => text.codeUnits
        .where((c) => c >= 32 && c <= 126)
        .take(max)
        .toList(growable: false);
    final cityBytes = ascii(city, 18);
    final nameBytes = ascii(poiName, 18);
    final data = ByteData(10 + cityBytes.length + nameBytes.length);
    var offset = 0;
    data.setUint8(offset++, BleNavOpCode.navContext.value);
    data.setUint8(offset++, cityBytes.length);
    for (final byte in cityBytes) {
      data.setUint8(offset++, byte);
    }
    data.setUint8(offset++, poiType.clamp(0, 2));
    data.setUint16(offset, poiDistanceMeters.clamp(0, 65535), Endian.little);
    offset += 2;
    data.setUint16(offset, poiPoint?.x ?? 0xffff, Endian.little);
    offset += 2;
    data.setUint16(offset, poiPoint?.y ?? 0xffff, Endian.little);
    offset += 2;
    data.setUint8(offset++, nameBytes.length);
    for (final byte in nameBytes) {
      data.setUint8(offset++, byte);
    }
    return data.buffer.asUint8List();
  }
}

/// Compact binary packet carrying strictly the latest notification to the ESP32 HUD display.
/// Layout:
///   [0]            : OpCode (0x0F)
///   [1]            : Title Length (T)
///   [2 .. 2+T-1]   : Title bytes (UTF-8)
///   [2+T]          : Message Length (M)
///   [3+T .. end]   : Message bytes (UTF-8)
List<int> hudUtf8(String value, int limit) {
  final bytes = <int>[];
  for (final rune in value.runes) {
    final next = utf8.encode(String.fromCharCode(rune));
    if (bytes.length + next.length > limit) break;
    bytes.addAll(next);
  }
  return bytes;
}

class LatestNotificationPacket {
  final String title, message, appName;
  const LatestNotificationPacket(
      {required this.title, required this.message, this.appName = ''});
  Uint8List toBinary() {
    final t = hudUtf8(title, 31),
        m = hudUtf8(message, 63),
        a = hudUtf8(appName, 23);
    return Uint8List.fromList([
      0x0f,
      t.length,
      ...t,
      m.length,
      ...m,
      if (a.isNotEmpty) ...[a.length, ...a]
    ]);
  }
}
