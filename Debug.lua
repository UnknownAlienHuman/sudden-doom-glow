-- Sudden Doom Glow: optional visual debug log.

local SDG = _G.SuddenDoomGlow
if type(SDG) ~= "table" then return end

local MAX_LINES = 120
local lines = {}
local frame
local scrollFrame
local content
local text

SDG.DebugUI = SDG.DebugUI or {}
local UI = SDG.DebugUI

local function SafePrint(message)
    if type(SDG.Print) == "function" then
        SDG:Print(message)
    elseif _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSuddenDoomGlow|r: " .. tostring(message))
    end
end

local function RefreshText()
    if not text then return end
    text:SetText(table.concat(lines, "\n"))
    local height = math.max(1, text:GetStringHeight() + 20)
    content:SetHeight(height)
    if scrollFrame then
        local maxOffset = math.max(0, height - scrollFrame:GetHeight())
        scrollFrame:SetVerticalScroll(maxOffset)
    end
end

function SDG:LogDebug(message)
    local db = _G.SuddenDoomGlowDB
    if not db or not db.debug then return end

    local timestamp = _G.GetTime and _G.GetTime() or 0
    lines[#lines + 1] = ("|cff888888[%.3f]|r %s"):format(timestamp, tostring(message))
    if #lines > MAX_LINES then table.remove(lines, 1) end
    RefreshText()
end

function UI:Clear()
    for i = #lines, 1, -1 do lines[i] = nil end
    RefreshText()
end

function UI:Create()
    if frame then return frame end

    frame = CreateFrame("Frame", "SDG_DebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(520, 370)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Sudden Doom Glow — Debug")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 22, -48)
    scrollFrame:SetPoint("BOTTOMRIGHT", -42, 58)

    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(440, 1)
    scrollFrame:SetScrollChild(content)

    text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT")
    text:SetWidth(440)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")

    local clear = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    clear:SetSize(90, 24)
    clear:SetPoint("BOTTOMLEFT", 22, 22)
    clear:SetText("Clear")
    clear:SetScript("OnClick", function() UI:Clear() end)

    local rescan = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    rescan:SetSize(110, 24)
    rescan:SetPoint("LEFT", clear, "RIGHT", 10, 0)
    rescan:SetText("Deep rescan")
    rescan:SetScript("OnClick", function()
        SafePrint("Deep rescan requested")
        SDG:RequestRescan("debug-ui", true)
    end)

    local test = CreateFrame("Button", nil, frame, "GameMenuButtonTemplate")
    test:SetSize(100, 24)
    test:SetPoint("LEFT", rescan, "RIGHT", 10, 0)
    test:SetText("Test glow")
    test:SetScript("OnClick", function()
        _G.SlashCmdList["SUDDEN_DOOM_GLOW"]("test")
    end)

    RefreshText()
    frame:Hide()
    return frame
end

function UI:Show()
    local window = self:Create()
    window:Show()
end

function UI:Hide()
    if frame then frame:Hide() end
end
