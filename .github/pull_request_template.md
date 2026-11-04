## Summary

- Addon release: `1.4.5`; Retail 12.1.5; expected interface `120105`.
- Knowledge base: `c2a630aa186de401262663cc8568a77988be69df`.
- KB source: `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5`.
- Live-source recheck: `12.1.5.70783` / `297d7aaaa736f346b3e036f38ee088eaf7f8c07f`.
- Runtime behavior changed:
- Docs/package changed:

## Verification

- [ ] `python3 tests/static_checks.py .`
- [ ] Lua 5.1 syntax for every loaded/test file
- [ ] `lua5.1 tests/runtime_smoke.lua Core.lua`
- [ ] `lua5.1 tests/runtime_regression.lua Core.lua`
- [ ] deterministic package rebuild, safe extraction, and source/package byte parity
- [ ] `VALIDATION.md` separates source, host, package, and client evidence

## Evidence limits

List only checks actually run. Keep named-client checks `NOT-RUN` until recorded.
