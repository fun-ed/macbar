import AppKit
import Combine
import CoreAudio

struct AppAudioRowState: Identifiable {
    enum RouteStatus: Equatable {
        case original, checking, active, waiting, failed(String)
    }
    let group: AppAudioGroup
    let gain: AppAudioGain
    let status: RouteStatus
    var id: String { group.id }
}

final class AppAudioController: ObservableObject {
    @Published private(set) var applications: [AppAudioRowState] = []
    @Published private(set) var discoveryError: String?
    let supported: Bool

    private var groups: [AppAudioGroup] = []
    private var gains: [String: AppAudioGain] = [:]
    private var routes: [String: AppAudioRoute] = [:]
    private var errors: [String: String] = [:]
    private var signatures: [String: [AudioObjectID]] = [:]
    private var output: AudioObjectID = 0
    private var timer: DispatchSourceTimer?
    private var nextDiscovery: TimeInterval = 0
    private var stopped = true
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [Listener] = []
    private var watchedOutputStreams: [AudioObjectID] = []
    private var watchedProcesses: Set<AudioObjectID> = []
    private var watchedOutput: AudioObjectID = 0

    init() {
        if #available(macOS 14.4, *) { supported = true } else { supported = false }
    }

    func start() {
        guard supported, stopped else { return }
        stopped = false
        addListener(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.refresh()
        }
        addListener(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.outputChanged()
        }
        refresh()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        stopped = true
        timer?.cancel()
        timer = nil
        for route in routes.values { route.stop() }
        routes = [:]
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
        listeners = []
        watchedProcesses = []
        watchedOutput = 0
    }

    deinit { stop() }

    func setVolume(_ id: String, _ value: Float) {
        guard groups.contains(where: { $0.id == id }) else { return }
        gains[id, default: AppAudioGain()].setVolume(value)
        errors[id] = nil
        reconcile()
    }

    func toggleMute(_ id: String) {
        guard groups.contains(where: { $0.id == id }) else { return }
        gains[id, default: AppAudioGain()].toggleMute()
        errors[id] = nil
        reconcile()
    }

    func retry(_ id: String) {
        errors[id] = nil
        reconcile()
    }

    private func tick() {
        guard !stopped else { return }
        let currentOutput = (try? AppAudioHardware.defaultOutput()) ?? 0
        if currentOutput != output { outputChanged(); return }
        let now = ProcessInfo.processInfo.systemUptime
        if now >= nextDiscovery { refresh() }
        for id in Array(routes.keys) {
            guard let route = routes[id] else { continue }
            do {
                if try route.poll(), route.probing {
                    let matchingGroup = groups.first(where: { $0.id == id })
                    let matchesCurrentTarget = matchingGroup?.objectIDs == route.processIDs
                        && route.outputDevice == output
                    route.stop()
                    routes[id] = nil
                    if matchesCurrentTarget {
                        try createRoute(id, probing: false, captureVerified: true)
                    } else {
                        try createRoute(id, probing: true)
                    }
                }
            } catch {
                fail(id, error)
            }
        }
        publish()
    }

    private func outputChanged() {
        guard !stopped else { return }
        for route in routes.values { route.stop() }
        routes = [:]
        errors = [:]
        output = (try? AppAudioHardware.defaultOutput()) ?? 0
        refresh()
    }

