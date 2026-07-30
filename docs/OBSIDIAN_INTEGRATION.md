# Obsidian Integration

## Vault access

- The vault root is user-selected (v0.1: `vaultPath` setting; picker UI next).
- All access goes through `ObsidianVault`, which refuses any path outside the
  vault (path traversal and symlink-parent escapes are rejected and tested).
- Nothing outside the vault is ever scanned.

## Write safety

- Atomic writes only.
- Before any rewrite, the previous content is copied to
  `.contextdock-revisions/<name>.<timestamp>.bak` inside the vault.
- The default write mode is **section append** (`appendToSection`): content is
  inserted under a `## Heading`, never replacing user-written text (tested).

## Format

Obsidian-compatible Markdown: YAML frontmatter (scalars + simple lists),
wikilinks (`[[Target]]`, `[[Target|Alias]]`, `[[Target#Heading]]`), Markdown
checklists with stable block IDs (`- [ ] action ^item-id`).

## What gets written

Checklists on plan selection (under `## Current work` of the project note),
with a timestamped subsection per checklist. Noisy agent events are summarised —
individual tool calls are never written.

## Navigation

`ObsidianURI` builds `obsidian://open?vault=…&file=…` and
`obsidian://search?...` URLs (URL-encoded, tested); "Open note" in the
checklist view uses it.

## Folder structure

`ContextDock/{Inbox,Projects,Repositories,Features,Decisions,Tasks,Plans,
Agent Sessions,Daily Updates,Concepts,People,Archive}` — created on demand,
see `SampleVault/` for a working example.
