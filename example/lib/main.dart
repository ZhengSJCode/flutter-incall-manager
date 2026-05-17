import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_incall_manager/flutter_incall_manager.dart';

void main() {
  runApp(const InCallManagerDemoApp());
}

class InCallManagerDemoApp extends StatelessWidget {
  const InCallManagerDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InCall Manager Demo',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final InCallManager _manager = InCallManager();

  bool _isActive = false;
  bool _speakerphoneOn = false;
  bool _microphoneMute = false;
  bool _keepScreenOn = false;
  bool _proximitySensorOn = false;
  bool _wiredHeadsetPlugged = false;
  bool _proximityNear = false;
  String _selectedAudioDevice = '';
  String _audioFocusState = '';

  @override
  void initState() {
    super.initState();
    _listenToEvents();
  }

  void _listenToEvents() {
    _manager.proximityStream.listen((event) {
      setState(() => _proximityNear = event.isNear);
    });

    _manager.wiredHeadsetStream.listen((event) {
      setState(() {
        _wiredHeadsetPlugged = event.isPlugged;
      });
    });

    if (defaultTargetPlatform == TargetPlatform.android) {
      _manager.audioDeviceChangedStream.listen((event) {
        setState(() {
          _selectedAudioDevice = event.selectedAudioDevice ?? '';
        });
      });

      _manager.audioFocusChangeStream.listen((event) {
        setState(() {
          _audioFocusState = event.eventText ?? '';
        });
      });
    }
  }

  Future<void> _checkWiredHeadset() async {
    final plugged = await _manager.getIsWiredHeadsetPluggedIn();
    setState(() => _wiredHeadsetPlugged = plugged);
  }

  Future<void> _toggleCall() async {
    if (_isActive) {
      await _manager.stop(busytoneUriType: '_DEFAULT_');
      setState(() {
        _isActive = false;
        _speakerphoneOn = false;
        _microphoneMute = false;
        _proximitySensorOn = false;
      });
    } else {
      await _manager.start(media: 'audio', auto: true);
      setState(() => _isActive = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InCall Manager Demo'),
        actions: [
          IconButton(
            icon: Icon(_wiredHeadsetPlugged ? Icons.headset_mic : Icons.headset_off),
            tooltip: 'Wired Headset',
            onPressed: _checkWiredHeadset,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Call state
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Call State', style: Theme.of(context).textTheme.titleMedium),
                      Chip(
                        label: Text(_isActive ? 'Active' : 'Idle'),
                        backgroundColor: _isActive ? Colors.green.shade100 : Colors.grey.shade300,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _toggleCall,
                    icon: Icon(_isActive ? Icons.call_end : Icons.call),
                    label: Text(_isActive ? 'Stop Call' : 'Start Call'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _isActive ? Colors.red : Colors.green,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Audio Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audio Controls', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Speakerphone'),
                    value: _speakerphoneOn,
                    onChanged: _isActive
                        ? (v) {
                            _manager.setSpeakerphoneOn(v);
                            setState(() => _speakerphoneOn = v);
                          }
                        : null,
                    dense: true,
                  ),
                  SwitchListTile(
                    title: const Text('Microphone Mute'),
                    value: _microphoneMute,
                    onChanged: _isActive
                        ? (v) {
                            _manager.setMicrophoneMute(v);
                            setState(() => _microphoneMute = v);
                          }
                        : null,
                    dense: true,
                  ),
                  SwitchListTile(
                    title: const Text('Keep Screen On'),
                    value: _keepScreenOn,
                    onChanged: (v) {
                      _manager.setKeepScreenOn(v);
                      setState(() => _keepScreenOn = v);
                    },
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _manager.setForceSpeakerphoneOn(true);
                          },
                          child: const Text('Force Speaker On'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _manager.setForceSpeakerphoneOn(false);
                          },
                          child: const Text('Force Speaker Off'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            _manager.setForceSpeakerphoneOn(null);
                          },
                          child: const Text('Auto'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Sensor Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sensors', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Proximity Sensor'),
                    subtitle: Text(_proximityNear ? 'Near' : 'Far'),
                    value: _proximitySensorOn,
                    onChanged: (v) {
                      if (v) {
                        _manager.startProximitySensor();
                      } else {
                        _manager.stopProximitySensor();
                      }
                      setState(() => _proximitySensorOn = v);
                    },
                    dense: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Screen Controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Screen', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _manager.turnScreenOff(),
                          child: const Text('Turn Screen Off'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _manager.turnScreenOn(),
                          child: const Text('Turn Screen On'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _manager.pokeScreen(timeout: 3000),
                    child: const Text('Poke Screen (Android)'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Ringtone / Ringback
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tones', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _manager.startRingtone('_DEFAULT_'),
                        child: const Text('Ringtone'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.startRingback('_DEFAULT_'),
                        child: const Text('Ringback'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.stopRingtone(),
                        child: const Text('Stop Ringtone'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.stopRingback(),
                        child: const Text('Stop Ringback'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Audio Routing
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audio Routing', style: Theme.of(context).textTheme.titleMedium),
                  if (_selectedAudioDevice.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Selected: $_selectedAudioDevice'),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _manager.chooseAudioRoute('EARPIECE'),
                        child: const Text('Earpiece'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.chooseAudioRoute('SPEAKER_PHONE'),
                        child: const Text('Speaker'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.chooseAudioRoute('WIRED_HEADSET'),
                        child: const Text('Wired Headset'),
                      ),
                      OutlinedButton(
                        onPressed: () => _manager.chooseAudioRoute('BLUETOOTH'),
                        child: const Text('Bluetooth'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Audio Focus (Android)
          if (defaultTargetPlatform == TargetPlatform.android)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Audio Focus (Android)', style: Theme.of(context).textTheme.titleMedium),
                    if (_audioFocusState.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text('State: $_audioFocusState'),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final res = await _manager.requestAudioFocus();
                              if (mounted) _showSnackBar('AudioFocus: $res');
                            },
                            child: const Text('Request'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final res = await _manager.abandonAudioFocus();
                              if (mounted) _showSnackBar('Abandon: $res');
                            },
                            child: const Text('Abandon'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Flash (iOS)
          if (defaultTargetPlatform == TargetPlatform.iOS)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Flash / Torch (iOS)', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _manager.setFlashOn(true, brightness: 1.0),
                            child: const Text('Flash On'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _manager.setFlashOn(false),
                            child: const Text('Flash Off'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
