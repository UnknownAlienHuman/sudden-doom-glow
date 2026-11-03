# Validation record

This file tracks evidence that must come from a named Retail client. Source inspection and the stubbed harness are separate forms of evidence; neither establishes live behavior.

## Current status

- Addon release: `1.4.0`
- TOC target interface: `120105` (expected for Retail 12.1.5)
- Selected UI source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`
- Source pin check: `2026-11-02`
- Static checks: **PASS** (interface/version metadata and loaded runtime policy checks)
- Stubbed runtime smoke: **PASS** on Lua 5.1.5 (settings persistence, overlay arbitration, action mapping, and Cooldown Viewer lifecycle scenarios)
- Lua syntax check: **PASS** on Lua 5.1.5 for runtime files and the smoke harness
- Client build/interface: **NOT-RUN**
- Live combat, restrictions, event payloads, taint, rendering, and Cooldown Viewer lifecycle: **NOT-RUN**

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

See [docs/LIVE_TEST_CHECKLIST.md](docs/LIVE_TEST_CHECKLIST.md) for the scenarios to record. Do not overwrite a failed result after a hotfix; append a record with the new build/context.
