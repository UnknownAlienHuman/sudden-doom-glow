# Code index

| Area | Primary anchors in `Core.lua` |
| --- | --- |
| SavedVariables migration | `InitializeDB`, `MergeNumericDefaults` |
| Secret/access boundary | `IsAccessible`, `SafeNumber`, `FrameCanBeUsed` |
| Spell family | `RebuildSpellFamilies`, `IsTargetFamilySpell`, `LearnExplicitOverride` |
| Action identity | `GetActionSpellID`, `SlotMatchesTarget`, `ScanActionSlots` |
| Physical buttons | `GetButtonSlot`, `MapNamedButtons`, `DeepMapButtons` |
| Glow ownership | `GetFrameState`, `EnsureAlert`, `ShowFrameGlow`, `HideFrameGlow` |
| Cooldown Viewer | `RefreshCDMFrame`, `ReconcileCDMFrames`, `AttachCDMHooks` |
| Signal arbitration | `QueryOverlayState`, `SetEventSignal`, `ReconcileGlow` |
| Combat-safe scheduling | `RequestRescan`, `QueueReconcile` |
| Runtime routing | `RegisterRuntimeEvents`, `OnEvent`, `SDG:OnLogin` |
| Commands | `SlashCmdList["SUDDEN_DOOM_GLOW"]` |
| Debug UI | `SDG:LogDebug`, `SDG.DebugUI` in `Debug.lua` |

`tests/static_checks.py` enforces the architectural exclusions. `tests/runtime_smoke.lua` exercises state transitions in a stubbed WoW runtime.
