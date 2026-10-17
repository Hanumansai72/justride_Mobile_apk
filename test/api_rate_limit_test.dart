import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:justride_ui/core/network/api_client.dart';
import 'package:justride_ui/core/services/backend_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiClient.instance.init();
  });
  test('429 exposes Retry-After and does not erase authentication', () async {
    await ApiClient.instance.saveAuthToken('test-token');
    final result = await http.runWithClient(
      () => ApiClient.instance.get('/devices/my-device'),
      () => MockClient((request) async => http.Response(
          jsonEncode({'success': false, 'message': 'Please wait.'}), 429,
          headers: {'retry-after': '23', 'content-type': 'application/json'})),
    );
    expect(result.statusCode, 429);
    expect(result.retryAfterSeconds, 23);
    expect(result.isTransientFailure, isTrue);
    expect(ApiClient.instance.token, 'test-token');
  });
  test(
      'authorization denial cannot be mistaken for a transient network failure',
      () {
    expect(ApiResponse.error('blocked', statusCode: 403).isTransientFailure,
        isFalse);
    expect(ApiResponse.error('offline').isTransientFailure, isTrue);
    expect(ApiResponse.error('unavailable', statusCode: 503).isTransientFailure,
        isTrue);
  });
  test('cached device does not disguise a 429 response as success', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('justride_paired_device', jsonEncode({
      '_id': 'device', 'devicename': 'JustRide', 'is_active': true,
      'is_blocked': false, 'is_retired': false,
    }));
    final result = await http.runWithClient(
      () => BackendService.instance.getMyDevice(),
      () => MockClient((_) async => http.Response('{"message":"Please wait"}', 429,
        headers: {'retry-after': '23'})),
    );
    expect(result.success, isFalse);
    expect(result.statusCode, 429);
    expect(result.retryAfterSeconds, 23);
    expect(result.data, isNotNull);
  });
  test(
      'concurrent device checks share one API request without caching later checks',
      () async {
    var calls = 0;
    await http.runWithClient(() async {
      final first = BackendService.instance.getMyDevice();
      final second = BackendService.instance.getMyDevice();
      expect(identical(first, second), isTrue);
      await Future.wait([first, second]);
      expect(calls, 1);
      await BackendService.instance.getMyDevice();
      expect(calls, 2);
    },
        () => MockClient((request) async {
              calls++;
              await Future<void>.delayed(const Duration(milliseconds: 5));
              return http.Response(
                  jsonEncode({
                    'success': true,
                    'data': {
                      '_id': 'device',
                      'devicename': 'JustRide',
                      'is_paired': true,
                      'is_active': true,
                      'is_blocked': false,
                      'is_retired': false,
                      'BLE_ADDRESS': 'AA:BB:CC:DD:EE:FF',
                    }
                  }),
                  200);
            }));
  });
}
