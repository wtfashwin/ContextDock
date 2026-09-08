import AppKit
import ContextDockKit
import SwiftUI

/// True notch-adherent island. One retained panel, two retained content hosts:
/// black collar (collapsed = physical cutout) and refractive surface
/// (expanded). Material owner is AppKit — NSGlassEffectView on macOS 26+,
/// NSVisualEffectView (.behindWindow) below — never stacked SwiftUI materials.
/// Top anchor fixed; growth is down + symmetric sideways.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { allowKey }
    var allowKey = false
}

/// Container reporting hover for debounced open/close. Tracking areas are
/// rebuilt on every resize so the envelope always matches the visual.
final class IslandContainerView: NSView {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// Back-link from SwiftUI value types to their controller without retain cycles
/// or post-init struct mutation: created before super.init, filled after.
final class ControllerBox {
    weak var value: IslandPanelController?
}

@MainActor
final class IslandPanelController: NSObject, NSWindowDelegate {
    private let panel: IslandPanel
    private let container: IslandContainerView
    private let collarHost: NSHostingView<AnyView>
    private let expandedHost: NSHostingView<AnyView>
    private let box = ControllerBox()
    private let model: DockModel
    private var clickOutsideMonitor: Any?
    private var screenChangeObserver: Any?
    private var hoverTask: Task<Void, Never>?
    private var lastScreen: NSScreen?

    private func activeScreen() -> NSScreen? {
        if let s = NSScreen.island { lastScreen = s; return s }
        return lastScreen
    }

