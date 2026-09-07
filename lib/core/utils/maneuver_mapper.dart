import 'package:flutter/material.dart';
import '../models/ble_navigation_packet.dart';

/// Maps Google Navigation maneuvers to JustRide simplified motorcycle display instructions.
class ManeuverMapper {
  /// Converts Google Routes API maneuver string to JustRide standard maneuver enum string.
  /// If the maneuver tag is null or empty, optional [instructionText] is parsed
  /// to ensure maneuvers like U-turns or turns are never missed.
  static String toJustRideManeuver(String? googleManeuver, [String? instructionText]) {
    final upper = (googleManeuver ?? '').toUpperCase().replaceAll('-', '_');

    if (upper.contains('SHARP_LEFT')) return 'SHARP_LEFT';
    if (upper.contains('SHARP_RIGHT')) return 'SHARP_RIGHT';
    if (upper.contains('SLIGHT_LEFT')) return 'SLIGHT_LEFT';
    if (upper.contains('SLIGHT_RIGHT')) return 'SLIGHT_RIGHT';
    if (upper.contains('U_TURN') || upper.contains('UTURN')) return 'U_TURN';
    if (upper.contains('ROUNDABOUT')) return 'ROUNDABOUT';
    if (upper.contains('MERGE')) return 'MERGE';
    if (upper.contains('EXIT') || upper.contains('RAMP')) return 'EXIT';
    if (upper.contains('LEFT')) return 'LEFT';
    if (upper.contains('RIGHT')) return 'RIGHT';
    if (upper.contains('DESTINATION') || upper.contains('ARRIVE')) return 'ARRIVE';

    // Instruction text inspection fallback (e.g. "Make a U-turn at...", "Turn right onto...")
    // Supports English as well as regional Indian languages (Assamese, Bengali, Hindi, Telugu, Tamil, Kannada, Marathi, Gujarati, Malayalam)
    if (instructionText != null && instructionText.isNotEmpty) {
      final ins = instructionText.toUpperCase();
      // U-TURN check
      if (ins.contains('U-TURN') ||
          ins.contains('UTURN') ||
          ins.contains('U TURN') ||
          instructionText.contains('ইউ-টার্ন') ||
          instructionText.contains('यू-टर्न') ||
          instructionText.contains('యూ-టర్న్') ||
          instructionText.contains('யூ-டர்ன்')) {
        return 'U_TURN';
      }
      // SHARP / SLIGHT turns
      if (ins.contains('SHARP LEFT')) return 'SHARP_LEFT';
      if (ins.contains('SHARP RIGHT')) return 'SHARP_RIGHT';
      if (ins.contains('SLIGHT LEFT') || ins.contains('BEAR LEFT') || ins.contains('KEEP LEFT')) {
        return 'SLIGHT_LEFT';
      }
      if (ins.contains('SLIGHT RIGHT') || ins.contains('BEAR RIGHT') || ins.contains('KEEP RIGHT')) {
        return 'SLIGHT_RIGHT';
      }

      // LEFT keywords in English and Indian languages:
      // Assamese/Bengali: বাওঁ, বাওঁফালে, বাঁয়ে, বাঁদিক
      // Hindi/Urdu: बाएं, बाएँ, बायें, बायां, बाये
      // Telugu: ఎడమ, ఎడమవైపు
      // Tamil: இடது
      // Kannada: ಎಡ
      // Marathi: डावीकडे, डावे
      // Gujarati: ડાબે
      // Malayalam: ഇടത്തേക്ക്
      final isLeft = ins.contains('TURN LEFT') ||
          ins.contains('LEFT') ||
          instructionText.contains('বাওঁ') ||
          instructionText.contains('বাঁয়ে') ||
          instructionText.contains('বাঁদিক') ||
          instructionText.contains('बाएं') ||
          instructionText.contains('बाएँ') ||
          instructionText.contains('बायें') ||
          instructionText.contains('बायां') ||
          instructionText.contains('बाये') ||
          instructionText.contains('ఎడమ') ||
          instructionText.contains('இடது') ||
          instructionText.contains('ಎಡ') ||
          instructionText.contains('डावीकडे') ||
          instructionText.contains('डावे') ||
          instructionText.contains('ડાબે') ||
          instructionText.contains('ഇടത്തേക്ക്');

      // RIGHT keywords in English and Indian languages:
      // Assamese/Bengali: সোঁ, সোঁফালে, ডানে, ডানদিক
      // Hindi/Urdu: दाएं, दाएँ, दायें, दायां, दाये
      // Telugu: కుడి, కుడివైపు
      // Tamil: வலது
      // Kannada: ಬಲ
      // Marathi: उजवीकडे, उजवे
      // Gujarati: જમણે
      // Malayalam: വലത്തേക്ക്
      final isRight = ins.contains('TURN RIGHT') ||
          ins.contains('RIGHT') ||
          instructionText.contains('সোঁ') ||
          instructionText.contains('ডানে') ||
          instructionText.contains('ডানদিক') ||
          instructionText.contains('दाएं') ||
          instructionText.contains('दाएँ') ||
          instructionText.contains('दायें') ||
          instructionText.contains('दायां') ||
          instructionText.contains('दाये') ||
          instructionText.contains('కుడి') ||
          instructionText.contains('వలது') ||
          instructionText.contains('ಬಲ') ||
          instructionText.contains('उजवीकडे') ||
          instructionText.contains('उजवे') ||
          instructionText.contains('જમણે') ||
          instructionText.contains('വലത്തേക്ക്');

      if (isLeft && !isRight) return 'LEFT';
      if (isRight && !isLeft) return 'RIGHT';
      if (ins.contains('ROUNDABOUT') || instructionText.contains('गोल चक्कर')) return 'ROUNDABOUT';
      if (ins.contains('DESTINATION') || ins.contains('ARRIVE') || instructionText.contains('গন্তব্য') || instructionText.contains('गंतव्य')) return 'ARRIVE';
    }

    return 'STRAIGHT';
  }

