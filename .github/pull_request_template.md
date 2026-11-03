## Summary

- Target baseline: addon `1.4.0`, Retail 12.1.5, expected interface `120105`, source `12.1.5.70688` / `d07eb00237d8891f153215db98a5df880a26cfe5` (checked 2026-11-02).
- Retail target/release:
- Detection, action-button, or Cooldown Viewer behavior changed:
- Docs or package contents changed:

## Verification

- [ ] `python tests/static_checks.py .`
- [ ] `lua tests/runtime_smoke.lua Core.lua`
- [ ] `python scripts/package.py`
- [ ] Package contains one `SuddenDoomGlow/` directory and only allowlisted files.
- [ ] `VALIDATION.md` accurately states live-client evidence and unverified scope.

## Evidence limits

State the selected source pin and any current-client checks performed. Keep source inspection and stub results separate from live client results. Do not claim live compatibility without a named-client record.
