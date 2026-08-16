# Phase 6 automations validation ledger

## Implementation evidence required

- Typed, profile-scoped contracts for supported cron list/detail, run-now, pause/resume,
  history/errors, upcoming execution, create/edit, and delete operations.
- Contract tests pin every writable field and distinguish current/legacy cron surfaces; the app
  never sends fields whose shape has not been verified.
- List/detail show enabled/paused state, prompt/profile, schedule, repeat, recent run outcome,
  error, and upcoming execution when returned.
- Create/edit expose only supported schedule/repeat/profile/model/provider/skills/delivery fields.
- Delete is reducer-confirmed; all writes reload server-authoritative state.
- Unsupported write operations do not disable readable cron data; transient errors do not become
  permanent capability verdicts.
- Automations polling/refresh runs only while visible and remains isolated from Chats/Home.
- Existing SessionList cron summaries stay compatible with the richer administration state.
- Client/reducer tests cover current and legacy payloads, profile isolation, missing fields,
  schedule validation, run-now, pause/resume, create/edit/delete, history failures, stale jobs,
  unsupported methods, and transient failures.

## Deferred execution

- Execute cron contract and AutomationsFeature tests on macOS.
- Generate/compile the Tuist project and run Automations snapshots/accessibility checks.
- Compare list/detail/history/upcoming fields against the real Hermes server.
- Create, edit, run, pause/resume, and delete a disposable job under multiple profiles.
- Validate schedule, repeat count, model/provider, skills, and delivery behavior only for fields
  confirmed by the connected server.
- Confirm Automations polling stops off-tab and does not disturb chat streaming.
