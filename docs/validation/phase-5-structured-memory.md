# Phase 5 structured memory validation ledger

## Implementation evidence required

- Typed, profile-scoped `learning.frames`, `learning.detail`, `learning.edit`, and
  `learning.delete` contracts with authoritative unsupported/transient separation.
- User-profile and agent-memory entries are distinguishable without treating `USER.md` or
  `MEMORY.md` as unrestricted remote files.
- Frames expose server capacity/usage information when available.
- Detail, edit, and delete/archive operations reload server-authoritative state and accurately
  surface rejection or partial behavior.
- The UI explains that new sessions capture a fresh memory snapshot.
- Search/filter and edit drafts remain local until explicit action.
- Delete/archive requires reducer-owned confirmation and cannot target an entry from another
  profile after selection changes.
- No raw document replacement exists unless an allowlisted, size-limited, revision-checked,
  atomic Hermes RPC is discovered and implemented separately.
- Client/reducer tests cover profile isolation, empty/capacity states, detail, edit, delete,
  stale selection, unsupported methods, timeouts, reload failures, and secret-safe diagnostics.

## Deferred execution

- Execute learning client and MemoryFeature tests on macOS.
- Generate/compile the Tuist project and run memory snapshots/accessibility checks.
- Compare both memory stores and capacity values with the real Hermes server.
- Edit and delete/archive entries, then start a fresh session and verify snapshot behavior.
- Verify switching profiles cannot leak or mutate another profile's memory.
- Confirm logs, snapshots, and errors do not expose unrelated memory contents.
