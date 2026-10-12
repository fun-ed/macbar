import XCTest
@testable import macbar

final class AppAudioStateTests: XCTestCase {
    func testGainClampsAndRejectsNonFiniteValues() {
        var state = AppAudioGain()
        XCTAssertFalse(state.needsRoute)
        state.setVolume(-1)
        XCTAssertEqual(state.effectiveGain, 0)
        XCTAssertTrue(state.needsRoute)
        state.setVolume(2)
        XCTAssertEqual(state.volume, 1)
        XCTAssertFalse(state.needsRoute)
        state.setVolume(.nan)
        state.setVolume(.infinity)
        XCTAssertEqual(state.volume, 1)
    }

    func testMuteRetainsGainAndSliderUnmutesWithoutChangingOtherApp() {
        var first = AppAudioGain()
        let second = AppAudioGain()
        first.setVolume(0.37)
        first.toggleMute()
        XCTAssertEqual(first.volume, 0.37)
        XCTAssertEqual(first.effectiveGain, 0)
        first.toggleMute()
        XCTAssertEqual(first.effectiveGain, 0.37)
        first.toggleMute()
        first.setVolume(0.2)
        XCTAssertFalse(first.muted)
        XCTAssertEqual(first.effectiveGain, 0.2)
        XCTAssertEqual(second.volume, 1)
        XCTAssertFalse(second.muted)
    }

    func testHelpersUseOuterAppOrParentBundleNotBundlePrefix() {
        let owner = process(10, parent: 1, bundle: "test.player", path: "/Applications/Player.app")
        let embedded = process(11, parent: 1, bundle: "test.player.helper", path: owner.appPath)
        let child = process(12, parent: 10, bundle: "test.audio.worker")
        let unrelated = process(13, parent: 1, bundle: "test.player.other")
        let groups = AppAudioGrouping.groups(processes: [owner, embedded, child, unrelated], ancestors: [10: owner],
                                             ownPID: 99, ownBundleID: "test.macbar")
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first { $0.appPath == owner.appPath }?.objectIDs, [10, 11, 12])
        XCTAssertEqual(groups.first { $0.appPath == nil }?.objectIDs, [13])
    }

    func testAppIsNotAssignedToItsLauncherAndOwnDescendantsAreExcluded() {
        let launcher = process(20, parent: 1, bundle: "test.terminal", path: "/Applications/Terminal.app")
        let player = process(10, parent: 20, bundle: "test.player", path: "/Applications/Player.app")
        let own = process(99, parent: 1, bundle: "test.macbar", path: "/Applications/macbar.app")
        let ownChild = process(100, parent: 99, bundle: "test.worker")
        let groups = AppAudioGrouping.groups(processes: [player, own, ownChild], ancestors: [20: launcher, 99: own],
                                             ownPID: 99, ownBundleID: "test.macbar")
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].appPath, player.appPath)
        XCTAssertEqual(groups[0].objectIDs, [10])
    }

    func testUnknownProcessesRemainSeparateAndParentCyclesAreBounded() {
        let first = process(10, parent: 11)
        let second = process(11, parent: 10)
        let groups = AppAudioGrouping.groups(processes: [first, second], ancestors: [10: first, 11: second],
                                             ownPID: 99, ownBundleID: nil)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.flatMap(\.objectIDs)), Set([UInt32(10), 11]))
    }

    func testPartialStartFailureCleanupRunsInReverseOrderExactlyOnce() {
        for acquired in 0...4 {
            let cleanup = AppAudioCleanup()
            var destroyed: [Int] = []
            for index in 0..<acquired { cleanup.append { destroyed.append(index) } }
            cleanup.close()
            cleanup.close()
            XCTAssertEqual(destroyed, Array((0..<acquired).reversed()))
        }
    }

    func testCleanupAlsoRunsWhenOwnerIsReleased() {
        var cleanup: AppAudioCleanup? = AppAudioCleanup()
        var destroyed = false
        cleanup?.append { destroyed = true }
        cleanup = nil
        XCTAssertTrue(destroyed)
    }

    func testZeroInputNeverVerifiesMuteAndTimesOut() {
        var health = AppAudioHealth(now: 0)
        XCTAssertNil(health.observe(now: 1, callbacks: 10, signals: 0, faulted: false))
        XCTAssertFalse(health.verified)
        XCTAssertEqual(health.observe(now: 4.1, callbacks: 41, signals: 0, faulted: false), .silent)
        XCTAssertFalse(health.verified)
    }

    func testVerifiedCaptureCarriesThroughLongSilence() {
        var probe = AppAudioHealth(now: 0)
        XCTAssertNil(probe.observe(now: 1, callbacks: 10, signals: 1, faulted: false))
        XCTAssertTrue(probe.verified)
        var formal = AppAudioHealth(now: 1, captureVerified: probe.verified)
        // Callbacks keep moving through more than 4 and 60 seconds without a new signal.
        for second in 2...62 {
            XCTAssertNil(formal.observe(now: Double(second) + 0.1, callbacks: UInt64(second * 10),
                                        signals: 0, faulted: false))
            XCTAssertTrue(formal.verified)
        }
    }

    func testCarriedCaptureIsInvalidatedByStalledCallbacksOrInvalidBuffers() {
        var stalled = AppAudioHealth(now: 0, captureVerified: true)
        XCTAssertEqual(stalled.observe(now: 3.1, callbacks: 0, signals: 0, faulted: false), .stalled)
        XCTAssertFalse(stalled.verified)

        var faulted = AppAudioHealth(now: 0, captureVerified: true)
        XCTAssertEqual(faulted.observe(now: 0.1, callbacks: 1, signals: 0, faulted: true), .invalidBuffers)
        XCTAssertFalse(faulted.verified)
    }

    private func process(_ pid: Int32, parent: Int32, bundle: String? = nil, path: String? = nil) -> AppAudioProcess {
        AppAudioProcess(objectID: UInt32(pid), pid: pid, parentPID: parent, bundleID: bundle,
                        name: bundle ?? "Process \(pid)", appPath: path, runningOutput: true)
    }
}
