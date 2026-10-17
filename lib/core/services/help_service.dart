import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class HelpArticle {
  const HelpArticle(
      {required this.id,
      required this.category,
      required this.question,
      required this.steps,
      required this.keywords,
      required this.route,
      required this.supportCategory});
  final String id, category, question, keywords, route, supportCategory;
  final List<String> steps;
  factory HelpArticle.fromJson(Map<String, dynamic> json) => HelpArticle(
      id: json['id'],
      category: json['category'],
      question: json['question'],
      steps: List<String>.from(json['steps']),
      keywords: json['keywords'],
      route: json['route'],
      supportCategory: json['supportCategory']);
  bool matches(String query) => query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .every((word) => '$question $keywords ${steps.join(' ')}'
          .toLowerCase()
          .contains(word));
}

class HelpService {
  static Future<List<HelpArticle>> loadArticles() async {
    final json =
        jsonDecode(await rootBundle.loadString('assets/help/app_faqs.json'))
            as List;
    return json
        .map((item) => HelpArticle.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  // Called only after the user opts in. No GPS, email, phone number, credentials,
  // serial identifiers, notification contents or background logs are collected.
  static Future<Map<String, String>> collectDiagnostics(
      {String? errorCode}) async {
    final result = <String, String>{
      'app_version': AppConstants.appVersion,
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name
    };
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final phone = await const MethodChannel('com.justride.app/diagnostics')
            .invokeMapMethod<String, dynamic>('deviceInfo');
        for (final key in ['phone_model', 'os_version']) {
          if (phone?[key] is String && (phone![key] as String).isNotEmpty) {
            result[key] = phone[key];
          }
        }
      } on PlatformException {
        /* Device details are unavailable on this runtime. */
      } on MissingPluginException {
        /* Browser/test runtimes have no native channel. */
      }
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('justride_paired_device');
    if (raw != null) {
      try {
        final device = jsonDecode(raw);
        final version = device is Map ? device['firmware_version'] : null;
        if (version is String && version.isNotEmpty) {
          result['firmware_version'] = 'Cached: $version';
        }
      } on FormatException {/* No usable cached device information. */}
    }
    if (errorCode != null && errorCode.trim().isNotEmpty) {
      result['error_code'] = errorCode.trim();
    }
    return result;
  }

  static String formatDiagnostics(Map<String, String> data) => data.entries
      .map((entry) => '${entry.key.replaceAll('_', ' ')}: ${entry.value}')
      .join('\n');
}
