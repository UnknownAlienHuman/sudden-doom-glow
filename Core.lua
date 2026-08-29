-- Sudden Doom Glow
-- Retail 12.1: official Spell Activation Overlay state -> addon-owned glow surfaces.

local ADDON_NAME = ... or "SuddenDoomGlow"

local SDG = _G.SuddenDoomGlow
if type(SDG) ~= "table" then
    SDG = {}
    _G.SuddenDoomGlow = SDG
end

local CreateFrame = _G.CreateFrame
local InCombatLockdown = _G.InCombatLockdown
local UnitClass = _G.UnitClass
local GetActionInfo = _G.GetActionInfo
local GetMacroInfo = _G.GetMacroInfo
local GetMacroSpell = _G.GetMacroSpell
local EnumerateFrames = _G.EnumerateFrames
local GetTime = _G.GetTime
local C_Timer = _G.C_Timer
local C_Spell = _G.C_Spell
local C_ActionBar = _G.C_ActionBar
local C_SpellActivationOverlay = _G.C_SpellActivationOverlay
local C_AddOns = _G.C_AddOns
local EventRegistry = _G.EventRegistry
local hooksecurefunc = _G.hooksecurefunc
local canaccessvalue = _G.canaccessvalue
local issecretvalue = _G.issecretvalue

local CURRENT_SCHEMA = 3
local MAX_ACTION_SLOTS = 540
local RESCAN_DELAY = 0.08
local OVERLAY_RECONCILE_DELAY = 0.06
local OVERLAY_SHOW_GRACE = 0.20
local EVENT_FALLBACK_TTL = 30.0
local CDM_ADDON = "Blizzard_CooldownViewer"

local DEFAULT_TARGET_SPELL_IDS = {
    47541,   -- Death Coil
    207317,  -- Epidemic
    1242174, -- Necrotic Coil
}

local DEFAULT_SIGNAL_SPELL_IDS = {
    47541,   -- Death Coil
    207317,  -- Epidemic
    1242174, -- Necrotic Coil
    450932,  -- current Sudden Doom aura / overlay family member
    81340,   -- legacy Sudden Doom aura / overlay family member
}

local function NewWeakKeyTable()
    return setmetatable({}, { __mode = "k" })
end

local R = {
    class = nil,
    didLogin = false,
    runtimeRegistered = false,

    targetRoots = {},
    targetRootList = {},
    targetFamily = {},
    targetFamilyList = {},
    signalFamily = {},
    signalFamilyList = {},
    procNames = {},
    procTokens = {},
    explicitOverrides = {},

    trackedSlots = {},
    trackedButtons = {},
    trackedButtonSet = NewWeakKeyTable(),
    frameState = NewWeakKeyTable(),

    cdmFrames = NewWeakKeyTable(),
    cdmViewers = NewWeakKeyTable(),
    cdmHooksAttached = false,

    eventSignals = {},
    eventSignalTimers = {},
    lastOverlayShowAt = 0,
    overlayQueryReadable = 0,
    overlayQueryCandidates = 0,
    overlayQueryAuthoritative = false,

    glowActive = false,
    lastDetection = "none",
    testUntil = 0,
    testToken = 0,

    needsRescan = false,
    pendingDeep = false,
    rescanTimer = nil,
    rescanReason = nil,
    queuedDeep = false,

    reconcileTimer = nil,
    actionCallbackAttached = false,
    actionCallbackOwner = {},
}
SDG.runtime = R

local DB

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Now()
    return GetTime and GetTime() or 0
end

local function Print(message)
    if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSuddenDoomGlow|r: " .. tostring(message))
    end
end

function SDG:Print(message)
    Print(message)
end

local function Log(message)
    if not DB or not DB.debug then return end
    if type(SDG.LogDebug) == "function" then
        SDG:LogDebug(tostring(message))
    else
        Print(message)
    end
end

local function ClearArray(t)
    for i = #t, 1, -1 do
        t[i] = nil
    end
end

