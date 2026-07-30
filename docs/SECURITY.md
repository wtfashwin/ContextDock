# ContextDock Security Model

## Principles

- Local-first: nothing leaves the Mac unless the user explicitly dispatches a
  reviewed context package to an agent.
- Repository content, note content, and agent output are untrusted input.
- Every automatic change is visible (audit log) and reversible (graph undo,
  vault revision backups).

## Threats and mitigations

| Threat | Mitigation |
|---|---|
| Path traversal / symlink escape out of the vault | `ObsidianVault.resolve` rejects any path outside the vault root, including `..` and symlinked parents (tested) |
| Accidental note overwrite | Atomic writes + `.contextdock-revisions` backup before every rewrite; section-append preferred over replacement (tested) |
| Secrets in context previews / agent packages | `SecretRedactor` (AWS keys, api_key/token/password assignments, bearer tokens, private key blocks, credentialed URLs, GitHub tokens) runs on every `AgentTaskPackage.preview()` (tested) |
| Command injection | All process launches use argument arrays (`Process.arguments`); no shell string concatenation anywhere |
| Hook spoofing / malformed events | Socket accepts only valid versioned `AgentEvent` JSON; malformed input rejected and audited (tested) |
| Oversized messages | 64 KB per-message bound, 256 KB per-stream bound; overflow rejected (tested) |
| Duplicate events | `EventDeduplicator` with bounded memory (tested) |
| Other local users reading the socket | Socket file mode 0600 |
| Network exposure | No network listener exists; Unix socket only |
| Credential parsing | The app never reads Claude/Codex auth files; adapter availability is a file-executability check only |
| Full-vault exfiltration | Task packages contain only the enumerated, user-visible fields; the preview is shown before sending |
| One repo receiving another's context | Context bundle is built per-request from the resolved repository + explicit mappings; matches carry visible reasons |

## Secrets

App-owned secrets belong in Keychain. v0.1 stores no secrets at all: adapters
use the user's already-authenticated CLIs.

## Telemetry

None. No analytics, no network calls of any kind.
