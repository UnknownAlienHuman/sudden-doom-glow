local corePath = assert(arg[1], "Core.lua path required")

local now = 0
local inCombat = false
local isLoggedIn = true
local playerClassName = "DEATHKNIGHT"
local timers = {}
local createdFrames = {}
local actionCallbacks = {}
local messages = {}
local cdmEnumerations = 0
local cancelledNewTimers = 0
local createdNewTimers = 0
local unpackValues = table.unpack or unpack
local secretValue = { secret = true }
local actionGetSpellCalls = 0
local structuralViolations = 0
local inaccessibleAlertMutations = 0
local deepEnumerationStarts = 0
local deepEnumerationItems = {}

local function AlertOwner(value)
    if value.template == "ActionButtonSpellAlertTemplate" then return value end
    return value.alertOwner
end

local function AssertAlertAccessible(value, operation)
    local alert = AlertOwner(value)
    if alert and alert.accessible == false then
        inaccessibleAlertMutations = inaccessibleAlertMutations + 1
        error(operation .. " touched an inaccessible addon alert")
    end
end

local function AssertOutsideCombat(frame, operation)
    AssertAlertAccessible(frame, operation)
    if inCombat and frame.template == "ActionButtonSpellAlertTemplate" then
        structuralViolations = structuralViolations + 1
        error(operation .. " mutated an alert frame in combat")
    end
end

local function NewAnimation()
    local animation = {
        accessible = true,
        playing = false,
        playCount = 0,
        Play = function(self)
            AssertAlertAccessible(self, "Play")
            self.playing = true
            self.playCount = self.playCount + 1
        end,
        Stop = function(self)
            AssertAlertAccessible(self, "Stop")
            self.playing = false
        end,
        IsPlaying = function(self) return self.playing end,
        CanBeAccessedInContext = function(self)
            return self.accessible ~= false and (not self.alertOwner or self.alertOwner.accessible ~= false)
        end,
        SetScript = function(self, script, callback) self[script] = callback end,
    }
    return animation
end

local function NewFrame(name, parent, template)
    local frame = {
        name = name,
        parent = parent,
        template = template,
        shown = true,
        width = 40,
        height = 40,
        frameLevel = 1,
        scripts = {},
        hooks = {},
        events = {},
        attributes = {},
    }

    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback) self.hooks[script] = callback end
    function frame:GetName() return self.name end
    function frame:GetObjectType() return "Button" end
    function frame:IsForbidden() return false end
    function frame:GetSize() return self.width, self.height end
    function frame:SetSize(width, height) AssertOutsideCombat(self, "SetSize"); self.width, self.height = width, height end
    function frame:SetAllPoints(relative) AssertOutsideCombat(self, "SetAllPoints"); self.allPoints = relative or true end
    function frame:ClearAllPoints() AssertOutsideCombat(self, "ClearAllPoints"); self.point = nil; self.allPoints = nil end
    function frame:SetPoint(...) AssertOutsideCombat(self, "SetPoint"); self.point = { ... } end
    function frame:SetParent(newParent) AssertOutsideCombat(self, "SetParent"); self.parent = newParent end
    function frame:SetFrameLevel(level) AssertOutsideCombat(self, "SetFrameLevel"); self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameStrata(value) AssertOutsideCombat(self, "SetFrameStrata"); self.frameStrata = value end
    function frame:Show() AssertAlertAccessible(self, "Show"); self.shown = true end
    function frame:Hide() AssertAlertAccessible(self, "Hide"); self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:GetPagedID() return self.pagedAction or self.action end
    function frame:GetAction() return self.action end
    function frame:GetAttribute(key) return self.attributes[key] or (key == "action" and self.action or nil) end
    function frame:CanBeAccessedInContext()
        return self.accessible ~= false and self.contextAccessible ~= false
    end

    if template == "ActionButtonSpellAlertTemplate" then
        frame.shown = false
        frame.ProcStartAnim = NewAnimation()
        frame.ProcLoop = NewAnimation()
        frame.ProcStartAnim.alertOwner = frame
        frame.ProcLoop.alertOwner = frame
    end
    return frame
end

function CreateFrame(_, name, parent, template)
    if inCombat and template == "ActionButtonSpellAlertTemplate" then
        structuralViolations = structuralViolations + 1
        error("alert frame created in combat")
    end
    local frame = NewFrame(name, parent, template)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

function EnumerateFrames(previous)
    if previous == nil then
        deepEnumerationStarts = deepEnumerationStarts + 1
        return deepEnumerationItems[1]
    end
    for index, frame in ipairs(deepEnumerationItems) do
        if frame == previous then return deepEnumerationItems[index + 1] end
    end
    return nil
end

function GetTime() return now end
function InCombatLockdown() return inCombat end
function UnitClass()
    return playerClassName == "DEATHKNIGHT" and "Death Knight" or "Mage", playerClassName
