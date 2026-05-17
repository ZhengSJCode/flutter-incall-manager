import AVFoundation
import Flutter
import UIKit

public class FlutterInCallManagerPlugin: NSObject, FlutterPlugin, AVAudioPlayerDelegate {

    // MARK: - Properties

    private var methodChannel: FlutterMethodChannel?
    private var proximityEventChannel: FlutterEventChannel?
    private var wiredHeadsetEventChannel: FlutterEventChannel?

    private var proximityStreamHandler: ProximityStreamHandler?
    private var wiredHeadsetStreamHandler: WiredHeadsetStreamHandler?

    private let audioSession = AVAudioSession.sharedInstance()
    private let currentDevice = UIDevice.current

    private var ringtone: AVAudioPlayer?
    private var ringback: AVAudioPlayer?
    private var busytone: AVAudioPlayer?

    private var defaultRingtoneUri: URL?
    private var defaultRingbackUri: URL?
    private var defaultBusytoneUri: URL?
    private var bundleRingtoneUri: URL?
    private var bundleRingbackUri: URL?
    private var bundleBusytoneUri: URL?

    private var proximityIsNear = false

    private var isProximityRegistered = false
    private var isAudioSessionInterruptionRegistered = false
    private var isAudioSessionRouteChangeRegistered = false
    private var isAudioSessionMediaServicesWereLostRegistered = false
    private var isAudioSessionMediaServicesWereResetRegistered = false
    private var isAudioSessionSilenceSecondaryAudioHintRegistered = false

    private var proximityObserver: Any?
    private var audioSessionInterruptionObserver: Any?
    private var audioSessionRouteChangeObserver: Any?
    private var audioSessionMediaServicesWereLostObserver: Any?
    private var audioSessionMediaServicesWereResetObserver: Any?
    private var audioSessionSilenceSecondaryAudioHintObserver: Any?

    private var incallAudioMode: String = AVAudioSession.Mode.voiceChat.rawValue
    private let incallAudioCategory: String = AVAudioSession.Category.playAndRecord.rawValue
    private var origAudioCategory: String?
    private var origAudioMode: String?
    private var audioSessionInitialized = false
    private var forceSpeakerOn = 0
    private var media = "audio"

