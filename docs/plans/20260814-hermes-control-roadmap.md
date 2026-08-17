# Hermes Control roadmap

Implementation and Apple-platform validation are intentionally separated while the Mac
environment is being prepared. Tests and protocol fixtures are authored with each feature,
but unexecuted checks must never be reported as passing.

## Implementation status — 2026-08-16

- [x] Phase 0 — Repository foundation ([PR #1](https://github.com/jbenzaquen42/hermes-mobile/pull/1))
- [x] Phase 1 — True steering ([PR #2](https://github.com/jbenzaquen42/hermes-mobile/pull/2))
- [x] Phase 2 — Application shell and Home ([PR #3](https://github.com/jbenzaquen42/hermes-mobile/pull/3))
- [x] Phase 3 — Profile administration ([PR #4](https://github.com/jbenzaquen42/hermes-mobile/pull/4))
- [x] Phase 4 — Skills, toolsets, and MCP ([PR #5](https://github.com/jbenzaquen42/hermes-mobile/pull/5))
- [x] Phase 5 — Memory and USER profile ([PR #6](https://github.com/jbenzaquen42/hermes-mobile/pull/6))
- [x] Phase 6 — Automations ([PR #8](https://github.com/jbenzaquen42/hermes-mobile/pull/8))
- [x] Phase 7 — Kanban ([PR #10](https://github.com/jbenzaquen42/hermes-mobile/pull/10))
- [ ] Phase 8 — Notifications and polish
- [ ] Validation Phase 1 — Mac and iPhone baseline
- [ ] Validation Phase 2 — Feature and regression validation
- [ ] Validation Phase 3 — Daily-driver acceptance

Checked implementation phases have merged source, authored unit/contract/snapshot tests, and
a phase-specific validation ledger. They have not yet been compiled or executed with the
Apple toolchain. Phase 5 is intentionally server-default-profile-only because current
`learning.*` RPCs do not accept a profile parameter; custom-profile memory is shown as
unsupported rather than accessing the wrong store.

## Phase 0 — Repository foundation

- Fork and clone Hermes Mobile with explicit `origin` and `upstream` remotes.
- Pin and record the upstream starting revision.
- Apply fork-owned display name and bundle identifiers.
- Keep signing inputs local and document Personal Team versus push-enabled requirements.
- Maintain a validation ledger for checks unavailable on Windows.

## Phase 1 — True steering

- Add typed `session.steer` and `session.redirect` gateway methods.
- Model accepted, rejected, queued, redirected, and unsupported outcomes explicitly.
- Preserve drafts through acknowledgement, timeout, reconnect, and rejection.
- Reject stale responses after a session change and prevent duplicate transcript entries.
- Make Steer the default running-turn action; retain Stop and explicit queue/redirect choices.
- Author reducer and protocol tests for all race cases before moving on.

## Phase 2 — Application shell and Home

- Add Home, Chats, Board, Automations, and Settings destinations.
- Build independently loading Home cards with partial-failure isolation.
- Add operational quick actions, refresh timestamps, foreground refresh, and light polling.
- Hide or clearly mark unsupported server modules without affecting chat.

## Phase 3 — Profile administration

- Add profile list, describe, create, configure, rename, and delete flows.
- Add profile-scoped model, reasoning, skills, toolsets, and MCP settings.
- Build the SOUL editor with preview, draft recovery, conflict/error reporting, and
  unsaved-change protection.

## Phase 4 — Skills, toolsets, and MCP

- Browse and inspect server-authoritative catalogs.
- Enable or disable capabilities per profile using explicit Save operations.
- Respect replace semantics, preserve unknown entries, and reload after saving.
- Never expose MCP secrets or environment values.

## Phase 5 — Memory and USER profile

- Implement structured memory through `learning.frames`, `learning.detail`,
  `learning.edit`, and `learning.delete`.
- Show capacity and fresh-session snapshot behavior.
- Defer raw document replacement unless narrowly scoped Hermes RPCs provide allowlisting,
  revision checking, atomic writes, size limits, and rollback.

## Phase 6 — Automations

- Improve cron list, detail, state, run-now, history, errors, and upcoming execution.
- Add create/edit/delete only behind verified contract shapes.
- Preserve profile, prompt, model/provider, skills, repeat, and delivery semantics.

## Phase 7 — Kanban

- Detect the native Kanban plugin and incrementally add board, lane, card, task detail,
  live refresh, editing, orchestration, logs, and review workflows.
- Use paged lanes plus searchable tasks on iPhone and multi-column inspection on iPad.

## Phase 8 — Notifications and polish

- Retain the existing push integration and add event preferences and deep links.
- Add diagnostics, accessibility, Dynamic Type, optional Face ID lock, and attribution.
- Keep Personal Team builds usable when APNs entitlement provisioning is unavailable.

## Validation Phase 1 — Mac and iPhone baseline

- Generate with Tuist, execute the existing and newly authored test suites, and build on a
  simulator.
- Resolve signing, install on the target iPhone, and connect to the real Hermes server.
- Confirm authentication, hydration, new chat, streaming, reconnect, and background return.
- Record Hermes version, desktop contract, capabilities, and TestFlight differences.

## Validation Phase 2 — Feature and regression validation

- Validate completed implementation phases in order against representative Hermes versions.
- Exercise unsupported methods, partial failures, stale sessions, disconnects, and retries.
- Run reducer, protocol, snapshot, accessibility, and layout checks.
- Treat draft loss, duplication, credential exposure, or chat instability as release blockers.

## Validation Phase 3 — Daily-driver acceptance

- Use the app across repeated foreground/background, network-loss, authentication-expiry,
  server-restart, and server-capability-change scenarios.
- Verify one-command rebuild/reinstall and push/deep-link behavior where signing permits.
- Complete release and attribution checklists.

## Branch and PR policy

- Keep each phase or independently reversible vertical slice on its own branch.
- Open a PR with protocol assumptions, authored tests, executed checks, and deferred checks.
- Avoid mixing generated project files or unrelated cleanup into feature PRs.
- If later validation fails, fix forward when safe or revert the isolated PR without taking
  unrelated completed features with it.
