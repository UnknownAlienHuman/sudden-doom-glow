# Test and validation checks

The static checker reads the TOC to determine the ordered runtime Lua files, checks
the target interface/version metadata, and scans every loaded runtime file for
forbidden legacy paths. The smoke harness supplies a deterministic subset of WoW
APIs and checks persisted settings, proc signal arbitration, action mapping,
protected-frame behavior, separate access to external parents and addon alerts,
timer cleanup, Cooldown Viewer lifecycle handling, restored button rendering
after temporary inaccessibility, combat-deferred deep rescans, and coalesced
burst refreshes when bar providers publish action assignments late.

Run from the repository root:

```bash
python tests/static_checks.py .
luac -p Core.lua
luac -p Options.lua
luac -p Debug.lua
lua tests/runtime_smoke.lua Core.lua
```

The current source and harness pass syntax checks and the smoke suite on Lua
5.1. If `luac` is unavailable, syntax can be checked with the Lua interpreter:

```bash
lua -e 'for _, path in ipairs({"Core.lua", "Debug.lua", "Options.lua", "tests/runtime_smoke.lua"}) do assert(loadfile(path)) end'
```

If a compatible Lua executable is unavailable in another environment, report
the runtime check as not run; a different Lua version does not establish Lua 5.1
syntax compatibility.

These checks run against stubs. They do not establish compatibility with a live
Retail client or verify current hotfixed event payloads. Live client validation
remains **NOT-RUN**; see the client matrix recorded in `../VALIDATION.md`.
