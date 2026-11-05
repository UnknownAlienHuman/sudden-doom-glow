local corePath = assert(arg[1], "Core.lua path required")
local coreDir = corePath:match("^(.*[/\\])") or ""

local now = 0
local inCombat = false
local timers = {}
local createdFrames = {}
local messages = {}
local actionCallbacks = {}
local queryCalls = 0
local actionSpellQueries = 0
local cdmEnumerations = 0
local unitEventRegistrations = 0
local geometryMutations = 0
local unpackValues = table.unpack or unpack
local secretValue = { secret = true }

local function NewAnimation(owner)
    local animation = { owner = owner, accessible = true, playing = false, playCount = 0 }
    function animation:CanBeAccessedInContext()
        return self.accessible ~= false and self.owner.accessible ~= false
    end
    function animation:IsForbidden() return false end
    function animation:Play()
        assert(self:CanBeAccessedInContext(), "played inaccessible animation")
        self.playing = true
        self.playCount = self.playCount + 1
    end
    function animation:Stop()
        assert(self:CanBeAccessedInContext(), "stopped inaccessible animation")
        self.playing = false
    end
    return animation
end

local function NewFrame(name, template)
    local frame = {
        name = name,
        template = template,
        accessible = true,
        shown = template ~= "ActionButtonSpellAlertTemplate",
        events = {}, scripts = {}, hooks = {}, attributes = {},
        width = 40, height = 40, frameLevel = 1,
        showCount = 0, hideCount = 0, gateLog = nil, slotReadCount = 0,
    }
    function frame:CanBeAccessedInContext()
        if self.gateLog then self.gateLog[#self.gateLog + 1] = "access" end
        return self.accessible ~= false
    end
    function frame:IsForbidden()
        if self.gateLog then self.gateLog[#self.gateLog + 1] = "forbidden" end
        return false
    end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:RegisterUnitEvent(event)
        unitEventRegistrations = unitEventRegistrations + 1
        self.events[event] = true
    end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        if self.failHookScript then error("HookScript failed") end
        self.hooks[script] = callback
    end
    function frame:GetObjectType() return "Button" end
    function frame:GetSize() return self.width, self.height end
    function frame:SetSize(w, h)
        assert(not inCombat, "SetSize in combat")
        geometryMutations = geometryMutations + 1
        self.width, self.height = w, h
    end
    function frame:ClearAllPoints()
        assert(not inCombat, "ClearAllPoints in combat")
        geometryMutations = geometryMutations + 1
    end
    function frame:SetPoint()
        assert(not inCombat, "SetPoint in combat")
        geometryMutations = geometryMutations + 1
    end
    function frame:SetAllPoints()
        assert(not inCombat, "SetAllPoints in combat")
        geometryMutations = geometryMutations + 1
    end
    function frame:SetParent(parent)
        assert(not inCombat, "SetParent in combat")
        geometryMutations = geometryMutations + 1
        self.parent = parent
    end
    function frame:GetFrameLevel()
        if self.failGetFrameLevel then error("GetFrameLevel failed") end
        return self.frameLevel
    end
    function frame:SetFrameLevel(level)
        assert(not inCombat, "SetFrameLevel in combat")
        if self.failSetFrameLevel then error("SetFrameLevel failed") end
        geometryMutations = geometryMutations + 1
        self.frameLevel = level
    end
    function frame:GetPagedID()
        self.slotReadCount = self.slotReadCount + 1
        return self.pagedAction or self.action
    end
    function frame:GetAction() return self.action end
    function frame:GetAttribute(key) return self.attributes[key] end
    function frame:Show()
        assert(self.accessible ~= false, "show inaccessible frame")
        self.shown = true
        self.showCount = self.showCount + 1
    end
    function frame:Hide()
        assert(self.accessible ~= false, "hide inaccessible frame")
        self.shown = false
        self.hideCount = self.hideCount + 1
    end
    function frame:IsShown() return self.shown end
    if template == "ActionButtonSpellAlertTemplate" then
        frame.ProcStartAnim = NewAnimation(frame)
        frame.ProcLoop = NewAnimation(frame)
    end
    return frame
end

function CreateFrame(_, name, _parent, template)
    assert(not (inCombat and template == "ActionButtonSpellAlertTemplate"), "created alert in combat")
    local frame = NewFrame(name, template)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

function InCombatLockdown() return inCombat end
function GetTime() return now end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
function IsLoggedIn() return true end
function EnumerateFrames() return nil end
function canaccessvalue(value) return value ~= secretValue end
function canaccesstable(value)
    if value.raiseTableAccess then error("table access probe failed") end
    return value.tableAccessible ~= false
end
function issecretvalue(value) return value == secretValue end
function GetMacroSpell() return nil end
function GetActionInfo(slot)
    local spellID = ({ [1] = 47541, [2] = 99999 })[slot]
    return spellID and "spell" or nil, spellID
end
function GetBuildInfo() return "12.1.5", "70783", "Nov 2026", 120105 end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}

C_Timer = {}
function C_Timer.NewTimer(delay, callback)
    local timer = { at = now + delay, callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
function C_Timer.After(delay, callback)
    timers[#timers + 1] = { at = now + delay, callback = callback, cancelled = false }
end
local function Advance(seconds)
    local target = now + seconds
    while true do
        local bestIndex, bestAt
        for i, timer in ipairs(timers) do
            if not timer.cancelled and timer.at <= target and (not bestAt or timer.at < bestAt) then
                bestIndex, bestAt = i, timer.at
            end
        end
        if not bestIndex then break end
        local timer = table.remove(timers, bestIndex)
        now = timer.at
        if not timer.cancelled then timer.callback() end
    end
    now = target
end

local loadedAddons = {
    Blizzard_CooldownViewer = true,
    Dominos = true,
}
local loadingAddons = {
    Bartender4 = true,
}
C_AddOns = {
    GetAddOnMetadata = function(_, field) return field == "Version" and "1.4.7" or nil end,
    IsAddOnLoaded = function(addonName)
        local loaded = loadedAddons[addonName] == true
        return loaded or loadingAddons[addonName] == true, loaded
    end,
}
local currentOverrideSpellID = 1242174
C_Spell = {
    GetBaseSpell = function(spellID)
        if spellID >= 800001 and spellID <= 800400 then return 47541 end
        return (spellID == 1242174 or spellID == 777001) and 47541 or spellID
    end,
    GetOverrideSpell = function(spellID)
        return spellID == 47541 and currentOverrideSpellID or spellID
    end,
}
local actions = { [1] = 47541, [2] = 99999 }
C_ActionBar = { GetSpell = function(slot)
    actionSpellQueries = actionSpellQueries + 1
    return actions[slot]
end }
local overlayState = {}
C_SpellActivationOverlay = {
    IsSpellOverlayed = function(spellID)
        queryCalls = queryCalls + 1
        return overlayState[spellID] == true
    end,
}

EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback, owner)
    actionCallbacks[event] = { callback = callback, owner = owner }
end
function EventRegistry:UnregisterCallback(event, owner)
    local record = actionCallbacks[event]
    if record and record.owner == owner then actionCallbacks[event] = nil end
end

function hooksecurefunc(target, methodName, hook)
    if target.hookFailures and target.hookFailures[methodName] then
        target.hookFailures[methodName] = target.hookFailures[methodName] - 1
        if target.hookFailures[methodName] <= 0 then target.hookFailures[methodName] = nil end
        error("hook installation failed")
    end
    local original = assert(target[methodName], methodName)
    target[methodName] = function(...)
        local values = { original(...) }
        hook(...)
        return unpackValues(values)
    end
end

local function NewCDMItem(name, spellID)
    local item = NewFrame(name)
    item.baseSpellID = spellID
    function item:GetBaseSpellID() return self.baseSpellID end
    function item:SetCooldownID(id) self.cooldownID = id end
    function item:SetOverrideSpell(id) self.overrideSpellID = id end
    function item:ClearCooldownID() self.cooldownID = nil; self.baseSpellID = nil end
    function item:ResetCooldownData() self.cooldownID = nil; self.baseSpellID = nil end
    return item
end

local activeEssential = {}
local function NewPool(list)
    local pool = {}
    function pool:EnumerateActive()
        cdmEnumerations = cdmEnumerations + 1
        local index = 0
        return function()
            index = index + 1
            return list[index]
        end
    end
    return pool
end
local function NewViewer(name, list)
    local viewer = NewFrame(name)
    viewer.itemFramePool = NewPool(list)
    function viewer:OnAcquireItemFrame() end
    return viewer
end

local cdmItem = NewCDMItem("CDMItem", 47541)
activeEssential[1] = cdmItem
EssentialCooldownViewer = NewViewer("EssentialCooldownViewer", activeEssential)
UtilityCooldownViewer = NewViewer("UtilityCooldownViewer", {})
BuffIconCooldownViewer = NewViewer("BuffIconCooldownViewer", {})
BuffBarCooldownViewer = NewViewer("BuffBarCooldownViewer", {})

ActionButton1 = NewFrame("ActionButton1")
ActionButton1.action = 1
ActionButton2 = NewFrame("ActionButton2")
ActionButton2.action = 2
MultiBarRightActionButton1 = NewFrame("MultiBarRightActionButton1")
MultiBarRightActionButton1.action = 1
BT4Button1 = NewFrame("BT4Button1")
BT4Button1.action = 1
ElvUI_Bar1Button1 = NewFrame("ElvUI_Bar1Button1")
ElvUI_Bar1Button1.action = 1

Settings = { VarType = { Boolean = "boolean", Number = "number" } }
local settingsCategory = { GetID = function() return 321 end }
local registeredSettings = {}
function Settings.RegisterVerticalLayoutCategory() return settingsCategory end
function Settings.RegisterAddOnSetting(_category, variable, key, variableTable, kind, label, defaultValue)
    if variableTable[key] == nil then variableTable[key] = defaultValue end
    local setting = {
        variable = variable, key = key, variableTable = variableTable,
        kind = kind, label = label,
    }
    function setting:SetValueChangedCallback(callback) self.callback = callback end
    function setting:GetValue() return self.variableTable[self.key] end
    function setting:SetValue(value)
        assert(type(value) == self.kind)
        self.variableTable[self.key] = value
        if self.callback then self.callback(self, value) end
    end
    registeredSettings[variable] = setting
    return setting
end
function Settings.CreateCheckbox() end
function Settings.CreateSliderOptions() return {} end
function Settings.CreateSlider() end
function Settings.RegisterAddOnCategory() end
function Settings.NotifyUpdate(variable)
    local setting = registeredSettings[variable]
    if setting and setting.callback then setting.callback(setting, setting:GetValue()) end
end
function Settings.OpenToCategory() end

SuddenDoomGlowDB = { enabled = true, debug = false, cdm = true }
local addon = {}

assert(loadfile(corePath))("SuddenDoomGlow", addon)
Advance(0)
local SDG = addon
local R = assert(SDG.runtime)
local eventFrame = assert(createdFrames[1])
local function Fire(event, ...)
    eventFrame.scripts.OnEvent(eventFrame, event, ...)
end

assert(R.runtimeRegistered, "runtime did not start")
assert(unitEventRegistrations == 0, "unrelated UNIT_SPELLCAST_SUCCEEDED owner remains")
assert(not eventFrame.events.UNIT_SPELLCAST_SUCCEEDED, "spellcast event remains registered")
assert(R.knownButtons[MultiBarRightActionButton1],
    "current Dominos compatibility-name button was not discovered")
assert(R.frameState[MultiBarRightActionButton1] and R.frameState[MultiBarRightActionButton1].alert,
    "current Dominos compatibility-name button was not prepared before combat")
assert(not R.knownButtons[BT4Button1] and not R.frameState[BT4Button1],
    "loading-but-not-loaded Bartender4 family was scanned eagerly")
assert(not R.knownButtons[ElvUI_Bar1Button1] and not R.frameState[ElvUI_Bar1Button1],
    "unloaded ElvUI family was scanned eagerly")

-- Object access must precede IsForbidden.
local gateLog = {}
ActionButton1.gateLog = gateLog
assert(actionCallbacks["ActionButton.OnActionChanged"], "action callback missing")
actionCallbacks["ActionButton.OnActionChanged"].callback(nil, ActionButton1)
ActionButton1.gateLog = nil
assert(gateLog[1] == "access" and gateLog[2] == "forbidden", "object gates are in the wrong order")

-- Foreign member lookup is itself an access boundary. A hostile metatable must
-- not escape the action-button adapter before the current assignment is read.
local hostileButton = setmetatable({ raiseTableAccess = false, tableAccessible = true }, {
    __index = function(_, key)
        if key == "CanBeAccessedInContext" then return function() return true end end
        if key == "IsForbidden" then return function() return false end end
        error("foreign action-button member read")
    end,
})
assert(pcall(actionCallbacks["ActionButton.OnActionChanged"].callback, nil, hostileButton),
    "foreign action-button member read escaped the adapter boundary")

-- Access predicates are ordinary booleans, not truthy compatibility values.
local malformedAccessButton = NewFrame("MalformedAccessButton")
malformedAccessButton.action = 1
function malformedAccessButton:CanBeAccessedInContext() return 1 end
assert(pcall(actionCallbacks["ActionButton.OnActionChanged"].callback, nil, malformedAccessButton),
    "malformed access predicate escaped the adapter boundary")
assert(not R.trackedButtons[malformedAccessButton] and not R.buttonSlots[malformedAccessButton],
    "malformed access predicate retained assignment ownership")
local constrainedWithoutContext = {
    action = 1,
    HasAccessConstraints = function() return true end,
    IsForbidden = function() return false end,
}
assert(pcall(actionCallbacks["ActionButton.OnActionChanged"].callback, nil, constrainedWithoutContext),
    "constrained object without a current-access predicate escaped the adapter")
assert(not R.trackedButtons[constrainedWithoutContext] and not R.buttonSlots[constrainedWithoutContext],
    "constrained object without current access retained assignment ownership")

-- A relevant SHOW payload is the best first query candidate. This preserves
-- authoritative all-false reconciliation while avoiding a linear active scan.
overlayState[450932] = true
queryCalls = 0
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 450932)
assert(queryCalls == 1, "relevant SHOW payload was not queried first")
Advance(0.10)
assert(queryCalls == 1, "authoritative positive SHOW scheduled a redundant delayed query")
overlayState[450932] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 450932)
local queriesAfterAuthoritativeHide = queryCalls
Advance(0.10)
assert(queryCalls == queriesAfterAuthoritativeHide,
    "authoritative all-false HIDE scheduled a redundant delayed query")
