-- Sudden Doom Glow (Retail / Midnight)
-- Reliable architecture:
--   aura state -> desired glow state -> idempotent render
-- Aura-first with conservative fallback signals.

local ADDON_NAME = ... or "SuddenDoomGlow"

-- SavedVariables migration:
-- Wipe DB on addon version bump to prevent stale mappings/config causing wrong glows.
if type(_G.SuddenDoomGlowDB) ~= "table" then
    _G.SuddenDoomGlowDB = {}
end
SuddenDoomGlowDB = _G.SuddenDoomGlowDB
local DB = SuddenDoomGlowDB

local function GetAddonVersion()
    local v

    if _G.C_AddOns and type(_G.C_AddOns.GetAddOnMetadata) == "function" then
        local ok, res = pcall(_G.C_AddOns.GetAddOnMetadata, ADDON_NAME, "Version")
        if ok then v = res end
    end

    if (type(v) ~= "string" or v == "") and type(_G.GetAddOnMetadata) == "function" then
        local ok, res = pcall(_G.GetAddOnMetadata, ADDON_NAME, "Version")
        if ok then v = res end
    end

    if type(v) ~= "string" or v == "" then
        v = "0"
    end

    return v
end

local CURRENT_VERSION = GetAddonVersion()

local DEFAULT_AURA_IDS = { 450932, 81340 }
-- 1242174 = Necrotic Coil (Forbidden Knowledge / APEX variant).
-- Graveyard is resolved dynamically from Epidemic via GetOverrideSpell because
-- current reports conflict on hardcoding a stable spellID for it.
local DEFAULT_PROC_SPELL_IDS = { 47541, 207317, 1242174 }

local function WipeDB(t)
    for k in pairs(t) do
        t[k] = nil
    end
end

