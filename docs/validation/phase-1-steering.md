# Phase 1 steering validation ledger

This ledger separates authored implementation evidence from checks that require the Mac,
simulator, target iPhone, or live Hermes server.

## Protocol assumptions

- `session.steer` accepts `{session_id, text}` and returns `queued` or `rejected`.
- A `queued` steer is accepted for the next tool boundary; it does not prove delivery before
  the active turn completes.
- `session.redirect` accepts `{session_id, text}` and returns `redirected`, `queued`, or
  `rejected`.
- Hermes error `4010` means the current runtime cannot perform the operation; JSON-RPC
  unknown-method responses mean the server does not expose the method.
- Timeouts and disconnects do not permanently mark steering unsupported.
- `prompt.submit` is reserved for idle submission or an explicitly queued follow-up because
  busy-input policy is server-configurable.

Reference Hermes Agent source revision used for these assumptions:
`3d34b1916dac5bec5bbf9e9c0d3fd19e921728c0`.

## Implementation evidence required

- Typed steer and redirect result decoding.
- Draft retained until acknowledgement.
- Rejection and transport failure restore or retain the exact draft.
- Session changes invalidate stale acknowledgements.
- Accepted guidance is represented once.
- Queue state remains independent and queueing can be disabled.
- Running composer defaults to Steer with separate Stop and explicit alternate actions.
- Reducer tests cover accepted, rejected, unsupported, completion-in-flight, session change,
  disconnect, timeout, reconnect, duplicate prevention, Stop with draft, queue disabled, and
  redirect fallback.

## Deferred execution

- Run `make test` on the Mac.
- Generate the Tuist project and build the simulator target.
- Exercise steer and redirect against the real Hermes dashboard.
- Confirm a steer never interrupts the active response.
- Confirm timeout/reconnect reconciliation does not duplicate or erase guidance.
- Confirm Dynamic Type, VoiceOver labels, keyboard behavior, and action-menu reachability on
  the target iPhone.