Advance(0.3)

overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
local preAccessState = assert(R.frameState[ActionButton1])
assert(preAccessState.shown, "precondition: action alert did not show")
assert(R.frameState[MultiBarRightActionButton1].shown,
    "current Dominos compatibility-name button did not receive the proc glow")
local activeAlert = assert(preAccessState.alert)
activeAlert.accessible = false
Fire("PLAYER_REGEN_ENABLED")
assert(not preAccessState.animating,
    "active alert cached object access across an explicit lifecycle boundary")
activeAlert.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(preAccessState.animating,
    "active alert did not recover after current object access returned")
ActionButton1.accessible = false
actionCallbacks["ActionButton.OnActionChanged"].callback(nil, ActionButton1)
assert(not preAccessState.shown, "unreadable reassignment left a stale action glow")
assert(not R.trackedButtons[ActionButton1] and not R.buttonSlots[ActionButton1],
    "unreadable reassignment retained stale assignment ownership")
ActionButton1.accessible = true
actionCallbacks["ActionButton.OnActionChanged"].callback(nil, ActionButton1)
assert(preAccessState.shown, "readable reassignment did not restore the current target glow")
assert(R.trackedButtons[ActionButton1] and R.buttonSlots[ActionButton1] == 1,
    "readable reassignment did not restore assignment ownership")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)

