# ContextDock

A native macOS app for developers to capture a thought, match it to project context, choose a plan, and launch a coding agent from a notch-style panel.

## What it does

- Opens a floating island with Option+Space, with a fallback layout for displays without a notch.
- Produces Recommended, Fastest, and Safest plans using an available Claude Code/Codex CLI or local rules.
- Launches CLI tasks with a context package and displays agent events.
- Tracks decisions and preferences in local storage.
- Includes an Obsidian note writer with atomic writes and revision backups.
- Accepts events through a local Unix socket and includes a demo event sender.

## Project status

This is a Swift application under active development. Some adapters and controls are partial: CLI output becomes generic events, attaching to an arbitrary existing session is incomplete, and the adapter cancellation method is currently empty. Documentation includes older limitation notes that may lag the code.

## Built with

Swift 6, SwiftUI, AppKit, Swift Package Manager, and Swift Testing. No external Swift package dependencies are declared.

## Getting started

Requirements: macOS 15 or later and a Swift 6 toolchain. Xcode Command Line Tools can build the Swift package; full Xcode can open `Package.swift`.

```bash
git clone https://github.com/wtfashwin/ContextDock.git
cd ContextDock
./scripts/make_app.sh
```

Launching the app currently installs hooks automatically before onboarding. It writes scripts under `~/.contextdock/bin/` and merges hook entries into `~/.claude/settings.json`. Review [the installer](Sources/ContextDockKit/HookInstaller.swift) and back up existing Claude settings before the first launch.

```bash
open build/ContextDock.app
```

The build script creates an app bundle and attempts local ad-hoc signing. It does not produce a notarized distribution.

Install and authenticate a supported agent CLI separately if you want AI planning or task dispatch. Without an available Claude Code/Codex CLI, planning falls back to local rules.

## Use it

Press Option+Space, enter a thought, choose a plan, and review its checklist and task package before dispatch. Configure the project and optional Obsidian vault in the app. Agent activity appears in the island and local journal.

Planning itself can call an installed Claude Code or Codex CLI. That CLI may send the request, matched context, and learned preferences to its provider before task dispatch. Review the provider account and its data handling before using sensitive project context. Local storage does not mean every planning path is offline.

## Structure and documentation

| Path | Purpose |
| --- | --- |
| `Sources/ContextDockApp/` | SwiftUI views and AppKit panel |
| `Sources/ContextDockKit/` | Planning, adapters, events, storage, and notes |
| `Tests/ContextDockKitTests/` | Core test suite |
| `scripts/make_app.sh` | Build the app bundle |
| `scripts/fake_events.py` | Demo socket events |

See [architecture](docs/ARCHITECTURE.md), [Claude adapter notes](docs/CLAUDE_ADAPTER.md), [Codex adapter notes](docs/CODEX_ADAPTER.md), and [contributing](CONTRIBUTING.md). Older [privacy](docs/PRIVACY.md) and [limitation](docs/KNOWN_LIMITATIONS.md) notes should be read alongside the current source.

## Available checks

```bash
./scripts/test.sh
swift build
```

The test script adds framework search paths when using Command Line Tools. These commands cover the Swift package; they do not establish UI behavior, external CLI compatibility, or provider integration.

To stop the running app, use its app controls or, from a terminal, `pkill -x ContextDock`.

## License

[MIT](LICENSE).
