import Foundation

struct AppAudioGain: Equatable {
    private(set) var volume: Float = 1
    private(set) var muted = false

    var effectiveGain: Float { muted ? 0 : volume }
    var needsRoute: Bool { muted || volume < 1 }

    mutating func setVolume(_ value: Float) {
        guard value.isFinite else { return }
        volume = min(max(value, 0), 1)
        muted = false
    }

    mutating func toggleMute() { muted.toggle() }
}

struct AppAudioProcess: Equatable {
    let objectID: UInt32
    let pid: Int32
    let parentPID: Int32
    let bundleID: String?
    let name: String
    let appPath: String?
    let runningOutput: Bool
}

struct AppAudioGroup: Equatable {
    let id: String
    let name: String
    let appPath: String?
    var processes: [AppAudioProcess]

    var objectIDs: [UInt32] { processes.map(\.objectID).sorted() }
    var isRunning: Bool { processes.contains { $0.runningOutput } }
}

enum AppAudioGrouping {
    // Ancestors include non-audio parents. Never merge unrelated bundle IDs by prefix.
    static func groups(processes: [AppAudioProcess], ancestors: [Int32: AppAudioProcess], ownPID: Int32,
                       ownBundleID: String?) -> [AppAudioGroup] {
        var groups: [String: AppAudioGroup] = [:]
        for process in processes {
            var owner = process
            var cursor = process
            var visited: Set<Int32> = []
            var excluded = false
            for _ in 0..<32 {
                if cursor.pid == ownPID || (ownBundleID != nil && cursor.bundleID == ownBundleID) {
                    excluded = true
                    break
                }
                if owner.appPath == nil, cursor.appPath != nil { owner = cursor }
                guard visited.insert(cursor.pid).inserted,
                      cursor.parentPID > 1, let parent = ancestors[cursor.parentPID] else { break }
                cursor = parent
            }
            guard !excluded else { continue }
            let id: String
            if let path = owner.appPath {
                id = "app:\(path)"
            } else if let bundle = owner.bundleID, !bundle.isEmpty {
                id = "bundle:\(bundle)"
            } else {
                id = "pid:\(owner.pid)"
            }
            if groups[id] == nil {
                groups[id] = AppAudioGroup(id: id, name: owner.name, appPath: owner.appPath, processes: [])
            }
            groups[id]?.processes.append(process)
        }
        return groups.values.sorted {
            if $0.name == $1.name { return $0.id < $1.id }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// Small resource stack: every acquisition registers its inverse before the next fallible step.
// Used for partial-start failures as well as normal route shutdown.
final class AppAudioCleanup {
    private var actions: [() -> Void] = []

    func append(_ action: @escaping () -> Void) { actions.append(action) }

    func close() {
        let pending = actions.reversed()
        actions = []
        for action in pending { action() }
    }

    deinit { close() }
}

struct AppAudioHealth {
    enum Failure: Equatable { case invalidBuffers, stalled, silent }
    private(set) var verified: Bool
    private var lastCallbackAt: TimeInterval
    private var lastSignalAt: TimeInterval
    private var callbacks: UInt64 = 0
    private var signals: UInt64 = 0

    init(now: TimeInterval, captureVerified: Bool = false) {
        verified = captureVerified
        lastCallbackAt = now
        lastSignalAt = now
    }

    mutating func observe(now: TimeInterval, callbacks: UInt64, signals: UInt64, faulted: Bool) -> Failure? {
        if faulted { verified = false; return .invalidBuffers }
        if callbacks != self.callbacks { self.callbacks = callbacks; lastCallbackAt = now }
        if signals != self.signals { self.signals = signals; lastSignalAt = now; verified = true }
        if now - lastCallbackAt > 2 { verified = false; return .stalled }
        // An unverified route needs an initial captured signal.
        // After verification, silence cannot distinguish quiet audio from revoked access.
        if !verified && now - lastSignalAt > 4 { return .silent }
        return nil
    }
}
