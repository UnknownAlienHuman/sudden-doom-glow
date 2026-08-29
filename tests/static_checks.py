from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
core = (root / "Core.lua").read_text(encoding="utf-8")
debug = (root / "Debug.lua").read_text(encoding="utf-8")
toc = (root / "SuddenDoomGlow.toc").read_text(encoding="utf-8")

required = [
    "C_SpellActivationOverlay.IsSpellOverlayed",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "ActionButton.OnActionChanged",
    "ActionButtonSpellAlertTemplate",
    "NewWeakKeyTable",
    "OVERLAY_SHOW_GRACE",
    "EVENT_FALLBACK_TTL",
]
for token in required:
    assert token in core, f"missing required contract: {token}"

for forbidden in [
    "C_UnitAuras",
    "UnitAura(",
    "GetSpellPowerCost",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "ActionButtonSpellAlertManager:",
    "SetAttribute(",
]:
    assert forbidden not in core, f"forbidden legacy path remains: {forbidden}"

assert "## Interface: 120100" in toc
assert "## OptionalDeps: Blizzard_CooldownViewer" in toc
assert "## Version: 1.3.1" in toc
assert "SDG.Debug = {}" not in debug
assert "SDG.DebugUI" in debug and "SDG:LogDebug" in debug
assert "WipeDB" not in core
assert not re.search(r"SetScript\(\s*[\"']OnUpdate", core), "polling OnUpdate introduced"

print("static checks: PASS")
