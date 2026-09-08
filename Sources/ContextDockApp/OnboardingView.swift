import ContextDockKit
import SwiftUI

// MARK: - Onboarding: a bespoke first 60 seconds
//
// Four handcrafted beats, each with its own interaction — never a static
// form: touch the miniature island yourself, watch hooks install line by
// line, audition every resident, then fire the demo and watch the REAL
// island grow wings. Relentlessly animated, instantly skippable.

struct OnboardingView: View {
    @Bindable var model: DockModel
    @State private var page = 0
    @State private var hooksInstalled = false
    @State private var demoFired = false
    @State private var previewExpanded = false
    @State private var miniTaps = 0
    @State private var logLines: [String] = []
    @State private var spotlight: AgentKind = .claudeCode
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var heroes: [AgentKind] {
        switch page {
        case 0: return [.claudeCode, .codex, .gemini]
        case 1: return [.opencode, .cursor, .qwen]
        case 2: return [.copilot, .qwen, .claudeCode]
        default: return [.codex, .copilot, .gemini]
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Hero residents march in per page — one shared glass surface,
            // stable per-agent IDs morph them instead of popping.
            PetGlassContainer {
                HStack(spacing: 12) {
                    ForEach(heroes, id: \.rawValue) { kind in
                        Text(PetStore.pet(for: kind, style: model.islandSettings.petStyle).emoji)
                            .font(.system(size: 28))
                            .padding(6)
                            .petGlassTile(id: "hero-\(kind.rawValue)", namespace: glass)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .id("\(page)-\(model.islandSettings.petStyle.rawValue)")
            .frame(height: 40)
            .padding(.top, 12)
            Group {
                switch page {
                case 0: meetIsland
                case 1: zeroConfig
                case 2: residents
                default: testDrive
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)
            Spacer(minLength: 2)
            navRow
        }
        .frame(width: 540, height: 500)
    }

    // MARK: Page 0 — touch it yourself

    private var meetIsland: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: previewExpanded ? 18 : 10, style: .continuous)
                    .fill(.black)
                    .frame(width: previewExpanded ? 400 : 170, height: previewExpanded ? 170 : 32)
                    .shadow(radius: 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: previewExpanded ? 18 : 10, style: .continuous)
                            .strokeBorder(.white.opacity(previewExpanded ? 0.25 : 0), lineWidth: 1)
                    )
                if previewExpanded {
                    HStack(spacing: 8) {
                        Text("🦉").font(.system(size: 28))
                        Text("🐙").font(.system(size: 28))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("2 engines · 1 needs you").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            Text("Hoot is editing middleware.ts").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                            Text("tap the real island ↑ to Jump").font(.system(size: 10)).foregroundStyle(.green)
                        }
                    }
                    .transition(.opacity.combined(with: .scale))
                } else {
                    HStack(spacing: 6) {
                        Text("🦉").font(.system(size: 13))
                        Text("fix auth bug…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(height: 190)
            .contentShape(Rectangle())
            .onTapGesture {
                miniTaps += 1
                withNav { previewExpanded.toggle() }
            }
            .modifier(PopOnChange(value: miniTaps, reduceMotion: reduceMotion))
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Miniature island. Tap to expand or collapse.")
            Text("Your notch is now an island. Go on — tap it.")
                .font(.system(size: 22, weight: .bold))
            Text("It hides inside the camera cutout until it matters, then stretches left and right: engines on the left, their words on the right. The miniature above is alive — the real one is waiting at the top of your screen.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 34)
        }
    }

    // MARK: Page 1 — hooks install in front of you

    private var zeroConfig: some View {
        VStack(spacing: 10) {
            Image(systemName: hooksInstalled ? "checkmark.seal.fill" : "cable.connector")
                .font(.system(size: 40)).foregroundStyle(hooksInstalled ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text("Zero config. Zero cloud.")
                .font(.system(size: 22, weight: .bold))
            Text("Local hooks point Claude Code + Codex at a socket file only you can read. If ContextDock isn't running, hooks exit instantly — your agents never notice.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 34)
            // Live install log: lines type out, or all-at-once with Reduce Motion.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(logLines, id: \.self) { line in
                    Text(line).font(.system(size: 10, design: .monospaced)).foregroundStyle(.green.opacity(0.85))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(minWidth: 420, minHeight: 66, alignment: .leading)
            .padding(10)
            .background(.black.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Button(hooksInstalled ? "✓ Hooks installed" : "Install local hooks") {
                installWithLog()
            }
            .modifier(GlassPrimary())
            .disabled(hooksInstalled)
        }
        .padding(.top, 8)
    }

    private func installWithLog() {
        let lines = ["$ contextdock hooks install",
                     "✓ ~/.claude/settings.json merged (4 events)",
                     "✓ ~/.contextdock/bin senders written (0600 socket)",
                     "✓ fail-open verified — agents unaffected offline"]
        if reduceMotion {
            _ = HookInstaller.installAll()
            logLines = lines
            hooksInstalled = true
            return
        }
        logLines = []
        for (i, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.45) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    logLines.append(line)
                }
                if i == lines.count - 1 {
                    _ = HookInstaller.installAll()
                    hooksInstalled = true
                    DockLog.info("onboarding hooks installed")
                }
            }
        }
    }

    // MARK: Page 2 — audition residents

    private var residents: some View {
        VStack(spacing: 8) {
            // Spotlight card for the tapped resident.
            let pet = PetStore.pet(for: spotlight, style: model.islandSettings.petStyle)
            HStack(spacing: 12) {
                Text(pet.emoji).font(.system(size: 44))
                    .id("\(spotlight.rawValue)-big")
                    .transition(.scale.combined(with: .opacity))
                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(pet.name)” · \(spotlight.displayName)").font(.headline)
                    Text(pet.trait).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 40)
            // Audition row: tap anyone. Interactive glass reacts to the pointer.
            PetGlassContainer {
                HStack(spacing: 10) {
                    ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                spotlight = kind
                            }
                        } label: {
                            Text(PetStore.pet(for: kind, style: model.islandSettings.petStyle).emoji)
                                .font(.system(size: 22))
                                .padding(6)
                                .background(Circle().fill(spotlight == kind ? Color.accentColor.opacity(0.25) : .clear))
                        }
                        .buttonStyle(.plain)
                        .petGlassTile(id: "audition-\(kind.rawValue)", namespace: glass, interactive: true)
                        .help(PetStore.pet(for: kind, style: model.islandSettings.petStyle).name)
                    }
                }
            }
            Picker("", selection: Binding(
                get: { model.islandSettings.petStyle },
                set: { v in model.updateSettings { $0.petStyle = v } })) {
                ForEach(PetStyle.allCases, id: \.rawValue) { s in Text(s.displayName).tag(s) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 50)
            Text(model.islandSettings.petStyle.meaning)
                .font(.callout).foregroundStyle(.secondary)
            Text("Every pack works from day one. Warbound, Abyss, Shadow and Retro celebrate you when earned — see Pets settings.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.top, 6)
        .animation(IslandMotion.resolve(.spring(response: 0.4, dampingFraction: 0.65), reduceMotion: reduceMotion), value: model.islandSettings.petStyle)
    }

    // MARK: Page 3 — fire the demo at the real island

    private var testDrive: some View {
        VStack(spacing: 10) {
            Image(systemName: demoFired ? "checkmark.seal.fill" : "paperplane.fill")
                .font(.system(size: 40)).foregroundStyle(demoFired ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
            Text(demoFired ? "Look up — the island has wings." : "Take it for a spin.")
                .font(.system(size: 22, weight: .bold))
            Text("Fires two demo engines and opens the real island: Claude asks to edit a file, Codex builds beside it. Approve from the notch, then Jump.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                .padding(.horizontal, 34)
            HStack {
                Button(demoFired ? "✓ Demo live in the notch" : "Send demo + open island") {
                    sendDemo()
                    demoFired = true
                    NotificationCenter.default.post(name: .expandIsland, object: nil)
                }
                .disabled(demoFired)
                Button("Finish") { finish() }.modifier(GlassPrimary())
            }
        }
        .padding(.top, 14)
    }

    private var navRow: some View {
        HStack {
            if page > 0 { Button("Back") { withNav { page -= 1 } }.modifier(GlassSecondary()) }
            else { Button("Skip") { finish() }.foregroundStyle(.secondary) }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            if page < 3 { Button("Next") { withNav { page += 1 } }.modifier(GlassPrimary()) }
            else { Button("Done") { finish() }.modifier(GlassPrimary()) }
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func withNav(_ change: () -> Void) {
        if reduceMotion { change() } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { change() }
        }
    }

    private func sendDemo() {
        let c = StableID("demo-claude-onboard")
        let x = StableID("demo-codex-onboard")
        model.ingest(event: AgentEvent(adapter: .claudeCode, sessionID: c, task: "fix auth bug",
                                      summary: "Reviewing middleware.ts", type: .sessionStarted, terminal: "iTerm"))
        model.ingest(event: AgentEvent(adapter: .claudeCode, sessionID: c, summary: "Edit middleware",
                                      filePath: "src/auth/middleware.ts", type: .permissionRequested, terminal: "iTerm",
                                      diffText: "+ if (!token) throw new AuthError('missing')", additions: 3, deletions: 1))
        model.ingest(event: AgentEvent(adapter: .codex, sessionID: x, task: "backend server",
                                      summary: "Building REST endpoints", type: .sessionStarted, terminal: "Ghostty"))
        DockLog.info("onboarding demo fired")
    }

    private func finish() {
        model.updateSettings { $0.onboarded = true }
        NotificationCenter.default.post(name: .closeOnboarding, object: nil)
    }
}

extension Notification.Name {
    static let closeOnboarding = Notification.Name("ContextDockCloseOnboarding")
    static let expandIsland = Notification.Name("ContextDockExpandIsland")
}
