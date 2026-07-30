# Contributing to ContextDock

Thanks for your interest in ContextDock — a native macOS thinking island.

## Getting started

1. Install a Swift 6 toolchain (Xcode Command Line Tools are enough).
2. `bash scripts/test.sh` — run the full test suite.
3. `bash scripts/make_app.sh && open build/ContextDock.app` — build and launch.

## Ground rules

- All engine logic lives in `Sources/ContextDockKit` and must stay UI-free and tested.
- The app shell (`Sources/ContextDockApp`) stays thin: AppKit panel + SwiftUI views.
- No hard-coded paths, projects, or providers. Detection over assumption.
- Every persisted or transported payload is schema-versioned.
- Secrets never leave the machine; run `SecretRedactor` over anything user-visible.

## Pull requests

- One logical change per PR, with tests for engine changes.
- Conventional Commits (`feat:`, `fix:`, `chore:`, ...) for messages.
- CI (swift test on macOS) must pass.

## Reporting bugs / requesting features

Use the issue templates. For support questions see SUPPORT.md.
