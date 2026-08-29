## Summary

- Retail build/interface checked:
- Detection contract changed:
- Action-bar/CDM surfaces changed:

## Verification

- [ ] `python tests/static_checks.py .`
- [ ] `lua tests/runtime_smoke.lua Core.lua`
- [ ] `luac -p Core.lua Debug.lua`
- [ ] Live combat matrix updated in `TODO.md`
- [ ] Release ZIP contains only the allow-listed addon files

## Evidence limits

State what remains unverified in the live client. Do not mark combat, secret-value, or hotfixed spell-ID behavior complete from a stub harness alone.
