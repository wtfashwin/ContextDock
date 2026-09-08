import ContextDockKit
import SwiftUI

// MARK: - Official Liquid Glass where SwiftUI owns the surface
//
// Straight from Apple's "Applying Liquid Glass to custom views":
// - `.glassEffect(.regular, in: RoundedRectangle)` — rounded rect because
//   these tiles are larger components that would look odd as capsules.
// - `.interactive()` — Apple's own pointer/touch fluid reactions.
// - `GlassEffectContainer(spacing:)` — one shared surface for performance;
//   spacing (8) stays UNDER item spacing (10+) so tiles never blob together
//   at rest, and only morph deliberately across hierarchy changes.
// - `glassEffectID(_:in:)` — stable per-agent IDs morph the same resident
//   between packs/pages instead of popping.
// The island itself is deliberately excluded: AppKit's NSGlassEffectView
// owns that surface (ADR-007) and materials must never stack.

extension View {
    /// Official glass tile. No-op below macOS 26 (nothing to fall back to —
    /// callers keep their own legible base styling underneath).
    @ViewBuilder
    func petGlassTile(radius: CGFloat = 12, id: String, namespace: Namespace.ID, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .glassEffectID(id, in: namespace)
            } else {
                self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .glassEffectID(id, in: namespace)
            }
        } else {
            self
        }
    }
}

/// Shared refractive surface for a row/grid of pet tiles.
struct PetGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        Group {
            if #available(macOS 26, *) {
                GlassEffectContainer(spacing: 8) { content }
            } else {
                content
            }
        }
    }
}

/// Secondary action: official glass button on Tahoe, bordered below.
struct GlassSecondary: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.buttonStyle(.glass)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}