-- Unrelated addon loads do not rescan; supported integration loads do.
local enumBefore = cdmEnumerations
Fire("ADDON_LOADED", "TotallyUnrelatedAddon")
Advance(0.2)
assert(cdmEnumerations == enumBefore, "unrelated ADDON_LOADED triggered a rescan")
loadingAddons.Bartender4 = nil
loadedAddons.Bartender4 = true
Fire("ADDON_LOADED", "Bartender4")
Advance(0.2)
assert(cdmEnumerations > enumBefore, "relevant ADDON_LOADED did not trigger recovery")
assert(R.knownButtons[BT4Button1] and R.frameState[BT4Button1] and R.frameState[BT4Button1].alert,
    "Bartender4 family was not discovered after its authoritative load event")
loadedAddons.ElvUI = true
Fire("ADDON_LOADED", "ElvUI")
Advance(0.2)
assert(R.knownButtons[ElvUI_Bar1Button1] and R.frameState[ElvUI_Bar1Button1]
    and R.frameState[ElvUI_Bar1Button1].alert,
    "ElvUI family was not discovered after its authoritative load event")
local enumBeforeDataReady = cdmEnumerations
Fire("COOLDOWN_VIEWER_DATA_LOADED")
Advance(0.2)
assert(cdmEnumerations > enumBeforeDataReady, "public CDM data readiness did not trigger recovery")

