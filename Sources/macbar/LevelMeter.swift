import Foundation
import os

final class LevelMeter {
    private struct State {
        var smoothed = 0.0
        var lastPush = 0.0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let publishInterval = 1.0 / 30.0
    private let releaseTime = 0.12

    // Maps RMS to 0...1 with a VU feel: silence at -54 dB, full scale at -6 dB.
    static func level(fromRMS rms: Double) -> Double {
        guard rms > 1e-9 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 54) / 48))
    }

    // Called from the audio callback thread; pushes at ~30 Hz with fast attack
    // and a release time constant so the bar decays smoothly after sound stops.
    func push(rawLevel: Double, deliver: @escaping (Double) -> Void) {
        let now = CFAbsoluteTimeGetCurrent()
        let value = state.withLock { st -> Double? in
            let dt = max(0, now - st.lastPush)
            guard dt >= publishInterval else { return nil }
            st.lastPush = now
            let next = rawLevel > st.smoothed
                ? rawLevel
                : st.smoothed + (rawLevel - st.smoothed) * exp(-dt / releaseTime)
            st.smoothed = rawLevel == 0 && next < 0.015 ? 0 : next
            return st.smoothed
        }
        guard let value else { return }
        deliver(value)
    }

    func reset() {
        state.withLock { st in
            st.smoothed = 0
            st.lastPush = 0
        }
    }
}