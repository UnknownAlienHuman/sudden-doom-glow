# Sudden Doom Glow agent guide

## Target and evidence

- Release: `1.4.0`
- Target: Retail `12.1.5`; TOC interface `120105` is expected target metadata.
- Selected Blizzard UI source: build `12.1.5.70688`, commit `d07eb00237d8891f153215db98a5df880a26cfe5`, checked `2026-11-03`; current `live` head matches this pin.
- Live client build, combat, taint, and rendering validation: **NOT-RUN**.

Read [SuddenDoomGlow.toc](SuddenDoomGlow.toc), [ARCHITECTURE.md](ARCHITECTURE.md), [API contracts](docs/API_CONTRACTS.md), then the relevant sections of `Core.lua`, `Options.lua`, and `Debug.lua`. Read the smoke harness and static checks before changing their contracts.

## Invariants

- Use overlay events and `C_SpellActivationOverlay.IsSpellOverlayed` for proc state. Do not restore aura, combat-log, resource-cost, cooldown, usability, or timing inference.
- A readable true can enable the glow. OFF is authoritative only when every configured candidate is readable and false. Keep the synchronous SHOW grace and bounded unavailable-query fallback.
- Keep HIDE signals independent. Unknown overlay events only wake reconciliation.
- Accept targets only when configured roots/base/override relationships prove them.
- Discover buttons from observed named/current-assignment surfaces. `C_ActionBar.GetSpell` is the primary slot-to-spell lookup; `GetActionInfo` with `GetMacroSpell` is the resolved current-assignment fallback. Do not invent slot scans.
- Keep one weak `trackedButtons` membership set and the weak `knownButtons` discovery set. Validate the current readable assignment before showing a glow.
- For action changes, update the event's relevant slot immediately, then coalesce one unfiltered next-frame pass over known buttons. Do not replace the pending pass on every event.
- Keep alert ownership and metadata in addon-owned structures. Do not call or patch `ActionButtonSpellAlertManager`.
- Defer alert construction and structural changes out of combat.
- The Cooldown Viewer adapter is source-coupled. Use configured `GetBaseSpellID` for identity; do not use managed aura-selected `GetSpellID`. Hook actual item instances and avoid pool scans from proc events.
- If pool evidence is incomplete, retain tracked membership and hide unverified assignments rather than pruning from partial evidence.
- SavedVariables migrations preserve unrelated user data.

## Change routing

- Defaults, schema, options, spell family, action mapping, signals, and rendering: `Core.lua`.
- Settings registration and combat deferral: `Options.lua`.
- Diagnostic log/window: `Debug.lua`.
- Contract pins and evidence limits: `docs/API_CONTRACTS.md`.
- Live-client evidence: `VALIDATION.md` and `docs/LIVE_TEST_CHECKLIST.md`.
- Packaging: `scripts/package.py`; keep the TOC runtime entries equal to its runtime allowlist.

## Checks and release archive

```bash
python tests/static_checks.py .
luac -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua
lua tests/runtime_smoke.lua Core.lua
python scripts/package.py
```

The install archive must contain one top-level `SuddenDoomGlow/` directory with exactly the packager's runtime and user-facing release allowlist. The archive excludes repository guidance, tests, and validation records. Stub checks do not prove live-client behavior. See [VALIDATION.md](VALIDATION.md).
