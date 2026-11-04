# API contracts and source-coupled integrations

## Evidence pins

- Knowledge base: `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`
- KB-selected UI source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, checked 2026-11-04

The complete `70688 → 70783` delta does not change the ActionBar, Spell Activation Overlay, Settings, alert-template, or Cooldown Viewer slices used here. This is source evidence, not live-client proof.

## Public contracts

`SpellActivationOverlayDocumentation.lua` defines:

- `C_SpellActivationOverlay.IsSpellOverlayed(spellID)` with `SecretArguments = AllowedWhenUntainted`;
- synchronous `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(spellID)` and `...GLOW_HIDE(spellID)`.

`ActionBarFrameDocumentation.lua` defines `C_ActionBar.GetSpell(actionID)` under its caller policy. A failed or inaccessible lookup remains unknown. The fallback is limited to the current observed action and resolved `GetMacroSpell`; macro text is never parsed.

The generated Cooldown Viewer contract defines synchronous data-loaded, spell-override, and table-hotfix events. Blizzard Settings exposes `RegisterAddOnSetting`, and `SettingMixin` emits value callbacks after the authoritative field write.

All secret-capable values are gated before comparison, type/nil tests, conversion, formatting, indexing, storage, logging, or deferral.

## Private implementation boundaries

### Alert template

The addon creates an addon-owned child from `ActionButtonSpellAlertTemplate` and uses `ProcStartAnim`/`ProcLoop`. These are source-verified private UI details, not a generated extension API. The addon does not mutate Blizzard's alert manager.

### Cooldown Viewer

The selected source supplies four viewer instances, active `itemFramePool` objects, `OnAcquireItemFrame`, and item lifecycle methods (`SetCooldownID`, `SetOverrideSpell`, `ClearCooldownID`, `ResetCooldownData`). The adapter:

- hooks actual instances once and only outside combat;
- enumerates pools only for bounded setup/recovery;
- reads configured `GetBaseSpellID` only;
- clears on proved reset/reassignment;
- prunes only from a complete readable generation;
- keeps proc events on the already tracked set.

### Settings

`enabled`, `cdm`, `debug`, and `glowScale` are ordinary fields, so `Options.lua` uses `Settings.RegisterAddOnSetting`. Migration, validation, normalization, and runtime effects remain in `Core.lua`. Proxy settings are intentionally absent.

## Runtime status

Expected interface is `120105`. Exact Lua 5.1 host checks are recorded in `VALIDATION.md`. Named-client combat, taint, rendering, and performance remain **NOT-RUN**.
