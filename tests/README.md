# Tests

- `static_checks.py` enforces the Retail 12.1 architecture and rejects legacy detection paths.
- `runtime_smoke.lua` supplies a deterministic WoW API stub for signal, mapping, migration, animation, replacement, and Cooldown Viewer lifecycle tests.

Run from the repository root:

```bash
python tests/static_checks.py .
lua tests/runtime_smoke.lua Core.lua
```
