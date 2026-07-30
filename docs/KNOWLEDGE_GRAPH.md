# Knowledge Graph

Data layer: `ContextDockKit/KnowledgeGraph.swift` (fully tested).

## Nodes

22 types (`project`, `repository`, `worktree`, `feature`, `decision`,
`requirement`, `task`, `checklist`, `document`, `file`, `person`, `team`,
`concept`, `question`, `risk`, `agent`, `agentSession`, `conversation`,
`plan`, `build`, `test`, `release`). Every node: stable ID, title, type,
project, source + source path, created/updated timestamps, confidence, tags,
summary, archived flag.

## Edges

17 types (`belongsTo`, `relatesTo`, `dependsOn`, `blocks`, `implements`,
`verifies`, `createdBy`, `updatedBy`, `discussedIn`, `derivedFrom`,
`supersedes`, `conflictsWith`, `approvedBy`, `storedIn`, `executedBy`,
`produced`, `references`). Every edge: source, target, type, evidence,
confidence, created time, user-confirmed flag.

## Invariants (tested)

- Nodes are never auto-deleted — `archiveNode` only.
- Edges to missing nodes are rejected; duplicate edges are ignored.
- `merge(duplicate:into:)` re-points edges, drops self-loops, archives the
  duplicate.
- `unlink` removes a specific edge.
- Every mutation checkpoints; `undo()` restores the previous state
  (bounded 50-step stack).

## UI

The island shows only the small context preview (matched sources with
reasons). The full graph window (Canvas zoom/pan/filter) is a next step —
see KNOWN_LIMITATIONS.md.
