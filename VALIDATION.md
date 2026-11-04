# Validation record

Source inspection, deterministic host execution, and named-client evidence are separate layers.

## Current status

- Addon release: `1.4.6`
- TOC target interface: `120105` (expected)
- Knowledge-base revision: `c2a630aa186de401262663cc8568a77988be69df`
- KB-selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`
- Complete `70688 -> 70783` relevant-slice comparison: **PASS**; no ActionBar, Spell Activation Overlay, spell-alert template, or Cooldown Viewer files changed
- Donor/sibling implementation review: **PASS** at the exact revisions recorded in `docs/DONOR_REVIEW.md`
- Static policy checks: **PASS**
- Exact Lua `5.1.5` syntax: **PASS**
- Broad Lua `5.1.5` runtime smoke: **PASS**
- Focused Lua `5.1.5` lifecycle regression: **PASS**
- Deterministic package rebuild: **PASS**; independent archives were byte-identical
- Archive integrity, allowlist, extracted-install execution, and source/package byte parity: **PASS**
- Archive SHA-256: `951dd60ea9ae41ab4fefc864d4240b9510d8486509f231e52f81d097eed73266` (`28441` bytes)
- Verification run: GitHub Actions `41927605083`, job `126915992067`
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.6 host coverage — 2026-11-04

The deterministic harnesses cover:

- access-gated foreign member reads for action buttons, render targets, animations, Cooldown Viewer instances, pools, items, and hook methods;
- hostile metatables and erroring/inaccessible member reads that fail closed without escaping the adapter boundary;
- reverse current-slot indexing and targeted immediate/deferred nonzero slot refresh;
- relevant SHOW and last-positive overlay-query hints without weakening authoritative all-false reconciliation;
- 32-entry configured lists and 128-entry resolved target/signal family limits;
- preservation of configured signal aliases when learned target variants saturate the runtime budget;
- fail-closed Cooldown Viewer post-hook installation with later lifecycle retry;
- render-target replacement, size-hook ownership, failed frame-level reads/writes, and geometry recovery;
- one geometry generation token that preserves global scale changes across object-access denial and combat deferral;
- stable rescans that do not repeat completed geometry mutations;
- no redundant full assignment pass before a queued post-combat rescan;
- current Bartender4, ElvUI, and Dominos named-button adapters;
- overlay query/event arbitration, bounded fallback timers, assignment revalidation, and cleanup;
- Cooldown Viewer readiness, partial-pool preservation, reset/reuse, and combat deferral;
- native `RegisterAddOnSetting`, local addon namespace, future-schema preservation, and lazy optional UI owners;
- package layout, exact source byte parity, and execution from the extracted installation.

Mutation checks confirmed that the focused regression fails when unsafe foreign member lookup, stale frame-level readiness, repeated stable geometry mutation, lost geometry generation, or non-hinted SHOW querying is restored.

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
