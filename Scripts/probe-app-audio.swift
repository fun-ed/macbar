// Build a signed probe bundle with its own audio-capture usage description:
// bash Scripts/make-app-audio-probe.sh
// Close macbar to avoid competing routes. Run while TWO DIFFERENT apps continuously play:
// .build/app-audio-probe.app/Contents/MacOS/app-audio-probe <PID-of-A> <PID-of-B>
// This captures/replays A only, never writes device volume, and always closes the route.
// Listen for A at 50%, then muted, then restored. B must sound unchanged in every stage.
// Machine checks prove live input, callbacks, master property preservation and HAL cleanup;
// they do NOT prove physical audibility, latency, or perceptual isolation of B.

import AppKit
import CoreAudio

@main
struct AppAudioProbe {
    static func main() {
        do {
            guard #available(macOS 14.4, *) else { throw ProbeError("Requires macOS 14.4+") }
            guard CommandLine.arguments.count == 3,
                  let firstPID = Int32(CommandLine.arguments[1]), let secondPID = Int32(CommandLine.arguments[2]),
                  firstPID != secondPID, firstPID != getpid(), secondPID != getpid() else {
                throw ProbeError("Usage: probe-app-audio <PID-of-A> <PID-of-B>; play audio continuously in both apps")
            }
            let groups = try AppAudioDiscovery.snapshot()
            guard let first = groups.first(where: { $0.processes.contains { $0.pid == firstPID } }),
                  let second = groups.first(where: { $0.processes.contains { $0.pid == secondPID } }),
                  first.id != second.id, first.isRunning, second.isRunning else {
                throw ProbeError("PIDs must belong to two different, currently playing application groups")
            }
            let output = try AppAudioHardware.defaultOutput()
            let master = masterProperties(output)
            let devicesBefore = try ownedAggregates()
            let tapsBefore = try ownedTaps()
            print("A: \(first.name), process objects \(first.objectIDs)")
            print("B: \(second.name), process objects \(second.objectIDs); not included in the tap")
            let probe = try AppAudioRoute(processIDs: first.objectIDs, outputDevice: output, gain: 0, probing: true)
            defer { probe.stop() }
            try waitForAudio(probe, output: output, duration: 1)
            probe.stop()
            let route = try AppAudioRoute(processIDs: first.objectIDs, outputDevice: output,
                                          gain: 0.5, probing: false, captureVerified: true)
            defer { route.stop() }
            print("50%: A should be quieter; B should be unchanged (listen for 3 seconds)")
            try waitForAudio(route, output: output, duration: 3)
            route.setGain(0)
            print("Mute: A should be silent; B should be unchanged (listen for 3 seconds)")
            try waitForAudio(route, output: output, duration: 3)
            guard second.objectIDs.contains(where: {
                (try? AppAudioHardware.uint32($0, kAudioProcessPropertyIsRunningOutput)) == 1
            }) else { throw ProbeError("B stopped output; isolation observation is invalid") }
            route.stop() // 100% is the original route, not a unity-gain capture/replay route.
            print("Restored: A and B should both play normally")
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
            guard masterProperties(output) == master else { throw ProbeError("Master volume/mute properties changed during probe") }
            guard try ownedAggregates() == devicesBefore, try ownedTaps() == tapsBefore else {
                throw ProbeError("Private app route resources remain after stop")
            }
            print("PASS: live tap input and replay callbacks observed; master properties unchanged; app taps/aggregates cleaned up")
            print("MANUAL REQUIRED: A/B audible isolation, popover-closed operation, output switch, app exit, TCC refusal and macOS 13 fallback")
        } catch {
            fputs("FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func waitForAudio(_ route: AppAudioRoute, output: AudioObjectID, duration: TimeInterval) throws {
        let deadline = Date(timeIntervalSinceNow: duration)
        var verified = false
        repeat {
            guard try AppAudioHardware.defaultOutput() == output else { throw ProbeError("Output changed during probe") }
            verified = try route.poll() || verified
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        } while Date() < deadline
        guard verified else { throw ProbeError("No non-zero audio captured; check system audio authorization and playback") }
    }

    private static func ownedAggregates() throws -> Set<String> {
        let devices = try AppAudioHardware.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return Set(devices.compactMap { try? AppAudioHardware.string($0, kAudioDevicePropertyDeviceUID) }
            .filter { $0.hasPrefix("no.runbox.funed.macbar.route.") })
    }

    private static func ownedTaps() throws -> Set<AudioObjectID> {
        let taps = try AppAudioHardware.objects(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyTapList)
        return Set(taps.filter { (try? AppAudioHardware.string($0, kAudioObjectPropertyName)) == "macbar-app-volume" })
    }

    private static func masterProperties(_ device: AudioObjectID) -> [String: UInt32] {
        var values: [String: UInt32] = [:]
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in UInt32(0)...UInt32(32) {
                var address = AppAudioHardware.address(selector, scope: kAudioObjectPropertyScopeOutput)
                address.mElement = element
                var bits: UInt32 = 0
                var size: UInt32 = 4
                if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &bits) == noErr, size == 4 {
                    values["\(selector):\(element)"] = bits
                }
            }
        }
        return values
    }

    private struct ProbeError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
