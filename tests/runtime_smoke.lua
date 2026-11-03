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
local unpackValues = table.unpack or unpack
local secretValue = { secret = true }
local actionGetSpellCalls = 0
local structuralViolations = 0

local function AssertOutsideCombat(frame, operation)
    if inCombat and frame.template == "ActionButtonSpellAlertTemplate" then
        structuralViolations = structuralViolations + 1
        error(operation .. " mutated an alert frame in combat")
    end
end

local function NewAnimation()
    return {
        playing = false,
        playCount = 0,
        Play = function(self) self.playing = true; self.playCount = self.playCount + 1 end,
        Stop = function(self) self.playing = false end,
        IsPlaying = function(self) return self.playing end,
        SetScript = function(self, script, callback) self[script] = callback end,
    }
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
        events = {},
        attributes = {},
    }

    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:IsEventRegistered(event) return self.events[event] == true end
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:GetName() return self.name end
    function frame:GetObjectType() return "Button" end
    function frame:IsForbidden() return false end
    function frame:CanBeAccessedInContext() return true end
    function frame:GetSize() return self.width, self.height end
    function frame:SetSize(width, height) AssertOutsideCombat(self, "SetSize"); self.width, self.height = width, height end
    function frame:SetAllPoints(relative) AssertOutsideCombat(self, "SetAllPoints"); self.allPoints = relative or true end
    function frame:ClearAllPoints() AssertOutsideCombat(self, "ClearAllPoints"); self.point = nil; self.allPoints = nil end
    function frame:SetPoint(...) AssertOutsideCombat(self, "SetPoint"); self.point = { ... } end
    function frame:SetFrameLevel(level) AssertOutsideCombat(self, "SetFrameLevel"); self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameStrata(value) AssertOutsideCombat(self, "SetFrameStrata"); self.frameStrata = value end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:GetPagedID() return self.pagedAction or self.action end
    function frame:GetAction() return self.action end
    function frame:GetAttribute(key) return self.attributes[key] or (key == "action" and self.action or nil) end
    function frame:CanBeAccessedInContext() return self.accessible ~= false end

    if template == "ActionButtonSpellAlertTemplate" then
        frame.shown = false
        frame.ProcStartAnim = NewAnimation()
        frame.ProcLoop = NewAnimation()
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

function GetTime() return now end
function InCombatLockdown() return inCombat end
function UnitClass()
    return playerClassName == "DEATHKNIGHT" and "Death Knight" or "Mage", playerClassName
end
function IsLoggedIn() return isLoggedIn end
function canaccessvalue(value) return value ~= secretValue end
function issecretvalue(value) return value == secretValue end
function ActionButton_GetPagedID(button) return button.pagedAction or button.action end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
SlashCmdList = {}

local settingsRegistered = {}
local proxyRegistrationCalls = 0
local settingsCategory = { GetID = function() return 321 end }
Settings = { VarType = { Boolean = "boolean", Number = "number" } }
function Settings.RegisterVerticalLayoutCategory(name)
    assert(name == "Sudden Doom Glow")
    return settingsCategory
end
function Settings.RegisterProxySetting(category, variable, valueType, label, defaultValue, getter, setter)
    proxyRegistrationCalls = proxyRegistrationCalls + 1
    local setting = { category = category, variable = variable, valueType = valueType,
        label = label, defaultValue = defaultValue, get = getter, set = setter }
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
function Settings.NotifyUpdate(variable) assert(settingsRegistered[variable]) end
function Settings.OpenToCategory(categoryID) assert(categoryID == 321) end

C_Timer = {}
function C_Timer.NewTimer(delay, callback)
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

