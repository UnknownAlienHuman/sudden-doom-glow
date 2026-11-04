# Sudden Doom Glow agent guide

## Target and evidence

- Release: `1.4.2`
- Target: Retail `12.1.5`; TOC interface `120105` is expected metadata until captured from `GetBuildInfo()`.
- Knowledge-base policy: `UnknownAlienHuman/wow-addon-engineering-kb@b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`.
- KB selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`.
- Current live source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`, checked `2026-11-03`. The complete `70688 → 70783` delta does not touch the ActionBar, Spell Activation Overlay, alert-template, or Cooldown Viewer files used by this addon.
- Live client combat, taint, rendering, and performance: **NOT-RUN**.

Read `SuddenDoomGlow.toc`, `ARCHITECTURE.md`, `docs/API_CONTRACTS.md`, then the relevant code. Read both test files before changing their contracts.

## Invariants

- Overlay SHOW/HIDE events are low-latency wake-ups. `C_SpellActivationOverlay.IsSpellOverlayed` is authoritative when the complete candidate family is readable.
- Any readable `true` may enable the glow. OFF is authoritative only when every configured candidate is readable and false.
- Keep event signals independent by spell ID. Unknown or unreadable payloads may wake a query but are not direct proc evidence.
- Never reconstruct Sudden Doom from auras, combat log, resources, cooldowns, usability, animation, visibility, errors, or timing.
- Gate secret-capable values before nil checks, comparison, conversion, formatting, logging, indexing, keys, persistence, or deferred capture.
- Check `CanBeAccessedInContext()` immediately before other script-object probes or mutations. Never cache access permission.
- Revalidate the current button assignment before every show. `C_ActionBar.GetSpell` is primary; resolved `GetActionInfo`/`GetMacroSpell` is the fallback. Never parse macro text.
- Action assignment events update assignments only; they do not become proc-state wake-ups.
- Keep one weak set of known buttons and one weak set of current matches. Structural work is deferred out of combat.
- Cooldown Viewer integration is source-coupled: use public data-ready as a wake-up, hook actual instances once, use configured `GetBaseSpellID`, enumerate pools only at setup/recovery, gate external pool tables, and never prune from partial viewer evidence.
- In combat, reuse only already observed Cooldown Viewer instances and existing addon-owned alerts. Defer new hooks, pool enumeration, and alert construction.
- Cooldown Viewer hotfix and talent/spell invalidations change assignment data, not proc state. Drop stale override observations while preserving overlay evidence and animation continuity.
- Cached positive query evidence remains valid only while its spell ID stays configured and only for the bounded fallback lifetime.
- Recover owned pending hides and missed animation starts on authoritative lifecycle events without polling.
- Future SavedVariables schemas remain untouched and inactive; every mutating command reports refusal.

## Change routing

- Runtime state, migrations, action mapping, overlay arbitration, rendering, and Cooldown Viewer adapter: `Core.lua`.
- Settings registration and combat deferral: `Options.lua`.
- Diagnostic log/window: `Debug.lua`.
- Source pins and implementation limits: `docs/API_CONTRACTS.md`.
- Live evidence: `VALIDATION.md` and `docs/LIVE_TEST_CHECKLIST.md`.
- Deterministic archive: `scripts/package.py`.

## Checks

```bash
python tests/static_checks.py .
luac -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua tests/runtime_regression_1_4_2.lua
lua tests/runtime_smoke.lua Core.lua
lua tests/runtime_regression_1_4_2.lua Core.lua
python scripts/package.py
```

The archive contains one top-level `SuddenDoomGlow/` directory and only the packager allowlist. Stub checks do not prove live-client behavior.
