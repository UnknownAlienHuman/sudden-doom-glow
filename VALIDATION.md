# Retail 12.1 validation record

Use this file only for evidence captured from a current game client. Source inspection and the stubbed runtime harness are recorded separately in `CHANGELOG.md` and `tests/`.

## Current state

- Implementation: `1.3.1`
- Target interface: `120100`
- Source/static/runtime-harness verification: complete
- Live combat verification: pending

## Record format

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
detection=
tracked buttons=
tracked CDM frames=
result=pass|fail
error/reproduction=
```

Do not overwrite failed evidence after a hotfix; append a new build/context record and mark the superseded result explicitly.
