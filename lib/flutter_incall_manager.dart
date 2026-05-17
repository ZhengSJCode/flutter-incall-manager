import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Events emitted from the native layer.
class InCallManagerEvents {
  final bool isNear;
  final bool isPlugged;
  final bool hasMic;
  final String? deviceName;
  final String? availableAudioDeviceList;
  final String? selectedAudioDevice;
  final String? eventText;
  final int? eventCode;

  InCallManagerEvents({
    this.isNear = false,
    this.isPlugged = false,
    this.hasMic = false,
    this.deviceName,
    this.availableAudioDeviceList,
    this.selectedAudioDevice,
    this.eventText,
    this.eventCode,
  });
}

class InCallManager {
  static const String channelName = 'incall_manager';

  final MethodChannel _channel = const MethodChannel(channelName);

  // Cache for audio URIs (matching JS behavior).
  final Map<String, Map<String, String?>> _audioUriMap = {
    'ringtone': {'_BUNDLE_': null, '_DEFAULT_': null},
    'ringback': {'_BUNDLE_': null, '_DEFAULT_': null},
    'busytone': {'_BUNDLE_': null, '_DEFAULT_': null},
  };

  bool _vibrate = false;

  /// Stream of proximity sensor events.
  Stream<InCallManagerEvents> get proximityStream {
    return EventChannel('${channelName}_proximity')
        .receiveBroadcastStream()
        .map((event) => InCallManagerEvents(isNear: event['isNear'] == true));
  }

  /// Stream of wired headset plug/unplug events.
  Stream<InCallManagerEvents> get wiredHeadsetStream {
    return EventChannel('${channelName}_wired_headset')
        .receiveBroadcastStream()
        .map((event) => InCallManagerEvents(
              isPlugged: event['isPlugged'] == true,
              hasMic: event['hasMic'] == true,
              deviceName: event['deviceName'] as String?,
            ));
  }

  /// Android-only: Stream of audio device change events.
  Stream<InCallManagerEvents> get audioDeviceChangedStream {
    return EventChannel('${channelName}_audio_device_changed')
        .receiveBroadcastStream()
        .map((event) => InCallManagerEvents(
              availableAudioDeviceList: event['availableAudioDeviceList'] as String?,
              selectedAudioDevice: event['selectedAudioDevice'] as String?,
            ));
  }

  /// Android-only: Stream of audio focus change events.
  Stream<InCallManagerEvents> get audioFocusChangeStream {
    return EventChannel('${channelName}_audio_focus_change')
        .receiveBroadcastStream()
        .map((event) => InCallManagerEvents(
              eventText: event['eventText'] as String?,
              eventCode: event['eventCode'] as int?,
            ));
  }

  /// Android-only: Stream of noisy audio events.
  Stream<void> get noisyAudioStream {
    return EventChannel('${channelName}_noisy_audio').receiveBroadcastStream();
  }

  /// Android-only: Stream of media button events.
  Stream<InCallManagerEvents> get mediaButtonStream {
    return EventChannel('${channelName}_media_button')
        .receiveBroadcastStream()
        .map((event) => InCallManagerEvents(
              eventText: event['eventText'] as String?,
              eventCode: event['eventCode'] as int?,
            ));
  }

  /// Start in-call management.
  ///
  /// [media] - 'audio' (default) or 'video'.
  /// [auto] - Automatic proximity sensor handling (default true).
  /// [ringbackUriType] - Optional ringback tone type to play immediately.
  Future<void> start({
    String media = 'audio',
    bool auto = true,
    String ringbackUriType = '',
  }) async {
    await _channel.invokeMethod('start', {
      'media': media,
      'auto': auto,
      'ringbackUriType': ringbackUriType,
    });
  }

  /// Stop in-call management.
  ///
  /// [busytoneUriType] - Optional busy tone type to play before stopping.
  Future<void> stop({String busytoneUriType = ''}) async {
    await _channel.invokeMethod('stop', {
      'busytoneUriType': busytoneUriType,
    });
  }

  /// Turn screen off (Android: uses proximity wake lock or manual dim).
  Future<void> turnScreenOff() async {
    await _channel.invokeMethod('turnScreenOff');
  }

  /// Turn screen on (Android: release proximity wake lock or restore brightness).
  Future<void> turnScreenOn() async {
    await _channel.invokeMethod('turnScreenOn');
  }

  /// Check if a wired headset is currently plugged in.
  Future<bool> getIsWiredHeadsetPluggedIn() async {
    final result = await _channel.invokeMethod<bool>('getIsWiredHeadsetPluggedIn');
    return result ?? false;
  }

