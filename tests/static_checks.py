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
assert version == "1.4.7", f"unexpected addon version: {version!r}"
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

mutation_checks = root / "tests" / "mutation_checks.py"
if (root / "tests").is_dir():
    assert mutation_checks.is_file(), "missing mutation sensitivity checks"

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
    "ParseActionSlotEvent",
    "ReadOptionalBooleanMethod",
    "IsAddOnFullyLoaded",
    "buttonsBySlot",
    "QueueActionRefresh",
    "ClearPendingActionRefresh",
    "FlushPendingActionRefresh",
    "CompleteRescanRequest",
    "InvalidateObservedAssignments",
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
assert "pcall(timers.NewTimer, 0.05, Run)" in debug
assert "refreshTimer = owner" in debug and "if refreshTimer ~= owner then return end" in debug
assert "pcall(cancel, handle)" in debug
assert "refreshTimer = timers.NewTimer" not in debug

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

member_gate = re.search(r"local function ReadMember\(container, key\)(.*?)\nend", core, re.DOTALL)
assert member_gate
body = member_gate.group(1)
assert 0 <= body.find("IsAccessible(container)") < body.find("ReadIndex"), (
    "foreign member lookup must be access-gated before indexing"
)
assert "pcall(ReadIndex, container, key)" in body

merge_defaults = re.search(r"local function MergeNumericDefaults\(destination, defaults\)(.*?)\nend", core, re.DOTALL)
assert merge_defaults and "#result >= MAX_CONFIGURED_SPELL_IDS" in merge_defaults.group(1)

frame_gate = re.search(r"FrameCanBeUsed = function\(frame\)(.*?)\nend", core, re.DOTALL)
assert frame_gate
body = frame_gate.group(1)
assert 0 <= body.find("CanBeAccessedInContext") < body.find("IsForbidden"), (
    "current-context access must precede other object probes"
)
assert "HasAccessConstraints" in body and "accessible ~= true" in body, (
    "conditionally constrained objects must require an affirmative current-access result"
)

optional_boolean = re.search(
    r"local function ReadOptionalBooleanMethod\(container, methodName\)(.*?)\nend",
    core,
    re.DOTALL,
)
assert optional_boolean and 'type(value) ~= "boolean"' in optional_boolean.group(1), (
    "object policy predicates must be ordinary booleans"
)

slot_payload = re.search(r"local function ParseActionSlotEvent\(value\)(.*?)\nend", core, re.DOTALL)
assert slot_payload
body = slot_payload.group(1)
assert body.find("IsAccessible(value)") < body.find("type(value)"), (
    "slot event payload must be gated before evaluation"
)
assert "if value == 0 then return nil, true end" in body

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
assert "matchesBySlot" in body, "one assignment pass must query each unique slot at most once"

queue_refresh = re.search(r"local function QueueActionRefresh\(changedSlot\)(.*?)\nend", core, re.DOTALL)
assert queue_refresh and "R.pendingActionSlots[changedSlot]" in queue_refresh.group(1)
assert "R.timers.rescan" in queue_refresh.group(1), (
    "a queued settled rescan must supersede another complete assignment pass"
)

request_rescan = re.search(r"function SDG:RequestRescan\(reason, deep\)(.*?)\nend", core, re.DOTALL)
assert request_rescan
body = request_rescan.group(1)
assert body.find("ClearPendingActionRefresh()") < body.find("R.timers.rescan"), (
    "rescan ownership must cancel pending assignment work before coalescing"
)
assert 'if scheduled then return true, "queued" end' in body
assert 'CompleteRescanRequest(self, reason)' in body and 'return true, "completed"' in body

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
item_hooks = re.search(r"local function HookCDMItem\(frame\)(.*?)\nend", core, re.DOTALL)
assert item_hooks
body = item_hooks.group(1)
assert "if not ok then" in body and "SuspendCDMFrame(frame)" in body
assert body.find("if not ok then") < body.find("hooked[name] = true"), (
    "failed item hooks must not restore assignment authority"
)
assert "return true" in body
assert "if hooked then" in core and "R.cdmViewerHooks[viewer] = true" in core
assert "allReadable = false" in core and "R.needsRescan = true" in core

cdm_reconcile = re.search(r"local function ReconcileCDMFrames\(\)(.*?)\nend", core, re.DOTALL)
assert cdm_reconcile
body = cdm_reconcile.group(1)
assert body.find("FrameCanBeUsed(viewer)") < body.find('ReadMember(viewer, "OnAcquireItemFrame")'), (
    "viewer current access must precede foreign acquire-method lookup"
)
assert 'IsAddOnFullyLoaded("Blizzard_CooldownViewer")' in body

