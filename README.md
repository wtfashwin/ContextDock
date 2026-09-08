# Context Dock

*A native macOS notch island that turns a stray thought into a dispatched, tracked, and journaled agent task — without leaving your screen's top edge.*

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Build](https://img.shields.io/github/actions/workflow/status/wtfashwin/ContextDock/ci.yml?branch=main)
![Version](https://img.shields.io/badge/version-1.0.0-informational)
![Coverage](https://img.shields.io/badge/tests-52%20passing-brightgreen)
![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey)

<p align="center">
  <img src="docs/assets/banner-placeholder.png" alt="Context Dock banner" width="720">
</p>

## 1. About

Context Dock lives in your MacBook's notch as a flush, always-available island. Capture a thought, get it matched against your live project context, pick a plan, and dispatch it to a coding agent — all without a Dock icon, a browser tab, or a context switch. It's built for developers running multiple AI coding agents across multiple projects who need one calm, native surface to route work through, not five terminal tabs and a mental map of who's doing what.

### Key features

**Core workflow**
- **Notch-native island** — measured cutout geometry per MacBook model, with a no-notch fallback bar for external displays.
- **Deterministic plan matching** — capture a thought and get three meaningfully different plans (Recommended / Fastest / Safest), each with a real, evidence-based checklist.
- **Multi-agent live feed** — passive discovery plus rich socket events track every connected agent's status in one glance.

**Trust & control**
- **Local-first by design** — your data stays on this Mac; nothing leaves until you explicitly send a reviewed context package.
- **Approve/deny at the speed of thought** — keyboard-driven decisions (⌘Y / ⌘N / ⌘1-3) with an audit-logged event bus underneath.
- **Obsidian vault writer** — atomic writes, revision backups, section-append that never clobbers your notes.

## 2. Tech Stack & Architecture

| Layer | Technology |
|---|---|
| UI shell | AppKit (`NSPanel`) + SwiftUI |
| Core logic | Pure Swift (`ContextDockKit`, UI-free, fully unit tested) |
| Concurrency | Swift 6 strict concurrency, actor-isolated state |
| IPC | Local Unix-socket event bus, schema-validated, size-bounded |
| Persistence | JSON in `Application Support`, atomic Obsidian vault writes |
| Testing | Swift Testing, 52 tests |

```
 Capture (⌥Space) → Context Match → Plan Select → Checklist
        │                                              │
        ▼                                              ▼
  Local Event Bus  ◀──────────────────────────  Agent Adapter
        │                                              │
        ▼                                              ▼
  Decision Journal                            Obsidian Vault Write
```

## 3. Getting Started

### Prerequisites
- macOS 15 or later
- Swift 6 toolchain (Xcode Command Line Tools are enough — full Xcode is optional)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/wtfashwin/ContextDock.git
cd ContextDock

# 2. Run the test suite
./scripts/test.sh

# 3. Build the app bundle
./scripts/make_app.sh
```

### Quick Start

```bash
# Launch the built app
open build/ContextDock.app

# Or open the package directly in Xcode
open Package.swift
```

Once running, press **Option+Space** anywhere to open the island, capture a thought, pick a plan, and let Context Dock track it through to completion.

## 4. Roadmap

- [x] Top-centre floating notch island with no-notch fallback
- [x] Deterministic context matching with three-plan selection
- [x] Obsidian vault writer with atomic, non-destructive writes
- [x] Multi-agent live feed with passive + socket-based discovery
- [x] Decision journal with confidence-scored pattern insights
- [x] Liquid Glass UI on macOS 26 with matte fallback
- [ ] Cross-platform companion for non-notch Macs and external monitors
- [ ] Team-shared context packages (opt-in, still local-first)
- [ ] Plugin API for third-party agent adapters

## 5. Contributing & License

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, style, and PR guidelines.

Licensed under the [MIT License](LICENSE).
