# API contracts and source-coupled integrations

## Evidence pins

Knowledge-base policy is read from `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`. Its selected source is Retail `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`.

Current live source was rechecked at `Gethe/wow-ui-source@297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, Retail `12.1.5.70783`, on `2026-11-03`. The complete one-commit `70688 → 70783` delta changes Battle.net, Roleset, TextureUtils, Unit-event metadata, friends/chat presentation, and `version.txt`; it does not change the ActionBar, Spell Activation Overlay, alert-template, or Cooldown Viewer files used by this addon.

This is source evidence only. Client build, taint, runtime access, combat behavior, rendering, and performance remain **NOT-RUN**.

## Generated public contracts

`SpellActivationOverlayDocumentation.lua` defines:

- `C_SpellActivationOverlay.IsSpellOverlayed(spellID)` with `SecretArguments = AllowedWhenUntainted` and a boolean result;
- synchronous `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(spellID)` and `...GLOW_HIDE(spellID)` events.

`ActionBarFrameDocumentation.lua` defines `C_ActionBar.GetSpell(actionID)` under its caller policy. For one observed button's current ordinary assignment, this is the primary lookup. An ordinary result with no valid spell may fall back to `GetActionInfo`; macro actions use `GetMacroSpell`. Failure or inaccessibility stays unknown and does not authorize another guess.

Access gates precede comparison, nil/type tests, conversion, table keys/indexes, formatting, logging, persistence, or deferred capture.

Pinned current files:

- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellActivationOverlayDocumentation.lua`
- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua`
- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua`

## Alert-template implementation boundary

The addon creates `ActionButtonSpellAlertTemplate` and uses its `ProcStartAnim` and `ProcLoop` children. These names are private UI implementation evidence, not a generated third-party extension API. The addon owns its child and does not join or patch Blizzard's global alert manager.

Pinned current files:

- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml`
- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.lua`

## Cooldown Viewer boundary

The generated contract supplies synchronous `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`, and `COOLDOWN_VIEWER_TABLE_HOTFIXED` events. The selected implementation supplies four viewer frames, `CooldownViewerMixin:OnAcquireItemFrame`, active `itemFramePool` objects, and item lifecycle methods `SetCooldownID`, `SetOverrideSpell`, `ClearCooldownID`, and `ResetCooldownData`. The events are public; the viewer, pool, and item method names are source-coupled private implementation details.

The adapter therefore:

- post-hooks actual instances once;
- performs new hook attachment and pool enumeration only outside combat and retries on the public data-ready event;
- reads only configured `GetBaseSpellID` identity;
- clears on proved reset/reassignment;
- access-gates external pool tables and prunes only from a complete readable generation covering all four selected viewers;
- keeps proc events on the already tracked set and never enumerates pools from the hot path.

Pinned current files:

- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua`
- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua`
- `Gethe/wow-ui-source@297d7aa:Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml`

## Runtime status

Expected interface is `120105`. No named-client `GetBuildInfo()` record or live matrix is attached to this release. See `VALIDATION.md` and `docs/LIVE_TEST_CHECKLIST.md`.
