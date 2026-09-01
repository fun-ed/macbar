import Foundation
import CoreAudio
import Combine

enum VolumeKind: Hashable {
    case output
    case input

    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }

    var defaultsSuffix: String {
        self == .output ? "output" : "input"
    }
}

final class AudioController: ObservableObject {
    @Published private(set) var outputVolume: Float = 0
    @Published private(set) var outputMuted = false
    @Published private(set) var inputVolume: Float = 0
    @Published private(set) var inputMuted = false
    @Published private(set) var outputAvailable = false
    @Published private(set) var inputAvailable = false
    @Published private(set) var outputHasVolumeControl = false
    @Published private(set) var inputHasVolumeControl = false
    @Published private(set) var meteringActive = false
    @Published private(set) var micPermissionDenied = false
    @Published private(set) var micMeteringFailed = false
    @Published private(set) var outputMeteringFailed = false
    @Published private(set) var outputLevel: Double = 0
    @Published private(set) var inputLevel: Double = 0

    private var outputDevice: AudioObjectID = 0
    private var inputDevice: AudioObjectID = 0
    private var hardwareMute = [VolumeKind: Bool]()
    private var softwareMuted = [VolumeKind: Bool]()
    private var listeners: [(device: AudioObjectID, address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []
    private let micMonitor = MicLevelMonitor()
    private let outputMonitor = OutputLevelMonitor()

    private let audioQueue = DispatchQueue(label: "no.runbox.funed.macbar.audio")
    private let defaults = UserDefaults.standard

    init() {
        softwareMuted[.output] = defaults.bool(forKey: "softwareMuted.output")
        softwareMuted[.input] = defaults.bool(forKey: "softwareMuted.input")
        installDefaultDeviceListeners()
        refresh()
        micMonitor.onLevel = { [weak self] value in self?.inputLevel = value }
        micMonitor.onPermissionDenied = { [weak self] in self?.micPermissionDenied = true }
        micMonitor.onFailed = { [weak self] in self?.micMeteringFailed = true }
        outputMonitor.onLevel = { [weak self] value in self?.outputLevel = value }
        outputMonitor.onFailed = { [weak self] in self?.outputMeteringFailed = true }
    }

    deinit {
        removeAllListeners()
    }

    // MARK: - Public API

    func volume(for kind: VolumeKind) -> Float {
        kind == .output ? outputVolume : inputVolume
    }

    func isMuted(_ kind: VolumeKind) -> Bool {
        kind == .output ? outputMuted : inputMuted
    }

    func hasVolumeControl(_ kind: VolumeKind) -> Bool {
        kind == .output ? outputHasVolumeControl : inputHasVolumeControl
    }

    func isAvailable(_ kind: VolumeKind) -> Bool {
        kind == .output ? outputAvailable : inputAvailable
    }

    func setVolume(_ kind: VolumeKind, _ value: Float) {
        let device = kind == .output ? outputDevice : inputDevice
        guard device != 0, hasVolumeControl(kind) else { return }
        let v = min(max(value, 0), 1)
        if v > 0.005 { storePreMuteVolume(kind, v) }
        setSoftwareMuted(kind, false)
        if hardwareMute[kind] == true {
            writeMute(device, kind.scope, false)
        }
        publish(kind, volume: v, muted: false)
        writeVolume(device, kind.scope, v)
    }

    func toggleMute(_ kind: VolumeKind) {
        let device = kind == .output ? outputDevice : inputDevice
        guard device != 0 else { return }
        if hardwareMute[kind] == true {
            writeMute(device, kind.scope, !isMuted(kind))
            readAndPublish()
        } else if isMuted(kind) {
            let restore = preMuteVolume(kind)
            setSoftwareMuted(kind, false)
            publish(kind, volume: restore, muted: false)
            writeVolume(device, kind.scope, restore)
        } else {
            storePreMuteVolume(kind, volume(for: kind))
            setSoftwareMuted(kind, true)
            publish(kind, volume: 0, muted: true)
            writeVolume(device, kind.scope, 0)
        }
    }

    func nudgeOutputVolume(_ delta: Float) {
        setVolume(.output, outputVolume + delta)
    }

    // MARK: - Sound level metering

    func setMeteringActive(_ active: Bool) {
        guard meteringActive != active else { return }
        meteringActive = active
        outputLevel = 0
        inputLevel = 0
        if active {
            micPermissionDenied = false
            micMeteringFailed = false
            outputMeteringFailed = false
            micMonitor.requestAndStart()
            outputMonitor.start()
        } else {
            micMonitor.stop()
            outputMonitor.stop()
        }
    }

    func level(for kind: VolumeKind) -> Double {
        kind == .output ? outputLevel : inputLevel
    }

    func isMetering(_ kind: VolumeKind) -> Bool {
        guard meteringActive else { return false }
        switch kind {
        case .output:
            return !outputMeteringFailed
        case .input:
            return !micPermissionDenied && !micMeteringFailed
        }
    }

    // MARK: - Device tracking

    func refresh() {
        let newOut = defaultDeviceID(kAudioHardwarePropertyDefaultOutputDevice)
        let newIn = defaultDeviceID(kAudioHardwarePropertyDefaultInputDevice)
        let outChanged = newOut != outputDevice
        let inChanged = newIn != inputDevice
        if outChanged {
            removeAllDeviceListeners(outputDevice)
            outputDevice = newOut
        }
        if inChanged {
            removeAllDeviceListeners(inputDevice)
            inputDevice = newIn
        }
        if outChanged { addDeviceListeners(outputDevice) }
        if inChanged { addDeviceListeners(inputDevice) }
        readAndPublish()
    }

    private func installDefaultDeviceListeners() {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, audioQueue, block) == noErr {
                listeners.append((AudioObjectID(kAudioObjectSystemObject), addr, block))
            }
        }
    }

