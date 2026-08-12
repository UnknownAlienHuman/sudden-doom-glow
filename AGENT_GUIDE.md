# SuddenDoomGlow agent guide

## Start here

Read [`SuddenDoomGlow.toc`](SuddenDoomGlow.toc), then [`Core.lua`](Core.lua) in this order: DB/defaults, proc caches, action-button mapping, aura scan, signal arbitration, render, runtime events, slash commands. [`Debug.lua`](Debug.lua) is loaded second and only adds the on-demand debug frame.

TOC release metadata is `1.2.2` (`SuddenDoomGlow.toc`, `## Version`).

## Load order and execution path

Complete `loadedFiles` inventory (root `docs/addon-architecture.json`, in execution order):

```text
Core.lua
Debug.lua
```

The TOC loads `Core.lua` then `Debug.lua`. The only declared optional dependency is `Blizzard_CooldownManager`; the core also discovers `EssentialCooldownViewer`, `UtilityCooldownViewer`, and `BuffIconCooldownViewer` when present. `Core.lua` initializes `SuddenDoomGlowDB`, resets it on TOC metadata version change, builds configured proc spell variants (including `C_Spell.GetOverrideSpell`), and registers `PLAYER_LOGIN` immediately.

At login `SDG:OnLogin` records class/GUID, builds proc/aura sets, idles non-DKs, and for Death Knights registers runtime events, action-button callbacks, action-slot rescans, baseline runic costs, aura scan, and optional CDM discovery. The runtime signal path is `ScanAuraFull` (primary) OR `HasOverlayProc` (secondary TTL signal) OR `HasProcViaCost` (combat-only tertiary fallback) -> `UpdateFromSignals` -> `SetGlow` -> `ApplyGlowState` -> local `ActionButtonSpellAlertTemplate` overlays on tracked action buttons and active CDM frames.

Action mapping is action-slot-first: `C_ActionBar.FindSpellActionButtons`/`GetActionInfo`/macro inspection populate `trackedSlots`; known bars and optional deep frame enumeration map physical buttons. `RequestRescan` coalesces page/binding/talent/spec/addon-load bursts and defers protected mutation in combat.

## State and surfaces

- SavedVariables: `SuddenDoomGlowDB`; metadata version `__version`; settings `enabled`, `debug`, `cdm`, `auraEnabled`, `overlayEnabled`, `costEnabled`, numeric `auraIDs`, numeric `procSpellIDs`, and mapped `slots`.
- Runtime state is on global `SuddenDoomGlow`: proc caches, tracked buttons/slots, CDM frames, aura authoritative/read-failed state, dormant CLEU fallback fields, glow/detection state, timers and rescan flags.
- Slash: `/sdglow status|dump`, `debug`, `aura <spellID>`, `spell <spellID>`, `spells`, `auras [filter]`, `rescan [deep]`, `test`, `cdm on|off`, `on`, `off`.
- Debug UI is created by `/sdglow debug`; it can clear logs, request deep rescan, force a test glow, and toggle aura/overlay signals.

## Dependencies and relationships

Blizzard action bars, spell/aura APIs, `EventRegistry.ActionButton.OnActionChanged`, and optional Cooldown Manager viewers are the runtime surfaces. Rendering is addon-local; do not replace it with calls into CDM. No checked-in addon consumes the `SuddenDoomGlow` global. The old `/sdglow learn` behavior is not present in this code path.

## Change routing

- DB/defaults/version and configured spell/aura sets: top of [`Core.lua`](Core.lua); preserve version-reset semantics.
- Mapping/rescan and combat-safe protected-frame behavior: `GetButtonActionSlot`, `ScanActionSlots`, `MapButtonsFromNamedBars`, `RescanButtons`, `RequestRescan`.
- Aura authority/fallback: `SetAuraState`, `ScanAuraFull`, and the dormant `HandleCombatLogAuraEvent` helper; keep safe numeric/secret guards. This snapshot does **not** register `COMBAT_LOG_EVENT_UNFILTERED`, so the helper is not a live event path unless registration is deliberately added and verified.
- Signal arbitration and glow rendering: `HasOverlayProc`, `HasProcViaCost`, `UpdateFromSignals`, `SetGlow`, `ApplyGlowState`, `EnsureSDGAlert`, `StartProc`, `StopProc`.
- Runtime event routing: `RegisterRuntimeEvents` and local `OnEvent`; update both registration and dispatch when adding events.
- User commands/debug controls: bottom of [`Core.lua`](Core.lua) and [`Debug.lua`](Debug.lua).

## Invariants and risks

- Aura is authoritative when the API is operational; nil from an operational spell-ID lookup means inactive. CLEU fields/helper exist only as an unregistered fallback scaffold in this snapshot and cannot be treated as a live signal. Do not turn overlay/cost into a force-off path.
- Glow state is idempotent; do not restart animations or create overlays on every event. Never mutate protected action-button structures in combat.
- `trackedSlots` must be validated against current paging/state before showing a glow; wrong slot mapping is worse than no glow.
- `C_Timer` rescan/update timers and CDM watcher must be cancelled/stopped on state changes; preserve coalescing and TTL (`OVERLAY_SIGNAL_TTL = 20`).
- Secret spell IDs, aura fields, action IDs and combat-protected frame APIs require `pcall`/`IsSecret` boundaries already present in code.
- The addon is DK-specific: non-Death-Knight behavior intentionally idles after login.

## Verification

1. Verify TOC order and optional dependency metadata; parse Lua.
2. In-game on a Death Knight: `/reload`, `/sdglow status`, `/sdglow spells`, `/sdglow auras`, and `/sdglow test`.
3. Exercise aura gain/loss and stacks, overlay show/hide, action paging/bindings/talent/spec changes, combat transitions and CDM viewer load.
4. Test `/sdglow rescan` and `/sdglow rescan deep` out of combat; verify deferral and recovery in combat.
5. Confirm glows on Blizzard and supported bar-mod buttons, no duplicate animations, no wrong-button glow, no Lua/taint errors, and no stale glow after overlay TTL.
6. Verify non-DK login remains idle and DB version bump resets stale mappings.

## Uncertain or version-sensitive claims

Cooldown Viewer frame pools, `EventRegistry.ActionButton.OnActionChanged`, override-spell IDs, action-button template names, and secret-value behavior are patch-sensitive. `COMBAT_LOG_EVENT_UNFILTERED` is not registered by this snapshot; treat `HandleCombatLogAuraEvent` as dormant code, not a live CLEU event path.
