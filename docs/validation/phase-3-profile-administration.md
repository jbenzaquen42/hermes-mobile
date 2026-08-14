# Phase 3 profile administration validation ledger

## Implementation evidence required

- Native typed contracts for `profiles.list`, `profiles.create`, `profiles.describe`, and
  `profiles.configure`, with REST rename/delete retained only where appropriate.
- Profile detail is scoped to the selected profile and includes description, model/provider,
  reasoning effort, SOUL, skills, toolsets, MCP servers, and destructive operations.
- SOUL loads from server-authoritative describe state and saves through configure.
- Markdown edit/preview, character/token estimate, unsaved-change protection, and local
  crash-recovery drafts are represented in reducer-owned state.
- One explicit Save operation reports partial failures accurately and reloads authoritative
  profile state after success.
- Unknown response fields are preserved or ignored safely; unsupported methods are gated only
  on authoritative responses, never timeouts.
- Reducer and contract tests cover profile isolation, load/reload, dirty-state protection,
  draft recovery, successful save, partial failure, rejection, unsupported methods, and
  destructive confirmation.

## Deferred execution

- Execute all HermesKit profile client/reducer tests on macOS.
- Generate the Tuist project and compile profile editor navigation and Markdown preview.
- Run compact/large Dynamic Type snapshots and VoiceOver label checks.
- Load, edit, save, and reload an existing profile against the real Hermes server.
- Confirm model/capability changes affect only the intended profile.
- Force a partial configure failure and verify the UI distinguishes saved and unsaved fields.
- Kill/relaunch while editing and verify local SOUL draft recovery without overwriting newer
  server content silently.
