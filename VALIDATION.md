# Validation record

Source inspection and stub execution are separate from named-client evidence.

## Current status

- Addon release: `1.4.2`
- TOC target interface: `120105` (expected)
- KB selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Current live source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`
- Complete `70688 → 70783` relevant-slice comparison: **PASS**; no ActionBar, Spell Activation Overlay, alert-template, or Cooldown Viewer files changed
- Static checks: **PASS**
- Focused 1.4.2 stub regression: **PASS** under Lua 5.3 (`texlua`)
- Focused regression against 1.4.1: **FAIL as expected** at the obsolete `UNIT_SPELLCAST_SUCCEEDED` owner
- Exact Lua 5.1 syntax and broad `runtime_smoke.lua` rerun for 1.4.2: **NOT-RUN in this environment**
- Deterministic package rebuild: **PASS**; two archives are byte-identical
- Archive allowlist, safe paths, extracted static checks, extracted focused regression, and source/package byte parity: **PASS**
- Archive SHA-256: `d1a97fd609416c1b0d115df394f36d39349f37d4e3e89283feddeb660de38a32` (`23824` bytes)
- Named-client build/interface, combat, taint, rendering, and performance: **NOT-RUN**

## 1.4.2 focused host review — 2026-11-03

The focused harness covers:

- no player-spellcast proc wake-up;
- filtered addon-load plus public Cooldown Viewer data-readiness recovery;
- separation of action assignment and irrelevant override updates from proc queries;
- no OFF/ON restart on Cooldown Viewer hotfix or talent/spell mapping invalidations;
- conservative stale-hide/recovery for unreadable action assignments and temporarily inaccessible animation groups;
- no pruning from a missing viewer or inaccessible external pool table;
- no new Cooldown Viewer enumeration/hook attachment during combat;
- explicit future-schema spell-command refusal;
- diagnostic access gating;
- accurate disabled-rescan status;
- optional UI owner attachment and Settings availability.

This is deterministic host evidence, not a WoW runtime result.

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
