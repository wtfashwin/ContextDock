import ContextDockKit
import SwiftUI

// MARK: - Agent color

func agentColor(_ kind: AgentKind) -> Color {
    switch kind {
    case .claudeCode: .orange
    case .codex, .codexCLI: .green
    case .gemini: .blue
    case .cursor: .purple
    case .opencode: .white
    case .qwen: .pink
    case .copilot: .cyan
    case .fake: .gray
    }
}

func statusColor(_ s: LiveStatus) -> Color {
    switch s {
    case .working: .blue
    case .waiting, .asking: .yellow
    case .needsApproval: .orange
    case .done: .green
    case .failed: .red
    }
}

// MARK: - Collapsed: the notch itself (pets LEFT, snippet RIGHT)

struct CollapsedNotch: View {
    @Bindable var model: DockModel
    let box: ControllerBox
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassShell(bottomRadius: NotchGeometry.bottomRadius, expanded: false) {
            HStack(spacing: 7) {
                petCluster
                    .modifier(PopOnChange(value: model.liveSessions.count, reduceMotion: reduceMotion))
                if model.waitingForUser {
                    Circle().fill(.yellow).frame(width: 6, height: 6)
                        .modifier(Pulse(modifierReduceMotion: reduceMotion))
                } else if model.activeAgentCount > 0 {
                    Circle().fill(.blue).frame(width: 6, height: 6)
                        .modifier(Pulse(modifierReduceMotion: reduceMotion))
                }
                Text(ticker)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onTapGesture { model.registerTap(); box.value?.expand() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("ContextDock. \(model.usageLine). Activate to expand.")
    }

    private var ticker: String {
        if let q = model.eggQuote { return q }
        if model.liveSessions.isEmpty { return model.repository?.name ?? "Dock" }
        return model.tickerSnippet
    }

    private var petCluster: some View {
        let pets = Array(model.pets().prefix(3))
        return Group {
            if pets.isEmpty {
                Text("◍").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                HStack(spacing: -5) {
                    ForEach(pets, id: \.session.id) { entry in
                        ZStack(alignment: .bottomTrailing) {
                            Text(entry.pet.emoji)
                                .font(.system(size: 13))
                                .frame(width: 19, height: 19)
                                .background(Circle().fill(.white.opacity(0.08)))
                                .overlay(Circle().stroke(agentColor(entry.session.agent).opacity(0.8), lineWidth: 1))
                            Circle().fill(statusColor(entry.session.status))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
        }
    }
}

/// Gentle status pulse; static when Reduce Motion is on.
struct Pulse: ViewModifier {
    var modifierReduceMotion: Bool
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(modifierReduceMotion ? 1 : (on ? 0.4 : 1))
            .onAppear { if !modifierReduceMotion { withAnimation(.easeInOut(duration: 1.1).repeatForever()) { on = true } } }
    }
}

// MARK: - Expanded wings

struct ExpandedWings: View {
    @Bindable var model: DockModel
    let box: ControllerBox
    @State private var input = ""
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sessions: [LiveSession] { model.sortedSessions }
    private var selected: LiveSession? {
        sessions.first(where: { $0.id == model.selectedSessionID }) ?? sessions.first
    }

    var body: some View {
        GlassShell(bottomRadius: 22, expanded: true,
                   vivid: model.islandSettings.glassVivid,
                   edgeTint: model.midnightMode ? .indigo : (model.urgentCount > 0 ? .orange : nil)) {
            VStack(spacing: 0) {
                notchBar
                if model.partyMode {
                    partyStrip
                } else if model.islandTab == .monitor && !sessions.isEmpty {
                    ScrollView { wings }
                } else {
                    captureFlow
                }
                bottomBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .foregroundStyle(.white)
        }
        .onExitCommand { box.value?.showCollapsed() }
    }

    // Top strip: still reads as notch — pets left, status right.
    private var notchBar: some View {
        HStack(spacing: 8) {
            if model.midnightMode {
                Text("🌙").font(.system(size: 13)).help("Midnight watch — the abyss nods back")
            }
            HStack(spacing: -5) {
                ForEach(Array(model.pets().prefix(4)), id: \.session.id) { entry in
                    Text(entry.pet.emoji).font(.system(size: 14))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.07)))
                        .overlay(Circle().stroke(agentColor(entry.session.agent).opacity(0.7), lineWidth: 1))
                }
            }
            Text(model.usageLine)
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer()
            Picker("", selection: $model.islandTab) {
                Text("Monitor").tag(DockModel.IslandTab.monitor)
                Text("Capture").tag(DockModel.IslandTab.capture)
            }
            .pickerStyle(.segmented).frame(width: 170)
            Button { NotificationCenter.default.post(name: .openSettings, object: nil) } label: {
                Image(systemName: "gearshape.fill").foregroundStyle(.white.opacity(0.55))
            }.buttonStyle(.plain).help("Settings (⌘,)")
            Button { box.value?.showCollapsed() } label: {
                Image(systemName: "chevron.up.circle.fill").foregroundStyle(.white.opacity(0.55))
            }.buttonStyle(.plain).keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // LEFT wing: engines/pets. RIGHT wing: snippets/activity.
    private var wings: some View {
        VStack(spacing: 8) {
            if let insight = model.activeInsight {
                InsightCard(model: model, insight: insight)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(sessions.filter { $0.permission != nil }, id: \.id) { s in
                PermissionCard(model: model, session: s)
                    .modifier(UrgentGlow(color: .orange))
            }
            ForEach(sessions.filter { $0.question != nil && $0.status == .asking }, id: \.id) { s in
                QuestionCard(model: model, session: s)
                    .modifier(UrgentGlow(color: .yellow))
            }
            HStack(alignment: .top, spacing: 10) {
                // LEFT: engine roster
                VStack(alignment: .leading, spacing: 6) {
                    Text("ENGINES").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        EngineRow(model: model, session: s, selected: selected?.id == s.id)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .animation(IslandMotion.resolve(IslandMotion.stagger(i), reduceMotion: reduceMotion), value: sessions.count)
                    }
                }
                .frame(width: 190, alignment: .leading)
                Divider().background(.white.opacity(0.1))
                // RIGHT: snippets for the selected engine
                if let s = selected {
                    SnippetPane(model: model, session: s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(s.id)
                        .transition(.opacity)
                }
            }
        }
        .padding(12)
        .overlay(BurstParticles(key: model.celebrationKey))
        .animation(IslandMotion.resolve(IslandMotion.wing, reduceMotion: reduceMotion), value: model.activeInsight == nil)
    }

    private var partyStrip: some View {
        VStack(spacing: 6) {
            Text("🎉 PARTY MODE — everything shipping, nothing blocked").font(.system(size: 12, weight: .bold))
            HStack(spacing: 8) {
                ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                    Text(PetStore.pet(for: kind, style: model.islandSettings.petStyle).emoji)
                        .font(.system(size: 22))
                }
            }
            Text("The parade also unlocks the Retro pet pack. Type “party” anytime to march again.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            Button("Calm down") { model.partyMode = false }.font(.system(size: 11))
        }
        .padding(14)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Label("Monitor", systemImage: "eye.fill")
            Label("Approve", systemImage: "checkmark.seal.fill")
            Label("Ask", systemImage: "questionmark.bubble.fill")
            Label("Jump", systemImage: "arrow.up.right.square.fill")
            Spacer()
            Text("click an engine → Jump lands its terminal").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.45))
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    // MARK: Capture flow (kept, black restyle)

    @ViewBuilder private var captureFlow: some View {
        switch model.panelState {
        case .thinking:
            VStack(spacing: 12) {
                Spacer(); ProgressView().tint(.white)
                Text("Matching context…").foregroundStyle(.white.opacity(0.6))
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .planChoices:
            if let plans = model.planSet {
                ScrollView { PlanChoicesView(model: model, plans: plans).padding(14) }
            }
        case .checklist, .agentRunning, .waitingForUser, .completed:
            ScrollView { ChecklistView(model: model).padding(14) }
        case .error:
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title)
                Text(model.lastError ?? "Unknown error").foregroundStyle(.white).multilineTextAlignment(.center)
                Button("Start over") { model.reset() }
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            captureView
        }
    }

    private var captureView: some View {
        VStack(spacing: 14) {
            Spacer()
            TextField("What are you working on? (try “party” 🎉)", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .lineLimit(1...4)
                .padding(13)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($inputFocused)
                .onSubmit { model.checkPartyCode(input); model.think(input: input) }
                .onAppear { inputFocused = true }
            HStack {
                if !model.activeLessons.isEmpty {
                    Label("\(model.activeLessons.count) preferences active", systemImage: "brain")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button("Think ⌘↵") { model.checkPartyCode(input); model.think(input: input) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding(.horizontal, 26)
    }
}

// MARK: - LEFT wing row: pet + engine + status, tap selects, double-tap jumps

struct EngineRow: View {
    @Bindable var model: DockModel
    let session: LiveSession
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            model.selectedSessionID = session.id
        } label: {
            HStack(spacing: 8) {
                Text(PetStore.pet(for: session.agent, style: model.islandSettings.petStyle).emoji)
                    .font(.system(size: 17))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(agentColor(session.agent).opacity(0.16)))
                    .overlay(Circle().stroke(selected ? agentColor(session.agent) : agentColor(session.agent).opacity(0.4), lineWidth: selected ? 2 : 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.agent.displayName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text("\(session.terminal) · \(session.elapsed)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer()
                Circle().fill(statusColor(session.status)).frame(width: 7, height: 7)
            }
            .padding(7)
            .modifier(GlassCard(radius: 10, tint: selected ? agentColor(session.agent) : .white))
            .brightness(hovering && !selected ? 0.08 : 0)
        }
        .buttonStyle(SquashButtonStyle())
        .onHover { hovering = $0 }
        .help("\(session.task) — click to preview, Jump for terminal")
        .accessibilityLabel("\(session.agent.displayName): \(session.task), \(session.status.rawValue)")
        .onTapGesture(count: 2) { model.jump(to: session) }
    }
}

// MARK: - RIGHT wing: snippets + Jump

struct SnippetPane: View {
    @Bindable var model: DockModel
    let session: LiveSession
    @State private var hoveringJump = false

    /// Exact landing address, so Jump never feels random.
    private func jumpHelp(for s: LiveSession) -> String {
        if let t = s.tmuxTarget { return "Focus tmux pane \(t) in \(s.terminal)" }
        if s.terminal == "iTerm", let tty = s.tty { return "Focus iTerm tab on \(tty)" }
        if let pid = s.pid { return "Focus \(s.terminal) running pid \(pid)" }
        return "Focus \(s.terminal)"
    }

    private func glassJumpFill(for s: LiveSession) -> some View {
        Group {
            if #available(macOS 26, *) {
                Capsule().fill(hoveringJump ? .white : agentColor(s.agent))
                    .glassEffect(.regular.tint(agentColor(s.agent).opacity(0.25)), in: Capsule())
            } else {
                Capsule().fill(hoveringJump ? .white : agentColor(s.agent))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SNIPPETS — \(session.agent.displayName.uppercased())").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.35))
            Text(session.task.isEmpty ? session.agent.displayName : session.task)
                .font(.system(size: 14, weight: .semibold)).lineLimit(2)
            Text(session.lastActivity)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7)).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.islandSettings.showSnippets && !session.log.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(session.log.suffix(4), id: \.text) { line in
                        HStack(spacing: 6) {
                            Text("└──").foregroundStyle(.white.opacity(0.25))
                            Text(line.text).lineLimit(1)
                            if let d = line.detail { Text(d).foregroundStyle(.white.opacity(0.35)).lineLimit(1) }
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    model.jump(to: session)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("Jump to \(session.terminal)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(glassJumpFill(for: session))
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
                }
                .buttonStyle(SquashButtonStyle())
                .onHover { hoveringJump = $0 }
                .help(jumpHelp(for: session))
                .accessibilityLabel("Jump to \(session.terminal)")
                if session.status == .done {
                    Text("Done — click to jump").font(.system(size: 11)).foregroundStyle(.green)
                } else if session.status.isUrgent {
                    Text("Needs you").font(.system(size: 11, weight: .bold)).foregroundStyle(.orange)
                }
            }
        }
        .padding(10)
        .modifier(GlassCard(radius: 14))
    }
}

struct StatusPill: View {
    let status: LiveStatus
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor(status)).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(statusColor(status).opacity(0.25)))
    }
    private var label: String {
        switch status {
        case .working: return "working"
        case .waiting: return "waiting"
        case .needsApproval: return "needs approval"
        case .asking: return "asking"
        case .done: return "done"
        case .failed: return "failed"
        }
    }
}

// MARK: - Pattern insight (the 5th decision: noticed, never automated)

struct InsightCard: View {
    @Bindable var model: DockModel
    let insight: PatternInsight
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "brain.fill").foregroundStyle(.cyan)
                Text("Noticed a pattern").font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(Int(insight.confidence * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            }
            Text(insight.title).font(.system(size: 13, weight: .semibold))
            Text(insight.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(4)
            Text("Nothing was changed or automated — your call.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            HStack {
                Button("Keep asking me") { model.dismissInsight(remember: true) }
                Spacer()
                Button("Show me next time") { model.dismissInsight(remember: false) }
            }
            .font(.system(size: 11))
        }
        .padding(11)
        .modifier(GlassCard(radius: 14, tint: .cyan))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.cyan.opacity(0.4), lineWidth: 1))
        .accessibilityLabel("Pattern insight: \(insight.title). \(insight.detail)")
    }
}

// MARK: - Permission / Question cards (full-width, above wings)

struct PermissionCard: View {
    @Bindable var model: DockModel
    let session: LiveSession
    var body: some View {
        if let p = session.permission {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Permission Request").font(.system(size: 12, weight: .bold))
                    Spacer()
                    StatusPill(status: session.status)
                }
                Text("\(p.toolName ?? "Edit") · \(p.filePath)")
                    .font(.system(size: 12, design: .monospaced)).lineLimit(2)
                if !p.diffText.isEmpty {
                    Text(p.diffText).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7)).lineLimit(4)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button("Deny ⌘N") { model.deny(sessionID: session.id) }
                        .keyboardShortcut("n", modifiers: .command)
                    Spacer()
                    Button("Jump") { model.jump(to: session) }
                    Button("Allow ⌘Y") { model.approve(sessionID: session.id) }
                        .keyboardShortcut("y", modifiers: .command)
                        .modifier(GlassPrimary())
                }
            }
            .padding(11)
            .modifier(GlassCard(radius: 14, tint: .orange))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.orange.opacity(0.45), lineWidth: 1))
        }
    }
}

