# API contracts and source-coupled integrations

## Evidence pin

Reviewed against `Gethe/wow-ui-source@d07eb00237d8891f153215db98a5df880a26cfe5`, Retail build `12.1.5.70688`, on `2026-11-03`. The current `live` branch head matched this commit. This is source evidence; the current client build, taint behavior, runtime access, rendering, and combat behavior are **NOT-RUN**.

## Generated public API contracts

The generated `SpellActivationOverlayDocumentation.lua` defines:

- `C_SpellActivationOverlay.IsSpellOverlayed(spellID)` with a required numeric `spellID`, a non-nil boolean result, and `SecretArguments = "AllowedWhenUntainted"`.
- `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` and `SPELL_ACTIVATION_OVERLAY_GLOW_HIDE` as synchronous events, each carrying a non-nil numeric `spellID`.

The generated `ActionBarFrameDocumentation.lua` defines:

- `C_ActionBar.GetSpell(actionID)` with a `luaIndex` action ID, a non-nil numeric spell ID result, and `SecretArguments = "AllowedWhenUntainted"`.

For an observed button's current assignment, `C_ActionBar.GetSpell(actionID)` is the primary slot-to-spell lookup. If the function is unavailable or an ordinary result contains no valid spell ID, the fallback reads `GetActionInfo`; for a macro action, `GetMacroSpell` resolves its spell. A failed or inaccessible query stays unknown and does not authorize fallback matching.

Use the exact caller/access policy for every query and gate secret-capable values before Lua comparison, conversion, indexing, formatting, storage, or deferral. The `GetActionInfo` fallback is scoped to an observed button's current assignment; it is not a slot-discovery API.

Pinned generated docs:

- [SpellActivationOverlayDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellActivationOverlayDocumentation.lua)
- [ActionBarFrameDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/ActionBarFrameDocumentation.lua)
- [FrameScriptDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua)
- [ActionButton.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)

## Source-coupled visual details

The addon creates `ActionButtonSpellAlertTemplate` and uses its `ProcStartAnim` and `ProcLoop` children. Blizzard's selected implementation calls the animations directly and wires start completion to the loop. This confirms the implementation for this source pin, but the template and child names are not generated addon APIs. They remain source-coupled and require client validation.

Pinned source:

- [ActionButtonSpellAlerts.xml](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.xml)
- [ActionButtonSpellAlerts.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButtonSpellAlerts.lua)

## Cooldown Viewer adapter boundary

The integration observes the actual configured viewer instances, their active item pools during setup/recovery, and item lifecycle methods on each actual item instance. The selected source confirms `CooldownViewerMixin:OnAcquireItemFrame` in `CooldownViewer.lua` and item methods `SetCooldownID`, `SetOverrideSpell`, `ClearCooldownID`, and `ResetCooldownData` in `CooldownViewerItemData.lua`. These are private UI implementation details, not generated extension APIs.

For identity, the adapter reads only `GetBaseSpellID`, which represents the configured base spell. It does not read `GetSpellID`: in this source, that value may prefer the linked managed aura spell. Overlay events touch the existing tracked item set; pool enumeration remains limited to setup/recovery.

The pinned native XML gives each viewer a fixed item template. Essential, Utility, and Buff Icon items have an `Icon` texture; Buff Bar items have a permanent child `Icon` frame. Item reuse resets data on the pooled item and does not replace that child. The addon places only its own alert child on the selected render target.

Pinned source:

- [CooldownViewer.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.lua)
- [CooldownViewerItemData.lua](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewerItemData.lua)
- [CooldownViewer.xml](https://github.com/Gethe/wow-ui-source/blob/d07eb00237d8891f153215db98a5df880a26cfe5/Interface/AddOns/Blizzard_CooldownViewer/CooldownViewer.xml)

## Current-client status

The source pin was checked on `2026-11-03`; expected interface family is `120105`. No named client `GetBuildInfo()` record or live test matrix has been captured. Runtime compatibility and all client-dependent behaviors remain **NOT-RUN**.

Reference knowledge base: https://github.com/UnknownAlienHuman/wow-addon-engineering-kb