end
function IsLoggedIn() return isLoggedIn end
function canaccessvalue(value) return value ~= secretValue end
function canaccesstable(value) return value.tableAccessible ~= false end
function issecretvalue(value) return value == secretValue end
function ActionButton_GetPagedID(button) return button.pagedAction or button.action end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}

local settingsRegistered = {}
local addonSettingRegistrationCalls = 0
local settingsCategory = { GetID = function() return 321 end }
Settings = { VarType = { Boolean = "boolean", Number = "number" } }
function Settings.RegisterVerticalLayoutCategory(name)
    assert(name == "Sudden Doom Glow")
    return settingsCategory
end
function Settings.RegisterAddOnSetting(category, variable, key, variableTable, valueType, label, defaultValue)
    addonSettingRegistrationCalls = addonSettingRegistrationCalls + 1
    if variableTable[key] == nil then variableTable[key] = defaultValue end
    local setting = { category = category, variable = variable, key = key, variableTable = variableTable,
        valueType = valueType, label = label, defaultValue = defaultValue }
    function setting:SetValueChangedCallback(callback) self.callback = callback end
    function setting:GetValue() return self.variableTable[self.key] end
    function setting:SetValue(value)
        assert(type(value) == self.valueType)
        self.variableTable[self.key] = value
        if self.callback then self.callback(self, value) end
    end
    settingsRegistered[variable] = setting
    return setting
end
function Settings.CreateCheckbox(category, setting, tooltip)
    assert(category == settingsCategory and setting and tooltip)
end
function Settings.CreateSliderOptions(minimum, maximum, step)
    assert(minimum == 1.0 and maximum == 1.8 and step == 0.1)
    return {}
end
function Settings.CreateSlider(category, setting, options, tooltip)
    assert(category == settingsCategory and setting and options and tooltip)
end
function Settings.RegisterAddOnCategory(category) assert(category == settingsCategory) end
function Settings.NotifyUpdate(variable)
    local setting = assert(settingsRegistered[variable])
    if setting.callback then setting.callback(setting, setting:GetValue()) end
end
function Settings.OpenToCategory(categoryID) assert(categoryID == 321) end

C_Timer = {}
function C_Timer.NewTimer(delay, callback)
    createdNewTimers = createdNewTimers + 1
    local timer = { at = now + delay, callback = callback, cancelled = false }
    function timer:Cancel()
        if not self.cancelled then cancelledNewTimers = cancelledNewTimers + 1 end
        self.cancelled = true
    end
    timers[#timers + 1] = timer
    return timer
end
function C_Timer.After(delay, callback)
    timers[#timers + 1] = { at = now + delay, callback = callback, cancelled = false }
end

local function Advance(seconds)
    local target = now + seconds
    while true do
        local selectedIndex
        local selectedAt
        for index, timer in ipairs(timers) do
            if not timer.cancelled and timer.at <= target and (not selectedAt or timer.at < selectedAt) then
                selectedIndex = index
                selectedAt = timer.at
            end
        end
        if not selectedIndex then break end
        local timer = table.remove(timers, selectedIndex)
        now = timer.at
        if not timer.cancelled then timer.callback() end
    end
    now = target
end

C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "1.4.6" end end }

local baseMap = { [1242174] = 47541 }
local overrideMap = { [47541] = 1242174 }
local spellNames = {
    [47541] = "Death Coil",
    [207317] = "Epidemic",
    [1242174] = "Necrotic Coil",
    [450932] = "Sudden Doom",
    [81340] = "Sudden Doom",
}

C_Spell = {}
function C_Spell.GetBaseSpell(spellID) return baseMap[spellID] or spellID end
function C_Spell.GetOverrideSpell(spellID) return overrideMap[spellID] or spellID end
function C_Spell.GetSpellName(spellID) return spellNames[spellID] or ("Spell " .. tostring(spellID)) end

local actions = {
    [1] = { "spell", 47541 },
    [2] = { "spell", 99999 },
    [13] = { "spell", 207317 },
    [4] = { "macro", 42 },
    [50] = { "spell", 99999 },
    [51] = { "spell", 99999 },
    [60] = { "spell", 47541 },
}
function GetActionInfo(slot)
    local action = actions[slot]
    if not action then return nil end
    return action[1], action[2], action[3]
end
local macroBodies = {
    [42] = "# /cast Death Coil\n# The comment is only documentation.",
}
function GetMacroInfo(macroID)
    return "Unrelated utility", "", macroBodies[macroID]
end
function GetMacroSpell() return nil end

C_ActionBar = {}
function C_ActionBar.GetSpell(slot)
    actionGetSpellCalls = actionGetSpellCalls + 1
    local action = actions[slot]
    return action and action[1] == "spell" and action[2] or nil
end

local overlayState = {}
C_SpellActivationOverlay = {}
function C_SpellActivationOverlay.IsSpellOverlayed(spellID)
    if overlayState[secretValue] then return secretValue end
    return overlayState[spellID] == true
end

EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback, owner)
    actionCallbacks[event] = { callback = callback, owner = owner }
