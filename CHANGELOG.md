# Changelog

## 1.4.7 — 2026-11-04

- Use the exact second `C_AddOns.IsAddOnLoaded` result: loading-in-progress no longer authorizes Bartender4, Dominos, ElvUI, or Cooldown Viewer discovery.
- Treat only `ACTIONBAR_SLOT_CHANGED(0)` as broad; denied, fractional, negative, or malformed payloads do no assignment work, while each valid slot is queried once per pass.
- Invalidate borrowed action/CDM assignment authority immediately on world/spec/secrecy resets, then restore it only from current providers.
- Never fall back from an assigned but inaccessible icon/render target to the parent button; geometry stays dirty until the actual target is usable.
- Require the complete selected Cooldown Viewer item lifecycle hook set before an item may render; failed/missing item or viewer hooks remain incomplete evidence and retain recovery ownership.
- Revalidate active alerts, animation objects, frame levels, render targets, and size-hook ownership at explicit lifecycle boundaries; stable rescans do not repeat completed geometry writes.
- Preserve one geometry generation across access denial and combat deferral, and ignore stale size hooks after render-target replacement.
- Query a relevant SHOW payload or last positive candidate first without weakening complete-readable-all-false OFF arbitration.
- Give every delayed proc, assignment, rescan, test, and diagnostic refresh path a terminal outcome: `NewTimer` falls back to identity-gated `After`, then to bounded synchronous work or conservative state clearing.
- Gate diagnostic chat-frame/member access and harden the optional debug refresh timer without adding polling or another runtime owner.
- Extend Lua regressions and mutation checks for loaded-vs-loading, stale assignment reset, inaccessible render targets, complete CDM hooks, timer failure, and hostile diagnostics. Named-client validation remains **NOT-RUN**.

## 1.4.6 — 2026-11-04

- Treat foreign action-button, render-target, animation, Cooldown Viewer, pool, and hook-method lookup as an access-gated operation; throwing or inaccessible member reads now fail closed instead of escaping the adapter boundary.
- Replace per-frame best-effort scale invalidation with one runtime geometry generation token, preserving global geometry changes made while a button or render target is inaccessible or combat-blocked.
- Require successful frame-level reads as well as parent, anchor/size, frame-level write, and size-hook operations before geometry is marked ready; render-target replacement invalidates readiness even when the prior surface was complete.
- Stop stable rescans from repeating completed geometry mutations. Recovery scans now delegate to idempotent `EnsureAlert` and mutate only missing, dirty, replaced, or generation-stale surfaces.
- Query a relevant SHOW payload or the last positive candidate first, reducing active-path overlay reads while preserving the complete-readable-all-false OFF rule.
- Recheck the current knowledge base, Blizzard source, and sibling `interrupt-glow` access-transition implementation; transfer only the object/member lifecycle decisions.
- Extend focused regressions and mutation checks for hostile member reads, frame-level read failure, geometry generation across access denial, render-target replacement, stable-rescan writes, and query-hint ordering. Named-client validation remains **NOT-RUN**.

## 1.4.5 — 2026-11-04

- Re-read the current engineering knowledge base at `c2a630aa186de401262663cc8568a77988be69df` and recheck the current Blizzard live source and pinned donor branch heads.
- Add a weak reverse button-slot index so nonzero `ACTIONBAR_SLOT_CHANGED` bursts update only current owners immediately and in a coalesced targeted retry; broad assignment events retain one full pass, and combat exit no longer performs that pass twice before a required rescan.
- Cap resolved target and signal families at 128 IDs and reserve configured signal aliases before learned replacements, bounding overlay-query and event-timer work independently of SavedVariables limits.
- Treat Cooldown Viewer item/viewer post-hook installation as fallible: failures no longer escape or become false-positive registrations and are retried only on later lifecycle recovery.
- Keep geometry dirty when alert access, frame level, anchoring, parenting, sizing, or render-target size-hook installation fails; attach at most one size hook to each current render target.
- Extend focused regressions for targeted slot dispatch, family saturation, foreign hook retry, render-target replacement, and geometry failure recovery. Named-client validation remains **NOT-RUN**.

