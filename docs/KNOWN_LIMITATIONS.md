# Known Limitations (v0.1)

Environment
- Built with Command Line Tools only (no Xcode.app on this machine): no
  `.xcodeproj` (SwiftPM package instead — Xcode opens `Package.swift`
  natively), no UI-automation tests (XCUITest requires Xcode), no archive.
- Screenshots could not be captured in-session: the terminal lacks the macOS
  Screen Recording permission. Grant it in System Settings → Privacy &
  Security → Screen Recording and run `screencapture -x shot.png` with the app
  open.

Product
- Liquid Glass (`glassEffect`) not yet adopted: current SDK path uses system
  Material fallback. `GlassCapsule` is the single adoption point.
- Repository detection uses last-known/candidate directories; there is no
  "frontmost editor cwd" signal yet (that arrives with real agent events
  carrying `workingDirectory`).
- Claude Code / Codex adapters are launch-based (spawn CLI, stream stdout).
  Structured `stream-json` parsing is minimal (lines become generic events);
  attaching to existing sessions is not implemented and not claimed.
- Vault picker UI not built yet: vault path is set via the store settings
  (`vaultPath`); security-scoped bookmarks matter only for the sandboxed
  distribution model, and v0.1 is unsandboxed.
- Knowledge-graph window (zoom/pan canvas) not built; graph exists as a fully
  tested data layer with merge/unlink/undo.
- Settings UI, hook installer, "What ContextDock learned" screen: data layers
  exist (`PreferenceSignal`, audit); screens not yet built.
- No custom shortcut recorder yet (Option+Space fixed).

Honesty notes
- The app never claims to know "all context": every match shows its reason,
  confidence is surfaced, and missing information is listed.
- Checklist completion requires evidence; an agent saying "done" only attaches
  evidence, it does not silently complete unrelated items.