end
function EventRegistry:UnregisterCallback(event, owner)
    local registration = actionCallbacks[event]
    if registration and registration.owner == owner then actionCallbacks[event] = nil end
end

function hooksecurefunc(target, methodName, hook)
    local original = assert(target[methodName], methodName)
    target[methodName] = function(...)
        local results = { original(...) }
        hook(...)
        return unpackValues(results)
    end
end

CooldownViewerMixin = { OnAcquireItemFrame = function() end }
CooldownViewerItemDataMixin = {
    SetCooldownID = function(self, id) self.cooldownID = id end,
    ClearCooldownID = function(self) self.cooldownID = nil; self.baseSpellID = nil; self.overrideSpellID = nil end,
    ResetCooldownData = function(self) self.cooldownID = nil; self.baseSpellID = nil; self.overrideSpellID = nil end,
    SetOverrideSpell = function(self, id) self.overrideSpellID = id end,
}

-- Blizzard copies mixin methods onto created instances. Capturing these before
-- addon loading prevents a mixin-only hook from appearing to observe live calls.
local copiedViewerAcquire = CooldownViewerMixin.OnAcquireItemFrame
local copiedSetCooldownID = CooldownViewerItemDataMixin.SetCooldownID
local copiedClearCooldownID = CooldownViewerItemDataMixin.ClearCooldownID
local copiedResetCooldownData = CooldownViewerItemDataMixin.ResetCooldownData
local copiedSetOverrideSpell = CooldownViewerItemDataMixin.SetOverrideSpell

local cdmItem = NewFrame("CDMItem")
cdmItem.baseSpellID = 47541
function cdmItem:GetBaseSpellID() return self.baseSpellID end
function cdmItem:GetSpellID() return self.overrideSpellID or self.baseSpellID end
cdmItem.SetCooldownID = copiedSetCooldownID
cdmItem.ClearCooldownID = copiedClearCooldownID
cdmItem.ResetCooldownData = copiedResetCooldownData
cdmItem.SetOverrideSpell = copiedSetOverrideSpell

local activeCDM = { cdmItem }
local pool = {}
function pool:EnumerateActive()
    cdmEnumerations = cdmEnumerations + 1
    local index = 0
    return function()
        index = index + 1
        return activeCDM[index]
    end
end
EssentialCooldownViewer = NewFrame("EssentialCooldownViewer")
EssentialCooldownViewer.OnAcquireItemFrame = copiedViewerAcquire
EssentialCooldownViewer.itemFramePool = pool

ActionButton1 = NewFrame("ActionButton1")
ActionButton1.action = 1
ActionButton2 = NewFrame("ActionButton2")
ActionButton2.action = 2
ActionButton3 = NewFrame("ActionButton3")
ActionButton3.action = 4
ActionButton4 = NewFrame("ActionButton4")
ActionButton4.action = 50
ActionButton5 = NewFrame("ActionButton5")
ActionButton5.action = 51
local deepOnlyButton = NewFrame("DeepOnlyButton")
deepOnlyButton.action = 60
deepEnumerationItems[1] = deepOnlyButton
MultiBarBottomLeftButton1 = NewFrame("MultiBarBottomLeftButton1")
MultiBarBottomLeftButton1.action = 13
MultiBarRightActionButton1 = NewFrame("MultiBarRightActionButton1")
MultiBarRightActionButton1.action = 1

SuddenDoomGlowDB = {
    enabled = true,
    debug = true,
    cdm = true,
    customPreserved = "yes",
    procSpellIDs = { 47541, 207317 },
    auraIDs = { 450932, 81340 },
}

local chunk = assert(loadfile(corePath))
local coreDirectory = corePath:match("^(.*[/\\])") or ""
local function LoadAddonFiles()
    local addon = {}
    chunk("SuddenDoomGlow", addon)
    for _, fileName in ipairs({ "Debug.lua", "Options.lua" }) do
        local extension = assert(loadfile(coreDirectory .. fileName))
        extension("SuddenDoomGlow", addon)
    end
    Advance(0) -- allow Core's deferred login to run after all TOC extensions load
    return addon
end

local addon = LoadAddonFiles()
local SDG = addon
local R = assert(SDG.runtime)
assert(SDG:RegisterSettings(), "Blizzard Settings category did not register")
local registeredSettingCount = 0
for _ in pairs(settingsRegistered) do registeredSettingCount = registeredSettingCount + 1 end
assert(registeredSettingCount == 4, "Settings did not register three checkboxes and the glow slider")
local scaleSetting = assert(settingsRegistered.SuddenDoomGlow_GlowScale)
assert(scaleSetting.valueType == Settings.VarType.Number and scaleSetting.variableTable == SuddenDoomGlowDB
    and scaleSetting.key == "glowScale", "glow size addon setting contract is incomplete")
