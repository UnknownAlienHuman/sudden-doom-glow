# Architecture

## Runtime flow

```text
PLAYER_LOGIN
  -> DK gate
  -> schema migration
  -> spell-family expansion
  -> action-slot/button mapping
  -> Cooldown Viewer lifecycle hooks

SHOW/HIDE event or official query wake-up
  -> signal arbitration
  -> desired boolean glow state
  -> idempotent addon-owned rendering
```

## Detection boundary

The addon does not consume general aura state. The only proc-state surface is Blizzard's Spell Activation Overlay contract:

- `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW`
- `SPELL_ACTIVATION_OVERLAY_GLOW_HIDE`
- `C_SpellActivationOverlay.IsSpellOverlayed`

A query `true` is sufficient for ON. A query `false` is sufficient for OFF only when all configured candidates were readable. Relevant event state bridges synchronous ordering and temporary query unavailability, with a short grace and a hard TTL.

## Spell identity

`targetRoots` comes from SavedVariables/defaults. `targetFamily` is runtime-only and contains roots, base spells, current overrides, and explicit Cooldown Viewer override events. A spell discovered on an action/CDM frame is accepted only when `GetBaseSpell` or a current root override proves the relationship.

`signalFamily` is the target family plus configured overlay aliases. Signal aliases affect detection only; they are never treated as action-button targets.

## Surfaces

Action buttons are mapped slot-first. Physical frames are only render targets after the current slot is revalidated. Structural discovery and alert creation are deferred in combat.

Cooldown Viewer frames are observed through current 12.1 lifecycle methods. Their aura internals are not read, hooked, or inferred. Pool enumeration is used only for initial/recovery reconciliation, not as a ticker.

## Ownership

All runtime metadata is stored in weak-key addon tables. External frames are not modified with `__SDG` fields. The addon creates its own `ActionButtonSpellAlertTemplate` child and never enters Blizzard's global alert-manager state.

## Persistent contract

`SuddenDoomGlowDB` stores user configuration and `schemaVersion`. Runtime frame maps, events, timers, explicit current-session overrides, and resolved spell families are never persisted.
