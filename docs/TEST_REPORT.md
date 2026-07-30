# Test Report — v0.1 (2026-07-30)

Command: `./scripts/test.sh`
Toolchain: Apple Swift 6.3.3 (Command Line Tools), Swift Testing framework.

**Result: 36/36 tests passed, exit 0.**

## Coverage by area

| Suite | Tests | What it proves |
|---|---|---|
| ProjectResolverTests | 2 | Detects real temp git repos (root/branch/commit/worktree flag); nil outside a repo |
| MarkdownTests | 3 | Frontmatter scalars + lists, wikilink alias/heading stripping, plain files |
| VaultTests | 5 | Path-traversal rejection, atomic write + revision backup, section-append preserves content, missing-section creation, Obsidian URI encoding |
| GraphTests | 5 | Node/edge creation, missing-node edge rejection, duplicate-edge ignore, merge re-pointing + archive, undo |
| ContextEngineTests | 4 | Feature-ID extraction (F09), deterministic matching with per-match reasons, unrelated-node exclusion, missing-info reporting |
| PlannerTests | 2 | Three distinct plans with recommendation + full card fields; validation catches duplicates |
| ChecklistTests | 2 | Build-from-plan; state-machine legality (no notStarted→completed, no completed→running) |
| SecurityTests | 5 | Secret redaction (AWS/GitHub/bearer/conn-string/private-key), oversized rejection, malformed rejection, valid round-trip, dedup with bounded eviction |
| PreferenceTests | 2 | One action never activates a rule; repetition raises confidence |
| StoreTests | 2 | Full persistence round-trip; empty-start behaviour |
| AgentIntegrationTests | 3 | Fake adapter full lifecycle; package preview redaction; **live Unix-socket** receive + dedup + audit |

## Live verification (manual, this session)

- App launched from `build/ContextDock.app`; process stayed resident, no Dock icon.
- `events.sock` and `store.json` created in Application Support.
- External process sent an `AgentEvent` over the socket → event validated,
  deduplicated, ingested by the model, and persisted to `store.json`
  (verified by reading the store afterwards).
- Clean shutdown.

## Defects found by tests during development

1. `EventSocketServer.process` called `queue.sync` from its own queue —
   dispatch deadlock trap (SIGTRAP). Fixed with a dedicated lock; the crashing
   integration test now passes.

## Not covered (see KNOWN_LIMITATIONS.md)

XCUITest-based UI tests (require Xcode.app), live Claude/Codex dispatch
(requires user-initiated run), Reduce Motion visual verification.
