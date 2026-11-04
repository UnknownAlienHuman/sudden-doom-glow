## Summary

- Target baseline: addon `1.4.2`, Retail 12.1.5, expected interface `120105`.
- KB selected source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`.
- Current live source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`.
- Detection/action-button/Cooldown Viewer behavior changed:
- Docs/package contents changed:

## Verification

- [ ] `python tests/static_checks.py .`
- [ ] Lua syntax for every loaded/test file
- [ ] `lua tests/runtime_smoke.lua Core.lua`
- [ ] `lua tests/runtime_regression_1_4_2.lua Core.lua`
- [ ] `python scripts/package.py`
- [ ] Deterministic archive rebuild and exact source/package byte parity
- [ ] `VALIDATION.md` separates source/stub/client evidence

## Evidence limits

State every command/scenario actually run. Keep unperformed named-client checks `NOT-RUN`.
