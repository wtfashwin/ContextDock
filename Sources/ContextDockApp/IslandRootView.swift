import ContextDockKit
import SwiftUI

/// Root SwiftUI content for the island panel. Attached flush to the top of
/// the screen (Dynamic Island style): square top corners, rounded bottom.
/// Real system material glass that follows the system light/dark theme —
/// no forced colour scheme, no stacked fake layers.
struct IslandRootView: View {
    @Bindable var model: DockModel
    let controller: IslandPanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.panelState == .collapsed || model.panelState == .hidden {
                CollapsedIsland(model: model)
                    .onTapGesture { controller.expand() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("ContextDock island. Activate to expand.")
            } else {
                ExpandedPanel(model: model, controller: controller)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: model.panelState)
    }
}

// MARK: - Glass container

/// Top-attached glass: square top edge, continuous rounded bottom corners.
/// Adapts to the system theme via material + hierarchical foreground styles.
struct IslandGlass<Content: View>: View {
    var bottomRadius: CGFloat = 20
    @ViewBuilder var content: Content

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius, topTrailingRadius: 0,
            style: .continuous
        )
    }

    var body: some View {
        content
            .background(.regularMaterial)
            .background(.background.opacity(0.35))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.primary.opacity(0.02), .primary.opacity(0.14)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )
            )
    }
}

// MARK: - Collapsed

struct CollapsedIsland: View {
    @Bindable var model: DockModel
    var body: some View {
        IslandGlass(bottomRadius: 17) {
            HStack(spacing: 8) {
                statusDot
                Text(model.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if model.activeAgentCount > 0 {
                    ProgressView().controlSize(.mini)
                    Text("\(model.activeAgentCount)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if model.waitingForUser {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.yellow).font(.system(size: 12))
                }
                if model.panelState == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.system(size: 12))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .frame(maxWidth: 260)
    }

    private var statusDot: some View {
        Circle()
            .fill(model.lastError != nil ? .red : model.activeAgentCount > 0 ? .blue : .green)
            .frame(width: 7, height: 7)
    }
}

// MARK: - Expanded

struct ExpandedPanel: View {
    @Bindable var model: DockModel
    let controller: IslandPanelController
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        IslandGlass(bottomRadius: 24) {
            VStack(spacing: 14) {
                header
                Divider()
                content
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(width: 680, height: 460, alignment: .top)
        }
        .onExitCommand { controller.showCollapsed() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(model.repository?.name ?? "No repository", systemImage: "shippingbox")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            if let branch = model.repository?.branch {
                Text(branch).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let bundle = model.contextBundle {
                Text("confidence \(Int(bundle.confidence * 100))%")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                controller.showCollapsed()
            } label: {
                Image(systemName: "chevron.up.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Collapse panel")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.panelState {
        case .expandedCapture:
            captureView
        case .thinking:
            VStack(spacing: 12) {
                ProgressView()
                Text("Matching context…").foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .planChoices:
            if let plans = model.planSet { PlanChoicesView(model: model, plans: plans) }
        case .checklist, .agentRunning, .waitingForUser, .completed:
            ChecklistView(model: model)
        case .error:
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title)
                Text(model.lastError ?? "Unknown error").foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Button("Start over") { model.reset() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            captureView
        }
    }

    private var captureView: some View {
        VStack(spacing: 16) {
            Spacer()
            TextField("What are you working on?", text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .lineLimit(1...5)
                .padding(14)
                .background(.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($inputFocused)
                .onSubmit { model.think(input: input) }
                .onAppear { inputFocused = true }
            HStack {
                if !model.activeLessons.isEmpty {
                    Label("\(model.activeLessons.count) learned preferences active", systemImage: "brain")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .help(model.activeLessons.joined(separator: "\n"))
                }
                Spacer()
                Button("Think") { model.think(input: input) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Spacer()
        }
        .padding(.horizontal, 30)
    }
}

// MARK: - Plan cards

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
                                    Text("— \(match.reason)").font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                } label: {
                    Text("Sources used (\(bundle.matches.count)) · \(bundle.explanation)")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(plans.options.enumerated()), id: \.element.id) { index, option in
                    PlanCard(
                        option: option,
                        isRecommended: option.id == plans.recommendedID,
                        shortcut: index + 1
                    ) {
                        model.select(plan: option)
                    }
                }
            }
            HStack {
                Button("Three new options") { model.regeneratePlans() }
                    .font(.system(size: 11))
                Spacer()
                Text("Press 1, 2, or 3 to choose")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
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
                HStack {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                }
                if isRecommended {
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.green.opacity(0.9)))
                }
                Text(option.resultLine)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(3)
                LabeledRow(label: "Size", value: option.workSize.rawValue)
                LabeledRow(label: "Benefit", value: option.benefit)
                LabeledRow(label: "Risk", value: option.risk)
                Spacer(minLength: 0)
                Text("Press \(shortcut)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(.primary.opacity(hovering ? 0.1 : isRecommended ? 0.08 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isRecommended ? .green.opacity(0.5) : .primary.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isRecommended ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character("\(shortcut)")), modifiers: [])
        .accessibilityLabel("\(isRecommended ? "Recommended plan" : "Plan"): \(option.title). \(option.resultLine)")
    }
}

struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(label + ":").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

// MARK: - Checklist

struct ChecklistView: View {
    @Bindable var model: DockModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let checklist = model.checklist {
                Text(checklist.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(checklist.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: item.status))
                                    .foregroundStyle(color(for: item.status))
                                Text(item.action)
                                    .font(.system(size: 12))
                                    .foregroundStyle(item.status == .completed ? .secondary : .primary)
                                    .strikethrough(item.status == .completed)
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if model.panelState == .checklist {
                    HStack(spacing: 10) {
                        Text("Send to:").font(.system(size: 12)).foregroundStyle(.secondary)
                        agentButton(.claudeCode, title: "Claude Code")
                        agentButton(.codex, title: "Codex")
                        Button("Demo agent") { model.dispatch(kind: .fake) }
                        Spacer()
                        Button("Open note") { model.openObsidianNote() }.font(.system(size: 11))
                    }
                }
                if model.panelState == .agentRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Agent running…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if model.panelState == .completed {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Completed").foregroundStyle(.primary)
                        Spacer()
                        Button("New capture") { model.reset() }
                    }
                }
            }
        }
    }

    /// Learned preferred agent gets the prominent style — the self-learning
    /// loop made visible.
    @ViewBuilder private func agentButton(_ kind: AgentKind, title: String) -> some View {
        if model.preferredAgent == kind {
            Button("\(title) ★") { model.dispatch(kind: kind) }
                .buttonStyle(.borderedProminent)
                .help("Learned preference: this agent has worked well here")
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
        default: .secondary.opacity(0.6)
        }
    }
}
