import AppKit
import SwiftUI
import Combine
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    private let audio = AudioController()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastPopoverCloseDate: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 300, height: 140)
        popover.contentViewController = NSHostingController(rootView: PopoverView().environmentObject(audio))
        popover.delegate = self

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateStatusIcon()

        audio.$outputMuted.combineLatest(audio.$inputMuted, audio.$outputVolume, audio.$inputVolume)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in self?.updateStatusIcon() }
            .store(in: &cancellables)

        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.handleScroll(event)
            return event
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  self.popover.isShown,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "q" else { return event }
            NSApp.terminate(nil)
            return nil
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard let button = statusItem?.button,
              let window = button.window,
              window.frame.contains(NSEvent.mouseLocation) else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
        let step = Float(delta) * (event.hasPreciseScrollingDeltas ? 0.004 : 0.03)
        audio.setVolume(.output, audio.volume(for: .output) + step)
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        if isSilent(.input) {
            symbolName = "mic.slash.fill"
        } else if isSilent(.output) {
            symbolName = "speaker.slash.fill"
        } else {
            symbolName = "speaker.wave.2.fill"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "macbar")
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
    }

    private func isSilent(_ kind: VolumeKind) -> Bool {
        guard audio.isAvailable(kind) else { return false }
        if audio.isMuted(kind) { return true }
        return audio.hasVolumeControl(kind) && audio.volume(for: kind) < 0.005
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if let last = lastPopoverCloseDate, Date().timeIntervalSince(last) < 0.2 { return }
        audio.setMeteringActive(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverCloseDate = Date()
        audio.setMeteringActive(false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        audio.setMeteringActive(false)
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionItem = NSMenuItem(title: "macbar v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let github = NSMenuItem(title: "GitHub Project", action: #selector(openGitHubProject), keyEquivalent: "")
        github.target = self
        menu.addItem(github)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit macbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem?.menu = menu
        button.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    private let projectURL = "https://github.com/fun-ed/macbar"

    @objc private func openGitHubProject() {
        if let url = URL(string: projectURL) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            default:
                try service.register()
            }
        } catch {
            NSLog("macbar: launch at login toggle failed: \(error)")
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}