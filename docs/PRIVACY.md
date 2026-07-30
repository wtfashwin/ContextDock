# Privacy

- All data stays on this Mac. There is no server, no account, no telemetry,
  and no network code in the app.
- The only ways data leaves the machine:
  1. You press "Send to agent" — the exact, redacted context package shown in
     the preview is passed to a CLI you already installed and authenticated.
  2. You open a note in Obsidian (a local app) via `obsidian://` URL.
- The app reads only: the repositories you point it at (via `git` metadata,
  not file contents), and the Obsidian vault folder you selected.
- The app never reads credentials, auth files, or anything outside the
  selected vault and repositories.
- Learned preferences are local, inspectable, and resettable
  (`PreferenceSignal` records what was learned, why, and from which actions).
- The audit log (`store.json`) records every socket event, vault write, and
  plan selection so every automatic change is reviewable.
