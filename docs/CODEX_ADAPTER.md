# Codex Adapter

Implementation: `CLIAgentAdapter(kind: .codex, …)` in
`ContextDockKit/Agents.swift`.

## What v0.1 does

- Detects the `codex` binary at common install paths; availability checked,
  never assumed.
- Launches app-initiated tasks with `codex exec --json "<package preview>"`
  in the selected repository (argument arrays, no shell).
- Streams stdout lines as normalized `AgentEvent`s; exit status maps to
  `completed`/`failed`.
- Tracks process state for the launched task.

## What it does NOT do

- No parsing of Codex credentials.
- No unrestricted command execution flags.
- Attaching to arbitrary existing Codex sessions is a separate capability,
  not implemented and not claimed as working.

## Next supported step

Parse `codex exec --json` event objects into the richer vocabulary (plan,
approvals, file changes), and surface approval requests as `permissionRequested`
events in the island's waiting-for-user state.
