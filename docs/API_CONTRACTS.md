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

`C_AddOns.IsAddOnLoaded(name)` returns `(loadedOrLoading, loaded)`; this current-Retail adapter accepts only the exact second ordinary `loaded == true` result. The generated Cooldown Viewer contract defines synchronous data-loaded, spell-override, and table-hotfix events. Blizzard Settings exposes `RegisterAddOnSetting`, and `SettingMixin` emits value callbacks after the authoritative field write.

All secret-capable values are gated before comparison, type/nil tests, conversion, formatting, indexing, storage, logging, or deferral. Foreign object/table member discovery is also an access operation: the container/table is gated, indexing is isolated with `pcall`, the returned member is gated, and invocation has its own error boundary. Access-policy methods are accepted only when they return ordinary booleans; a conditionally constrained object requires an affirmative `CanBeAccessedInContext()` result.

## Private implementation boundaries

### Alert template

The addon creates an addon-owned child from `ActionButtonSpellAlertTemplate` and uses `ProcStartAnim`/`ProcLoop`. These are source-verified private UI details, not a generated extension API. The addon does not mutate Blizzard's alert manager.

### Cooldown Viewer

The selected source supplies four viewer instances, active `itemFramePool` objects, `OnAcquireItemFrame`, and item lifecycle methods (`SetCooldownID`, `SetOverrideSpell`, `ClearCooldownID`, `ResetCooldownData`). The adapter:

- verifies that `Blizzard_CooldownViewer` is fully loaded and the viewer is currently usable before reading its acquire method or pool;
- never reads a viewer, pool, item, or method through an unguarded foreign member access;
- hooks actual instances once and only outside combat;
- treats post-hook installation as a fallible foreign boundary, requires the viewer acquire hook plus every selected item lifecycle hook before rendering, records only completed hooks, and retries only on a later lifecycle pass;
- enumerates pools only for bounded setup/recovery;
- reads configured `GetBaseSpellID` only;
- clears on proved reset/reassignment;
- prunes only from a complete readable generation;
- keeps proc events on the already tracked set.

### Settings

`enabled`, `cdm`, `debug`, and `glowScale` are ordinary fields, so `Options.lua` uses `Settings.RegisterAddOnSetting`. Migration, validation, normalization, and runtime effects remain in `Core.lua`. Proxy settings are intentionally absent.

## Bounded runtime work

SavedVariables accept at most 32 configured target IDs and 32 configured signal IDs. Runtime replacement expansion has a separate 128-ID cap per resolved family. Explicit configured signal aliases are inserted first so learned target variants cannot evict proc-authority candidates.

Known buttons maintain one weak reverse action-slot index. `ACTIONBAR_SLOT_CHANGED(slot > 0)` updates only that slot's current owners immediately and in one coalesced targeted retry. The exact zero payload is the only broad slot invalidation; denied, nonintegral, negative, or malformed payloads perform no assignment work. One assignment pass queries each unique slot once and shares the result across its current button owners. Page, modifier, vehicle, override, and macro invalidations share one complete next-frame pass. A scheduled settled rescan cancels and replaces duplicate complete assignment work, including world/spec/secrecy recovery. Proc-state queries remain independent from assignment events. Relevant SHOW payloads and the last positive candidate are ordering hints only; decisive immediate reads avoid redundant delayed queries but never authorize OFF before the complete readable candidate set is false. Opaque payloads remain bounded wake-ups and never become spell IDs.

Alert geometry is complete only after foreign-member discovery, parent, anchors/size, frame-level read/write, and the current render target's size hook succeed. If an assigned icon target exists but is currently inaccessible, the adapter returns unavailable rather than silently using the parent button. A temporary access, lookup, or mutation failure remains dirty. Global geometry settings replace a runtime generation token, so a surface inaccessible during the change must reconcile before reusing readiness. Stale hooks from a replaced render target cannot mutate the current surface, while a successful current-target size callback resolves synchronously without leaving a false global dirty flag. Already-active alerts also revalidate their current animation objects at lifecycle boundaries. Stable lifecycle scans do not repeat completed geometry mutations.

## Deferred-work ownership

`C_Timer.NewTimer` is cancel-before-replace when its callback object is readable. A successful call with an unreadable handle remains logically cancellable through an ordinary owner token. Construction failure falls back to identity-gated `C_Timer.After`; if no timer path exists, required rescans/assignment reconciliation run once synchronously, while event/query/test evidence is cleared conservatively. No timer failure may leave permanent ON state or false queued ownership.

World/spec/secrecy resets cancel transient evidence, hide current output, clear the reverse button-slot index, and mark observed Cooldown Viewer assignments unreadable before rebuilding bounded families. Current provider state alone may restore authority. Diagnostic chat output and debug refresh callback access use the same fail-closed member/owner discipline.

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
