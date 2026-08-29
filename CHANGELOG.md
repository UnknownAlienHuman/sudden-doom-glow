# Changelog

## 1.3.1 — 2026-08-29

### Retail 12.1 migration

- Targeted Interface `120100` and corrected the optional addon name to `Blizzard_CooldownViewer`.
- Replaced aura scanning, combat-log reconstruction, and runic-cost inference with the official Spell Activation Overlay event/query contract.
- Removed all recurring proc/CDM polling.

### Signal correctness

- Added conservative query arbitration: any readable `true` enables the glow; OFF is authoritative only when every configured candidate is readable and false.
- Added a short synchronous SHOW grace and a mandatory post-grace reconciliation.
- Added a bounded 30-second event fallback only when the official query is unavailable.
- Kept simultaneous overlay IDs independent so one HIDE cannot clear another active signal.
- Treated unrelated overlay events only as delayed query wake-ups, never as Sudden Doom evidence.

### Spell and button mapping

- Built a dynamic Death Coil/Epidemic family through `GetBaseSpell`, `GetOverrideSpell`, and `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`.
- Prevented arbitrary spell learning from stale or coincidental action slots.
- Revalidated the current action slot immediately before every action-button glow.
- Coalesced mapping updates and deferred structural work during combat.

### Rendering and Cooldown Viewer

- Kept all glow ownership inside the addon and made animation transitions idempotent.
- Moved runtime metadata into weak-key tables instead of writing fields onto external frames.
- Created/resized alert frames only outside combat.
- Hooked Cooldown Viewer acquire/set/reset lifecycle paths once instead of running a ticker.
- Added conservative all-pools-readable pruning and geometry re-prime after layout changes.
- Added Buff Bar icon-target handling.

### Persistence and diagnostics

- Replaced version-based SavedVariables wiping with schema migration.
- Split the debug logger from the debug UI namespace.
- Added static policy checks and a stubbed runtime harness.

## 1.2.2

- Hardened the previous aura-first implementation against secret values and action-slot mismatches.
- This architecture is superseded by 1.3.1 for Retail 12.1.
