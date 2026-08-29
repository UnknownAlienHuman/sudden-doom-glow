local corePath = assert(arg[1], "Core.lua path required")

local now = 0
local inCombat = false
local timers = {}
local createdFrames = {}
local actionCallbacks = {}
local messages = {}
local unpackValues = table.unpack or unpack

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
    function frame:RegisterUnitEvent(event) self.events[event] = true end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:GetName() return self.name end
    function frame:GetObjectType() return "Button" end
    function frame:IsForbidden() return false end
    function frame:CanBeAccessedInContext() return true end
    function frame:GetSize() return self.width, self.height end
    function frame:SetSize(width, height) self.width, self.height = width, height end
    function frame:SetAllPoints(relative) self.allPoints = relative or true end
    function frame:ClearAllPoints() self.point = nil; self.allPoints = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:SetFrameLevel(level) self.frameLevel = level end
    function frame:GetFrameLevel() return self.frameLevel end
    function frame:SetFrameStrata(value) self.frameStrata = value end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:GetPagedID() return self.action end
    function frame:GetAction() return self.action end
    function frame:GetAttribute(key) return self.attributes[key] or (key == "action" and self.action or nil) end

    if template == "ActionButtonSpellAlertTemplate" then
        frame.shown = false
        frame.ProcStartAnim = NewAnimation()
        frame.ProcLoop = NewAnimation()
    end
    return frame
end

function CreateFrame(_, name, parent, template)
    local frame = NewFrame(name, parent, template)
    createdFrames[#createdFrames + 1] = frame
    return frame
end

function GetTime() return now end
function InCombatLockdown() return inCombat end
function UnitClass() return "Death Knight", "DEATHKNIGHT" end
function IsLoggedIn() return true end
function canaccessvalue() return true end
function issecretvalue() return false end
function ActionButton_GetPagedID(button) return button.action end

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

C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "1.3.1" end end }

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
}
function GetActionInfo(slot)
    local action = actions[slot]
    if not action then return nil end
    return action[1], action[2], action[3]
end
function GetMacroInfo() return nil end
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
    local action = actions[slot]
    return action and action[2] or nil
end

local overlayState = {}
C_SpellActivationOverlay = {}
function C_SpellActivationOverlay.IsSpellOverlayed(spellID)
    return overlayState[spellID] == true
end

EventRegistry = {}
function EventRegistry:RegisterCallback(event, callback, owner)
    actionCallbacks[event] = { callback = callback, owner = owner }
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

local cdmItem = NewFrame("CDMItem")
cdmItem.baseSpellID = 47541
function cdmItem:GetBaseSpellID() return self.baseSpellID end
function cdmItem:GetSpellID() return self.overrideSpellID or self.baseSpellID end

local activeCDM = { cdmItem }
local pool = {}
function pool:EnumerateActive()
    local index = 0
    return function()
        index = index + 1
        return activeCDM[index]
    end
end
EssentialCooldownViewer = NewFrame("EssentialCooldownViewer")
EssentialCooldownViewer.itemFramePool = pool

ActionButton1 = NewFrame("ActionButton1")
ActionButton1.action = 1
ActionButton2 = NewFrame("ActionButton2")
ActionButton2.action = 2
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

local SDG = assert(SuddenDoomGlow)
local R = assert(SDG.runtime)
local eventFrame = assert(createdFrames[1])
local onEvent = assert(eventFrame.scripts.OnEvent)

local function Fire(event, ...)
    onEvent(eventFrame, event, ...)
end

assert(SuddenDoomGlowDB.customPreserved == "yes", "DB migration destroyed unrelated settings")
assert(SuddenDoomGlowDB.schemaVersion == 3, "schema migration missing")
assert(SuddenDoomGlowDB.procSpellIDs == nil and SuddenDoomGlowDB.auraIDs == nil, "legacy fields retained")
assert(R.targetFamily[47541] and R.targetFamily[207317] and R.targetFamily[1242174], "spell family incomplete")
assert(R.trackedButtonSet[ActionButton1], "Death Coil button not tracked")
assert(R.trackedButtonSet[MultiBarBottomLeftButton1], "Epidemic button not tracked")
assert(R.cdmFrames[cdmItem], "Cooldown Viewer item not tracked")

-- Official query ON and idempotent rendering.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.glowActive, "overlay query did not enable glow")
local actionAlert = assert(R.frameState[ActionButton1].alert)
local initialPlays = actionAlert.ProcStartAnim.playCount
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(actionAlert.ProcStartAnim.playCount == initialPlays, "duplicate event restarted animation")
assert(R.frameState[cdmItem].shown, "CDM mirror did not glow")

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
local callback = assert(actionCallbacks["ActionButton.OnActionChanged"]).callback
callback(nil, ActionButton2)
assert(R.trackedButtonSet[ActionButton2], "override action button not tracked")

-- Current-slot validation prevents a stale glow after a page/action change.
overlayState[47541] = true
Fire("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", 47541)
assert(R.frameState[ActionButton1].shown, "precondition: original action button not glowing")
ActionButton1.action = 2
callback(nil, ActionButton1)
assert(not R.frameState[ActionButton1].shown, "stale action button retained glow")

-- Pool reassignment/reset removes the CDM frame without polling.
CooldownViewerItemDataMixin.ResetCooldownData(cdmItem)
assert(not R.cdmFrames[cdmItem], "released CDM frame remained tracked")
assert(not R.frameState[cdmItem].shown, "released CDM frame retained glow")

print("runtime smoke: PASS")