-- One-slot invalidation touches only buttons already indexed to that slot;
-- the next-frame broad pass still covers providers that settle after the event.
ActionButton1.slotReadCount = 0
ActionButton2.slotReadCount = 0
MultiBarRightActionButton1.slotReadCount = 0
queryCalls = 0
actionSpellQueries = 0
Fire("ACTIONBAR_SLOT_CHANGED", 1)
assert(ActionButton1.slotReadCount > 0 and MultiBarRightActionButton1.slotReadCount > 0,
    "targeted slot refresh missed current slot owners")
assert(ActionButton2.slotReadCount == 0,
    "one-slot invalidation scanned an unrelated known button")
assert(actionSpellQueries == 1,
    "one-slot invalidation queried the same action slot once per button")
Advance(0)
assert(ActionButton2.slotReadCount == 0,
    "deferred one-slot recovery became an unrelated full scan")
assert(actionSpellQueries == 2,
    "deferred one-slot recovery did not reuse one query per unique slot")

-- Denied/malformed slot payloads are not equivalent to the explicit broad zero.
ActionButton1.slotReadCount = 0
ActionButton2.slotReadCount = 0
Fire("ACTIONBAR_SLOT_CHANGED", secretValue)
Fire("ACTIONBAR_SLOT_CHANGED", -1)
Fire("ACTIONBAR_SLOT_CHANGED", 1.5)
Advance(0)
assert(ActionButton1.slotReadCount == 0 and ActionButton2.slotReadCount == 0,
    "invalid ACTIONBAR_SLOT_CHANGED payload became a broad refresh")
Fire("ACTIONBAR_SLOT_CHANGED", 0)
Advance(0)
assert(ActionButton1.slotReadCount > 0 and ActionButton2.slotReadCount > 0,
    "explicit broad ACTIONBAR_SLOT_CHANGED(0) did not refresh known buttons")

-- A settled rescan supersedes an already queued broad assignment pass.
ActionButton1.slotReadCount = 0
ActionButton2.slotReadCount = 0
Fire("ACTIONBAR_PAGE_CHANGED")
assert(R.timers["action-refresh"], "broad assignment refresh was not queued")
assert(SDG:RequestRescan("test-supersedes-action-refresh", false))
assert(not R.timers["action-refresh"], "settled rescan retained redundant assignment work")
Advance(0.2)
assert(ActionButton1.slotReadCount == 1 and ActionButton2.slotReadCount == 1,
    "rescan plus queued assignment owner performed duplicate full passes")

-- World entry similarly owns one settled pass instead of one immediate pass plus rescan.
ActionButton1.slotReadCount = 0
ActionButton2.slotReadCount = 0
Fire("PLAYER_ENTERING_WORLD")
assert(ActionButton1.slotReadCount == 0 and ActionButton2.slotReadCount == 0,
    "world-entry reset performed assignment work before its settled rescan")
assert(not next(R.trackedButtons) and not next(R.buttonSlots),
    "world-entry reset retained stale action assignment ownership")
assert(R.frameState[cdmItem] and R.frameState[cdmItem].assignmentReadable == false,
    "world-entry reset retained stale Cooldown Viewer assignment authority")
assert(R.targetFamily[47541] and R.signalFamily[450932],
    "world-entry reset did not rebuild bounded configured spell families")
Advance(0.2)
assert(ActionButton1.slotReadCount == 1 and ActionButton2.slotReadCount == 1,
    "world-entry recovery performed more than one full assignment pass")
assert(R.trackedButtons[ActionButton1] and R.frameState[cdmItem].assignmentReadable == true,
    "settled world-entry recovery did not restore current assignments")

queryCalls = 0
Fire("ACTIONBAR_PAGE_CHANGED")
Advance(0)
assert(ActionButton2.slotReadCount > 0,
    "coalesced broad assignment recovery did not run")
