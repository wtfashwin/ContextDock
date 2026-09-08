import AppKit
import ContextDockKit

// MARK: - Native glass probe (isolated smoke test)
//
// Hierarchy per spec: NSPanel (nonopaque, clear) → NSGlassEffectView.regular
// → contentView. No notch geometry, no animation, no session data, no @main.
// Open from the Debug menu; retained by AppDelegate while visible.
// Verdict log: 2026-09-07, SDK 26.5, runtime macOS 26.6.2 — refracts live
// desktop behind the panel; .regular is intentionally subdued. PASS.

@available(macOS 26.0, *)
@MainActor
final class ContextDockGlassProbeController: NSWindowController {
    init() {
        let bounds = NSRect(x: 0, y: 0, width: 440, height: 168)
        let panel = NSPanel(
            contentRect: bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.alphaValue = 1
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let content = NSView(frame: bounds)
        let title = NSTextField(labelWithString: "ContextDock · Native glass probe")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .labelColor

        let claude = NSTextField(labelWithString: "Demo · Claude — Running")
        let codex = NSTextField(labelWithString: "Demo · Codex — Waiting for input")
        let explanation = NSTextField(
            labelWithString: "Move a colorful window behind this panel."
        )
        explanation.font = .systemFont(ofSize: 12)
        explanation.textColor = .secondaryLabelColor

        let labels = [title, claude, codex, explanation]
        for label in labels {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20)
            ])
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            claude.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            codex.topAnchor.constraint(equalTo: claude.bottomAnchor, constant: 8),
            explanation.topAnchor.constraint(equalTo: codex.bottomAnchor, constant: 12),
            explanation.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -16)
        ])

        let glass = NSGlassEffectView(frame: bounds)
        glass.style = .regular
        glass.cornerRadius = 24
        // Content belongs INSIDE the glass. Never siblings.
        glass.contentView = content
        panel.contentView = glass

        super.init(window: panel)
        panel.center()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func present() {
        window?.orderFrontRegardless()
        DockLog.info("glass probe presented")
    }
}
