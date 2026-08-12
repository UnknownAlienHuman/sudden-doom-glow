# Code index

| Area | Exact anchors |
| --- | --- |
| DB and caches | [`Core.lua`](Core.lua): `GetAddonVersion`, defaults, `BuildProcCaches`, `RebuildAuraIDSet` |
| Button mapping | `GetButtonActionSlot`, `ScanActionSlots`, `MapButtonsFromNamedBars`, `RescanButtons`, `RequestRescan` |
| Aura/signals | `SetAuraState`, `ScanAuraFull`, `HasOverlayProc`, `HasProcViaCost`, `UpdateFromSignals` |
| Rendering | `EnsureSDGAlert`, `StartProc`, `StopProc`, `SafeShowGlow`, `SafeHideGlow`, `ApplyGlowState`, `SetGlow` |
| Events/login | `SDG:OnLogin`, `SDG:RegisterRuntimeEvents`, local `OnEvent`, `EventRegistry` callback |
| User/debug | `SlashCmdList["SUDDEN_DOOM_GLOW"]` in [`Core.lua`](Core.lua), `SDG.Debug:CreateDebugFrame` in [`Debug.lua`](Debug.lua) |

`SuddenDoomGlowDB` is the only persistent contract; all `SDG.*` caches are runtime-only.
