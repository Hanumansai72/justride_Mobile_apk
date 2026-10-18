import 'package:flutter/services.dart';

Future<void> load(String apiKey) async {}

// The URL is fixed in native code, rather than accepting arbitrary launch targets.
Future<void> openAttribution() async {
  await const MethodChannel('com.justride.app/maps_config')
      .invokeMethod<void>('openLocationIq');
}
