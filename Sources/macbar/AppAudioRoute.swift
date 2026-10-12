import CoreAudio
import Foundation
import AppAudioRT

final class AppAudioRoute {
    let processIDs: [AudioObjectID]
    let outputDevice: AudioObjectID
    let probing: Bool
    private let cleanup = AppAudioCleanup()
    private let captureVerified: Bool
    private var context: OpaquePointer?
    private var health = AppAudioHealth(now: ProcessInfo.processInfo.systemUptime)
    var verified: Bool { health.verified }

    @available(macOS 14.4, *)
    init(processIDs: [AudioObjectID], outputDevice: AudioObjectID, gain: Float, probing: Bool,
         captureVerified: Bool = false) throws {
        self.processIDs = processIDs
        self.outputDevice = outputDevice
        self.probing = probing
        self.captureVerified = captureVerified
        do {
            try start(gain: gain)
        } catch {
            stop()
            throw error
        }
    }

    func setGain(_ gain: Float) {
        if let context { MBAppAudioRTSetGain(context, probing ? 0 : gain) }
    }

    // Called only on the main thread; the callback communicates through lock-free C atomics.
    func poll() throws -> Bool {
        guard let context else { return false }
        let failure = health.observe(now: ProcessInfo.processInfo.systemUptime,
                                     callbacks: MBAppAudioRTCallbacks(context),
                                     signals: MBAppAudioRTSignals(context),
                                     faulted: MBAppAudioRTFaulted(context) != 0)
        switch failure {
        case .invalidBuffers:
            throw AppAudioHardwareError(operation: "Unsupported live audio buffer layout", status: kAudioDeviceUnsupportedFormatError)
        case .stalled:
            throw AppAudioHardwareError(operation: "Audio route stopped delivering buffers", status: kAudioHardwareNotRunningError)
        case .silent:
            throw AppAudioHardwareError(operation: "No captured audio; allow system audio access and play audio, then retry", status: kAudioHardwareUnspecifiedError)
        case nil: break
        }
        return verified
    }

    func stop() {
        if let context { MBAppAudioRTSetEnabled(context, 0) }
        cleanup.close()
        context = nil
        health = AppAudioHealth(now: ProcessInfo.processInfo.systemUptime)
    }

    deinit { stop() }

