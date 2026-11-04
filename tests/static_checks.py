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
assert version == "1.4.5", f"unexpected addon version: {version!r}"
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
    "MAX_RESOLVED_SPELL_IDS = 128",
    "buttonsBySlot",
    "QueueActionRefresh",
    "MultiBarRightActionButton",
    "MultiBarBottomLeftActionButton",
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

table_gate = re.search(r"local function IsReadableTable\(value\)(.*?)\nend", core, re.DOTALL)
assert table_gate and "pcall(canaccesstable, value)" in table_gate.group(1)

merge_defaults = re.search(r"local function MergeNumericDefaults\(destination, defaults\)(.*?)\nend", core, re.DOTALL)
assert merge_defaults and "#result >= MAX_CONFIGURED_SPELL_IDS" in merge_defaults.group(1)

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

family_additions = re.findall(
    r"AddUniqueID\(R\.(?:targetFamily|signalFamily),\s*R\.(?:targetFamilyList|signalFamilyList),(.*?)\)",
    core,
)
assert family_additions and all("MAX_RESOLVED_SPELL_IDS" in call for call in family_additions), (
    "every resolved family insertion must carry the runtime cap"
)

rebuild = re.search(r"local function RebuildSpellFamilies\(\)(.*?)\nend", core, re.DOTALL)
assert rebuild
body = rebuild.group(1)
assert body.find("DB.signalSpellIDs") < body.find("#R.targetFamilyList"), (
    "configured signal aliases must reserve their family budget before learned target variants"
)

targeted_refresh = re.search(r"local function RefreshKnownButtons\(changedSlot\)(.*?)\nend", core, re.DOTALL)
assert targeted_refresh
body = targeted_refresh.group(1)
assert "R.buttonsBySlot[changedSlot]" in body and body.find("if changedSlot then") < body.find("R.knownButtons"), (
    "one-slot refresh must use the reverse slot index before any broad known-button pass"
)

queue_refresh = re.search(r"local function QueueActionRefresh\(changedSlot\)(.*?)\nend", core, re.DOTALL)
assert queue_refresh and "R.pendingActionSlots[changedSlot]" in queue_refresh.group(1)

regen_branch = re.search(
    r'elseif event == "PLAYER_REGEN_ENABLED" then(.*?)elseif event == "PLAYER_REGEN_DISABLED"',
    core,
    re.DOTALL,
)
assert regen_branch
body = regen_branch.group(1)
assert body.find("if R.needsRescan then") < body.find("RefreshAssignments()"), (
    "a required post-combat rescan must replace the immediate full assignment pass"
)

assert 'pcall(hooksecurefunc, frame, name' in core
assert 'pcall(hooksecurefunc, viewer, "OnAcquireItemFrame"' in core
assert "if ok then hooked[name] = true end" in core
assert "if hooked then R.cdmViewerHooks[viewer] = true end" in core

geometry = re.search(r"local function RefreshAlertGeometry\(frame, state\)(.*?)\nend", core, re.DOTALL)
assert geometry
body = geometry.group(1)
assert "state.sizeHookTargets" in body and "pcall(target.HookScript" in body
assert body.count("return false") >= 3, "geometry failures must stay dirty rather than reuse stale readiness"

# Reassignment callbacks must conservatively hide an unreadable current assignment.
action_callback = re.search(
    r'RegisterCallback\("ActionButton.OnActionChanged"(.*?)end, R.actionCallbackOwner\)',
    core,
    re.DOTALL,
)
assert action_callback and "HideFrameGlow(button)" in action_callback.group(1)


kb_pin = "c2a630aa186de401262663cc8568a77988be69df"
if (root / "AGENT_GUIDE.md").exists():
    for documentation in ("AGENT_GUIDE.md", "docs/API_CONTRACTS.md", "VALIDATION.md"):
        text = (root / documentation).read_text(encoding="utf-8")
        assert kb_pin in text, f"stale/missing knowledge-base pin in {documentation}"

# Dead redirect stubs were intentionally removed; architecture has one owner.
assert not (root / "CODE_INDEX.md").exists()
assert not (root / "CODE_GRAPH.md").exists()
assert not (root / "docs" / "RELEASE_1.3.1.md").exists()

print(f"static checks: PASS (interface={interface}, version={version}, runtime={', '.join(runtime_names)})")