struct QuestionCard: View {
    @Bindable var model: DockModel
    let session: LiveSession
    var body: some View {
        if let q = session.question {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "questionmark.bubble.fill").foregroundStyle(.yellow)
                    Text("\(session.agent.displayName) asks").font(.system(size: 12, weight: .bold))
                }
                Text(q.question).font(.system(size: 13)).lineLimit(3)
                HStack(spacing: 8) {
                    ForEach(Array(q.options.enumerated()), id: \.offset) { idx, opt in
                        Button("⌘\(idx + 1) \(opt)") { model.answer(sessionID: session.id, option: opt) }
                            .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: .command)
                    }
                    Spacer()
                    Button("Jump") { model.jump(to: session) }
                }
            }
            .padding(11)
            .modifier(GlassCard(radius: 14, tint: .yellow))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.yellow.opacity(0.4), lineWidth: 1))
        }
    }
}

// MARK: - Plan cards + checklist (black restyle, kept behavior)

struct PlanChoicesView: View {
    @Bindable var model: DockModel
    let plans: PlanSet
    var body: some View {
        VStack(spacing: 12) {
            if let bundle = model.contextBundle, !bundle.matches.isEmpty {
                DisclosureGroup(isExpanded: $model.showSources) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(bundle.matches, id: \.node.id) { match in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(match.node.title).font(.system(size: 11, weight: .medium))
                                    Text("— \(match.reason)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                } label: {
                    Text("Sources used (\(bundle.matches.count)) · \(bundle.explanation)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(plans.options.enumerated()), id: \.element.id) { index, option in
                    PlanCard(option: option, isRecommended: option.id == plans.recommendedID, shortcut: index + 1) {
                        model.select(plan: option)
                    }
                }
            }
            HStack {
                Button("Three new options") { model.regeneratePlans() }.font(.system(size: 11))
                Spacer()
                Text("Press 1, 2, or 3").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

struct PlanCard: View {
    let option: PlanOption
    let isRecommended: Bool
    let shortcut: Int
    let onSelect: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                Text(option.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                if isRecommended {
                    Text("RECOMMENDED").font(.system(size: 9, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.9)))
                }
                Text(option.resultLine).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(3)
                LabeledRow(label: "Size", value: option.workSize.rawValue)
                LabeledRow(label: "Benefit", value: option.benefit)
                LabeledRow(label: "Risk", value: option.risk)
                Spacer(minLength: 0)
                Text("Press \(shortcut)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            .background(.white.opacity(hovering ? 0.12 : isRecommended ? 0.09 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isRecommended ? .green.opacity(0.5) : .white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(shortcut)")), modifiers: [])
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            Text(value).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
        }
    }
}

struct ChecklistView: View {
    @Bindable var model: DockModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let checklist = model.checklist {
                Text(checklist.title).font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(checklist.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: item.status)).foregroundStyle(color(for: item.status))
                            Text(item.action).font(.system(size: 12))
                                .foregroundStyle(item.status == .completed ? .white.opacity(0.5) : .white)
                                .strikethrough(item.status == .completed)
                            Spacer()
                            Text(item.status.rawValue).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                if model.panelState == .checklist {
                    HStack(spacing: 10) {
                        Text("Send to:").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        agentButton(.claudeCode, title: "Claude Code")
                        agentButton(.codex, title: "Codex")
                        Button("Demo agent") { model.dispatch(kind: .fake) }
                        Spacer()
                        Button("Open note") { model.openObsidianNote() }.font(.system(size: 11))
                    }
                }
                if model.panelState == .agentRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Agent running…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    }
                }
                if model.panelState == .completed {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Completed")
                        Spacer()
                        Button("New capture") { model.reset() }
                    }
                }
            }
        }
    }
    @ViewBuilder private func agentButton(_ kind: AgentKind, title: String) -> some View {
        if model.preferredAgent == kind {
            Button("\(title) ★") { model.dispatch(kind: kind) }.modifier(GlassPrimary())
        } else {
            Button(title) { model.dispatch(kind: kind) }
        }
    }
    private func icon(for status: ChecklistItemStatus) -> String {
        switch status {
        case .completed: "checkmark.circle.fill"
        case .running: "circle.dotted.circle"
        case .failed: "xmark.circle.fill"
        case .waiting, .needsApproval: "questionmark.circle"
        case .blocked: "hand.raised.circle"
        default: "circle"
        }
    }
    private func color(for status: ChecklistItemStatus) -> Color {
        switch status {
        case .completed: .green
        case .running: .blue
        case .failed: .red
        case .waiting, .needsApproval: .yellow
        case .blocked: .orange
        default: .white.opacity(0.4)
        }
    }
}

extension Notification.Name {
    static let openSettings = Notification.Name("ContextDockOpenSettings")
}
