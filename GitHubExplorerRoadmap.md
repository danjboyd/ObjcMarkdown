# GitHub and Local Document Explorer Roadmap

## Goal

Provide a unified in-app explorer for local and GitHub-hosted documents so users can browse and open markdown workflows without spawning new windows.

## V1 Scope (Locked)

- Public GitHub repositories only.
- GitHub documents are read-only in-app.
- Local `Save As...` is supported for GitHub-opened content.
- No branch/tag selection in v1.
- No GitHub Enterprise support in v1.
- No repo-wide full-text search in v1.
- Tabs are used for document switching; no split-compare in v1.
- Tab/session restore is out of scope for v1.

## Explorer UX

- Single explorer UI reused for both sources:
  - `Local`
  - `GitHub`
- Source switch control in sidebar.
- GitHub mode controls:
  - `User` text field
  - `Repo` searchable dropdown for the selected user
  - repo list sorted by `updated` descending
  - hide archived/forked repos by default
  - include archived/forked toggle
- Local mode controls:
  - root path defaults to user home
  - root path preference is user-configurable
- Document list color tiers:
  - markdown files: accent color A
  - importable files (`.html`, `.htm`, `.rtf`, `.docx`, `.odt`): accent color B
  - other files: gray

## Open Behavior

- Single-click:
  - open/replace current tab
  - if current tab has unsaved edits, prompt `Save / Don't Save / Cancel`
- Double-click:
  - open in a new tab
- Importable files:
  - auto-convert to markdown using Pandoc integration
  - open converted markdown in a tab
- Unsupported/binary files:
  - shown in explorer; open is blocked with a clear message

## File Size Guardrail

- Enforce a max file size when opening local/GitHub files.
- Default cap: 5 MB.
- Cap is configurable in preferences.

## Data/Integration Notes

- Reuse existing import/export conversion path (`OMDDocumentConverter`).
- Reuse existing render/editor pipeline (`setCurrentMarkdown:sourcePath:` and preview render flow).
- Add explicit GitHub API error handling for:
  - user/repo not found
  - rate limiting
  - network timeouts

## Implementation Order

1. Sidebar explorer shell + source mode switching.
2. Local explorer and root preference.
3. GitHub user/repo controls + repo dropdown + directory listing.
4. Tab strip with single/double-click open behavior.
5. File-size cap enforcement + preference control.
6. Polish and focused tests.

## Deferred

- Branch/tag selector.
- GitHub auth/private repositories.
- GitHub Enterprise hosts.
- Repo-wide search.
- Tab/session persistence.
- Split compare between documents.

## Implementation Status (2026-02-18)

- Initial implementation landed:
  - Sidebar explorer with `Local` and `GitHub` source toggle.
  - GitHub `User` field + repository dropdown populated from public repos sorted by latest update.
  - Fork/archived visibility controlled by a toggle (hidden by default).
  - Single-click replace-current-tab open with dirty confirmation.
  - Double-click open in new tab.
  - File color tiers for markdown/importable/other.
  - Preferences support for local explorer root and max open file size cap.
  - GitHub-opened files are read-only and save via local `Save Markdown As...`.
- Remaining polish:
  - richer tab actions (close/reorder),
  - improved GitHub API rate-limit UX (auth/token support),
  - broader automated UI coverage for explorer interactions.
