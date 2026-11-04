# Architecture

Release `1.4.6` targets Retail 12.1.5 with expected interface `120105`. Current live source `12.1.5.70783` was checked on 2026-11-04; the relevant ActionBar, Spell Activation Overlay, alert-template, Settings, and Cooldown Viewer contracts remain compatible with knowledge-base revision `c2a630aa186de401262663cc8568a77988be69df` and its selected UI-source baseline. Named-client behavior remains **NOT-RUN**.

## Runtime flow

```mermaid
flowchart TD
    Login[PLAYER_LOGIN] --> DB[Migrate and validate SavedVariables]
    DB --> Families[Build bounded target and signal families]
    Families --> Buttons[Resolve known button assignments]
    Login --> Viewer[Attach Cooldown Viewer lifecycle outside combat]
    Overlay[Overlay SHOW/HIDE] --> Arbitration[Event/query arbitration]
    Query[IsSpellOverlayed] --> Arbitration
    Assignment[Action assignment changes] --> Buttons
    Mapping[Override/hotfix/talent/spell invalidation] --> Families
    Arbitration --> Desired[Desired glow state]
    Buttons --> Render[Addon-owned alert surfaces]
    Viewer --> Render
    Desired --> Render
    Combat[Combat lockdown] --> Deferred[One latest post-combat structural pass]
    Deferred --> Buttons
    Deferred --> Viewer
```

## Ownership model

Every file receives the same second TOC vararg table. `Core.lua`, `Debug.lua`, and `Options.lua` compose through that table; implementation state stays file-local. The only intentional globals are the SavedVariables root, slash-command registration, and the named debug frame required by `UISpecialFrames`.

## Detection

The Spell Activation Overlay event/query pair is the sole proc authority. SHOW/HIDE events are synchronous wake-ups. The official query supplies current state when caller, argument, and result are accessible. A relevant SHOW payload or the last positive candidate is queried first, but authoritative OFF still requires every candidate to be readable and false. A short SHOW grace covers same-frame ordering; inaccessible/unavailable query state has one bounded fallback lifetime.

Action-bar events update assignment ownership only. Mapping invalidations coalesce outside combat and refresh already observed assignments immediately in combat without creating structure. Duplicate or irrelevant Cooldown Viewer override events do no work.

## Spell identity and bounds

`targetSpellIDs` and `signalSpellIDs` are validated ordinary integer arrays, capped at 32 entries each. Resolved target and signal families are independently capped at 128 IDs so replacement learning cannot turn overlay reconciliation into unbounded work. Configured signal aliases reserve their budget before learned target variants. `targetFamily` expands configured roots through `C_Spell.GetBaseSpell`, `C_Spell.GetOverrideSpell`, and explicit Cooldown Viewer override pairs. An alias does not become an action-button target merely because it produced an event.

## Action buttons

Known stock and supported third-party button surfaces are weakly tracked. The current action slot is resolved from the button's authoritative provider; `C_ActionBar.GetSpell` is primary, with a resolved action/macro fallback only when ordinary and available. Every foreign field/method read is access-gated and isolated from hostile/inaccessible metatables before it can influence assignment state. Named adapters cover current `BT4ButtonN`, `ElvUI_BarXButtonY`, `DominosActionButtonN`, and Dominos `MultiBar*ActionButtonN` families; the exact donor pins and limits are recorded in `docs/DONOR_REVIEW.md`.

Known buttons maintain one weak reverse index from current action slot to button. A nonzero `ACTIONBAR_SLOT_CHANGED(slot)` performs an immediate targeted refresh and one coalesced targeted next-frame retry; broad slot/page/modifier/vehicle invalidations collapse into one complete pass. If combat exit already requires a settled structural rescan, that rescan alone owns assignment, viewer, geometry, and proc recovery. There is no 540-slot sweep, macro-body parsing, per-frame polling, or action-event proc query.

## Cooldown Viewer

The adapter uses public data/override/hotfix events as wake-ups and source-verified private instance methods as a narrow compatibility boundary. Viewer/pool/item member discovery is fail-closed and protected from throwing reads. Viewer pools are enumerated only during setup/recovery outside combat. Actual viewer/item instances are post-hooked once; installation failures are contained, never marked successful, and retried only on a later lifecycle pass. Item identity uses `GetBaseSpellID`; linked managed aura state is never inspected.

A complete readable generation covering all four selected viewers may prune unseen items. Missing, inaccessible, or unreadable viewers/pools are incomplete evidence and cannot authorize pruning. During combat, only observed items and existing alerts are reused.

## Rendering

Frame state is held in weak-key addon tables. The addon creates its own `ActionButtonSpellAlertTemplate` child and never joins or patches `ActionButtonSpellAlertManager`.

Show/hide is idempotent. Visibility, animation, and geometry readiness are tracked separately. Every current render target owns at most one size-change hook. A runtime generation token invalidates all cached geometry after global scale changes, including surfaces that were inaccessible at the time. Failed access, member lookup, hook, frame-level read/write, anchor, parent, or size operations remain dirty and retry on an authoritative lifecycle pass. Stable rescans reuse completed geometry without repeating mutations; inaccessible OFF transitions become owned pending hides. No polling is used.

## Settings and persistence

`SuddenDoomGlowDB` owns `enabled`, `cdm`, `debug`, `glowScale`, bounded target/signal lists, schema, and producer version. Migration runs once before Settings registration. Blizzard's Settings UI writes ordinary fields through `RegisterAddOnSetting`; addon callbacks apply idempotent runtime effects.

Future schemas are preserved unchanged and disable all mutation. Frames, timers, callback owners, hooks, event signals, resolved families, and observed override relationships remain runtime-only.

## Code map

| Area | Owner |
|---|---|
| Runtime, persistence, rendering, integrations | `Core.lua` |
| Blizzard Settings | `Options.lua` |
| Diagnostics | `Debug.lua` |
| Source contracts | `docs/API_CONTRACTS.md` |
| External implementation evidence | `docs/DONOR_REVIEW.md` |
| Broad/focused host regressions | `tests/runtime_smoke.lua`, `tests/runtime_regression.lua` |
| Deterministic package | `scripts/package.py` |