geometry = re.search(
    r"local function RefreshAlertGeometry\(frame, state, resolvedTarget\)(.*?)\nend",
    core,
    re.DOTALL,
)
assert geometry
body = geometry.group(1)
assert "state.sizeHookTargets" in body and 'ReadMember(target, "HookScript")' in body
assert body.count("MarkGeometryDirty(state)") >= 6, (
    "geometry failures must stay dirty rather than reuse stale readiness"
)
assert 'ReadMember(target, "GetFrameLevel")' in body
assert "state.geometryToken = R.geometryToken" in body
assert "if state.renderTarget ~= target then return end" in body, (
    "stale size hooks must not mutate the current render target"
)

prime_geometry = re.search(r"local function PrimeTrackedAlerts\(forceGeometry\)(.*?)\nend", core, re.DOTALL)
assert prime_geometry
body = prime_geometry.group(1)
assert "if forceGeometry then R.geometryToken = {} end" in body
assert "RefreshAlertGeometry(" not in body, (
    "stable priming must delegate to idempotent EnsureAlert instead of repeating geometry mutations"
)

query_overlay = re.search(r"local function QueryOverlayState\(\)(.*?)\nend", core, re.DOTALL)
assert query_overlay and "R.queryHintSpellID" in query_overlay.group(1)

show_handler = re.search(r"local function HandleOverlayShow\(spellID\)(.*?)\nend", core, re.DOTALL)
hide_handler = re.search(r"local function HandleOverlayHide\(spellID\)(.*?)\nend", core, re.DOTALL)
assert show_handler and hide_handler
assert 'R.lastDetection ~= "overlay-query"' in show_handler.group(1)
assert "R.glowActive or not R.overlayQueryAuthoritative" in hide_handler.group(1)

named_mapping = re.search(r"local function MapNamedButtons\(\)(.*?)\nend", core, re.DOTALL)
assert named_mapping
body = named_mapping.group(1)
assert "IsAddOnFullyLoaded(provider)" in body and 'IsAddOnFullyLoaded("ElvUI")' in body

timer_scheduler = re.search(r"local function ScheduleTimer\(key, delay, callback\)(.*?)\nend", core, re.DOTALL)
assert timer_scheduler
body = timer_scheduler.group(1)
assert "pcall(C_Timer.NewTimer, delay, Run)" in body
assert "pcall(C_Timer.After, delay, Run)" in body
assert body.find("if ok then") < body.find("timer.handle = handle"), (
    "successful timer construction must own scheduled work even without a readable handle"
)

addon_loaded = re.search(r"local function IsAddOnFullyLoaded\(addonName\)(.*?)\nend", core, re.DOTALL)
assert addon_loaded
body = addon_loaded.group(1)
assert "_loadedOrLoading, loaded" in body and "loaded == true" in body
assert "return loadedOrLoading" not in body, (
    "loading-in-progress must not be treated as fully loaded"
)

render_target = re.search(r"local function GetRenderTarget\(frame\)(.*?)\nend", core, re.DOTALL)
assert render_target
body = render_target.group(1)
assert "if iconFrame ~= nil then" in body
assert "if not FrameCanBeUsed(iconFrame) then return nil end" in body, (
    "an assigned inaccessible icon target must not fall back to the parent button"
)

print_path = re.search(r"local function Print\(message\)(.*?)\nend", core, re.DOTALL)
assert print_path
body = print_path.group(1)
assert 'ReadMember(_G, "DEFAULT_CHAT_FRAME")' in body
assert 'ReadMember(chatFrame, "AddMessage")' in body and "pcall(addMessage" in body

signal_owner = re.search(r"local function SetEventSignal\(spellID\)(.*?)\nend", core, re.DOTALL)
assert signal_owner
body = signal_owner.group(1)
assert "local expires = ScheduleTimer" in body and "local reconciles = expires and ScheduleTimer" in body
assert "ClearEventSignal(spellID)" in body and "return false" in body

queue_refresh_body = queue_refresh.group(1)
assert "FlushPendingActionRefresh" in queue_refresh_body and "if not ScheduleTimer" in queue_refresh_body

reset_recover = re.search(r"local function ResetAndRecover\(reason\)(.*?)\nend", core, re.DOTALL)
assert reset_recover
body = reset_recover.group(1)
assert body.find("InvalidateObservedAssignments()") < body.find("RebuildSpellFamilies()")

assert "pcall(C_Timer.After, 0, function() SDG:OnLogin() end)" in core

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