assert(queryCalls == 0, "action events queried independent proc state")

-- An opaque HIDE remains a wake-up only while evidence is active; it is never
-- indexed or compared as a spell ID.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
overlayState[47541] = false
queryCalls = 0
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", secretValue)
assert(queryCalls == 0, "opaque HIDE payload was queried synchronously")
Advance(0.25)
assert(queryCalls > 0 and not R.glowActive,
    "opaque HIDE did not wake authoritative candidate reconciliation after grace")
queryCalls = 0
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 999999)
Advance(0.10)
assert(queryCalls == 0, "irrelevant HIDE woke the query while no evidence was active")

-- A CDM table hotfix must not toggle an already active glow or restart art.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
Advance(0.1)
local actionState = assert(R.frameState[ActionButton1])
local actionAlert = assert(actionState.alert)
assert(R.glowActive and actionState.shown, "precondition: proc glow did not start")
local showCount, hideCount = actionAlert.showCount, actionAlert.hideCount
local playCount = actionAlert.ProcStartAnim.playCount + actionAlert.ProcLoop.playCount
Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 47541, 777001)
assert(R.explicitOverrides[47541] == 777001, "explicit override event was not retained")
Fire("COOLDOWN_VIEWER_TABLE_HOTFIXED")
Advance(0.2)
assert(R.glowActive and actionState.shown, "CDM hotfix cleared active proc state")
assert(R.targetFamily[777001], "CDM hotfix discarded a current runtime override observation")
assert(actionAlert.showCount == showCount and actionAlert.hideCount == hideCount,
    "CDM hotfix toggled the visible alert")
assert(actionAlert.ProcStartAnim.playCount + actionAlert.ProcLoop.playCount == playCount,
    "CDM hotfix restarted the alert animation")

-- Talent/spell invalidations rebuild assignment identity without forcing a proc edge.
currentOverrideSpellID = 1242174
showCount, hideCount = actionAlert.showCount, actionAlert.hideCount
playCount = actionAlert.ProcStartAnim.playCount + actionAlert.ProcLoop.playCount
queryCalls = 0
Fire("PLAYER_TALENT_UPDATE")
Fire("TRAIT_CONFIG_UPDATED")
Fire("SPELLS_CHANGED")
assert(queryCalls == 0, "mapping invalidations queried before the coalesced recovery pass")
Advance(0.2)
assert(queryCalls == 1, "mapping invalidation burst did not collapse into one proc query")
assert(R.glowActive and actionState.shown, "mapping invalidation cleared active proc state")
assert(not R.targetFamily[777001] and R.targetFamily[1242174],
    "mapping invalidation retained a stale explicit override")
assert(actionAlert.showCount == showCount and actionAlert.hideCount == hideCount,
    "mapping invalidation toggled the visible alert")
assert(actionAlert.ProcStartAnim.playCount + actionAlert.ProcLoop.playCount == playCount,
    "mapping invalidation restarted the alert animation")

-- Irrelevant override updates do not query independent proc state.
queryCalls = 0
Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 99999, 99998)
assert(queryCalls == 0, "irrelevant override update queried proc state")

-- If animation objects are temporarily inaccessible, a lifecycle wake retries art
-- without requiring a second proc edge.
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
Advance(0.3)
actionAlert.ProcStartAnim.accessible = false
actionAlert.ProcLoop.accessible = false
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(actionState.shown and not actionState.animating, "inaccessible animation was treated as running")
actionAlert.ProcStartAnim.accessible = true
actionAlert.ProcLoop.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(actionState.animating, "lifecycle wake did not recover missed animation")

-- Pageable non-target alerts must retain geometry recovery ownership even when
-- their alert is temporarily inaccessible, and a later render target is hooked once.
local dormantState = assert(R.frameState[ActionButton2])
local dormantAlert = assert(dormantState.alert)
dormantAlert.accessible = false
assert(SDG:SetOption("glowScale", 1.5))
assert(R.needsGeometry and not dormantState.geometryReady,
    "inaccessible dormant alert lost its geometry recovery state")
dormantAlert.accessible = true
local iconTarget = NewFrame("ActionButton2Icon")
function iconTarget:GetObjectType() return "Frame" end
ActionButton2.Icon = iconTarget
iconTarget.failHookScript = true
Fire("PLAYER_REGEN_ENABLED")
assert(R.needsGeometry and not dormantState.geometryReady and not iconTarget.hooks.OnSizeChanged,
    "failed size-hook installation was incorrectly marked complete")
iconTarget.failHookScript = nil
Fire("PLAYER_REGEN_ENABLED")
assert(dormantState.geometryReady and not R.needsGeometry,
    "geometry recovery did not complete after access returned")
assert(iconTarget.hooks.OnSizeChanged,
    "replacement render target did not receive one size-change recovery hook")

iconTarget.failGetFrameLevel = true
assert(SDG:SetOption("glowScale", 1.55))
assert(R.needsGeometry and not dormantState.geometryReady,
    "failed frame-level read was incorrectly marked complete")
iconTarget.failGetFrameLevel = nil
Fire("PLAYER_REGEN_ENABLED")
assert(dormantState.geometryReady and not R.needsGeometry,
    "frame-level read recovery did not complete")

dormantAlert.failSetFrameLevel = true
assert(SDG:SetOption("glowScale", 1.6))
assert(R.needsGeometry and not dormantState.geometryReady,
    "failed frame-level mutation was incorrectly marked complete")