    init(model: DockModel) {
        self.model = model
        let screen = NSScreen.island
        lastScreen = screen
        let geo = screen?.notchGeometry ?? NotchGeometry.fallback
        let midX = screen?.frame.midX ?? 735
        let maxY = screen?.frame.maxY ?? 956
        let w = geo.collapsedWidth, h = geo.notchHeight
        panel = IslandPanel(
            contentRect: NSRect(x: midX - w / 2, y: maxY - h, width: w, height: h),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        // Container first (tracking needs it before content lands).
        container = IslandContainerView(frame: panel.contentRect(forFrameRect: panel.frame))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        // Dual retained hosts: created once, visibility toggled, never rebuilt.
        // Collar is opaque black by design (hardware fusion, not glass).
        collarHost = NSHostingView(rootView: AnyView(CollapsedNotch(model: model, box: box)))
        collarHost.autoresizingMask = [.width, .height]
        // Expanded content is transparent: the AppKit material view owns refraction.
        expandedHost = NSHostingView(rootView: AnyView(
            ExpandedWings(model: model, box: box).environment(\.nativeGlassHost, true)
        ))
        expandedHost.autoresizingMask = [.width, .height]

        super.init()
        // .screenSaver is the minimum level that covers the menu bar / notch
        // region (.statusBar renders underneath it). stationary pins Spaces.
        panel.level = .screenSaver
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self

        if #available(macOS 26.0, *),
           !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = IslandTokens.expandedRadius
            glass.autoresizingMask = [.width, .height]
            glass.contentView = expandedHost
            container.addSubview(glass)
            DockLog.info("renderer: NSGlassEffectView.regular")
        } else {
            let vibe = NSVisualEffectView()
            vibe.blendingMode = .behindWindow
            vibe.material = .hudWindow
            vibe.state = .active
            vibe.autoresizingMask = [.width, .height]
            // Manual rounded mask: vibrancy has no cornerRadius API.
            vibe.wantsLayer = true
            vibe.layer?.cornerRadius = IslandTokens.expandedRadius
            vibe.layer?.masksToBounds = true
            vibe.addSubview(expandedHost)
            container.addSubview(vibe)
            DockLog.info("renderer: NSVisualEffectView.hudWindow fallback")
        }
        container.addSubview(collarHost)
        panel.contentView = container
        layoutHosts()
        // Boot state is collapsed: material surface starts hidden, never flashed.
        container.subviews.first?.isHidden = true
        expandedHost.isHidden = true

        // Controller back-link after both hosts exist (views hold weak refs).
        box.value = self

        container.onHover = { [weak self] inside in
            Task { @MainActor in self?.hoverChanged(inside) }
        }
        model.onStateChange = { [weak self] in self?.applyState() }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.repositionToNotch() }
        }
    }

    private func layoutHosts() {
        collarHost.frame = container.bounds
        expandedHost.frame = container.bounds
        container.subviews.first?.frame = container.bounds
    }

    // MARK: - Geometry (top anchor fixed; grow down + sideways)

    var geometry: NotchGeometry { activeScreen()?.notchGeometry ?? .fallback }

    func collapsedFrame() -> NSRect? {
        guard let screen = activeScreen() else { return nil }
        let w = geometry.collapsedWidth, h = geometry.notchHeight
        // x = centerX − w/2, y = topY − h (AppKit screen coords).
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    func expandedFrame() -> NSRect? {
        guard let screen = activeScreen() else { return nil }
        let full = model.liveSessions.count > 2 || model.urgentCount > 0 || model.islandTab == .capture
        let w = geometry.expandedWidth(full: full)
        let h: CGFloat = full ? IslandTokens.expandedFullHeight : IslandTokens.expandedPeekHeight
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    private func place(_ rect: NSRect, shadow: Bool) {
        // Never stack animator transactions (tracked crash class).
        let cur = panel.frame
        guard abs(cur.width - rect.width) > 0.5 || abs(cur.height - rect.height) > 0.5 ||
              abs(cur.minX - rect.minX) > 0.5 || abs(cur.minY - rect.minY) > 0.5 else { return }
        panel.hasShadow = shadow
        let tiny = abs(cur.width - rect.width) < 1 && abs(cur.height - rect.height) < 1
        if tiny {
            panel.setFrame(rect, display: true)
            layoutHosts()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = IslandTokens.morphSeconds
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(rect, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.layoutHosts() }
        }
        DockLog.info("island frame \(Int(rect.width))x\(Int(rect.height)) shadow=\(shadow)")
    }

    private func placeOptional(_ rect: NSRect?, shadow: Bool) {
        guard let rect else { return }
        place(rect, shadow: shadow)
    }

    func repositionToNotch() {
        switch model.panelState {
        case .collapsed, .hidden: placeOptional(collapsedFrame(), shadow: false)
        default: placeOptional(expandedFrame(), shadow: true)
        }
    }

    // MARK: - State (single surface swap; hosts never rebuilt)

    private func showSurface(expanded: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let material = container.subviews.first
        if reduceMotion {
            collarHost.isHidden = expanded
            material?.isHidden = !expanded
            expandedHost.isHidden = !expanded
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                collarHost.animator().alphaValue = expanded ? 0 : 1
                material?.animator().alphaValue = expanded ? 1 : 0
            } completionHandler: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.collarHost.isHidden = expanded
                    material?.isHidden = !expanded
                    self.expandedHost.isHidden = !expanded
                    self.collarHost.alphaValue = 1
                    material?.alphaValue = 1
                }
            }
        }
    }

    func showCollapsed() {
        guard model.panelState != .collapsed else {
            placeOptional(collapsedFrame(), shadow: false)
            return
        }
        hoverTask?.cancel()
        model.panelState = .collapsed
        panel.allowKey = false
        showSurface(expanded: false)
        placeOptional(collapsedFrame(), shadow: false)
        panel.orderFrontRegardless()
        removeClickOutsideMonitor()
    }

    func expand() {
        hoverTask?.cancel()
        model.panelState = model.currentExpandedState()
        if !model.liveSessions.isEmpty && model.panelState == .expandedCapture {
            model.islandTab = .monitor
        }
        panel.allowKey = true
        showSurface(expanded: true)
        placeOptional(expandedFrame(), shadow: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        installClickOutsideMonitor()
    }

    func toggleExpanded() {
        if model.panelState == .collapsed || model.panelState == .hidden { expand() }
        else { showCollapsed() }
    }

    private func applyState() {
        switch model.panelState {
        case .collapsed, .hidden:
            panel.allowKey = false
            showSurface(expanded: false)
            placeOptional(collapsedFrame(), shadow: false)
        default:
            showSurface(expanded: true)
            placeOptional(expandedFrame(), shadow: true)
        }
    }

    // MARK: - Hover debounce (120ms open / 250ms close, stale tasks cancelled)

    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            let delay = inside ? IslandTokens.hoverOpenNs : IslandTokens.hoverCloseNs
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                if inside {
                    if self.model.panelState == .collapsed || self.model.panelState == .hidden {
                        self.expand()
                    }
                } else if !self.panel.isKeyWindow {
                    // Explicit interaction (key window) holds the panel open.
                    if self.model.panelState != .collapsed { self.showCollapsed() }
                }
            }
        }
    }

    // MARK: - Click outside (inside clicks never collapse — the jump fix)

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSMouseInRect(NSEvent.mouseLocation, self.panel.frame, false) { return }
                self.showCollapsed()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if model.panelState != .collapsed { showCollapsed() }
    }
}