  /// Maps JustRide maneuver to ESP32 nav_direction_t code
  static JustRideManeuverCode toManeuverCode(String maneuver) {
    return JustRideManeuverCode.fromString(maneuver);
  }

  /// Rider-friendly action label for high-contrast motorcycle HUD
  static String toRiderActionText(String maneuver) {
    switch (maneuver.toUpperCase()) {
      case 'LEFT':
        return 'TURN LEFT';
      case 'RIGHT':
        return 'TURN RIGHT';
      case 'SLIGHT_LEFT':
        return 'BEAR LEFT';
      case 'SLIGHT_RIGHT':
        return 'BEAR RIGHT';
      case 'SHARP_LEFT':
        return 'SHARP LEFT';
      case 'SHARP_RIGHT':
        return 'SHARP RIGHT';
      case 'U_TURN':
        return 'MAKE U-TURN';
      case 'ROUNDABOUT':
        return 'ROUNDABOUT';
      case 'MERGE':
        return 'MERGE';
      case 'EXIT':
        return 'TAKE EXIT';
      case 'ARRIVE':
        return 'YOU HAVE ARRIVED';
      case 'STRAIGHT':
      default:
        return 'CONTINUE STRAIGHT';
    }
  }

  /// Material Icon for in-app navigation banner
  static IconData toIcon(String maneuver) {
    switch (maneuver.toUpperCase()) {
      case 'LEFT':
        return Icons.turn_left_rounded;
      case 'RIGHT':
        return Icons.turn_right_rounded;
      case 'SLIGHT_LEFT':
        return Icons.turn_slight_left_rounded;
      case 'SLIGHT_RIGHT':
        return Icons.turn_slight_right_rounded;
      case 'SHARP_LEFT':
        return Icons.turn_sharp_left_rounded;
      case 'SHARP_RIGHT':
        return Icons.turn_sharp_right_rounded;
      case 'U_TURN':
        return Icons.u_turn_left_rounded;
      case 'ROUNDABOUT':
        return Icons.roundabout_left_rounded;
      case 'MERGE':
        return Icons.merge_type_rounded;
      case 'EXIT':
        return Icons.ramp_right_rounded;
      case 'ARRIVE':
        return Icons.flag_rounded;
      case 'STRAIGHT':
      default:
        return Icons.straight_rounded;
    }
  }

  /// Text arrow symbol for compact logging or fallbacks
  static String toArrowSymbol(String maneuver) {
    switch (maneuver.toUpperCase()) {
      case 'LEFT':
        return '←';
      case 'RIGHT':
        return '→';
      case 'SLIGHT_LEFT':
        return '↖';
      case 'SLIGHT_RIGHT':
        return '↗';
      case 'SHARP_LEFT':
        return '↙';
      case 'SHARP_RIGHT':
        return '↘';
      case 'U_TURN':
        return '↶';
      case 'ROUNDABOUT':
        return '↺';
      case 'ARRIVE':
        return '★';
      case 'STRAIGHT':
      default:
        return '↑';
    }
  }
}
