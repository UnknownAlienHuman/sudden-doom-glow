-- Sudden Doom Glow: optional visual diagnostics, separate from runtime state.

local _addonName, SDG = ...
if type(SDG) ~= "table" then return end

local MAX_LINES = 120
local lines = {}
local frame
local scrollFrame
local content
local text
local refreshTimer
local pendingShow = false
local deferFrame

SDG.DebugUI = SDG.DebugUI or {}
local UI = SDG.DebugUI

local function CanAccess(value)
    if type(_G.canaccessvalue) == "function" then
        local ok, accessible = pcall(_G.canaccessvalue, value)
        return ok and accessible == true
    end
    if type(_G.issecretvalue) == "function" then
        local ok, secret = pcall(_G.issecretvalue, value)
        return ok and secret ~= true
    end
    return true
end

local function InCombat()
    if type(_G.InCombatLockdown) ~= "function" then return false end
    local ok, locked = pcall(_G.InCombatLockdown)
    return ok and CanAccess(locked) and locked == true
end

local function SafePrint(message)
    if type(SDG.Print) == "function" then SDG:Print(message) end
end

local function SafeMessage(value)
    if not CanAccess(value) then return nil end
    local kind = type(value)
    if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return nil end
    return tostring(value)
end

local function IsVisible()
    return frame and frame:IsShown()
end

local function CancelRefresh()
    local owner = refreshTimer
    refreshTimer = nil
    if not owner then return end
    local handle = owner.handle
    if not CanAccess(handle) or handle == nil then return end
    local ok, cancel = pcall(function() return handle.Cancel end)
    if ok and CanAccess(cancel) and type(cancel) == "function" then
        pcall(cancel, handle)
    end
end

local function RefreshText()
    refreshTimer = nil
    if not text or not IsVisible() then return end
    text:SetText(table.concat(lines, "\n"))
    local height = math.max(1, text:GetStringHeight() + 18)
    content:SetHeight(height)
    local maxOffset = math.max(0, height - scrollFrame:GetHeight())
    scrollFrame:SetVerticalScroll(maxOffset)
end

local function ScheduleRefresh()
    if not IsVisible() or refreshTimer then return end
    local owner = {}
    refreshTimer = owner
    local function Run()
        if refreshTimer ~= owner then return end
        refreshTimer = nil
        RefreshText()
    end

    local timers = _G.C_Timer
    if timers and type(timers.NewTimer) == "function" then
        local ok, handle = pcall(timers.NewTimer, 0.05, Run)
        if ok then
            if refreshTimer == owner and CanAccess(handle) and handle ~= nil then
                owner.handle = handle
            end
            return
        end
    end

    if refreshTimer == owner then refreshTimer = nil end
    RefreshText()
end

local function EnsureDeferredWorkFrame()
    if deferFrame then return deferFrame end
    if type(_G.CreateFrame) ~= "function" then return nil end

    deferFrame = _G.CreateFrame("Frame")
    deferFrame:SetScript("OnEvent", function(self)
        if InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingShow then
            pendingShow = false
            UI:Show()
        end
    end)
    return deferFrame
end

local function DeferShow()
    pendingShow = true
    local owner = EnsureDeferredWorkFrame()
    if owner and not owner:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    SafePrint("Debug window will open after combat.")
end

function SDG:LogDebug(message)
    if type(SDG.GetOption) ~= "function" or not SDG:GetOption("debug") then return end
    local safeMessage = SafeMessage(message)
    if not safeMessage then return end

    local timestamp = _G.GetTime and _G.GetTime() or 0
    lines[#lines + 1] = ("|cff888888[%.3f]|r %s"):format(timestamp, safeMessage)
    if #lines > MAX_LINES then table.remove(lines, 1) end
    ScheduleRefresh()
end

function UI:Clear()
    for i = #lines, 1, -1 do lines[i] = nil end
    ScheduleRefresh()
end

function UI:Create()
    if frame then return frame end
    if InCombat() then
        DeferShow()
        return nil
    end
    if type(_G.CreateFrame) ~= "function" then return nil end

    frame = _G.CreateFrame("Frame", "SDG_DebugFrame", _G.UIParent, "BackdropTemplate")
    frame:SetSize(520, 370)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    _G.UISpecialFrames = _G.UISpecialFrames or {}
    local escapeRegistered = false
    for i = 1, #_G.UISpecialFrames do
        if _G.UISpecialFrames[i] == "SDG_DebugFrame" then
            escapeRegistered = true
            break
        end
    end
    if not escapeRegistered then
        _G.UISpecialFrames[#_G.UISpecialFrames + 1] = "SDG_DebugFrame"
    end
    frame:SetScript("OnShow", ScheduleRefresh)
    frame:SetScript("OnHide", CancelRefresh)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.035, 0.045, 0.04, 0.97)
    frame:SetBackdropBorderColor(0.15, 0.24, 0.18, 1)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(0.2, 0.72, 0.38, 1)
    accent:SetPoint("TOPLEFT", 12, -44)
    accent:SetPoint("TOPRIGHT", -12, -44)
    accent:SetHeight(2)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -15)
    title:SetText("Sudden Doom Glow  /  Debug")
    title:SetTextColor(0.36, 0.88, 0.52)

    local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() UI:Hide() end)

    scrollFrame = _G.CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -58)
    scrollFrame:SetPoint("BOTTOMRIGHT", -38, 58)

    content = _G.CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(440, 1)
    scrollFrame:SetScrollChild(content)

    text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT")
    text:SetWidth(440)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetTextColor(0.82, 0.86, 0.83)

    local clear = _G.CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    clear:SetSize(86, 24)
    clear:SetPoint("BOTTOMLEFT", 20, 18)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() UI:Clear() end)

    local rescan = _G.CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    rescan:SetSize(112, 24)
    rescan:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    rescan:SetText("Deep rescan")
    rescan:SetScript("OnClick", function()
        if type(SDG.RequestRescan) ~= "function" then
            SafePrint("Deep rescan unavailable while the addon runtime is disabled.")
            return
        end
        local accepted, mode = SDG:RequestRescan("debug-ui", true)
        if not accepted then
            SafePrint("Deep rescan unavailable while the addon runtime is disabled.")
        elseif mode == "deferred" then
            SafePrint("Deep rescan deferred until combat ends")
        elseif mode == "completed" then
            SafePrint("Deep rescan completed")
        else
            SafePrint("Deep rescan queued")
        end
    end)

    local test = _G.CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    test:SetSize(96, 24)
    test:SetPoint("LEFT", rescan, "RIGHT", 10, 0)
    test:SetText("Test glow")
    test:SetScript("OnClick", function()
        if type(SDG.TestGlow) == "function" then SDG:TestGlow() end
    end)

    frame:Hide()
    return frame
end

function UI:Show()
    if InCombat() then
        DeferShow()
        return false
    end
    local window = self:Create()
    if not window then return false end
    window:Show()
    return true
end

function UI:Hide()
    pendingShow = false
    if deferFrame and deferFrame:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        deferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    if frame then frame:Hide() end
end

