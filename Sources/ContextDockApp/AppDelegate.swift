import AppKit
import Carbon.HIToolbox
import ContextDockKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: IslandPanelController?
    private var hotKeyRef: EventHotKeyRef?
    private let model = DockModel()
    private var socketServer: EventSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = IslandPanelController(model: model)
        panelController = controller
        controller.showCollapsed()
        registerGlobalHotKey()
        startEventSocket()
        observeScreenLock()
        model.bootstrap()
    }

    /// Fresh start after every screen lock: persist on lock, re-detect the
    /// active repository and reset the island on unlock.
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

    func applicationWillTerminate(_ notification: Notification) {
        socketServer?.stop()
        model.persist()
    }

    // Option+Space via Carbon RegisterEventHotKey (documented API, no
    // Accessibility permission needed).
    private func registerGlobalHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.toggleFromHotKey()
            }
            return noErr
        }, 1, &eventType, nil, nil)
        let hotKeyID = EventHotKeyID(signature: OSType(0x43444B31), id: 1)  // 'CDK1'
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func toggleFromHotKey() {
        panelController?.toggleExpanded()
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
