# Phase 4 skills, toolsets, and MCP validation ledger

## Implementation evidence required

- Typed, capability-gated catalog reads for installed skills, toolsets, and MCP servers.
- Skill browse/search/detail includes server-returned description, documentation, source, and
  category without inventing missing metadata.
- Toolsets show descriptions and tool counts; MCP shows safe names, tool metadata, enabled
  state, and health only when Hermes exposes it.
- No secrets, environment values, headers, command arguments, credential-bearing URLs, or raw
  MCP definitions enter models, diagnostics, snapshots, or persistence.
- Editing begins from the complete server-authoritative selection.
- Local toggles do not write until one explicit Save.
- Save respects replace semantics, preserves unknown server entries, reports partial failures,
  and reloads authoritative state.
- Disabling a toolset used by an active workflow produces a warning before Save.
- Reducer/client tests cover search, detail, reload, unsupported methods, transient failures,
  unknown-entry preservation, empty selections, partial saves, and authoritative reload.

## Deferred execution

- Execute capability client and reducer tests on macOS.
- Generate/compile the Tuist project and run SwiftUI snapshots.
- Validate large catalogs, search responsiveness, Dynamic Type, and VoiceOver.
- Compare skill/toolset/MCP lists and descriptions to the real Hermes server.
- Save each selection type and confirm the intended profile alone changes.
- Verify unknown server entries survive a save from an older mobile client.
- Inspect logs and UI under MCP failures to confirm no secret/config value is exposed.
