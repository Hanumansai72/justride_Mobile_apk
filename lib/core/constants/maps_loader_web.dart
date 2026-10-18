import 'dart:js_interop';

@JS('justRideLoadGoogleMaps')
external JSPromise<JSAny?> _loadGoogleMaps(JSString key);

Future<void> load(String apiKey) async {
  await _loadGoogleMaps(apiKey.toJS).toDart;
}

@JS('window.open')
external JSAny? _openAttribution(JSString url, JSString target);
Future<void> openAttribution() async {
  _openAttribution('https://locationiq.com'.toJS, '_blank'.toJS);
}