local registeredScale = scaleSetting:GetValue()
scaleSetting:SetValue(1.6)
assert(scaleSetting:GetValue() == 1.6 and SuddenDoomGlowDB.glowScale == 1.6,
    "Settings slider did not write through to SavedVariables")
scaleSetting:SetValue(registeredScale)
assert(SDG:OpenSettings(), "Settings category could not be opened")
local enabledSetting = assert(settingsRegistered.SuddenDoomGlow_Enabled)
assert(enabledSetting.valueType == Settings.VarType.Boolean and enabledSetting.variableTable == SuddenDoomGlowDB
    and enabledSetting.key == "enabled", "enabled addon setting contract is incomplete")
local savedEnabled = SuddenDoomGlowDB.enabled
assert(SDG:SetOption("enabled", "false") == false and SuddenDoomGlowDB.enabled == savedEnabled,
    "wrong-type boolean setting changed SavedVariables")
local eventFrame = assert(createdFrames[1])
local activeEventFrame = eventFrame
local onEvent = assert(eventFrame.scripts.OnEvent)

local function Fire(event, ...)
    onEvent(eventFrame, event, ...)
end

assert(SuddenDoomGlowDB.customPreserved == "yes", "DB migration destroyed unrelated settings")
assert(SuddenDoomGlowDB.schemaVersion == 5, "schema migration missing")
assert(SuddenDoomGlowDB.procSpellIDs == nil and SuddenDoomGlowDB.auraIDs == nil, "legacy fields retained")
assert(R.targetFamily[47541] and R.targetFamily[207317] and R.targetFamily[1242174], "spell family incomplete")
assert(type(SDG.GetOption) == "function" and type(SDG.SetOption) == "function", "public settings option API missing")
local defaultGlowScale = SDG:GetOption("glowScale")
assert(type(defaultGlowScale) == "number", "glow scale setting missing")
SDG:SetOption("glowScale", 1.5)
assert(SDG:GetOption("glowScale") == 1.5, "glow scale option did not persist")
SDG:SetOption("glowScale", defaultGlowScale)
assert(R.frameState[ActionButton1] and R.frameState[ActionButton1].alert,
    "Death Coil alert was not prepared")
assert(R.frameState[MultiBarBottomLeftButton1] and R.frameState[MultiBarBottomLeftButton1].alert,
    "Epidemic alert was not prepared")
assert(R.knownButtons[MultiBarRightActionButton1]
    and R.frameState[MultiBarRightActionButton1]
    and R.frameState[MultiBarRightActionButton1].alert,
    "current Dominos compatibility-name button was not prepared")
assert(R.cdmFrames[cdmItem], "Cooldown Viewer item not tracked")
assert(actionGetSpellCalls > 0, "current action slots were not resolved through C_ActionBar.GetSpell")
local callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback
callback(nil, ActionButton3)
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(not (R.frameState[ActionButton3] and R.frameState[ActionButton3].shown),
    "macro comment mentioning a target spell was treated as an action")

-- Secret identifiers must be rejected before any numeric/type comparison.
ActionButton3.action = secretValue
local secretCallbackOK = pcall(actionCallbacks["ActionButton.OnActionChanged"].callback, nil, ActionButton3)
assert(secretCallbackOK, "secret action identifier raised during current-slot validation")
ActionButton3.action = 4

-- Official query ON and idempotent rendering.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "overlay query did not enable glow")
assert(R.frameState[MultiBarRightActionButton1].shown,
    "current Dominos compatibility-name button did not glow")
local actionAlert = assert(R.frameState[ActionButton1].alert)
local initialPlays = actionAlert.ProcStartAnim.playCount
local enumBeforeRepeatedEvents = cdmEnumerations
local cancellationsBeforeDuplicateShows = cancelledNewTimers
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(actionAlert.ProcStartAnim.playCount == initialPlays, "duplicate event restarted animation")
assert(R.frameState[cdmItem].shown, "CDM mirror did not glow")
assert(cdmEnumerations == enumBeforeRepeatedEvents, "repeated proc events enumerated Cooldown Viewer pools")
assert(cancelledNewTimers > cancellationsBeforeDuplicateShows,
    "duplicate SHOW did not cancel superseded owned timers")

-- Multiple simultaneous overlay IDs: hiding one must not hide the other.
overlayState[207317] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 207317)
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(R.glowActive, "one HIDE cleared another active signal")
overlayState[207317] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 207317)
assert(not R.glowActive, "authoritative all-false query did not clear glow")

-- Synchronous SHOW grace must expire quickly when the official query stays false.
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "SHOW grace did not protect synchronous event")
Advance(0.25)
assert(not R.glowActive, "false query left glow active after SHOW grace")

