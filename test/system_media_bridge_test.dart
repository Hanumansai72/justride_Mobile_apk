import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justride_ui/core/models/ble_media_packet.dart';
import 'package:justride_ui/core/services/system_media_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.justride.app/system_media');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('refresh fetches playback again even when the track is unchanged',
      () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {
        'state': 4,
        'actions': 31,
        'volume': 50,
        'title': 'YouTube Music track',
        'artist': 'Artist',
      };
    });
    final first = encodeMediaSnapshot(await readSystemMedia());
    final refresh = encodeMediaSnapshot(await readSystemMedia(command: 7));
    expect(calls, ['getMediaSnapshot', 'getMediaSnapshot']);
    expect(refresh, first);
    expect(refresh.take(5), [0x12, 4, 31, 50, 19]);
    expect(refresh.length, 6 + refresh[4] + 6);
  });

  test('missing access and no session remain explicit device states', () async {
    for (final state in [1, 2, 3, 4]) {
      messenger.setMockMethodCallHandler(
          channel, (_) async => {'state': state});
      expect(encodeMediaSnapshot(await readSystemMedia())[1], state);
    }
  });

  test('bridge failures send an error instead of waiting indefinitely',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'SESSION_UNAVAILABLE');
    });
    expect(encodeMediaSnapshot(await readSystemMedia()), [0x12, 7, 0, 0, 0, 0]);
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(encodeMediaSnapshot(await readSystemMedia())[1], 7);
  });
  test('all six device controls call the intended native method and retain metadata', () async {
    final commands=<String>[];
    messenger.setMockMethodCallHandler(channel,(call) async {
      if(call.method=='getMediaSnapshot')return {'state':4,'title':'Actual track','actions':31};
      commands.add(call.method);return true;
    });
    for(var command=1;command<=6;command++) {
      expect((await readSystemMedia(command:command))['title'],'Actual track');
    }
    expect(commands,['play','pause','next','previous','volumeUp','volumeDown']);
  });
  test('music access opens Android settings without claiming permission was granted', () async {
    const notifications=MethodChannel('com.justride.app/system_notifications');
    var opened=false;
    messenger.setMockMethodCallHandler(notifications,(call) async {
      expect(call.method,'openNotificationSettings');opened=true;
    });
    messenger.setMockMethodCallHandler(channel,(_) async => {'state':1});
    try {
      expect((await readSystemMedia(command:8))['state'],1);
      expect(opened,isTrue);
    } finally {messenger.setMockMethodCallHandler(notifications,null);}
  });
  test('v5 adds real playback timing without changing legacy bytes', () {
    final snapshot = <Object?, Object?>{
      'state': 4,
      'actions': 31,
      'title': 'Track',
      'artist': 'Artist',
      'elapsedSeconds': 105,
      'durationSeconds': 200
    };
    final legacy = encodeMediaSnapshot(snapshot);
    final rich = encodeMediaSnapshot(snapshot, includeTimeline: true);
    expect(rich.take(legacy.length), legacy);
    expect(rich.skip(legacy.length), [105, 0, 0, 0, 200, 0, 0, 0]);
    final unknown = encodeMediaSnapshot({'state': 3}, includeTimeline: true);
    expect(unknown.sublist(unknown.length - 8), List.filled(8, 0));
    final clamped = encodeMediaSnapshot(
        {'elapsedSeconds': 999, 'durationSeconds': 10},
        includeTimeline: true);
    expect(clamped.sublist(clamped.length - 8), [10, 0, 0, 0, 10, 0, 0, 0]);
    final invalid = encodeMediaSnapshot(
        {'elapsedSeconds': double.infinity, 'durationSeconds': -1},
        includeTimeline: true);
    expect(invalid.sublist(invalid.length - 8), List.filled(8, 0));
  });
}