    private func refresh() {
        guard !stopped else { return }
        nextDiscovery = ProcessInfo.processInfo.systemUptime + 1
        do {
            let newOutput = (try? AppAudioHardware.defaultOutput()) ?? 0
            if output != newOutput {
                for route in routes.values { route.stop() }
                routes = [:]
                errors = [:]
                output = newOutput
            }
            groups = try AppAudioDiscovery.snapshot()
            discoveryError = nil
            let current = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.objectIDs) })
            for id in Array(routes.keys) where current[id] != routes[id]?.processIDs {
                routes.removeValue(forKey: id)?.stop()
            }
            for (id, ids) in current where signatures[id] != ids { errors[id] = nil }
            errors = errors.filter { current[$0.key] != nil }
            signatures = current
            syncListeners()
            reconcile()
        } catch {
            for route in routes.values { route.stop() }
            routes = [:]
            discoveryError = "Unable to list audio applications: \(error.localizedDescription)"
            publish()
        }
    }

    private func reconcile() {
        guard !stopped else { return }
        for group in groups {
            let gain = gains[group.id] ?? AppAudioGain()
            if !gain.needsRoute || !group.isRunning {
                routes.removeValue(forKey: group.id)?.stop()
                if !gain.needsRoute { errors[group.id] = nil }
                continue
            }
            if let route = routes[group.id] { route.setGain(gain.effectiveGain); continue }
            guard errors[group.id] == nil else { continue }
            do { try createRoute(group.id, probing: true) }
            catch { fail(group.id, error) }
        }
        publish()
    }

    private func createRoute(_ id: String, probing: Bool, captureVerified: Bool = false) throws {
        guard #available(macOS 14.4, *), let group = groups.first(where: { $0.id == id }),
              (gains[id] ?? AppAudioGain()).needsRoute, group.isRunning else { return }
        guard output != 0 else {
            throw AppAudioHardwareError(operation: "No default output", status: kAudioHardwareBadDeviceError)
        }
        let route = try AppAudioRoute(processIDs: group.objectIDs, outputDevice: output,
                                      gain: (gains[id] ?? AppAudioGain()).effectiveGain, probing: probing,
                                      captureVerified: captureVerified)
        guard (try? AppAudioHardware.defaultOutput()) == output else {
            route.stop()
            throw AppAudioHardwareError(operation: "Output changed while creating route", status: kAudioHardwareBadDeviceError)
        }
        routes[id] = route
    }

    private func fail(_ id: String, _ error: Error) {
        routes.removeValue(forKey: id)?.stop()
        errors[id] = error.localizedDescription
    }

    private func publish() {
        applications = groups.filter { $0.isRunning || gains[$0.id]?.needsRoute == true }.map { group in
            let gain = gains[group.id] ?? AppAudioGain()
            let status: AppAudioRowState.RouteStatus
            if let error = errors[group.id] { status = .failed(error) }
            else if let route = routes[group.id] { status = route.probing || !route.verified ? .checking : .active }
            else { status = gain.needsRoute ? .waiting : .original }
            return AppAudioRowState(group: group, gain: gain, status: status)
        }
    }

    private func addListener(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                             changed: @escaping () -> Void) {
        var address = AppAudioHardware.address(selector, scope: scope)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, !self.stopped else { return }
            changed()
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append(Listener(object: object, address: address, block: block))
        }
        // Polling remains active if an individual HAL listener cannot be installed.
    }

    private func syncListeners() {
        let processes = Set(groups.flatMap(\.objectIDs))
        let outputStreams = (try? AppAudioHardware.objects(output, kAudioDevicePropertyStreams,
                                                          scope: kAudioObjectPropertyScopeOutput)) ?? []
        guard processes != watchedProcesses || output != watchedOutput || outputStreams != watchedOutputStreams else { return }
        for var listener in listeners where listener.object != AudioObjectID(kAudioObjectSystemObject) {
            AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, .main, listener.block)
        }
        listeners.removeAll { $0.object != AudioObjectID(kAudioObjectSystemObject) }
        watchedProcesses = processes
        watchedOutput = output
        watchedOutputStreams = outputStreams
        for process in processes {
            addListener(process, kAudioProcessPropertyIsRunningOutput) { [weak self] in self?.refresh() }
        }
        if output != 0 {
            for selector in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive] {
                addListener(output, selector) { [weak self] in self?.outputChanged() }
            }
            addListener(output, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput) { [weak self] in
                self?.outputChanged()
            }
            for stream in outputStreams {
                addListener(stream, kAudioStreamPropertyVirtualFormat) { [weak self] in self?.outputChanged() }
            }
        }
    }
}