    @available(macOS 14.4, *)
    private func start(gain: Float) throws {
        guard !processIDs.isEmpty else {
            throw AppAudioHardwareError(operation: "No audio processes", status: kAudioHardwareBadObjectError)
        }
        for id in processIDs {
            let pid = try AppAudioHardware.uint32(id, kAudioProcessPropertyPID)
            guard pid != UInt32(getpid()) else {
                throw AppAudioHardwareError(operation: "Self capture rejected", status: kAudioHardwareIllegalOperationError)
            }
        }
        guard try AppAudioHardware.defaultOutput() == outputDevice else {
            throw AppAudioHardwareError(operation: "Output changed before creating tap", status: kAudioHardwareBadDeviceError)
        }
        let outputStreams = try AppAudioHardware.objects(outputDevice, kAudioDevicePropertyStreams,
                                                        scope: kAudioObjectPropertyScopeOutput)
        guard outputStreams.count == 1, outputStreams[0] != kAudioObjectUnknown else {
            throw AppAudioHardwareError(operation: "Tap requires one physical output stream (1–32 Float32 channels)", status: kAudioDeviceUnsupportedFormatError)
        }
        let outputUID = try AppAudioHardware.string(outputDevice, kAudioDevicePropertyDeviceUID)
        let description = CATapDescription()
        description.name = "macbar-app-volume"
        description.uuid = UUID()
        description.isPrivate = true
        description.isExclusive = false
        description.__processes = processIDs.map { NSNumber(value: $0) }
        description.isMixdown = true
        description.isMono = false
        description.deviceUID = outputUID
        description.__stream = NSNumber(value: 0)
        description.muteBehavior = probing ? .unmuted : .mutedWhenTapped
        var aggregateDestroyed = true
        var procDestroyed = true
        var rt: OpaquePointer?
        // Registered first, released last: callback storage outlives every HAL resource.
        cleanup.append {
            guard let rt else { return }
            if procDestroyed || aggregateDestroyed { MBAppAudioRTDestroy(rt) }
            else { NSLog("macbar: HAL cleanup failed; disabled route context retained for callback safety") }
        }

        var tap: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        if tap != 0 {
            cleanup.append { Self.reportCleanup(AudioHardwareDestroyProcessTap(tap), "destroy app tap") }
        }
        try AppAudioHardware.check(tapStatus, "Create app tap")
        guard tap != 0 else {
            throw AppAudioHardwareError(operation: "Empty app tap for output stream 0",
                                        status: kAudioHardwareBadObjectError)
        }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var property = AppAudioHardware.address(kAudioTapPropertyFormat)
        try AppAudioHardware.check(AudioObjectGetPropertyData(tap, &property, 0, nil, &size, &format), "Read tap format")
        guard size == MemoryLayout<AudioStreamBasicDescription>.size else {
            throw AppAudioHardwareError(operation: "Invalid tap format size", status: kAudioHardwareBadPropertySizeError)
        }
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "macbar-app-volume-aggregate",
            kAudioAggregateDeviceUIDKey: "no.runbox.funed.macbar.route.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        var aggregate: AudioObjectID = 0
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate)
        aggregateDestroyed = aggregate == 0
        if aggregate != 0 {
            cleanup.append {
                let status = AudioHardwareDestroyAggregateDevice(aggregate)
                aggregateDestroyed = status == noErr
                Self.reportCleanup(status, "destroy app aggregate")
            }
        }
        try AppAudioHardware.check(aggregateStatus, "Create app aggregate")
        guard aggregate != 0 else { throw AppAudioHardwareError(operation: "Empty app aggregate", status: kAudioHardwareBadObjectError) }

        var validationStatus: OSStatus = noErr
        guard let newContext = MBAppAudioRTCreate(aggregate, outputDevice, format, &validationStatus) else {
            throw AppAudioHardwareError(operation: "Validate aggregate topology/stereo mapping (one physical device, stereo Float32 tap, 1–32 Float32 output channels)", status: validationStatus)
        }
        rt = newContext
        context = newContext
        var proc: AudioDeviceIOProcID?
        let procStatus = AudioDeviceCreateIOProcID(aggregate, MBAppAudioRTIOProc, UnsafeMutableRawPointer(newContext), &proc)
        if let proc {
            procDestroyed = false
            cleanup.append {
                Self.reportCleanup(AudioDeviceStop(aggregate, proc), "stop app IOProc")
                let status = AudioDeviceDestroyIOProcID(aggregate, proc)
                procDestroyed = status == noErr
                Self.reportCleanup(status, "destroy app IOProc")
            }
        }
        try AppAudioHardware.check(procStatus, "Create app IOProc")
        guard let proc else { throw AppAudioHardwareError(operation: "Empty app IOProc", status: kAudioHardwareBadObjectError) }
        try AppAudioHardware.check(MBAppAudioRTDisablePhysicalInputs(aggregate, proc), "Disable physical input streams")
        MBAppAudioRTSetGain(newContext, probing ? 0 : gain)
        MBAppAudioRTSetEnabled(newContext, 1)
        try AppAudioHardware.check(AudioDeviceStart(aggregate, proc), "Start app audio route")
        health = AppAudioHealth(now: ProcessInfo.processInfo.systemUptime, captureVerified: captureVerified)
    }

    private static func reportCleanup(_ status: OSStatus, _ operation: String) {
        if status != noErr { NSLog("macbar: \(operation) failed (CoreAudio \(status))") }
    }
}
