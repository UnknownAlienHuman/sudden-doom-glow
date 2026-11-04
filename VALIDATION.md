# Validation record

Source inspection, deterministic host execution, and named-client evidence are separate layers.

## Current status

- Addon release: `1.4.4`
- TOC target interface: `120105` (expected)
- Knowledge-base revision: `b03e1635d0ff8bcd6be4f4dfac589dafec4e5e83`
- KB-selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`
- Complete `70688 -> 70783` relevant-slice comparison: **PASS**; no ActionBar, Spell Activation Overlay, spell-alert template, or Cooldown Viewer files changed
- Donor implementation review: **PASS** at the exact revisions recorded in `docs/DONOR_REVIEW.md`
- Static policy checks: **PASS**
- Exact Lua `5.1.5` syntax: **PASS**
- Broad Lua `5.1.5` runtime smoke: **PASS**
- Focused Lua `5.1.5` lifecycle regression: **PASS**
- Deterministic package rebuild: **PASS**; independent archives were byte-identical
- Archive allowlist, integrity, extracted-install execution, and source/package byte parity: **PASS**
- Archive SHA-256: `1389bfc6dacd011f92286a29b848ff8d636e9bd869a4542dee8dc096356fc45e` (`25489` bytes)
- Verification run: GitHub Actions `41871913547`, job `126720989894`
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.4 host coverage — 2026-11-04

The deterministic harnesses cover:

- current Dominos `DominosActionButtonN` and `MultiBar*ActionButtonN` compatibility names;
- current Bartender4 and ElvUI named-button adapters retained after source verification;
- legacy default merging that cannot exceed the 32-ID target/signal limits;
- fail-closed external table-access probes, including an erroring `canaccesstable` call;
- native `RegisterAddOnSetting` ownership and idempotent runtime effects;
- local second-vararg addon namespace and lazy optional UI owners;
- coalesced mapping recovery and duplicate/irrelevant override rejection;
- geometry readiness, inaccessible-object recovery, overlay arbitration, bounded timers, and cleanup;
- Cooldown Viewer readiness, partial-pool preservation, reset/reuse, and combat deferral;
- future-schema preservation, package layout, extracted execution, and source/archive parity.

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
