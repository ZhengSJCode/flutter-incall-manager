import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_incall_manager/flutter_incall_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InCallManager manager;
  late List<MethodCall> methodCalls;

  setUp(() {
    manager = InCallManager();
    methodCalls = [];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('incall_manager'),
      (MethodCall call) async {
        methodCalls.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('incall_manager'),
      null,
    );
  });

  // ==================== InCallManagerEvents ====================

  group('InCallManagerEvents', () {
    test('default values are correct', () {
      final event = InCallManagerEvents();
      expect(event.isNear, false);
      expect(event.isPlugged, false);
      expect(event.hasMic, false);
      expect(event.deviceName, isNull);
      expect(event.availableAudioDeviceList, isNull);
      expect(event.selectedAudioDevice, isNull);
      expect(event.eventText, isNull);
      expect(event.eventCode, isNull);
    });

    test('all fields can be set', () {
      final event = InCallManagerEvents(
        isNear: true,
        isPlugged: true,
        hasMic: true,
        deviceName: 'TestDevice',
        availableAudioDeviceList: '["SPEAKER_PHONE"]',
        selectedAudioDevice: 'SPEAKER_PHONE',
        eventText: 'AUDIOFOCUS_GAIN',
        eventCode: 1,
      );
      expect(event.isNear, true);
      expect(event.isPlugged, true);
      expect(event.hasMic, true);
      expect(event.deviceName, 'TestDevice');
      expect(event.availableAudioDeviceList, '["SPEAKER_PHONE"]');
      expect(event.selectedAudioDevice, 'SPEAKER_PHONE');
      expect(event.eventText, 'AUDIOFOCUS_GAIN');
      expect(event.eventCode, 1);
    });
  });

  // ==================== start / stop ====================

  group('start', () {
    test('sends default arguments', () async {
      await manager.start();
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'start');
      expect(methodCalls.first.arguments, {
        'media': 'audio',
        'auto': true,
        'ringbackUriType': '',
      });
    });

    test('sends video media with auto=false', () async {
      await manager.start(media: 'video', auto: false);
      expect(methodCalls.first.arguments, {
        'media': 'video',
        'auto': false,
        'ringbackUriType': '',
      });
    });

    test('sends ringback uri type', () async {
      await manager.start(ringbackUriType: '_DEFAULT_');
      expect(methodCalls.first.arguments, {
        'media': 'audio',
        'auto': true,
        'ringbackUriType': '_DEFAULT_',
      });
    });
  });

  group('stop', () {
    test('sends empty busytone by default', () async {
      await manager.stop();
      expect(methodCalls, hasLength(1));
      expect(methodCalls.first.method, 'stop');
      expect(methodCalls.first.arguments, {
        'busytoneUriType': '',
      });
    });

    test('sends busytone uri type', () async {
      await manager.stop(busytoneUriType: '_DEFAULT_');
      expect(methodCalls.first.arguments, {
        'busytoneUriType': '_DEFAULT_',
      });
    });
  });

  // ==================== Screen ====================

  group('turnScreenOn', () {
    test('invokes turnScreenOn', () async {
      await manager.turnScreenOn();
      expect(methodCalls.single.method, 'turnScreenOn');
    });
  });

  group('turnScreenOff', () {
    test('invokes turnScreenOff', () async {
      await manager.turnScreenOff();
      expect(methodCalls.single.method, 'turnScreenOff');
    });
  });

  group('setKeepScreenOn', () {
    test('sends true', () async {
      await manager.setKeepScreenOn(true);
      expect(methodCalls.single.method, 'setKeepScreenOn');
      expect(methodCalls.single.arguments, {'enable': true});
    });

    test('sends false', () async {
      await manager.setKeepScreenOn(false);
      expect(methodCalls.single.arguments, {'enable': false});
    });
  });

  // ==================== Speaker / Mute ====================

  group('setSpeakerphoneOn', () {
    test('sends true', () async {
      await manager.setSpeakerphoneOn(true);
      expect(methodCalls.single.method, 'setSpeakerphoneOn');
      expect(methodCalls.single.arguments, {'enable': true});
    });
  });

  group('setForceSpeakerphoneOn', () {
    test('null maps to 0', () async {
      await manager.setForceSpeakerphoneOn(null);
      expect(methodCalls.single.method, 'setForceSpeakerphoneOn');
      expect(methodCalls.single.arguments, {'flag': 0});
    });

    test('true maps to 1', () async {
      await manager.setForceSpeakerphoneOn(true);
      expect(methodCalls.single.arguments, {'flag': 1});
    });

    test('false maps to -1', () async {
      await manager.setForceSpeakerphoneOn(false);
      expect(methodCalls.single.arguments, {'flag': -1});
    });
  });

  group('setMicrophoneMute', () {
    test('sends true', () async {
      await manager.setMicrophoneMute(true);
      expect(methodCalls.single.method, 'setMicrophoneMute');
      expect(methodCalls.single.arguments, {'enable': true});
    });
  });

  // ==================== Ringtone ====================

  group('startRingtone', () {
    test('sends default arguments', () async {
      await manager.startRingtone('_DEFAULT_');
      expect(methodCalls.single.method, 'startRingtone');
      expect(methodCalls.single.arguments, {
        'ringtoneUriType': '_DEFAULT_',
        'iosCategory': 'default',
        'seconds': -1,
      });
    });

    test('sends seconds', () async {
      await manager.startRingtone('_DEFAULT_', seconds: 5);
      expect(methodCalls.single.arguments, {
        'ringtoneUriType': '_DEFAULT_',
        'iosCategory': 'default',
        'seconds': 5,
      });
    });

    test('sends iosCategory playback', () async {
      await manager.startRingtone('_DEFAULT_', iosCategory: 'playback');
      expect(methodCalls.single.arguments, {
        'ringtoneUriType': '_DEFAULT_',
        'iosCategory': 'playback',
        'seconds': -1,
      });
    });

    test('sends vibratePattern when provided', () async {
      await manager.startRingtone('_DEFAULT_', vibratePattern: [500, 1000, 500]);
      expect(methodCalls.single.arguments, {
        'ringtoneUriType': '_DEFAULT_',
        'iosCategory': 'default',
        'seconds': -1,
        'vibratePattern': [500, 1000, 500],
      });
    });

    test('omits vibratePattern when null', () async {
      await manager.startRingtone('_DEFAULT_', vibratePattern: null);
      final args = methodCalls.single.arguments as Map;
      expect(args.containsKey('vibratePattern'), false);
    });
  });

  group('stopRingtone', () {
    test('invokes stopRingtone', () async {
      await manager.stopRingtone();
      expect(methodCalls.single.method, 'stopRingtone');
    });
  });

  // ==================== Proximity ====================

  group('startProximitySensor', () {
    test('invokes startProximitySensor', () async {
      await manager.startProximitySensor();
      expect(methodCalls.single.method, 'startProximitySensor');
    });
  });

  group('stopProximitySensor', () {
    test('invokes stopProximitySensor', () async {
      await manager.stopProximitySensor();
      expect(methodCalls.single.method, 'stopProximitySensor');
    });
  });

  // ==================== Ringback ====================

  group('startRingback', () {
    test('sends ringback uri type', () async {
      await manager.startRingback('_DEFAULT_');
      expect(methodCalls.single.method, 'startRingback');
      expect(methodCalls.single.arguments, {
        'ringbackUriType': '_DEFAULT_',
      });
    });
  });

  group('stopRingback', () {
    test('invokes stopRingback', () async {
      await manager.stopRingback();
      expect(methodCalls.single.method, 'stopRingback');
    });
  });

  // ==================== pokeScreen ====================

  group('pokeScreen', () {
    test('sends default timeout', () async {
      await manager.pokeScreen();
      expect(methodCalls.single.method, 'pokeScreen');
      expect(methodCalls.single.arguments, {'timeout': 3000});
    });

    test('sends custom timeout', () async {
      await manager.pokeScreen(timeout: 5000);
      expect(methodCalls.single.arguments, {'timeout': 5000});
    });
  });

  // ==================== Audio URI ====================

  group('getAudioUri', () {
    test('returns null for invalid audioType', () async {
      final result = await manager.getAudioUri('invalid', '_DEFAULT_');
      expect(result, isNull);
    });

    test('calls method channel for ringtone', () async {
      // Set up a handler that returns a URI
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'getAudioUri') {
            return 'content://test/ringtone';
          }
          return null;
        },
      );

      final result = await manager.getAudioUri('ringtone', '_DEFAULT_');
      expect(result, 'content://test/ringtone');
      expect(methodCalls.last.method, 'getAudioUri');
    });

    test('caches audio uri and returns cached value', () async {
      int callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'getAudioUri') {
            callCount++;
            return 'content://test/ringtone_$callCount';
          }
          return null;
        },
      );

      final result1 = await manager.getAudioUri('ringtone', '_DEFAULT_');
      final result2 = await manager.getAudioUri('ringtone', '_DEFAULT_');
      // Second call should use cache, returning same value
      expect(result1, result2);
    });

    test('returns null when platform returns error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'getAudioUri') {
            throw MissingPluginException();
          }
          return null;
        },
      );

      final result = await manager.getAudioUri('ringtone', '_DEFAULT_');
      expect(result, isNull);
    });
  });

  // ==================== Wired Headset ====================

  group('getIsWiredHeadsetPluggedIn', () {
    test('returns false when platform returns null', () async {
      final result = await manager.getIsWiredHeadsetPluggedIn();
      expect(result, false);
    });

    test('returns true when platform returns true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'getIsWiredHeadsetPluggedIn') return true;
          return null;
        },
      );

      final result = await manager.getIsWiredHeadsetPluggedIn();
      expect(result, true);
    });
  });

  // ==================== Audio Route ====================

  group('chooseAudioRoute', () {
    test('sends route argument', () async {
      await manager.chooseAudioRoute('SPEAKER_PHONE');
      expect(methodCalls.single.method, 'chooseAudioRoute');
      expect(methodCalls.single.arguments, {'route': 'SPEAKER_PHONE'});
    });

    test('returns map from platform', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'chooseAudioRoute') {
            return {
              'availableAudioDeviceList': '["SPEAKER_PHONE","EARPIECE"]',
              'selectedAudioDevice': 'SPEAKER_PHONE',
            };
          }
          return null;
        },
      );

      final result = await manager.chooseAudioRoute('SPEAKER_PHONE');
      expect(result, isNotNull);
      expect(result!['selectedAudioDevice'], 'SPEAKER_PHONE');
    });

    test('returns null on platform error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'chooseAudioRoute') {
            throw MissingPluginException();
          }
          return null;
        },
      );

      final result = await manager.chooseAudioRoute('INVALID');
      expect(result, isNull);
    });
  });

  // ==================== Audio Focus ====================

  group('requestAudioFocus', () {
    test('sends method call', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'requestAudioFocus') {
            return 'AUDIOFOCUS_REQUEST_GRANTED';
          }
          return null;
        },
      );

      final result = await manager.requestAudioFocus();
      expect(methodCalls.last.method, 'requestAudioFocus');
      expect(result, 'AUDIOFOCUS_REQUEST_GRANTED');
    });

    test('returns null on platform error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'requestAudioFocus') {
            throw MissingPluginException();
          }
          return null;
        },
      );

      final result = await manager.requestAudioFocus();
      expect(result, isNull);
    });
  });

  group('abandonAudioFocus', () {
    test('sends method call', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('incall_manager'),
        (MethodCall call) async {
          methodCalls.add(call);
          if (call.method == 'abandonAudioFocus') {
            return 'AUDIOFOCUS_REQUEST_GRANTED';
          }
          return null;
        },
      );

      final result = await manager.abandonAudioFocus();
      expect(methodCalls.last.method, 'abandonAudioFocus');
      expect(result, 'AUDIOFOCUS_REQUEST_GRANTED');
    });
  });

  // ==================== Flash ====================

  group('setFlashOn', () {
    test('sends enable and brightness', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await manager.setFlashOn(true, brightness: 0.5);
        expect(methodCalls.single.method, 'setFlashOn');
        expect(methodCalls.single.arguments, {
          'enable': true,
          'brightness': 0.5,
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('sends brightness 0 when turning off', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await manager.setFlashOn(false);
        expect(methodCalls.single.arguments, {
          'enable': false,
          'brightness': 0,
        });
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('skips method call on non-iOS platform', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await manager.setFlashOn(true, brightness: 0.8);
        expect(methodCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ==================== Event Streams ====================

  group('proximityStream', () {
    test('maps isNear from event data', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.proximityStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_proximity',
        const StandardMethodCodec().encodeSuccessEnvelope({'isNear': true}),
        (ByteData? _) {},
      );

      expect(events, hasLength(1));
      expect(events.first.isNear, true);

      await subscription.cancel();
    });

    test('defaults isNear to false when missing', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.proximityStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_proximity',
        const StandardMethodCodec().encodeSuccessEnvelope(<String, dynamic>{}),
        (ByteData? _) {},
      );

      expect(events.first.isNear, false);

      await subscription.cancel();
    });
  });

  group('wiredHeadsetStream', () {
    test('maps all headset fields', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.wiredHeadsetStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_wired_headset',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'isPlugged': true,
          'hasMic': true,
          'deviceName': 'MyHeadset',
        }),
        (ByteData? _) {},
      );

      expect(events, hasLength(1));
      expect(events.first.isPlugged, true);
      expect(events.first.hasMic, true);
      expect(events.first.deviceName, 'MyHeadset');

      await subscription.cancel();
    });
  });

  group('audioDeviceChangedStream', () {
    test('maps audio device fields', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.audioDeviceChangedStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_audio_device_changed',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'availableAudioDeviceList': '["SPEAKER_PHONE","EARPIECE"]',
          'selectedAudioDevice': 'EARPIECE',
        }),
        (ByteData? _) {},
      );

      expect(events, hasLength(1));
      expect(
        events.first.availableAudioDeviceList,
        '["SPEAKER_PHONE","EARPIECE"]',
      );
      expect(events.first.selectedAudioDevice, 'EARPIECE');

      await subscription.cancel();
    });
  });

  group('audioFocusChangeStream', () {
    test('maps audio focus fields', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.audioFocusChangeStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_audio_focus_change',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'eventText': 'AUDIOFOCUS_LOSS',
          'eventCode': -3,
        }),
        (ByteData? _) {},
      );

      expect(events, hasLength(1));
      expect(events.first.eventText, 'AUDIOFOCUS_LOSS');
      expect(events.first.eventCode, -3);

      await subscription.cancel();
    });
  });

  group('noisyAudioStream', () {
    test('emits void events', () async {
      int eventCount = 0;
      final subscription = manager.noisyAudioStream.listen((_) {
        eventCount++;
      });

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_noisy_audio',
        const StandardMethodCodec().encodeSuccessEnvelope(null),
        (ByteData? _) {},
      );

      expect(eventCount, 1);

      await subscription.cancel();
    });
  });

  group('mediaButtonStream', () {
    test('maps media button fields', () async {
      final events = <InCallManagerEvents>[];
      final subscription = manager.mediaButtonStream.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'incall_manager_media_button',
        const StandardMethodCodec().encodeSuccessEnvelope({
          'eventText': 'KEYCODE_MEDIA_PLAY',
          'eventCode': 126,
        }),
        (ByteData? _) {},
      );

      expect(events, hasLength(1));
      expect(events.first.eventText, 'KEYCODE_MEDIA_PLAY');
      expect(events.first.eventCode, 126);

      await subscription.cancel();
    });
  });

  // ==================== Multiple invocation ====================

  group('multiple invocations', () {
    test('tracks all method calls in order', () async {
      await manager.start();
      await manager.setSpeakerphoneOn(true);
      await manager.startRingtone('_DEFAULT_');
      await manager.stopRingtone();
      await manager.stop();

      expect(methodCalls.length, 5);
      expect(methodCalls.map((c) => c.method), [
        'start',
        'setSpeakerphoneOn',
        'startRingtone',
        'stopRingtone',
        'stop',
      ]);
    });
  });
}
