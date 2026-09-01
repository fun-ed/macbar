import CoreAudio
import Foundation

var failures = 0

func report(_ name: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : "  (\(detail))")")
    if !ok { failures += 1 }
}

func propertyAddress(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID {
    var deviceID = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var addr = propertyAddress(selector, kAudioObjectPropertyScopeGlobal)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
    return deviceID
}

func readFloat(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement) -> Float? {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
    var value = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
    return status == noErr ? value : nil
}

func hasVolumeElement(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ element: AudioObjectPropertyElement) -> Bool {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
    return AudioObjectHasProperty(device, &addr)
}

// mirrors AudioController: main element first, else average of channels
func volumeOf(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Float? {
    if hasVolumeElement(device, scope, kAudioObjectPropertyElementMain) {
        var addr = propertyAddress(kAudioDevicePropertyVolumeScalar, scope)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            return value
        }
    }
    var sum = Float(0)
    var count = 0
    for element in UInt32(1)...UInt32(32) where hasVolumeElement(device, scope, element) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            sum += value
            count += 1
        }
    }
    return count > 0 ? sum / Float(count) : nil
}

func writeVolumeAll(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ value: Float) {
    if hasVolumeElement(device, scope, kAudioObjectPropertyElementMain) {
        var addr = propertyAddress(kAudioDevicePropertyVolumeScalar, scope)
        var v = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v)
        return
    }
    for element in UInt32(1)...UInt32(32) where hasVolumeElement(device, scope, element) {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: scope, mElement: element)
        var v = Float32(value)
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &v)
    }
}

func readMute(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool? {
    var addr = propertyAddress(kAudioDevicePropertyMute, scope)
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value)
    return status == noErr ? value != 0 : nil
}

func setMute(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope, _ muted: Bool) {
    var addr = propertyAddress(kAudioDevicePropertyMute, scope)
    var value = UInt32(muted ? 1 : 0)
    let size = UInt32(MemoryLayout<UInt32>.size)
    AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
}

func devicesWithScope(_ scope: AudioObjectPropertyScope) -> [AudioObjectID] {
    var sizeAddr = propertyAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &sizeAddr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    var readSize = size
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &sizeAddr, 0, nil, &readSize, &ids) == noErr else { return [] }
    return ids.filter { id in
        var streamsAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &streamsAddr, 0, nil, &streamSize) == noErr && streamSize > 0
    }
}

let outDevice = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
let inDevice = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
print("output device id=\(outDevice), input device id=\(inDevice)")

if outDevice != 0, let v0 = volumeOf(outDevice, kAudioObjectPropertyScopeOutput) {
    let target = min(v0 + 0.05, 1.0)
    writeVolumeAll(outDevice, kAudioObjectPropertyScopeOutput, target)
    Thread.sleep(forTimeInterval: 0.3)
    let echoed = volumeOf(outDevice, kAudioObjectPropertyScopeOutput)
    report("output volume set/get", echoed != nil && abs(echoed! - target) < 0.02, "\(Int(round(v0 * 100)))% -> \(Int(round(target * 100)))%")
    writeVolumeAll(outDevice, kAudioObjectPropertyScopeOutput, v0)
    Thread.sleep(forTimeInterval: 0.3)
    let restored = volumeOf(outDevice, kAudioObjectPropertyScopeOutput)
    report("output volume restore", restored != nil && abs(restored! - v0) < 0.02)
} else {
    report("output volume readable", false)
}

if let m0 = readMute(outDevice, kAudioObjectPropertyScopeOutput) {
    setMute(outDevice, kAudioObjectPropertyScopeOutput, !m0)
    let after = readMute(outDevice, kAudioObjectPropertyScopeOutput)
    report("output mute toggle", after != nil && after! != m0)
    setMute(outDevice, kAudioObjectPropertyScopeOutput, m0)
    let restored = readMute(outDevice, kAudioObjectPropertyScopeOutput)
    report("output mute restore", restored == m0)
} else {
    report("output mute supported", false, "no hardware mute on default output; app uses software fallback")
}

if inDevice != 0, let v = readFloat(inDevice, kAudioObjectPropertyScopeInput, kAudioObjectPropertyElementMain) {
    report("input volume readable", true, "\(Int(round(v * 100)))%")
} else {
    report("input volume readable", false)
}

if readMute(inDevice, kAudioObjectPropertyScopeInput) != nil {
    report("input mute property present", true)
} else {
    report("input mute property present", false, "software-mute fallback applies in app")
}

let outputs = devicesWithScope(kAudioObjectPropertyScopeOutput)
report("output devices enumerated", outputs.contains(outDevice), "count=\(outputs.count)")

exit(failures == 0 ? 0 : 1)
