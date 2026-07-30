# Claude Code Adapter

Implementation: `CLIAgentAdapter(kind: .claudeCode, …)` in
`ContextDockKit/Agents.swift`.

## What v0.1 does

- Detects the `claude` binary at common install paths
  (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.claude/local`).
  Availability is checked, never assumed; an unavailable adapter emits a
  `failed` event and throws.
- Launches app-initiated tasks with
  `claude -p "<package preview>" --output-format stream-json --verbose`
  in the selected repository directory (argument arrays, no shell).
- The prompt is the redacted `AgentTaskPackage.preview()` — only user-approved
  plan/checklist/context fields, never the vault.
- Streams stdout lines as normalized `AgentEvent`s (generic `toolFinished`
  summaries in v0.1); exit status maps to `completed`/`failed`.

## What it does NOT do

- No parsing of Claude authentication data, ever.
- No `--dangerously-skip-permissions`.
- No attaching to existing sessions (not implemented, not claimed).

## Next supported step

Parse `stream-json` message types into the richer event vocabulary
(`questionAsked`, `toolStarted/Finished`, `fileChanged`), and receive hook
events over the local Unix socket (`~/Library/Application
Support/ContextDock/events.sock`) via a user-approved hook installer.
