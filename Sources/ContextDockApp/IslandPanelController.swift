import AppKit
import ContextDockKit
import SwiftUI

/// Non-activating floating NSPanel pinned to the top centre of the active display.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { allowKey }
    var allowKey = false
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private let panel: IslandPanel
    private let model: DockModel
    private var clickOutsideMonitor: Any?

    static let collapsedSize = NSSize(width: 260, height: 34)
    static let expandedSize = NSSize(width: 680, height: 460)

    init(model: DockModel) {
        self.model = model
        panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.delegate = self

        let root = IslandRootView(model: model, controller: self)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting

        model.onStateChange = { [weak self] in self?.applyState() }
    }

    // MARK: - Placement

    private func targetScreen() -> NSScreen {
        // Active display: the screen with the key window, else the mouse, else main.
        if let key = NSApp.keyWindow?.screen { return key }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func place(size: NSSize) {
        let screen = targetScreen()
        // Flush to the very top of the screen (over the menu-bar region),
        // Dynamic Island style — the panel level already sits above the bar.
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true, animate: panel.isVisible)
    }

    // MARK: - State

    func showCollapsed() {
        model.panelState = .collapsed
        panel.allowKey = false
        place(size: Self.collapsedSize)
        panel.orderFrontRegardless()
        removeClickOutsideMonitor()
    }

    func expand() {
        model.panelState = model.currentExpandedState()
        panel.allowKey = true
        place(size: Self.expandedSize)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickOutsideMonitor()
    }

    func toggleExpanded() {
        if model.panelState == .collapsed || model.panelState == .hidden {
            expand()
        } else {
            showCollapsed()
        }
    }

    private func applyState() {
        switch model.panelState {
        case .collapsed, .hidden:
            place(size: Self.collapsedSize)
            panel.allowKey = false
        default:
            place(size: Self.expandedSize)
        }
    }

    // MARK: - Click outside / Escape

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.showCollapsed() }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Collapsing on focus loss keeps the island out of the way.
        if model.panelState != .collapsed { showCollapsed() }
    }
}