    private func addDeviceListeners(_ device: AudioObjectID) {
        guard device != 0 else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeWildcard,
                mElement: kAudioObjectPropertyElementWildcard)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                DispatchQueue.main.async { self?.readAndPublish() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &addr, audioQueue, block) == noErr {
                listeners.append((device, addr, block))
            }
        }
    }

    private func removeAllDeviceListeners(_ device: AudioObjectID) {
        for entry in listeners where entry.device == device {
            var addr = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.device, &addr, audioQueue, entry.block)
        }
        listeners.removeAll { $0.device == device }
    }

    private func removeAllListeners() {
        for entry in listeners {
            var addr = entry.address
            AudioObjectRemovePropertyListenerBlock(entry.device, &addr, audioQueue, entry.block)
        }
        listeners.removeAll()
    }

    // MARK: - State read

    private func readAndPublish() {
        readDevice(.output)
        readDevice(.input)
    }

    private func readDevice(_ kind: VolumeKind) {
        let device = kind == .output ? outputDevice : inputDevice
        if device == 0 {
            publish(kind, available: false, hasVolume: false, volume: 0, muted: false)
            return
        }
        if let v = readVolume(device, kind.scope) {
            publish(kind, available: true, hasVolume: true, volume: v, muted: nil)
        } else {
            publish(kind, available: true, hasVolume: false, volume: 0, muted: nil)
        }
        if let hwMute = readMute(device, kind.scope) {
            hardwareMute[kind] = true
            setSoftwareMuted(kind, false)
            publish(kind, available: true, hasVolume: hasVolumeControl(kind), volume: volume(for: kind), muted: hwMute)
        } else {
            hardwareMute[kind] = false
            publish(kind, available: true, hasVolume: hasVolumeControl(kind), volume: volume(for: kind), muted: softwareMuted[kind] ?? false)
        }
    }

    private func publish(
        _ kind: VolumeKind,
        available: Bool? = nil,
        hasVolume: Bool? = nil,
        volume: Float? = nil,
        muted: Bool? = nil
    ) {
        switch kind {
        case .output:
            if let a = available { outputAvailable = a }
            if let hv = hasVolume { outputHasVolumeControl = hv }
            if let v = volume, abs(v - outputVolume) > 0.0001 { outputVolume = v }
            if let m = muted { outputMuted = m }
        case .input:
            if let a = available { inputAvailable = a }
            if let hv = hasVolume { inputHasVolumeControl = hv }
            if let v = volume, abs(v - inputVolume) > 0.0001 { inputVolume = v }
            if let m = muted { inputMuted = m }
        }
    }

    private func publish(_ kind: VolumeKind, volume: Float, muted: Bool) {
        publish(kind, available: true, hasVolume: true, volume: volume, muted: muted)
    }

    // MARK: - CoreAudio helpers

    private func defaultDeviceID(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
        var deviceID = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : 0
    }

    private func hasProperty(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement) -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        return AudioObjectHasProperty(device, &addr)
    }

    private func readFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement) -> Float? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private func writeFloat(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement, _ value: Float32) {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        var v = value
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v)
    }

    private func readVolume(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Float? {
        if hasProperty(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain),
           let v = readFloat(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) {
            return v
        }
        var sum = Float(0)
        var count = 0
        for element in UInt32(1)...UInt32(32) where hasProperty(device, kAudioDevicePropertyVolumeScalar, scope, element) {
            if let v = readFloat(device, kAudioDevicePropertyVolumeScalar, scope, element) {
                sum += v
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return sum / Float(count)
    }

    private func writeVolume(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ value: Float) {
        if hasProperty(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain) {
            writeFloat(device, kAudioDevicePropertyVolumeScalar, scope, kAudioObjectPropertyElementMain, value)
            return
        }
        for element in UInt32(1)...UInt32(32) where hasProperty(device, kAudioDevicePropertyVolumeScalar, scope, element) {
            writeFloat(device, kAudioDevicePropertyVolumeScalar, scope, element, value)
        }
    }

    private func readMute(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool? {
        guard hasProperty(device, kAudioDevicePropertyMute, scope, kAudioObjectPropertyElementMain) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
        return status == noErr ? value != 0 : nil
    }

    private func writeMute(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ muted: Bool) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(muted ? 1 : 0)
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
    }

    // MARK: - Software mute fallback

    private func setSoftwareMuted(_ kind: VolumeKind, _ value: Bool) {
        softwareMuted[kind] = value
        defaults.set(value, forKey: "softwareMuted.\(kind.defaultsSuffix)")
    }

    private func storePreMuteVolume(_ kind: VolumeKind, _ value: Float) {
        guard value > 0.005 else { return }
        defaults.set(value, forKey: "preMuteVolume.\(kind.defaultsSuffix)")
    }

    private func preMuteVolume(_ kind: VolumeKind) -> Float {
        let stored = defaults.float(forKey: "preMuteVolume.\(kind.defaultsSuffix)")
        return stored > 0.005 ? stored : 0.5
    }
}