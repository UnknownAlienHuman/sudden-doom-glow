# Architecture

The TOC loads [`Core.lua`](Core.lua) before [`Debug.lua`](Debug.lua) and declares only optional `Blizzard_CooldownManager`. Core DB/defaults and proc caches feed action-slot mapping, aura scanning, signal arbitration, and local render overlays.

Runtime flow: `PLAYER_LOGIN` -> `SDG:OnLogin` -> DK-only event/callback registration -> `ScanAuraFull` + rescan -> `UpdateFromSignals` -> `SetGlow`/`ApplyGlowState`. Aura state is primary; overlay TTL and combat-only runic-cost checks are fallbacks. Action slots are mapped before physical buttons, and active CDM item frames are discovered opportunistically. `Debug.lua` adds an on-demand UI but does not own the state machine.

Persistent state is `SuddenDoomGlowDB`; all render caches and timers live on `SuddenDoomGlow`. CDM is an optional discovery surface, not a rendering API dependency.

The source contains `HandleCombatLogAuraEvent`/CLEU state fields as dormant fallback scaffolding, but `COMBAT_LOG_EVENT_UNFILTERED` is not registered in the current runtime event frame; the live authority path is `ScanAuraFull` plus overlay/cost fallbacks.
