# Release 1.3.1

## Contract

Sudden Doom state is obtained from Blizzard's Spell Activation Overlay event/query surfaces. General aura scans, combat-log reconstruction, and runic-cost inference are not part of the runtime.

## Source verification

- Interface `120100`
- current Cooldown Viewer addon name
- dynamic base/override family
- action-slot revalidation
- addon-owned weak-key metadata
- event-driven CDM lifecycle integration
- no recurring ticker
- schema migration without DB wipe

## Automated local verification

- static architecture policy checks
- Lua syntax parse
- deterministic runtime smoke harness

## Live verification still required

See `TODO.md` and `VALIDATION.md`. Current game-data payload IDs, combat lockdown, forbidden-object behavior, taint, and third-party bar layouts cannot be proven by the stub harness.
