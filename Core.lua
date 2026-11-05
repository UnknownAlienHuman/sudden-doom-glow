-- Sudden Doom Glow
-- Retail 12.1.5: official Spell Activation Overlay state -> addon-owned glow surfaces.

local ADDON_NAME, SDG = ...
ADDON_NAME = type(ADDON_NAME) == "string" and ADDON_NAME or "SuddenDoomGlow"
if type(SDG) ~= "table" then SDG = {} end

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
local canaccesstable = _G.canaccesstable
local issecretvalue = _G.issecretvalue

local CURRENT_SCHEMA = 5
local MAX_CONFIGURED_SPELL_IDS = 32
local MAX_RESOLVED_SPELL_IDS = 128
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
    buttonSlots = NewWeakKeyTable(),
    buttonsBySlot = {},
    frameState = NewWeakKeyTable(),
    pendingHides = NewWeakKeyTable(),

    cdmFrames = NewWeakKeyTable(),
    cdmViewerHooks = NewWeakKeyTable(),
    cdmItemHooks = NewWeakKeyTable(),

    eventSignals = {},
    timers = {},
    overlayQueryReadable = 0,
    overlayQueryCandidates = 0,
    overlayQueryAuthoritative = false,
    queryHintSpellID = nil,

    glowActive = false,
    lastDetection = "none",
    testUntil = 0,
    needsGeometry = false,
    geometryToken = {},
    unsupportedSchema = false,

    needsRescan = false,
    rescanDeep = false,
    rescanReason = nil,
    pendingActionSlots = {},
    actionRefreshAll = false,

    actionCallbackAttached = false,
    actionCallbackOwner = {},
    appliedOptions = {},
}
SDG.runtime = R

local DB
local frame = CreateFrame("Frame")
local RECOVERY_EVENTS = {
    PLAYER_REGEN_ENABLED = true,
    PLAYER_ENTERING_WORLD = true,
    SPELL_SECRECY_CHANGED = true,
}

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Now()
    return GetTime and GetTime() or 0
end

-- Gate values before nil checks, comparison, conversion, formatting or logging.
-- pcall remains an error boundary; it never grants access or declassifies data.
local function IsAccessible(value)
    if type(canaccessvalue) == "function" then
        local ok, accessible = pcall(canaccessvalue, value)
        return ok and accessible and true or false
    end
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and not secret
    end
    return true
end

local function IsReadableTable(value)
    if not IsAccessible(value) or type(value) ~= "table" then return false end
    if type(canaccesstable) == "function" then
        local ok, readable = pcall(canaccesstable, value)
        return ok and IsAccessible(readable) and readable and true or false
    end
    return true
end

local function ReadIndex(container, key)
    return container[key]
end

local function WriteIndex(container, key, value)
    container[key] = value
end

-- Foreign script objects and tables can become inaccessible after discovery.
-- Every member lookup is therefore an access-gated operation, not a harmless
-- prelude to a protected call. `known=false` includes denied and throwing reads.
local function ReadMember(container, key)
    if not IsAccessible(container) then return nil, false end
    if container == nil then return nil, false end
    if type(container) == "table" and not IsReadableTable(container) then
        return nil, false
    end
    local ok, value = pcall(ReadIndex, container, key)
    if not ok or not IsAccessible(value) then return nil, false end
    return value, true
end

local function CallMethod(container, methodName, ...)
    local method, known = ReadMember(container, methodName)
    if not known or type(method) ~= "function" then return false end
    return pcall(method, container, ...)
end

local function WriteMember(container, key, value)
    if not IsAccessible(container) or container == nil then return false end
    if not IsAccessible(value) then return false end
    if type(container) == "table" and not IsReadableTable(container) then return false end
    return pcall(WriteIndex, container, key, value)
end

local function ReadOptionalBooleanMethod(container, methodName)
    local method, known = ReadMember(container, methodName)
    if not known then return nil, false end
    if method == nil then return nil, true end
    if type(method) ~= "function" then return nil, false end

    local ok, value = pcall(method, container)
    if not ok or not IsAccessible(value) or type(value) ~= "boolean" then
        return nil, false
    end
    return value, true
end

local FrameCanBeUsed

local function SafeMessage(value)
    if not IsAccessible(value) then return nil end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
    return tostring(value)
end

local function Print(message)
    local text = SafeMessage(message)
    if not text or not FrameCanBeUsed then return end

    local chatFrame, frameKnown = ReadMember(_G, "DEFAULT_CHAT_FRAME")
    if not frameKnown or not FrameCanBeUsed(chatFrame) then return end
    local addMessage, methodKnown = ReadMember(chatFrame, "AddMessage")
    if methodKnown and type(addMessage) == "function" then
        pcall(addMessage, chatFrame, "|cff66ccffSuddenDoomGlow|r: " .. text)
    end
end

function SDG:Print(message)
    Print(message)
end

local function Log(message)
    if not DB or not DB.debug then return end
    local text = SafeMessage(message)
    if not text then return end
    if type(SDG.LogDebug) == "function" then
        SDG:LogDebug(text)
    else
        Print(text)
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

local function ParseActionSlotEvent(value)
    -- ACTIONBAR_SLOT_CHANGED uses zero as an explicit broad invalidation. A
    -- denied or malformed payload is not permission to reinterpret the event
    -- as that broad case.
    if not IsAccessible(value) or type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
        return nil, false
    end
    if value == 0 then return nil, true end
    local slot = SafeID(value)
    return slot, slot ~= nil
end

local function SafeString(value)
    if IsAccessible(value) and type(value) == "string" then return value end
    return nil
end

FrameCanBeUsed = function(frame)
    if not IsAccessible(frame) or not frame then return false end
    local kind = type(frame)
    if kind ~= "table" and kind ~= "userdata" then return false end
    -- Current-context access is the first object gate. It is not cached across
    -- callbacks, combat, restriction transitions or deferred work.
    local accessible, accessKnown = ReadOptionalBooleanMethod(frame, "CanBeAccessedInContext")
    if not accessKnown or accessible == false then return false end

    local constrained, constraintsKnown = ReadOptionalBooleanMethod(frame, "HasAccessConstraints")
    if not constraintsKnown or (constrained == true and accessible ~= true) then return false end

    local forbidden, forbiddenKnown = ReadOptionalBooleanMethod(frame, "IsForbidden")
    if not forbiddenKnown or forbidden == true then return false end
    return true
end

local function RuntimeEnabled()
    return DB and DB.enabled and R.class == "DEATHKNIGHT" and not R.unsupportedSchema
end

local function UpdateRecoveryEvents()
    if R.runtimeRegistered then return end
    for event in pairs(RECOVERY_EVENTS) do
        if next(R.pendingHides) then frame:RegisterEvent(event)
        else frame:UnregisterEvent(event) end
    end
end

local function CancelTimer(key)
    local timer = R.timers[key]
    R.timers[key] = nil
    if timer and timer.handle then CallMethod(timer.handle, "Cancel") end
end

local function CancelTimers()
    for key in pairs(R.timers) do CancelTimer(key) end
end

local function ClearQueryObservation()
    R.lastQueryActiveAt, R.lastQuerySpellID, R.queryHintSpellID = nil, nil, nil
    CancelTimer("query-expire")
