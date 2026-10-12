import AppKit
import CoreAudio
import AppAudioRT

struct AppAudioHardwareError: LocalizedError {
    let operation: String
    let status: OSStatus
    var errorDescription: String? { "\(operation) failed (CoreAudio \(status))." }
}

enum AppAudioHardware {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AppAudioHardwareError(operation: operation, status: status) }
    }

    static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var property = address(selector)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "Read audio property")
        guard size == MemoryLayout<UInt32>.size else {
            throw AppAudioHardwareError(operation: "Audio property size", status: kAudioHardwareBadPropertySizeError)
        }
        return value
    }

    static func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [AudioObjectID] {
        var property = address(selector, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size), "Read audio list size")
        guard size % 4 == 0, size <= 4096 * 4 else {
            throw AppAudioHardwareError(operation: "Audio list size", status: kAudioHardwareBadPropertySizeError)
        }
        if size == 0 { return [] }
        var values = [AudioObjectID](repeating: 0, count: Int(size / 4))
        let capacity = size
        try values.withUnsafeMutableBytes {
            try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!), "Read audio list")
        }
        guard size <= capacity, size % 4 == 0 else {
            throw AppAudioHardwareError(operation: "Audio list changed", status: kAudioHardwareBadPropertySizeError)
        }
        return Array(values.prefix(Int(size / 4)))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value), "Read audio identifier")
        guard let value else {
            throw AppAudioHardwareError(operation: "Missing audio identifier", status: kAudioHardwareUnspecifiedError)
        }
        return value.takeRetainedValue() as String
    }

    static func defaultOutput() throws -> AudioObjectID {
        let device = try uint32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
        guard device != kAudioObjectUnknown else {
            throw AppAudioHardwareError(operation: "No default output", status: kAudioHardwareBadDeviceError)
        }
        return device
    }
}

enum AppAudioDiscovery {
    static func snapshot() throws -> [AppAudioGroup] {
        let ids = try AppAudioHardware.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        var processes: [AppAudioProcess] = []
        var ancestors: [Int32: AppAudioProcess] = [:]
        for id in ids {
            guard let rawPID = try? AppAudioHardware.uint32(id, kAudioProcessPropertyPID) else { continue }
            let pid = Int32(bitPattern: rawPID)
            guard pid > 0, pid != getpid() else { continue }
            let bundleID = try? AppAudioHardware.string(id, kAudioProcessPropertyBundleID)
            let running = (try? AppAudioHardware.uint32(id, kAudioProcessPropertyIsRunningOutput)) == 1
            let outputs = (try? AppAudioHardware.objects(id, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)) ?? []
            guard running || !outputs.isEmpty else { continue }
            let process = metadata(pid: pid, objectID: id, bundleID: bundleID, running: running)
            processes.append(process)
            ancestors[pid] = process
            var parent = process.parentPID
            var seen: Set<Int32> = [pid]
            for _ in 0..<32 {
                guard parent > 1, seen.insert(parent).inserted else { break }
                let ancestor = ancestors[parent] ?? metadata(pid: parent, objectID: 0, bundleID: nil, running: false)
                ancestors[parent] = ancestor
                parent = ancestor.parentPID
            }
        }
        return AppAudioGrouping.groups(processes: processes, ancestors: ancestors, ownPID: getpid(),
                                       ownBundleID: Bundle.main.bundleIdentifier)
            .filter { $0.appPath != Bundle.main.bundleURL.path }
    }

    private static func metadata(pid: Int32, objectID: AudioObjectID, bundleID: String?, running: Bool) -> AppAudioProcess {
        let application = NSRunningApplication(processIdentifier: pid)
        var bytes = [CChar](repeating: 0, count: 4096)
        let length = bytes.withUnsafeMutableBufferPointer { MBAppAudioProcessPath(pid, $0.baseAddress!, UInt32($0.count)) }
        let executable = length > 0 ? String(cString: bytes) : nil
        // The outer .app owns embedded helpers, even when launchd has reparented them.
        let appPath = (executable ?? application?.bundleURL?.path).flatMap { path -> String? in
            let components = URL(fileURLWithPath: path).pathComponents
            guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
            return NSString.path(withComponents: Array(components.prefix(index + 1)))
        }
        let bundle = appPath.flatMap { Bundle(path: $0) }
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        let executableName = executable.map { URL(fileURLWithPath: $0).lastPathComponent }
        let fallbackName = executableName ?? bundleID ?? "Process \(pid)"
        let name = displayName ?? bundleName ?? application?.localizedName ?? fallbackName
        return AppAudioProcess(objectID: objectID, pid: pid, parentPID: MBAppAudioParentPID(pid),
                               bundleID: bundle?.bundleIdentifier ?? bundleID ?? application?.bundleIdentifier,
                               name: name, appPath: appPath, runningOutput: running)
    }
}