## 1.4.4 — 2026-11-04

- Audit current WeakAuras, Bartender4, LibActionButton, Dominos, ElvUI, and LibCustomGlow implementations against the knowledge-base rules; record exact pins and rejected transfers.
- Add current Dominos `MultiBar*ActionButtonN` compatibility families so their alert surfaces are discovered and prepared outside combat without a global deep scan.
- Keep Bartender4 and ElvUI adapters unchanged after confirming their current global button names.
- Enforce the 32-ID limit while merging legacy defaults, preventing migration from writing oversized target/signal lists.
- Fail closed when `canaccesstable` itself errors while probing a foreign Cooldown Viewer pool.
- Add exact Lua 5.1 regressions for Dominos naming, migration bounds, and failed table-access probes. Live-client validation remains **NOT-RUN**.

## 1.4.3 — 2026-11-04

- Replace proxy settings with native `RegisterAddOnSetting` ownership for ordinary SavedVariables fields; keep migration, normalization, and idempotent runtime effects in the addon.
- Remove the accidental global addon namespace and compose files through the shared second TOC vararg table.
- Create Settings/debug deferred event owners only when combat actually blocks a requested operation.
- Bound target and signal configuration to 32 IDs each, preventing unbounded SavedVariables and overlay-query amplification.
- Coalesce Cooldown Viewer override/hotfix and talent/spell mapping bursts; duplicate or irrelevant override events now do no work.
- Track geometry readiness separately, retry failed parenting/anchoring safely, and avoid marking failed structural work complete.
- Harden value gates with fail-closed access checks and avoid repeated reads of secret-capable assignment fields.
- Remove obsolete redirect/release documents; `ARCHITECTURE.md`, `CHANGELOG.md`, and `VALIDATION.md` are the maintained owners.
- Exact Lua 5.1 syntax, broad smoke, focused regression, static checks, deterministic package, safe extraction, and source/package parity pass. Live-client validation remains **NOT-RUN**.

## 1.4.2 — 2026-11-03

- Recheck the complete live-source transition from `12.1.5.70688` to `12.1.5.70783`; the addon-owned ActionBar, Spell Activation Overlay, alert-template, and Cooldown Viewer source slices are unchanged.
- Remove the unrelated player-spellcast wake-up and stop action-assignment events from querying proc state.
- Filter `ADDON_LOADED` to the native/third-party bar integrations the addon actually observes.
- Preserve active overlay evidence across Cooldown Viewer hotfix and talent/spell assignment invalidations; discard stale explicit override observations only when spell relationships change.
- Recover from the public `COOLDOWN_VIEWER_DATA_LOADED` readiness event and ignore irrelevant override updates.
- Defer Cooldown Viewer pool enumeration, new hooks, and alert construction out of combat; reuse only already observed items during lockdown.
- Treat a missing/inaccessible viewer or unreadable external pool table as incomplete evidence so partial observations cannot prune valid tracked items.
- Recover alert animation after temporary animation-object inaccessibility without requiring another proc edge.
- Hide stale action/CDM presentation when reassignment identity cannot be inspected, then recover from the next authoritative lifecycle pass.
- Gate diagnostic values before formatting/logging and check current object access before other object probes.
- Report disabled rescan requests and future-schema spell commands accurately.
- Add focused regressions for each corrected lifecycle path. Live-client combat, taint, rendering, and performance remain **NOT-RUN**.

## 1.4.1 — 2026-11-03

- Revalidate existing action-button and Cooldown Viewer assignments immediately when configured spell families change, including during combat.
- Tie cached positive overlay-query results to spell IDs that remain configured.
- Recover addon-owned pending hides on authoritative context changes while disabled, without polling.
- Make slash commands report when a newer SavedVariables schema prevents changes instead of reporting scratch-state values.
- Unreadable overlay payloads still wake an authoritative query; a missed ON transition is recovered on an authoritative context event.
- Static checks, Lua 5.1.1 syntax, and stubbed runtime smoke pass. Live-client behavior remains **NOT-RUN**.

