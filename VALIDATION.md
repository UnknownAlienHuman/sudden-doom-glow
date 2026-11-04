# Validation record

Source inspection, deterministic host execution, and named-client evidence are separate layers.

## Current status

- Addon release: `1.4.5`
- TOC target interface: `120105` (expected)
- Knowledge-base revision: `c2a630aa186de401262663cc8568a77988be69df`
- KB-selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`
- Complete `70688 -> 70783` relevant-slice comparison: **PASS**; no ActionBar, Spell Activation Overlay, spell-alert template, or Cooldown Viewer files changed
- Donor branch-head recheck: **PASS** at the exact revisions recorded in `docs/DONOR_REVIEW.md`
- Static policy checks: **PASS**
- Exact Lua `5.1.5` syntax: **PASS**
- Broad Lua `5.1.5` runtime smoke: **PASS**
- Focused Lua `5.1.5` lifecycle regression: **PASS**
- Deterministic package rebuild: **PASS**; independent archives were byte-identical
- Archive integrity, allowlist, extracted-install execution, and source/package byte parity: **PASS**
- Archive SHA-256: `152b09abe6178f398fee519ee5d9499ad7e98556103598a10c4853fcae9d6fd3` (`26693` bytes)
- Verification run: GitHub Actions `41920487543`, job `126891351369`
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.5 host coverage — 2026-11-04

The deterministic harnesses cover:

- reverse current-slot indexing and targeted immediate/deferred nonzero slot refresh;
- one coalesced complete pass only for broad assignment invalidations;
- 32-entry configured lists and 128-entry resolved target/signal family limits;
- preservation of configured signal aliases when learned target variants saturate the runtime budget;
- fail-closed Cooldown Viewer item/viewer post-hook installation with later lifecycle retry;
- render-target replacement, size-hook ownership, frame-level failures, and geometry recovery;
- no redundant full assignment pass before a queued post-combat rescan;
- current Bartender4, ElvUI, and Dominos named-button adapters;
- overlay query/event arbitration, bounded fallback timers, assignment revalidation, and cleanup;
- Cooldown Viewer readiness, partial-pool preservation, reset/reuse, and combat deferral;
- native `RegisterAddOnSetting`, local addon namespace, future-schema preservation, and lazy optional UI owners;
- package layout, exact source byte parity, and execution from the extracted installation.

Mutation checks performed during development confirmed that the focused regression fails when the full-slot scan, unbounded family growth, unsafe foreign hook, or stale geometry-ready behavior is restored.

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
