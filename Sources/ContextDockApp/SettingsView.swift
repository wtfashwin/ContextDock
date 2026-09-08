import ContextDockKit
import ServiceManagement
import SwiftUI

// MARK: - Settings: General / Pets / Eggs / Advanced
//
// Every playful thing explains itself: what it is, why it exists,
// how to earn it. No mystery checkboxes.

struct SettingsView: View {
    @Bindable var model: DockModel

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(0)
            pets.tabItem { Label("Pets", systemImage: "pawprint.fill") }.tag(1)
            eggs.tabItem { Label("Easter Eggs", systemImage: "gift.fill") }.tag(2)
            advanced.tabItem { Label("Advanced", systemImage: "wrench.fill") }.tag(3)
        }
        .frame(width: 500, height: 400)
    }

    private var general: some View {
        Form {
            Toggle("Sound alerts", isOn: Binding(
                get: { model.islandSettings.soundsEnabled },
                set: { v in model.updateSettings { $0.soundsEnabled = v } }))
            Toggle("Show text snippets in right wing", isOn: Binding(
                get: { model.islandSettings.showSnippets },
                set: { v in model.updateSettings { $0.showSnippets = v } }))
            Toggle("Vivid liquid glass", isOn: Binding(
                get: { model.islandSettings.glassVivid },
                set: { v in model.updateSettings { $0.glassVivid = v } }))
            .help("Specular streaks, lensing rim, animated sheen. Off = quiet matte black.")
            Toggle("Launch at login", isOn: Binding(
                get: { model.islandSettings.launchAtLogin },
                set: { v in model.updateSettings { $0.launchAtLogin = v }; setLoginItem(enabled: v) }))
            .help("Registers ContextDock as a login item (SMAppService).")
            Text("Global hotkey: ⌥Space · Jump: click any engine · Approve: ⌘Y · Deny: ⌘N")
                .font(.callout).foregroundStyle(.secondary)
            Text("You so far: \(model.islandSettings.approvalsGiven) approvals · \(model.islandSettings.questionsAnswered) answers · \(model.islandSettings.jumpsMade) jumps.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var pets: some View {
        VStack(spacing: 10) {
            Picker("Style", selection: Binding(
                get: { model.islandSettings.petStyle },
                set: { v in model.updateSettings { $0.petStyle = v } })) {
                ForEach(PetStyle.allCases, id: \.rawValue) { s in Text(s.displayName).tag(s) }
            }
            .pickerStyle(.segmented).padding(.horizontal, 16)
            let st = model.islandSettings.petStyle
            let lock = PetStore.unlocked(st, settings: model.islandSettings)
            Text(lock.open ? st.meaning : "\(st.meaning) \(lock.hint)")
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(AgentKind.allCases, id: \.rawValue) { kind in
                    let pet = PetStore.pet(for: kind, style: st)
                    VStack(spacing: 2) {
                        Text(pet.emoji).font(.system(size: 28))
                        Text(kind.displayName).font(.caption)
                        Text("“\(pet.name)”").font(.caption2).foregroundStyle(.secondary)
                        Text(pet.trait).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
    }

    private var eggs: some View {
        Form {
            Toggle("Parade mode", isOn: Binding(
                get: { model.partyMode },
                set: { v in
                    model.partyMode = v
                    if v { model.updateSettings { $0.partyUnlocked = true } }
                }))
            .help("Every engine marches with confetti. Means: everything shipping, nothing blocked. Also unlocks Retro. (Also: type “party”.)")
            Toggle("Midnight watch", isOn: Binding(
                get: { model.midnightMode },
                set: { v in model.midnightMode = v }))
            .help("Void-black island, indigo rim, the Abyss nods back. For the 2am sessions. (Also: type “midnight”.)")
            HStack {
                VStack(alignment: .leading) {
                    Text("Good game")
                    Text("Automatic — fires when the last engine goes green with nothing waiting.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Preview") {
                    model.eggQuote = "GG — clean board 🤝"
                }
            }
            Text("Tap the notch 5× anytime and a resident says something. Pet quotes live there.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var advanced: some View {
        Form {
            Button("Reinstall agent hooks") { _ = HookInstaller.installAll() }
                .help("Re-merges ~/.claude/settings.json + writes ~/.contextdock/bin senders.")
            Button("Replay onboarding") { model.updateSettings { $0.onboarded = false } }
            Button("Open log file") {
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("ContextDock/dock.log")
                NSWorkspace.shared.open(url)
            }
            .help("Capped at 512KB. IDs and timings only — never your content.")
            Text("Socket: \(HookInstaller.socketPath())")
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(20)
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            model.lastError = "Login item failed: \(error)"
        }
    }
}