dormantAlert.failSetFrameLevel = nil
Fire("PLAYER_REGEN_ENABLED")
assert(dormantState.geometryReady and not R.needsGeometry,
    "frame-level recovery did not complete")

-- A new render target invalidates cached geometry even when the old surface was
-- complete; a stable rescan must not repeat already completed mutations.
local replacementTarget = NewFrame("ActionButton2ReplacementIcon")
function replacementTarget:GetObjectType() return "Frame" end
ActionButton2.Icon = replacementTarget
SDG:RescanButtons(false)
assert(dormantState.renderTarget == replacementTarget and dormantAlert.parent == replacementTarget,
    "render-target replacement reused stale geometry")
local staleTargetMutationCount = geometryMutations
iconTarget.hooks.OnSizeChanged()
assert(geometryMutations == staleTargetMutationCount,
    "stale render-target hook mutated the current surface")
local stableGeometryMutations = geometryMutations
SDG:RescanButtons(false)
assert(geometryMutations == stableGeometryMutations,
    "stable rescan repeated completed geometry mutations")

-- An assigned but temporarily inaccessible icon target is incomplete evidence;
-- it must never make the alert fall back to the parent button.
local deniedTargetMutationCount = geometryMutations
replacementTarget.accessible = false
SDG:RescanButtons(false)
assert(dormantAlert.parent == replacementTarget,
    "inaccessible render target silently reparented the alert to its button")
assert(not dormantState.geometryReady and R.needsGeometry,
    "inaccessible render target retained stale geometry readiness")
assert(geometryMutations == deniedTargetMutationCount,
    "inaccessible render target caused structural fallback mutations")
replacementTarget.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(dormantState.geometryReady and dormantAlert.parent == replacementTarget,
    "render target did not recover after current access returned")

replacementTarget.width = 46
R.needsGeometry = false
local currentTargetMutationCount = geometryMutations
replacementTarget.hooks.OnSizeChanged()
assert(geometryMutations > currentTargetMutationCount and dormantState.geometryReady
    and not R.needsGeometry,
    "successful current-target size refresh left global geometry recovery dirty")

-- A global geometry change cannot be written into an inaccessible frame-keyed
-- state. The generation token must invalidate it when access returns.
local widthBeforeDeniedScale = dormantAlert.width
ActionButton2.accessible = false
assert(SDG:SetOption("glowScale", 1.7))
assert(R.needsGeometry, "inaccessible button lost global geometry invalidation")
ActionButton2.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(dormantState.geometryReady and dormantState.geometryToken == R.geometryToken,
    "returned button reused a geometry generation from before access denial")
assert(dormantAlert.width ~= widthBeforeDeniedScale
    and dormantAlert.width == replacementTarget.width * 1.7,
    "returned button did not apply the deferred global geometry change")

-- Missing one selected viewer is incomplete evidence and cannot prune an item
-- omitted from another readable pool during the same transition.
local savedUtility = UtilityCooldownViewer
UtilityCooldownViewer = nil
activeEssential[1] = nil
SDG:RescanButtons(false)
assert(R.cdmFrames[cdmItem], "partial viewer availability pruned tracked item")
UtilityCooldownViewer = savedUtility
activeEssential[1] = cdmItem

-- An inaccessible external pool table is also incomplete evidence.
UtilityCooldownViewer.itemFramePool.tableAccessible = false
activeEssential[1] = nil
SDG:RescanButtons(false)
assert(R.cdmFrames[cdmItem], "inaccessible viewer pool table pruned tracked item")
UtilityCooldownViewer.itemFramePool.tableAccessible = true
UtilityCooldownViewer.itemFramePool.raiseTableAccess = true
assert(pcall(SDG.RescanButtons, SDG, false),
    "failing canaccesstable probe escaped the external-pool boundary")
assert(R.cdmFrames[cdmItem], "failed viewer pool access probe pruned tracked item")
UtilityCooldownViewer.itemFramePool.raiseTableAccess = nil
activeEssential[1] = cdmItem

-- Current viewer access must be established before any other foreign member is
-- inspected. A denied viewer is incomplete evidence, not an adapter exception.
local savedDeniedViewer = UtilityCooldownViewer
local deniedViewer = setmetatable({ tableAccessible = true }, {
    __index = function(_, key)
        if key == "CanBeAccessedInContext" then return function() return false end end
        error("denied viewer member read")
    end,
})
UtilityCooldownViewer = deniedViewer
assert(pcall(SDG.RescanButtons, SDG, false),
    "viewer member lookup happened before the current-access gate")
UtilityCooldownViewer = savedDeniedViewer

-- Foreign hook installation is an error boundary: failed hooks do not escape or
-- become false-positive registrations, and a later lifecycle pass retries them.
local savedUtilityViewer = UtilityCooldownViewer
local flakyViewer = NewViewer("FlakyUtilityViewer", {})
flakyViewer.hookFailures = { OnAcquireItemFrame = 1 }
UtilityCooldownViewer = flakyViewer
assert(pcall(SDG.RescanButtons, SDG, false), "viewer hook failure escaped recovery")
assert(not R.cdmViewerHooks[flakyViewer], "failed viewer hook was marked installed")
assert(R.needsRescan, "failed viewer hook did not retain lifecycle recovery ownership")
SDG:RescanButtons(false)
assert(R.cdmViewerHooks[flakyViewer] and not R.needsRescan,
    "viewer hook was not retried to a complete generation")
