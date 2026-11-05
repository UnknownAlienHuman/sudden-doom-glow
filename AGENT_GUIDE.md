# Sudden Doom Glow engineering guide

## Target and evidence

- Release: `1.4.7`
- Target: Retail `12.1.5`; expected TOC interface `120105`
- Knowledge base: `UnknownAlienHuman/wow-addon-engineering-kb@c2a630aa186de401262663cc8568a77988be69df`
- KB-selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, checked `2026-11-04`
- Named-client combat, taint, rendering, and performance: **NOT-RUN**

Read `SuddenDoomGlow.toc`, `ARCHITECTURE.md`, `docs/API_CONTRACTS.md`, and both runtime tests before changing behavior.

## Invariants

- Spell Activation Overlay events are wake-ups; `C_SpellActivationOverlay.IsSpellOverlayed` is state authority when the complete candidate set is readable.
- Any readable `true` enables the glow. OFF requires every configured candidate to be readable and false.
- Never reconstruct Sudden Doom from auras, combat log, resources, cooldowns, usability, animation, visibility, errors, or timing.
- Gate secret-capable values before nil/type checks, comparison, conversion, formatting, keys, storage, logging, or deferral.
- Recheck current object access immediately before mutation; never cache permission.
- Accept object-policy results only as ordinary booleans; a conditionally constrained object requires affirmative current-context access.
- Treat every foreign member lookup as an access operation: gate the object/table, read behind `pcall`, gate the returned member, then call behind a second error boundary.
- Revalidate the current action assignment before every show. Use `C_ActionBar.GetSpell`, then only the resolved `GetActionInfo`/`GetMacroSpell` fallback. Never parse macro text.
- Assignment events update assignments only. They do not become proc-state signals.
- Keep structural work out of combat. Reuse only known buttons, observed Cooldown Viewer items, and existing addon-owned alerts during lockdown.
- Cooldown Viewer integration is source-coupled: public readiness event, actual-instance post-hooks, the complete selected item lifecycle-hook set before render authority, configured `GetBaseSpellID`, bounded recovery enumeration, and no pruning from partial evidence.
- Hotfix/talent/spell invalidations rebuild mapping identity without inventing a proc edge or restarting a valid animation.
- Settings are ordinary SavedVariables fields registered through `Settings.RegisterAddOnSetting`; migration and runtime side effects remain addon-owned.
- Configured target and signal lists are capped at 32 IDs each; resolved runtime families are capped at 128 IDs each, with configured signal aliases reserved before learned variants.
- Maintain one reverse button-to-slot index. Positive slot changes stay targeted and query each unique slot once; only the exact zero slot payload or documented broad assignment events may walk all known buttons. Denied/malformed payloads do nothing.
- Gate optional named adapters behind the exact second `C_AddOns.IsAddOnLoaded` result; loading-in-progress is not readiness, and `ADDON_LOADED` owns later discovery.
- One settled rescan cancels and replaces queued complete assignment work; do not run an immediate full pass and then another rescan for the same transition.
- Global geometry changes replace one runtime generation token. A temporarily inaccessible frame must reconcile that token before reusing cached readiness; an assigned inaccessible icon never falls back to the parent button.
- Query hints may change candidate order only. They never weaken the all-candidates-readable OFF rule.
- Opaque overlay payloads may wake bounded reconciliation but are never compared, stored, indexed, or converted into spell identity.
- Every delayed owner has a terminal path: cancel/replace, identity-gated fallback, one synchronous required-work pass, or conservative evidence clearing.
- World/spec/secrecy transitions revoke borrowed action/CDM assignment authority before recovery.
- Future SavedVariables schemas remain untouched and inactive.
- The addon table passed as the second TOC vararg is the only shared Lua namespace. Do not restore `_G.SuddenDoomGlow`.

## Ownership

- `Core.lua`: persistence, spell families, action mapping, overlay arbitration, rendering, Cooldown Viewer adapter.
- `Options.lua`: Blizzard Settings registration and combat deferral.
- `Debug.lua`: bounded diagnostic log/window.
- `docs/API_CONTRACTS.md`: source pins and private/public boundaries.
- `docs/DONOR_REVIEW.md`: pinned external implementations and transfer/rejection decisions.
- `VALIDATION.md`: executed checks and remaining uncertainty.
- `scripts/package.py`: deterministic allowlisted release archive.

## Checks

```bash
python3 tests/static_checks.py .
luac5.1 -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua tests/runtime_regression.lua
lua5.1 tests/runtime_smoke.lua Core.lua
lua5.1 tests/runtime_regression.lua Core.lua
python3 tests/mutation_checks.py . lua5.1
python3 scripts/package.py
```

Stub checks are host evidence, not a live-client pass.