-- If a once-readable overlay query later becomes secret, retain its last known
-- ON state for a bounded window instead of immediately flickering it off.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "precondition: readable ON query did not enable glow")
overlayState[47541] = false
overlayState[secretValue] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(R.glowActive, "inaccessible query discarded recent readable ON state")
Advance(30.1)
assert(not R.glowActive, "unreadable query retained stale ON state beyond its bound")
overlayState[secretValue] = false

-- If query is unavailable, relevant events are a bounded fallback, not permanent state.
local queryFunction = C_SpellActivationOverlay.IsSpellOverlayed
C_SpellActivationOverlay.IsSpellOverlayed = nil
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "event fallback failed when query unavailable")
Advance(0.25)
assert(R.glowActive, "event fallback expired at grace instead of TTL")
Advance(30.0)
assert(not R.glowActive, "event fallback TTL did not clear stale glow")
C_SpellActivationOverlay.IsSpellOverlayed = queryFunction

-- An unreadable event payload still wakes the authoritative query; it does
-- not need to mutate the per-ID event signal to reconcile OFF.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
Advance(0.25)
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", secretValue)
Advance(0.10)
assert(not R.glowActive, "unreadable HIDE payload suppressed an authoritative OFF query")

-- A temporarily unreadable button must resume rendering when access returns.
-- A different button callback forces the old compaction path.
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
ActionButton1.accessible = false
callback(nil, MultiBarBottomLeftButton1)
ActionButton1.accessible = true
callback(nil, ActionButton1)
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton1] and R.frameState[ActionButton1].shown,
    "temporarily inaccessible button could not reenter glow rendering")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(not R.frameState[ActionButton1].shown, "OFF transition left the restored button glowing")
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton1].shown, "restored button did not glow after an OFF-to-ON cycle")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)

-- Explicit current-client override event adds a replacement and maps its button.
baseMap[777001] = 47541
spellNames[777001] = "Hotfixed Coil"
actions[3] = { "spell", 777001 }
ActionButton2.action = 3
Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 47541, 777001)
Advance(0.10)
assert(R.targetFamily[777001], "explicit override was not learned")
callback(nil, ActionButton2)
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton2] and R.frameState[ActionButton2].shown,
    "override action button did not render after reassignment")

-- Two native action changes arrive before their bar provider publishes the new
-- spells. The coalesced deferred refresh must recheck both known buttons.
callback(nil, ActionButton4)
callback(nil, ActionButton5)
Fire("ACTIONBAR_SLOT_CHANGED", 50)
Fire("ACTIONBAR_SLOT_CHANGED", 51)
actions[50] = { "spell", 47541 }
actions[51] = { "spell", 207317 }
Advance(0)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton4] and R.frameState[ActionButton4].shown,
    "burst refresh lost the late assignment for action slot A")
assert(R.frameState[ActionButton5] and R.frameState[ActionButton5].shown,
    "burst refresh lost the late assignment for action slot B")

-- Parent context access can fail while our own alert remains accessible. Proc OFF
-- and addon disable must still hide that alert child.
local primaryAlert = assert(R.frameState[ActionButton1].alert)
assert(primaryAlert.shown, "precondition: primary alert should be visible")
ActionButton1.contextAccessible = false
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(not primaryAlert.shown, "inaccessible external parent prevented hiding the addon alert")
ActionButton1.contextAccessible = true
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(primaryAlert.shown, "precondition: primary alert did not show before disable")
ActionButton1.contextAccessible = false
assert(SDG:SetOption("enabled", false), "could not disable addon for parent access test")
assert(not primaryAlert.shown, "disabling addon failed to hide alert under inaccessible parent context")
ActionButton1.contextAccessible = true
assert(SDG:SetOption("enabled", true), "could not re-enable addon after parent access test")
callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback

-- If the alert itself is inaccessible, show, hide, and geometry paths must skip
-- every native call, including calls whose errors Core would otherwise pcall.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(primaryAlert.shown, "precondition: primary alert did not show for inaccessible child test")
local inaccessibleMutationBaseline = inaccessibleAlertMutations
local savedGlowScale = SDG:GetOption("glowScale")
primaryAlert.accessible = false
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(primaryAlert.shown, "inaccessible visible alert was unexpectedly hidden")
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
primaryAlert.accessible = true
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(not primaryAlert.shown, "precondition: restored alert did not hide before inaccessible show test")
primaryAlert.accessible = false
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
SDG:SetOption("glowScale", math.min(1.8, savedGlowScale + 0.1))
assert(inaccessibleAlertMutations == inaccessibleMutationBaseline,
    "Core attempted native operations on an inaccessible addon alert")
assert(not primaryAlert.shown, "inaccessible alert was mutated while proc state changed")
primaryAlert.accessible = true
SDG:SetOption("glowScale", savedGlowScale)
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(primaryAlert.shown, "restored alert did not show on the next readable ON transition")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(not primaryAlert.shown, "restored alert could not hide on the next readable OFF transition")