C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "1.4.0" end end }

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
function C_ActionBar.FindSpellActionButtons(spellID)
    local slots = {}
    for slot, action in pairs(actions) do
        if action[1] == "spell" and C_Spell.GetBaseSpell(action[2]) == spellID then
            slots[#slots + 1] = slot
        end
    end
    table.sort(slots)
    return slots
end
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
MultiBarBottomLeftButton1 = NewFrame("MultiBarBottomLeftButton1")
MultiBarBottomLeftButton1.action = 13

SuddenDoomGlowDB = {
    enabled = true,
    debug = true,
    cdm = true,
    customPreserved = "yes",
    procSpellIDs = { 47541, 207317 },
    auraIDs = { 450932, 81340 },
}

local chunk = assert(loadfile(corePath))
chunk("SuddenDoomGlow")
local coreDirectory = corePath:match("^(.*[/\\])") or ""
for _, fileName in ipairs({ "Debug.lua", "Options.lua" }) do
    local extension = loadfile(coreDirectory .. fileName)
    if extension then extension("SuddenDoomGlow") end
end
Advance(0) -- allow Core's deferred login to run after all TOC extensions load

local SDG = assert(SuddenDoomGlow)
local R = assert(SDG.runtime)
assert(SDG:RegisterSettings(), "Blizzard Settings category did not register")
local registeredSettingCount = 0
for _ in pairs(settingsRegistered) do registeredSettingCount = registeredSettingCount + 1 end
assert(registeredSettingCount == 4, "Settings did not register three checkboxes and the glow slider")
local scaleSetting = assert(settingsRegistered.SuddenDoomGlow_GlowScale)
assert(scaleSetting.valueType == Settings.VarType.Number and type(scaleSetting.get) == "function" and
    type(scaleSetting.set) == "function", "glow size proxy setting contract is incomplete")
local registeredScale = scaleSetting.get()
scaleSetting.set(1.6)
assert(scaleSetting.get() == 1.6 and SuddenDoomGlowDB.glowScale == 1.6,
    "Settings slider did not write through to SavedVariables")
scaleSetting.set(registeredScale)
assert(SDG:OpenSettings(), "Settings category could not be opened")
local enabledSetting = assert(settingsRegistered.SuddenDoomGlow_Enabled)
assert(enabledSetting.valueType == Settings.VarType.Boolean and type(enabledSetting.get) == "function" and
    type(enabledSetting.set) == "function", "enabled checkbox proxy contract is incomplete")
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
assert(SuddenDoomGlowDB.schemaVersion == 4, "schema migration missing")
assert(SuddenDoomGlowDB.procSpellIDs == nil and SuddenDoomGlowDB.auraIDs == nil, "legacy fields retained")
assert(R.targetFamily[47541] and R.targetFamily[207317] and R.targetFamily[1242174], "spell family incomplete")
assert(type(SDG.GetOption) == "function" and type(SDG.SetOption) == "function", "public settings option API missing")
local defaultGlowScale = SDG:GetOption("glowScale")
assert(type(defaultGlowScale) == "number", "glow scale setting missing")
SDG:SetOption("glowScale", 1.5)
assert(SDG:GetOption("glowScale") == 1.5, "glow scale option did not persist")
SDG:SetOption("glowScale", defaultGlowScale)
assert(R.trackedButtonSet[ActionButton1], "Death Coil button not tracked")
assert(R.trackedButtonSet[MultiBarBottomLeftButton1], "Epidemic button not tracked")
assert(R.cdmFrames[cdmItem], "Cooldown Viewer item not tracked")
assert(actionGetSpellCalls > 0, "current action slots were not resolved through C_ActionBar.GetSpell")
R.trackedSlots[4] = true
local callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback
callback(nil, ActionButton3)
assert(not R.trackedButtonSet[ActionButton3], "macro comment mentioning a target spell was treated as an action")

-- Secret identifiers must be rejected before any numeric/type comparison.
ActionButton3.action = secretValue
local secretCallbackOK = pcall(actionCallbacks["ActionButton.OnActionChanged"].callback, nil, ActionButton3)
assert(secretCallbackOK, "secret action identifier raised during current-slot validation")
assert(not R.trackedButtonSet[ActionButton3], "inaccessible secret action was tracked")
ActionButton3.action = 4

-- Official query ON and idempotent rendering.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "overlay query did not enable glow")
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

-- Explicit current-client override event adds a replacement and maps its button.
baseMap[777001] = 47541
spellNames[777001] = "Hotfixed Coil"
actions[3] = { "spell", 777001 }
ActionButton2.action = 3
Fire("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", 47541, 777001)
Advance(0.10)
assert(R.targetFamily[777001], "explicit override was not learned")
callback(nil, ActionButton2)
assert(R.trackedButtonSet[ActionButton2], "override action button not tracked")

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

-- Pool reassignment/reset removes the CDM frame without polling. Invoke the
-- instance method copied before Core loaded, as Retail does for mixin methods.
cdmItem:ResetCooldownData()
assert(not R.cdmFrames[cdmItem], "released CDM frame remained tracked")
assert(not R.frameState[cdmItem].shown, "released CDM frame retained glow")

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
chunk("SuddenDoomGlow")
activeEventFrame = createdFrames[firstFrameAfterReload]
Advance(0)
SDG = assert(SuddenDoomGlow)
R = assert(SDG.runtime)
assert(not R.targetFamily[customRoot], "removed target option returned after addon reload")
assert(not R.targetFamily[207317], "removed built-in target returned after addon reload")

-- Disable and specialization changes invalidate pending event signals/timers.
local currentQuery = C_SpellActivationOverlay.IsSpellOverlayed
C_SpellActivationOverlay.IsSpellOverlayed = nil
local function FireCurrent(event, ...)
    activeEventFrame.scripts.OnEvent(activeEventFrame, event, ...)
end
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
local priorProxyCalls = proxyRegistrationCalls
inCombat = true
assert(loadfile(coreDirectory .. "Options.lua"))("SuddenDoomGlow")
local lateOptionsFrame = createdFrames[#createdFrames]
assert(SDG:RegisterSettings() == false, "combat-time Settings registration was not deferred")
assert(proxyRegistrationCalls == priorProxyCalls, "Settings controls were created during combat")
inCombat = false
lateOptionsFrame.scripts.OnEvent(lateOptionsFrame, "PLAYER_REGEN_ENABLED")
assert(proxyRegistrationCalls == priorProxyCalls + 4, "deferred Settings registration did not finish after combat")

-- A future SavedVariables schema is preserved and disables runtime controls.
SuddenDoomGlowDB.schemaVersion = 99
SuddenDoomGlowDB.futureSetting = "keep"
local frameBeforeFutureSchema = #createdFrames + 1
chunk("SuddenDoomGlow")
activeEventFrame = createdFrames[frameBeforeFutureSchema]
Advance(0)
SDG = assert(SuddenDoomGlow)
R = assert(SDG.runtime)
assert(R.unsupportedSchema, "future SavedVariables schema was not recognized")
assert(SuddenDoomGlowDB.schemaVersion == 99 and SuddenDoomGlowDB.futureSetting == "keep",
    "future SavedVariables were overwritten")
assert(SDG:SetOption("enabled", false) == false, "future schema allowed setting mutation")

-- Other classes initialize without registering the Death Knight runtime.
SuddenDoomGlowDB.schemaVersion = 4
playerClassName = "MAGE"
local frameBeforeOtherClass = #createdFrames + 1
chunk("SuddenDoomGlow")
activeEventFrame = createdFrames[frameBeforeOtherClass]
Advance(0)
SDG = assert(SuddenDoomGlow)
R = assert(SDG.runtime)
assert(R.class == "MAGE" and not R.runtimeRegistered,
    "non-Death Knight login registered the proc runtime")

print("runtime smoke: PASS")
