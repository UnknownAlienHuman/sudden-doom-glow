# Test and validation checks

Run from the repository root:

```bash
python3 tests/static_checks.py .
luac5.1 -p Core.lua Debug.lua Options.lua tests/runtime_smoke.lua tests/runtime_regression.lua
lua5.1 tests/runtime_smoke.lua Core.lua
lua5.1 tests/runtime_regression.lua Core.lua
python3 tests/mutation_checks.py . lua5.1
python3 scripts/package.py
```

`runtime_smoke.lua` retains the broad lifecycle matrix. `runtime_regression.lua` focuses on assignment/proc separation, decisive-query suppression, opaque overlay wake-ups, strict slot-payload parsing, one action query per unique slot, reverse slot-index targeting, rescan ownership, exact loaded-vs-loading adapter discovery, bounded resolved spell families, hostile/denied/malformed foreign access predicates, complete viewer/item hook generations, timer fallbacks and terminal evidence clearing, active-alert revalidation, stale assignment invalidation, inaccessible icon targets, geometry generations, stale render-target hooks, stable-rescan mutation suppression, Cooldown Viewer readiness and partial evidence, combat structural deferral, native AddOnSetting behavior, migration/list bounds, hostile diagnostic output, future-schema refusal, and lazy optional UI owners.

These are deterministic host tests. They do not establish live Retail behavior, taint safety, visual quality, hotfixed payloads, or measured performance.