UtilityCooldownViewer = savedUtilityViewer

-- Enabling CDM in combat must not enumerate pools or attach a newly observed item.
assert(SDG:SetOption("cdm", false))
local newItem = NewCDMItem("NewCDMItem", 47541)
newItem.hookFailures = { SetCooldownID = 1 }
activeEssential[1] = newItem
local enumAtCombat = cdmEnumerations
inCombat = true
assert(SDG:SetOption("cdm", true))
assert(cdmEnumerations == enumAtCombat, "CDM pools enumerated in combat")
assert(not R.cdmItemHooks[newItem], "new CDM item was hooked in combat")
inCombat = false
ActionButton1.slotReadCount = 0
ActionButton2.slotReadCount = 0
Fire("PLAYER_REGEN_ENABLED")
assert(ActionButton1.slotReadCount == 0 and ActionButton2.slotReadCount == 0,
    "combat exit duplicated assignment work before the queued settled rescan")
Advance(0.2)
assert(ActionButton1.slotReadCount > 0 and ActionButton2.slotReadCount > 0,
    "settled post-combat rescan did not refresh assignments")
assert(cdmEnumerations > enumAtCombat and R.cdmItemHooks[newItem],
    "post-combat CDM recovery did not inspect the new item")
assert(not R.cdmItemHooks[newItem].SetCooldownID,
    "failed item hook was marked installed")
assert(not R.cdmFrames[newItem]
    and (not R.frameState[newItem] or R.frameState[newItem].assignmentReadable ~= true),
    "partially hooked Cooldown Viewer item retained render authority")
assert(R.needsRescan, "failed item hook did not retain lifecycle recovery ownership")
SDG:RescanButtons(false)
assert(R.cdmItemHooks[newItem].SetCooldownID and R.cdmFrames[newItem]
    and R.frameState[newItem].assignmentReadable == true,
    "item hook was not retried before assignment authority was restored")

-- Every selected lifecycle method is mandatory. A known-missing method is not
-- permission to render a pooled item whose future reset cannot be observed.
local incompleteItem = NewCDMItem("IncompleteCDMItem", 47541)
local savedResetCooldownData = incompleteItem.ResetCooldownData
incompleteItem.ResetCooldownData = nil
activeEssential[1] = incompleteItem
SDG:RescanButtons(false)
assert(not R.cdmFrames[incompleteItem]
    and (not R.frameState[incompleteItem] or R.frameState[incompleteItem].assignmentReadable ~= true),
    "item with an incomplete reset contract retained render authority")
incompleteItem.ResetCooldownData = savedResetCooldownData
SDG:RescanButtons(false)
assert(R.cdmFrames[incompleteItem] and R.cdmItemHooks[incompleteItem].ResetCooldownData,
    "completed item lifecycle was not recovered on a later pass")
activeEssential[1] = newItem

