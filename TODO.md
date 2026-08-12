# SuddenDoomGlow TODO (refactor pass)

## Done
- [x] Rebuilt `Core.lua` around modular blocks (`Buttons`, `Aura`, `Signals`, `Render`, `Events`).
- [x] Replaced fragile metatable-based event registration with direct `frame:RegisterEvent/RegisterUnitEvent` + `frame:SetScript("OnEvent")`.
- [x] Removed `pcall`-based event registration wrapper that produced `UNKNOWN()` protected-call violations on some clients.
- [x] Switched to aura-first proc state (`GetPlayerAuraBySpellID` + `GetAuraDataByIndex`) with conservative combat-only cost fallback.
- [x] Removed combat readability gate for aura authority: aura API is now authoritative both in and out of combat.
- [x] Added combat-safe aura fallback via `COMBAT_LOG_EVENT_UNFILTERED` (`SPELL_AURA_*`) when aura API read fails.
- [x] Hotfix: disabled `COMBAT_LOG_EVENT_UNFILTERED` registration in runtime path for compatibility with clients where this call is blocked for the addon.
- [x] Re-enabled overlay fallback as secondary signal even when aura API is readable; added TTL cleanup to prevent stale stuck glow on missed hide events.
- [x] Reworked `UNIT_SPELLCAST_SUCCEEDED` path to triple short aura refresh (0 + 0.06 + 0.14), without forced off.
- [x] Switched glow renderer to addon-local `ActionButtonSpellAlertTemplate` overlays only (removed manager path that caused protected-call errors in combat).
- [x] Restored CDM pooled-frame glow rendering with stable pool refresh + idempotent show/hide.
- [x] Tightened button mapping to action-slot first; removed slotless heuristics that caused wrong glows.
- [x] Removed automatic deep frame scan on login; replaced with delayed normal rescans to avoid false button matches.
- [x] Fixed action-button callback attach/re-attach path and combat-safe tracked-button retention (no in-combat removals).
- [x] Made glow show/hide idempotent.
- [x] Kept deferred rescan in combat while preserving event processing in combat.

- [x] Fixed action-slot resolver: prefer GetAttribute("action")/ActionButton_GetPagedID to handle paging/stance/vehicle correctly (prevents empty/wrong button glow after bar swaps).
- [x] Added SavedVariables wipe on addon version bump (DB reset) to avoid stale mappings persisting across updates.

- [x] Combat-safe render validation: re-check current action-slot before showing glow (prevents wrong/empty button glow when paging/stance swaps happen in combat).
- [x] Coalesced rescan triggers (bindings/talents/page changes) into a single delayed rescan to reduce slot-scan spam.
- [x] Aura scan fast-path: skip full index scan when GetPlayerAuraBySpellID is available+operational to reduce UNIT_AURA overhead.
- [x] Added current + legacy Sudden Doom aura defaults (`450932`, `81340`) without forcing another DB wipe.
- [x] Reworked proc spell cache to resolve live override spell variants (`C_Spell.GetOverrideSpell`) and seed slots from `C_ActionBar.FindSpellActionButtons`.
- [x] Added `UPDATE_OVERRIDE_ACTIONBAR` rescan path for live spell swaps on the same button.
- [x] Added slash helpers for proc spell IDs (`/sdglow spell`, `/sdglow spells`) to handle future hotfix churn without code edits.

## Next validation in game
- [ ] In combat proc: glow appears immediately (no wait for leaving combat).
- [ ] Single proc: glow ON for full aura duration, OFF on aura end.
- [ ] Current Midnight Sudden Doom buff resolves as `450932` on live affected clients.
- [ ] Forbidden Knowledge / APEX path: Death Coil button -> Necrotic Coil (`1242174`) still glows from the same proc logic.
- [ ] Graveyard path resolves from Epidemic override without hardcoded spellID regressions.
- [ ] Two stacks: after first cast glow remains ON if one stack remains.
- [ ] Consume with no stacks left: no residual glow for several seconds.
- [ ] CDM mirrors glow in combat reliably with no random misses.
- [ ] No wrong/stuck action button glow after action bar remaps.
- [ ] Combat paging: swap pages/stance/vehicle while proc active -> glow follows the correct button, never an empty slot.
- [ ] Performance: no noticeable hitching when swapping pages or talents (rescan coalescing).


## 1.2.2 (audit hardening)
- Hardened Runic Power cost detection against secret values (SafeNumber)
- Improved action-slot candidate resolution (avoid button-index vs slot-index mixups)
- Kept combat-safe slot revalidation before showing glow
