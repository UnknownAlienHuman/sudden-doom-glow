# Sudden Doom Glow

Sudden Doom Glow mirrors active Sudden Doom spell activation overlays onto matching Death Coil, Epidemic, replacement action buttons, and configured Blizzard Cooldown Viewer items.

- **Version:** 1.4.1
- **Target:** Retail 12.1.5
- **TOC interface:** `120105` (expected for this target)
- **Selected UI source:** build `12.1.5.70688`, commit `d07eb00237d8891f153215db98a5df880a26cfe5` (checked 2026-11-03; live head matches)
- **SavedVariables:** `SuddenDoomGlowDB`
- **Optional dependency:** `Blizzard_CooldownViewer`

The TOC interface is target metadata. The addon's runtime client build has not been captured; see [API contracts](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/docs/API_CONTRACTS.md) and [live checklist](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/docs/LIVE_TEST_CHECKLIST.md).

## Detection and display

The addon listens to synchronous Spell Activation Overlay glow events and reconciles them against `C_SpellActivationOverlay.IsSpellOverlayed`. A readable `true` can turn the glow on. OFF is authoritative only when all configured candidates are readable and false. SHOW ordering receives a short grace; unavailable query state uses a bounded event fallback. Simultaneous spell IDs remain independent.

Spell roots are expanded through the current base/override APIs and the Cooldown Viewer spell-override event. The addon observes known button surfaces and checks each button's current assignment with `C_ActionBar.GetSpell`; the fallback reads `GetActionInfo` and resolves macros with `GetMacroSpell`. Relevant slot changes refresh immediately, followed by one coalesced next-frame pass over known buttons. Macro text is not searched to infer a castable spell.

The addon owns the glow state and its frame metadata. Alert construction and geometry changes are deferred out of combat. Cooldown Viewer integration is an optional, source-coupled adapter that observes actual viewer/item instances and uses each item's configured base spell ID. Details and limits are in [API contracts](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/docs/API_CONTRACTS.md).

## Settings

Open **Settings → AddOns → Sudden Doom Glow**, or enter `/sdglow`.

- Enable or disable the addon.
- Choose whether to mirror the glow in Cooldown Viewer.
- Adjust glow size from `1.0` to `1.8` (default `1.4`).
- Open the dark green diagnostic log when troubleshooting.

Settings and debug windows wait until combat ends before opening. `/sdglow test` previews the glow for two seconds. Changes through slash commands also refresh the Settings controls.

## Commands

```text
/sdglow [options]
/sdglow status
/sdglow debug
/sdglow rescan [deep]
/sdglow test
/sdglow spell <spellID>
/sdglow signal <spellID>
/sdglow spells
/sdglow cdm on|off
/sdglow on|off
```

`/sdglow aura <spellID>` remains a compatibility alias for `/sdglow signal <spellID>`.

Default target spells are Death Coil (`47541`), Epidemic (`207317`) and Necrotic Coil (`1242174`). Detection also includes the Sudden Doom signal aliases `450932` and `81340`. The spell/signal commands toggle configured IDs; removals persist across updates and reloads. Base spells and their replacements form one target family, so a remaining configured replacement can still include its base spell.

Existing settings migrate without a database wipe. Settings from a newer schema are preserved and left inactive until a compatible addon version is installed.

## Verification and live testing

The repository includes static checks and a stubbed runtime harness. They do not establish behavior in the live client. Client combat, restricted contexts, hotfixed spell IDs, UI stack compatibility, and live Cooldown Viewer layouts remain **NOT-RUN** until evidence is recorded in [VALIDATION.md](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/VALIDATION.md).

Run these commands from a repository checkout; the install archive does not include the test files.

```bash
python tests/static_checks.py .
luac -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua
lua tests/runtime_smoke.lua Core.lua
```

## Packaging

Build the deterministic install archive with:

```bash
python scripts/package.py
```

The default output is `dist/SuddenDoomGlow-1.4.1.zip`. An output path can be supplied as the first argument. The archive contains one `SuddenDoomGlow/` directory and only the runtime files and user-facing release files in the packager allowlist.

## Install

Place the `SuddenDoomGlow` directory in `World of Warcraft/_retail_/Interface/AddOns/`, enable the addon, and reload the UI.

## License

MIT. See [`LICENSE`](LICENSE).
