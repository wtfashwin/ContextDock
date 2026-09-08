# ContextDock Architecture

## Decisions (ADRs)

**ADR-001 — SwiftPM package instead of a checked-in `.xcodeproj`.**
This machine has Command Line Tools only (no Xcode.app), so `xcodebuild` and
XCTest are unavailable. A SwiftPM package builds and tests with the CLT
toolchain today and opens natively in Xcode (`open Package.swift`) when Xcode
is installed. Tests use the Swift Testing framework, which ships with the CLT.

**ADR-002 — Two targets: `ContextDockKit` (logic) + `ContextDockApp` (shell).**
Every engine, adapter, and model lives in a UI-free library that tests can hit
directly. The app target only holds AppKit panel plumbing and SwiftUI views.

**ADR-003 — JSON document store, not SQLite/SwiftData (yet).**
The dataset (nodes, edges, checklists, events) is small for a v1;
human-debuggable JSON with atomic writes wins. `LocalStoreProtocol` is the
repository seam — swapping in SQLite/SwiftData later touches one file.
Events/audit are bounded (5k/2k) so the file cannot grow unbounded.

**ADR-004 — Unix domain socket for agent events.**
Local-only, owner-only permissions (0600), newline-delimited JSON, versioned
schema, size-bounded, deduplicated, audited. No network listener exists.

**ADR-005 — Carbon `RegisterEventHotKey` for Option+Space.**
Documented API, works without Accessibility permission. No event taps.

**ADR-006 — Material-based glass now, `glassEffect` behind availability later.**
The current SDK path builds with system `ultraThinMaterial` + dark tint +
hairline border (real native material, one layer). When built against an SDK
exposing Liquid Glass APIs, `GlassCapsule` is the single place to adopt them
behind `if #available`.
(Superseded by ADR-007 once SDK 26.5 + macOS 26.6 runtime were confirmed.)

**ADR-007 — AppKit owns the glass; SwiftUI stays transparent inside it.**
`NSGlassEffectView.regular` (macOS 26+, verified in SDK 26.5) is the sole
material owner for the expanded island, with `NSVisualEffectView`
(`.behindWindow`, `.hudWindow`) as the named fallback and an opaque
presentation under Reduce Transparency. SwiftUI content inside renders
transparent (`nativeGlassHost` env) — no stacked `.glassEffect`/materials.
One retained `NSPanel` holds two retained `NSHostingView`s (black collar +
transparent expanded tree), visibility-toggled with a 0.16s crossfade, never
rebuilt. Collapsed stays pure black (hardware fusion, like Apple's island).
Proven first in isolation (`GlassProbe.swift`, Debug menu). Window level
`.screenSaver` is the minimum covering the menu bar (`.statusBar` renders
under it). Motion: single 0.36s/0.9 morph, 120/250ms hover debounce with
cancellation, no looping idle effects; celebrations are one-shot.

## Module map

| Module (spec) | Where it lives |
|---|---|
| AppShell / IslandUI | `Sources/ContextDockApp` (`AppDelegate`, `IslandPanelController`, `IslandRootView`) |
| Capture / Checklist UI | `IslandRootView.swift` |
| ContextEngine | `ContextDockKit/ContextEngine.swift` |
| ProjectResolver | `ContextDockKit/ProjectResolver.swift` |
| KnowledgeGraph | `ContextDockKit/KnowledgeGraph.swift` |
| ObsidianAdapter | `ContextDockKit/Obsidian.swift` |
| AgentCore + adapters | `ContextDockKit/Agents.swift`, `EventSocket.swift` |
| Planner | `ContextDockKit/Planner.swift` |
| LocalStore | `ContextDockKit/LocalStore.swift` |
| Security | `ContextDockKit/Security.swift` |

## Concurrency

- UI state (`DockModel`) is `@MainActor` + `@Observable`.
- Engines are value types (`Sendable`) invoked from `Task`s off the main thread.
- The socket server runs on its own serial dispatch queue; the deduplicator is
  guarded by a lock (a `queue.sync` from the queue itself deadlocks — found by
  a crashing integration test, fixed).

## Data flow

input → `ContextEngine.resolve` (deterministic matchers, each match carries a
reason) → `PlannerEngine.plan` (3 distinct options) → user selects →
`ChecklistBuilder` → vault section-append → `AgentAdapter.dispatch` →
normalized `AgentEvent` stream (direct callback or Unix socket) → checklist
advance with evidence → persist.
