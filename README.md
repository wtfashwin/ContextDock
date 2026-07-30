# ContextDock

A small native macOS "thinking island" that sits at the top centre of your screen.
Capture a thought, let it match your project context, choose one of three plans,
get a checklist, dispatch to an agent, and have the results written back to your
Obsidian vault.

Native Swift + SwiftUI + AppKit. No Electron. Local-first: your data stays on
this Mac unless you explicitly send a reviewed context package to an agent.

## Status: v0.1 (first working version)

Working today:

- Top-centre floating island (non-activating `NSPanel`, no Dock icon)
- Collapsed capsule with project/branch, status dot, agent count, waiting/done indicators
- Option+Space global shortcut, click to expand, Escape / click-outside to collapse
- Capture input → deterministic context matching with per-source reasons
- Three meaningfully different plan cards (Recommended / Fastest / Safest), keyboard 1/2/3
- Checklist with a real state machine and evidence-based completion
- Obsidian vault writer: atomic writes, revision backups, section-append (never clobbers)
- Local Unix-socket event bus with schema validation, size bounds, dedup, audit log
- Fake (demo) agent adapter with a full event lifecycle
- Claude Code / Codex CLI adapters (launch-based, detected — never assumed)
- Transparent preference learning (no rule from a single action)
- JSON persistence in Application Support, survives relaunch

## Build & run

Requires Swift 6 toolchain (Command Line Tools are enough; Xcode optional).

```bash
# Run tests
./scripts/test.sh

# Build the app bundle and launch
./scripts/make_app.sh
open build/ContextDock.app
```

To open in Xcode (when installed): `open Package.swift`.

## Layout

- `Sources/ContextDockKit` — all engines, adapters, models (UI-free, fully tested)
- `Sources/ContextDockApp` — AppKit panel shell + SwiftUI views
- `Tests/ContextDockKitTests` — unit + integration tests (Swift Testing)
- `docs/` — architecture, security, adapter docs
- `SampleVault/` — sample Obsidian vault used for demos
- `scripts/` — build/test helpers

## Documentation

See `docs/ARCHITECTURE.md`, `docs/SECURITY.md`, `docs/KNOWN_LIMITATIONS.md`,
`docs/OBSIDIAN_INTEGRATION.md`, `docs/CLAUDE_ADAPTER.md`, `docs/CODEX_ADAPTER.md`,
`docs/KNOWLEDGE_GRAPH.md`, `docs/TEST_REPORT.md`, `docs/BUILD_REPORT.md`.
