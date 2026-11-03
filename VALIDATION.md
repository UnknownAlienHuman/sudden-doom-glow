# Validation record

This file tracks evidence that must come from a named Retail client. Source inspection and the stubbed harness are separate forms of evidence; neither establishes live behavior.

## Current status

- Addon release: `1.4.1`
- TOC target interface: `120105` (expected for Retail 12.1.5)
- Selected UI source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Source pin check: `2026-11-03`
- Static checks: **PASS**
- Stubbed runtime smoke: **PASS** on Lua 5.1.1
- Lua syntax check: **PASS** via Lua 5.1.1 `loadfile`
- Client build/interface: **NOT-RUN**
- Live combat, restrictions, event payloads, taint, rendering, and Cooldown Viewer lifecycle: **NOT-RUN**

## 1.4.1 source and host review — 2026-11-03

Static checks, Lua 5.1.1 syntax, and the stubbed runtime smoke pass. Coverage includes overlay arbitration, action and Cooldown Viewer assignment refresh after configuration changes, disabled pending-hide recovery, and future-schema slash refusal. Unreadable overlay payloads wake the authoritative query; missed ON transitions recover on authoritative context events. This is host/source evidence only: no WoW client, combat, taint, rendering, or performance result is claimed.

Temporary variants that independently restore the old candidate-cache, disabled-cleanup, and unreadable-HIDE paths each fail the corresponding regression assertion. The unchanged final implementation passes all three.

## Prior 1.4.0 source and host review — 2026-11-03

The selected `live` source head still matches the pin above. The first pass was checked with Lua 5.1.5; this pass uses the available Lua 5.1.1 interpreter.

Two behavioral regressions were reproduced independently against PR head `4439c39010d56c083adf7a285b58ee3e285086be`: a temporarily inaccessible button could not resume glow rendering, and a burst of slot changes lost the earlier slot's delayed assignment update. Both pass after replacing duplicate membership state and retaining one complete deferred refresh. The harness also checks alert-access boundaries and deep-scan deferral across combat.

These checks validate ordinary Lua control flow and stubbed API interactions. They do not establish client access policy, taint safety, visual quality, or a measured performance gain.

## Evidence record format

Append one record per client build and context. Preserve failures and superseded evidence.

```text
build=
interface=
date=
context=outside|combat|encounter|mythicplus|arena|battleground
bar implementation=
Cooldown Viewer layout=
other addons=
Sudden Doom stacks=
overlay payload spellID=
resolved targets=
resolved signals=
tracked buttons=
tracked Cooldown Viewer items=
result=pass|fail
error/reproduction=
```

See [docs/LIVE_TEST_CHECKLIST.md](https://github.com/UnknownAlienHuman/sudden-doom-glow/blob/main/docs/LIVE_TEST_CHECKLIST.md) for the scenarios to record. Do not overwrite a failed result after a hotfix; append a record with the new build/context.
