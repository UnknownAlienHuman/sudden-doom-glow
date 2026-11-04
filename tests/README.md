# Test and validation checks

Run from the repository root:

```bash
python3 tests/static_checks.py .
luac5.1 -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua tests/runtime_regression.lua
lua5.1 tests/runtime_smoke.lua Core.lua
lua5.1 tests/runtime_regression.lua Core.lua
python3 scripts/package.py
```

`runtime_smoke.lua` retains the broad lifecycle matrix. `runtime_regression.lua` focuses on assignment/proc separation, coalesced mapping invalidation, Cooldown Viewer readiness and partial evidence, combat structural deferral, inaccessible object recovery, native AddOnSetting behavior, bounded configured lists, future-schema refusal, and lazy optional UI owners.

These are deterministic host tests. They do not establish live Retail behavior, taint safety, visual quality, hotfixed payloads, or measured performance.