local function CopyNumericList(src)
    local out = {}
    if type(src) ~= "table" then
        return out
    end

    for i = 1, #src do
        local id = tonumber(src[i])
        if id then
            out[#out + 1] = id
        end
    end

    return out
end

local function MergeNumericDefaults(dst, defaults)
    if type(dst) ~= "table" then
        return CopyNumericList(defaults)
    end

    local seen = {}
    for i = 1, #dst do
        local id = tonumber(dst[i])
        if id then
            seen[id] = true
            dst[i] = id
        end
    end

    for i = 1, #defaults do
        local id = tonumber(defaults[i])
        if id and not seen[id] then
            dst[#dst + 1] = id
            seen[id] = true
        end
    end

    return dst
end

if DB.__version ~= CURRENT_VERSION then
    WipeDB(DB)
    DB.__version = CURRENT_VERSION
end

if DB.debug == nil then DB.debug = false end
if DB.enabled == nil then DB.enabled = true end
if DB.cdm == nil then DB.cdm = true end
if DB.auraEnabled == nil then DB.auraEnabled = true end
if DB.overlayEnabled == nil then DB.overlayEnabled = true end
if DB.costEnabled == nil then DB.costEnabled = true end
DB.auraIDs = MergeNumericDefaults(DB.auraIDs, DEFAULT_AURA_IDS)
DB.procSpellIDs = MergeNumericDefaults(DB.procSpellIDs, DEFAULT_PROC_SPELL_IDS)
if type(DB.slots) ~= "table" then DB.slots = {} end

local SDG = _G.SuddenDoomGlow
if type(SDG) ~= "table" then SDG = {} end
_G.SuddenDoomGlow = SDG

local MAX_ACTION_SLOTS = 540
local OVERLAY_SIGNAL_TTL = 20.0
local RESCAN_COALESCE_DELAY = 0.08

local PROC_TEMPLATES = {
    "ActionButtonSpellAlertTemplate",
    "ActionBarButtonSpellActivationAlert",
    "ActionButtonSpellActivationAlert",
    "SpellActivationAlertTemplate",
    "SpellActivationAlert",
}

local InCombatLockdown = _G.InCombatLockdown
local UnitClass = _G.UnitClass
local UnitGUID = _G.UnitGUID
local GetActionInfo = _G.GetActionInfo
local GetMacroInfo = _G.GetMacroInfo
local GetMacroSpell = _G.GetMacroSpell
local EnumerateFrames = _G.EnumerateFrames
local C_Timer = _G.C_Timer
local C_UnitAuras = _G.C_UnitAuras
local C_ActionBar = _G.C_ActionBar
local C_Spell = _G.C_Spell
local GetSpellPowerCost = _G.GetSpellPowerCost
local UnitAura = _G.UnitAura
local GetTime = _G.GetTime
local CombatLogGetCurrentEventInfo = _G.CombatLogGetCurrentEventInfo

local function InCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function Print(msg)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSuddenDoomGlow|r: " .. tostring(msg))
    end
end

local function Debug(msg)
    if not DB.debug then return end
    local g = _G.SuddenDoomGlow
    if g and g.Debug and g.Debug.CreateDebugFrame then
        g:Debug(msg)
    else
        Print(msg)
    end
end

local function IsSecret(v)
    if type(_G.issecretvalue) == "function" then
        local ok, res = pcall(_G.issecretvalue, v)
        if ok then
            return res and true or false
        end
    end

    local tv = type(v)
    if tv == "number" then
        local ok = pcall(function() local _ = v + 0 end)
        return not ok
    elseif tv == "string" then
        local ok = pcall(function() local _ = v .. "" end)
        return not ok
    end

    return false
end

local function SafeNumber(v)
    if v == nil or IsSecret(v) then return nil end
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber(v) end
    return nil
end

local function SpellName(spellID)
    if _G.GetSpellInfo then
        local name = _G.GetSpellInfo(spellID)
        if type(name) == "string" then return name end
    end

    if C_Spell then
        if C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellID)
            if info and type(info.name) == "string" then
                return info.name
            end
        end
        if C_Spell.GetSpellName then
            local name = C_Spell.GetSpellName(spellID)
            if type(name) == "string" then return name end
        end
    end

    return nil
end

local function WipeArray(t)
    for i = #t, 1, -1 do t[i] = nil end
end

local function WipeMap(t)
    for k in pairs(t) do t[k] = nil end
end

SDG.procSpellSet = SDG.procSpellSet or {}
SDG.procNameSet = SDG.procNameSet or {}
SDG.procTokens = SDG.procTokens or {}
SDG.procConfiguredSpellIDs = SDG.procConfiguredSpellIDs or {}
SDG.procSpellList = SDG.procSpellList or {}
SDG.auraIDSet = SDG.auraIDSet or {}

SDG.trackedSlots = SDG.trackedSlots or {}
SDG.trackedButtons = SDG.trackedButtons or {}
SDG._trackedButtonSet = SDG._trackedButtonSet or {}

SDG.extraButtons = SDG.extraButtons or {}
SDG._cdmLastSeen = SDG._cdmLastSeen or {}

SDG.overlayProcSpells = SDG.overlayProcSpells or {}
SDG.baseCost = SDG.baseCost or {}

SDG.glowActive = SDG.glowActive or false
SDG.lastDetection = SDG.lastDetection or "none"
SDG.needsRescan = SDG.needsRescan or false
SDG.pendingDeep = SDG.pendingDeep or false

SDG.auraActive = SDG.auraActive or false
SDG.auraStacks = SDG.auraStacks or 0
SDG.auraSpellId = SDG.auraSpellId or nil
SDG.auraSource = SDG.auraSource or "none"
SDG.auraAuthoritative = SDG.auraAuthoritative or false
SDG.auraReadFailed = SDG.auraReadFailed or false

SDG.cleuAuraActive = SDG.cleuAuraActive or false
SDG.cleuAuraStacks = SDG.cleuAuraStacks or 0
SDG.cleuAuraSpellID = SDG.cleuAuraSpellID or nil
SDG.cleuAuraUpdatedAt = SDG.cleuAuraUpdatedAt or 0

SDG.class = SDG.class or nil
SDG.playerGUID = SDG.playerGUID or nil

SDG._updateDirty = SDG._updateDirty or false
SDG._updateTimer = SDG._updateTimer or nil
SDG._trackedListDirty = SDG._trackedListDirty or false
SDG._castRefreshPending = SDG._castRefreshPending or false

SDG._rescanTimer = SDG._rescanTimer or nil
SDG._rescanReason = SDG._rescanReason or nil
SDG._rescanDeepQueued = SDG._rescanDeepQueued or false

function SDG:Print(msg)
    Print(msg)
end

local function AddUniqueSpellID(list, seen, id)
    id = SafeNumber(id)
    if type(id) ~= "number" or id < 1 then
        return false
    end
    if seen[id] then
        return false
    end
    seen[id] = true
    list[#list + 1] = id
    return true
end

local function CollectConfiguredProcSpellIDs()
    if type(DB.procSpellIDs) ~= "table" or #DB.procSpellIDs == 0 then
        DB.procSpellIDs = CopyNumericList(DEFAULT_PROC_SPELL_IDS)
    end

    local ids = {}
    local seen = {}
    for i = 1, #DB.procSpellIDs do
        AddUniqueSpellID(ids, seen, DB.procSpellIDs[i])
    end

    return ids
end

local function CollectOverrideSpellVariants(spellID, out, seen, depth)
    depth = depth or 0
    if depth > 6 then
        return
    end

    if not AddUniqueSpellID(out, seen, spellID) then
        return
    end

    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and type(overrideID) == "number" and overrideID > 0 and overrideID ~= spellID then
            CollectOverrideSpellVariants(overrideID, out, seen, depth + 1)
        end
    end
end

local function BuildProcCaches()
    WipeMap(SDG.procSpellSet)
    WipeMap(SDG.procNameSet)
    WipeArray(SDG.procTokens)
    WipeArray(SDG.procConfiguredSpellIDs)
    WipeArray(SDG.procSpellList)

    local configured = CollectConfiguredProcSpellIDs()
    for i = 1, #configured do
        SDG.procConfiguredSpellIDs[i] = configured[i]
    end

    local seen = {}
    for i = 1, #configured do
        CollectOverrideSpellVariants(configured[i], SDG.procSpellList, seen, 0)
    end

    for i = 1, #SDG.procSpellList do
        local sid = SDG.procSpellList[i]
        SDG.procSpellSet[sid] = true
        SDG.procTokens[#SDG.procTokens + 1] = tostring(sid)

        local n = SpellName(sid)
        if n then
            local ln = n:lower()
            SDG.procNameSet[ln] = true
            SDG.procTokens[#SDG.procTokens + 1] = ln
        end
    end
end

function SDG:RebuildAuraIDSet()
    WipeMap(self.auraIDSet)

    if type(DB.auraIDs) ~= "table" then DB.auraIDs = {} end
    for i = 1, #DB.auraIDs do
        local id = tonumber(DB.auraIDs[i])
        if id then
            self.auraIDSet[id] = true
        end
    end
end

local function SafePlay(anim)
    if anim and anim.Play then
        pcall(anim.Play, anim)
        return true
    end
    return false
end

local function SafeStop(anim)
    if anim and anim.Stop then
        pcall(anim.Stop, anim)
        return true
    end
    return false
end

local function StartProc(alert)
    if not alert then return end

    local start = alert.ProcStartAnim or alert.procStartAnim or alert.AnimIn or alert.animIn
    local loop = alert.ProcLoopAnim or alert.procLoopAnim or alert.AnimLoop or alert.animLoop
    local startFB = alert.ProcStartFlipbook or alert.procStartFlipbook
    local loopFB = alert.ProcLoopFlipbook or alert.procLoopFlipbook

    local outro = alert.ProcEndAnim or alert.procEndAnim or alert.AnimOut or alert.animOut
    SafeStop(outro)

    local startAnim = start or startFB
    local loopAnim = loop or loopFB

    local started = SafePlay(startAnim)
    if not started then
        SafePlay(loopAnim)
        return
    end

    if loopAnim and loopAnim.Play then
        if startAnim and startAnim.SetScript and not startAnim.__SDG_ChainLoop then
            startAnim.__SDG_ChainLoop = true
            startAnim:SetScript("OnFinished", function()
                if alert and alert.IsShown and alert:IsShown() then
                    pcall(loopAnim.Play, loopAnim)
                end
            end)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.12, function()
                if alert and alert.IsShown and alert:IsShown() then
                    pcall(loopAnim.Play, loopAnim)
                end
            end)
        end
    end
end

local function StopProc(alert)
    if not alert then return end

    local outro = alert.ProcEndAnim or alert.procEndAnim or alert.AnimOut or alert.animOut
    if outro and outro.Play then
        pcall(outro.Play, outro)
        return
    end

    SafeStop(alert.ProcStartAnim or alert.procStartAnim or alert.AnimIn or alert.animIn)
    SafeStop(alert.ProcLoopAnim or alert.procLoopAnim or alert.AnimLoop or alert.animLoop)
    SafeStop(alert.ProcStartFlipbook or alert.procStartFlipbook)
    SafeStop(alert.ProcLoopFlipbook or alert.procLoopFlipbook)
end

local function EnsureSDGAlert(btn)
    if not btn or not _G.CreateFrame then return nil end
    if btn.IsForbidden and btn:IsForbidden() then return nil end

    if btn.__SDG_Alert then return btn.__SDG_Alert end

    local w, h = 0, 0
    if btn.GetSize then w, h = btn:GetSize() end

    for i = 1, #PROC_TEMPLATES do
        local template = PROC_TEMPLATES[i]
        local ok, alert = pcall(_G.CreateFrame, "Frame", nil, btn, template)
        if ok and alert then
            if w and h and w > 0 and h > 0 then
                alert:SetSize(w * 1.4, h * 1.4)
            else
                alert:SetAllPoints(btn)
            end
            alert:SetPoint("CENTER", btn, "CENTER", 0, 0)
            alert:SetFrameStrata("HIGH")
            alert:SetFrameLevel((btn.GetFrameLevel and btn:GetFrameLevel() or 0) + 50)
            alert:Hide()
            btn.__SDG_Alert = alert
            btn.__SDG_AlertShown = false
            return alert
        end
    end

    return nil
end

local GetButtonActionSlot
local SafeHideGlow
local MacroMatchesProc

local function AddTrackedButton(btn)
    if not btn then return end
    if btn.IsForbidden and btn:IsForbidden() then return end
    if SDG._trackedButtonSet[btn] then return end

    SDG._trackedButtonSet[btn] = true
    SDG.trackedButtons[#SDG.trackedButtons + 1] = btn
end

local function RemoveTrackedButton(btn)
    if not btn then return end
    if not SDG._trackedButtonSet[btn] then return end

    SDG._trackedButtonSet[btn] = nil
    SDG._trackedListDirty = true
    SafeHideGlow(btn)
end

function SDG:CompactTrackedButtons()
    if not self._trackedListDirty then return end

    local keep = {}
    for i = 1, #self.trackedButtons do
        local btn = self.trackedButtons[i]
        if btn and self._trackedButtonSet[btn] then
            keep[#keep + 1] = btn
        end
    end

    WipeArray(self.trackedButtons)
    WipeMap(self._trackedButtonSet)

    for i = 1, #keep do
        local btn = keep[i]
        self.trackedButtons[i] = btn
        self._trackedButtonSet[btn] = true
    end

    self._trackedListDirty = false
end

GetButtonActionSlot = function(btn)
    local t = type(btn)
    if t ~= "table" and t ~= "userdata" then return nil end

    local name
    if btn.GetName then
        local ok, n = pcall(btn.GetName, btn)
        if ok and type(n) == "string" then name = n end
    end

    local function IsKnownActionButtonName(n)
        if type(n) ~= "string" then return false end
        if n:match("^ActionButton%d+$") then return true end
        if n:match("^MultiBar") then return true end
        if n:match("^ExtraActionButton") then return true end
        if n:match("^ElvUI_Bar%d+Button%d+$") then return true end
        if n:match("^BT4Button%d+$") then return true end
        if n:match("^DominosActionButton%d+$") then return true end
        return false
    end

    local candidates = {}
    local seen = {}
    local function Push(slot)
        if type(slot) ~= "number" then return end
        if slot < 1 or slot > MAX_ACTION_SLOTS then return end
        if not seen[slot] then
            seen[slot] = true
            candidates[#candidates + 1] = slot
        end
    end

    -- Blizzard helper: resolves current paged ID for action buttons.
    -- Prefer it for known action button names (Blizzard / major bar mods).
    local getPaged = _G.ActionButton_GetPagedID
    if type(getPaged) == "function" and IsKnownActionButtonName(name) then
        local ok, slot = pcall(getPaged, btn)
        if ok then Push(slot) end
    end

    -- Button mixin helpers (some action bar mods keep these updated).
    if type(btn.GetPagedID) == "function" then
        local ok, slot = pcall(btn.GetPagedID, btn)
        if ok then Push(slot) end
    end

    if type(btn.GetAction) == "function" then
        local ok, slot = pcall(btn.GetAction, btn)
        if ok then Push(slot) end
    end

    -- Secure attribute (some implementations keep it updated).
    if btn.GetAttribute then
        local a = btn:GetAttribute("action")
        Push(a)
    end

    Push(btn._state_action)
    Push(btn.action)

    -- If multiple candidates exist (common with paging/state drivers), try to pick the one
    -- that actually contains our proc action. This prevents wrong glows on bars that report
    -- button indices (1-12) instead of real action slots.
    if #candidates > 1 then
        for i = 1, #candidates do
            local s = candidates[i]
            if SDG.trackedSlots and SDG.trackedSlots[s] then
                return s
            end
        end
        if GetActionInfo then
            for i = 1, #candidates do
                local s = candidates[i]
                local ok, actionType, id = pcall(GetActionInfo, s)
                if ok and actionType == "spell" and type(id) == "number" and SDG.procSpellSet[id] then
                    return s
                end
                if ok and actionType == "macro" and id and MacroMatchesProc(id) then
                    return s
                end
            end
        end
    end

    return candidates[1]
end


local function SafeShowGlow(btn)
    if not btn then return end

    -- Always validate current action-slot, even in combat.
    -- Paging/stance/vehicle swaps can occur during combat; we must not glow the wrong physical button.
    if not btn.__SDG_CDMTracked then
        local slot = GetButtonActionSlot(btn)
        if not slot then
            -- If we cannot resolve safely, do not show.
            SafeHideGlow(btn)
            return
        end
        if not SDG.trackedSlots[slot] then
            SafeHideGlow(btn)
            return
        end
    end

    local inCombat = InCombat()
    if not btn.__SDG_CDMTracked then
        if inCombat then
            -- In combat we never mutate the tracked list; just ensure we only glow tracked buttons.
            if not SDG._trackedButtonSet[btn] then
                return
            end
        else
            local slot = GetButtonActionSlot(btn)
            if not slot or not SDG.trackedSlots[slot] then
                RemoveTrackedButton(btn)
                return
            end
        end
    end

    local alert = EnsureSDGAlert(btn)
    if not alert then return end

    if btn.__SDG_AlertShown and alert.IsShown and alert:IsShown() then return end

    alert:Show()
    StartProc(alert)
    btn.__SDG_AlertShown = true
end

SafeHideGlow = function(btn)
    if not btn then return end

    local alert = btn.__SDG_Alert
    if not alert then
        btn.__SDG_AlertShown = false
        return
    end

    if not btn.__SDG_AlertShown and not (alert.IsShown and alert:IsShown()) then
        return
    end

    StopProc(alert)
    alert:Hide()
    btn.__SDG_AlertShown = false
end

function SDG:PrimeAlerts()
    if InCombat() then return end

    self:CompactTrackedButtons()
    for i = 1, #self.trackedButtons do
        EnsureSDGAlert(self.trackedButtons[i])
    end
    for i = 1, #self.extraButtons do
        EnsureSDGAlert(self.extraButtons[i])
    end
end

MacroMatchesProc = function(macroID)
    if not macroID then return false end

    if GetMacroSpell then
        local ms = GetMacroSpell(macroID)
        if type(ms) == "number" and SDG.procSpellSet[ms] then
            return true
        end
        if type(ms) == "string" and SDG.procNameSet[ms:lower()] then
            return true
        end
    end

    if not GetMacroInfo then return false end

    local _, _, body = GetMacroInfo(macroID)
    if type(body) ~= "string" or body == "" then
        return false
    end

    local b = body:lower()
    for i = 1, #SDG.procTokens do
        local tok = SDG.procTokens[i]
        if tok and b:find(tok, 1, true) then
            return true
        end
    end

    return false
end

local function SlotLooksLikeProc(slot)
    local actionType, id = GetActionInfo(slot)

    if actionType == "spell" and type(id) == "number" and SDG.procSpellSet[id] then
        return true
    end

    if actionType == "macro" and id then
        if MacroMatchesProc(id) then return true end
        if type(id) == "number" and SDG.procSpellSet[id] then return true end
    end

    return false
end

local function ScanActionSlots()
    WipeMap(SDG.trackedSlots)
    BuildProcCaches()

    local found = {}
    local seen = {}

    local function TrackSlot(slot)
        slot = SafeNumber(slot)
        if type(slot) ~= "number" then return end
        if slot < 1 or slot > MAX_ACTION_SLOTS then return end
        if seen[slot] then return end
        seen[slot] = true
        SDG.trackedSlots[slot] = true
        found[#found + 1] = slot
    end

    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        for i = 1, #SDG.procSpellList do
            local sid = SDG.procSpellList[i]
            local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, sid)
            if ok and type(slots) == "table" then
                for j = 1, #slots do
                    TrackSlot(slots[j])
                end
            end
        end
    end

    for slot = 1, MAX_ACTION_SLOTS do
        if SlotLooksLikeProc(slot) then
            TrackSlot(slot)
        end
    end

    DB.slots = found
    Debug(("Slots mapped: %d"):format(#found))
end

local NAMED_BUTTON_SETS = {
    { prefix = "ActionButton", count = 12 },
    { prefix = "MultiBarBottomLeftButton", count = 12 },
    { prefix = "MultiBarBottomRightButton", count = 12 },
    { prefix = "MultiBarRightButton", count = 12 },
    { prefix = "MultiBarLeftButton", count = 12 },
    { prefix = "MultiBar5Button", count = 12 },
    { prefix = "MultiBar6Button", count = 12 },
    { prefix = "MultiBar7Button", count = 12 },
    { prefix = "MultiBar8Button", count = 12 },
    { prefix = "MultiBar9Button", count = 12 },
    { prefix = "MultiBar10Button", count = 12 },
    { prefix = "BT4Button", count = 180 },
    { prefix = "DominosActionButton", count = 180 },
}

local function MapButtonsFromNamedBars()
    for s = 1, #NAMED_BUTTON_SETS do
        local set = NAMED_BUTTON_SETS[s]
        for i = 1, set.count do
            local btn = _G[set.prefix .. i]
            if btn then
                local slot = GetButtonActionSlot(btn)
                if slot and SDG.trackedSlots[slot] then
                    AddTrackedButton(btn)
                end
            end
        end
    end

    for bar = 1, 10 do
        for i = 1, 12 do
            local btn = _G["ElvUI_Bar" .. bar .. "Button" .. i]
            if btn then
                local slot = GetButtonActionSlot(btn)
                if slot and SDG.trackedSlots[slot] then
                    AddTrackedButton(btn)
                end
            end
        end
    end

    local extra = _G.ExtraActionButton1
    if extra then
        local slot = GetButtonActionSlot(extra)
        if slot and SDG.trackedSlots[slot] then
            AddTrackedButton(extra)
        end
    end
end

local function EnumerateAndMapButtons(maxFrames)
    if not EnumerateFrames then return end

    local count = 0
    local f = EnumerateFrames()
    while f do
        count = count + 1
        if maxFrames and count > maxFrames then break end

        if f.GetObjectType then
            local ot = f:GetObjectType()
            if (ot == "Button" or ot == "CheckButton") and not (f.IsForbidden and f:IsForbidden()) then
                local slot = GetButtonActionSlot(f)
                if slot and SDG.trackedSlots[slot] then
                    AddTrackedButton(f)
                end
            end
        end

        f = EnumerateFrames(f)
    end
end
function SDG:RescanButtons(deep)
    if InCombat() then
        self.needsRescan = true
        if deep then self.pendingDeep = true end
        Debug("Rescan deferred (combat)")
        return
    end

    self.needsRescan = false

    local wasActive = self.glowActive
    if wasActive then
        for i = 1, #self.trackedButtons do
            SafeHideGlow(self.trackedButtons[i])
        end
        for i = 1, #self.extraButtons do
            SafeHideGlow(self.extraButtons[i])
        end
    end

    WipeArray(self.trackedButtons)
    WipeMap(self._trackedButtonSet)
    self._trackedListDirty = false

    ScanActionSlots()
    MapButtonsFromNamedBars()

    if deep then
        EnumerateAndMapButtons(25000)
    end

    if DB.cdm then
        self:TryFindCDMButtons()
    else
        for i = 1, #self.extraButtons do
            local f = self.extraButtons[i]
            if f then f.__SDG_CDMTracked = nil end
        end
        WipeArray(self.extraButtons)
        WipeMap(self._cdmLastSeen)
    end

    self:PrimeAlerts()
    Debug(("Buttons mapped: actions=%d cdm=%d"):format(#self.trackedButtons, #self.extraButtons))

    if wasActive then
        self:ApplyGlowState()
    end
end

function SDG:RequestRescan(reason, deep)
    -- Coalesce bursts of rescan triggers (bindings, talent swaps, page changes, etc.).
    if reason then
        self._rescanReason = reason
    end
    if deep then
        self._rescanDeepQueued = true
    end

    if InCombat() then
        self.needsRescan = true
        if deep then self.pendingDeep = true end
        if reason then Debug("Rescan deferred: " .. tostring(reason)) end
        return
    end

    if self._rescanTimer then
        return
    end

    local function Flush()
        if not SDG then return end
        SDG._rescanTimer = nil

        local doDeep = SDG._rescanDeepQueued or SDG.pendingDeep
        SDG._rescanDeepQueued = false
        SDG.pendingDeep = nil

        SDG:RescanButtons(doDeep)
        SDG:UpdateBaselineCosts()
        SDG:MarkUpdateDirty(SDG._rescanReason or "rescan", 0)
        SDG._rescanReason = nil
    end

    if C_Timer and C_Timer.NewTimer then
        self._rescanTimer = C_Timer.NewTimer(RESCAN_COALESCE_DELAY, Flush)
    elseif C_Timer and C_Timer.After then
        self._rescanTimer = true
        C_Timer.After(RESCAN_COALESCE_DELAY, Flush)
    else
        Flush()
    end
end

local function GetFrameSpellID(frame)
    if not frame then return nil end

    if frame.GetSpellID then
        local ok, sid = pcall(frame.GetSpellID, frame)
        if ok and type(sid) == "number" and not IsSecret(sid) then
            return sid
        end
    end

    local sid = frame.spellID or frame.spellId
    if type(sid) == "number" and not IsSecret(sid) then
        return sid
    end

    sid = frame.rangeCheckSpellID or frame.rangeCheckSpellId
    if type(sid) == "number" and not IsSecret(sid) then
        return sid
    end

    if type(frame.cooldownInfo) == "table" then
        sid = frame.cooldownInfo.spellID or frame.cooldownInfo.spellId or frame.cooldownInfo.id
        if type(sid) == "number" and not IsSecret(sid) then
            return sid
        end
    end

    return nil
end

function SDG:UpdatesActiveCDMFrames()
    BuildProcCaches()

    if not DB.cdm then
        if type(self.extraButtons) == "table" then
            for i = 1, #self.extraButtons do
                local f = self.extraButtons[i]
                if f then f.__SDG_CDMTracked = nil end
            end
        end
        WipeArray(self.extraButtons)
        WipeMap(self._cdmLastSeen)
        return
    end

    local now = (GetTime and GetTime()) or 0
    local grace = 0.45
    local lastSeen = self._cdmLastSeen

    local viewers = {
        _G.EssentialCooldownViewer,
        _G.UtilityCooldownViewer,
        _G.BuffIconCooldownViewer,
    }

    local activeFrames = {}
    local activeSet = {}

    local function PushUnique(frame)
        if frame and not activeSet[frame] then
            activeSet[frame] = true
            activeFrames[#activeFrames + 1] = frame
        end
    end

    for i = 1, #viewers do
        local viewer = viewers[i]
        if viewer and viewer.itemFramePool and viewer.itemFramePool.EnumerateActive then
            for frame in viewer.itemFramePool:EnumerateActive() do
                if frame and frame.IsShown and frame:IsShown() then
                    local sid = GetFrameSpellID(frame)
                    if type(sid) == "number" and self.procSpellSet[sid] then
                        frame.__SDG_CDMTracked = true
                        lastSeen[frame] = now
                        PushUnique(frame)
                    end
                end
            end
        end
    end

    if #self.extraButtons > 0 then
        for i = 1, #self.extraButtons do
            local old = self.extraButtons[i]
            if old and not activeSet[old] then
                local seenAt = lastSeen[old] or 0
                if (now - seenAt) <= grace then
                    PushUnique(old)
                else
                    old.__SDG_CDMTracked = nil
                    lastSeen[old] = nil
                    if self.glowActive then
                        SafeHideGlow(old)
                    end
                end
            end
        end
    end

    self.extraButtons = activeFrames
end

function SDG:TryFindCDMButtons()
    self:UpdatesActiveCDMFrames()
    if self.glowActive then
        self:ApplyGlowState()
    end
end

function SDG:StartCDMWatcher()
    if self._cdmTicker then return end
    if not (DB.cdm and C_Timer and C_Timer.NewTicker) then return end

    self._cdmTicker = C_Timer.NewTicker(0.20, function()
        if not SDG then return end
        if not (SDG.glowActive and DB.cdm) then
            SDG:StopCDMWatcher()
            return
        end

        SDG:UpdatesActiveCDMFrames()
        for i = 1, #SDG.extraButtons do
            SafeShowGlow(SDG.extraButtons[i])
        end
    end)
end

function SDG:StopCDMWatcher()
    if self._cdmTicker then
        self._cdmTicker:Cancel()
        self._cdmTicker = nil
    end
end

function SDG:SetAuraState(active, stacks, spellID, source)
    local prevA = self.auraActive
    local prevS = self.auraStacks

    self.auraActive = active and true or false
    self.auraStacks = self.auraActive and (SafeNumber(stacks) or 1) or 0
    self.auraSpellId = SafeNumber(spellID)
    self.auraSource = source or "none"

    return prevA ~= self.auraActive or prevS ~= self.auraStacks
end

function SDG:ScanAuraFull(reason)
    if not DB.auraEnabled then
        self.auraAuthoritative = true
        self.auraReadFailed = false
        return self:SetAuraState(false, 0, nil, "disabled")
    end

    local auraApiAvailable = false
    local auraApiOperational = false

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and type(DB.auraIDs) == "table" then
        auraApiAvailable = true
        for i = 1, #DB.auraIDs do
            local auraID = tonumber(DB.auraIDs[i])
            if auraID then
                local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, auraID)
                if ok then
                    auraApiOperational = true
                end
                if ok and aura then
                    local stacks = aura.applications or aura.charges or aura.stackCount or 1
                    self.auraAuthoritative = true
                    self.auraReadFailed = false
                    return self:SetAuraState(true, stacks, auraID, reason or "spellid")
                end
            end
        end
    end

    
    -- Fast-path: if spellID lookup API is present and operational, treat nil as authoritative 'not present'.
    -- Avoid full index scans on every UNIT_AURA when the proc is not active.
    if auraApiAvailable and auraApiOperational then
        self.auraAuthoritative = true
        self.auraReadFailed = false
        return self:SetAuraState(false, 0, nil, reason or "spellid_none")
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        auraApiAvailable = true
        for i = 1, 80 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if ok then
                auraApiOperational = true
            end
            if not ok or not aura then break end

            local sid = SafeNumber(aura.spellId or aura.spellID)
            if sid and self.auraIDSet[sid] then
                local stacks = aura.applications or aura.charges or aura.stackCount or 1
                self.auraAuthoritative = true
                self.auraReadFailed = false
                return self:SetAuraState(true, stacks, sid, reason or "index")
            end
        end
    end

    if UnitAura and type(DB.auraIDs) == "table" then
        auraApiAvailable = true
        auraApiOperational = true
        for i = 1, 40 do
            local _, _, count, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
            if not sid then break end
            sid = SafeNumber(sid)
            if sid and self.auraIDSet[sid] then
                self.auraAuthoritative = true
                self.auraReadFailed = false
                return self:SetAuraState(true, count or 1, sid, reason or "legacy")
            end
        end
    end

    self.auraReadFailed = auraApiAvailable and (not auraApiOperational) or false

    if self.auraReadFailed and self.cleuAuraUpdatedAt and self.cleuAuraUpdatedAt > 0 then
        local now = (GetTime and GetTime()) or 0
        if (now - self.cleuAuraUpdatedAt) <= 12.0 then
            self.auraAuthoritative = true
            return self:SetAuraState(self.cleuAuraActive, self.cleuAuraStacks, self.cleuAuraSpellID, reason or "cleu_fallback")
        end
    end

    self.auraAuthoritative = auraApiOperational and true or false
    return self:SetAuraState(false, 0, nil, reason or (auraApiAvailable and "none" or "unavailable"))
end

function SDG:HasOverlayProc()
    if type(self.overlayProcSpells) ~= "table" then
        return false
    end

    local now = (GetTime and GetTime()) or 0
    local hasActive = false
    for sid, seenAt in pairs(self.overlayProcSpells) do
        if type(seenAt) ~= "number" or (now - seenAt) > OVERLAY_SIGNAL_TTL then
            self.overlayProcSpells[sid] = nil
        else
            hasActive = true
        end
    end

    return hasActive
end

local function GetRunicPowerType()
    if _G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.RunicPower then
        return _G.Enum.PowerType.RunicPower
    end
    return 6
end

local function GetSpellRunicCost(spellID)
    if type(spellID) ~= "number" then return nil end

    local rpType = GetRunicPowerType()

    if C_Spell and C_Spell.GetSpellPowerCost then
        local ok, costs = pcall(C_Spell.GetSpellPowerCost, spellID)
        if ok and type(costs) == "table" then
            for i = 1, #costs do
                local c = costs[i]
                if type(c) == "table" and c.type == rpType then
                    local cost = SafeNumber(c.cost or c.minCost)
                    if type(cost) == "number" then return cost end
                end
            end
        end
    end

    if GetSpellPowerCost then
        local ok, costs = pcall(GetSpellPowerCost, spellID)
        if ok and type(costs) == "table" then
            for i = 1, #costs do
                local c = costs[i]
                if type(c) == "table" and c.type == rpType then
                    local cost = SafeNumber(c.cost or c.minCost)
                    if type(cost) == "number" then return cost end
                end
            end
        end
    end

    return nil
end

function SDG:UpdateBaselineCosts()
    if #self.procConfiguredSpellIDs == 0 then
        BuildProcCaches()
    end

    for i = 1, #self.procConfiguredSpellIDs do
        local sid = self.procConfiguredSpellIDs[i]
        local cost = GetSpellRunicCost(sid)
        if type(cost) == "number" then
            local prev = self.baseCost[sid]
            if type(prev) ~= "number" or cost > prev then
                self.baseCost[sid] = cost
            end
        end
    end
end

function SDG:HasProcViaCost()
    self:UpdateBaselineCosts()

    local threshold = 1
    for i = 1, #self.procConfiguredSpellIDs do
        local sid = self.procConfiguredSpellIDs[i]
        local base = self.baseCost[sid]
        local cost = GetSpellRunicCost(sid)
        if type(base) == "number" and type(cost) == "number" and cost <= (base - threshold) then
            return true
        end
    end

    return false
end

function SDG:ApplyGlowState()
    self:CompactTrackedButtons()

    if DB.cdm then
        self:UpdatesActiveCDMFrames()
    end

    if self.glowActive then
        for i = 1, #self.trackedButtons do
            SafeShowGlow(self.trackedButtons[i])
        end
        for i = 1, #self.extraButtons do
            SafeShowGlow(self.extraButtons[i])
        end
    else
        for i = 1, #self.trackedButtons do
            SafeHideGlow(self.trackedButtons[i])
        end
        for i = 1, #self.extraButtons do
            SafeHideGlow(self.extraButtons[i])
        end
    end
end

function SDG:SetGlow(active, force)
    local newState = active and true or false
    if not force and newState == self.glowActive then return end

    self.glowActive = newState
    self:ApplyGlowState()

    if DB.cdm and self.glowActive then
        self:StartCDMWatcher()
    else
        self:StopCDMWatcher()
    end
end

function SDG:UpdateFromSignals()
    if not DB.enabled then
        self.lastDetection = "none"
        self:SetGlow(false)
        return
    end

    local active = false
    local det = "none"

    if DB.auraEnabled and self.auraActive then
        active = true
        det = "aura"
    elseif DB.overlayEnabled and self:HasOverlayProc() then
        active = true
        det = "overlay"
    elseif DB.costEnabled ~= false and InCombat() and self:HasProcViaCost() then
        active = true
        det = "cost"
    end

    self.lastDetection = det
    self:SetGlow(active)
end

function SDG:MarkUpdateDirty(reason, delay)
    self._updateDirty = true

    if self._updateTimer then return end

    local interval = delay
    if interval == nil then interval = 0 end

    local function Flush()
        SDG._updateTimer = nil
        if SDG._updateDirty then
            SDG._updateDirty = false
            SDG:UpdateFromSignals()
        end
    end

    if interval <= 0 and C_Timer and C_Timer.After then
        self._updateTimer = true
        C_Timer.After(0, Flush)
    elseif C_Timer and C_Timer.NewTimer then
        self._updateTimer = C_Timer.NewTimer(interval, Flush)
    elseif C_Timer and C_Timer.After then
        self._updateTimer = true
        C_Timer.After(interval, Flush)
    else
        self._updateDirty = false
        self:UpdateFromSignals()
    end

    if DB.debug and reason then
        Debug("Dirty: " .. tostring(reason))
    end
end

local function QueueSpellcastAuraRefresh()
    if SDG._castRefreshPending then return end
    SDG._castRefreshPending = true

    local function Pass(reason, isLast)
        if not SDG then return end
        SDG:ScanAuraFull(reason)
        if SDG.auraAuthoritative and not SDG.auraActive then
            WipeMap(SDG.overlayProcSpells)
        end
        SDG:MarkUpdateDirty(reason, 0)
        if isLast then
            SDG._castRefreshPending = false
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() Pass("spellcast_hint_0", false) end)
        C_Timer.After(0.06, function() Pass("spellcast_hint_1", false) end)
        C_Timer.After(0.14, function() Pass("spellcast_hint_2", true) end)
    else
        Pass("spellcast_hint", true)
    end
end

function SDG:HandleCombatLogAuraEvent()
    if not CombatLogGetCurrentEventInfo then return end
    if not self.playerGUID then return end
    if not DB.auraEnabled then return end

    local _, subEvent, _, _, _, _, _, destGUID, _, _, _, spellID, _, _, auraType, amount = CombatLogGetCurrentEventInfo()
    if destGUID ~= self.playerGUID then return end
    if type(spellID) ~= "number" or not self.auraIDSet[spellID] then return end
    if auraType and auraType ~= "BUFF" then return end

    local changed = false
    local stacks = SafeNumber(amount)

    if subEvent == "SPELL_AURA_APPLIED" then
        self.cleuAuraActive = true
        self.cleuAuraStacks = stacks or 1
        changed = true
    elseif subEvent == "SPELL_AURA_APPLIED_DOSE" then
        self.cleuAuraActive = true
        self.cleuAuraStacks = stacks or self.cleuAuraStacks or 1
        if self.cleuAuraStacks < 1 then self.cleuAuraStacks = 1 end
        changed = true
    elseif subEvent == "SPELL_AURA_REMOVED_DOSE" then
        self.cleuAuraStacks = stacks or 0
        self.cleuAuraActive = self.cleuAuraStacks > 0
        changed = true
    elseif subEvent == "SPELL_AURA_REFRESH" then
        self.cleuAuraActive = true
        if not self.cleuAuraStacks or self.cleuAuraStacks < 1 then
            self.cleuAuraStacks = stacks or 1
        end
        changed = true
    elseif subEvent == "SPELL_AURA_REMOVED" then
        self.cleuAuraActive = false
        self.cleuAuraStacks = 0
        changed = true
    end

    if not changed then return end

    self.cleuAuraSpellID = spellID
    self.cleuAuraUpdatedAt = (GetTime and GetTime()) or 0

    if self.auraReadFailed or (not self.auraAuthoritative) then
        self.auraAuthoritative = true
        self:SetAuraState(self.cleuAuraActive, self.cleuAuraStacks, self.cleuAuraSpellID, "cleu")
        self:MarkUpdateDirty("cleu", 0)
    end
end

function SDG:AttachActionButtonCallback()
    if self._actionChangedAttached then return end

    if not (EventRegistry and EventRegistry.RegisterCallback) then
        return
    end

    EventRegistry:RegisterCallback("ActionButton.OnActionChanged", function(_, button)
        if not SDG or SDG.class ~= "DEATHKNIGHT" then return end
        if not button then return end

        local slot = GetButtonActionSlot(button)
        local shouldTrack = slot and SDG.trackedSlots[slot] or false
        local tracked = SDG._trackedButtonSet[button] and true or false

        if shouldTrack and not tracked then
            AddTrackedButton(button)
            if not InCombat() then
                EnsureSDGAlert(button)
                if SDG.glowActive then
                    SafeShowGlow(button)
                end
            else
                -- Do not create overlays in combat on protected action buttons.
                if SDG.glowActive and button.__SDG_Alert then
                    SafeShowGlow(button)
                end
                SDG.needsRescan = true
            end
        elseif (not shouldTrack) and tracked then
            if not InCombat() then
                RemoveTrackedButton(button)
            else
                -- Avoid transient combat remaps dropping tracked buttons mid-fight.
                SDG.needsRescan = true
            end
        end
    end, self)

    self._actionChangedAttached = true
end

function SDG:OnLogin()
    if self._didLogin then return end
    self._didLogin = true

    local _, class = UnitClass("player")
    self.class = class
    self.playerGUID = UnitGUID("player")

    BuildProcCaches()
    self:RebuildAuraIDSet()

    if self.class ~= "DEATHKNIGHT" then
        Debug("Non-DK class; addon idle")
        self.lastDetection = "none"
        self:SetGlow(false, true)
        return
    end

    self:RegisterRuntimeEvents()
    self:AttachActionButtonCallback()

    self:RescanButtons(false)
    self:UpdateBaselineCosts()
    if #self.trackedButtons == 0 and C_Timer and C_Timer.After then
        -- Avoid auto-deep scan: retry normal bar mapping after UI finishes late setup.
        C_Timer.After(0.35, function()
            if SDG and SDG.class == "DEATHKNIGHT" then
                SDG:RequestRescan("login_retry_1", false)
            end
        end)
        C_Timer.After(1.00, function()
            if SDG and SDG.class == "DEATHKNIGHT" and #SDG.trackedButtons == 0 then
                SDG:RequestRescan("login_retry_2", false)
            end
        end)
    end

    self:ScanAuraFull("login")
    self:MarkUpdateDirty("login", 0)

    if DB.cdm and C_Timer and C_Timer.After then
        C_Timer.After(0.3, function()
            if SDG then SDG:TryFindCDMButtons() end
        end)
    end

    Debug(("Loaded buttons=%d cdm=%d"):format(#self.trackedButtons, #self.extraButtons))
end

local frame = _G.CreateFrame("Frame")

function SDG:RegisterRuntimeEvents()
    if frame.__SDG_RuntimeEventsRegistered then return end
    frame.__SDG_RuntimeEventsRegistered = true

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
    frame:RegisterEvent("ADDON_LOADED")

    frame:RegisterUnitEvent("UNIT_AURA", "player")
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        SDG:OnLogin()
        return
    end

    if SDG.class ~= "DEATHKNIGHT" then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        SDG:ScanAuraFull("enter_world")
        SDG:MarkUpdateDirty("enter_world", 0)

    elseif event == "PLAYER_REGEN_DISABLED" then
        SDG:ScanAuraFull("enter_combat")
        SDG:MarkUpdateDirty("enter_combat", 0)

    elseif event == "PLAYER_REGEN_ENABLED" then
        SDG:ScanAuraFull("leave_combat")
        SDG:MarkUpdateDirty("leave_combat", 0)
        if SDG.needsRescan then
            SDG:RequestRescan("regen_enabled", SDG.pendingDeep)
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" then
            SDG:ScanAuraFull("unit_aura")
            SDG:MarkUpdateDirty("unit_aura", 0)
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if unit == "player" and type(spellID) == "number" and SDG.procSpellSet[spellID] then
            QueueSpellcastAuraRefresh()
        end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        local spellID = ...
        if type(spellID) == "number" and (SDG.procSpellSet[spellID] or SDG.auraIDSet[spellID]) then
            SDG.overlayProcSpells[spellID] = (GetTime and GetTime()) or 0
            SDG:MarkUpdateDirty("overlay_show", 0)
        end

    elseif event == "SPELL_ACTIVATION_OVERLAY_GLOW_HIDE" then
        local spellID = ...
        if type(spellID) == "number" and SDG.overlayProcSpells[spellID] then
            SDG.overlayProcSpells[spellID] = nil
            SDG:MarkUpdateDirty("overlay_hide", 0)
        end

    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or
           event == "UPDATE_OVERRIDE_ACTIONBAR" or
           event == "UPDATE_BONUS_ACTIONBAR" or event == "UPDATE_VEHICLE_ACTIONBAR" or
           event == "UPDATE_BINDINGS" or event == "SPELLS_CHANGED" or
           event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_TALENT_UPDATE" or
           event == "TRAIT_CONFIG_UPDATED" then
        SDG:RequestRescan(event, false)

    elseif event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Blizzard_ActionBar" then
            SDG:AttachActionButtonCallback()
            SDG:RequestRescan("addon_loaded_actionbar", false)
        elseif DB.cdm and type(addonName) == "string" and (addonName:find("Blizzard_Cooldown") or addonName:find("CooldownManager")) then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.2, function()
                    if SDG then SDG:TryFindCDMButtons() end
                end)
            else
                SDG:TryFindCDMButtons()
            end
        end
    end
end

frame:SetScript("OnEvent", OnEvent)
frame:RegisterEvent("PLAYER_LOGIN")

if _G.IsLoggedIn and _G.IsLoggedIn() then
    SDG:OnLogin()
end

local function FormatIDList(list)
    if type(list) ~= "table" or #list == 0 then return "(empty)" end
    local out = {}
    for i = 1, #list do out[i] = tostring(list[i]) end
    return table.concat(out, ",")
end

local function DumpState()
    local combat = InCombat()

    Print("enabled=" .. tostring(DB.enabled) ..
        " combat=" .. tostring(combat) ..
        " buttons=" .. tostring(#SDG.trackedButtons) ..
        " cdm=" .. tostring(#SDG.extraButtons) ..
        " detection=" .. tostring(SDG.lastDetection) ..
        " glow=" .. tostring(SDG.glowActive))

    Print("aura: active=" .. tostring(SDG.auraActive) ..
        " stacks=" .. tostring(SDG.auraStacks) ..
        " spellID=" .. tostring(SDG.auraSpellId) ..
        " source=" .. tostring(SDG.auraSource) ..
        " authoritative=" .. tostring(SDG.auraAuthoritative) ..
        " readFailed=" .. tostring(SDG.auraReadFailed))

    Print("auraIDs: " .. FormatIDList(DB.auraIDs))
    Print("procSpellIDs configured: " .. FormatIDList(SDG.procConfiguredSpellIDs))
    Print("procSpellIDs resolved: " .. FormatIDList(SDG.procSpellList))

    local overlay = {}
    for sid in pairs(SDG.overlayProcSpells or {}) do
        overlay[#overlay + 1] = tostring(sid)
    end
    table.sort(overlay)
    Print("overlay: " .. (#overlay > 0 and table.concat(overlay, ",") or "(none)"))
    Print("signals: aura=" .. tostring(SDG.auraActive) ..
        " overlay=" .. tostring(SDG:HasOverlayProc()) ..
        " cost=" .. tostring(SDG:HasProcViaCost()) ..
        " costEnabled=" .. tostring(DB.costEnabled ~= false))
end

local function DumpPlayerHelpfulAuras(filter)
    filter = type(filter) == "string" and filter ~= "" and filter:lower() or nil

    Print("Player HELPFUL auras (name | spellID):")

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 80 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end

            local sid = aura.spellId or aura.spellID
            local nm = aura.name

            local sidStr = "<unknown>"
            if type(sid) == "number" then
                sidStr = tostring(sid)
            elseif sid ~= nil and IsSecret(sid) then
                sidStr = "<secret>"
            elseif sid ~= nil then
                sidStr = tostring(sid)
            end

            local nameStr = "<unknown>"
            if type(nm) == "string" and not IsSecret(nm) then
                nameStr = nm
            elseif nm ~= nil and IsSecret(nm) then
                nameStr = "<secret>"
            end

            if not filter or (type(nameStr) == "string" and nameStr:lower():find(filter, 1, true)) then
                Print(("%02d) %s | %s"):format(i, nameStr, sidStr))
            end
        end
        return
    end

    if UnitAura then
        for i = 1, 40 do
            local name, _, _, _, _, _, _, _, _, sid = UnitAura("player", i, "HELPFUL")
            if not name then break end
            local nameStr = (type(name) == "string" and not IsSecret(name)) and name or "<secret>"
            local sidStr = (type(sid) == "number") and tostring(sid) or "<unknown>"
            if not filter or (type(nameStr) == "string" and nameStr:lower():find(filter, 1, true)) then
                Print(("%02d) %s | %s"):format(i, nameStr, sidStr))
            end
        end
    end
end

local function ToggleAuraID(id)
    id = tonumber(id)
    if not id then
        Print("Usage: /sdglow aura <spellID>")
        return
    end

    if type(DB.auraIDs) ~= "table" then DB.auraIDs = {} end

    for i = 1, #DB.auraIDs do
        if tonumber(DB.auraIDs[i]) == id then
            table.remove(DB.auraIDs, i)
            SDG:RebuildAuraIDSet()
            SDG:ScanAuraFull("aura_list_changed")
            SDG:MarkUpdateDirty("aura_list_changed", 0)
            Print("Removed auraID " .. tostring(id) .. ". Now: " .. FormatIDList(DB.auraIDs))
            return
        end
    end

    DB.auraIDs[#DB.auraIDs + 1] = id
    SDG:RebuildAuraIDSet()
    SDG:ScanAuraFull("aura_list_changed")
    SDG:MarkUpdateDirty("aura_list_changed", 0)
    Print("Added auraID " .. tostring(id) .. ". Now: " .. FormatIDList(DB.auraIDs))
end

local function ToggleProcSpellID(id)
    id = tonumber(id)
    if not id then
        Print("Usage: /sdglow spell <spellID>")
        return
    end

    if type(DB.procSpellIDs) ~= "table" then
        DB.procSpellIDs = {}
    end

    for i = 1, #DB.procSpellIDs do
        if tonumber(DB.procSpellIDs[i]) == id then
            table.remove(DB.procSpellIDs, i)
            BuildProcCaches()
            SDG:RequestRescan("proc_spell_list_changed", false)
            SDG:UpdateBaselineCosts()
            SDG:MarkUpdateDirty("proc_spell_list_changed", 0)
            Print("Removed proc spellID " .. tostring(id) .. ". Now: " .. FormatIDList(DB.procSpellIDs))
            return
        end
    end

    DB.procSpellIDs[#DB.procSpellIDs + 1] = id
    BuildProcCaches()
    SDG:RequestRescan("proc_spell_list_changed", false)
    SDG:UpdateBaselineCosts()
    SDG:MarkUpdateDirty("proc_spell_list_changed", 0)
    Print("Added proc spellID " .. tostring(id) .. ". Now: " .. FormatIDList(DB.procSpellIDs))
end

SLASH_SUDDEN_DOOM_GLOW1 = "/sdglow"
SlashCmdList["SUDDEN_DOOM_GLOW"] = function(msg)
    msg = msg or ""

    local cmd, arg = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "help" then
        Print("Commands:")
        Print("  /sdglow status")
        Print("  /sdglow debug")
        Print("  /sdglow aura <spellID>")
        Print("  /sdglow spell <spellID>")
        Print("  /sdglow spells")
        Print("  /sdglow auras [filter]")
        Print("  /sdglow rescan [deep]")
        Print("  /sdglow test")
        Print("  /sdglow cdm (on|off)")
        Print("  /sdglow on | /sdglow off")
        return
    end

    if cmd == "debug" then
        DB.debug = not DB.debug
        Print("Debug: " .. (DB.debug and "ON" or "OFF"))

        if SDG.Debug and SDG.Debug.CreateDebugFrame then
            if DB.debug then
                SDG.Debug:CreateDebugFrame()
                if _G.SDG_DebugFrame then _G.SDG_DebugFrame:Show() end
            else
                if _G.SDG_DebugFrame then _G.SDG_DebugFrame:Hide() end
            end
        end
        return
    end

    if cmd == "status" or cmd == "dump" then
        DumpState()
        return
    end

    if cmd == "spells" then
        BuildProcCaches()
        Print("procSpellIDs configured: " .. FormatIDList(SDG.procConfiguredSpellIDs))
        Print("procSpellIDs resolved: " .. FormatIDList(SDG.procSpellList))
        return
    end

    if cmd == "auras" then
        DumpPlayerHelpfulAuras(arg ~= "" and arg or nil)
        return
    end

    if cmd == "aura" then
        ToggleAuraID(arg)
        return
    end

    if cmd == "spell" then
        ToggleProcSpellID(arg)
        return
    end

    if cmd == "rescan" then
        local deep = arg and arg:lower():find("deep", 1, true) ~= nil
        SDG:RequestRescan("slash_rescan", deep)
        if InCombat() then
            Print("Rescan deferred (in combat)")
        else
            Print("Rescan done. buttons=" .. tostring(#SDG.trackedButtons) .. " cdm=" .. tostring(#SDG.extraButtons))
        end
        return
    end

    if cmd == "test" then
        SDG:SetGlow(true, true)
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                if SDG then SDG:MarkUpdateDirty("test_end", 0) end
            end)
        else
            SDG:MarkUpdateDirty("test_end", 0)
        end
        Print("Test glow for 2s")
        return
    end

    if cmd == "cdm" then
        local newValue = not DB.cdm
        if arg == "on" then newValue = true
        elseif arg == "off" then newValue = false
        end
        DB.cdm = newValue

        if DB.cdm then
            SDG:TryFindCDMButtons()
        else
            SDG:StopCDMWatcher()
            for i = 1, #SDG.extraButtons do
                local f = SDG.extraButtons[i]
                if f then
                    f.__SDG_CDMTracked = nil
                    SafeHideGlow(f)
                end
            end
            WipeArray(SDG.extraButtons)
            WipeMap(SDG._cdmLastSeen)
        end

        SDG:ApplyGlowState()
        Print("CDM mirror: " .. (DB.cdm and "ON" or "OFF"))
        return
    end

    if cmd == "off" then
        DB.enabled = false
        SDG.lastDetection = "none"
        SDG:SetGlow(false, true)
        Print("Disabled")
        return
    end

    if cmd == "on" then
        DB.enabled = true
        SDG:ScanAuraFull("slash_on")
        SDG:MarkUpdateDirty("slash_on", 0)
        Print("Enabled")
        return
    end

    Print("Unknown command. Use /sdglow help")
end