end

local function ScheduleTimer(key, delay, callback)
    CancelTimer(key)
    if not RuntimeEnabled() then return false end
    local timer = {}
    R.timers[key] = timer
    local function Run()
        if R.timers[key] ~= timer then return end
        R.timers[key] = nil
        if RuntimeEnabled() then callback() end
    end

    if C_Timer and type(C_Timer.NewTimer) == "function" then
        local ok, handle = pcall(C_Timer.NewTimer, delay, Run)
        if ok then
            -- A successful call owns scheduled work even when the callback object
            -- itself is nil or inaccessible. Identity gating still cancels it.
            if R.timers[key] == timer and IsAccessible(handle) and handle then
                timer.handle = handle
            end
            return true
        end
    end

    if C_Timer and type(C_Timer.After) == "function" then
        -- Compatibility fallback has no handle; stale callbacks are harmless
        -- because only the current ordinary owner token may run.
        local ok = pcall(C_Timer.After, delay, Run)
        if ok then return true end
    end

    if R.timers[key] == timer then R.timers[key] = nil end
    return false
end

local function GetAddonVersion()
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local ok, version = pcall(C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
        if ok then return SafeString(version) or "unknown" end
    end
    return "unknown"
end

local function IsAddOnFullyLoaded(addonName)
    if not (C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function") then
        return false
    end
    local ok, _loadedOrLoading, loaded = pcall(C_AddOns.IsAddOnLoaded, addonName)
    return ok and IsAccessible(loaded) and type(loaded) == "boolean" and loaded == true
end

local function CopyNumericList(source)
    local result = {}
    local seen = {}
    if type(source) ~= "table" then return result end

    for i = 1, #source do
        if #result >= MAX_CONFIGURED_SPELL_IDS then break end
        local id = SafeID(source[i])
        if id and not seen[id] then
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
        if #result >= MAX_CONFIGURED_SPELL_IDS then break end
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

local function AddUniqueID(set, list, value, limit)
    local id = SafeID(value)
    if not id or set[id] then return false end
    if limit and #list >= limit then return false end
    set[id] = true
    list[#list + 1] = id
    return true
end

local function AddTargetFamilyChain(spellID, depth)
    depth = depth or 0
    if depth > 8 then return end

    spellID = SafeID(spellID)
    if not spellID then return end

    if not AddUniqueID(R.targetFamily, R.targetFamilyList, spellID, MAX_RESOLVED_SPELL_IDS) then return end
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

    for i = 1, math.min(#DB.targetSpellIDs, MAX_CONFIGURED_SPELL_IDS) do
        local configuredID = SafeID(DB.targetSpellIDs[i])
        if configuredID then
            local baseID = GetBaseSpellID(configuredID) or configuredID
            AddUniqueID(R.targetRoots, R.targetRootList, baseID, MAX_CONFIGURED_SPELL_IDS)
            AddTargetFamilyChain(configuredID, 0)
            AddTargetFamilyChain(baseID, 0)
        end
    end

    for baseID, overrideID in pairs(R.explicitOverrides) do
        if R.targetRoots[baseID] or R.targetFamily[baseID] then
            AddTargetFamilyChain(overrideID, 0)
        end
    end

    -- Explicit signal configuration is authoritative and must not be displaced
    -- by a large replacement family. Target variants use only the remaining budget.
    for i = 1, math.min(#DB.signalSpellIDs, MAX_CONFIGURED_SPELL_IDS) do
        AddUniqueID(R.signalFamily, R.signalFamilyList, DB.signalSpellIDs[i], MAX_RESOLVED_SPELL_IDS)
    end
    for i = 1, #R.targetFamilyList do
        AddUniqueID(R.signalFamily, R.signalFamilyList, R.targetFamilyList[i], MAX_RESOLVED_SPELL_IDS)
    end
    if R.lastQuerySpellID and not R.signalFamily[R.lastQuerySpellID] then
        ClearQueryObservation()
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
            AddUniqueID(R.signalFamily, R.signalFamilyList, spellID, MAX_RESOLVED_SPELL_IDS)
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
                AddUniqueID(R.signalFamily, R.signalFamilyList, spellID, MAX_RESOLVED_SPELL_IDS)
            end
            return true
        end
    end

    return false
end

local function LearnExplicitOverride(baseSpellID, overrideSpellID, source)
    if not IsAccessible(baseSpellID) or not IsAccessible(overrideSpellID) then return false, false end
    baseSpellID = SafeID(baseSpellID)
    overrideSpellID = SafeID(overrideSpellID)
    if not baseSpellID then return false, false end

    local normalizedBase = GetBaseSpellID(baseSpellID) or baseSpellID
    if not (R.targetRoots[normalizedBase] or R.targetFamily[normalizedBase] or R.targetFamily[baseSpellID]) then
        return false, false
    end

    if not overrideSpellID then
        if R.explicitOverrides[normalizedBase] then
            R.explicitOverrides[normalizedBase] = nil
            Log("Override removed for " .. tostring(normalizedBase) .. " (" .. tostring(source) .. ")")
            return true, true
        end
        return false, true
    end

    if R.explicitOverrides[normalizedBase] == overrideSpellID and R.targetFamily[overrideSpellID] then
        return false, true
    end

    R.explicitOverrides[normalizedBase] = overrideSpellID
    Log(("Override %d -> %d (%s)"):format(normalizedBase, overrideSpellID, tostring(source)))
    return true, true
end

local function IsRelevantSignal(spellID)
    spellID = SafeID(spellID)
    if not spellID then return false end
    if R.signalFamily[spellID] then return true end
    if IsTargetFamilySpell(spellID, true) then
        AddUniqueID(R.signalFamily, R.signalFamilyList, spellID, MAX_RESOLVED_SPELL_IDS)
        return R.signalFamily[spellID] == true
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
    local getPagedID, pagedKnown = ReadMember(button, "GetPagedID")
    if not pagedKnown then return nil end
    if getPagedID ~= nil then
        if type(getPagedID) ~= "function" then return nil end
        local ok, value = pcall(getPagedID, button)
        if not ok or not IsAccessible(value) then return nil end
        if value ~= nil then return SafeID(value) end
    end
    local getAction, actionMethodKnown = ReadMember(button, "GetAction")
    if not actionMethodKnown then return nil end
    if getAction ~= nil then
        if type(getAction) ~= "function" then return nil end
        local ok, actionType, value = pcall(getAction, button)
        if not ok or not IsAccessible(actionType) or not IsAccessible(value) then return nil end
        if type(actionType) == "number" then return SafeID(actionType) end
        if actionType ~= nil then
            return actionType == "action" and SafeID(value) or nil
        end
    end
    local action, actionKnown = ReadMember(button, "action")
    if not actionKnown then return nil end
    if action ~= nil then return SafeID(action) end
    local stateAction, stateActionKnown = ReadMember(button, "_state_action")
    if not stateActionKnown then return nil end
    if stateAction ~= nil then return SafeID(stateAction) end
    local getAttribute, attributeKnown = ReadMember(button, "GetAttribute")
    if not attributeKnown then return nil end
    if getAttribute ~= nil then
        if type(getAttribute) ~= "function" then return nil end
        local ok, value = pcall(getAttribute, button, "action")
        if ok then return SafeID(value) end
    end
    return nil
end

local function SetButtonSlotIndex(button, slot)
    local oldSlot = R.buttonSlots[button]
    if oldSlot == slot then return end

    if oldSlot then
        local oldSet = R.buttonsBySlot[oldSlot]
        if oldSet then
            oldSet[button] = nil
            if not next(oldSet) then R.buttonsBySlot[oldSlot] = nil end
        end
    end

    R.buttonSlots[button] = slot
    if slot then
        local slotSet = R.buttonsBySlot[slot]
        if not slotSet then
            slotSet = NewWeakKeyTable()
            R.buttonsBySlot[slot] = slotSet
        end
        slotSet[button] = true
    end
end

local function ClearButtonSlotIndex()
    ClearMap(R.buttonSlots)
    ClearMap(R.buttonsBySlot)
end

local function IsCurrentTargetButton(button)
    local slot = GetButtonSlot(button)
    return slot and SlotMatchesTarget(slot) or false
end

local function GetRenderTarget(frame)
    if not FrameCanBeUsed(frame) then return nil end
    local iconFrame, iconKnown = ReadMember(frame, "Icon")
    if not iconKnown then return nil end
    if iconFrame ~= nil then
        -- An assigned but currently inaccessible render target is incomplete
        -- evidence. Never silently reparent the alert to the button instead.
        if not FrameCanBeUsed(iconFrame) then return nil end
        local getObjectType, objectTypeKnown = ReadMember(iconFrame, "GetObjectType")
        if not objectTypeKnown then return nil end
        if getObjectType == nil then return frame end
        if type(getObjectType) ~= "function" then return nil end
        local ok, objectType = pcall(getObjectType, iconFrame)
        if not ok or not IsAccessible(objectType) then return nil end
        if SafeString(objectType) == "Frame" then return iconFrame end
    end
    return frame
end

local function GetFrameState(frame)
    local state = R.frameState[frame]
    if not state then
        state = {
            alert = nil,
            shown = false,
            animating = false,
            geometryReady = false,
            geometryToken = nil,
            renderTarget = nil,
            sizeHookTargets = nil,
            isCDM = false,
        }
        R.frameState[frame] = state
    end
    return state
end

local function MarkGeometryDirty(state)
    state.geometryReady = false
    R.needsGeometry = true
    return false
end

local function RefreshAlertGeometry(frame, state, resolvedTarget)
    if InCombat() then return MarkGeometryDirty(state) end
    if not FrameCanBeUsed(state.alert) then return MarkGeometryDirty(state) end

    local target = resolvedTarget or GetRenderTarget(frame)
    if not FrameCanBeUsed(target) then return MarkGeometryDirty(state) end

    if state.renderTarget ~= target and not CallMethod(state.alert, "SetParent", target) then
        return MarkGeometryDirty(state)
    end

    local width, height = 0, 0
    local getSize, sizeKnown = ReadMember(target, "GetSize")
    if not sizeKnown then return MarkGeometryDirty(state) end
    if getSize ~= nil then
        if type(getSize) ~= "function" then return MarkGeometryDirty(state) end
        local ok, w, h = pcall(getSize, target)
        if not ok or not IsAccessible(w) or not IsAccessible(h) then
            return MarkGeometryDirty(state)
        end
        width = SafeNumber(w) or 0
        height = SafeNumber(h) or 0
    end

    if not CallMethod(state.alert, "ClearAllPoints") then return MarkGeometryDirty(state) end
    if width > 0 and height > 0 then
        if not CallMethod(state.alert, "SetSize", width * DB.glowScale, height * DB.glowScale) then
            return MarkGeometryDirty(state)
        end
        if not CallMethod(state.alert, "SetPoint", "CENTER", target, "CENTER", 0, 0) then
            return MarkGeometryDirty(state)
        end
    elseif not CallMethod(state.alert, "SetAllPoints", target) then
        return MarkGeometryDirty(state)
    end

    local getFrameLevel, levelKnown = ReadMember(target, "GetFrameLevel")
    if not levelKnown or type(getFrameLevel) ~= "function" then
        return MarkGeometryDirty(state)
    end
    local levelOK, level = pcall(getFrameLevel, target)
    level = levelOK and SafeNumber(level) or nil
    if not level or not CallMethod(state.alert, "SetFrameLevel", level + 20) then
        return MarkGeometryDirty(state)
    end

    local hookScript, hookKnown = ReadMember(target, "HookScript")
    if not hookKnown or type(hookScript) ~= "function" then
        return MarkGeometryDirty(state)
    end
    local hookedTargets = state.sizeHookTargets
    if not hookedTargets then
        hookedTargets = NewWeakKeyTable()
        state.sizeHookTargets = hookedTargets
    end
    if not hookedTargets[target] then
        local hooked = pcall(hookScript, target, "OnSizeChanged", function()
            -- Hooks cannot be removed. Once the frame adopts another render
            -- target, an old target no longer owns geometry invalidation.
            if state.renderTarget ~= target then return end
            state.geometryReady = false
            if not RuntimeEnabled() then
                R.needsGeometry = true
                return
            end
            -- A successful synchronous refresh owns this size change. Keep the
            -- global recovery flag for actual failures or other dirty surfaces.
            RefreshAlertGeometry(frame, state)
        end)
        if not hooked then return MarkGeometryDirty(state) end
        hookedTargets[target] = true
    end

    state.renderTarget = target
    state.geometryReady = true
    state.geometryToken = R.geometryToken
    return true
end

local function EnsureAlert(frame)
    if not FrameCanBeUsed(frame) then return nil end
    local state = GetFrameState(frame)
    if state.alert then
        if not FrameCanBeUsed(state.alert) then
            MarkGeometryDirty(state)
            return nil
        end
        local target = GetRenderTarget(frame)
        if not target then
            MarkGeometryDirty(state)
            return nil
        end
        if state.geometryToken ~= R.geometryToken then MarkGeometryDirty(state) end
        if state.renderTarget ~= target then MarkGeometryDirty(state) end
        if not state.geometryReady and not RefreshAlertGeometry(frame, state, target) then return nil end
        return state.alert
    end
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
    state.animating = false
    state.geometryReady = false
    CallMethod(alert, "Hide")
    local geometryReady = RefreshAlertGeometry(frame, state, target)
    return geometryReady and alert or nil
end

local function StopAnimation(animation)
    if not FrameCanBeUsed(animation) then return false end
    return CallMethod(animation, "Stop")
end

local function PlayAnimation(animation)
    if not FrameCanBeUsed(animation) then return false end
    return CallMethod(animation, "Play")
end

local function DeferHide(state)
    R.pendingHides[state] = true
    UpdateRecoveryEvents()
end

local function HideAlert(state)
    state.animating = false
    if not state.alert or not state.shown then
        R.pendingHides[state] = nil
        return
    end
    local alert = state.alert
    if not FrameCanBeUsed(alert) then DeferHide(state); return end

    WriteMember(alert, "animationPlaying", false)
    local startAnimation, startKnown = ReadMember(alert, "ProcStartAnim")
    local loopAnimation, loopKnown = ReadMember(alert, "ProcLoop")
    if startKnown then StopAnimation(startAnimation) end
    if loopKnown then StopAnimation(loopAnimation) end
    if CallMethod(alert, "Hide") then
        state.shown = false
        R.pendingHides[state] = nil
    else
        DeferHide(state)
    end
end

local function HideFrameGlow(frame)
    -- Only the ordinary identity is needed to find our own presentation. An
    -- inaccessible parent must not prevent hiding an accessible addon child.
    if not IsAccessible(frame) or not frame then return end
    local state = R.frameState[frame]
    if state then HideAlert(state) end
end

local function FlushPendingHides()
    -- Recheck only at an authoritative context transition. No polling, borrowed
    -- callback payload or cached permission is retained by this cleanup owner.
    for state in pairs(R.pendingHides) do HideAlert(state) end
    UpdateRecoveryEvents()
end

local function ShowFrameGlow(frame, assignmentValidated)
    if not FrameCanBeUsed(frame) then HideFrameGlow(frame); return end
    local state = GetFrameState(frame)
    if not state.isCDM and not assignmentValidated then
        local current = IsCurrentTargetButton(frame)
        if not current then
            HideFrameGlow(frame)
            return
        end
    end

    if state.isCDM and not state.assignmentReadable then return end
    if state.shown and state.animating and not R.pendingHides[state] then
        local alertReady = FrameCanBeUsed(state.alert)
        local startAnimation, startKnown = ReadMember(state.alert, "ProcStartAnim")
        local loopAnimation, loopKnown = ReadMember(state.alert, "ProcLoop")
        if alertReady and startKnown and loopKnown and
           FrameCanBeUsed(startAnimation) and FrameCanBeUsed(loopAnimation) then
            return
        end
        -- Current permission is not cached. A denied destination keeps the
        -- desired ON state, but must be retried only at an explicit wake-up.
        state.animating = false
    end
    local alert = EnsureAlert(frame)
    if not alert then return end

    local wasShown = state.shown
    if not wasShown and not CallMethod(alert, "Show") then return end

    local startAnimation, startKnown = ReadMember(alert, "ProcStartAnim")
    local loopAnimation, loopKnown = ReadMember(alert, "ProcLoop")
    if not startKnown or not loopKnown then
        state.shown = true
        state.animating = false
        WriteMember(alert, "animationPlaying", false)
        return
    end

    local played
    if wasShown then
        played = PlayAnimation(loopAnimation) or PlayAnimation(startAnimation)
    else
        StopAnimation(loopAnimation)
        played = PlayAnimation(startAnimation) or PlayAnimation(loopAnimation)
    end

    state.shown = true
    state.animating = played and true or false
    WriteMember(alert, "animationPlaying", state.animating)
    R.pendingHides[state] = nil
end

local function RefreshButton(button, slot, matchesTarget)
    if not IsAccessible(button) or not button then return end
    SetButtonSlotIndex(button, slot)
    if slot and matchesTarget == nil then matchesTarget = SlotMatchesTarget(slot) end
    if slot and matchesTarget then
        R.trackedButtons[button] = true
        EnsureAlert(button)
        if R.glowActive then ShowFrameGlow(button, true) else HideFrameGlow(button) end
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
    { "BT4Button", 180, true, "Bartender4" },
    { "DominosActionButton", 180, true, "Dominos" },
    -- Current Dominos reuses these Blizzard-style compatibility names for
    -- bars whose IDs are outside its own ActionButton name ranges.
    { "MultiBarRightActionButton", 12, true, "Dominos" },
    { "MultiBarLeftActionButton", 12, true, "Dominos" },
    { "MultiBarBottomRightActionButton", 12, true, "Dominos" },
    { "MultiBarBottomLeftActionButton", 12, true, "Dominos" },
    { "MultiBar5ActionButton", 12, true, "Dominos" },
    { "MultiBar6ActionButton", 12, true, "Dominos" },
    { "MultiBar7ActionButton", 12, true, "Dominos" },
}

local function MapNamedButtons()
    for setIndex = 1, #NAMED_BUTTON_SETS do
        local prefix = NAMED_BUTTON_SETS[setIndex][1]
        local count = NAMED_BUTTON_SETS[setIndex][2]
        local provider = NAMED_BUTTON_SETS[setIndex][4]
        if not provider or IsAddOnFullyLoaded(provider) then
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
    end

    if IsAddOnFullyLoaded("ElvUI") then
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
end

local function DeepMapButtons(maxFrames)
    if type(EnumerateFrames) ~= "function" then return end
    local count = 0
    local ok, current = pcall(EnumerateFrames)
    if not ok or not IsAccessible(current) then return end
    while current do
        count = count + 1
        if count > maxFrames then break end
        if FrameCanBeUsed(current) then
            local getObjectType, objectTypeKnown = ReadMember(current, "GetObjectType")
            local objectOK, objectType = false, nil
            if objectTypeKnown and type(getObjectType) == "function" then
                objectOK, objectType = pcall(getObjectType, current)
            end
            objectType = objectOK and SafeString(objectType) or nil
            if objectOK and (objectType == "Button" or objectType == "CheckButton") and
               IsCurrentTargetButton(current) then
                R.knownButtons[current] = true
            end
        end
        local nextOK, nextFrame = pcall(EnumerateFrames, current)
        if not nextOK or not IsAccessible(nextFrame) then break end
        current = nextFrame
    end
end

-- Narrow source-coupled adapter: ordinary configured identity only. GetSpellID
-- can prefer managed aura data in 12.1.5, so it is deliberately not queried here.
local function CDMFrameMatches(frame)
    if not FrameCanBeUsed(frame) then return nil end
    local getBaseSpellID, methodKnown = ReadMember(frame, "GetBaseSpellID")
    if not methodKnown or type(getBaseSpellID) ~= "function" then return nil end
    local ok, spellID = pcall(getBaseSpellID, frame)
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

local CDM_ITEM_HOOK_METHODS = {
    "SetCooldownID", "SetOverrideSpell", "ClearCooldownID", "ResetCooldownData",
}

local function CDMItemHooksComplete(frame)
    local hooked = R.cdmItemHooks[frame]
    if not hooked then return false end
    for i = 1, #CDM_ITEM_HOOK_METHODS do
        if hooked[CDM_ITEM_HOOK_METHODS[i]] ~= true then return false end
    end
    return true
end

local function RefreshCDMFrame(frame)
    if not RuntimeEnabled() or not DB.cdm then return end
    if not IsAccessible(frame) or not frame then return end
    if not CDMItemHooksComplete(frame) then
        local state = R.frameState[frame]
        if state then state.assignmentReadable = false end
        HideFrameGlow(frame)
        return
    end
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

local function SuspendCDMFrame(frame)
    local state = R.frameState[frame]
    if state then state.assignmentReadable = false end
    HideFrameGlow(frame)
    R.needsRescan = true
end

local function HookCDMItem(frame)
    if not IsAccessible(frame) or not frame then return false end
    if InCombat() then
        SuspendCDMFrame(frame)
        return false
    end
    if not FrameCanBeUsed(frame) or type(hooksecurefunc) ~= "function" then
        SuspendCDMFrame(frame)
        return false
    end
    local hooked = R.cdmItemHooks[frame]
    if not hooked then hooked = {}; R.cdmItemHooks[frame] = hooked end
    for i = 1, #CDM_ITEM_HOOK_METHODS do
        local name = CDM_ITEM_HOOK_METHODS[i]
        local method, methodKnown = ReadMember(frame, name)
        if not methodKnown or type(method) ~= "function" then
            SuspendCDMFrame(frame)
            return false
        end
        if not hooked[name] then
            local clear = name == "ClearCooldownID" or name == "ResetCooldownData"
            local ok = pcall(hooksecurefunc, frame, name, function(item)
                if not RuntimeEnabled() or not DB.cdm then return end
                if clear then ClearCDMFrame(item) else RefreshCDMFrame(item) end
            end)
            if not ok then
                SuspendCDMFrame(frame)
                return false
            end
            hooked[name] = true
        end
    end
    return true
end

local CDM_VIEWER_NAMES = {
    "EssentialCooldownViewer", "UtilityCooldownViewer",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
}

local function EnumerateCDMViewer(viewer, seen)
    if not FrameCanBeUsed(viewer) then return false end
    local pool, poolKnown = ReadMember(viewer, "itemFramePool")
    if not poolKnown or not IsReadableTable(pool) then return false end
    local enumerateActive, enumerateKnown = ReadMember(pool, "EnumerateActive")
    if not enumerateKnown or type(enumerateActive) ~= "function" then return false end
    local complete = true
    local ok = pcall(function()
        for item in enumerateActive(pool) do
            if not IsAccessible(item) then error("Unavailable viewer item") end
            if item then
                seen[item] = true
                if HookCDMItem(item) then
                    RefreshCDMFrame(item)
                else
                    complete = false
                end
            end
        end
    end)
    return ok and complete
end

local function ReconcileCDMFrames()
    if not RuntimeEnabled() or not DB.cdm then
        for item in pairs(R.cdmFrames) do ClearCDMFrame(item) end
        return
    end
    if InCombat() then
        -- Reuse only already observed instances in combat. Pool enumeration, new
        -- post-hooks and alert construction are deferred to one post-combat rescan.
        R.needsRescan = true
        for item in pairs(R.cdmItemHooks) do RefreshCDMFrame(item) end
        return
    end
    if not IsAddOnFullyLoaded("Blizzard_CooldownViewer") then return end

    local seen = NewWeakKeyTable()
    local allReadable, foundViewer = true, false
    for i = 1, #CDM_VIEWER_NAMES do
        local viewer = _G[CDM_VIEWER_NAMES[i]]
        if not IsAccessible(viewer) then
            allReadable = false
        elseif not viewer then
            -- The selected client defines all four viewers together. A missing
            -- configured surface is incomplete evidence and cannot authorize pruning.
            allReadable = false
        else
            foundViewer = true
            if not FrameCanBeUsed(viewer) then
                allReadable = false
            else
                local acquireMethod, acquireKnown = ReadMember(viewer, "OnAcquireItemFrame")
                if not acquireKnown then
                    allReadable = false
                elseif not R.cdmViewerHooks[viewer] then
                    if type(hooksecurefunc) ~= "function" or type(acquireMethod) ~= "function" then
                        allReadable = false
                        R.needsRescan = true
                    else
                        -- Mixins are copied into frames. Hook the actual instance,
                        -- including instances created before this addon was loaded.
                        local hooked = pcall(hooksecurefunc, viewer, "OnAcquireItemFrame", function(_, item)
                            if not RuntimeEnabled() or not DB.cdm or not IsAccessible(item) or not item then return end
                            if InCombat() then
                                SuspendCDMFrame(item)
                                return
                            end
                            if not FrameCanBeUsed(item) then
                                SuspendCDMFrame(item)
                                return
                            end
                            if HookCDMItem(item) then RefreshCDMFrame(item) end
                        end)
                        if hooked then
                            R.cdmViewerHooks[viewer] = true
                        else
                            allReadable = false
                            R.needsRescan = true
                        end
                    end
                end
                if not EnumerateCDMViewer(viewer, seen) then allReadable = false end
            end
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
    local preferred = SafeID(R.queryHintSpellID)
    if not preferred or not R.signalFamily[preferred] then
        preferred = SafeID(R.lastQuerySpellID)
        if preferred and not R.signalFamily[preferred] then preferred = nil end
    end

    local function QueryCandidate(spellID)
        local ok, overlayed = pcall(C_SpellActivationOverlay.IsSpellOverlayed, spellID)
        if not ok or not IsAccessible(overlayed) or type(overlayed) ~= "boolean" then
            return false, false
        end
        readable = readable + 1
        return overlayed, true
    end

    if preferred then
        local overlayed = QueryCandidate(preferred)
        if overlayed then
            R.overlayQueryReadable = readable
            R.overlayQueryCandidates = candidates
            R.overlayQueryAuthoritative = true
            R.queryHintSpellID = preferred
            return true, true, preferred
        end
    end

    for i = 1, candidates do
        local spellID = R.signalFamilyList[i]
        if spellID ~= preferred then
            local overlayed = QueryCandidate(spellID)
            if overlayed then
                R.overlayQueryReadable = readable
                R.overlayQueryCandidates = candidates
                R.overlayQueryAuthoritative = true
                R.queryHintSpellID = spellID
                return true, true, spellID
            end
        end
    end

    R.overlayQueryReadable = readable
    R.overlayQueryCandidates = candidates
    R.overlayQueryAuthoritative = candidates > 0 and readable == candidates
    R.queryHintSpellID = nil
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
    local queryActive, queryAuthoritative, querySpellID = QueryOverlayState()
    local eventActive, newest = HasEventSignal()
    local withinShowGrace = eventActive and now - newest <= OVERLAY_SHOW_GRACE
    if queryActive then
        R.lastQueryActiveAt, R.lastQuerySpellID = now, querySpellID
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
            local scheduled = ScheduleTimer("query-expire", EVENT_FALLBACK_TTL - (now - R.lastQueryActiveAt), function()
                ClearQueryObservation()
                ReconcileGlow("query-ttl")
            end)
            if not scheduled then
                -- A positive observation without a terminal owner cannot be kept.
                ClearQueryObservation()
                R.lastDetection = "no-readable-signal"
                SetGlow(false)
            end
        end
    else
        if queryAuthoritative then ClearEventSignals() end
        ClearQueryObservation()
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
    if not ScheduleTimer("reconcile", delay, function() ReconcileGlow(reason) end) then
        ReconcileGlow(reason)
    end
end

local function SetEventSignal(spellID)
    R.eventSignals[spellID] = Now()
    local expires = ScheduleTimer("signal-expire:" .. spellID, EVENT_FALLBACK_TTL, function()
        ClearEventSignal(spellID)
        ReconcileGlow("event-ttl")
    end)
    local reconciles = expires and ScheduleTimer("signal-grace:" .. spellID, OVERLAY_SHOW_GRACE + 0.01, function()
        if R.eventSignals[spellID] then ReconcileGlow("show-grace-expired") end
    end)
    if not expires or not reconciles then
        -- Event-only evidence is valid only with both bounded terminal owners.
        ClearEventSignal(spellID)
        return false
    end
    return true
end

local function HandleOverlayShow(spellID)
    spellID = SafeID(spellID)
    if not spellID then
        -- The payload cannot be inspected, but the ordinary event occurrence may
        -- still wake a query over our configured ordinary candidates.
        if not R.glowActive then QueueReconcile("overlay-show-opaque", OVERLAY_RECONCILE_DELAY) end
        return
    end

    if IsRelevantSignal(spellID) then
        R.queryHintSpellID = spellID
        SetEventSignal(spellID)
        ReconcileGlow("overlay-show")
        if R.lastDetection ~= "overlay-query" then
            QueueReconcile("overlay-show-delayed", OVERLAY_RECONCILE_DELAY)
        end
    elseif not R.glowActive then
        -- An unrelated overlay event is only a wake-up signal. This catches a
        -- newly hotfixed proc payload once the official query reports one of our
        -- known action/replacement spells, without treating every overlay as Sudden Doom.
        QueueReconcile("overlay-wakeup", OVERLAY_RECONCILE_DELAY)
    end
end

local function HandleOverlayHide(spellID)
    spellID = SafeID(spellID)
    if not spellID then
        if R.glowActive then QueueReconcile("overlay-hide-opaque", OVERLAY_RECONCILE_DELAY) end
        return
    end

    if IsRelevantSignal(spellID) then
        if R.queryHintSpellID == spellID then R.queryHintSpellID = nil end
        ClearEventSignal(spellID)
        ReconcileGlow("overlay-hide")
        if R.glowActive or not R.overlayQueryAuthoritative then
            QueueReconcile("overlay-hide-delayed", OVERLAY_RECONCILE_DELAY)
        end
    elseif R.glowActive then
        QueueReconcile("overlay-hide-delayed", OVERLAY_RECONCILE_DELAY)
    end
end

local function PrimeTrackedAlerts(forceGeometry)
    if forceGeometry then R.geometryToken = {} end
    if InCombat() then R.needsGeometry = true; return end
    local complete = true

    local function PrimeFrame(frame, required)
        local state = R.frameState[frame]
        if required or (state and state.alert) then
            if not EnsureAlert(frame) then complete = false end
        end
    end

    for button in pairs(R.knownButtons) do
        if IsAccessible(button) then
            PrimeFrame(button, R.trackedButtons[button] == true)
        else
            complete = false
        end
    end
    for item in pairs(R.cdmFrames) do
        if IsAccessible(item) then PrimeFrame(item, true) else complete = false end
    end
    R.needsGeometry = not complete
end

local function RefreshKnownButtons(changedSlot)
    if not RuntimeEnabled() then return end
    local matchesBySlot = {}
    local function RefreshCurrentButton(button)
        local slot = GetButtonSlot(button)
        local matchesTarget
        if slot then
            matchesTarget = matchesBySlot[slot]
            if matchesTarget == nil then
                matchesTarget = SlotMatchesTarget(slot) and true or false
                matchesBySlot[slot] = matchesTarget
            end
        end
        RefreshButton(button, slot, matchesTarget)
    end
    if changedSlot then
        local slotSet = R.buttonsBySlot[changedSlot]
        if not slotSet or not next(slotSet) then
            R.buttonsBySlot[changedSlot] = nil
            return
        end
        for button in pairs(slotSet) do
            RefreshCurrentButton(button)
        end
        return
    end

    for button in pairs(R.knownButtons) do
        RefreshCurrentButton(button)
    end
end

local function ClearPendingActionRefresh()
    CancelTimer("action-refresh")
    R.actionRefreshAll = false
    ClearMap(R.pendingActionSlots)
end

local function FlushPendingActionRefresh()
    if R.actionRefreshAll then
        R.actionRefreshAll = false
        ClearMap(R.pendingActionSlots)
        RefreshKnownButtons()
        return
    end
    local pendingSlots = R.pendingActionSlots
    R.pendingActionSlots = {}
    for slot in pairs(pendingSlots) do RefreshKnownButtons(slot) end
end

local function QueueActionRefresh(changedSlot)
    -- A complete settled rescan already owns assignment reconciliation. Do not
    -- retain a second full pass that will run immediately before it.
    if not InCombat() and R.timers.rescan then return end
    if changedSlot then
        R.pendingActionSlots[changedSlot] = true
    else
        R.actionRefreshAll = true
        ClearMap(R.pendingActionSlots)
    end
    if R.timers["action-refresh"] then return end
    if not ScheduleTimer("action-refresh", 0, FlushPendingActionRefresh) then
        FlushPendingActionRefresh()
    end
end

local function RefreshAssignments()
    if not RuntimeEnabled() then return end
    RefreshKnownButtons()
    if DB.cdm then
        -- Reuse observed instances; released items have no base spell after
        -- ResetCooldownData. This also finds newly configured targets without
        -- enumerating viewer pools or creating missing alerts during combat.
        for item in pairs(R.cdmItemHooks) do RefreshCDMFrame(item) end
    end
end

function SDG:RescanButtons(deep)
    if not RuntimeEnabled() then return end
    if InCombat() then
        R.needsRescan = true
        R.rescanDeep = R.rescanDeep or deep
        return
    end
    ClearPendingActionRefresh()
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

local function CompleteRescanRequest(owner, fallbackReason)
    local useDeep = R.rescanDeep
    R.rescanDeep = false
    local why = R.rescanReason
    R.rescanReason = nil
    owner:RescanButtons(useDeep)
    ReconcileGlow(why or fallbackReason or "rescan")
end

function SDG:RequestRescan(reason, deep)
    if not RuntimeEnabled() then return false end
    R.rescanReason = reason or R.rescanReason
    R.rescanDeep = R.rescanDeep or deep
    if InCombat() then
        R.needsRescan = true
        return true, "deferred"
    end
    ClearPendingActionRefresh()
    if R.timers.rescan then return true, "queued" end
    local scheduled = ScheduleTimer("rescan", RESCAN_DELAY, function()
        CompleteRescanRequest(self, "rescan")
    end)
    if scheduled then return true, "queued" end
    if not RuntimeEnabled() then
        R.rescanDeep = false
        R.rescanReason = nil
        return false
    end

    -- Required recovery must not disappear merely because a timer provider
    -- rejected construction. Perform one bounded synchronous pass instead.
    CompleteRescanRequest(self, reason)
    return true, "completed"
end

local function QueueMappingRecovery(reason, clearOverrides)
    if clearOverrides then ClearMap(R.explicitOverrides) end
    if InCombat() then
        -- Mapping identity may change during combat even though structural work
        -- cannot. Refresh already-observed assignments now and keep one complete
        -- recovery pass for combat exit.
        RebuildSpellFamilies()
        RefreshAssignments()
        ReconcileGlow(reason)
        R.needsRescan = true
        return
    end
    SDG:RequestRescan(reason, false)
end

local function AttachActionButtonCallback()
    if R.actionCallbackAttached or not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
    EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button)
        if not RuntimeEnabled() or not IsAccessible(button) or not button then return end
        R.knownButtons[button] = true
        if not FrameCanBeUsed(button) then
            SetButtonSlotIndex(button, nil)
            R.trackedButtons[button] = nil
            HideFrameGlow(button)
            return
        end
        RefreshButton(button, GetButtonSlot(button))
    end, R.actionCallbackOwner)
    R.actionCallbackAttached = true
end

local RUNTIME_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_OVERRIDE_ACTIONBAR",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "UPDATE_MACROS", "MODIFIER_STATE_CHANGED",
    "PLAYER_TALENT_UPDATE", "TRAIT_CONFIG_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
    "SPELLS_CHANGED", "SPELL_SECRECY_CHANGED", "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "COOLDOWN_VIEWER_DATA_LOADED", "COOLDOWN_VIEWER_TABLE_HOTFIXED", "ADDON_LOADED",
}

local RELEVANT_ADDONS = {
    Blizzard_CooldownViewer = true,
    Bartender4 = true,
    Dominos = true,
    ElvUI = true,
}

local function ResetTransientState(clearOverrides)
    CancelTimers()
    ClearMap(R.eventSignals)
    ClearQueryObservation()
    R.testUntil = 0
    R.needsRescan, R.rescanDeep = false, false
    R.rescanReason = nil
    ClearPendingActionRefresh()
    if clearOverrides then ClearMap(R.explicitOverrides) end
    SetGlow(false, true)
end

local function InvalidateObservedAssignments()
    ClearMap(R.trackedButtons)
    ClearButtonSlotIndex()
    for item in pairs(R.cdmFrames) do
        local state = R.frameState[item]
        if state then state.assignmentReadable = false end
        HideFrameGlow(item)
    end
end

local function ResetAndRecover(reason)
    ResetTransientState(true)
    -- World/spec/secrecy transitions invalidate borrowed assignment identity
    -- immediately. Keep discovered owners/hooks for recovery, but no stale
    -- button slot or pooled CDM assignment may render before revalidation.
    InvalidateObservedAssignments()
    RebuildSpellFamilies()
    if InCombat() then
        -- Structural discovery is blocked, but already observed ordinary
        -- assignments and proc state can be reconciled now. One full recovery
        -- pass remains owned by combat exit.
        RefreshAssignments()
        ReconcileGlow(reason)
        R.needsRescan = true
        return
    end
    if not SDG:RequestRescan(reason, false) then
        SDG:RescanButtons(false)
        ReconcileGlow(reason)
    end
end

local function StopRuntime()
    R.runtimeRegistered = false
    for i = 1, #RUNTIME_EVENTS do frame:UnregisterEvent(RUNTIME_EVENTS[i]) end
    if R.actionCallbackAttached and EventRegistry and type(EventRegistry.UnregisterCallback) == "function" then
        EventRegistry:UnregisterCallback("ActionButton.OnActionChanged", R.actionCallbackOwner)
        R.actionCallbackAttached = false
    end
    ResetTransientState(true)
    for item in pairs(R.cdmFrames) do ClearCDMFrame(item) end
    ClearMap(R.trackedButtons)
    ClearButtonSlotIndex()
    UpdateRecoveryEvents()
    R.lastDetection = "disabled"
end

local function StartRuntime()
    if not RuntimeEnabled() or R.runtimeRegistered then return end
    R.runtimeRegistered = true
    for i = 1, #RUNTIME_EVENTS do frame:RegisterEvent(RUNTIME_EVENTS[i]) end
    FlushPendingHides()
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

local function NormalizeOptionValue(key, value)
    if not IsAccessible(value) then return nil, false end
    if key == "glowScale" then
        value = SafeNumber(value)
        if not value then return nil, false end
        return math.max(1, math.min(1.8, value)), true
    end
    if key == "enabled" or key == "cdm" or key == "debug" then
        if type(value) ~= "boolean" then return nil, false end
        return value, true
    end
    return nil, false
end

local function ApplyOptionEffects(key, value)
    if R.appliedOptions[key] == value then return false end
    R.appliedOptions[key] = value

    if key == "enabled" then
        if value then StartRuntime() else StopRuntime() end
    elseif key == "cdm" then
        ReconcileCDMFrames()
    elseif key == "glowScale" then
        if RuntimeEnabled() then PrimeTrackedAlerts(true) end
    elseif key == "debug" and SDG.DebugUI then
        if value then SDG.DebugUI:Show() else SDG.DebugUI:Hide() end
    end
    return true
end

local function RememberAppliedOptions()
    R.appliedOptions.enabled = DB.enabled
    R.appliedOptions.cdm = DB.cdm
    R.appliedOptions.debug = DB.debug
    R.appliedOptions.glowScale = DB.glowScale
end

function SDG:GetOption(key)
    if key == "enabled" or key == "cdm" or key == "debug" or key == "glowScale" then
        return DB and DB[key]
    end
end

-- Settings.RegisterAddOnSetting writes the SavedVariables field before its
-- callback. Normalize that stored value, then run the same idempotent effects
-- used by slash/API changes.
function SDG:ApplySettingOption(key, value)
    if not DB or R.unsupportedSchema then return false end
    local normalized, valid = NormalizeOptionValue(key, value)
    if not valid then
        local previous = R.appliedOptions[key]
        if previous ~= nil then DB[key] = previous end
        return false
    end

    local corrected = DB[key] ~= normalized
    DB[key] = normalized
    ApplyOptionEffects(key, normalized)
    if corrected and type(self.NotifySettingsChanged) == "function" then
        self:NotifySettingsChanged(key)
    end
    return true
end

function SDG:SetOption(key, value)
    if not DB then return false end
    if R.unsupportedSchema then
        Print("Update Sudden Doom Glow to edit settings saved by a newer version.")
        return false
    end

    local normalized, valid = NormalizeOptionValue(key, value)
    if not valid then return false end
    if DB[key] == normalized and R.appliedOptions[key] == normalized then return true end

    DB[key] = normalized
    ApplyOptionEffects(key, normalized)
    if type(self.NotifySettingsChanged) == "function" then self:NotifySettingsChanged(key) end
    return true
end

function SDG:TestGlow()
    if not RuntimeEnabled() then Print("Enable the addon on a Death Knight to test the glow."); return false end
    R.testUntil = Now() + 2
    ReconcileGlow("test")
    local scheduled = ScheduleTimer("test", 2.05, function()
        R.testUntil = 0
        ReconcileGlow("test-end")
    end)
    if not scheduled then
        R.testUntil = 0
        ReconcileGlow("test-timer-failed")
        Print("Test glow unavailable: timer scheduling failed")
        return false
    end
    Print("Test glow for 2 seconds")
    return true
end

function SDG:OnLogin()
    if R.didLogin then return end
    R.didLogin = true
    frame:UnregisterEvent("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    R.class = SafeString(class)
    InitializeDB()
    RememberAppliedOptions()
    if type(self.RegisterSettings) == "function" then self:RegisterSettings() end
    if not RuntimeEnabled() then
        RebuildSpellFamilies()
        R.lastDetection = R.class == "DEATHKNIGHT" and "disabled" or "non-dk"
        return
    end
    StartRuntime()
    if not next(R.trackedButtons) then
        if not ScheduleTimer("login-retry", 0.35, function() self:RequestRescan("login-ready", false) end) then
            self:RequestRescan("login-ready", false)
        end
    end
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then SDG:OnLogin(); return end
    if RECOVERY_EVENTS[event] and next(R.pendingHides) then FlushPendingHides() end
    if not RuntimeEnabled() then return end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        HandleOverlayShow(...)
    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        HandleOverlayHide(...)
    elseif event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
        local baseSpellID, overrideSpellID = ...
        local changed, relevant = LearnExplicitOverride(baseSpellID, overrideSpellID, event)
        if not relevant or not changed then return end
        QueueMappingRecovery(event, false)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if R.needsRescan then
            -- One settled post-combat rescan owns assignments, viewer recovery,
            -- geometry, and proc reconciliation; do not duplicate the full pass.
            SDG:RequestRescan(event)
        else
            RefreshAssignments()
            if R.needsGeometry then PrimeTrackedAlerts() end
            ReconcileGlow(event)
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        ReconcileGlow(event)
    elseif event == "PLAYER_ENTERING_WORLD" then
        ResetAndRecover(event)
    elseif event == "ADDON_LOADED" then
        local addonName = SafeString((...))
        if addonName and RELEVANT_ADDONS[addonName] then
            SDG:RequestRescan(event .. ":" .. addonName, false)
        end
    elseif event == "COOLDOWN_VIEWER_DATA_LOADED" then
        -- Public readiness signal for the source-coupled viewer adapter.
        SDG:RequestRescan(event, false)
    elseif event == "COOLDOWN_VIEWER_TABLE_HOTFIXED" then
        -- Static viewer data changed, but runtime override observations and proc
        -- evidence remain valid. Outside combat, bursts collapse into one pass.
        QueueMappingRecovery(event, false)
    elseif event == "PLAYER_TALENT_UPDATE" or event == "TRAIT_CONFIG_UPDATED" or
           event == "SPELLS_CHANGED" then
        -- Drop stale override observations. Outside combat, bursty invalidations
        -- collapse into one settled pass; combat reuses only existing surfaces.
        QueueMappingRecovery(event, true)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELL_SECRECY_CHANGED" then
        if event == "PLAYER_SPECIALIZATION_CHANGED" then
            local unit = ...
            if SafeString(unit) ~= "player" then return end
        end
        ResetAndRecover(event)
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        local changedSlot, valid = ParseActionSlotEvent((...))
        if not valid then return end
        if changedSlot then RefreshKnownButtons(changedSlot) end
        QueueActionRefresh(changedSlot)
    else
        -- Paging/modifier/vehicle and other broad assignment invalidations
        -- collapse into one complete next-frame pass.
        QueueActionRefresh(nil)
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
    local storedDB = _G.SuddenDoomGlowDB
    local storedSchema = type(storedDB) == "table" and SafeNumber(storedDB.schemaVersion) or CURRENT_SCHEMA
    Print(("version=%s schema=%s supported=%s enabled=%s combat=%s glow=%s detection=%s")
        :format(GetAddonVersion(), tostring(storedSchema or "unknown"), tostring(not R.unsupportedSchema),
            tostring(DB.enabled), tostring(InCombat()), tostring(R.glowActive), tostring(R.lastDetection)))
    Print(("buttons=%d cdm=%d query=%d/%d authoritative=%s eventSignals=%d")
        :format(CountEntries(R.trackedButtons), CountEntries(R.cdmFrames), R.overlayQueryReadable,
            R.overlayQueryCandidates, tostring(R.overlayQueryAuthoritative), CountEntries(R.eventSignals)))
    Print(("ID limits: configured=%d resolved=%d per family")
        :format(MAX_CONFIGURED_SPELL_IDS, MAX_RESOLVED_SPELL_IDS))
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

    local added = true
    for i = 1, #list do
        if list[i] == id then
            table.remove(list, i)
            added = false
            break
        end
    end
    if added then
        if #list >= MAX_CONFIGURED_SPELL_IDS then
            Print(("Maximum %d configured %s IDs reached."):format(MAX_CONFIGURED_SPELL_IDS, label))
            return false
        end
        list[#list + 1] = id
    end
    local reason = label .. (added and "-added" or "-removed")
    if InCombat() then
        RebuildSpellFamilies()
        RefreshAssignments()
        ReconcileGlow(reason)
        R.needsRescan = true
    else
        SDG:RescanButtons(false)
        ReconcileGlow(reason)
    end
    Print((added and "Added " or "Removed ") .. label .. " spellID " .. tostring(id))
    return true
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
        if not SDG:SetOption("debug", not DB.debug) then return end
        Print("Debug: " .. (DB.debug and "ON" or "OFF"))
    elseif command == "rescan" then
        local accepted, mode = SDG:RequestRescan("slash", argument:lower() == "deep")
        if accepted then
            if mode == "deferred" then Print("Rescan deferred until combat ends")
            elseif mode == "completed" then Print("Rescan completed")
            else Print("Rescan queued") end
        else
            Print("Rescan unavailable while the addon runtime is disabled.")
        end
    elseif command == "test" then
        SDG:TestGlow()
    elseif command == "spell" then
        if R.unsupportedSchema then
            Print("Update Sudden Doom Glow to edit settings saved by a newer version.")
        else
            ToggleID(DB.targetSpellIDs, argument, "spell")
        end
    elseif command == "signal" or command == "aura" then
        if R.unsupportedSchema then
            Print("Update Sudden Doom Glow to edit settings saved by a newer version.")
        else
            ToggleID(DB.signalSpellIDs, argument, "signal")
        end
    elseif command == "spells" then
        if R.unsupportedSchema then
            Print("Configured spells are unavailable until the addon supports the newer settings schema.")
        else
            Print("targets configured: " .. FormatIDList(DB.targetSpellIDs))
            Print("targets resolved: " .. FormatIDList(R.targetFamilyList))
            Print("signals resolved: " .. FormatIDList(R.signalFamilyList))
        end
    elseif command == "cdm" then
        argument = argument:lower()
        if argument == "on" then
            if not SDG:SetOption("cdm", true) then return end
        elseif argument == "off" then
            if not SDG:SetOption("cdm", false) then return end
        else Print("Usage: /sdglow cdm on|off"); return end
        Print("Cooldown Viewer mirror: " .. (DB.cdm and "ON" or "OFF"))
    elseif command == "on" or command == "off" then
        if not SDG:SetOption("enabled", command == "on") then return end
        Print(DB.enabled and "Enabled" or "Disabled")
    else
        Print("Unknown command. Use /sdglow help")
    end
end

-- Normal login waits until every TOC file has loaded. A late load initializes
-- through a one-shot callback, so Options.lua is available before registration.
local isLoggedIn = _G.IsLoggedIn
if type(isLoggedIn) == "function" then
    local ok, loggedIn = pcall(isLoggedIn)
    if ok and IsAccessible(loggedIn) and loggedIn == true then
        local deferred = C_Timer and type(C_Timer.After) == "function"
            and pcall(C_Timer.After, 0, function() SDG:OnLogin() end)
        if not deferred then SDG:OnLogin() end
    end
end
