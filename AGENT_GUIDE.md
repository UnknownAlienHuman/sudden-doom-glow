# Sudden Doom Glow agent guide

## Target

- Retail 12.1.0
- Interface `120100`
- Release `1.3.1`
- Runtime files: `Core.lua`, then `Debug.lua`

## Read order

1. `SuddenDoomGlow.toc`
2. `ARCHITECTURE.md`
3. `Core.lua`: DB/access helpers -> spell family -> action mapping -> rendering -> CDM -> signals -> events/commands
4. `tests/static_checks.py`
5. `tests/runtime_smoke.lua`

## Non-negotiable invariants

- Spell Activation Overlay is the proc-state contract. Do not restore general `UNIT_AURA`, CLEU, resource-cost, usability, cooldown, or timing inference.
- Any readable overlay query `true` may enable the glow. OFF is authoritative only when every configured query candidate is readable and false.
- Keep both the synchronous SHOW grace and the longer unavailable-query TTL. They solve different failure modes.
- One HIDE removes only its own event signal.
- Unknown overlay events are wake-ups only; never treat every overlay as Sudden Doom.
- Accept a new target spell only after a base/override relationship to a configured root is proven.
- Never create, reparent, resize, reanchor, or otherwise structurally mutate alert/action frames in combat.
- Validate the current action slot before showing a button glow.
- Keep Blizzard and addon glow ownership separate. Do not call or patch `ActionButtonSpellAlertManager`.
- Keep external-frame metadata in weak-key addon tables.
- Cooldown Viewer integration is lifecycle-hooked and event-driven. Do not add a ticker or infer aura state from managed widgets.
- If any active CDM pool cannot be read, retain the previous tracked set rather than pruning from partial evidence.
- SavedVariables migration must preserve settings; never wipe the DB on an addon version change.

## Change routing

- Defaults/schema: top of `Core.lua`, `InitializeDB`.
- Replacement handling: `RebuildSpellFamilies`, `LearnExplicitOverride`.
- Bar support: `NAMED_BUTTON_SETS`, `MapNamedButtons`; keep deep enumeration manual.
- CDM compatibility: `GetCDMFrameSpellIDs`, `AttachCDMHooks`; verify against the pinned current Blizzard source before changing hook names.
- Signal timing: constants and `ReconcileGlow`; update the runtime harness for every arbitration change.
- User controls: slash-command block and `Debug.lua`.

## Required checks

```bash
python tests/static_checks.py .
lua tests/runtime_smoke.lua Core.lua
luac -p Core.lua
luac -p Debug.lua
```

Then run the live matrix in `TODO.md`. Source/static checks cannot prove combat restrictions or current hotfixed payload IDs.

## Release package

The install ZIP must contain one top-level `SuddenDoomGlow/` directory with only:

```text
Core.lua
Debug.lua
SuddenDoomGlow.toc
README.md
CHANGELOG.md
LICENSE
```

Do not include agent guides, TODOs, architecture files, tests, logs, or other repository-only material.
