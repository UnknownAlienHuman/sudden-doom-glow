# API contracts and source-coupled integrations

## Evidence pins

- Knowledge base: `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df`
- KB-selected UI source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, checked 2026-11-04

The complete `70688 → 70783` delta does not change the ActionBar, Spell Activation Overlay, Settings, alert-template, or Cooldown Viewer slices used here. This is source evidence, not live-client proof.

## Public contracts

`SpellActivationOverlayDocumentation.lua` defines:

- `C_SpellActivationOverlay.IsSpellOverlayed(spellID)` with `SecretArguments = AllowedWhenUntainted`;
- synchronous `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(spellID)` and `...GLOW_HIDE(spellID)`.

`ActionBarFrameDocumentation.lua` defines `C_ActionBar.GetSpell(actionID)` under its caller policy. A failed or inaccessible lookup remains unknown. The fallback is limited to the current observed action and resolved `GetMacroSpell`; macro text is never parsed.

The generated Cooldown Viewer contract defines synchronous data-loaded, spell-override, and table-hotfix events. Blizzard Settings exposes `RegisterAddOnSetting`, and `SettingMixin` emits value callbacks after the authoritative field write.

All secret-capable values are gated before comparison, type/nil tests, conversion, formatting, indexing, storage, logging, or deferral. Foreign object/table member discovery is also an access operation: the container/table is gated, indexing is isolated with `pcall`, the returned member is gated, and invocation has its own error boundary.

## Private implementation boundaries

### Alert template

The addon creates an addon-owned child from `ActionButtonSpellAlertTemplate` and uses `ProcStartAnim`/`ProcLoop`. These are source-verified private UI details, not a generated extension API. The addon does not mutate Blizzard's alert manager.

### Cooldown Viewer

The selected source supplies four viewer instances, active `itemFramePool` objects, `OnAcquireItemFrame`, and item lifecycle methods (`SetCooldownID`, `SetOverrideSpell`, `ClearCooldownID`, `ResetCooldownData`). The adapter:

- never reads a viewer, pool, item, or method through an unguarded foreign member access;
- hooks actual instances once and only outside combat;
- treats post-hook installation as a fallible foreign boundary, records success only after the hook is installed, and retries only on a later lifecycle pass;
- enumerates pools only for bounded setup/recovery;
- reads configured `GetBaseSpellID` only;
- clears on proved reset/reassignment;
- prunes only from a complete readable generation;
- keeps proc events on the already tracked set.

### Settings

`enabled`, `cdm`, `debug`, and `glowScale` are ordinary fields, so `Options.lua` uses `Settings.RegisterAddOnSetting`. Migration, validation, normalization, and runtime effects remain in `Core.lua`. Proxy settings are intentionally absent.

## Bounded runtime work

SavedVariables accept at most 32 configured target IDs and 32 configured signal IDs. Runtime replacement expansion has a separate 128-ID cap per resolved family. Explicit configured signal aliases are inserted first so learned target variants cannot evict proc-authority candidates.

Known buttons maintain one weak reverse action-slot index. `ACTIONBAR_SLOT_CHANGED(slot > 0)` updates only that slot's current owners immediately and in one coalesced targeted retry. Page, modifier, vehicle, override, macro, and broad slot invalidations share one complete next-frame pass. A required post-combat structural rescan replaces, rather than follows, a duplicate complete assignment pass. Proc-state queries remain independent from assignment events. Relevant SHOW payloads and the last positive candidate are ordering hints only; they reduce active-path reads but never authorize OFF before the complete readable candidate set is false.

Alert geometry is complete only after foreign-member discovery, parent, anchors/size, frame-level read/write, and the current render target's size hook succeed. A temporary access, lookup, or mutation failure remains dirty. Global geometry settings replace a runtime generation token, so a surface inaccessible during the change must reconcile before reusing readiness. Stable lifecycle scans do not repeat completed geometry mutations.

## External implementation evidence

Current donor implementations are pinned and summarized in [`DONOR_REVIEW.md`](DONOR_REVIEW.md). They establish naming and lifecycle evidence only:

- Bartender4/LibActionButton confirm `BT4ButtonN`, current-action ownership, and centralized event dispatch;
- ElvUI confirms `ElvUI_Bar<bar>Button<slot>` names;
- Dominos confirms mixed `DominosActionButtonN` and `MultiBar*ActionButtonN` families;
- WeakAuras and LibCustomGlow confirm keyed visual ownership and exact terminal cleanup.
- `UnknownAlienHuman/interrupt-glow` confirms that current object access must be rechecked at the exact visual/member boundary and that denied presentation resumes only on explicit lifecycle recovery.

No donor private registry is treated as a public API, and LibCustomGlow is intentionally not embedded.

## Runtime status

Expected interface is `120105`. Exact Lua 5.1 host checks are recorded in `VALIDATION.md`. Named-client combat, taint, rendering, and performance remain **NOT-RUN**.
