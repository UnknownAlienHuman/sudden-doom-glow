# Architecture

Release `1.4.0` targets Retail 12.1.5 with expected TOC interface `120105`. Source was checked on 2026-11-02 at `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`; live client behavior is **NOT-RUN**. See [API contracts](docs/API_CONTRACTS.md).

## Runtime flow

```mermaid
flowchart TD
    Login[PLAYER_LOGIN] --> Family[Build configured spell families]
    Family --> Mapping[Find candidate action slots and map buttons]
    Login --> Viewer[Attach Cooldown Viewer instance hooks]
    Overlay[Overlay SHOW or HIDE] --> Arbitration[Query and event arbitration]
    Query[IsSpellOverlayed] --> Arbitration
    Override[Cooldown Viewer spell override] --> Family
    Arbitration --> State[Desired glow state]
    Mapping --> Render[Addon-owned alert]
    Viewer --> Render
    State --> Render
    Combat[Combat lockdown] --> Deferred[Defer structural changes]
    Deferred --> Mapping
```

## Detection

The detection authority is the Spell Activation Overlay event/query pair. `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` and `...GLOW_HIDE` wake reconciliation; `C_SpellActivationOverlay.IsSpellOverlayed` supplies current state when its caller and inputs are allowed. The addon keeps each event spell independent, treats incomplete query evidence as unknown, and uses a bounded fallback when the query is unavailable.

`targetRoots` comes from defaults and SavedVariables. `targetFamily` expands configured roots with base and override relationships and explicit Cooldown Viewer override events. `signalFamily` includes configured overlay aliases used for detection. A signal alias does not by itself become an action-button target.

## Action buttons

`C_ActionBar.FindSpellActionButtons` discovers candidate slots for each base spell. The addon reads the spell from an observed slot with `C_ActionBar.GetSpell`, with resolved macro spell support through the current macro API. A physical button is rendered only after its current assignment is readable and still belongs to the configured target family. Main/pageable action buttons and supported third-party bars prepare alerts before combat; static multibars allocate alerts only for matching spells. Named buttons remain discoverable for future assignment changes. Deep frame enumeration is manual.

## Cooldown Viewer

When enabled, the addon observes the actual four configured viewer instances, reconciles their active item pools at setup/recovery boundaries, and hooks each observed item instance's assignment/reset methods. Item identity is evaluated through `GetBaseSpellID`; `GetSpellID` can select managed aura identity and is not used for this match. Overlay events update the already tracked item set; they do not trigger pool enumeration.

These viewer member names and frame pools are source-coupled implementation details. See [API contracts](docs/API_CONTRACTS.md) for exact pins and the extension boundary.

## Rendering and ownership

Weak-key tables hold addon metadata; external frames do not receive addon fields. The addon creates an alert child using Blizzard's `ActionButtonSpellAlertTemplate`, then controls its animation and visibility. This template and its named animation children are private UI implementation details, not a public extension contract.

Alert creation, parenting, sizing, and anchoring happen outside combat. In combat, existing addon-owned presentation is shown or hidden only. A stale or unreadable assignment cannot authorize a new button glow.

## Persistent data

`SuddenDoomGlowDB` stores user settings and `schemaVersion`. Frame maps, event signals, timers, explicit current-session overrides, and resolved spell families remain runtime-only.

## Code map

| Area | Main code |
|---|---|
| SavedVariables migration and options | `InitializeDB`, `GetOption`, `SetOption` in `Core.lua` |
| Secret/access boundary | `IsAccessible`, `SafeNumber`, `FrameCanBeUsed` in `Core.lua` |
| Spell family and override handling | `RebuildSpellFamilies`, `IsTargetFamilySpell`, `LearnExplicitOverride` in `Core.lua` |
| Action slot and button mapping | `GetActionSpellID`, `ScanActionSlots`, `GetButtonSlot`, `MapNamedButtons` in `Core.lua` |
| Glow ownership | `GetFrameState`, `EnsureAlert`, `ShowFrameGlow`, `HideFrameGlow` in `Core.lua` |
| Cooldown Viewer | `CDMFrameMatches`, `ReconcileCDMFrames`, `HookCDMItem` in `Core.lua` |
| Signal arbitration | `QueryOverlayState`, `SetEventSignal`, `ReconcileGlow` in `Core.lua` |
| Settings UI | `Options.lua` |
| Diagnostics window and logging | `Debug.lua` |

The static checker and smoke harness are described in [tests/README.md](tests/README.md). The historical [1.3.1 release note](docs/RELEASE_1.3.1.md) remains historical.