local function ClearMap(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function IsAccessible(value)
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok then return accessible and true or false end
    end

    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        if ok then return not secret end
    end

    return true
end

local function SafeNumber(value)
    if value == nil or not IsAccessible(value) then return nil end
    if type(value) == "number" then return value end
    if type(value) == "string" then
        local ok, number = pcall(tonumber, value)
        if ok then return number end
    end
    return nil
end

local function SafeString(value)
    if type(value) == "string" and IsAccessible(value) then
        return value
    end
    return nil
end

local function SafeMethod(object, methodName, ...)
    if not object then return false end
    local method = object[methodName]
    if type(method) ~= "function" then return false end
    return pcall(method, object, ...)
end

local function FrameCanBeUsed(frame)
    if not frame then return false end

    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or forbidden then return false end
    end

    if type(frame.CanBeAccessedInContext) == "function" then
        local ok, accessible = pcall(frame.CanBeAccessedInContext, frame)
        if not ok or not accessible then return false end
    end

    return true
end

local function GetAddonVersion()
    local version
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, value = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
        if ok then version = SafeString(value) end
    end
    if not version and type(_G.GetAddOnMetadata) == "function" then
        local ok, value = pcall(_G.GetAddOnMetadata, ADDON_NAME, "Version")
        if ok then version = SafeString(value) end
    end
    return version or "0"
end

local function CopyNumericList(source)
    local result = {}
    local seen = {}
    if type(source) ~= "table" then return result end

    for i = 1, #source do
        local id = SafeNumber(source[i])
        if id and id > 0 and not seen[id] then
            seen[id] = true
            result[#result + 1] = id
        end
    end
    return result
end

local function MergeNumericDefaults(destination, defaults)
    local result = CopyNumericList(destination)
    local seen = {}
    for i = 1, #result do seen[result[i]] = true end
    for i = 1, #defaults do
        local id = defaults[i]
        if not seen[id] then
            seen[id] = true
            result[#result + 1] = id
        end
    end
    return result
end

local function InitializeDB()
    if type(_G.SuddenDoomGlowDB) ~= "table" then
        _G.SuddenDoomGlowDB = {}
    end
    DB = _G.SuddenDoomGlowDB

    -- Preserve user settings. Older versions wiped the entire DB on every release;
    -- migration is now field-based and schema-versioned.
    if type(DB.targetSpellIDs) ~= "table" and type(DB.procSpellIDs) == "table" then
        DB.targetSpellIDs = CopyNumericList(DB.procSpellIDs)
    end
    if type(DB.signalSpellIDs) ~= "table" and type(DB.auraIDs) == "table" then
        DB.signalSpellIDs = CopyNumericList(DB.auraIDs)
    end

    if DB.enabled == nil then DB.enabled = true end
    if DB.debug == nil then DB.debug = false end
    if DB.cdm == nil then DB.cdm = true end

    DB.targetSpellIDs = MergeNumericDefaults(DB.targetSpellIDs, DEFAULT_TARGET_SPELL_IDS)
    DB.signalSpellIDs = MergeNumericDefaults(DB.signalSpellIDs, DEFAULT_SIGNAL_SPELL_IDS)

    DB.schemaVersion = CURRENT_SCHEMA
    DB.addonVersion = GetAddonVersion()

    -- Retained only so downgrading does not corrupt an older client. They are not
    -- live detection controls in the 12.1 architecture.
    DB.procSpellIDs = nil
    DB.auraIDs = nil
    DB.auraEnabled = nil
    DB.overlayEnabled = nil
    DB.costEnabled = nil
    DB.slots = nil
end

local function SpellName(spellID)
    if C_Spell and type(C_Spell.GetSpellName) == "function" then
        local ok, name = pcall(C_Spell.GetSpellName, spellID)
        if ok then return SafeString(name) end
    end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and type(info) == "table" and IsAccessible(info) then
            return SafeString(info.name)
        end
    end
    if type(_G.GetSpellInfo) == "function" then
        local ok, name = pcall(_G.GetSpellInfo, spellID)
        if ok then return SafeString(name) end
    end
    return nil
end

local function GetBaseSpellID(spellID)
    spellID = SafeNumber(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.GetBaseSpell) == "function" then
        local ok, baseID = pcall(C_Spell.GetBaseSpell, spellID)
        if ok then
            baseID = SafeNumber(baseID)
            if baseID and baseID > 0 then return baseID end
        end
    end
    return spellID
end

local function GetOverrideSpellID(spellID)
    spellID = SafeNumber(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok then
            overrideID = SafeNumber(overrideID)
            if overrideID and overrideID > 0 then return overrideID end
        end
    end
    return spellID
end

local function AddUniqueID(set, list, value)
    local id = SafeNumber(value)
    if not id or id < 1 or set[id] then return false end
    set[id] = true
    list[#list + 1] = id
    return true
end

local function AddTargetFamilyChain(spellID, depth)
    depth = depth or 0
    if depth > 8 then return end

    spellID = SafeNumber(spellID)
    if not spellID or spellID < 1 then return end

    local added = AddUniqueID(R.targetFamily, R.targetFamilyList, spellID)
    local baseID = GetBaseSpellID(spellID)
    if baseID and baseID ~= spellID then
        AddUniqueID(R.targetFamily, R.targetFamilyList, baseID)
    end

    local overrideID = GetOverrideSpellID(spellID)
    if overrideID and overrideID ~= spellID then
        if AddUniqueID(R.targetFamily, R.targetFamilyList, overrideID) then
            AddTargetFamilyChain(overrideID, depth + 1)
        end
    elseif added and baseID and baseID ~= spellID then
        local baseOverrideID = GetOverrideSpellID(baseID)
        if baseOverrideID and baseOverrideID ~= baseID then
            AddTargetFamilyChain(baseOverrideID, depth + 1)
        end
    end
end

local function RebuildSpellFamilies()
    ClearMap(R.targetRoots)
    ClearArray(R.targetRootList)
    ClearMap(R.targetFamily)
    ClearArray(R.targetFamilyList)
    ClearMap(R.signalFamily)
    ClearArray(R.signalFamilyList)
    ClearMap(R.procNames)
    ClearArray(R.procTokens)

    DB.targetSpellIDs = MergeNumericDefaults(DB.targetSpellIDs, DEFAULT_TARGET_SPELL_IDS)
    DB.signalSpellIDs = MergeNumericDefaults(DB.signalSpellIDs, DEFAULT_SIGNAL_SPELL_IDS)

    for i = 1, #DB.targetSpellIDs do
        local configuredID = SafeNumber(DB.targetSpellIDs[i])
        if configuredID then
            local baseID = GetBaseSpellID(configuredID) or configuredID
            AddUniqueID(R.targetRoots, R.targetRootList, baseID)
            AddTargetFamilyChain(configuredID, 0)
            AddTargetFamilyChain(baseID, 0)
        end
    end

    for baseID, overrideID in pairs(R.explicitOverrides) do
        if R.targetRoots[baseID] or R.targetFamily[baseID] then
            AddTargetFamilyChain(overrideID, 0)
        end
    end

    for i = 1, #R.targetFamilyList do
        AddUniqueID(R.signalFamily, R.signalFamilyList, R.targetFamilyList[i])
    end
    for i = 1, #DB.signalSpellIDs do
        AddUniqueID(R.signalFamily, R.signalFamilyList, DB.signalSpellIDs[i])
    end

    for i = 1, #R.targetFamilyList do
        local spellID = R.targetFamilyList[i]
        R.procTokens[#R.procTokens + 1] = tostring(spellID)
        local name = SpellName(spellID)
        if name then
            local lower = name:lower()
            R.procNames[lower] = true
            R.procTokens[#R.procTokens + 1] = lower
        end
    end
end

local function IsTargetFamilySpell(spellID, learn)
    spellID = SafeNumber(spellID)
    if not spellID then return false end
    if R.targetFamily[spellID] then return true end

    local baseID = GetBaseSpellID(spellID)
    if baseID and (R.targetRoots[baseID] or R.targetFamily[baseID]) then
        if learn then
            AddTargetFamilyChain(spellID, 0)
            AddUniqueID(R.signalFamily, R.signalFamilyList, spellID)
        end
        return true
    end

    for i = 1, #R.targetRootList do
        local rootID = R.targetRootList[i]
        local overrideID = GetOverrideSpellID(rootID)
        if overrideID == spellID then
            if learn then
                R.explicitOverrides[rootID] = spellID
                AddTargetFamilyChain(spellID, 0)
                AddUniqueID(R.signalFamily, R.signalFamilyList, spellID)
            end
            return true
        end
    end

    return false
end

local function LearnExplicitOverride(baseSpellID, overrideSpellID, source)
    baseSpellID = SafeNumber(baseSpellID)
    overrideSpellID = SafeNumber(overrideSpellID)
    if not baseSpellID then return false end

    local normalizedBase = GetBaseSpellID(baseSpellID) or baseSpellID
    if not (R.targetRoots[normalizedBase] or R.targetFamily[normalizedBase] or R.targetFamily[baseSpellID]) then
        return false
    end

    if not overrideSpellID then
        if R.explicitOverrides[normalizedBase] then
            R.explicitOverrides[normalizedBase] = nil
            RebuildSpellFamilies()
            Log("Override removed for " .. tostring(normalizedBase) .. " (" .. tostring(source) .. ")")
            return true
        end
        return false
    end

    if R.explicitOverrides[normalizedBase] == overrideSpellID and R.targetFamily[overrideSpellID] then
        return false
    end

    R.explicitOverrides[normalizedBase] = overrideSpellID
    RebuildSpellFamilies()
    Log(("Override %d -> %d (%s)"):format(normalizedBase, overrideSpellID, tostring(source)))
    return true
end

local function IsRelevantSignal(spellID)
    spellID = SafeNumber(spellID)
    if not spellID then return false end
    if R.signalFamily[spellID] then return true end
    if IsTargetFamilySpell(spellID, true) then
        AddUniqueID(R.signalFamily, R.signalFamilyList, spellID)
        return true
    end
    return false
end

local function MacroMatchesTarget(macroID)
    macroID = SafeNumber(macroID)
    if not macroID then return false end

    if type(GetMacroSpell) == "function" then
        local ok, spell = pcall(GetMacroSpell, macroID)
        if ok then
            local spellID = SafeNumber(spell)
            if spellID and IsTargetFamilySpell(spellID, true) then return true end
            local spellName = SafeString(spell)
            if spellName and R.procNames[spellName:lower()] then return true end
        end
    end

    if type(GetMacroInfo) ~= "function" then return false end
    local ok, _, _, body = pcall(GetMacroInfo, macroID)
    if not ok or type(body) ~= "string" or not IsAccessible(body) then return false end

    local lower = body:lower()
    for i = 1, #R.procTokens do
        if lower:find(R.procTokens[i], 1, true) then return true end
    end
    return false
end

local function GetActionSpellID(slot)
    slot = SafeNumber(slot)
    if not slot or type(GetActionInfo) ~= "function" then return nil, nil end

    local ok, actionType, id, subType = pcall(GetActionInfo, slot)
    if not ok then return nil, nil end
    actionType = SafeString(actionType)
    subType = SafeString(subType)

    if actionType == "spell" then
        return SafeNumber(id), actionType
    end

    if actionType == "macro" then
        local macroID = SafeNumber(id)
        if macroID and type(GetMacroSpell) == "function" then
            local spellOK, macroSpell = pcall(GetMacroSpell, macroID)
            if spellOK then
                local macroSpellID = SafeNumber(macroSpell)
                if macroSpellID then return macroSpellID, actionType end
            end
        end
        return nil, actionType, macroID, subType
    end

    if C_ActionBar and type(C_ActionBar.GetSpell) == "function" then
        local spellOK, spellID = pcall(C_ActionBar.GetSpell, slot)
        if spellOK then
            spellID = SafeNumber(spellID)
            if spellID then return spellID, actionType end
        end
    end

    return nil, actionType
end

local function SlotMatchesTarget(slot)
    local spellID, actionType, macroID = GetActionSpellID(slot)
    if spellID and IsTargetFamilySpell(spellID, true) then return true end
    if actionType == "macro" and macroID and MacroMatchesTarget(macroID) then return true end
    return false
end

local function TrackSlot(slot)
    slot = SafeNumber(slot)
    if not slot or slot < 1 or slot > MAX_ACTION_SLOTS then return false end
    if R.trackedSlots[slot] then return false end
    R.trackedSlots[slot] = true
    return true
end

local function AddSlotsFromFindSpell(spellID)
    if not (C_ActionBar and type(C_ActionBar.FindSpellActionButtons) == "function") then return end
    local baseID = GetBaseSpellID(spellID) or spellID
    local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, baseID)
    if not ok or type(slots) ~= "table" or not IsAccessible(slots) then return end

    pcall(function()
        for i = 1, #slots do TrackSlot(slots[i]) end
    end)
end

local function ScanActionSlots()
    ClearMap(R.trackedSlots)
    RebuildSpellFamilies()

    for i = 1, #R.targetRootList do AddSlotsFromFindSpell(R.targetRootList[i]) end
    for i = 1, #R.targetFamilyList do AddSlotsFromFindSpell(R.targetFamilyList[i]) end

    for slot = 1, MAX_ACTION_SLOTS do
        if SlotMatchesTarget(slot) then TrackSlot(slot) end
    end
end

local function GetButtonSlot(button)
    if not button or not FrameCanBeUsed(button) then return nil end
    local candidates = {}
    local seen = {}

    local function Add(value)
        local slot = SafeNumber(value)
        if slot and slot >= 1 and slot <= MAX_ACTION_SLOTS and not seen[slot] then
            seen[slot] = true
            candidates[#candidates + 1] = slot
        end
    end

    if type(button.GetPagedID) == "function" then
        local ok, value = pcall(button.GetPagedID, button)
        if ok then Add(value) end
    end
    if type(button.GetAction) == "function" then
        local ok, value = pcall(button.GetAction, button)
        if ok then Add(value) end
    end

    Add(button.action)
    Add(button._state_action)

    if type(button.GetAttribute) == "function" then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok then Add(value) end
    end

    if type(_G.ActionButton_GetPagedID) == "function" then
        local ok, value = pcall(_G.ActionButton_GetPagedID, button)
        if ok then Add(value) end
    end

    for i = 1, #candidates do
        local slot = candidates[i]
        if R.trackedSlots[slot] and SlotMatchesTarget(slot) then return slot end
    end

    for i = 1, #candidates do
        if SlotMatchesTarget(candidates[i]) then return candidates[i] end
    end

    return candidates[1]
end

local function IsCurrentTargetButton(button)
    local slot = GetButtonSlot(button)
    return slot and R.trackedSlots[slot] and SlotMatchesTarget(slot), slot
end

local function GetRenderTarget(frame)
    if not frame then return nil end
    local iconFrame = frame.Icon
    if iconFrame and type(iconFrame.GetObjectType) == "function" then
        local ok, objectType = pcall(iconFrame.GetObjectType, iconFrame)
        if ok and objectType == "Frame" and FrameCanBeUsed(iconFrame) then
            return iconFrame
        end
    end
    return frame
end

local function GetFrameState(frame)
    local state = R.frameState[frame]
    if not state then
        state = { alert = nil, shown = false, renderTarget = nil, isCDM = false }
        R.frameState[frame] = state
    end
    return state
end

local function RefreshAlertGeometry(frame, state)
    if InCombat() then return end
    local target = GetRenderTarget(frame)
    if not target or not FrameCanBeUsed(target) or not state.alert then return end

    local width, height = 0, 0
    if type(target.GetSize) == "function" then
        local ok, w, h = pcall(target.GetSize, target)
        if ok then
            width = SafeNumber(w) or 0
            height = SafeNumber(h) or 0
        end
    end

    pcall(state.alert.ClearAllPoints, state.alert)
    if width > 0 and height > 0 then
        pcall(state.alert.SetSize, state.alert, width * 1.4, height * 1.4)
        pcall(state.alert.SetPoint, state.alert, "CENTER", target, "CENTER", 0, 0)
    else
        pcall(state.alert.SetAllPoints, state.alert, target)
    end

    if type(target.GetFrameLevel) == "function" and type(state.alert.SetFrameLevel) == "function" then
        local ok, level = pcall(target.GetFrameLevel, target)
        level = ok and SafeNumber(level) or nil
        if level then pcall(state.alert.SetFrameLevel, state.alert, level + 20) end
    end

    state.renderTarget = target
end

local function EnsureAlert(frame)
    if not frame or not FrameCanBeUsed(frame) then return nil end
    local state = GetFrameState(frame)
    if state.alert then
        RefreshAlertGeometry(frame, state)
        return state.alert
    end
    if InCombat() or type(CreateFrame) ~= "function" then return nil end

    local target = GetRenderTarget(frame)
    if not target or not FrameCanBeUsed(target) then return nil end
    local ok, alert = pcall(CreateFrame, "Frame", nil, target, "ActionButtonSpellAlertTemplate")
    if not ok or not alert then
        Log("ActionButtonSpellAlertTemplate unavailable for a render target")
        return nil
    end

    state.alert = alert
    state.renderTarget = target
    state.shown = false
    pcall(alert.Hide, alert)
    RefreshAlertGeometry(frame, state)
    return alert
end

local function StopAnimation(animation)
    if animation and type(animation.Stop) == "function" then pcall(animation.Stop, animation) end
end

local function PlayAnimation(animation)
    if animation and type(animation.Play) == "function" then
        local ok = pcall(animation.Play, animation)
        return ok
    end
    return false
end

local function ShowFrameGlow(frame)
    if not frame or not FrameCanBeUsed(frame) then return end
    local state = GetFrameState(frame)
    if not state.isCDM then
        local current = IsCurrentTargetButton(frame)
        if not current then
            if state.shown and state.alert then
                StopAnimation(state.alert.ProcStartAnim)
                StopAnimation(state.alert.ProcLoop)
                pcall(state.alert.Hide, state.alert)
                state.shown = false
            end
            return
        end
    end

    local alert = EnsureAlert(frame)
    if not alert or state.shown then return end

    StopAnimation(alert.ProcLoop)
    pcall(alert.Show, alert)
    alert.animationPlaying = true
    if not PlayAnimation(alert.ProcStartAnim) then
        PlayAnimation(alert.ProcLoop)
    end
    state.shown = true
end

local function HideFrameGlow(frame)
    if not frame then return end
    local state = R.frameState[frame]
    if not state or not state.alert then return end
    if not state.shown then
        pcall(state.alert.Hide, state.alert)
        return
    end

    state.alert.animationPlaying = false
    StopAnimation(state.alert.ProcStartAnim)
    StopAnimation(state.alert.ProcLoop)
    pcall(state.alert.Hide, state.alert)
    state.shown = false
end

local function CompactTrackedButtons()
    local compact = {}
    local set = NewWeakKeyTable()
    for i = 1, #R.trackedButtons do
        local button = R.trackedButtons[i]
        if button and R.trackedButtonSet[button] and FrameCanBeUsed(button) then
            compact[#compact + 1] = button
            set[button] = true
        end
    end
    R.trackedButtons = compact
    R.trackedButtonSet = set
end

local function AddTrackedButton(button)
    if not button or R.trackedButtonSet[button] or not FrameCanBeUsed(button) then return end
    R.trackedButtonSet[button] = true
    R.trackedButtons[#R.trackedButtons + 1] = button
end

local function RemoveTrackedButton(button)
    if not button or not R.trackedButtonSet[button] then return end
    HideFrameGlow(button)
    R.trackedButtonSet[button] = nil
end

local NAMED_BUTTON_SETS = {
    { "ActionButton", 12 },
    { "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 },
    { "MultiBarLeftButton", 12 },
    { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 },
    { "MultiBar7Button", 12 },
    { "MultiBar8Button", 12 },
    { "MultiBar9Button", 12 },
    { "MultiBar10Button", 12 },
    { "BT4Button", 180 },
    { "DominosActionButton", 180 },
}

local function MapNamedButtons()
    for setIndex = 1, #NAMED_BUTTON_SETS do
        local prefix = NAMED_BUTTON_SETS[setIndex][1]
        local count = NAMED_BUTTON_SETS[setIndex][2]
        for index = 1, count do
            local button = _G[prefix .. index]
            if button then
                local matches = IsCurrentTargetButton(button)
                if matches then AddTrackedButton(button) end
            end
        end
    end

    for bar = 1, 15 do
        for index = 1, 12 do
            local button = _G["ElvUI_Bar" .. bar .. "Button" .. index]
            if button then
                local matches = IsCurrentTargetButton(button)
                if matches then AddTrackedButton(button) end
            end
        end
    end
end

local function DeepMapButtons(maxFrames)
    if type(EnumerateFrames) ~= "function" then return end
    local count = 0
    local frame = EnumerateFrames()
    while frame do
        count = count + 1
        if count > maxFrames then break end
        if FrameCanBeUsed(frame) and type(frame.GetObjectType) == "function" then
            local ok, objectType = pcall(frame.GetObjectType, frame)
            if ok and (objectType == "Button" or objectType == "CheckButton") then
                local matches = IsCurrentTargetButton(frame)
                if matches then AddTrackedButton(frame) end
            end
        end
        frame = EnumerateFrames(frame)
    end
end

local function GetCDMFrameSpellIDs(frame)
    local ids = {}
    local seen = {}
    local function Add(value)
        local id = SafeNumber(value)
        if id and id > 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end

    if type(frame.GetBaseSpellID) == "function" then
        local ok, value = pcall(frame.GetBaseSpellID, frame)
        if ok then Add(value) end
    end
    if type(frame.GetSpellID) == "function" then
        local ok, value = pcall(frame.GetSpellID, frame)
        if ok then Add(value) end
    end
    return ids
end

local function CDMFrameMatches(frame)
    if not frame or not FrameCanBeUsed(frame) then return false end
    local ids = GetCDMFrameSpellIDs(frame)
    for i = 1, #ids do
        if IsTargetFamilySpell(ids[i], true) then return true end
    end
    return false
end

local function RefreshCDMFrame(frame)
    if not frame then return end
    local state = GetFrameState(frame)
    if DB.cdm and CDMFrameMatches(frame) then
        state.isCDM = true
        R.cdmFrames[frame] = true
        EnsureAlert(frame)
        if R.glowActive then ShowFrameGlow(frame) else HideFrameGlow(frame) end
    else
        HideFrameGlow(frame)
        state.isCDM = false
        R.cdmFrames[frame] = nil
    end
end

local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local function EnumerateCDMViewer(viewer, seen)
    if not viewer or not FrameCanBeUsed(viewer) then return true end
    local pool = viewer.itemFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then return false end

    return pcall(function()
        for frame in pool:EnumerateActive() do
            if frame then
                seen[frame] = true
                RefreshCDMFrame(frame)
            end
        end
    end)
end

local function ReconcileCDMFrames()
    if not DB.cdm then
        for frame in pairs(R.cdmFrames) do RefreshCDMFrame(frame) end
        return
    end

    local seen = NewWeakKeyTable()
    local allReadable = true
    local foundViewer = false

    for i = 1, #CDM_VIEWER_NAMES do
        local viewer = _G[CDM_VIEWER_NAMES[i]]
        if viewer then
            foundViewer = true
            R.cdmViewers[viewer] = true
            if not EnumerateCDMViewer(viewer, seen) then allReadable = false end
        end
    end

    -- A temporary inaccessible/transitioning pool must not erase correct state.
    if foundViewer and allReadable then
        for frame in pairs(R.cdmFrames) do
            if not seen[frame] then
                HideFrameGlow(frame)
                local state = R.frameState[frame]
                if state then state.isCDM = false end
                R.cdmFrames[frame] = nil
            end
        end
    end
end

local function AttachCDMHooks()
    if R.cdmHooksAttached or type(hooksecurefunc) ~= "function" then
        ReconcileCDMFrames()
        return
    end

    local attached = false
    local viewerMixin = _G.CooldownViewerMixin
    if type(viewerMixin) == "table" and type(viewerMixin.OnAcquireItemFrame) == "function" then
        hooksecurefunc(viewerMixin, "OnAcquireItemFrame", function(_, itemFrame)
            if itemFrame then RefreshCDMFrame(itemFrame) end
        end)
        attached = true
    end

    local dataMixin = _G.CooldownViewerItemDataMixin
    if type(dataMixin) == "table" then
        if type(dataMixin.SetCooldownID) == "function" then
            hooksecurefunc(dataMixin, "SetCooldownID", function(itemFrame)
                RefreshCDMFrame(itemFrame)
            end)
            attached = true
        end
        if type(dataMixin.ClearCooldownID) == "function" then
            hooksecurefunc(dataMixin, "ClearCooldownID", function(itemFrame)
                RefreshCDMFrame(itemFrame)
            end)
            attached = true
        end
        if type(dataMixin.ResetCooldownData) == "function" then
            hooksecurefunc(dataMixin, "ResetCooldownData", function(itemFrame)
                RefreshCDMFrame(itemFrame)
            end)
            attached = true
        end
        if type(dataMixin.SetOverrideSpell) == "function" then
            hooksecurefunc(dataMixin, "SetOverrideSpell", function(itemFrame)
                RefreshCDMFrame(itemFrame)
            end)
            attached = true
        end
    end

    R.cdmHooksAttached = attached
    ReconcileCDMFrames()
end

local function ApplyGlowState()
    CompactTrackedButtons()
    for i = 1, #R.trackedButtons do
        local button = R.trackedButtons[i]
        if R.glowActive then ShowFrameGlow(button) else HideFrameGlow(button) end
    end

    if DB.cdm then ReconcileCDMFrames() end
    for frame in pairs(R.cdmFrames) do
        if R.glowActive then ShowFrameGlow(frame) else HideFrameGlow(frame) end
    end
end

local function SetGlow(active, force)
    active = active and true or false
    if not force and active == R.glowActive then return end
    R.glowActive = active
    ApplyGlowState()
end

local function QueryOverlayState()
    if not (C_SpellActivationOverlay and type(C_SpellActivationOverlay.IsSpellOverlayed) == "function") then
        R.overlayQueryReadable = 0
        R.overlayQueryCandidates = #R.signalFamilyList
        R.overlayQueryAuthoritative = false
        return false, false
    end

    local readable = 0
    local candidates = #R.signalFamilyList
    for i = 1, candidates do
        local spellID = R.signalFamilyList[i]
        local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if ok and IsAccessible(overlayed) and type(overlayed) == "boolean" then
            readable = readable + 1
            if overlayed then
                R.overlayQueryReadable = readable
                R.overlayQueryCandidates = candidates
                R.overlayQueryAuthoritative = true
                return true, true
            end
        end
    end

    R.overlayQueryReadable = readable
    R.overlayQueryCandidates = candidates
    R.overlayQueryAuthoritative = candidates > 0 and readable == candidates
    return false, R.overlayQueryAuthoritative
end

local function HasEventSignal()
    local now = Now()
    local active = false
    for spellID, seenAt in pairs(R.eventSignals) do
        if type(seenAt) ~= "number" or now - seenAt > EVENT_FALLBACK_TTL then
            R.eventSignals[spellID] = nil
        else
            active = true
        end
    end
    return active
end

local function ReconcileGlow(reason)
    if not DB.enabled then
        R.lastDetection = "disabled"
        SetGlow(false)
        return
    end

    local now = Now()
    if R.testUntil > now then
        R.lastDetection = "test"
        SetGlow(true)
        return
    end

    local queryActive, queryAuthoritative = QueryOverlayState()
    local eventActive = HasEventSignal()
    local withinShowGrace = eventActive and (now - R.lastOverlayShowAt) <= OVERLAY_SHOW_GRACE

    if queryActive then
        R.lastDetection = "overlay-query"
        SetGlow(true)
    elseif eventActive and (withinShowGrace or not queryAuthoritative) then
        R.lastDetection = withinShowGrace and "overlay-event-grace" or "overlay-event-fallback"
        SetGlow(true)
    else
        if queryAuthoritative then ClearMap(R.eventSignals) end
        R.lastDetection = queryAuthoritative and "overlay-query-off" or "no-readable-signal"
        SetGlow(false)
    end

    if DB.debug and reason then
        Log(("Reconcile %s: query=%s authoritative=%s event=%s -> %s")
            :format(tostring(reason), tostring(queryActive), tostring(queryAuthoritative), tostring(eventActive), tostring(R.glowActive)))
    end
end

local function QueueReconcile(reason, delay)
    delay = delay or 0
    if delay <= 0 then
        ReconcileGlow(reason)
        return
    end

    if R.reconcileTimer and type(R.reconcileTimer.Cancel) == "function" then
        pcall(R.reconcileTimer.Cancel, R.reconcileTimer)
    end
    R.reconcileTimer = nil

    local function Run()
        R.reconcileTimer = nil
        ReconcileGlow(reason)
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        R.reconcileTimer = C_Timer.NewTimer(delay, Run)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, Run)
    else
        Run()
    end
end

local function SetEventSignal(spellID)
    local now = Now()
    R.eventSignals[spellID] = now
    R.lastOverlayShowAt = now

    local oldTimer = R.eventSignalTimers[spellID]
    if oldTimer and type(oldTimer.Cancel) == "function" then pcall(oldTimer.Cancel, oldTimer) end
    R.eventSignalTimers[spellID] = nil

    local function Expire()
        R.eventSignalTimers[spellID] = nil
        if R.eventSignals[spellID] == now then
            R.eventSignals[spellID] = nil
            ReconcileGlow("event-ttl")
        end
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        R.eventSignalTimers[spellID] = C_Timer.NewTimer(EVENT_FALLBACK_TTL, Expire)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(EVENT_FALLBACK_TTL, Expire)
    end

    -- SHOW is synchronous, but the query surface can lag behind the event within
    -- the same frame. Re-evaluate once the short grace window closes so a readable
    -- false cannot leave an event-only glow active until the long fallback TTL.
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(OVERLAY_SHOW_GRACE + 0.01, function()
            if R.eventSignals[spellID] == now then
                ReconcileGlow("show-grace-expired")
            end
        end)
    end
end

local function ClearEventSignal(spellID)
    R.eventSignals[spellID] = nil
    local timer = R.eventSignalTimers[spellID]
    if timer and type(timer.Cancel) == "function" then pcall(timer.Cancel, timer) end
    R.eventSignalTimers[spellID] = nil
end

local function HandleOverlayShow(spellID)
    spellID = SafeNumber(spellID)
    if not spellID then return end

    if IsRelevantSignal(spellID) then
        SetEventSignal(spellID)
        ReconcileGlow("overlay-show")
        QueueReconcile("overlay-show-delayed", OVERLAY_RECONCILE_DELAY)
    else
        -- An unrelated overlay event is only a wake-up signal. This catches a
        -- newly hotfixed proc payload once the official query reports one of our
        -- known action/replacement spells, without treating every overlay as Sudden Doom.
        QueueReconcile("overlay-wakeup", OVERLAY_RECONCILE_DELAY)
    end
end

local function HandleOverlayHide(spellID)
    spellID = SafeNumber(spellID)
    if not spellID then return end

    if IsRelevantSignal(spellID) then
        ClearEventSignal(spellID)
        ReconcileGlow("overlay-hide")
    end
    QueueReconcile("overlay-hide-delayed", OVERLAY_RECONCILE_DELAY)
end

local function PrimeTrackedAlerts()
    if InCombat() then return end
    CompactTrackedButtons()
    for i = 1, #R.trackedButtons do EnsureAlert(R.trackedButtons[i]) end
    for frame in pairs(R.cdmFrames) do EnsureAlert(frame) end
end

function SDG:RescanButtons(deep)
    if InCombat() then
        R.needsRescan = true
        R.pendingDeep = R.pendingDeep or deep
        return
    end

    R.needsRescan = false
    for i = 1, #R.trackedButtons do HideFrameGlow(R.trackedButtons[i]) end
    ClearArray(R.trackedButtons)
    R.trackedButtonSet = NewWeakKeyTable()

    ScanActionSlots()
    MapNamedButtons()
    if deep then DeepMapButtons(25000) end

    AttachCDMHooks()
    ReconcileCDMFrames()
    PrimeTrackedAlerts()
    ApplyGlowState()

    local slotCount = 0
    for _ in pairs(R.trackedSlots) do slotCount = slotCount + 1 end
    Log(("Rescan complete: slots=%d buttons=%d deep=%s")
        :format(slotCount, #R.trackedButtons, tostring(deep and true or false)))
end

function SDG:RequestRescan(reason, deep)
    R.rescanReason = reason or R.rescanReason
    R.queuedDeep = R.queuedDeep or deep

    if InCombat() then
        R.needsRescan = true
        R.pendingDeep = R.pendingDeep or deep
        return
    end

    if R.rescanTimer then return end

    local function Run()
        R.rescanTimer = nil
        local useDeep = R.queuedDeep or R.pendingDeep
        R.queuedDeep = false
        R.pendingDeep = false
        local why = R.rescanReason
        R.rescanReason = nil
        SDG:RescanButtons(useDeep)
        ReconcileGlow(why or "rescan")
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        R.rescanTimer = C_Timer.NewTimer(RESCAN_DELAY, Run)
    elseif C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(RESCAN_DELAY, Run)
        R.rescanTimer = true
    else
        Run()
    end
end

local function AttachActionButtonCallback()
    if R.actionCallbackAttached then return end
    if not (EventRegistry and type(EventRegistry.RegisterCallback) == "function") then return end

    EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button)
        if R.class ~= "DEATHKNIGHT" or not button then return end
        local matches = IsCurrentTargetButton(button)
        if matches then
            AddTrackedButton(button)
            if not InCombat() then EnsureAlert(button) end
            if R.glowActive then ShowFrameGlow(button) end
        else
            HideFrameGlow(button)
            if not InCombat() then
                RemoveTrackedButton(button)
            else
                R.needsRescan = true
            end
        end
    end, R.actionCallbackOwner)

    R.actionCallbackAttached = true
end

local frame = CreateFrame("Frame")

local function RegisterRuntimeEvents()
    if R.runtimeRegistered then return end
    R.runtimeRegistered = true

    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    frame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    frame:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
    frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    frame:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
    frame:RegisterEvent("UPDATE_BINDINGS")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("SPELL_SECRECY_CHANGED")
    frame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
    frame:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

function SDG:OnLogin()
    if R.didLogin then return end
    R.didLogin = true

    local _, class = UnitClass("player")
    R.class = class
    InitializeDB()
    RebuildSpellFamilies()

    if class ~= "DEATHKNIGHT" then
        R.lastDetection = "non-dk"
        SetGlow(false, true)
        return
    end

    RegisterRuntimeEvents()
    AttachActionButtonCallback()
    AttachCDMHooks()
    self:RescanButtons(false)
    ReconcileGlow("login")

    if #R.trackedButtons == 0 and C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0.35, function() SDG:RequestRescan("login-retry-1", false) end)
        C_Timer.After(1.00, function()
            if #R.trackedButtons == 0 then SDG:RequestRescan("login-retry-2", false) end
        end)
    end
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        SDG:OnLogin()
        return
    end
    if R.class ~= "DEATHKNIGHT" then return end

    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        HandleOverlayShow(...)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        HandleOverlayHide(...)
    elseif event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        local baseSpellID, overrideSpellID = ...
        if LearnExplicitOverride(baseSpellID, overrideSpellID, event) then
            SDG:RequestRescan(event, false)
        end
        ReconcileGlow(event)
    elseif event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        RebuildSpellFamilies()
        SDG:RequestRescan(event, false)
    elseif event == "SPELL_SECRECY_CHANGED" then
        RebuildSpellFamilies()
        ReconcileGlow(event)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and IsTargetFamilySpell(spellID, true) then
            QueueReconcile("spellcast", OVERLAY_RECONCILE_DELAY)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        PrimeTrackedAlerts()
        if R.needsRescan then
            SDG:RequestRescan(event, R.pendingDeep)
        else
            ReconcileCDMFrames()
            ReconcileGlow(event)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ReconcileGlow(event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        SDG:RequestRescan(event, false)
        ReconcileGlow(event)
    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_ActionBar" then
            AttachActionButtonCallback()
            SDG:RequestRescan(event, false)
        elseif addonName == CDM_ADDON then
            AttachCDMHooks()
            SDG:RequestRescan(event, false)
        end
    elseif event == "ACTIONBAR_SLOT_CHANGED" or
           event == "ACTIONBAR_PAGE_CHANGED" or
           event == "UPDATE_OVERRIDE_ACTIONBAR" or
           event == "UPDATE_BONUS_ACTIONBAR" or
           event == "UPDATE_VEHICLE_ACTIONBAR" or
           event == "UPDATE_BINDINGS" or
           event == "PLAYER_TALENT_UPDATE" or
           event == "TRAIT_CONFIG_UPDATED" or
           event == "PLAYER_SPECIALIZATION_CHANGED" or
           event == "SPELLS_CHANGED" then
        RebuildSpellFamilies()
        SDG:RequestRescan(event, false)
    end
end

frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("PLAYER_LOGIN")

if type(_G.IsLoggedIn) == "function" and _G.IsLoggedIn() then
    SDG:OnLogin()
end

local function FormatIDList(list)
    if type(list) ~= "table" or #list == 0 then return "(empty)" end
    local result = {}
    for i = 1, #list do result[i] = tostring(list[i]) end
    return table.concat(result, ",")
end

local function CountWeakSet(set)
    local count = 0
    for _ in pairs(set) do count = count + 1 end
    return count
end

local function DumpStatus()
    Print(("version=%s schema=%d enabled=%s combat=%s glow=%s detection=%s")
        :format(GetAddonVersion(), CURRENT_SCHEMA, tostring(DB.enabled), tostring(InCombat()), tostring(R.glowActive), tostring(R.lastDetection)))
    Print(("buttons=%d cdm=%d query=%d/%d authoritative=%s eventSignals=%d")
        :format(#R.trackedButtons, CountWeakSet(R.cdmFrames), R.overlayQueryReadable,
            R.overlayQueryCandidates, tostring(R.overlayQueryAuthoritative), CountWeakSet(R.eventSignals)))
    Print("targets configured: " .. FormatIDList(DB.targetSpellIDs))
    Print("targets resolved: " .. FormatIDList(R.targetFamilyList))
    Print("signals resolved: " .. FormatIDList(R.signalFamilyList))
end

local function ToggleID(list, value, label)
    local id = SafeNumber(value)
    if not id or id < 1 then
        Print("Usage: /sdglow " .. label .. " <spellID>")
        return
    end

    for i = 1, #list do
        if list[i] == id then
            table.remove(list, i)
            RebuildSpellFamilies()
            SDG:RequestRescan(label .. "-removed", false)
            ReconcileGlow(label .. "-removed")
            Print("Removed " .. label .. " spellID " .. tostring(id))
            return
        end
    end

    list[#list + 1] = id
    RebuildSpellFamilies()
    SDG:RequestRescan(label .. "-added", false)
    ReconcileGlow(label .. "-added")
    Print("Added " .. label .. " spellID " .. tostring(id))
end

_G.SLASH_SUDDEN_DOOM_GLOW1 = "/sdglow"
_G.SlashCmdList["SUDDEN_DOOM_GLOW"] = function(message)
    local command, argument = (message or ""):match("^(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()

    if command == "" or command == "help" then
        Print("/sdglow status | debug | rescan [deep] | test")
        Print("/sdglow spell <spellID> | signal <spellID> | spells")
        Print("/sdglow cdm on|off | on | off")
    elseif command == "status" or command == "dump" then
        DumpStatus()
    elseif command == "debug" then
        DB.debug = not DB.debug
        Print("Debug: " .. (DB.debug and "ON" or "OFF"))
        if SDG.DebugUI then
            if DB.debug and type(SDG.DebugUI.Show) == "function" then SDG.DebugUI:Show() end
            if not DB.debug and type(SDG.DebugUI.Hide) == "function" then SDG.DebugUI:Hide() end
        end
    elseif command == "rescan" then
        local deep = argument:lower():find("deep", 1, true) ~= nil
        SDG:RequestRescan("slash", deep)
        Print(InCombat() and "Rescan deferred until combat ends" or "Rescan queued")
    elseif command == "test" then
        R.testToken = R.testToken + 1
        local token = R.testToken
        R.testUntil = Now() + 2.0
        ReconcileGlow("test")
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(2.05, function()
                if R.testToken == token then
                    R.testUntil = 0
                    ReconcileGlow("test-end")
                end
            end)
        end
        Print("Test glow for 2 seconds")
    elseif command == "spell" then
        ToggleID(DB.targetSpellIDs, argument, "spell")
    elseif command == "signal" or command == "aura" then
        if command == "aura" then Print("'aura' is retained as an alias for 'signal'") end
        ToggleID(DB.signalSpellIDs, argument, "signal")
    elseif command == "spells" then
        RebuildSpellFamilies()
        Print("targets configured: " .. FormatIDList(DB.targetSpellIDs))
        Print("targets resolved: " .. FormatIDList(R.targetFamilyList))
        Print("signals resolved: " .. FormatIDList(R.signalFamilyList))
    elseif command == "cdm" then
        if argument == "on" then DB.cdm = true
        elseif argument == "off" then DB.cdm = false
        else DB.cdm = not DB.cdm end
        AttachCDMHooks()
        ReconcileCDMFrames()
        ApplyGlowState()
        Print("Cooldown Viewer mirror: " .. (DB.cdm and "ON" or "OFF"))
    elseif command == "on" then
        DB.enabled = true
        ReconcileGlow("enabled")
        Print("Enabled")
    elseif command == "off" then
        DB.enabled = false
        R.lastDetection = "disabled"
        SetGlow(false, true)
        Print("Disabled")
    else
        Print("Unknown command. Use /sdglow help")
    end
end