-- A missed ON is recovered on a lifecycle wake even when global proc state
-- was already true and no new overlay edge arrives.
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
primaryAlert.accessible = false
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive and not primaryAlert.shown,
    "precondition: inaccessible alert did not miss its ON render")
primaryAlert.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(primaryAlert.shown, "regeneration did not recover a missed ON with global state already active")

-- An inaccessible alert must be hidden after OFF once access returns and a
-- lifecycle wake occurs. A later ON cancels that pending hide.
primaryAlert.accessible = false
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
assert(primaryAlert.shown, "inaccessible alert was mutated during OFF")
primaryAlert.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(not primaryAlert.shown, "pending OFF was not cleaned up after access returned")
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
primaryAlert.accessible = false
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
primaryAlert.accessible = true
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
Fire("PLAYER_REGEN_ENABLED")
assert(R.glowActive and primaryAlert.shown,
    "a valid ON did not cancel an earlier queued hide")
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)

-- Disable must retain enough cleanup ownership to hide an inaccessible alert
-- after access returns, even though ordinary runtime events have stopped.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
primaryAlert.accessible = false
overlayState[47541] = false
assert(SDG:SetOption("enabled", false), "could not disable with an inaccessible alert")
local timerCountBeforeDisabledRecovery = createdNewTimers
assert(activeEventFrame.events.PLAYER_REGEN_ENABLED
    and activeEventFrame.events.PLAYER_ENTERING_WORLD
    and activeEventFrame.events.SPELL_SECRECY_CHANGED,
    "disabled inaccessible alert did not register its recovery wake events")
assert(not activeEventFrame.events.SPELL_ACTIVATION_OVERLAY_GLOW_SHOW
    and not activeEventFrame.events.SPELL_ACTIVATION_OVERLAY_GLOW_HIDE,
    "disabled runtime retained proc events while waiting for cleanup")
primaryAlert.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(not primaryAlert.shown, "disabled addon abandoned cleanup of its inaccessible alert")
assert(createdNewTimers == timerCountBeforeDisabledRecovery,
    "disabled alert cleanup polled with a newly scheduled timer")
assert(not activeEventFrame.events.PLAYER_REGEN_ENABLED
    and not activeEventFrame.events.PLAYER_ENTERING_WORLD
    and not activeEventFrame.events.SPELL_SECRECY_CHANGED,
    "successful disabled cleanup left recovery events registered")
assert(SDG:SetOption("enabled", true), "could not re-enable after deferred cleanup")
callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback

-- Disabling CDM while its child is inaccessible also leaves a cleanup that
-- must run after access returns without a new proc transition.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
local cdmAlert = assert(R.frameState[cdmItem].alert)
assert(cdmAlert.shown, "precondition: CDM alert did not show")
cdmAlert.accessible = false
assert(SDG:SetOption("cdm", false), "could not disable CDM with an inaccessible alert")
cdmAlert.accessible = true
Fire("PLAYER_REGEN_ENABLED")
assert(not cdmAlert.shown, "CDM disable abandoned cleanup of its inaccessible alert")
assert(SDG:SetOption("cdm", true), "could not re-enable CDM after deferred cleanup")
callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback
overlayState[47541] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)

-- Current-slot validation prevents a stale glow after a page/action change.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton1].shown, "precondition: original action button not glowing")
ActionButton1.pagedAction = 2
ActionButton1.action = 1
ActionButton1.attributes.action = 1
callback(nil, ActionButton1)
assert(not R.frameState[ActionButton1].shown, "stale action button retained glow")
ActionButton1.pagedAction = nil

-- An inaccessible viewer makes the pass incomplete, so it cannot prune the
-- previously tracked item. A readable complete pass still retains active items.
EssentialCooldownViewer.accessible = false
SDG:RescanButtons(false)
assert(R.cdmFrames[cdmItem], "inaccessible viewer caused tracked CDM item pruning")
EssentialCooldownViewer.accessible = true
SDG:RescanButtons(false)
assert(R.cdmFrames[cdmItem], "readable viewer unexpectedly lost active CDM item")

-- Removing current target roots in combat hides existing action and CDM
-- alerts immediately while the unrelated signal continues to hold global ON.
overlayState[47541] = true
overlayState[450932] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 450932)
assert(R.glowActive and R.frameState[ActionButton1].shown and R.frameState[cdmItem].shown,
    "precondition: action and CDM targets were not glowing under signal ON")
local cdmEnumerationsBeforeCombatRemoval = cdmEnumerations
inCombat = true
SlashCmdList.SUDDEN_DOOM_GLOW("spell 47541")
SlashCmdList.SUDDEN_DOOM_GLOW("spell 1242174")
assert(R.glowActive, "removing target roots incorrectly cleared the unrelated active signal")
assert(not R.frameState[ActionButton1].shown and not R.frameState[cdmItem].shown,
    "combat target removal left obsolete action or CDM alerts visible")
