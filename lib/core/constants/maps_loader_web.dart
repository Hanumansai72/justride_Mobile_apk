import 'dart:js_interop';

@JS('justRideLoadGoogleMaps')
external JSPromise<JSAny?> _loadGoogleMaps(JSString key);

Future<void> load(String apiKey) async {
  await _loadGoogleMaps(apiKey.toJS).toDart;
}
