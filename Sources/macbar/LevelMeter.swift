import Foundation
import os

final class LevelMeter {
    private struct State {
        var smoothed = 0.0
        var lastPush = 0.0
        var pendingPeak = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let publishInterval = 0.5
    private let releaseTime = 0.12

    // Maps RMS to 0...1 with a VU feel: silence at -54 dB, full scale at -6 dB.
    static func level(fromRMS rms: Double) -> Double {
        guard rms > 1e-9 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 54) / 48))
    }

    // Called from the audio callback thread; publishes at most 2 Hz with fast attack
    // and a release time constant so the bar decays smoothly after sound stops.
    func push(rawLevel: Double, now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent(), deliver: @escaping (Double) -> Void) {
        let value = state.withLock { st -> Double? in
            // Keep brief RMS-mapped signals that arrive between publications.
            st.pendingPeak = max(st.pendingPeak, rawLevel)
            let dt = max(0, now - st.lastPush)
            guard dt >= publishInterval else { return nil }
            st.lastPush = now
            let target = st.pendingPeak
            st.pendingPeak = 0
            let wasSilent = st.smoothed == 0
            let next = target > st.smoothed
                ? target
                : target + (st.smoothed - target) * exp(-dt / releaseTime)
            st.smoothed = target == 0 && next < 0.015 ? 0 : next
            guard !wasSilent || st.smoothed != 0 else { return nil }
            return st.smoothed
        }
        guard let value else { return }
        deliver(value)
    }

    func reset() {
        state.withLock { st in
            st.smoothed = 0
            st.lastPush = 0
            st.pendingPeak = 0
        }
    }
}