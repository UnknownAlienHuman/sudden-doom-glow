-- Sudden Doom Glow
-- Retail 12.1.5: official Spell Activation Overlay state -> addon-owned glow surfaces.

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

local CURRENT_SCHEMA = 4
local RESCAN_DELAY = 0.08
local OVERLAY_RECONCILE_DELAY = 0.06
local OVERLAY_SHOW_GRACE = 0.20
local EVENT_FALLBACK_TTL = 30.0

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
    explicitOverrides = {},

    trackedButtons = NewWeakKeyTable(),
    knownButtons = NewWeakKeyTable(),
    frameState = NewWeakKeyTable(),

    cdmFrames = NewWeakKeyTable(),
    cdmViewerHooks = NewWeakKeyTable(),
    cdmItemHooks = NewWeakKeyTable(),

    eventSignals = {},
    timers = {},
    overlayQueryReadable = 0,
    overlayQueryCandidates = 0,
    overlayQueryAuthoritative = false,

    glowActive = false,
    lastDetection = "none",
    testUntil = 0,
    needsGeometry = false,
    unsupportedSchema = false,

    needsRescan = false,
    rescanDeep = false,
    rescanReason = nil,

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

local function CountEntries(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Access checks precede nil comparisons, coercion, indexing and arithmetic.
-- A failed read stays unknown; pcall is only an error boundary, never a secret gate.
local function IsAccessible(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return false end
    if type(canaccessvalue) == "function" then return canaccessvalue(value) end
    return true
end

local function SafeNumber(value)
    if not IsAccessible(value) then return nil end
    if type(value) == "string" then value = tonumber(value) end
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function SafeID(value)
    value = SafeNumber(value)
    if value and value > 0 and value <= 2147483647 and value % 1 == 0 then return value end
    return nil
end

local function SafeString(value)
    if IsAccessible(value) and type(value) == "string" then return value end
    return nil
end

local function FrameCanBeUsed(frame)
    if not IsAccessible(frame) or not frame then return false end
    local kind = type(frame)
    if kind ~= "table" and kind ~= "userdata" then return false end
    if type(frame.IsForbidden) == "function" then
        local ok, forbidden = pcall(frame.IsForbidden, frame)
        if not ok or not IsAccessible(forbidden) or forbidden then return false end
    end
    if type(frame.CanBeAccessedInContext) == "function" then
        local ok, accessible = pcall(frame.CanBeAccessedInContext, frame)
        if not ok or not IsAccessible(accessible) or not accessible then return false end
    end
    return true
end

local function RuntimeEnabled()
    return DB and DB.enabled and R.class == "DEATHKNIGHT" and not R.unsupportedSchema
end

local function CancelTimer(key)
    local timer = R.timers[key]
    R.timers[key] = nil
    if timer and timer.handle then timer.handle:Cancel() end
end

local function CancelTimers()
    for key in pairs(R.timers) do CancelTimer(key) end
end

local function ScheduleTimer(key, delay, callback)
    CancelTimer(key)
    if not RuntimeEnabled() then return end
    local timer = {}
    R.timers[key] = timer
    local function Run()
        if R.timers[key] ~= timer then return end
        R.timers[key] = nil
        if RuntimeEnabled() then callback() end
    end
    if C_Timer and type(C_Timer.NewTimer) == "function" then
        timer.handle = C_Timer.NewTimer(delay, Run)
    elseif C_Timer and type(C_Timer.After) == "function" then
        -- Identity gating still cancels late callbacks on this compatibility path.
        C_Timer.After(delay, Run)
    else
        R.timers[key] = nil
    end
end

local function GetAddonVersion()
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        return SafeString(C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "unknown"
    end
    return "unknown"
end

local function CopyNumericList(source)
    local result = {}
    local seen = {}
    if type(source) ~= "table" then return result end

    for i = 1, #source do
        local id = SafeID(source[i])
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
    local saved = _G.SuddenDoomGlowDB
    if type(saved) ~= "table" then
        saved = {}
        _G.SuddenDoomGlowDB = saved
    end
    local schema = SafeNumber(saved.schemaVersion) or 0
    if schema > CURRENT_SCHEMA then
        -- Do not downgrade or overwrite settings written by a newer release.
        R.unsupportedSchema = true
        DB = { enabled = false, debug = false, cdm = false, glowScale = 1.4,
            targetSpellIDs = {}, signalSpellIDs = {} }
        Print("Settings belong to a newer addon version. Update the addon to use them.")
        return
    end
    DB = saved
    if type(DB.targetSpellIDs) ~= "table" and type(DB.procSpellIDs) == "table" then
        DB.targetSpellIDs = CopyNumericList(DB.procSpellIDs)
    end
    if type(DB.signalSpellIDs) ~= "table" and type(DB.auraIDs) == "table" then
        DB.signalSpellIDs = CopyNumericList(DB.auraIDs)
    end
    if type(DB.enabled) ~= "boolean" then DB.enabled = true end
    if type(DB.debug) ~= "boolean" then DB.debug = false end
    if type(DB.cdm) ~= "boolean" then DB.cdm = true end
    local scale = SafeNumber(DB.glowScale)
    DB.glowScale = scale and math.max(1, math.min(1.8, scale)) or 1.4

    -- Defaults are seeded once. In current schemas an empty list is intentional.
    if schema < 3 or type(DB.targetSpellIDs) ~= "table" then
        DB.targetSpellIDs = MergeNumericDefaults(DB.targetSpellIDs, DEFAULT_TARGET_SPELL_IDS)
    else
        DB.targetSpellIDs = CopyNumericList(DB.targetSpellIDs)
    end
    if schema < 3 or type(DB.signalSpellIDs) ~= "table" then
        DB.signalSpellIDs = MergeNumericDefaults(DB.signalSpellIDs, DEFAULT_SIGNAL_SPELL_IDS)
    else
        DB.signalSpellIDs = CopyNumericList(DB.signalSpellIDs)
    end
    DB.schemaVersion = CURRENT_SCHEMA
    DB.addonVersion = GetAddonVersion()
    DB.procSpellIDs, DB.auraIDs = nil, nil
    DB.auraEnabled, DB.overlayEnabled, DB.costEnabled, DB.slots = nil, nil, nil, nil
end

local function GetBaseSpellID(spellID)
    spellID = SafeID(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.GetBaseSpell) == "function" then
        local ok, baseID = pcall(C_Spell.GetBaseSpell, spellID)
        if ok then
            baseID = SafeID(baseID)
            if baseID and baseID > 0 then return baseID end
        end
    end
    return spellID
end

local function GetOverrideSpellID(spellID)
    spellID = SafeID(spellID)
    if not spellID then return nil end
    if C_Spell and type(C_Spell.GetOverrideSpell) == "function" then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok then
            overrideID = SafeID(overrideID)
            if overrideID and overrideID > 0 then return overrideID end
        end
    end
    return spellID
end

local function AddUniqueID(set, list, value)
    local id = SafeID(value)
    if not id or set[id] then return false end
    set[id] = true
    list[#list + 1] = id
    return true
end

local function AddTargetFamilyChain(spellID, depth)
    depth = depth or 0
    if depth > 8 then return end

    spellID = SafeID(spellID)
    if not spellID then return end

    if not AddUniqueID(R.targetFamily, R.targetFamilyList, spellID) then return end
    local baseID = GetBaseSpellID(spellID)
    if baseID and baseID ~= spellID then
        AddTargetFamilyChain(baseID, depth + 1)
    end

    local overrideID = GetOverrideSpellID(spellID)
    if overrideID and overrideID ~= spellID then
        AddTargetFamilyChain(overrideID, depth + 1)
    end
end

local function RebuildSpellFamilies()
    ClearMap(R.targetRoots)
    ClearArray(R.targetRootList)
    ClearMap(R.targetFamily)
    ClearArray(R.targetFamilyList)
    ClearMap(R.signalFamily)
    ClearArray(R.signalFamilyList)

    for i = 1, #DB.targetSpellIDs do
        local configuredID = SafeID(DB.targetSpellIDs[i])
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
end

local function IsTargetFamilySpell(spellID, learn)
    spellID = SafeID(spellID)
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
    if not IsAccessible(baseSpellID) or not IsAccessible(overrideSpellID) then return false end
    baseSpellID = SafeID(baseSpellID)
    overrideSpellID = SafeID(overrideSpellID)
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
    spellID = SafeID(spellID)
    if not spellID then return false end
    if R.signalFamily[spellID] then return true end
    if IsTargetFamilySpell(spellID, true) then
        AddUniqueID(R.signalFamily, R.signalFamilyList, spellID)
        return true
    end
    return false
end

local function GetActionSpellID(slot)
    slot = SafeID(slot)
    if not slot then return nil end
    if C_ActionBar and type(C_ActionBar.GetSpell) == "function" then
        local ok, spellID = pcall(C_ActionBar.GetSpell, slot)
        if not ok or not IsAccessible(spellID) then return nil end
        spellID = SafeID(spellID)
        if spellID then return spellID end
    end
    -- Resolved macro spell only: text mentions and inactive conditional branches
    -- are not evidence that the current action belongs to the target family.
    if type(GetActionInfo) ~= "function" then return nil end
    local ok, actionType, id = pcall(GetActionInfo, slot)
    if not ok then return nil end
    actionType, id = SafeString(actionType), SafeID(id)
    if actionType == "spell" then return id end
    if actionType == "macro" and id and type(GetMacroSpell) == "function" then
        local resolved, spellID = pcall(GetMacroSpell, id)
        if resolved then return SafeID(spellID) end
    end
    return nil
end

local function SlotMatchesTarget(slot)
    local spellID = GetActionSpellID(slot)
    return spellID and IsTargetFamilySpell(spellID, true) or false
end

local function GetButtonSlot(button)
    if not FrameCanBeUsed(button) then return nil end
    -- The first assignment provider is authoritative. Never search stale alternate
    -- fields for a matching spell after the current page has changed.
    if type(button.GetPagedID) == "function" then
        local ok, value = pcall(button.GetPagedID, button)
        if not ok or not IsAccessible(value) then return nil end
        if value ~= nil then return SafeID(value) end
    end
    if type(button.GetAction) == "function" then
        local ok, actionType, value = pcall(button.GetAction, button)
        if not ok or not IsAccessible(actionType) or not IsAccessible(value) then return nil end
        if type(actionType) == "number" then return SafeID(actionType) end
        if actionType ~= nil then
            return actionType == "action" and SafeID(value) or nil
        end
    end
    if not IsAccessible(button.action) then return nil end
    if button.action ~= nil then return SafeID(button.action) end
    if not IsAccessible(button._state_action) then return nil end
    if button._state_action ~= nil then return SafeID(button._state_action) end
    if type(button.GetAttribute) == "function" then
        local ok, value = pcall(button.GetAttribute, button, "action")
        if ok then return SafeID(value) end
    end
    return nil
end

local function IsCurrentTargetButton(button)
    local slot = GetButtonSlot(button)
    return slot and SlotMatchesTarget(slot) or false
end

local function GetRenderTarget(frame)
    if not FrameCanBeUsed(frame) then return nil end
    local iconFrame = frame.Icon
    if FrameCanBeUsed(iconFrame) and type(iconFrame.GetObjectType) == "function" then
        local ok, objectType = pcall(iconFrame.GetObjectType, iconFrame)
        if ok and SafeString(objectType) == "Frame" then
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
    if InCombat() or not FrameCanBeUsed(state.alert) then return end
    local target = GetRenderTarget(frame)
    if not target then return end
    if state.renderTarget ~= target and type(state.alert.SetParent) == "function" then
        state.alert:SetParent(target)
    end

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
        pcall(state.alert.SetSize, state.alert, width * DB.glowScale, height * DB.glowScale)
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
    if not FrameCanBeUsed(frame) then return nil end
    local state = GetFrameState(frame)
    if state.alert then return FrameCanBeUsed(state.alert) and state.alert or nil end
    if InCombat() then R.needsRescan = true; return nil end
    if type(CreateFrame) ~= "function" then return nil end

    local target = GetRenderTarget(frame)
    if not target or not FrameCanBeUsed(target) then return nil end
    local ok, alert = pcall(CreateFrame, "Frame", nil, target, "ActionButtonSpellAlertTemplate")
    if not ok or not FrameCanBeUsed(alert) then
        Log("ActionButtonSpellAlertTemplate unavailable for a render target")
        return nil
    end

    state.alert = alert
    state.renderTarget = target
    state.shown = false
    pcall(alert.Hide, alert)
    RefreshAlertGeometry(frame, state)
    if type(target.HookScript) == "function" then
        target:HookScript("OnSizeChanged", function()
            if not RuntimeEnabled() then return end
            if InCombat() then R.needsGeometry = true
            else RefreshAlertGeometry(frame, state) end
        end)
    end
    return alert
end

local function StopAnimation(animation)
    if FrameCanBeUsed(animation) and type(animation.Stop) == "function" then pcall(animation.Stop, animation) end
end

local function PlayAnimation(animation)
    if FrameCanBeUsed(animation) and type(animation.Play) == "function" then
        local ok = pcall(animation.Play, animation)
        return ok
    end
    return false
end

local HideFrameGlow

local function ShowFrameGlow(frame)
    if not FrameCanBeUsed(frame) then HideFrameGlow(frame); return end
    local state = GetFrameState(frame)
    if not state.isCDM then
        local current = IsCurrentTargetButton(frame)
        if not current then
            HideFrameGlow(frame)
            return
        end
    end

    if state.isCDM and not state.assignmentReadable then return end
    if state.shown then return end
    local alert = EnsureAlert(frame)
    if not alert then return end

    StopAnimation(alert.ProcLoop)
    if not pcall(alert.Show, alert) then return end
    alert.animationPlaying = true
    if not PlayAnimation(alert.ProcStartAnim) then
        PlayAnimation(alert.ProcLoop)
    end
    state.shown = true
end

HideFrameGlow = function(frame)
    -- Only the ordinary identity is needed to find our own presentation. An
    -- inaccessible parent must not prevent hiding an accessible addon child.
    if not IsAccessible(frame) or not frame then return end
    local state = R.frameState[frame]
    if not state or not FrameCanBeUsed(state.alert) then return end
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

local function RefreshButton(button, slot)
    if not IsAccessible(button) or not button then return end
    if slot and SlotMatchesTarget(slot) then
        R.trackedButtons[button] = true
        EnsureAlert(button)
        if R.glowActive then ShowFrameGlow(button) else HideFrameGlow(button) end
    else
        R.trackedButtons[button] = nil
        HideFrameGlow(button)
    end
end

local NAMED_BUTTON_SETS = {
    { "ActionButton", 12, true },
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
    { "BT4Button", 180, true },
    { "DominosActionButton", 180, true },
}

local function MapNamedButtons()
    for setIndex = 1, #NAMED_BUTTON_SETS do
        local prefix = NAMED_BUTTON_SETS[setIndex][1]
        local count = NAMED_BUTTON_SETS[setIndex][2]
        for index = 1, count do
            local button = _G[prefix .. index]
            if FrameCanBeUsed(button) then
                R.knownButtons[button] = true
                -- Pageable bars need an existing overlay before a combat page
                -- switch. Static Blizzard bars allocate only for current targets.
                if NAMED_BUTTON_SETS[setIndex][3] then EnsureAlert(button) end
            end
        end
    end

    for bar = 1, 15 do
        for index = 1, 12 do
            local button = _G["ElvUI_Bar" .. bar .. "Button" .. index]
            if FrameCanBeUsed(button) then
                R.knownButtons[button] = true
                EnsureAlert(button)
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
            objectType = ok and SafeString(objectType) or nil
            if ok and (objectType == "Button" or objectType == "CheckButton") then
                local matches = IsCurrentTargetButton(frame)
                if matches then R.knownButtons[frame] = true end
            end
        end
        frame = EnumerateFrames(frame)
    end
end

-- Narrow source-coupled adapter: ordinary configured identity only. GetSpellID
-- can prefer managed aura data in 12.1.5, so it is deliberately not queried here.
local function CDMFrameMatches(frame)
    if not FrameCanBeUsed(frame) or type(frame.GetBaseSpellID) ~= "function" then return nil end
    local ok, spellID = pcall(frame.GetBaseSpellID, frame)
    if not ok or not IsAccessible(spellID) then return nil end
    spellID = SafeID(spellID)
    return spellID and IsTargetFamilySpell(spellID, true) or false
end

local function ClearCDMFrame(frame)
    if not IsAccessible(frame) or not frame then return end
    HideFrameGlow(frame)
    R.cdmFrames[frame] = nil
    local state = R.frameState[frame]
    if state then state.isCDM = false; state.assignmentReadable = false end
end

local function RefreshCDMFrame(frame)
    if not RuntimeEnabled() or not DB.cdm then return end
    if not IsAccessible(frame) or not frame then return end
    local matches = CDMFrameMatches(frame)
    if matches == nil then
        -- Keep membership when identity cannot be read, but do not render an
        -- unverified assignment after a pooled item's lifecycle callback.
        local state = R.frameState[frame]
        if state then state.assignmentReadable = false end
        HideFrameGlow(frame)
        return
    end
    if not matches then ClearCDMFrame(frame); return end
    local state = GetFrameState(frame)
    state.isCDM, state.assignmentReadable = true, true
    R.cdmFrames[frame] = true
    EnsureAlert(frame)
    if R.glowActive then ShowFrameGlow(frame) else HideFrameGlow(frame) end
end

local function HookCDMItem(frame)
    if not FrameCanBeUsed(frame) or type(hooksecurefunc) ~= "function" then return end
    local hooked = R.cdmItemHooks[frame]
    if not hooked then hooked = {}; R.cdmItemHooks[frame] = hooked end
    for _, name in ipairs({ "SetCooldownID", "SetOverrideSpell", "ClearCooldownID", "ResetCooldownData" }) do
        if not hooked[name] and type(frame[name]) == "function" then
            local clear = name == "ClearCooldownID" or name == "ResetCooldownData"
            hooksecurefunc(frame, name, function(item)
                if not RuntimeEnabled() or not DB.cdm then return end
                if clear then ClearCDMFrame(item) else RefreshCDMFrame(item) end
            end)
            hooked[name] = true
        end
    end
end

local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}

local function EnumerateCDMViewer(viewer, seen)
    if not FrameCanBeUsed(viewer) then return false end
    local pool = viewer.itemFramePool
    if not IsAccessible(pool) or type(pool) ~= "table" or type(pool.EnumerateActive) ~= "function" then return false end
    return pcall(function()
        for item in pool:EnumerateActive() do
            if not IsAccessible(item) then error("Unavailable viewer item") end
            if item then
                seen[item] = true
                HookCDMItem(item)
                RefreshCDMFrame(item)
            end
        end
    end)
end

local function ReconcileCDMFrames()
    if not RuntimeEnabled() or not DB.cdm then
        for item in pairs(R.cdmFrames) do ClearCDMFrame(item) end
        return
    end
    local seen = NewWeakKeyTable()
    local allReadable, foundViewer = true, false
    for i = 1, #CDM_VIEWER_NAMES do
        local viewer = _G[CDM_VIEWER_NAMES[i]]
        if IsAccessible(viewer) and viewer then
            foundViewer = true
            if FrameCanBeUsed(viewer) and type(hooksecurefunc) == "function" and
               not R.cdmViewerHooks[viewer] and type(viewer.OnAcquireItemFrame) == "function" then
                -- Mixins are copied into frames. Hook the actual instance, including
                -- instances created before this addon was loaded.
                hooksecurefunc(viewer, "OnAcquireItemFrame", function(_, item)
                    if not RuntimeEnabled() or not DB.cdm or not FrameCanBeUsed(item) then return end
                    HookCDMItem(item)
                    RefreshCDMFrame(item)
                end)
                R.cdmViewerHooks[viewer] = true
            end
            if not EnumerateCDMViewer(viewer, seen) then allReadable = false end
        elseif not IsAccessible(viewer) then
            allReadable = false
        end
    end
    if foundViewer and allReadable then
        for item in pairs(R.cdmFrames) do
            if IsAccessible(item) and not seen[item] then ClearCDMFrame(item) end
        end
    end
end

local function ApplyGlowState()
    for button in pairs(R.trackedButtons) do
        if R.glowActive then ShowFrameGlow(button) else HideFrameGlow(button) end
    end
    -- Proc events touch the tracked set only; pool enumeration belongs to lifecycle
    -- setup/recovery, never to the hot glow path.
    for item in pairs(R.cdmFrames) do
        if R.glowActive then ShowFrameGlow(item) else HideFrameGlow(item) end
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

local function ClearEventSignal(spellID)
    R.eventSignals[spellID] = nil
    CancelTimer("signal-expire:" .. spellID)
    CancelTimer("signal-grace:" .. spellID)
end

local function ClearEventSignals()
    for spellID in pairs(R.eventSignals) do ClearEventSignal(spellID) end
end

local function HasEventSignal()
    local now, newest = Now(), nil
    for spellID, seenAt in pairs(R.eventSignals) do
        if not R.signalFamily[spellID] or now - seenAt >= EVENT_FALLBACK_TTL then
            ClearEventSignal(spellID)
        elseif not newest or seenAt > newest then
            newest = seenAt
        end
    end
    return newest ~= nil, newest
end

local ReconcileGlow
ReconcileGlow = function(reason)
    if not RuntimeEnabled() then
        R.lastDetection = R.class == "DEATHKNIGHT" and "disabled" or "non-dk"
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
    local eventActive, newest = HasEventSignal()
    local withinShowGrace = eventActive and now - newest <= OVERLAY_SHOW_GRACE
    if queryActive then
        R.lastQueryActiveAt = now
        CancelTimer("query-expire")
        R.lastDetection = "overlay-query"
        SetGlow(true)
    elseif eventActive and (withinShowGrace or not queryAuthoritative) then
        R.lastDetection = withinShowGrace and "overlay-event-grace" or "overlay-event-fallback"
        SetGlow(true)
    elseif not queryAuthoritative and R.lastQueryActiveAt and now - R.lastQueryActiveAt < EVENT_FALLBACK_TTL then
        -- An inaccessible query is not an OFF signal. Retain only the last ordinary
        -- positive observation, bounded by the same hard fallback TTL.
        R.lastDetection = "overlay-query-unavailable"
        SetGlow(true)
        if not R.timers["query-expire"] then
            ScheduleTimer("query-expire", EVENT_FALLBACK_TTL - (now - R.lastQueryActiveAt), function()
                R.lastQueryActiveAt = nil
                ReconcileGlow("query-ttl")
            end)
        end
    else
        if queryAuthoritative then ClearEventSignals() end
        R.lastQueryActiveAt = nil
        CancelTimer("query-expire")
        R.lastDetection = queryAuthoritative and "overlay-query-off" or "no-readable-signal"
        SetGlow(false)
    end
    if DB.debug and reason then
        Log(("%s: query=%s readable=%d/%d event=%s glow=%s")
            :format(reason, tostring(queryActive), R.overlayQueryReadable, R.overlayQueryCandidates,
                tostring(eventActive), tostring(R.glowActive)))
    end
end

local function QueueReconcile(reason, delay)
    if not delay or delay <= 0 then ReconcileGlow(reason); return end
    -- Coalesce bursts without continually postponing an already queued read.
    if R.timers.reconcile then return end
    ScheduleTimer("reconcile", delay, function() ReconcileGlow(reason) end)
end

local function SetEventSignal(spellID)
    R.eventSignals[spellID] = Now()
    ScheduleTimer("signal-expire:" .. spellID, EVENT_FALLBACK_TTL, function()
        ClearEventSignal(spellID)
        ReconcileGlow("event-ttl")
    end)
    ScheduleTimer("signal-grace:" .. spellID, OVERLAY_SHOW_GRACE + 0.01, function()
        if R.eventSignals[spellID] then ReconcileGlow("show-grace-expired") end
    end)
end

local function HandleOverlayShow(spellID)
    spellID = SafeID(spellID)
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
    spellID = SafeID(spellID)
    if not spellID then return end

    if IsRelevantSignal(spellID) then
        ClearEventSignal(spellID)
        ReconcileGlow("overlay-hide")
    end
    QueueReconcile("overlay-hide-delayed", OVERLAY_RECONCILE_DELAY)
end

local function PrimeTrackedAlerts()
    if InCombat() then R.needsGeometry = true; return end
    for button in pairs(R.knownButtons) do
        if IsAccessible(button) then
            if R.trackedButtons[button] then EnsureAlert(button) end
            local state = R.frameState[button]
            if state then RefreshAlertGeometry(button, state) end
        end
    end
    for item in pairs(R.cdmFrames) do
        if IsAccessible(item) then
            EnsureAlert(item)
            local state = R.frameState[item]
            if state then RefreshAlertGeometry(item, state) end
        end
    end
    R.needsGeometry = false
end

local function RefreshKnownButtons(changedSlot)
    if not RuntimeEnabled() then return end
    for button in pairs(R.knownButtons) do
        local slot = GetButtonSlot(button)
        if not changedSlot or slot == changedSlot then
            RefreshButton(button, slot)
        end
    end
end

function SDG:RescanButtons(deep)
    if not RuntimeEnabled() then return end
    if InCombat() then
        R.needsRescan = true
        R.rescanDeep = R.rescanDeep or deep
        return
    end
    R.needsRescan = false
    RebuildSpellFamilies()
    MapNamedButtons()
    if deep then DeepMapButtons(25000) end
    RefreshKnownButtons()
    ReconcileCDMFrames()
    PrimeTrackedAlerts()
    if DB.debug then
        Log(("Rescan: buttons=%d deep=%s"):format(CountEntries(R.trackedButtons), tostring(not not deep)))
    end
end

function SDG:RequestRescan(reason, deep)
    if not RuntimeEnabled() then return end
    R.rescanReason = reason or R.rescanReason
    R.rescanDeep = R.rescanDeep or deep
    if InCombat() then
        R.needsRescan = true
        return
    end
    if R.timers.rescan then return end
    ScheduleTimer("rescan", RESCAN_DELAY, function()
        local useDeep = R.rescanDeep
        R.rescanDeep = false
        local why = R.rescanReason
        R.rescanReason = nil
        self:RescanButtons(useDeep)
        ReconcileGlow(why or "rescan")
    end)
end

local function AttachActionButtonCallback()
    if R.actionCallbackAttached or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
    EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button)
        if not RuntimeEnabled() or not FrameCanBeUsed(button) then return end
        R.knownButtons[button] = true
        RefreshButton(button, GetButtonSlot(button))
    end, R.actionCallbackOwner)
    R.actionCallbackAttached = true
end

local frame = CreateFrame("Frame")
local RUNTIME_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_MACROS", "MODIFIER_STATE_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
    "SPELLS_CHANGED", "SPELL_SECRECY_CHANGED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED", "ADDON_LOADED",
}

