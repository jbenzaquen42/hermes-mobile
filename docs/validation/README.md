# Validation handoff

Implementation is merged through Phase 5. The Windows development host could perform source,
contract, diff, and security reviews, but it could not run Swift, Tuist, Xcode, the iOS
simulator, signing, or physical-device checks.

## Phase ledgers

- [ ] [Phase 1 — Steering](phase-1-steering.md)
- [ ] [Phase 2 — Home shell](phase-2-home-shell.md)
- [ ] [Phase 3 — Profile administration](phase-3-profile-administration.md)
- [ ] [Phase 4 — Capability management](phase-4-capability-management.md)
- [ ] [Phase 5 — Structured memory](phase-5-structured-memory.md)
- [ ] [Phase 6 — Automations](phase-6-automations.md) — implementation still pending

These boxes remain unchecked until every deferred item in the linked ledger has current Mac,
simulator/device, and live-server evidence. Phase 0 baseline commands and device acceptance are
in [`../plans/20260814-hermes-control-baseline.md`](../plans/20260814-hermes-control-baseline.md).

## Next implementation sequence

1. Implement Phase 6 Automations from its contract-first ledger.
2. Implement Phase 7 Kanban.
3. Implement Phase 8 Notifications and polish.
4. Run Validation Phases 1–3 in order once the Mac is ready.

Do not mark a phase ledger complete solely because its source PR merged. If Mac compilation
finds integration errors in a phase, fix forward in a small PR or revert that phase's isolated
merge before continuing validation.
