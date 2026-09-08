# Changelog

## 1.0.0 — 2026-09-07

The notch island. Zero-config, crash-hardened, liquid glass.

- True notch adherence: measured cutout geometry (179×32pt here; 185×32 14",
  220×38 16" reference), screenSaver-level flush panel, symmetric wing
  expansion, pure-black collapsed seam. No-notch fallback bar.
- Live multi-agent feed: Claude, Codex, Gemini, Cursor, OpenCode, Qwen,
  Copilot + demo. Passive discovery (one ps snapshot, bounded cached lsof,
  tmux panes, transcript titles) merged with rich socket events.
- PID-accurate redirect: tmux pane → iTerm tty → activate → open-at-cwd,
  every Jump button showing its exact landing address.
- Approve (⌘Y) / Deny (⌘N) / answer (⌘1-3) from the notch; approval bursts.
- Decision journal: after 4 similar calls the 5th surfaces a pattern insight
  with confidence — suggestions only, never automation.
- Official Liquid Glass on macOS 26 (glassEffect + container, specular
  streaks, lensing rim, vivid sheen, glass tiles + prominent actions) with
  matte fallback; Vivid toggle; Reduce Motion/Transparency honored.
- 8 pet packs × 8 engines, compiler-proven mutually exclusive; Warbound
  (3 failures), Abyss (15 jumps), Shadow (5 answers), Retro (parade) unlocks
  with visible progress. Eggs with meanings: parade, midnight watch, GG.
- 4-beat animated onboarding with live island preview; Settings with
  General/Pets/Eggs/Advanced; launch-at-login; capped file logging.
- Hardening: fixed EXC_BAD_ACCESS in settings windows (actor-trampoline +
  lifetime) and in window animations (serialized frames); debounced
  off-main persistence; O(1) session index; identity-preserving reducer.
- 52 tests, all green.

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