assert(cdmEnumerations == cdmEnumerationsBeforeCombatRemoval,
    "combat target removal enumerated Cooldown Viewer pools")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
SlashCmdList.SUDDEN_DOOM_GLOW("spell 47541")
SlashCmdList.SUDDEN_DOOM_GLOW("spell 1242174")
Advance(0.10)
overlayState[450932] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 450932)
overlayState[47541] = false

-- Pool reassignment/reset removes the CDM frame without polling. Invoke the
-- instance method copied before Core loaded, as Retail does for mixin methods.
cdmItem:ResetCooldownData()
assert(not R.cdmFrames[cdmItem], "released CDM frame remained tracked")
assert(not R.frameState[cdmItem].shown, "released CDM frame retained glow")

-- Removing a configured query candidate invalidates its recent positive
-- result; retention must not keep an obsolete candidate lit.
overlayState[47541] = false
overlayState[207317] = false
overlayState[1242174] = false
overlayState[81340] = false
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 47541)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 207317)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 1242174)
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", 81340)
overlayState[450932] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 450932)
assert(R.glowActive, "precondition: configured signal query did not turn glow on")
overlayState[450932] = false
overlayState[secretValue] = true
SlashCmdList.SUDDEN_DOOM_GLOW("signal 450932")
Advance(0.10)
assert(not R.glowActive, "removed query candidate retained its previous positive result")
overlayState[secretValue] = false

-- User-configured spell lists are bounded before they can amplify hot-path queries.
local savedTargets = {}
for i = 1, #SuddenDoomGlowDB.targetSpellIDs do savedTargets[i] = SuddenDoomGlowDB.targetSpellIDs[i] end
SuddenDoomGlowDB.targetSpellIDs = {}
for i = 1, 32 do SuddenDoomGlowDB.targetSpellIDs[i] = 900000 + i end
local messagesBeforeLimit = #messages
SlashCmdList.SUDDEN_DOOM_GLOW("spell 999999")
assert(#SuddenDoomGlowDB.targetSpellIDs == 32, "configured target limit was exceeded")
assert(#messages == messagesBeforeLimit + 1 and messages[#messages]:find("Maximum 32", 1, true),
    "configured target limit did not report a bounded refusal")
SuddenDoomGlowDB.targetSpellIDs = savedTargets
Fire("SPELLS_CHANGED")
Advance(0.10)

-- Runtime option removal survives family rebuilds and addon reloads.
local customRoot = 990001
SlashCmdList.SUDDEN_DOOM_GLOW("spell " .. customRoot)
assert(R.targetFamily[customRoot], "custom target option did not take effect")
SlashCmdList.SUDDEN_DOOM_GLOW("spell " .. customRoot)
SlashCmdList.SUDDEN_DOOM_GLOW("spell 207317")
assert(not R.targetFamily[207317], "removed built-in target remained resolved")
Fire("SPELLS_CHANGED")
Advance(0.10)
assert(not R.targetFamily[customRoot], "removed target option returned during family rebuild")
assert(not R.targetFamily[207317], "removed built-in target returned during family rebuild")
local firstFrameAfterReload = #createdFrames + 1
addon = LoadAddonFiles()
activeEventFrame = createdFrames[firstFrameAfterReload]
SDG = addon
R = assert(SDG.runtime)
assert(not R.targetFamily[customRoot], "removed target option returned after addon reload")
assert(not R.targetFamily[207317], "removed built-in target returned after addon reload")

-- Disable and specialization changes invalidate pending event signals/timers.
local currentQuery = C_SpellActivationOverlay.IsSpellOverlayed
C_SpellActivationOverlay.IsSpellOverlayed = nil
local function FireCurrent(event, ...)
    activeEventFrame.scripts.OnEvent(activeEventFrame, event, ...)
end

-- A deep rescan requested just before combat is retained through its deferred
-- combat pass and runs exactly once after regeneration.
local deepStartsBeforeCombat = deepEnumerationStarts
SDG:RequestRescan("deep-before-combat", true)
inCombat = true
Advance(0.10)
assert(deepEnumerationStarts == deepStartsBeforeCombat,
    "deep frame enumeration ran during combat")
SDG:RequestRescan("ordinary-during-combat", false)
inCombat = false
FireCurrent("PLAYER_REGEN_ENABLED")
Advance(0.10)
assert(deepEnumerationStarts == deepStartsBeforeCombat + 1,
    "deferred deep rescan did not execute exactly once out of combat")
assert(R.frameState[deepOnlyButton] and R.frameState[deepOnlyButton].alert,
    "deferred deep rescan did not map its otherwise unknown button")

FireCurrent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "precondition: unavailable query did not use bounded event fallback")
assert(next(R.timers) ~= nil, "precondition: SHOW did not schedule owned timers")
local cancellationsBeforeDisable = cancelledNewTimers
SlashCmdList.SUDDEN_DOOM_GLOW("off")
assert(next(R.timers) == nil, "disabling left addon-owned timers registered")
assert(cancelledNewTimers > cancellationsBeforeDisable, "disabling did not cancel active owned timers")
SlashCmdList.SUDDEN_DOOM_GLOW("on")
assert(not R.glowActive, "pending event timer revived the glow after disable and re-enable")
FireCurrent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
FireCurrent("PLAYER_SPECIALIZATION_CHANGED", "player")
assert(not R.glowActive, "specialization reset retained stale unavailable-query signal")
C_SpellActivationOverlay.IsSpellOverlayed = currentQuery