## 1.4.0 — 2026-11-03

### Retail 12.1.5

- Target interface `120105`; source reviewed at `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`.
- Replace the guessed 540-slot sweep with `C_ActionBar.GetSpell` lookups of observed button assignments; remove the unused candidate-slot cache.
- Fix stale paging matches and remove macro-body substring matching.
- Use one weak button set so temporary inaccessibility cannot desynchronize tracking; coalesce bursts into one complete deferred assignment check.
- Check secret/access boundaries before comparisons, conversion and indexing.
- Recheck addon-owned alert and animation access before mutation; hide accessible addon visuals even when their parent cannot be inspected.
- Hook actual Cooldown Viewer instances, including items created before addon load; use configured base spell identity only.
- Keep pool enumeration out of proc events and retain membership when a pool is unreadable.
- Cancel owned timers and native callbacks on disable; invalidate transient signals on specialization, world and secrecy changes.
- Preserve explicit spell-list removals across rebuilds/reloads; validate settings and leave future schemas untouched.

### Controls and maintenance

- Add native Settings controls for enablement, Cooldown Viewer mirroring, diagnostics and glow size; `/sdglow` opens the category.
- Refresh diagnostics with a dark green panel, bounded log and visible-only text updates.
- Prepare pageable button alerts outside combat; static multibars allocate alerts only for matching spells.
- Consolidate button updates and pending deep scans; remove repeated login family builds and redundant glow passes.
- Add regression cases for copied mixins, secret/unreadable values, combat restrictions, macro false matches, Settings proxies and lifecycle cleanup.
- Consolidate the code map in `ARCHITECTURE.md`; add pinned API references and a deterministic install packager.

### Validation

Lua 5.1 syntax, static checks, the stubbed smoke harness and package checks pass. The second pass reproduces the inaccessible-button and multi-slot burst bugs against the earlier implementation and verifies their fixes. Live-client combat, taint, event payloads, rendering and performance remain **NOT-RUN**; see [VALIDATION.md](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/VALIDATION.md).

## 1.3.1 — 2026-08-29

### Retail 12.1 migration

- Targeted Interface `120100` and corrected the optional addon name to `Blizzard_CooldownViewer`.
- Replaced aura scanning, combat-log reconstruction, and runic-cost inference with the official Spell Activation Overlay event/query contract.
- Removed all recurring proc/CDM polling.

### Signal correctness

- Added conservative query arbitration: any readable `true` enables the glow; OFF is authoritative only when every configured candidate is readable and false.
- Added a short synchronous SHOW grace and a mandatory post-grace reconciliation.
- Added a bounded 30-second event fallback only when the official query is unavailable.
- Kept simultaneous overlay IDs independent so one HIDE cannot clear another active signal.
- Treated unrelated overlay events only as delayed query wake-ups, never as Sudden Doom evidence.

### Spell and button mapping

- Built a dynamic Death Coil/Epidemic family through `GetBaseSpell`, `GetOverrideSpell`, and `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED`.
- Prevented arbitrary spell learning from stale or coincidental action slots.
- Revalidated the current action slot immediately before every action-button glow.
- Coalesced mapping updates and deferred structural work during combat.

### Rendering and Cooldown Viewer

- Kept all glow ownership inside the addon and made animation transitions idempotent.
- Moved runtime metadata into weak-key tables instead of writing fields onto external frames.
- Created/resized alert frames only outside combat.
- Hooked Cooldown Viewer acquire/set/reset lifecycle paths once instead of running a ticker.
- Added conservative all-pools-readable pruning and geometry re-prime after layout changes.
- Added Buff Bar icon-target handling.

### Persistence and diagnostics

- Replaced version-based SavedVariables wiping with schema migration.
- Split the debug logger from the debug UI namespace.
- Added static policy checks and a stubbed runtime harness.

## 1.2.2

- Hardened the previous aura-first implementation against secret values and action-slot mismatches.
- This architecture is superseded by 1.3.1 for Retail 12.1.
