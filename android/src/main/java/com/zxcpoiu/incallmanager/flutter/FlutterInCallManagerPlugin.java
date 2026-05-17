package com.zxcpoiu.incallmanager.flutter;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.media.AudioAttributes;
import android.media.AudioDeviceInfo;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.provider.Settings;
import android.util.Log;
import android.view.KeyEvent;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import java.io.File;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class FlutterInCallManagerPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {

    private static final String TAG = "FlutterInCallManager";
    private static final String CHANNEL_NAME = "incall_manager";
    private static final String PROXIMITY_CHANNEL = CHANNEL_NAME + "_proximity";
    private static final String WIRED_HEADSET_CHANNEL = CHANNEL_NAME + "_wired_headset";
    private static final String AUDIO_DEVICE_CHANGED_CHANNEL = CHANNEL_NAME + "_audio_device_changed";
    private static final String AUDIO_FOCUS_CHANGE_CHANNEL = CHANNEL_NAME + "_audio_focus_change";
    private static final String NOISY_AUDIO_CHANNEL = CHANNEL_NAME + "_noisy_audio";
    private static final String MEDIA_BUTTON_CHANNEL = CHANNEL_NAME + "_media_button";

    private MethodChannel methodChannel;
    private EventChannel.EventSink proximitySink;
    private EventChannel.EventSink wiredHeadsetSink;
    private EventChannel.EventSink audioDeviceChangedSink;
    private EventChannel.EventSink audioFocusChangeSink;
    private EventChannel.EventSink noisyAudioSink;
    private EventChannel.EventSink mediaButtonSink;

    private Context context;
    private Activity activity;
    private FlutterPluginBinding flutterPluginBinding;

    // Audio Manager
    private AudioManager audioManager;
    private boolean audioManagerActivated = false;
    private boolean isAudioFocused = false;
    private boolean isOrigAudioSetupStored = false;
    private boolean origIsSpeakerPhoneOn = false;
    private boolean origIsMicrophoneMute = false;
    private int origAudioMode = AudioManager.MODE_INVALID;
    private boolean defaultSpeakerOn = false;
    private int defaultAudioMode = AudioManager.MODE_IN_COMMUNICATION;
    private int forceSpeakerOn = 0;
    private boolean automatic = true;

    // Screen Manager
    private PowerManager powerManager;
    private WindowManager windowManager;
    private WindowManager.LayoutParams lastLayoutParams;

    // Proximity
    private SensorManager sensorManager;
    private Sensor proximitySensor;
    private boolean isProximityRegistered = false;
    private boolean proximityIsNear = false;

    // Audio devices
    private enum AudioDevice { SPEAKER_PHONE, WIRED_HEADSET, EARPIECE, BLUETOOTH, NONE }
    private AudioDevice defaultAudioDevice = AudioDevice.NONE;
    private AudioDevice selectedAudioDevice = AudioDevice.NONE;
    private AudioDevice userSelectedAudioDevice = AudioDevice.NONE;
    private Set<AudioDevice> audioDevices = new HashSet<>();
    private boolean hasWiredHeadsetFlag = false;

    // Broadcast Receivers
    private BroadcastReceiver wiredHeadsetReceiver;
    private BroadcastReceiver noisyAudioReceiver;
    private BroadcastReceiver mediaButtonReceiver;

    // Media Players
    private MediaPlayer ringtonePlayer;
    private MediaPlayer ringbackPlayer;
    private MediaPlayer busytonePlayer;
    private Handler ringtoneCountDownHandler;
    private volatile Looper ringtoneLooper;

    private String media = "audio";
    private String packageName;

    // Vibrator
    private Vibrator vibrator;

    // Audio URI cache
    private Map<String, Uri> audioUriMap;
    private Uri defaultRingtoneUri;
    private Uri defaultRingbackUri;
    private Uri defaultBusytoneUri;
    private Uri bundleRingtoneUri;
    private Uri bundleRingbackUri;
    private Uri bundleBusytoneUri;

    // Audio attributes
    private AudioAttributes audioAttributes;
    private AudioFocusRequest audioFocusRequest;

    // ==================== FlutterPlugin ====================

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        flutterPluginBinding = binding;
        context = binding.getApplicationContext();
        packageName = context.getPackageName();

        audioManager = (AudioManager) context.getSystemService(Context.AUDIO_SERVICE);
        powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
        windowManager = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
        sensorManager = (SensorManager) context.getSystemService(Context.SENSOR_SERVICE);
        vibrator = (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
        if (sensorManager != null) {
            proximitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY);
        }

        audioUriMap = new HashMap<>();
        defaultRingtoneUri = Settings.System.DEFAULT_RINGTONE_URI;
        defaultRingbackUri = Settings.System.DEFAULT_RINGTONE_URI;
        defaultBusytoneUri = Settings.System.DEFAULT_NOTIFICATION_URI;
        audioUriMap.put("defaultRingtoneUri", defaultRingtoneUri);
        audioUriMap.put("defaultRingbackUri", defaultRingbackUri);
        audioUriMap.put("defaultBusytoneUri", defaultBusytoneUri);
        audioUriMap.put("bundleRingtoneUri", bundleRingtoneUri);
        audioUriMap.put("bundleRingbackUri", bundleRingbackUri);
        audioUriMap.put("bundleBusytoneUri", bundleBusytoneUri);

        methodChannel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        methodChannel.setMethodCallHandler(this);

        new EventChannel(binding.getBinaryMessenger(), PROXIMITY_CHANNEL)
                .setStreamHandler(new ProximityStreamHandler());
        new EventChannel(binding.getBinaryMessenger(), WIRED_HEADSET_CHANNEL)
                .setStreamHandler(new WiredHeadsetStreamHandler());
        new EventChannel(binding.getBinaryMessenger(), AUDIO_DEVICE_CHANGED_CHANNEL)
                .setStreamHandler(new AudioDeviceChangedStreamHandler());
        new EventChannel(binding.getBinaryMessenger(), AUDIO_FOCUS_CHANGE_CHANNEL)
                .setStreamHandler(new AudioFocusChangeStreamHandler());
        new EventChannel(binding.getBinaryMessenger(), NOISY_AUDIO_CHANNEL)
                .setStreamHandler(new NoisyAudioStreamHandler());
        new EventChannel(binding.getBinaryMessenger(), MEDIA_BUTTON_CHANNEL)
                .setStreamHandler(new MediaButtonStreamHandler());

        Log.d(TAG, "FlutterInCallManagerPlugin initialized");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stopRingtoneInternal();
        stopRingbackInternal();
        stopBusytoneInternal();
        stopInternal();
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
            methodChannel = null;
        }
        context = null;
        activity = null;
        flutterPluginBinding = null;
    }

    // Helper to get current Activity.
    private Activity getActivity() {
        return activity;
    }

    // ==================== ActivityAware ====================

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        activity = null;
    }

    @Override
    public void onReattachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
    }

    @Override
    public void onDetachedFromActivity() {
        activity = null;
    }

    // ==================== MethodCallHandler ====================

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "start":
                handleStart(call, result);
                break;
            case "stop":
                handleStop(call, result);
                break;
            case "turnScreenOn":
                handleTurnScreenOn(result);
                break;
            case "turnScreenOff":
                handleTurnScreenOff(result);
                break;
            case "setKeepScreenOn":
                handleSetKeepScreenOn(call, result);
                break;
            case "setSpeakerphoneOn":
                handleSetSpeakerphoneOn(call, result);
                break;
            case "setForceSpeakerphoneOn":
                handleSetForceSpeakerphoneOn(call, result);
                break;
            case "setMicrophoneMute":
                handleSetMicrophoneMute(call, result);
                break;
            case "startRingtone":
                handleStartRingtone(call, result);
                break;
            case "stopRingtone":
                handleStopRingtone(result);
                break;
            case "startProximitySensor":
                handleStartProximitySensor(result);
                break;
            case "stopProximitySensor":
                handleStopProximitySensor(result);
                break;
            case "startRingback":
                handleStartRingback(call, result);
                break;
            case "stopRingback":
                handleStopRingback(result);
                break;
            case "pokeScreen":
                handlePokeScreen(call, result);
                break;
            case "getAudioUri":
                handleGetAudioUri(call, result);
                break;
            case "getIsWiredHeadsetPluggedIn":
                handleGetIsWiredHeadsetPluggedIn(result);
                break;
            case "chooseAudioRoute":
                handleChooseAudioRoute(call, result);
                break;
            case "requestAudioFocus":
                handleRequestAudioFocus(result);
                break;
            case "abandonAudioFocus":
                handleAbandonAudioFocus(result);
                break;
            case "setFlashOn":
                // Android doesn't support setFlashOn
                result.success(null);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    // ==================== Start / Stop ====================

    private void handleStart(MethodCall call, Result result) {
        String _media = call.argument("media");
        boolean auto = call.argument("auto");
        String ringbackUriType = call.argument("ringbackUriType");

        if (_media != null) media = _media;
        if (media.equals("video")) {
            defaultSpeakerOn = true;
        } else {
            defaultSpeakerOn = false;
        }
        automatic = auto;

        if (!audioManagerActivated) {
            audioManagerActivated = true;
            Log.d(TAG, "start audioRouteManager");

            if (ringtonePlayer != null && ringtonePlayer.isPlaying()) {
                Log.d(TAG, "stop ringtone");
                stopRingtoneInternal();
            }
            storeOriginalAudioSetup();
            requestAudioFocusInternal();
            startEvents();

            audioManager.setMode(defaultAudioMode);
            setSpeakerphoneOnInternal(defaultSpeakerOn);
            audioManager.setMicrophoneMute(false);
            forceSpeakerOn = 0;
            hasWiredHeadsetFlag = hasWiredHeadset();
            defaultAudioDevice = defaultSpeakerOn ? AudioDevice.SPEAKER_PHONE
                    : (hasEarpiece() ? AudioDevice.EARPIECE : AudioDevice.SPEAKER_PHONE);
            userSelectedAudioDevice = AudioDevice.NONE;
            selectedAudioDevice = AudioDevice.NONE;
            audioDevices.clear();
            updateAudioDeviceState();

            if (ringbackUriType != null && !ringbackUriType.isEmpty()) {
                startRingbackInternal(ringbackUriType);
            }
        }
        result.success(null);
    }

    private void handleStop(MethodCall call, Result result) {
        String busytoneUriType = call.argument("busytoneUriType");
        if (audioManagerActivated) {
            stopRingbackInternal();
            if (busytoneUriType != null && !busytoneUriType.isEmpty() && startBusytone(busytoneUriType)) {
                Log.d(TAG, "play busytone before stop InCallManager");
                result.success(null);
                return;
            }
            stopInternal();
        }
        result.success(null);
    }

    private void stopInternal() {
        Log.d(TAG, "stop() InCallManager");
        stopBusytoneInternal();
        stopEvents();
        setSpeakerphoneOnInternal(false);
        audioManager.setMicrophoneMute(false);
        forceSpeakerOn = 0;
        restoreOriginalAudioSetup();
        abandonAudioFocusInternal();
        audioManagerActivated = false;
    }

    // ==================== Screen ====================

    private void handleTurnScreenOn(Result result) {
        Log.d(TAG, "turnScreenOn()");
        Activity act = getActivity();
        if (act == null) { result.success(null); return; }
        act.runOnUiThread(() -> {
            Window window = act.getWindow();
            if (lastLayoutParams != null) {
                window.setAttributes(lastLayoutParams);
            } else {
                WindowManager.LayoutParams params = window.getAttributes();
                params.screenBrightness = -1;
                window.setAttributes(params);
            }
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        });
        result.success(null);
    }

    private void handleTurnScreenOff(Result result) {
        Log.d(TAG, "turnScreenOff()");
        Activity act = getActivity();
        if (act == null) { result.success(null); return; }
        act.runOnUiThread(() -> {
            Window window = act.getWindow();
            lastLayoutParams = window.getAttributes();
            WindowManager.LayoutParams params = window.getAttributes();
            params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_OFF;
            window.setAttributes(params);
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        });
        result.success(null);
    }

    private void handleSetKeepScreenOn(MethodCall call, Result result) {
        boolean enable = call.argument("enable");
        Log.d(TAG, "setKeepScreenOn() " + enable);
        Activity act = getActivity();
        if (act == null) { result.success(null); return; }
        act.runOnUiThread(() -> {
            Window window = act.getWindow();
            if (enable) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            }
        });
        result.success(null);
    }

    private void handlePokeScreen(MethodCall call, Result result) {
        int timeout = call.argument("timeout");
        Log.d(TAG, "pokeScreen() timeout=" + timeout);
        // Acquire a temporary wake lock
        PowerManager.WakeLock wl = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "incallmanager:poke"
        );
        wl.acquire(timeout > 0 ? timeout : 3000);
        result.success(null);
    }

    // ==================== Speaker / Mute ====================

    private void handleSetSpeakerphoneOn(MethodCall call, Result result) {
        boolean enable = call.argument("enable");
        setSpeakerphoneOnInternal(enable);
        result.success(null);
    }

    private void setSpeakerphoneOnInternal(boolean enable) {
        if (enable != audioManager.isSpeakerphoneOn()) {
            Log.d(TAG, "setSpeakerphoneOn(): " + enable);
            audioManager.setMode(defaultAudioMode);
            audioManager.setSpeakerphoneOn(enable);
        }
    }

    private void handleSetForceSpeakerphoneOn(MethodCall call, Result result) {
        int flag = call.argument("flag");
        if (flag < -1 || flag > 1) { result.success(null); return; }
        Log.d(TAG, "setForceSpeakerphoneOn() flag: " + flag);
        forceSpeakerOn = flag;

        if (flag == 1) {
            if (audioDevices.contains(AudioDevice.SPEAKER_PHONE)) {
                userSelectedAudioDevice = AudioDevice.SPEAKER_PHONE;
            }
        } else if (flag == -1) {
            if (audioDevices.contains(AudioDevice.EARPIECE)) {
                userSelectedAudioDevice = AudioDevice.EARPIECE;
            }
        } else {
            userSelectedAudioDevice = AudioDevice.NONE;
        }
        updateAudioDeviceState();
        result.success(null);
    }

    private void handleSetMicrophoneMute(MethodCall call, Result result) {
        boolean enable = call.argument("enable");
        if (enable != audioManager.isMicrophoneMute()) {
            Log.d(TAG, "setMicrophoneMute(): " + enable);
            audioManager.setMicrophoneMute(enable);
        }
        result.success(null);
    }

    // ==================== Ringtone ====================

    private void handleStartRingtone(MethodCall call, Result result) {
        String ringtoneUriType = call.argument("ringtoneUriType");
        int seconds = call.argument("seconds");
        if (ringtoneUriType == null) ringtoneUriType = "_DEFAULT_";

        List<Integer> vibratePattern = call.argument("vibratePattern");
        if (vibratePattern != null && vibrator != null && vibrator.hasVibrator()) {
            long[] pattern = new long[vibratePattern.size()];
            for (int i = 0; i < vibratePattern.size(); i++) {
                pattern[i] = vibratePattern.get(i);
            }
            if (Build.VERSION.SDK_INT >= 26) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0));
            } else {
                vibrator.vibrate(pattern, 0);
            }
        }

        Log.d(TAG, "startRingtone(): UriType=" + ringtoneUriType);
        final String finalType = ringtoneUriType;
        final int finalSeconds = seconds;

        new Thread(() -> {
            Looper.prepare();
            ringtoneLooper = Looper.myLooper();
            try {
                if (ringtonePlayer != null) {
                    if (ringtonePlayer.isPlaying()) {
                        Log.d(TAG, "startRingtone(): is already playing");
                        ringtoneLooper.quit();
                        return;
                    }
                    stopRingtoneInternal();
                }

                if (audioManager.getStreamVolume(AudioManager.STREAM_RING) == 0) {
                    Log.d(TAG, "startRingtone(): ringer is silent. leave without play.");
                    ringtoneLooper.quit();
                    return;
                }

                Uri ringtoneUri = getRingtoneUri(finalType);
                if (ringtoneUri == null) {
                    Log.d(TAG, "startRingtone(): no available media");
                    ringtoneLooper.quit();
                    return;
                }

                if (audioManagerActivated) {
                    stopInternal();
                }

                storeOriginalAudioSetup();
                ringtonePlayer = new MediaPlayer();
                ringtonePlayer.setDataSource(context, ringtoneUri);
                ringtonePlayer.setLooping(true);
                ringtonePlayer.setAudioAttributes(
                        new AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                .build()
                );
                ringtonePlayer.prepare();
                audioManager.setMode(AudioManager.MODE_RINGTONE);
                updateAudioDeviceState();
                ringtonePlayer.start();

                if (finalSeconds > 0) {
                    ringtoneCountDownHandler = new Handler(Looper.myLooper());
                    ringtoneCountDownHandler.postDelayed(() -> {
                        Log.d(TAG, "mRingtoneCountDownHandler.stopRingtone() timeout after " + finalSeconds + " seconds");
                        stopRingtoneInternal();
                    }, finalSeconds * 1000L);
                }
                Looper.loop();
            } catch (Exception e) {
                Log.e(TAG, "startRingtone() failed", e);
            } finally {
                ringtoneLooper = null;
            }
        }).start();
        result.success(null);
    }

    private void handleStopRingtone(Result result) {
        stopRingtoneInternal();
        result.success(null);
    }

    private void stopRingtoneInternal() {
        try {
            if (ringtonePlayer != null) {
                ringtonePlayer.stop();
                ringtonePlayer.release();
                ringtonePlayer = null;
                restoreOriginalAudioSetup();
            }
            if (ringtoneCountDownHandler != null) {
                ringtoneCountDownHandler.removeCallbacksAndMessages(null);
                ringtoneCountDownHandler = null;
            }
            if (ringtoneLooper != null) {
                ringtoneLooper.quit();
                ringtoneLooper = null;
            }
            if (vibrator != null) {
                vibrator.cancel();
            }
        } catch (Exception e) {
            Log.d(TAG, "stopRingtone() failed");
        }
    }

    // ==================== Ringback ====================

    private void handleStartRingback(MethodCall call, Result result) {
        String ringbackUriType = call.argument("ringbackUriType");
        if (ringbackUriType == null || ringbackUriType.isEmpty()) {
            result.success(null);
            return;
        }
        startRingbackInternal(ringbackUriType);
        result.success(null);
    }

    private void startRingbackInternal(String ringbackUriType) {
        try {
            Log.d(TAG, "startRingback(): UriType=" + ringbackUriType);
            if (ringbackPlayer != null) {
                if (ringbackPlayer.isPlaying()) {
                    Log.d(TAG, "startRingback(): is already playing");
                    return;
                }
                stopRingbackInternal();
            }

            Uri ringbackUri = getRingbackUri(ringbackUriType);
            if (ringbackUri == null) {
                Log.d(TAG, "startRingback(): no available media");
                return;
            }

            ringbackPlayer = new MediaPlayer();
            ringbackPlayer.setDataSource(context, ringbackUri);
            ringbackPlayer.setLooping(true);
            ringbackPlayer.setAudioAttributes(
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build()
            );
            ringbackPlayer.prepare();
            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            updateAudioDeviceState();
            ringbackPlayer.start();
        } catch (Exception e) {
            Log.d(TAG, "startRingback() failed", e);
        }
    }

    private void handleStopRingback(Result result) {
        stopRingbackInternal();
        result.success(null);
    }

    private void stopRingbackInternal() {
        try {
            if (ringbackPlayer != null) {
                ringbackPlayer.stop();
                ringbackPlayer.release();
                ringbackPlayer = null;
            }
        } catch (Exception e) {
            Log.d(TAG, "stopRingback() failed");
        }
    }

    // ==================== Busytone ====================

    private boolean startBusytone(String busytoneUriType) {
        try {
            Log.d(TAG, "startBusytone(): UriType=" + busytoneUriType);
            if (busytonePlayer != null) {
                if (busytonePlayer.isPlaying()) {
                    Log.d(TAG, "startBusytone(): is already playing");
                    return false;
                }
                stopBusytoneInternal();
            }

            Uri busytoneUri = getBusytoneUri(busytoneUriType);
            if (busytoneUri == null) {
                Log.d(TAG, "startBusytone(): no available media");
                return false;
            }

            busytonePlayer = new MediaPlayer();
            busytonePlayer.setDataSource(context, busytoneUri);
            busytonePlayer.setLooping(false);
            busytonePlayer.setAudioAttributes(
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
            );
            busytonePlayer.setOnCompletionListener(mp -> {
                Log.d(TAG, "busytone onCompletion, invoke stop()");
                stopInternal();
            });
            busytonePlayer.prepare();
            audioManager.setMode(AudioManager.MODE_IN_COMMUNICATION);
            updateAudioDeviceState();
            busytonePlayer.start();
            return true;
        } catch (Exception e) {
            Log.d(TAG, "startBusytone() failed", e);
            return false;
        }
    }

    private void stopBusytoneInternal() {
        try {
            if (busytonePlayer != null) {
                busytonePlayer.stop();
                busytonePlayer.release();
                busytonePlayer = null;
            }
        } catch (Exception e) {
            Log.d(TAG, "stopBusytone() failed");
        }
    }

    // ==================== Proximity ====================

    private void handleStartProximitySensor(Result result) {
        if (proximitySensor == null) {
            Log.d(TAG, "Proximity Sensor is not supported.");
            result.success(null);
            return;
        }
        if (isProximityRegistered) {
            Log.d(TAG, "Proximity Sensor is already registered.");
            result.success(null);
            return;
        }
        Log.d(TAG, "startProximitySensor()");
        sensorManager.registerListener(proximityListener, proximitySensor, SensorManager.SENSOR_DELAY_NORMAL);
        isProximityRegistered = true;
        result.success(null);
    }

    private void handleStopProximitySensor(Result result) {
        if (proximitySensor == null || !isProximityRegistered) {
            result.success(null);
            return;
        }
        Log.d(TAG, "stopProximitySensor()");
        sensorManager.unregisterListener(proximityListener);
        isProximityRegistered = false;
        result.success(null);
    }

    private final SensorEventListener proximityListener = new SensorEventListener() {
        @Override
        public void onSensorChanged(SensorEvent event) {
            boolean isNear = event.values[0] < proximitySensor.getMaximumRange();
            if (isNear != proximityIsNear) {
                proximityIsNear = isNear;
                if (automatic && selectedAudioDevice == AudioDevice.EARPIECE) {
                    if (isNear) {
                        handleTurnScreenOff(new MethodChannel.Result() {
                            @Override public void success(Object o) {}
                            @Override public void error(String s, String s1, Object o) {}
                            @Override public void notImplemented() {}
                        });
                    } else {
                        handleTurnScreenOn(new MethodChannel.Result() {
                            @Override public void success(Object o) {}
                            @Override public void error(String s, String s1, Object o) {}
                            @Override public void notImplemented() {}
                        });
                    }
                    updateAudioDeviceState();
                }
                if (proximitySink != null) {
                    Map<String, Object> data = new HashMap<>();
                    data.put("isNear", isNear);
                    runOnMainThread(() -> proximitySink.success(data));
                }
            }
        }

        @Override
        public void onAccuracyChanged(Sensor sensor, int accuracy) {}
    };

    // ==================== Audio URI ====================

    private void handleGetAudioUri(MethodCall call, Result result) {
        String audioType = call.argument("audioType");
        String fileType = call.argument("fileType");
        Uri uri = null;
        if ("ringback".equals(audioType)) {
            uri = getRingbackUri(fileType);
        } else if ("busytone".equals(audioType)) {
            uri = getBusytoneUri(fileType);
        } else if ("ringtone".equals(audioType)) {
            uri = getRingtoneUri(fileType);
        }
        if (uri != null) {
            result.success(uri.toString());
        } else {
            result.error("error_code", "getAudioUri() failed", null);
        }
    }

    private void handleGetIsWiredHeadsetPluggedIn(Result result) {
        result.success(hasWiredHeadset());
    }

    private void handleChooseAudioRoute(MethodCall call, Result result) {
        String route = call.argument("route");
        Log.d(TAG, "chooseAudioRoute(): " + route);
        if (route != null) {
            try {
                AudioDevice device = AudioDevice.valueOf(route);
                if (audioDevices.contains(device)) {
                    userSelectedAudioDevice = device;
                }
            } catch (IllegalArgumentException e) {
                // ignore invalid route
            }
        }
        updateAudioDeviceState();
        Map<String, Object> resMap = new HashMap<>();
        resMap.put("availableAudioDeviceList", getAudioDeviceListJson());
        resMap.put("selectedAudioDevice", selectedAudioDevice != null ? selectedAudioDevice.name() : "");
        result.success(resMap);
    }

    private void handleRequestAudioFocus(Result result) {
        result.success(requestAudioFocusInternal());
    }

    private void handleAbandonAudioFocus(Result result) {
        result.success(abandonAudioFocusInternal());
    }

    // ==================== Audio Focus ====================

    private String requestAudioFocusInternal() {
        if (isAudioFocused) return "";
        String res;

        if (Build.VERSION.SDK_INT >= 26) {
            if (audioAttributes == null) {
                audioAttributes = new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build();
            }
            if (audioFocusRequest == null) {
                audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setAudioAttributes(audioAttributes)
                        .setAcceptsDelayedFocusGain(false)
                        .setWillPauseWhenDucked(false)
                        .setOnAudioFocusChangeListener(this::onAudioFocusChange)
                        .build();
            }
            int focusRes = audioManager.requestAudioFocus(audioFocusRequest);
            res = focusRes == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ? "AUDIOFOCUS_REQUEST_GRANTED"
                    : focusRes == AudioManager.AUDIOFOCUS_REQUEST_FAILED ? "AUDIOFOCUS_REQUEST_FAILED"
                    : focusRes == AudioManager.AUDIOFOCUS_REQUEST_DELAYED ? "AUDIOFOCUS_REQUEST_DELAYED"
                    : "AUDIOFOCUS_REQUEST_UNKNOWN";
        } else {
            int focusRes = audioManager.requestAudioFocus(
                    afChangeListener, AudioManager.STREAM_VOICE_CALL, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT);
            res = focusRes == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ? "AUDIOFOCUS_REQUEST_GRANTED"
                    : focusRes == AudioManager.AUDIOFOCUS_REQUEST_FAILED ? "AUDIOFOCUS_REQUEST_FAILED"
                    : "AUDIOFOCUS_REQUEST_UNKNOWN";
        }

        if ("AUDIOFOCUS_REQUEST_GRANTED".equals(res)) {
            isAudioFocused = true;
        }
        Log.d(TAG, "requestAudioFocus(): res = " + res);
        return res;
    }

    private String abandonAudioFocusInternal() {
        if (!isAudioFocused) return "";
        String res;

        if (Build.VERSION.SDK_INT >= 26 && audioFocusRequest != null) {
            int abandonRes = audioManager.abandonAudioFocusRequest(audioFocusRequest);
            res = abandonRes == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ? "AUDIOFOCUS_REQUEST_GRANTED"
                    : "AUDIOFOCUS_REQUEST_UNKNOWN";
        } else {
            int abandonRes = audioManager.abandonAudioFocus(afChangeListener);
            res = abandonRes == AudioManager.AUDIOFOCUS_REQUEST_GRANTED ? "AUDIOFOCUS_REQUEST_GRANTED"
                    : "AUDIOFOCUS_REQUEST_UNKNOWN";
        }

        if ("AUDIOFOCUS_REQUEST_GRANTED".equals(res)) {
            isAudioFocused = false;
        }
        Log.d(TAG, "abandonAudioFocus(): res = " + res);
        return res;
    }

    private final AudioManager.OnAudioFocusChangeListener afChangeListener = this::onAudioFocusChange;

    private void onAudioFocusChange(int focusChange) {
        String focusChangeStr;
        switch (focusChange) {
            case AudioManager.AUDIOFOCUS_GAIN: focusChangeStr = "AUDIOFOCUS_GAIN"; break;
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT: focusChangeStr = "AUDIOFOCUS_GAIN_TRANSIENT"; break;
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE: focusChangeStr = "AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE"; break;
            case AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK: focusChangeStr = "AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK"; break;
            case AudioManager.AUDIOFOCUS_LOSS: focusChangeStr = "AUDIOFOCUS_LOSS"; break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT: focusChangeStr = "AUDIOFOCUS_LOSS_TRANSIENT"; break;
            case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: focusChangeStr = "AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK"; break;
            case AudioManager.AUDIOFOCUS_NONE: focusChangeStr = "AUDIOFOCUS_NONE"; break;
            default: focusChangeStr = "AUDIOFOCUS_UNKNOW"; break;
        }
        Log.d(TAG, "onAudioFocusChange(): " + focusChange + " - " + focusChangeStr);

        if (audioFocusChangeSink != null) {
            Map<String, Object> data = new HashMap<>();
            data.put("eventText", focusChangeStr);
            data.put("eventCode", focusChange);
            runOnMainThread(() -> audioFocusChangeSink.success(data));
        }
    }

    // ==================== Audio Routing ====================

    private void setAudioDeviceInternal(AudioDevice device) {
        Log.d(TAG, "setAudioDeviceInternal(device=" + device + ")");
        if (!audioDevices.contains(device)) {
            Log.e(TAG, "specified audio device does not exist");
            return;
        }
        switch (device) {
            case SPEAKER_PHONE:
                setSpeakerphoneOnInternal(true);
                break;
            case EARPIECE:
            case WIRED_HEADSET:
            case BLUETOOTH:
                setSpeakerphoneOnInternal(false);
                break;
        }
        selectedAudioDevice = device;
    }

    private void updateAudioDeviceState() {
        Log.d(TAG, "--- updateAudioDeviceState: wired headset=" + hasWiredHeadsetFlag);

        Set<AudioDevice> newAudioDevices = new HashSet<>();
        newAudioDevices.add(AudioDevice.SPEAKER_PHONE);
        if (hasWiredHeadsetFlag) {
            newAudioDevices.add(AudioDevice.WIRED_HEADSET);
        }
        if (hasEarpiece()) {
            newAudioDevices.add(AudioDevice.EARPIECE);
        }

        if (userSelectedAudioDevice != null
                && userSelectedAudioDevice != AudioDevice.NONE
                && !newAudioDevices.contains(userSelectedAudioDevice)) {
            userSelectedAudioDevice = AudioDevice.NONE;
        }

        boolean audioDeviceSetUpdated = !audioDevices.equals(newAudioDevices);
        audioDevices = newAudioDevices;

        AudioDevice newAudioDevice = getPreferredAudioDevice();

        if (newAudioDevice != selectedAudioDevice || audioDeviceSetUpdated) {
            setAudioDeviceInternal(newAudioDevice);
            Log.d(TAG, "New device status: available=" + audioDevices + ", selected=" + newAudioDevice);

            if (audioDeviceChangedSink != null) {
                Map<String, Object> data = new HashMap<>();
                data.put("availableAudioDeviceList", getAudioDeviceListJson());
                data.put("selectedAudioDevice", selectedAudioDevice.name());
                runOnMainThread(() -> audioDeviceChangedSink.success(data));
            }
        }
        Log.d(TAG, "--- updateAudioDeviceState done");
    }

    private String getAudioDeviceListJson() {
        StringBuilder sb = new StringBuilder("[");
        boolean first = true;
        for (AudioDevice d : audioDevices) {
            if (!first) sb.append(",");
            sb.append("\"").append(d.name()).append("\"");
            first = false;
        }
        sb.append("]");
        return sb.toString();
    }

    private AudioDevice getPreferredAudioDevice() {
        if (userSelectedAudioDevice != null && userSelectedAudioDevice != AudioDevice.NONE) {
            return userSelectedAudioDevice;
        } else if (audioDevices.contains(AudioDevice.WIRED_HEADSET)) {
            return AudioDevice.WIRED_HEADSET;
        } else if (audioDevices.contains(defaultAudioDevice)) {
            return defaultAudioDevice;
        } else {
            return AudioDevice.SPEAKER_PHONE;
        }
    }

    private boolean hasEarpiece() {
        return context.getPackageManager().hasSystemFeature(PackageManager.FEATURE_TELEPHONY);
    }

    private boolean hasWiredHeadset() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return audioManager.isWiredHeadsetOn();
        } else {
            AudioDeviceInfo[] devices = audioManager.getDevices(AudioManager.GET_DEVICES_ALL);
            for (AudioDeviceInfo device : devices) {
                int type = device.getType();
                if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET
                        || type == AudioDeviceInfo.TYPE_USB_DEVICE
                        || type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES) {
                    return true;
                }
            }
            return false;
        }
    }

    // ==================== Events ====================

    private void startEvents() {
        startWiredHeadsetEvent();
        startNoisyAudioEvent();
        startMediaButtonEvent();
        handleStartProximitySensor(new MethodChannel.Result() {
            @Override public void success(Object o) {}
            @Override public void error(String s, String s1, Object o) {}
            @Override public void notImplemented() {}
        });
        // setKeepScreenOn(true)
        Activity act = getActivity();
        if (act != null) {
            act.runOnUiThread(() -> {
                Window window = act.getWindow();
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
            });
        }
    }

    private void stopEvents() {
        stopWiredHeadsetEvent();
        stopNoisyAudioEvent();
        stopMediaButtonEvent();
        handleStopProximitySensor(new MethodChannel.Result() {
            @Override public void success(Object o) {}
            @Override public void error(String s, String s1, Object o) {}
            @Override public void notImplemented() {}
        });
    }

    private void startWiredHeadsetEvent() {
        if (wiredHeadsetReceiver == null) {
            IntentFilter filter = new IntentFilter(
                    Build.VERSION.SDK_INT >= 21 ? AudioManager.ACTION_HEADSET_PLUG : Intent.ACTION_HEADSET_PLUG);
            wiredHeadsetReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent intent) {
                    String action = intent.getAction();
                    if ((Build.VERSION.SDK_INT >= 21 ? AudioManager.ACTION_HEADSET_PLUG : Intent.ACTION_HEADSET_PLUG).equals(action)) {
                        hasWiredHeadsetFlag = intent.getIntExtra("state", 0) == 1;
                        updateAudioDeviceState();
                        if (wiredHeadsetSink != null) {
                            Map<String, Object> data = new HashMap<>();
                            data.put("isPlugged", intent.getIntExtra("state", 0) == 1);
                            data.put("hasMic", intent.getIntExtra("microphone", 0) == 1);
                            data.put("deviceName", intent.getStringExtra("name") != null ? intent.getStringExtra("name") : "");
                            runOnMainThread(() -> wiredHeadsetSink.success(data));
                        }
                    }
                }
            };
            context.registerReceiver(wiredHeadsetReceiver, filter);
        }
    }

    private void stopWiredHeadsetEvent() {
        if (wiredHeadsetReceiver != null) {
            try { context.unregisterReceiver(wiredHeadsetReceiver); } catch (Exception e) {}
            wiredHeadsetReceiver = null;
        }
    }

    private void startNoisyAudioEvent() {
        if (noisyAudioReceiver == null) {
            noisyAudioReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent intent) {
                    if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(intent.getAction())) {
                        updateAudioDeviceState();
                        if (noisyAudioSink != null) {
                            runOnMainThread(() -> noisyAudioSink.success(null));
                        }
                    }
                }
            };
            context.registerReceiver(noisyAudioReceiver,
                    new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
        }
    }

    private void stopNoisyAudioEvent() {
        if (noisyAudioReceiver != null) {
            try { context.unregisterReceiver(noisyAudioReceiver); } catch (Exception e) {}
            noisyAudioReceiver = null;
        }
    }

    private void startMediaButtonEvent() {
        if (mediaButtonReceiver == null) {
            mediaButtonReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context ctx, Intent intent) {
                    if (Intent.ACTION_MEDIA_BUTTON.equals(intent.getAction())) {
                        KeyEvent event = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
                        if (event != null && mediaButtonSink != null) {
                            int keyCode = event.getKeyCode();
                            String keyText;
                            switch (keyCode) {
                                case KeyEvent.KEYCODE_MEDIA_PLAY: keyText = "KEYCODE_MEDIA_PLAY"; break;
                                case KeyEvent.KEYCODE_MEDIA_PAUSE: keyText = "KEYCODE_MEDIA_PAUSE"; break;
                                case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE: keyText = "KEYCODE_MEDIA_PLAY_PAUSE"; break;
                                case KeyEvent.KEYCODE_MEDIA_NEXT: keyText = "KEYCODE_MEDIA_NEXT"; break;
                                case KeyEvent.KEYCODE_MEDIA_PREVIOUS: keyText = "KEYCODE_MEDIA_PREVIOUS"; break;
                                case KeyEvent.KEYCODE_MEDIA_CLOSE: keyText = "KEYCODE_MEDIA_CLOSE"; break;
                                case KeyEvent.KEYCODE_MEDIA_EJECT: keyText = "KEYCODE_MEDIA_EJECT"; break;
                                case KeyEvent.KEYCODE_MEDIA_RECORD: keyText = "KEYCODE_MEDIA_RECORD"; break;
                                case KeyEvent.KEYCODE_MEDIA_STOP: keyText = "KEYCODE_MEDIA_STOP"; break;
                                default: keyText = "KEYCODE_UNKNOW"; break;
                            }
                            Map<String, Object> data = new HashMap<>();
                            data.put("eventText", keyText);
                            data.put("eventCode", keyCode);
                            runOnMainThread(() -> mediaButtonSink.success(data));
                        }
                    }
                }
            };
            context.registerReceiver(mediaButtonReceiver, new IntentFilter(Intent.ACTION_MEDIA_BUTTON));
        }
    }

    private void stopMediaButtonEvent() {
        if (mediaButtonReceiver != null) {
            try { context.unregisterReceiver(mediaButtonReceiver); } catch (Exception e) {}
            mediaButtonReceiver = null;
        }
    }

    // ==================== Original Audio Setup ====================

    private void storeOriginalAudioSetup() {
        if (!isOrigAudioSetupStored) {
            origAudioMode = audioManager.getMode();
            origIsSpeakerPhoneOn = audioManager.isSpeakerphoneOn();
            origIsMicrophoneMute = audioManager.isMicrophoneMute();
            isOrigAudioSetupStored = true;
        }
    }

    private void restoreOriginalAudioSetup() {
        if (isOrigAudioSetupStored) {
            setSpeakerphoneOnInternal(origIsSpeakerPhoneOn);
            audioManager.setMicrophoneMute(origIsMicrophoneMute);
            audioManager.setMode(origAudioMode);
            isOrigAudioSetupStored = false;
        }
    }

    // ==================== Audio URI Helpers ====================

    private Uri getRingtoneUri(String type) {
        if (type.isEmpty() || "_DEFAULT_".equals(type)) {
            return defaultRingtoneUri;
        }
        return getAudioUri(type, "incallmanager_ringtone", "mp3",
                "media_volume.ogg", "/system/media/audio/ui",
                "bundleRingtoneUri", "defaultRingtoneUri");
    }

    private Uri getRingbackUri(String type) {
        if (type.isEmpty() || "_DEFAULT_".equals(type)) {
            return defaultRingbackUri;
        }
        return getAudioUri(type, "incallmanager_ringback", "mp3",
                "media_volume.ogg", "/system/media/audio/ui",
                "bundleRingbackUri", "defaultRingbackUri");
    }

    private Uri getBusytoneUri(String type) {
        if (type.isEmpty() || "_DEFAULT_".equals(type)) {
            return defaultBusytoneUri;
        }
        return getAudioUri(type, "incallmanager_busytone", "mp3",
                "LowBattery.ogg", "/system/media/audio/ui",
                "bundleBusytoneUri", "defaultBusytoneUri");
    }

    private Uri getAudioUri(String type, String fileBundle, String fileBundleExt,
                            String fileSysWithExt, String fileSysPath,
                            String uriBundleKey, String uriDefaultKey) {
        if ("_BUNDLE_".equals(type)) {
            if (audioUriMap.get(uriBundleKey) == null) {
                int res = context.getResources().getIdentifier(fileBundle, "raw", packageName);
                if (res <= 0) {
                    audioUriMap.put(uriBundleKey, null);
                    return getDefaultUserUri(uriDefaultKey);
                } else {
                    Uri u = Uri.parse("android.resource://" + packageName + "/" + res);
                    audioUriMap.put(uriBundleKey, u);
                    return u;
                }
            } else {
                return audioUriMap.get(uriBundleKey);
            }
        }

        String target = fileSysPath + "/" + type;
        Uri uri = getSysFileUri(target);
        if (uri == null) {
            return getDefaultUserUri(uriDefaultKey);
        }
        audioUriMap.put(uriDefaultKey, uri);
        return uri;
    }

    private Uri getSysFileUri(String target) {
        File file = new File(target);
        if (file.isFile()) {
            return Uri.fromFile(file);
        }
        return null;
    }

    private Uri getDefaultUserUri(String type) {
        switch (type) {
            case "defaultRingtoneUri": return Settings.System.DEFAULT_RINGTONE_URI;
            case "defaultRingbackUri": return Settings.System.DEFAULT_RINGTONE_URI;
            case "defaultBusytoneUri": return Settings.System.DEFAULT_NOTIFICATION_URI;
            default: return Settings.System.DEFAULT_NOTIFICATION_URI;
        }
    }

    // ==================== Helpers ====================

    private void runOnMainThread(Runnable runnable) {
        new Handler(Looper.getMainLooper()).post(runnable);
    }

    // ==================== EventChannel StreamHandlers ====================

    private class ProximityStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            proximitySink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            proximitySink = null;
        }
    }

    private class WiredHeadsetStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            wiredHeadsetSink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            wiredHeadsetSink = null;
        }
    }

    private class AudioDeviceChangedStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            audioDeviceChangedSink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            audioDeviceChangedSink = null;
        }
    }

    private class AudioFocusChangeStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            audioFocusChangeSink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            audioFocusChangeSink = null;
        }
    }

    private class NoisyAudioStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            noisyAudioSink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            noisyAudioSink = null;
        }
    }

    private class MediaButtonStreamHandler implements EventChannel.StreamHandler {
        @Override
        public void onListen(Object arguments, EventChannel.EventSink events) {
            mediaButtonSink = events;
        }

        @Override
        public void onCancel(Object arguments) {
            mediaButtonSink = null;
        }
    }
}
