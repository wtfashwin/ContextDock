# Changelog

## 0.1.0 — 2026-07-30

First working version.

- Native top-centre island (non-activating NSPanel, accessory app, Option+Space,
  Escape/click-outside collapse, active-display placement).
- Capture → deterministic context matching with per-source reasons and
  confidence → three distinct plan cards (Recommended/Fastest/Safest,
  keyboard 1/2/3) → checklist with evidence-based state machine.
- Obsidian vault adapter: containment-enforced paths, atomic writes, revision
  backups, section-append, frontmatter/wikilink parser, obsidian:// URIs.
- Knowledge graph with archive/merge/unlink/undo; never auto-deletes.
- Agent layer: AgentAdapter protocol, normalized 23-type AgentEvent, fake
  adapter with full lifecycle, launch-based Claude Code and Codex CLI adapters,
  local Unix-socket event bus (validated, bounded, deduplicated, audited).
- Secret redaction on every outgoing context package.
- Transparent preference learning; JSON persistence surviving relaunch.
- 36 unit/integration tests, all green.
