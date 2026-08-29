# Sudden Doom Glow

A focused Retail addon for Unholy Death Knights. It mirrors the **Sudden Doom** proc glow onto every current Death Coil/Epidemic action and the corresponding Blizzard Cooldown Viewer item, including live spell replacements.

- **Version:** 1.3.1
- **Retail interface:** `120100` (12.1.0)
- **SavedVariables:** `SuddenDoomGlowDB`
- **Optional dependency:** `Blizzard_CooldownViewer`

## Why 1.3 is different

Retail 12.1 is no longer a safe environment for generic combat aura scans. Sudden Doom Glow therefore does not reconstruct the proc from `UNIT_AURA`, combat log payloads, runic-power cost changes, or a polling loop.

The runtime contract is:

```text
SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE
            +
C_SpellActivationOverlay.IsSpellOverlayed
            ↓
conservative signal arbitration
            ↓
addon-owned, idempotent glow overlays
            ↓
action buttons + Blizzard Cooldown Viewer items
```

The event is the low-latency wake-up. The official overlay query is the state authority whenever every candidate is readable. A short SHOW grace handles synchronous event/query ordering; an event-only fallback is bounded to 30 seconds when the query surface is unavailable. A readable all-false query turns the glow off.

## Spell replacement handling

Configured roots are expanded through `C_Spell.GetBaseSpell` and `C_Spell.GetOverrideSpell`. The addon also consumes the explicit 12.1 `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED` pair. This covers current and hotfixed replacements such as Necrotic Coil without learning arbitrary spell IDs from a coincidentally reused action slot.

Defaults:

- Death Coil — `47541`
- Epidemic — `207317`
- Necrotic Coil — `1242174`
- Sudden Doom signal family — `450932`, legacy `81340`, plus the resolved action family

## Rendering and combat safety

- The addon owns its alert frames; it does not mutate `ActionButtonSpellAlertManager`.
- Alerts are created and resized outside combat, then only shown or hidden in combat.
- Current action slots are revalidated before every show, preventing stale highlights after paging or state-driver changes.
- Frame metadata is stored in addon-owned weak-key tables rather than on Blizzard or bar-addon frames.
- Cooldown Viewer integration hooks pool/item lifecycle methods once; there is no recurring viewer scan or ticker.
- A failed/inaccessible CDM pool pass never prunes previously valid frames.

Supported named action-button families include Blizzard bars, ElvUI, Bartender4, and Dominos. `/sdglow rescan deep` is available for an unknown bar implementation and is never run automatically.

## Commands

```text
/sdglow status
/sdglow debug
/sdglow rescan [deep]
/sdglow test
/sdglow spell <spellID>
/sdglow signal <spellID>
/sdglow spells
/sdglow cdm on|off
/sdglow on|off
```

`/sdglow aura <spellID>` remains as a compatibility alias for `/sdglow signal`.

## SavedVariables migration

Version 1.3 uses schema migration instead of wiping the database on each addon update. Existing enable/debug/CDM settings and unrelated user fields are preserved. Legacy `procSpellIDs` and `auraIDs` are migrated into `targetSpellIDs` and `signalSpellIDs`.

## Verification

Repository checks cover:

- Lua syntax;
- absence of legacy aura/cost/CLEU/polling paths;
- database migration without a destructive wipe;
- duplicate event idempotence;
- simultaneous overlay IDs;
- SHOW/query synchronization and grace expiry;
- unavailable-query TTL fallback;
- explicit hotfixed overrides;
- stale action-slot rejection;
- Cooldown Viewer frame acquisition and reset.

Run:

```bash
python tests/static_checks.py .
lua tests/runtime_smoke.lua Core.lua
```

Target-client combat validation remains required after Blizzard hotfixes. See [`TODO.md`](TODO.md).

## Install

Copy the `SuddenDoomGlow` directory into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Then enable the addon and reload the UI.

## License

MIT. See [`LICENSE`](LICENSE).
