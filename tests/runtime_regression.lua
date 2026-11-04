local corePath = assert(arg[1], "Core.lua path required")
local coreDir = corePath:match("^(.*[/\\])") or ""

local now = 0
local inCombat = false
local timers = {}
local createdFrames = {}
local messages = {}
local actionCallbacks = {}
local queryCalls = 0
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

C_AddOns = { GetAddOnMetadata = function(_, field) return field == "Version" and "1.4.6" or nil end }
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
C_ActionBar = { GetSpell = function(slot) return actions[slot] end }
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

-- A relevant SHOW payload is the best first query candidate. This preserves
-- authoritative all-false reconciliation while avoiding a linear active scan.
overlayState[450932] = true
queryCalls = 0
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 450932)
assert(queryCalls == 1, "relevant SHOW payload was not queried first")
overlayState[450932] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 450932)
Advance(0.3)

overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
local preAccessState = assert(R.frameState[ActionButton1])
assert(preAccessState.shown, "precondition: action alert did not show")
assert(R.frameState[MultiBarRightActionButton1].shown,
    "current Dominos compatibility-name button did not receive the proc glow")
ActionButton1.accessible = false
actionCallbacks["ActionButton.OnActionChanged"].callback(nil, ActionButton1)
assert(not preAccessState.shown, "unreadable reassignment left a stale action glow")
ActionButton1.accessible = true
actionCallbacks["ActionButton.OnActionChanged"].callback(nil, ActionButton1)
assert(preAccessState.shown, "readable reassignment did not restore the current target glow")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)

-- Unrelated addon loads do not rescan; supported integration loads do.
local enumBefore = cdmEnumerations
Fire("ADDON_LOADED", "TotallyUnrelatedAddon")
Advance(0.2)
assert(cdmEnumerations == enumBefore, "unrelated ADDON_LOADED triggered a rescan")
Fire("ADDON_LOADED", "Bartender4")
Advance(0.2)
assert(cdmEnumerations > enumBefore, "relevant ADDON_LOADED did not trigger recovery")
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
Fire("ACTIONBAR_SLOT_CHANGED", 1)
assert(ActionButton1.slotReadCount > 0 and MultiBarRightActionButton1.slotReadCount > 0,
    "targeted slot refresh missed current slot owners")
assert(ActionButton2.slotReadCount == 0,
    "one-slot invalidation scanned an unrelated known button")
Advance(0)
assert(ActionButton2.slotReadCount == 0,
    "deferred one-slot recovery became an unrelated full scan")
Fire("ACTIONBAR_PAGE_CHANGED")
Advance(0)
assert(ActionButton2.slotReadCount > 0,
    "coalesced broad assignment recovery did not run")
assert(queryCalls == 0, "action events queried independent proc state")

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
local stableGeometryMutations = geometryMutations
SDG:RescanButtons(false)
assert(geometryMutations == stableGeometryMutations,
    "stable rescan repeated completed geometry mutations")

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

-- Foreign hook installation is an error boundary: failed hooks do not escape or
-- become false-positive registrations, and a later lifecycle pass retries them.
local savedUtilityViewer = UtilityCooldownViewer
local flakyViewer = NewViewer("FlakyUtilityViewer", {})
flakyViewer.hookFailures = { OnAcquireItemFrame = 1 }
UtilityCooldownViewer = flakyViewer
assert(pcall(SDG.RescanButtons, SDG, false), "viewer hook failure escaped recovery")
assert(not R.cdmViewerHooks[flakyViewer], "failed viewer hook was marked installed")
SDG:RescanButtons(false)
assert(R.cdmViewerHooks[flakyViewer], "viewer hook was not retried after failure")
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
assert(cdmEnumerations > enumAtCombat and R.cdmFrames[newItem] and R.cdmItemHooks[newItem],
    "post-combat CDM recovery did not attach the new item")
assert(not R.cdmItemHooks[newItem].SetCooldownID,
    "failed item hook was marked installed")
SDG:RescanButtons(false)
assert(R.cdmItemHooks[newItem].SetCooldownID,
    "item hook was not retried after failure")

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

print("runtime regression 1.4.6: PASS")
