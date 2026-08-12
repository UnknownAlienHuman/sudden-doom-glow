# SuddenDoomGlow

Refactored addon for Unholy DK proc highlight:
- Tracks **Sudden Doom** aura (`spellID 450932` + legacy `81340` by default, configurable via `/sdglow aura <id>`).
- Highlights action buttons that cast:
  - Death Coil (`47541`)
  - Epidemic (`207317`)
  - Necrotic Coil (`1242174`)

**Version:** 1.2.2
**Interface:** 120001, 120005
**SavedVariables:** `SuddenDoomGlowDB`
**Optional dependency:** Blizzard_CooldownManager
**CurseForge:** [Sudden Doom Glow (Death Coil / Epidemic)](https://www.curseforge.com/wow/addons/sudden-doom-glow-death-coil-epidemic)

## Preview

![Sudden Doom proc glow on an action button](https://media.forgecdn.net/attachments/1511/788/screenshot-2026-02-02-231126-png.png)

Screenshot from the [CurseForge gallery](https://www.curseforge.com/wow/addons/sudden-doom-glow-death-coil-epidemic).

## Install

Copy `SuddenDoomGlow` to `World of Warcraft/_retail_/Interface/AddOns/`, enable it, and reload the UI.

## Detection model
1. Aura-first (`C_UnitAuras.GetPlayerAuraBySpellID`) is authoritative in and out of combat.
2. Overlay signal is a secondary fallback path; overlay flags have TTL cleanup to prevent stale stuck glow.
3. In combat, a conservative runic-cost fallback is used as tertiary signal (`Death Coil`/`Epidemic` cost drop).
4. `UNIT_SPELLCAST_SUCCEEDED` triggers short delayed aura refreshes (0 + 0.06 + 0.14), no force-off hacks.

## Refactor notes
- Event loop uses direct frame registration (`SetScript`, `RegisterEvent`, `RegisterUnitEvent`) without `pcall` wrappers.
- `COMBAT_LOG_EVENT_UNFILTERED` fallback is disabled in this build due protected-call blocks on some clients.
- Glow rendering uses addon-local `ActionButtonSpellAlertTemplate` overlays (combat-safe, no manager calls).
- Restored glow rendering on Blizzard Cooldown Viewer item frames with stable pooling + idempotent show/hide.
- Button mapping is action-slot first, now seeded by `C_ActionBar.FindSpellActionButtons` + runtime override spell resolution.
- Auto deep-scan on login is removed to avoid false button captures.
- Render path is idempotent (no animation restarts when state is unchanged).

## Commands
- `/sdglow status`
- `/sdglow debug`
- `/sdglow aura <spellID>`
- `/sdglow spell <spellID>`
- `/sdglow spells`
- `/sdglow auras [filter]`
- `/sdglow rescan [deep]`
- `/sdglow test`
- `/sdglow cdm on|off`
- `/sdglow on|off`

Compatibility notes:
- `/sdglow learn` is deprecated in this refactor.
- `Graveyard` is resolved from the live `Epidemic` override path instead of a hardcoded spellID.

## Current development status

The listed refactor and v1.2.2 hardening work are complete in the repository snapshot. Remaining work is live in-game validation: proc timing and duration, override paths, stacks, combat Cooldown Viewer rendering, remaps/paging, and performance. See [TODO.md](TODO.md).

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