-- Unsupported future schemas must refuse all spell-list commands explicitly.
R.unsupportedSchema = true
local messageBase = #messages
SlashCmdList.SUDDEN_DOOM_GLOW("spell 47541")
SlashCmdList.SUDDEN_DOOM_GLOW("signal 450932")
SlashCmdList.SUDDEN_DOOM_GLOW("spells")
assert(#messages == messageBase + 3, "future-schema spell commands did not report refusal")
R.unsupportedSchema = false

-- Public diagnostics drop inaccessible values before tostring/concatenation.
local beforeSecretPrint = #messages
assert(pcall(SDG.Print, SDG, secretValue), "secret diagnostic value raised")
assert(#messages == beforeSecretPrint, "secret diagnostic value was printed")
local savedChatFrame = DEFAULT_CHAT_FRAME
DEFAULT_CHAT_FRAME = setmetatable({
    CanBeAccessedInContext = function() return true end,
}, {
    __index = function() error("hostile chat-frame member read") end,
})
assert(pcall(SDG.Print, SDG, "guarded chat output"),
    "hostile chat-frame member read escaped diagnostics")
assert(#messages == beforeSecretPrint,
    "unverified chat frame received diagnostic output")
DEFAULT_CHAT_FRAME = savedChatFrame

-- Disabled runtimes report rescan refusal instead of a false queued message.
assert(SDG:SetOption("enabled", false))
assert(SDG:RequestRescan("disabled", false) == false, "disabled runtime accepted rescan")
assert(SDG:SetOption("enabled", true))

-- Optional UI owners attach once and ordinary registration remains usable.
local frameCount = #createdFrames
assert(loadfile(coreDir .. "Debug.lua"))("SuddenDoomGlow", addon)
assert(loadfile(coreDir .. "Options.lua"))("SuddenDoomGlow", addon)
assert(#createdFrames == frameCount, "optional UI modules created idle event-owner frames")
assert(SDG:RegisterSettings(), "Settings registration failed")
assert(registeredSettings.SuddenDoomGlow_Enabled and registeredSettings.SuddenDoomGlow_CooldownViewer
    and registeredSettings.SuddenDoomGlow_Debug and registeredSettings.SuddenDoomGlow_GlowScale,
    "ordinary SavedVariables fields were not registered as addon settings")
assert(not Settings.RegisterProxySetting, "test unexpectedly retained proxy setting support")

local enabledSetting = registeredSettings.SuddenDoomGlow_Enabled
enabledSetting:SetValue(false)
assert(not SuddenDoomGlowDB.enabled and not R.runtimeRegistered,
    "direct addon setting did not stop the runtime")
enabledSetting:SetValue(true)
assert(SuddenDoomGlowDB.enabled and R.runtimeRegistered,
    "direct addon setting did not restart the runtime")

-- Runtime replacement learning is bounded independently of SavedVariables.
-- Explicit signal aliases remain present when target variants consume the budget.
local variantButton = NewFrame("VariantButton")
for i = 1, 220 do
    local slot = 1000 + i
    actions[slot] = 800000 + i
    variantButton.action = slot
    actionCallbacks["ActionButton.OnActionChanged"].callback(nil, variantButton)
end
assert(#R.targetFamilyList <= 128, "resolved target family exceeded its runtime bound")
assert(#R.signalFamilyList <= 128, "resolved signal family exceeded its runtime bound")
assert(R.signalFamily[450932] and R.signalFamily[81340],
    "configured signal aliases were displaced by learned target variants")
assert(R.buttonSlots[variantButton] == 1220 and R.buttonsBySlot[1220][variantButton],
    "button slot index did not retain the latest assignment")
assert(not R.buttonsBySlot[1001], "button slot index retained an obsolete empty set")

-- Timer ownership remains correct when NewTimer returns an inaccessible handle,
-- falls back to After, or every timer constructor rejects the request.
local savedNewTimer = C_Timer.NewTimer
local savedAfter = C_Timer.After
C_Timer.NewTimer = function(delay, callback)
    savedNewTimer(delay, callback)
    return secretValue
end
ActionButton1.slotReadCount = 0
local accepted, mode = SDG:RequestRescan("inaccessible-timer-handle", false)
assert(accepted and mode == "queued" and R.timers.rescan and not R.timers.rescan.handle,
    "successful timer with inaccessible handle lost logical ownership")
Advance(0.2)
assert(ActionButton1.slotReadCount > 0 and not R.timers.rescan,
    "identity-owned timer with inaccessible handle did not complete")

C_Timer.NewTimer = function() error("timer creation failed") end
ActionButton1.slotReadCount = 0
accepted, mode = SDG:RequestRescan("timer-after-fallback", false)
assert(accepted and mode == "queued" and R.timers.rescan,
    "NewTimer failure did not fall back to cancellable identity-owned After work")
Advance(0.2)
assert(ActionButton1.slotReadCount > 0 and not R.timers.rescan,
    "After fallback did not complete the required rescan")

C_Timer.After = function() error("after creation failed") end
ActionButton1.slotReadCount = 0
accepted, mode = SDG:RequestRescan("timer-synchronous-fallback", false)
assert(accepted and mode == "completed" and ActionButton1.slotReadCount > 0,
    "total timer failure dropped required rescan recovery")
assert(not R.timers.rescan and R.rescanReason == nil and not R.rescanDeep,
    "synchronous rescan fallback retained stale timer ownership")

ActionButton1.slotReadCount = 0
Fire("ACTIONBAR_PAGE_CHANGED")
assert(ActionButton1.slotReadCount > 0 and not R.timers["action-refresh"]
    and not R.actionRefreshAll and not next(R.pendingActionSlots),
    "timer failure stranded broad assignment recovery")

queryCalls = 0
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(not R.eventSignals[47541] and not R.glowActive,
    "event-only evidence survived without both bounded terminal timers")
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", secretValue)
assert(queryCalls > 0, "opaque wake-up was dropped when delayed timer construction failed")

overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive and R.lastQueryActiveAt, "precondition: positive query was not retained")
local savedOverlayQuery = C_SpellActivationOverlay.IsSpellOverlayed
C_SpellActivationOverlay.IsSpellOverlayed = function() return secretValue end
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(not R.glowActive and R.lastQueryActiveAt == nil and not R.timers["query-expire"],
    "positive query evidence survived without a terminal expiry owner")
C_SpellActivationOverlay.IsSpellOverlayed = savedOverlayQuery
overlayState[47541] = false
assert(SDG:TestGlow() == false and R.testUntil == 0 and not R.glowActive,
    "test glow remained active after terminal timer failure")

C_Timer.NewTimer = savedNewTimer
C_Timer.After = savedAfter

-- A full legacy list plus seeded defaults must still respect the hard bound.
assert(SDG:SetOption("enabled", false))
local legacyTargets, legacySignals = {}, {}
for i = 1, 32 do
    legacyTargets[i] = 910000 + i
    legacySignals[i] = 920000 + i
end
SuddenDoomGlowDB = {
    schemaVersion = 2,
    enabled = false,
    debug = false,
    cdm = false,
    targetSpellIDs = legacyTargets,
    signalSpellIDs = legacySignals,
}
local boundedAddon = {}
assert(loadfile(corePath))("SuddenDoomGlow", boundedAddon)
Advance(0)
assert(#SuddenDoomGlowDB.targetSpellIDs == 32,
    "legacy target defaults exceeded the configured ID bound")
assert(#SuddenDoomGlowDB.signalSpellIDs == 32,
    "legacy signal defaults exceeded the configured ID bound")

print("runtime regression 1.4.7: PASS")