local function ResetTransientState(clearOverrides)
    CancelTimers()
    ClearMap(R.eventSignals)
    R.lastQueryActiveAt, R.testUntil = nil, 0
    R.needsRescan, R.rescanDeep = false, false
    R.rescanReason = nil
    if clearOverrides then ClearMap(R.explicitOverrides) end
    SetGlow(false, true)
end

local function StopRuntime()
    R.runtimeRegistered = false
    for i = 1, #RUNTIME_EVENTS do frame:UnregisterEvent(RUNTIME_EVENTS[i]) end
    frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    if R.actionCallbackAttached and EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("ActionButton.OnActionChanged", R.actionCallbackOwner)
        R.actionCallbackAttached = false
    end
    ResetTransientState(true)
    for item in pairs(R.cdmFrames) do ClearCDMFrame(item) end
    ClearMap(R.trackedButtons)
    R.lastDetection = "disabled"
end

local function StartRuntime()
    if not RuntimeEnabled() or R.runtimeRegistered then return end
    R.runtimeRegistered = true
    for i = 1, #RUNTIME_EVENTS do frame:RegisterEvent(RUNTIME_EVENTS[i]) end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    AttachActionButtonCallback()
    if InCombat() then
        -- Re-enable prepared surfaces without waiting for another proc or page
        -- event. Missing alerts remain deferred until structural work is allowed.
        RebuildSpellFamilies()
        R.needsRescan = true
        RefreshKnownButtons()
        ReconcileCDMFrames()
    else
        SDG:RescanButtons(false)
    end
    ReconcileGlow("enabled")