  /// Set flash/torch on or off (iOS only).
  ///
  /// [enable] - true to turn on, false to turn off.
  /// [brightness] - Optional brightness level (0.0 - 1.0).
  Future<void> setFlashOn(bool enable, {double brightness = 0}) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _channel.invokeMethod('setFlashOn', {
        'enable': enable,
        'brightness': brightness,
      });
    }
  }

  /// Keep screen on or allow it to sleep.
  Future<void> setKeepScreenOn(bool enable) async {
    await _channel.invokeMethod('setKeepScreenOn', {
      'enable': enable,
    });
  }

  /// Turn speakerphone on or off.
  Future<void> setSpeakerphoneOn(bool enable) async {
    await _channel.invokeMethod('setSpeakerphoneOn', {
      'enable': enable,
    });
  }

  /// Force speakerphone state.
  ///
  /// [flag] - true: force on, false: force off, null: use default.
  Future<void> setForceSpeakerphoneOn(bool? flag) async {
    final int val;
    if (flag == null) {
      val = 0;
    } else if (flag) {
      val = 1;
    } else {
      val = -1;
    }
    await _channel.invokeMethod('setForceSpeakerphoneOn', {
      'flag': val,
    });
  }

  /// Mute or unmute the microphone.
  Future<void> setMicrophoneMute(bool enable) async {
    await _channel.invokeMethod('setMicrophoneMute', {
      'enable': enable,
    });
  }

  /// Start playing a ringtone.
  ///
  /// [ringtoneUriType] - '_DEFAULT_', '_BUNDLE_', or a custom file name.
  /// [vibratePattern] - Vibration pattern array (duration in ms, alternating on/off).
  /// [iosCategory] - 'playback' or 'default'.
  /// [seconds] - Duration in seconds before stopping (Android only, -1 = loop).
  Future<void> startRingtone(
    String ringtoneUriType, {
    List<int>? vibratePattern,
    String iosCategory = 'default',
    int seconds = -1,
  }) async {
    _vibrate = vibratePattern != null;
    await _channel.invokeMethod('startRingtone', {
      'ringtoneUriType': ringtoneUriType,
      'iosCategory': iosCategory,
      'seconds': seconds,
    });
    if (_vibrate && vibratePattern != null) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Stop the currently playing ringtone.
  Future<void> stopRingtone() async {
    await _channel.invokeMethod('stopRingtone');
  }

  /// Start the proximity sensor monitoring.
  Future<void> startProximitySensor() async {
    await _channel.invokeMethod('startProximitySensor');
  }

  /// Stop the proximity sensor monitoring.
  Future<void> stopProximitySensor() async {
    await _channel.invokeMethod('stopProximitySensor');
  }

  /// Start playing a ringback tone.
  ///
  /// [ringbackUriType] - '_DTMF_', '_DEFAULT_', '_BUNDLE_', or custom file name.
  Future<void> startRingback(String ringbackUriType) async {
    await _channel.invokeMethod('startRingback', {
      'ringbackUriType': ringbackUriType,
    });
  }

  /// Stop playing the ringback tone.
  Future<void> stopRingback() async {
    await _channel.invokeMethod('stopRingback');
  }

  /// Poke the screen to wake it up temporarily (Android only).
  ///
  /// [timeout] - Duration in ms (default 3000).
  Future<void> pokeScreen({int timeout = 3000}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod('pokeScreen', {
        'timeout': timeout,
      });
    }
  }

  /// Get the URI for a given audio type and file type.
  ///
  /// [audioType] - 'ringtone', 'ringback', or 'busytone'.
  /// [fileType] - '_BUNDLE_' or '_DEFAULT_'.
  Future<String?> getAudioUri(String audioType, String fileType) async {
    if (!_audioUriMap.containsKey(audioType)) {
      return null;
    }
    if (_audioUriMap[audioType]![fileType] != null) {
      return _audioUriMap[audioType]![fileType];
    }
    try {
      final result = await _channel.invokeMethod<String>('getAudioUri', {
        'audioType': audioType,
        'fileType': fileType,
      });
      if (result != null && result.isNotEmpty) {
        _audioUriMap[audioType]![fileType] = result;
        return result;
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  /// Choose audio route (EARPIECE, SPEAKER_PHONE, WIRED_HEADSET, BLUETOOTH).
  Future<Map<dynamic, dynamic>?> chooseAudioRoute(String route) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'chooseAudioRoute',
        {'route': route},
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Request audio focus (Android only).
  Future<String?> requestAudioFocus() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await _channel.invokeMethod<String>('requestAudioFocus');
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Abandon audio focus (Android only).
  Future<String?> abandonAudioFocus() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await _channel.invokeMethod<String>('abandonAudioFocus');
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