    // MARK: - FlutterPlugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterInCallManagerPlugin()
        instance.setupChannels(with: registrar)
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)
    }

    private func setupChannels(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        methodChannel = FlutterMethodChannel(
            name: "incall_manager",
            binaryMessenger: messenger
        )

        proximityStreamHandler = ProximityStreamHandler(plugin: self)
        proximityEventChannel = FlutterEventChannel(
            name: "incall_manager_proximity",
            binaryMessenger: messenger
        )
        proximityEventChannel?.setStreamHandler(proximityStreamHandler)

        wiredHeadsetStreamHandler = WiredHeadsetStreamHandler(plugin: self)
        wiredHeadsetEventChannel = FlutterEventChannel(
            name: "incall_manager_wired_headset",
            binaryMessenger: messenger
        )
        wiredHeadsetEventChannel?.setStreamHandler(wiredHeadsetStreamHandler)
    }

    // MARK: - MethodCallHandler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            handleStart(call, result: result)
        case "stop":
            handleStop(call, result: result)
        case "turnScreenOn":
            NSLog("FlutterInCallManager.turnScreenOn(): ios doesn't support turnScreenOn()")
            result(nil)
        case "turnScreenOff":
            NSLog("FlutterInCallManager.turnScreenOff(): ios doesn't support turnScreenOff()")
            result(nil)
        case "setFlashOn":
            handleSetFlashOn(call, result: result)
        case "setKeepScreenOn":
            handleSetKeepScreenOn(call, result: result)
        case "setSpeakerphoneOn":
            handleSetSpeakerphoneOn(call, result: result)
        case "setForceSpeakerphoneOn":
            handleSetForceSpeakerphoneOn(call, result: result)
        case "setMicrophoneMute":
            NSLog("FlutterInCallManager.setMicrophoneMute(): ios doesn't support setMicrophoneMute()")
            result(nil)
        case "startRingtone":
            handleStartRingtone(call, result: result)
        case "stopRingtone":
            handleStopRingtone(result: result)
        case "startProximitySensor":
            handleStartProximitySensor(result: result)
        case "stopProximitySensor":
            handleStopProximitySensor(result: result)
        case "startRingback":
            handleStartRingback(call, result: result)
        case "stopRingback":
            handleStopRingback(result: result)
        case "getAudioUri":
            handleGetAudioUri(call, result: result)
        case "getIsWiredHeadsetPluggedIn":
            handleGetIsWiredHeadsetPluggedIn(result: result)
        case "chooseAudioRoute":
            result(FlutterMethodNotImplemented)
        case "requestAudioFocus":
            result(nil)
        case "abandonAudioFocus":
            result(nil)
        case "pokeScreen":
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Start / Stop

    private func handleStart(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard !audioSessionInitialized else {
            result(nil)
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        media = args["media"] as? String ?? "audio"
        let auto = args["auto"] as? Bool ?? true
        let ringbackUriType = args["ringbackUriType"] as? String ?? ""

        if media == "video" {
            incallAudioMode = AVAudioSession.Mode.videoChat.rawValue
        } else {
            incallAudioMode = AVAudioSession.Mode.voiceChat.rawValue
        }
        NSLog("FlutterInCallManager.start(): media=%@, mode=%@", media, incallAudioMode)

        storeOriginalAudioSetup()
        forceSpeakerOn = 0
        startAudioSessionNotification()

        audioSessionSetCategory(incallAudioCategory, options: [], caller: #function)
        audioSessionSetMode(incallAudioMode, caller: #function)
        audioSessionSetActive(true, options: [], caller: #function)

        if !ringbackUriType.isEmpty {
            startRingbackInternal(ringbackUriType)
        }

        if media == "audio" {
            handleStartProximitySensor(result: { _ in })
        }
        handleSetKeepScreenOn(call, result: { _ in })
        audioSessionInitialized = true
        result(nil)
    }

    private func handleStop(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard audioSessionInitialized else {
            result(nil)
            return
        }
        let args = call.arguments as? [String: Any] ?? [:]
        let busytoneUriType = args["busytoneUriType"] as? String ?? ""

        stopRingbackInternal()

        if !busytoneUriType.isEmpty && startBusytone(busytoneUriType) {
            NSLog("FlutterInCallManager.stop(): play busytone before stop")
            result(nil)
            return
        }

        stopInCallManager()
        result(nil)
    }

    private func stopInCallManager() {
        NSLog("FlutterInCallManager.stop(): stop InCallManager")
        restoreOriginalAudioSetup()
        stopBusytone()
        handleStopProximitySensor(result: { _ in })
        audioSessionSetActive(false, options: .notifyOthersOnDeactivation, caller: #function)
        setKeepScreenOnInternal(false)
        stopAudioSessionNotification()
        NotificationCenter.default.removeObserver(self)
        forceSpeakerOn = 0
        audioSessionInitialized = false
    }

    // MARK: - Flash / Keep Screen On

    private func handleSetFlashOn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let enable = args["enable"] as? Bool ?? false
        let brightness = args["brightness"] as? Double ?? 0

        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch,
              device.position == .back else {
            result(nil)
            return
        }
        do {
            try device.lockForConfiguration()
            if enable {
                if brightness > 0, device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: Float(brightness))
                } else {
                    device.torchMode = .on
                }
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            // ignore
        }
        result(nil)
    }

    private func handleSetKeepScreenOn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let enable = args["enable"] as? Bool ?? false
        setKeepScreenOnInternal(enable)
        result(nil)
    }

    private func setKeepScreenOnInternal(_ enable: Bool) {
        NSLog("FlutterInCallManager.setKeepScreenOn(): enable: %@", enable ? "YES" : "NO")
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = enable
        }
    }

    // MARK: - Speakerphone / Force Speaker / Mute

    private func handleSetSpeakerphoneOn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let enable = args["enable"] as? Bool ?? false

        if !enable {
            NSLog("Routing audio via Earpiece")
            do {
                try audioSession.setCategory(.playAndRecord)
                try audioSession.setMode(.voiceChat)
                try audioSession.setPreferredOutputNumberOfChannels(0)
                try audioSession.overrideOutputAudioPort(.none)
                try audioSession.setActive(true)
            } catch {
                NSLog("Error routing audio via Earpiece: %@", error.localizedDescription)
            }
        } else {
            NSLog("Routing audio via Loudspeaker")
            do {
                try audioSession.setCategory(.playAndRecord, options: .defaultToSpeaker)
                try audioSession.setMode(.voiceChat)
                try audioSession.setPreferredOutputNumberOfChannels(0)
                try audioSession.overrideOutputAudioPort(.speaker)
                try audioSession.setActive(true)
            } catch {
                NSLog("Error routing audio via Loudspeaker: %@", error.localizedDescription)
            }
        }
        result(nil)
    }

    private func handleSetForceSpeakerphoneOn(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let flag = args["flag"] as? Int ?? 0
        forceSpeakerOn = flag
        NSLog("FlutterInCallManager.setForceSpeakerphoneOn(): flag: %d", flag)
        updateAudioRoute()
        result(nil)
    }

    // MARK: - Ringtone

    private func handleStartRingtone(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let ringtoneUriType = args["ringtoneUriType"] as? String ?? "_DEFAULT_"
        let ringtoneCategory = args["iosCategory"] as? String ?? "default"

        NSLog("FlutterInCallManager.startRingtone(): type: %@", ringtoneUriType)

        if let player = ringtone, player.isPlaying {
            NSLog("FlutterInCallManager.startRingtone(): is already playing.")
            result(nil)
            return
        }
        stopRingtoneInternal()

        guard let ringtoneUri = getRingtoneUri(ringtoneUriType) else {
            NSLog("FlutterInCallManager.startRingtone(): no available media")
            result(nil)
            return
        }

        storeOriginalAudioSetup()
        do {
            ringtone = try AVAudioPlayer(contentsOf: ringtoneUri)
            ringtone?.delegate = self
            ringtone?.numberOfLoops = -1
            ringtone?.prepareToPlay()

            if ringtoneCategory == "playback" {
                audioSessionSetCategory(AVAudioSession.Category.playback.rawValue, options: [], caller: #function)
            } else {
                audioSessionSetCategory(AVAudioSession.Category.soloAmbient.rawValue, options: [], caller: #function)
            }
            audioSessionSetMode(AVAudioSession.Mode.default.rawValue, caller: #function)
            ringtone?.play()
        } catch {
            NSLog("FlutterInCallManager.startRingtone(): caught error = %@", error.localizedDescription)
        }
        result(nil)
    }

    private func handleStopRingtone(result: @escaping FlutterResult) {
        stopRingtoneInternal()
        result(nil)
    }

    private func stopRingtoneInternal() {
        guard let player = ringtone else { return }
        NSLog("FlutterInCallManager.stopRingtone()")
        player.stop()
        ringtone = nil
        restoreOriginalAudioSetup()
        audioSessionSetActive(false, options: .notifyOthersOnDeactivation, caller: #function)
    }

    // MARK: - Ringback

    private func handleStartRingback(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let ringbackUriType = args["ringbackUriType"] as? String ?? ""
        startRingbackInternal(ringbackUriType)
        result(nil)
    }

    private func startRingbackInternal(_ ringbackUriType: String) {
        NSLog("FlutterInCallManager.startRingback(): type=%@", ringbackUriType)

        if let player = ringback, player.isPlaying {
            NSLog("FlutterInCallManager.startRingback(): is already playing")
            return
        }
        stopRingbackInternal()

        let resolvedType = ringbackUriType == "_DTMF_" ? "_DEFAULT_" : ringbackUriType
        guard let ringbackUri = getRingbackUri(resolvedType) else {
            NSLog("FlutterInCallManager.startRingback(): no available media")
            return
        }

        do {
            ringback = try AVAudioPlayer(contentsOf: ringbackUri)
            ringback?.delegate = self
            ringback?.numberOfLoops = -1
            ringback?.prepareToPlay()

            audioSessionSetCategory(incallAudioCategory, options: [], caller: #function)
            audioSessionSetMode(incallAudioMode, caller: #function)
            ringback?.play()
        } catch {
            NSLog("FlutterInCallManager.startRingback(): caught error=%@", error.localizedDescription)
        }
    }

    private func handleStopRingback(result: @escaping FlutterResult) {
        stopRingbackInternal()
        result(nil)
    }

    private func stopRingbackInternal() {
        guard let player = ringback else { return }
        NSLog("FlutterInCallManager.stopRingback()")
        player.stop()
        ringback = nil
    }

    // MARK: - Busytone

    private func startBusytone(_ busytoneUriType: String) -> Bool {
        NSLog("FlutterInCallManager.startBusytone(): type: %@", busytoneUriType)

        if let player = busytone, player.isPlaying {
            NSLog("FlutterInCallManager.startBusytone(): is already playing")
            return false
        }
        stopBusytone()

        let resolvedType = busytoneUriType == "_DTMF_" ? "_DEFAULT_" : busytoneUriType
        guard let busytoneUri = getBusytoneUri(resolvedType) else {
            NSLog("FlutterInCallManager.startBusytone(): no available media")
            return false
        }

        do {
            busytone = try AVAudioPlayer(contentsOf: busytoneUri)
            busytone?.delegate = self
            busytone?.numberOfLoops = 0
            busytone?.prepareToPlay()

            audioSessionSetCategory(incallAudioCategory, options: [], caller: #function)
            audioSessionSetMode(incallAudioMode, caller: #function)
            busytone?.play()
        } catch {
            NSLog("FlutterInCallManager.startBusytone(): caught error = %@", error.localizedDescription)
            return false
        }
        return true
    }

    private func stopBusytone() {
        guard let player = busytone else { return }
        NSLog("FlutterInCallManager.stopBusytone()")
        player.stop()
        busytone = nil
    }

    // MARK: - Proximity Sensor

    private func handleStartProximitySensor(result: @escaping FlutterResult) {
        guard !isProximityRegistered else {
            result(nil)
            return
        }
        NSLog("FlutterInCallManager.startProximitySensor()")
        DispatchQueue.main.async {
            self.currentDevice.isProximityMonitoringEnabled = true
        }

        // Remove any existing observer
        if let observer = proximityObserver {
            NotificationCenter.default.removeObserver(observer,
                                                       name: UIDevice.proximityStateDidChangeNotification,
                                                       object: nil)
        }

        proximityObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.proximityStateDidChangeNotification,
            object: currentDevice,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            let state = self.currentDevice.proximityState
            if state != self.proximityIsNear {
                NSLog("FlutterInCallManager.UIDeviceProximityStateDidChangeNotification(): isNear: %@", state ? "YES" : "NO")
                self.proximityIsNear = state
                self.proximityStreamHandler?.sendEvent(["isNear": state])
            }
        }

        isProximityRegistered = true
        result(nil)
    }

    private func handleStopProximitySensor(result: @escaping FlutterResult) {
        guard isProximityRegistered else {
            result(nil)
            return
        }
        NSLog("FlutterInCallManager.stopProximitySensor()")
        DispatchQueue.main.async {
            self.currentDevice.isProximityMonitoringEnabled = false
        }

        if let observer = proximityObserver {
            NotificationCenter.default.removeObserver(observer,
                                                       name: UIDevice.proximityStateDidChangeNotification,
                                                       object: nil)
        }
        proximityObserver = nil
        isProximityRegistered = false
        result(nil)
    }

    // MARK: - Audio URI

    private func handleGetAudioUri(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        let audioType = args["audioType"] as? String ?? ""
        let fileType = args["fileType"] as? String ?? ""

        var uri: URL?
        switch audioType {
        case "ringback":
            uri = getRingbackUri(fileType)
        case "busytone":
            uri = getBusytoneUri(fileType)
        case "ringtone":
            uri = getRingtoneUri(fileType)
        default:
            break
        }

        if let uri = uri, !uri.absoluteString.isEmpty {
            result(uri.absoluteString)
        } else {
            result(FlutterError(code: "error_code", message: "getAudioUri() failed", details: nil))
        }
    }

    private func handleGetIsWiredHeadsetPluggedIn(result: @escaping FlutterResult) {
        result(isWiredHeadsetPluggedIn())
    }

    // MARK: - Audio Route

    private func isWiredHeadsetPluggedIn() -> Bool {
        return checkAudioRoute(targetPortTypes: [AVAudioSession.Port.headphones], routeType: "output")
            || checkAudioRoute(targetPortTypes: [AVAudioSession.Port.headsetMic], routeType: "input")
    }

    private func checkAudioRoute(targetPortTypes: [AVAudioSession.Port], routeType: String) -> Bool {
        let currentRoute = audioSession.currentRoute
        let routes = routeType == "input" ? currentRoute.inputs : currentRoute.outputs
        for port in routes {
            if targetPortTypes.contains(port.portType) {
                return true
            }
        }
        return false
    }

    private func updateAudioRoute() {
        NSLog("FlutterInCallManager.updateAudioRoute(): [Enter] forceSpeakerOn flag=%d media=%@", forceSpeakerOn, media)

        let overridePort: AVAudioSession.PortOverride
        let overridePortString: String
        var audioMode: String?

        if forceSpeakerOn == 1 {
            overridePort = .speaker
            overridePortString = ".Speaker"
            if media == "video" {
                audioMode = AVAudioSession.Mode.videoChat.rawValue
                handleStopProximitySensor(result: { _ in })
            }
        } else if forceSpeakerOn == -1 {
            overridePort = .none
            overridePortString = ".None"
            if media == "video" {
                audioMode = AVAudioSession.Mode.voiceChat.rawValue
                handleStartProximitySensor(result: { _ in })
            }
        } else {
            overridePort = .none
            overridePortString = ".None"
            if media == "video" {
                audioMode = AVAudioSession.Mode.videoChat.rawValue
                handleStopProximitySensor(result: { _ in })
            }
        }

        let isCurrentRouteToSpeaker = checkAudioRoute(
            targetPortTypes: [AVAudioSession.Port.builtInSpeaker],
            routeType: "output"
        )

        if (overridePort == .speaker && !isCurrentRouteToSpeaker)
            || (overridePort == .none && isCurrentRouteToSpeaker) {
            do {
                try audioSession.overrideOutputAudioPort(overridePort)
                NSLog("FlutterInCallManager.updateAudioRoute(): overrideOutputAudioPort(%@) success", overridePortString)
            } catch {
                NSLog("FlutterInCallManager.updateAudioRoute(): overrideOutputAudioPort(%@) fail: %@", overridePortString, error.localizedDescription)
            }
        }

        if audioSession.category.rawValue != incallAudioCategory {
            audioSessionSetCategory(incallAudioCategory, options: [], caller: #function)
            NSLog("FlutterInCallManager.updateAudioRoute() audio category has changed to %@", incallAudioCategory)
        }

        if let mode = audioMode, audioSession.mode.rawValue != mode {
            audioSessionSetMode(mode, caller: #function)
            NSLog("FlutterInCallManager.updateAudioRoute() audio mode has changed to %@", mode)
        }
    }

    // MARK: - Audio Session Helpers

    private func audioSessionSetCategory(_ category: String, options: AVAudioSession.CategoryOptions, caller: String) {
        guard let avCategory = AVAudioSession.Category(rawValue: category) else { return }
        do {
            if options.isEmpty {
                try audioSession.setCategory(avCategory)
            } else {
                try audioSession.setCategory(avCategory, options: options)
            }
            NSLog("FlutterInCallManager.%@: audioSession.setCategory: %@ success", caller, category)
        } catch {
            NSLog("FlutterInCallManager.%@: audioSession.setCategory: %@ fail: %@", caller, category, error.localizedDescription)
        }
    }

    private func audioSessionSetMode(_ mode: String, caller: String) {
        guard let avMode = AVAudioSession.Mode(rawValue: mode) else { return }
        do {
            try audioSession.setMode(avMode)
            NSLog("FlutterInCallManager.%@: audioSession.setMode(%@) success", caller, mode)
        } catch {
            NSLog("FlutterInCallManager.%@: audioSession.setMode(%@) fail: %@", caller, mode, error.localizedDescription)
        }
    }

    private func audioSessionSetActive(_ active: Bool, options: AVAudioSession.SetActiveOptions, caller: String) {
        do {
            if options.isEmpty {
                try audioSession.setActive(active)
            } else {
                try audioSession.setActive(active, options: options)
            }
            NSLog("FlutterInCallManager.%@: audioSession.setActive(%@) success", caller, active ? "YES" : "NO")
        } catch {
            NSLog("FlutterInCallManager.%@: audioSession.setActive(%@) fail: %@", caller, active ? "YES" : "NO", error.localizedDescription)
        }
    }

    private func storeOriginalAudioSetup() {
        origAudioCategory = audioSession.category.rawValue
        origAudioMode = audioSession.mode.rawValue
        NSLog("FlutterInCallManager.storeOriginalAudioSetup(): origAudioCategory=%@, origAudioMode=%@", origAudioCategory ?? "nil", origAudioMode ?? "nil")
    }

    private func restoreOriginalAudioSetup() {
        if let category = origAudioCategory {
            audioSessionSetCategory(category, options: [], caller: #function)
            NSLog("FlutterInCallManager.restoreOriginalAudioSetup() restored category=%@", category)
        }
        if let mode = origAudioMode {
            audioSessionSetMode(mode, caller: #function)
            NSLog("FlutterInCallManager.restoreOriginalAudioSetup() restored mode=%@", mode)
        }
    }

    // MARK: - Audio Notification Management

    private func startAudioSessionNotification() {
        NSLog("FlutterInCallManager.startAudioSessionNotification() starting...")
        startAudioSessionInterruptionNotification()
        startAudioSessionRouteChangeNotification()
        startAudioSessionMediaServicesWereLostNotification()
        startAudioSessionMediaServicesWereResetNotification()
        startAudioSessionSilenceSecondaryAudioHintNotification()
    }

    private func stopAudioSessionNotification() {
        NSLog("FlutterInCallManager.startAudioSessionNotification() stopping...")
        stopAudioSessionInterruptionNotification()
        stopAudioSessionRouteChangeNotification()
        stopAudioSessionMediaServicesWereLostNotification()
        stopAudioSessionMediaServicesWereResetNotification()
        stopAudioSessionSilenceSecondaryAudioHintNotification()
    }

    private func startAudioSessionInterruptionNotification() {
        guard !isAudioSessionInterruptionRegistered else { return }
        if let obs = audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.interruptionNotification, object: nil)
        }

        audioSessionInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }
            switch type {
            case .began:
                NSLog("FlutterInCallManager.AudioSessionInterruptionNotification: Began")
            case .ended:
                NSLog("FlutterInCallManager.AudioSessionInterruptionNotification: Ended")
            @unknown default:
                NSLog("FlutterInCallManager.AudioSessionInterruptionNotification: Unknow Value")
            }
        }
        isAudioSessionInterruptionRegistered = true
    }

    private func stopAudioSessionInterruptionNotification() {
        guard isAudioSessionInterruptionRegistered else { return }
        if let obs = audioSessionInterruptionObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.interruptionNotification, object: nil)
        }
        audioSessionInterruptionObserver = nil
        isAudioSessionInterruptionRegistered = false
    }

    private func startAudioSessionRouteChangeNotification() {
        guard !isAudioSessionRouteChangeRegistered else { return }
        if let obs = audioSessionRouteChangeObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.routeChangeNotification, object: nil)
        }

        audioSessionRouteChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
                return
            }

            switch reason {
            case .unknown:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: Unknown")
            case .newDeviceAvailable:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: NewDeviceAvailable")
                if self.checkAudioRoute(targetPortTypes: [AVAudioSession.Port.headsetMic], routeType: "input") {
                    self.wiredHeadsetStreamHandler?.sendEvent([
                        "isPlugged": true,
                        "hasMic": true,
                        "deviceName": AVAudioSession.Port.headsetMic.rawValue,
                    ])
                } else if self.checkAudioRoute(targetPortTypes: [AVAudioSession.Port.headphones], routeType: "output") {
                    self.wiredHeadsetStreamHandler?.sendEvent([
                        "isPlugged": true,
                        "hasMic": false,
                        "deviceName": AVAudioSession.Port.headphones.rawValue,
                    ])
                }
            case .oldDeviceUnavailable:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: OldDeviceUnavailable")
                if !self.isWiredHeadsetPluggedIn() {
                    self.wiredHeadsetStreamHandler?.sendEvent([
                        "isPlugged": false,
                        "hasMic": false,
                        "deviceName": "",
                    ])
                }
            case .categoryChange:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: CategoryChange")
                self.updateAudioRoute()
            case .override:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: Override")
            case .wakeFromSleep:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: WakeFromSleep")
            case .noSuitableRouteForCategory:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: NoSuitableRouteForCategory")
            case .routeConfigurationChange:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: RouteConfigurationChange")
            @unknown default:
                NSLog("FlutterInCallManager.AudioRouteChange.Reason: Unknow Value")
            }
        }
        isAudioSessionRouteChangeRegistered = true
    }

    private func stopAudioSessionRouteChangeNotification() {
        guard isAudioSessionRouteChangeRegistered else { return }
        if let obs = audioSessionRouteChangeObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.routeChangeNotification, object: nil)
        }
        audioSessionRouteChangeObserver = nil
        isAudioSessionRouteChangeRegistered = false
    }

    private func startAudioSessionMediaServicesWereLostNotification() {
        guard !isAudioSessionMediaServicesWereLostRegistered else { return }
        if let obs = audioSessionMediaServicesWereLostObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        }

        audioSessionMediaServicesWereLostObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification,
            object: nil,
            queue: nil
        ) { _ in
            NSLog("FlutterInCallManager.AudioSessionMediaServicesWereLostNotification: Media Services Were Lost")
        }
        isAudioSessionMediaServicesWereLostRegistered = true
    }

    private func stopAudioSessionMediaServicesWereLostNotification() {
        guard isAudioSessionMediaServicesWereLostRegistered else { return }
        if let obs = audioSessionMediaServicesWereLostObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.mediaServicesWereLostNotification, object: nil)
        }
        audioSessionMediaServicesWereLostObserver = nil
        isAudioSessionMediaServicesWereLostRegistered = false
    }

    private func startAudioSessionMediaServicesWereResetNotification() {
        guard !isAudioSessionMediaServicesWereResetRegistered else { return }
        if let obs = audioSessionMediaServicesWereResetObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }

        audioSessionMediaServicesWereResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: nil
        ) { _ in
            NSLog("FlutterInCallManager.AudioSessionMediaServicesWereResetNotification: Media Services Were Reset")
        }
        isAudioSessionMediaServicesWereResetRegistered = true
    }

    private func stopAudioSessionMediaServicesWereResetNotification() {
        guard isAudioSessionMediaServicesWereResetRegistered else { return }
        if let obs = audioSessionMediaServicesWereResetObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        }
        audioSessionMediaServicesWereResetObserver = nil
        isAudioSessionMediaServicesWereResetRegistered = false
    }

    private func startAudioSessionSilenceSecondaryAudioHintNotification() {
        guard !isAudioSessionSilenceSecondaryAudioHintRegistered else { return }
        if let obs = audioSessionSilenceSecondaryAudioHintObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
        }

        audioSessionSilenceSecondaryAudioHintObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt else {
                return
            }
            switch typeValue {
            case AVAudioSession.SilenceSecondaryAudioHintType.begin.rawValue:
                NSLog("FlutterInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: Begin")
            case AVAudioSession.SilenceSecondaryAudioHintType.end.rawValue:
                NSLog("FlutterInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: End")
            default:
                NSLog("FlutterInCallManager.AVAudioSessionSilenceSecondaryAudioHintNotification: Unknow Value")
            }
        }
        isAudioSessionSilenceSecondaryAudioHintRegistered = true
    }

    private func stopAudioSessionSilenceSecondaryAudioHintNotification() {
        guard isAudioSessionSilenceSecondaryAudioHintRegistered else { return }
        if let obs = audioSessionSilenceSecondaryAudioHintObserver {
            NotificationCenter.default.removeObserver(obs, name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
        }
        audioSessionSilenceSecondaryAudioHintObserver = nil
        isAudioSessionSilenceSecondaryAudioHintRegistered = false
    }

    // MARK: - Audio URI Helpers

    private func getRingtoneUri(_ type: String) -> URL? {
        let fileBundle = "incallmanager_ringtone"
        let fileBundleExt = "mp3"
        let fileSysWithExt = "Opening.m4r"
        let fileSysPath = "/Library/Ringtones"

        let resolvedType = (type.isEmpty || type == "_DEFAULT_") ? fileSysWithExt : type
        return getAudioUri(type: resolvedType,
                           fileBundle: fileBundle,
                           fileBundleExt: fileBundleExt,
                           fileSysWithExt: fileSysWithExt,
                           fileSysPath: fileSysPath,
                           bundleUri: &bundleRingtoneUri,
                           defaultUri: &defaultRingtoneUri)
    }

    private func getRingbackUri(_ type: String) -> URL? {
        let fileBundle = "incallmanager_ringback"
        let fileBundleExt = "mp3"
        let fileSysWithExt = "Marimba.m4r"
        let fileSysPath = "/Library/Ringtones"

        let resolvedType = (type.isEmpty || type == "_DEFAULT_") ? fileSysWithExt : type
        return getAudioUri(type: resolvedType,
                           fileBundle: fileBundle,
                           fileBundleExt: fileBundleExt,
                           fileSysWithExt: fileSysWithExt,
                           fileSysPath: fileSysPath,
                           bundleUri: &bundleRingbackUri,
                           defaultUri: &defaultRingbackUri)
    }

    private func getBusytoneUri(_ type: String) -> URL? {
        let fileBundle = "incallmanager_busytone"
        let fileBundleExt = "mp3"
        let fileSysWithExt = "ct-busy.caf"
        let fileSysPath = "/System/Library/Audio/UISounds"

        let resolvedType = (type.isEmpty || type == "_DEFAULT_") ? fileSysWithExt : type
        return getAudioUri(type: resolvedType,
                           fileBundle: fileBundle,
                           fileBundleExt: fileBundleExt,
                           fileSysWithExt: fileSysWithExt,
                           fileSysPath: fileSysPath,
                           bundleUri: &bundleBusytoneUri,
                           defaultUri: &defaultBusytoneUri)
    }

    private func getAudioUri(type: String,
                             fileBundle: String,
                             fileBundleExt: String,
                             fileSysWithExt: String,
                             fileSysPath: String,
                             bundleUri: inout URL?,
                             defaultUri: inout URL?) -> URL? {
        if type == "_BUNDLE_" {
            if bundleUri == nil {
                bundleUri = Bundle.main.url(forResource: fileBundle, withExtension: fileBundleExt)
                if bundleUri == nil {
                    NSLog("FlutterInCallManager.getAudioUri(): %@.%@ not found in bundle.", fileBundle, fileBundleExt)
                    // Fall through to system file
                } else {
                    return bundleUri
                }
            } else {
                return bundleUri
            }
        }

        if defaultUri == nil {
            let target = "\(fileSysPath)/\(type)"
            defaultUri = getSysFileUri(target)
        }
        return defaultUri
    }

    private func getSysFileUri(_ target: String) -> URL? {
        let url = URL(fileURLWithPath: target, isDirectory: false)
        let path = url.path
        if FileManager.default.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
                return url
            }
        }
        NSLog("FlutterInCallManager.getSysFileUri(): can not get url for %@", target)
        return nil
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let filename = player.url?.deletingPathExtension().lastPathComponent ?? ""
        NSLog("FlutterInCallManager.audioPlayerDidFinishPlaying(): finished playing: %@", filename)

        if let busytoneUri = defaultBusytoneUri,
           filename == busytoneUri.deletingPathExtension().lastPathComponent {
            NSLog("FlutterInCallManager.audioPlayerDidFinishPlaying(): busytone finished, invoke stop()")
            stopInCallManager()
        } else if let bundleBusytone = bundleBusytoneUri,
                  filename == bundleBusytone.deletingPathExtension().lastPathComponent {
            NSLog("FlutterInCallManager.audioPlayerDidFinishPlaying(): busytone finished, invoke stop()")
            stopInCallManager()
        }
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let filename = player.url?.deletingPathExtension().lastPathComponent ?? ""
        NSLog("FlutterInCallManager.audioPlayerDecodeErrorDidOccur(): player=%@, error=%@", filename, error?.localizedDescription ?? "unknown")
    }

    // MARK: - Deinit

    deinit {
        stopRingtoneInternal()
        stopRingbackInternal()
        stopBusytone()
        stopAudioSessionNotification()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - ProximityStreamHandler

class ProximityStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: FlutterInCallManagerPlugin?
    private var eventSink: FlutterEventSink?

    init(plugin: FlutterInCallManagerPlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(data)
        }
    }
}

// MARK: - WiredHeadsetStreamHandler

class WiredHeadsetStreamHandler: NSObject, FlutterStreamHandler {
    private weak var plugin: FlutterInCallManagerPlugin?
    private var eventSink: FlutterEventSink?

    init(plugin: FlutterInCallManagerPlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    func sendEvent(_ data: [String: Any]) {
        DispatchQueue.main.async {
            self.eventSink?(data)
        }
    }
}