end

function SDG:GetOption(key)
    if key == "enabled" or key == "cdm" or key == "debug" or key == "glowScale" then
        return DB and DB[key]
    end
end

function SDG:SetOption(key, value)
    if not DB or R.unsupportedSchema then return false end
    if not IsAccessible(value) then return false end
    if key == "glowScale" then
        value = SafeNumber(value)
        if not value then return false end
        value = math.max(1, math.min(1.8, value))
    elseif key == "enabled" or key == "cdm" or key == "debug" then
        if type(value) ~= "boolean" then return false end
    else
        return false
    end
    if DB[key] == value then return true end
    DB[key] = value
    if key == "enabled" then
        if value then StartRuntime() else StopRuntime() end
    elseif key == "cdm" then
        ReconcileCDMFrames()
    elseif key == "glowScale" then
        if RuntimeEnabled() then PrimeTrackedAlerts() end
    elseif key == "debug" and self.DebugUI then
        if value then self.DebugUI:Show() else self.DebugUI:Hide() end
    end
    if type(self.NotifySettingsChanged) == "function" then self:NotifySettingsChanged(key) end
    return true
end

function SDG:TestGlow()
    if not RuntimeEnabled() then Print("Enable the addon on a Death Knight to test the glow."); return end
    R.testUntil = Now() + 2
    ReconcileGlow("test")
    ScheduleTimer("test", 2.05, function()
        R.testUntil = 0
        ReconcileGlow("test-end")
    end)
    Print("Test glow for 2 seconds")
