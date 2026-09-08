import SwiftUI

// MARK: - Liquid glass, staged honestly
//
// Two truths drive this file:
// 1. The collapsed notch is hardware — pure black, no glass, like Apple's island.
// 2. Everything expanded is chrome, and chrome on macOS 26 is Liquid Glass:
//    Apple's own .glassEffect refraction shader, staged with a crisp lens
//    line, a breathing state rim, and cursor-tracking light. No sweeps,
//    no waves, no timers pretending to be liquid.
// Every custom layer short-circuits on Reduce Motion / Reduce Transparency.

enum IslandMotion {
    static let morph = Animation.spring(response: 0.36, dampingFraction: 0.9)
    static let wing = Animation.spring(response: 0.5, dampingFraction: 0.82)
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.55)
    static let gentle = Animation.easeInOut(duration: 0.25)
    static func stagger(_ i: Int) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.8).delay(Double(min(i, 8)) * 0.035)
    }
    static func resolve(_ custom: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : custom
    }
}

/// True when SwiftUI renders inside the AppKit material view. Content must
/// then be transparent: the glass owns refraction, never stacked materials.
struct NativeGlassHostKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nativeGlassHost: Bool {
        get { self[NativeGlassHostKey.self] }
        set { self[NativeGlassHostKey.self] = newValue }
    }
}

/// The island shell: black seam collapsed, refractive chrome expanded.
struct GlassShell<Content: View>: View {
    var bottomRadius: CGFloat
    var expanded: Bool
    var vivid: Bool = true
    var edgeTint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nativeGlassHost) private var hosted
    @ViewBuilder var content: Content

    var body: some View {
        Group {
            if hosted {
                // Inside NSGlassEffectView / NSVisualEffectView: transparent
                // content clipped to the material mask. No fills, no stacked
                // materials, no competing corner radii.
                content
                    .clipShape(shape)
                    .overlay(statusRim(shape: shape, tint: edgeTint))
                    .modifier(IslandHoverLight(enabled: vivid))
            } else if #available(macOS 26, *), expanded, !reduceTransparency {
                GlassEffectContainer {
                    content
                        .glassEffect(.regular.tint(.black.opacity(0.22)), in: shape)
                }
                .overlay(lensLine(in: shape))
                .overlay(edgeLight(shape: shape, tint: edgeTint, vivid: vivid))
                .modifier(IslandHoverLight())
            } else {
                content
                    .background(Color.black)
                    .background(
                        LinearGradient(colors: [.white.opacity(expanded ? 0.06 : 0.0), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(.white.opacity(expanded ? 0.12 : 0.0), lineWidth: 0.75))
            }
        }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius, topTrailingRadius: 0,
            style: .continuous
        )
    }

    /// Crisp lens line + pooled top light + floor depth. Static geometry —
    /// the "liquid" read comes from the shader plus your cursor.
    private func lensLine(in shape: UnevenRoundedRectangle) -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 1.5)
                LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
                    .blur(radius: 1)
                Spacer()
            }
            VStack {
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 30)
            }
        }
        .clipShape(shape)
        .allowsHitTesting(false)
    }

    private func edgeLight(shape: UnevenRoundedRectangle, tint: Color?, vivid: Bool) -> some View {
        statusRim(shape: shape, tint: tint)
    }

    /// Static state rim. Value-driven only: brightens the moment the tint
    /// changes, never loops while idle.
    private func statusRim(shape: UnevenRoundedRectangle, tint: Color?) -> some View {
        shape.strokeBorder(
            LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.22 : 0.8),
                                    .white.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: tint == nil ? 0.75 : 1.25
        )
        .allowsHitTesting(false)
    }
}


/// Cursor-tracking liquid light. The glass brightens where you point —
/// Apple's "reacts to pointer in real time", staged by hand.
private struct IslandHoverLight: ViewModifier {
    var enabled: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loc: CGPoint? = nil
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if let loc, enabled, !reduceMotion {
                        RadialGradient(colors: [.white.opacity(0.13), .clear],
                                       center: .center, startRadius: 0, endRadius: 150)
                            .frame(width: 300, height: 210)
                            .position(loc)
                            .allowsHitTesting(false)
                    }
                }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): loc = pt
                case .ended: loc = nil
                }
            }
    }
}

/// Liquid tile for cards + rows. Inside the native host: transparent content
/// plus a hairline — the AppKit material does the refracting.
struct GlassCard: ViewModifier {
    var radius: CGFloat = 14
    var tint: Color = .white
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nativeGlassHost) private var hosted
    func body(content: Content) -> some View {
        Group {
            if hosted {
                content
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(tint.opacity(0.22), lineWidth: 1)
                    )
            } else if #available(macOS 26, *), !reduceTransparency {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.08)), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(cardLens(radius: radius))
            } else {
                content
                    .background(.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            }
        }
    }

    private func cardLens(radius: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 1)
                LinearGradient(colors: [.white.opacity(0.1), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 9)
                Spacer()
            }
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Press squash + hover lift. Every tappable thing gets one.
struct SquashButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6),
                       value: configuration.isPressed)
    }
}

/// Approval burst: capped particles, one TimelineView, strict budget.
struct BurstParticles: View {
    var key: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if key > 0, !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    // Deterministic pseudo-random from key: no state, no timers.
                    Canvas { ctx, size in
                        for i in 0..<18 {
                            let seed = Double((key * 31 + i * 17) % 100) / 100
                            let angle = seed * 2 * .pi + Double(i) * 0.35
                            let age = (t * 0.9 + seed).truncatingRemainder(dividingBy: 1)
                            let r = age * min(size.width, size.height) * 0.45
                            let alpha = max(0, 1 - age)
                            let pt = CGPoint(x: size.width / 2 + cos(angle) * r,
                                             y: size.height / 2 + sin(angle) * r * 0.6)
                            ctx.opacity = alpha * 0.8
                            ctx.fill(Circle().path(in: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                                     with: .color(i % 3 == 0 ? .green : .white))
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

/// Static alert rim for urgent cards. Brightens once when the card appears
/// (value-driven transition at the call site); never loops while idle.
struct UrgentGlow: ViewModifier {
    var color: Color
    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(color.opacity(0.75), lineWidth: 1.25)
            )
    }
}

/// Scale-pop whenever the observed value changes (new event, new session).
struct PopOnChange<V: Equatable>: ViewModifier {
    var value: V
    var reduceMotion: Bool
    @State private var scale: CGFloat = 1
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onChange(of: value) {
                guard !reduceMotion else { return }
                withAnimation(IslandMotion.pop) { scale = 1.25 }
                withAnimation(IslandMotion.pop.delay(0.09)) { scale = 1 }
            }
    }
}

/// Primary action: real glass on Tahoe, prominent bordered below.
struct GlassPrimary: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26, *) {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.borderedProminent)
            }
        }
    }
}