-- Protected alert structure stays untouched in combat while rendering can
-- show/hide the already-created addon-owned overlay.
overlayState[47541] = true
inCombat = true
local combatOK, combatError = pcall(function()
    FireCurrent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
    FireCurrent("PLAYER_TALENT_UPDATE")
end)
assert(combatOK, "combat path structurally mutated an alert: " .. tostring(combatError))
assert(structuralViolations == 0, "combat structural violation was swallowed by an error boundary")
inCombat = false
FireCurrent("PLAYER_REGEN_ENABLED")

-- Late-loading Settings registration waits for combat to end.
local priorAddonSettingCalls = addonSettingRegistrationCalls
local framesBeforeLateOptions = #createdFrames
inCombat = true
assert(loadfile(coreDirectory .. "Options.lua"))("SuddenDoomGlow", addon)
assert(#createdFrames == framesBeforeLateOptions, "loading Options created an idle event owner")
assert(SDG:RegisterSettings() == false, "combat-time Settings registration was not deferred")
local lateOptionsFrame = createdFrames[#createdFrames]
assert(#createdFrames == framesBeforeLateOptions + 1, "deferred Settings owner was not created on demand")
assert(addonSettingRegistrationCalls == priorAddonSettingCalls, "Settings controls were created during combat")
inCombat = false
lateOptionsFrame.scripts.OnEvent(lateOptionsFrame, "PLAYER_REGEN_ENABLED")
assert(addonSettingRegistrationCalls == priorAddonSettingCalls + 4, "deferred Settings registration did not finish after combat")

-- A future SavedVariables schema is preserved and disables runtime controls.
SuddenDoomGlowDB.schemaVersion = 99
SuddenDoomGlowDB.futureSetting = "keep"
local frameBeforeFutureSchema = #createdFrames + 1
addon = LoadAddonFiles()
activeEventFrame = createdFrames[frameBeforeFutureSchema]
SDG = addon
R = assert(SDG.runtime)
assert(R.unsupportedSchema, "future SavedVariables schema was not recognized")
assert(SuddenDoomGlowDB.schemaVersion == 99 and SuddenDoomGlowDB.futureSetting == "keep",
    "future SavedVariables were overwritten")
assert(SDG:SetOption("enabled", false) == false, "future schema allowed setting mutation")
local futureSettingsSnapshot = {
    debug = SDG:GetOption("debug"),
    enabled = SDG:GetOption("enabled"),
    cdm = SDG:GetOption("cdm"),
}
local messagesBeforeFutureCommands = #messages
SlashCmdList.SUDDEN_DOOM_GLOW("debug")
SlashCmdList.SUDDEN_DOOM_GLOW("on")
SlashCmdList.SUDDEN_DOOM_GLOW("cdm off")
assert(SDG:GetOption("debug") == futureSettingsSnapshot.debug
    and SDG:GetOption("enabled") == futureSettingsSnapshot.enabled
    and SDG:GetOption("cdm") == futureSettingsSnapshot.cdm,
    "slash commands changed settings under a future schema")
assert(#messages >= messagesBeforeFutureCommands + 3,
    "slash commands did not report refusal under a future schema")
local futureCommandOutput = table.concat({
    messages[messagesBeforeFutureCommands + 1],
    messages[messagesBeforeFutureCommands + 2],
    messages[messagesBeforeFutureCommands + 3],
}, "\n")
assert(select(2, futureCommandOutput:gsub("newer version", "")) == 3,
    "future-schema slash commands did not report three explicit refusals")
assert(not futureCommandOutput:find("Debug:", 1, true)
    and not futureCommandOutput:find("Enabled", 1, true)
    and not futureCommandOutput:find("Cooldown Viewer mirror:", 1, true),
    "future-schema slash command reported a false successful update")

-- Other classes initialize without registering the Death Knight runtime.
SuddenDoomGlowDB.schemaVersion = 5
playerClassName = "MAGE"
local frameBeforeOtherClass = #createdFrames + 1
addon = LoadAddonFiles()
activeEventFrame = createdFrames[frameBeforeOtherClass]
SDG = addon
R = assert(SDG.runtime)
assert(R.class == "MAGE" and not R.runtimeRegistered,
    "non-Death Knight login registered the proc runtime")

print("runtime smoke: PASS")
