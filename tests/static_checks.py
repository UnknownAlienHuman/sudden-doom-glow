from pathlib import Path
import re
import sys

root = Path(sys.argv[1]).resolve()
toc = (root / "SuddenDoomGlow.toc").read_text(encoding="utf-8")


def metadata(name: str) -> str:
    match = re.search(rf"^## {re.escape(name)}:\s*(.*?)\s*$", toc, re.MULTILINE)
    assert match, f"TOC is missing ## {name}: metadata"
    return match.group(1)


interface = int(metadata("Interface"))
assert interface == 120105, f"unexpected Retail 12.1.5 interface: {interface}"
version = metadata("Version")
assert version == "1.4.3", f"unexpected addon version: {version!r}"
assert metadata("OptionalDeps") == "Blizzard_CooldownViewer"
assert metadata("SavedVariables") == "SuddenDoomGlowDB"

runtime_files = []
for line in toc.splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    path = (root / line).resolve()
    assert path.parent == root and path.is_file(), f"missing/non-root runtime file: {line}"
    assert path.suffix.lower() == ".lua", f"unexpected runtime entry: {line}"
    runtime_files.append(path)

runtime_names = [path.name for path in runtime_files]
assert runtime_names == ["Core.lua", "Debug.lua", "Options.lua"], runtime_names
assert len(runtime_names) == len(set(runtime_names))

sources = {path.name: path.read_text(encoding="utf-8") for path in runtime_files}
all_runtime = "\n".join(sources.values())
core = sources["Core.lua"]
debug = sources["Debug.lua"]
options = sources["Options.lua"]

for token in (
    "C_SpellActivationOverlay.IsSpellOverlayed",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW",
    "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "COOLDOWN_VIEWER_DATA_LOADED",
    "ActionButton.OnActionChanged",
    "ActionButtonSpellAlertTemplate",
    "MAX_CONFIGURED_SPELL_IDS = 32",
    "QueueMappingRecovery",
    "pendingHides",
    "geometryReady",
    "canaccesstable",
    "IsReadableTable",
):
    assert token in all_runtime, f"missing required contract: {token}"

for forbidden in (
    "C_UnitAuras",
    "UnitAura(",
    "GetSpellPowerCost",
    "COMBAT_LOG_EVENT_UNFILTERED",
    "ActionButtonSpellAlertManager:",
    "UNIT_SPELLCAST_SUCCEEDED",
    "GetMacroInfo",
    "SetAttribute(",
    "WipeDB",
    "RegisterProxySetting",
    "_G.SuddenDoomGlow =",
):
    assert forbidden not in all_runtime, f"forbidden/stale path remains: {forbidden}"

assert "local ADDON_NAME, SDG = ..." in core
assert "local _addonName, SDG = ..." in debug
assert "local _addonName, SDG = ..." in options
assert "RegisterAddOnSetting" in options
assert "ApplySettingOption" in core and "ApplySettingOption" in options
assert "Blizzard_CooldownViewer = true" in core
assert "Blizzard_ActionBar = true" not in core
assert "local CURRENT_SCHEMA = 5" in core
assert not re.search(r"SetScript\(\s*[\"']OnUpdate", all_runtime), "polling OnUpdate introduced"

# The two optional UI owners are lazy: one definition and one demand-time call,
# with no file-scope construction.
assert debug.count("EnsureDeferredWorkFrame()") == 2, "debug defer owner is eager or duplicated"
assert options.count("EnsureDeferredWorkFrame()") == 2, "settings defer owner is eager or duplicated"

safe_number = re.search(r"local function SafeNumber\(value\)(.*?)\nend", core, re.DOTALL)
assert safe_number
body = safe_number.group(1)
assert 0 <= body.find("IsAccessible(value)") < body.find("type(value)"), (
    "SafeNumber must gate access before type/comparison"
)

access_gate = re.search(r"local function IsAccessible\(value\)(.*?)\nend", core, re.DOTALL)
assert access_gate and "pcall(canaccessvalue, value)" in access_gate.group(1)

frame_gate = re.search(r"local function FrameCanBeUsed\(frame\)(.*?)\nend", core, re.DOTALL)
assert frame_gate
body = frame_gate.group(1)
assert 0 <= body.find("CanBeAccessedInContext") < body.find("IsForbidden"), (
    "current-context access must precede other object probes"
)

assert 'elseif event == "ADDON_LOADED"' in core and "RELEVANT_ADDONS[addonName]" in core
assert 'elseif event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then' in core
assert 'elseif event == "COOLDOWN_VIEWER_DATA_LOADED" then' in core
assert 'event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED"' in core
assert 'event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELL_SECRECY_CHANGED"' in core
assert 'local changed, relevant = LearnExplicitOverride' in core
assert 'if not relevant or not changed then return end' in core
assert 'QueueReconcile(event, OVERLAY_RECONCILE_DELAY)' not in core

# Reassignment callbacks must conservatively hide an unreadable current assignment.
action_callback = re.search(
    r'RegisterCallback\("ActionButton.OnActionChanged"(.*?)end, R.actionCallbackOwner\)',
    core,
    re.DOTALL,
)
assert action_callback and "HideFrameGlow(button)" in action_callback.group(1)

# Dead redirect stubs were intentionally removed; architecture has one owner.
assert not (root / "CODE_INDEX.md").exists()
assert not (root / "CODE_GRAPH.md").exists()
assert not (root / "docs" / "RELEASE_1.3.1.md").exists()

print(f"static checks: PASS (interface={interface}, version={version}, runtime={', '.join(runtime_names)})")
