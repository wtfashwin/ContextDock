import ContextDockKit
import SwiftUI

/// Root SwiftUI content for the island panel. Dark glass, centre focus,
/// details only on demand. Uses system Material as the glass base — a real
/// native material, not stacked fake layers. (glassEffect adoption is gated
/// behind availability when building with an SDK that provides it.)
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

struct GlassCapsule<Content: View>: View {
    var cornerRadius: CGFloat = 17
    @ViewBuilder var content: Content
    var body: some View {
        content
            .background(.black.opacity(0.55))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
            )
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Collapsed

struct CollapsedIsland: View {
    @Bindable var model: DockModel
    var body: some View {
        GlassCapsule {
            HStack(spacing: 8) {
                statusDot
                Text(model.status)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                if model.activeAgentCount > 0 {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("\(model.activeAgentCount)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
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
        GlassCapsule(cornerRadius: 22) {
            VStack(spacing: 14) {
                header
                Divider().overlay(.white.opacity(0.08))
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
                .foregroundStyle(.white.opacity(0.8))
            if let branch = model.repository?.branch {
                Text(branch).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if let bundle = model.contextBundle {
                Text("confidence \(Int(bundle.confidence * 100))%")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button {
                controller.showCollapsed()
            } label: {
                Image(systemName: "chevron.up.circle.fill")
                    .foregroundStyle(.white.opacity(0.5))
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
                ProgressView().tint(.white)
                Text("Matching context…").foregroundStyle(.white.opacity(0.7))
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .planChoices:
            if let plans = model.planSet { PlanChoicesView(model: model, plans: plans) }
        case .checklist, .agentRunning, .waitingForUser, .completed:
            ChecklistView(model: model)
        case .error:
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title)
                Text(model.lastError ?? "Unknown error").foregroundStyle(.white.opacity(0.8))
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
                .foregroundStyle(.white)
                .lineLimit(1...5)
                .padding(14)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .focused($inputFocused)
                .onSubmit { model.think(input: input) }
                .onAppear { inputFocused = true }
            HStack {
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
    @State private var showExplanation = false

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
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90)
                } label: {
                    Text("Sources used (\(bundle.matches.count)) · \(bundle.explanation)")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.8))
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
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
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
                        .foregroundStyle(.white)
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
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    .lineLimit(3)
                LabeledRow(label: "Size", value: option.workSize.rawValue)
                LabeledRow(label: "Benefit", value: option.benefit)
                LabeledRow(label: "Risk", value: option.risk)
                Spacer(minLength: 0)
                Text("Press \(shortcut)")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(.white.opacity(hovering ? 0.1 : isRecommended ? 0.08 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isRecommended ? .green.opacity(0.5) : .white.opacity(0.1), lineWidth: 1)
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
            Text(label + ":").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(2)
        }
    }
}

// MARK: - Checklist

struct ChecklistView: View {
    @Bindable var model: DockModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let checklist = model.checklist {
                Text(checklist.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(checklist.items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: icon(for: item.status))
                                    .foregroundStyle(color(for: item.status))
                                Text(item.action)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(item.status == .completed ? 0.5 : 0.9))
                                    .strikethrough(item.status == .completed)
                                Spacer()
                                Text(item.status.rawValue)
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    }
                }
                if model.panelState == .checklist {
                    HStack(spacing: 10) {
                        Text("Send to:").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        Button("Demo agent") { model.dispatch(kind: .fake) }
                        Button("Claude Code") { model.dispatch(kind: .claudeCode) }
                        Button("Codex") { model.dispatch(kind: .codex) }
                        Spacer()
                        Button("Open note") { model.openObsidianNote() }.font(.system(size: 11))
                    }
                }
                if model.panelState == .agentRunning {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Agent running…").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                if model.panelState == .completed {
                    HStack {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Completed").foregroundStyle(.white)
                        Spacer()
                        Button("New capture") { model.reset() }
                    }
                }
            }
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
