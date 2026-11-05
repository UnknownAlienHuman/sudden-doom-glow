# Validation record

Source inspection, deterministic host execution, and named-client evidence are separate layers.

## Current status

- Addon release: `1.4.7`
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
- Mutation sensitivity checks: **PASS**; all six restored defects were rejected by the focused regression
- Deterministic package rebuild: **PASS**; independent archives were byte-identical
- Archive integrity, safe paths, symlink rejection, allowlist, extracted-install execution, and source/package byte parity: **PASS**
- Install archive SHA-256: `81e460b10dbc37ba79b35696c3c83eedc452a235709a80914674625015e89ed2` (`31572` bytes)
- Verification run: GitHub Actions `41959209167`, job `127021279524`
- Superseded workflow attempt: `41958939106`; temporary YAML was rejected before a job was created, so no addon code ran in that attempt
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.7 host coverage — 2026-11-04

The deterministic harnesses cover:

- exact `loadedOrLoading` versus completed-addon boundaries for optional providers;
- ordinary boolean object-policy predicates, current access, hostile metatables, and denied foreign member reads;
- access-gated diagnostic chat output and identity-owned debug refresh callbacks;
- positive, zero, denied, and malformed `ACTIONBAR_SLOT_CHANGED` payloads, one query per unique slot, and targeted immediate/deferred refresh;
- immediate stale action and Cooldown Viewer assignment invalidation on world, specialization, and secrecy transitions;
- relevant SHOW and last-positive query hints, complete-readable-all-false OFF, bounded event/query fallback, and terminal timer failure handling;
- inaccessible callback handles, `C_Timer.After` fallback, synchronous required-work fallback, and conservative proc/test evidence clearing;
- assigned-but-inaccessible render targets with no parent fallback;
- active-alert and animation access recovery, render-target replacement, stale size-hook suppression, frame-level failures, and geometry generations;
- complete Cooldown Viewer viewer/item lifecycle-hook generations before assignment authority is restored;
- 32-entry configured lists, 128-entry resolved target/signal limits, and configured signal priority;
- current Bartender4, ElvUI, and Dominos named-button adapters;
- Cooldown Viewer readiness, partial-pool preservation, reset/reuse, and combat deferral;
- native `RegisterAddOnSetting`, local addon namespace, future-schema preservation, and lazy optional UI owners;
- package layout, exact source byte parity, and execution from the extracted installation.

`tests/mutation_checks.py` proves that the focused regression fails when loaded-vs-loading confusion, inaccessible-icon parent fallback, stale assignment retention, dropped required rescan, partial Cooldown Viewer hook authorization, or unguarded chat-frame access is restored.

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