end

function SDG:OnLogin()
    if R.didLogin then return end
    R.didLogin = true
    frame:UnregisterEvent("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    R.class = SafeString(class)
    InitializeDB()
    if type(self.RegisterSettings) == "function" then self:RegisterSettings() end
    if not RuntimeEnabled() then
        RebuildSpellFamilies()
        R.lastDetection = R.class == "DEATHKNIGHT" and "disabled" or "non-dk"
        return
    end
    StartRuntime()
    if not next(R.trackedButtons) then
        ScheduleTimer("login-retry", 0.35, function() self:RequestRescan("login-ready", false) end)
    end
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then SDG:OnLogin(); return end
    if not RuntimeEnabled() then return end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        HandleOverlayShow(...)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        HandleOverlayHide(...)
    elseif event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        local baseSpellID, overrideSpellID = ...
        if LearnExplicitOverride(baseSpellID, overrideSpellID, event) then
            RefreshKnownButtons()
            SDG:RequestRescan(event, false)
        end
        ReconcileGlow(event)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- Registration is player-only; the payload is not a proc-state source.
        QueueReconcile("spellcast", OVERLAY_RECONCILE_DELAY)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if R.needsGeometry then PrimeTrackedAlerts() end
        if R.needsRescan then SDG:RequestRescan(event)
        else ReconcileGlow(event) end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ReconcileGlow(event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetTransientState(true)
        RebuildSpellFamilies()
        SDG:RequestRescan(event, false)
        ReconcileGlow(event)
    elseif event == "ADDON_LOADED" then
        SDG:RequestRescan(event, false)
    elseif event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" or
           event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED" or
           event == "SPELL_SECRECY_CHANGED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if SafeString(unit) ~= "player" then return end
        end
        ResetTransientState(true)
        RebuildSpellFamilies()
        RefreshKnownButtons()
        SDG:RequestRescan(event, false)
        ReconcileGlow(event)
    else
        local changedSlot = event == "ACTIONBAR_SLOT_CHANGED" and SafeID((...)) or nil
        RefreshKnownButtons(changedSlot)
        -- Bar providers can update their assignment after our native event handler.
        -- One unfiltered pass covers every slot in a burst without retaining
        -- event arguments or replacing the pending timer on each invalidation.
        if not R.timers["action-refresh"] then
            ScheduleTimer("action-refresh", 0, RefreshKnownButtons)
        end
        QueueReconcile(event, OVERLAY_RECONCILE_DELAY)
    end
end

frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("PLAYER_LOGIN")

local function FormatIDList(list)
    if type(list) ~= "table" or #list == 0 then return "(empty)" end
    local result = {}
    for i = 1, #list do result[i] = tostring(list[i]) end
    return table.concat(result, ",")
end

local function DumpStatus()
    if type(_G.GetBuildInfo) == "function" then
        local version, build, _, interface = _G.GetBuildInfo()
        Print(("client=%s build=%s interface=%s")
            :format(SafeString(version) or "unknown", SafeString(build) or "unknown",
                tostring(SafeNumber(interface) or "unknown")))
    end
    Print(("version=%s schema=%d enabled=%s combat=%s glow=%s detection=%s")
        :format(GetAddonVersion(), CURRENT_SCHEMA, tostring(DB.enabled), tostring(InCombat()), tostring(R.glowActive), tostring(R.lastDetection)))
    Print(("buttons=%d cdm=%d query=%d/%d authoritative=%s eventSignals=%d")
        :format(CountEntries(R.trackedButtons), CountEntries(R.cdmFrames), R.overlayQueryReadable,
            R.overlayQueryCandidates, tostring(R.overlayQueryAuthoritative), CountEntries(R.eventSignals)))
    Print("targets configured: " .. FormatIDList(DB.targetSpellIDs))
    Print("targets resolved: " .. FormatIDList(R.targetFamilyList))
    Print("signals resolved: " .. FormatIDList(R.signalFamilyList))
end

local function ToggleID(list, value, label)
    local id = SafeID(value)
    if not id then
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
    if not DB then SDG:OnLogin() end
    local command, argument = (message or ""):match("^(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if command == "" or command == "options" then
        if type(SDG.OpenSettings) == "function" then SDG:OpenSettings()
        else Print("Use /sdglow help for commands.") end
    elseif command == "help" then
        Print("/sdglow options | status | debug | rescan [deep] | test")
        Print("/sdglow spell <spellID> | signal <spellID> | spells | cdm on|off | on | off")
    elseif command == "status" or command == "dump" then
        DumpStatus()
    elseif command == "debug" then
        SDG:SetOption("debug", not DB.debug)
        Print("Debug: " .. (DB.debug and "ON" or "OFF"))
    elseif command == "rescan" then
        SDG:RequestRescan("slash", argument:lower() == "deep")
        Print(InCombat() and "Rescan deferred until combat ends" or "Rescan queued")
    elseif command == "test" then
        SDG:TestGlow()
    elseif command == "spell" then
        if not R.unsupportedSchema then ToggleID(DB.targetSpellIDs, argument, "spell") end
    elseif command == "signal" or command == "aura" then
        if not R.unsupportedSchema then ToggleID(DB.signalSpellIDs, argument, "signal") end
    elseif command == "spells" then
        Print("targets configured: " .. FormatIDList(DB.targetSpellIDs))
        Print("targets resolved: " .. FormatIDList(R.targetFamilyList))
        Print("signals resolved: " .. FormatIDList(R.signalFamilyList))
    elseif command == "cdm" then
        argument = argument:lower()
        if argument == "on" then SDG:SetOption("cdm", true)
        elseif argument == "off" then SDG:SetOption("cdm", false)
        else Print("Usage: /sdglow cdm on|off"); return end
        Print("Cooldown Viewer mirror: " .. (DB.cdm and "ON" or "OFF"))
    elseif command == "on" or command == "off" then
        SDG:SetOption("enabled", command == "on")
        Print(DB.enabled and "Enabled" or "Disabled")
    else
        Print("Unknown command. Use /sdglow help")
    end
end

-- Normal login waits until every TOC file has loaded. A late load initializes
-- through a one-shot callback, so Options.lua is available before registration.
if type(_G.IsLoggedIn) == "function" and _G.IsLoggedIn() then
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function() SDG:OnLogin() end)
    else
        SDG:OnLogin()
    end
end
