import AppKit
import Carbon.HIToolbox
import ContextDockKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panelController: IslandPanelController?
    private var hotKeyRef: EventHotKeyRef?
    private let model = DockModel()
    private var socketServer: EventSocketServer?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var discoveryTimer: Timer?
    private var glassProbeController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let controller = IslandPanelController(model: model)
        panelController = controller
        controller.showCollapsed()
        registerGlobalHotKey()
        startEventSocket()
        observeScreenLock()
        observeSettingsRequests()
        model.bootstrap()
        if #available(macOS 26, *) {
            DockLog.info("liquid glass: native glassEffect path")
        } else {
            DockLog.info("liquid glass: matte fallback path")
        }
        _ = HookInstaller.installAll()
        startAdaptiveDiscovery()
        if !model.islandSettings.onboarded {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        model.persist()
    }

    // MARK: - Menu (accessory apps get none by default; add Settings + Quit)

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsMenuItem), keyEquivalent: ","))
        appMenu.addItem(.separator())
        let debugItem = NSMenuItem(title: "Debug: Glass Probe", action: #selector(openGlassProbeMenuItem), keyEquivalent: "")
        debugItem.target = self
        appMenu.addItem(debugItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit ContextDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    // Crash fix (EXC_BAD_ACCESS in openSettings): ObjC menu delivery bypasses
    // actor isolation, and a closed NSWindow with isReleasedWhenClosed leaves
    // a dangling retain. Trampoline: @objc/nonisolated → hop to MainActor;
    // windows never self-release; delegate nils them on close.
    @objc nonisolated private func openSettingsMenuItem() {
        Task { @MainActor in (NSApp.delegate as? AppDelegate)?.openSettings() }
    }

    /// Isolated probe first (brief §3): NSGlassEffectView refraction away
    /// from the notch, two labeled rows, nonactivating. Retained while open.
    @objc nonisolated private func openGlassProbeMenuItem() {
        Task { @MainActor in
            guard let self = NSApp.delegate as? AppDelegate else { return }
            if #available(macOS 26.0, *) {
                if self.glassProbeController == nil {
                    self.glassProbeController = ContextDockGlassProbeController()
                }
                (self.glassProbeController as? ContextDockGlassProbeController)?.present()
            } else {
                self.model.lastError = "Native Liquid Glass needs macOS 26+."
            }
        }
    }

    private func openSettings() {
        if let w = settingsWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        w.title = "ContextDock Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: SettingsView(model: model))
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
        DockLog.info("settings opened")
    }

    private func showOnboarding() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "Welcome to ContextDock"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: OnboardingView(model: model))
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = w
        DockLog.info("onboarding shown")
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        let number = (notification.object as? NSWindow)?.windowNumber ?? -1
        Task { @MainActor in
            guard let self = NSApp.delegate as? AppDelegate else { return }
            if self.settingsWindow?.windowNumber == number { self.settingsWindow = nil }
            if self.onboardingWindow?.windowNumber == number { self.onboardingWindow = nil }
        }
    }

    private func observeSettingsRequests() {
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.openSettings() }
        }
        NotificationCenter.default.addObserver(forName: .closeOnboarding, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
                self?.panelController?.expand()
            }
        }
        NotificationCenter.default.addObserver(forName: .expandIsland, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.panelController?.expand() }
        }
    }

    // MARK: - Screen lock

    private func observeScreenLock() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                (NSApp.delegate as? AppDelegate)?.model.persist()
            }
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard let self = NSApp.delegate as? AppDelegate else { return }
                self.model.reset()
                self.model.refreshRepository()
                self.panelController?.showCollapsed()
            }
        }
    }

    // MARK: - Hotkey

    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.toggleFromHotKey()
            }
            return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x43444B31), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func toggleFromHotKey() {
        panelController?.toggleExpanded()
    }

    // MARK: - Adaptive discovery (perf: poll fast only when it matters)

    private func startAdaptiveDiscovery() {
        model.pollDiscovery()
        scheduleNextDiscovery(after: 4)
    }

    private func scheduleNextDiscovery(after seconds: TimeInterval) {
        discoveryTimer?.invalidate()
        discoveryTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.model.pollDiscovery()
                // Urgent → 2s, active → 4s, idle → 10s. Idle Macs sip CPU.
                let delay: TimeInterval
                if self.model.urgentCount > 0 { delay = 2 }
                else if !self.model.liveSessions.filter(\.status.isActive).isEmpty { delay = 4 }
                else { delay = 10 }
                self.scheduleNextDiscovery(after: delay)
            }
        }
    }

    private func startEventSocket() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContextDock")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("events.sock").path
        let model = model
        let server = EventSocketServer(
            socketPath: path,
            onEvent: { event in
                Task { @MainActor in model.ingest(event: event) }
            },
            onAudit: { audit in
                Task { @MainActor in model.recordAudit(audit) }
            }
        )
        do {
            try server.start()
            socketServer = server
        } catch {
            model.status = "Socket unavailable: \(error)"
        }
    }
}
