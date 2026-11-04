# Validation record

Source inspection, deterministic host execution, and named-client evidence are separate layers.

## Current status

- Addon release: `1.4.3`
- TOC target interface: `120105` (expected)
- Knowledge-base revision: `b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`
- KB-selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`
- Complete `70688 -> 70783` relevant-slice comparison: **PASS**; no ActionBar, Spell Activation Overlay, spell-alert template, or Cooldown Viewer files changed
- Static policy checks: **PASS**
- Exact Lua `5.1.5` syntax: **PASS**
- Broad Lua `5.1.5` runtime smoke: **PASS**
- Focused Lua `5.1.5` lifecycle regression: **PASS**
- Deterministic package rebuild: **PASS**; independent archives were byte-identical
- Archive safe-path, symlink, allowlist, extracted-install, and source/package byte-parity checks: **PASS**
- Archive SHA-256: `4a109e029efb6cc5d8f0c8dc02840d5fdf76f61788085b671e7ef91b7b74197a` (`24966` bytes)
- Verification run: GitHub Actions `41796469532`, job `126461642194`
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.3 host coverage — 2026-11-04

The deterministic harnesses cover:

- native `RegisterAddOnSetting` ownership and idempotent addon-owned runtime effects;
- local second-vararg addon namespace with no accidental global implementation table;
- lazy Settings/debug deferred owners;
- 32-entry limits for target and signal configuration;
- coalesced mapping recovery for Cooldown Viewer, talent, spell, and override bursts;
- duplicate and irrelevant override events doing no work;
- geometry readiness, failed structural mutation recovery, and no false completion;
- fail-closed value/table/object access gates;
- action assignment, overlay query/event arbitration, bounded fallback timers, and cleanup;
- Cooldown Viewer readiness, partial-pool preservation, reset/reuse, and combat deferral;
- future-schema preservation and explicit command refusal;
- package layout, byte parity, and execution from the extracted installation.

These are host tests with WoW API stubs. They do not establish client combat, taint, protected-object, animation, visual, or performance behavior.

## Named-client record format

```text
build=
interface=
addon commit/package=
date=
context=outside|combat|encounter|mythicplus|arena|battleground
bar implementation=
Cooldown Viewer layout=
other addons=
Sudden Doom stacks=
overlay payload spellID=
immediate query=
next-frame query=
post-grace query=
resolved targets=
resolved signals=
tracked buttons=
tracked Cooldown Viewer items=
result=pass|fail
error/reproduction=
```
