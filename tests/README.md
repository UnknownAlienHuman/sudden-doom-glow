# Test and validation checks

Run from the repository root:

```bash
python tests/static_checks.py .
luac -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua tests/runtime_regression_1_4_2.lua
lua tests/runtime_smoke.lua Core.lua
lua tests/runtime_regression_1_4_2.lua Core.lua
python scripts/package.py
```

`runtime_smoke.lua` retains the broad 1.4.x stub matrix. `runtime_regression_1_4_2.lua` focuses on the third audit: filtered addon readiness, action/irrelevant-override query separation, CDM and talent/spell continuity, stale-override removal, animation recovery, external-table gates, conservative partial-viewer pruning, combat-deferred CDM setup, future-schema command refusal, diagnostic access gates, and accurate rescan status.

These tests use deterministic stubs. They do not establish live Retail behavior, taint safety, visual quality, hotfixed event payloads, or measured performance. Record those separately in `VALIDATION.md`.
