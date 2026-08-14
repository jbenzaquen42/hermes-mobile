# Phase 2 application shell and Home validation ledger

## Implementation evidence required

- Five primary destinations: Home, Chats, Board, Automations, and Settings.
- Existing authentication, chat navigation, live-chat slot ownership, and reconnect behavior
  remain intact beneath the new shell.
- Home cards load independently and retain last successful content when another card fails.
- Home exposes gateway health, profile/model, running sessions, active workers when available,
  pending interactions, recent completion/failure, cron attention, Kanban status, and push
  health without exposing sensitive cached values.
- Unsupported optional modules are hidden or clearly marked without breaking other tabs.
- Last-successful-refresh is visible; foreground, pull-to-refresh, and visible-only light polling
  share one refresh path.
- Quick actions route to new chat, active chat, pending interaction, Kanban task, scheduled job,
  and test ping when supported.
- Reducer tests cover per-card success/failure, stale content, unsupported capabilities, polling
  start/stop, foreground refresh, and quick-action delegation.

## Deferred execution

- Execute HermesKit reducer tests on macOS.
- Generate the Tuist project and compile the complete SwiftUI shell.
- Run simulator snapshots across compact and regular iPhone widths.
- Verify Dynamic Type and VoiceOver card/action labels.
- Connect to a live Hermes server with cron, push, and Kanban individually unavailable.
- Confirm Home polling stops off-tab and does not increase background activity.
- Confirm opening/closing chats through the new tab shell preserves streaming and reconnect state.
