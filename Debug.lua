-- Sudden Doom Glow Debugger (Visual)
local AD = ...
local SDG = SuddenDoomGlow
if not SDG then return end

local format = string.format
local GetTime = GetTime

SDG.Debug = {} 
local D = SDG.Debug

local function SafePrint(msg)
    if SDG and SDG.Print then
        SDG:Print(msg)
    elseif DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffSuddenDoomGlow|r: ' .. tostring(msg))
    end
end

-- Constants
local MAX_LINES = 100
local lines = {}

-- UI Elements
local f, scroll, content, text

function D:CreateDebugFrame()
    if f then return f end
    
    -- Main Frame
    f = CreateFrame("Frame", "SDG_DebugFrame", UIParent, "BackdropTemplate")
    f:SetSize(450, 350)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    
    if Mixin and BackdropTemplateMixin then
        Mixin(f, BackdropTemplateMixin)
    end
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })
    
    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Sudden Doom Glow Debugger")

    -- Scroll Frame
    scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -40)
    scroll:SetPoint("BOTTOMRIGHT", -40, 80)
    
    -- Content Frame (Virtual)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 500) 
    scroll:SetScrollChild(content)
    
    -- Log Text
    text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(380)
    text:SetJustifyH("LEFT")
    text:SetText("Log started...")
    
    -- Flush existing lines
    if #lines > 0 then
        text:SetText(table.concat(lines, "\n"))
    end

    -- Buttons
    local btnClear = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    btnClear:SetPoint("BOTTOMLEFT", 20, 20)
    btnClear:SetSize(80, 25)
    btnClear:SetText("Clear")
    btnClear:SetScript("OnClick", function() D:Clear() end)

    local btnRescan = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    btnRescan:SetPoint("LEFT", btnClear, "RIGHT", 10, 0)
    btnRescan:SetSize(80, 25)
    btnRescan:SetText("Rescan")
    btnRescan:SetScript("OnClick", function() 
        SafePrint('Force Rescan requested.')
        SDG:RequestRescan("Debug", true) 
    end)

    local btnTest = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    btnTest:SetPoint("LEFT", btnRescan, "RIGHT", 10, 0)
    btnTest:SetSize(80, 25)
    btnTest:SetText("Test Glow")
    btnTest:SetScript("OnClick", function() 
        SafePrint('Forcing Glow ON for 3s.')
        SDG:SetGlow(true, true) 
        C_Timer.After(3, function() 
            SafePrint('Forcing Glow OFF.')
            SDG:SetGlow(false) 
        end) 
    end)

    -- Detection Toggles
    -- Aura
    local chkAura = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkAura:SetPoint("BOTTOMLEFT", 20, 50)
    chkAura.text = chkAura:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chkAura.text:SetPoint("LEFT", chkAura, "RIGHT", 0, 1)
    chkAura.text:SetText("Aura (Primary)")
    -- Default to true if nil
    if SuddenDoomGlowDB.auraEnabled == nil then SuddenDoomGlowDB.auraEnabled = true end
    chkAura:SetChecked(SuddenDoomGlowDB.auraEnabled)
    chkAura:SetScript("OnClick", function(self)
        SuddenDoomGlowDB.auraEnabled = self:GetChecked()
        SafePrint('Aura Check: ' .. tostring(SuddenDoomGlowDB.auraEnabled))
        SDG:MarkUpdateDirty("debug_toggle")
    end)

    -- Overlay
    local chkOverlay = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    chkOverlay:SetPoint("LEFT", chkAura, "RIGHT", 110, 0)
    chkOverlay.text = chkOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    chkOverlay.text:SetPoint("LEFT", chkOverlay, "RIGHT", 0, 1)
    chkOverlay.text:SetText("Overlay (Event)")
    if SuddenDoomGlowDB.overlayEnabled == nil then SuddenDoomGlowDB.overlayEnabled = true end
    chkOverlay:SetChecked(SuddenDoomGlowDB.overlayEnabled)
    chkOverlay:SetScript("OnClick", function(self)
        SuddenDoomGlowDB.overlayEnabled = self:GetChecked()
        SafePrint('Overlay Check: ' .. tostring(SuddenDoomGlowDB.overlayEnabled))
        SDG:MarkUpdateDirty("debug_toggle")
    end)

    f:Hide()
    return f
end

function SDG:Debug(msg)
    if not SuddenDoomGlowDB or not SuddenDoomGlowDB.debug then return end
    if not f then 
        -- Store early messages
        table.insert(lines, tostring(msg))
        return 
    end
    
    local t = GetTime()
    local ts = format("%.3f", t)
    local line = format("|cff888888[%s]|r %s", ts, tostring(msg))
    
    table.insert(lines, line)
    if #lines > MAX_LINES then
        table.remove(lines, 1)
    end
    
    if text then
        text:SetText(table.concat(lines, "\n"))
        local h = text:GetStringHeight()
        content:SetHeight(h + 20)
        
        -- Auto scroll to bottom
        local offset = h - scroll:GetHeight()
        local current = scroll:GetVerticalScroll()
        if offset > 0 and (offset - current < 50 or current > offset) then
             -- Scroll if near bottom
            scroll:SetVerticalScroll(offset + 10)
        end
    end
end

function D:Clear()
    lines = {}
    if text then text:SetText("") end
end

-- Debug UI is created on-demand (when /sdglow debug is enabled).

function D:Show()
    local fr = self:CreateDebugFrame()
    if fr then fr:Show() end
end

function D:Hide()
    if _G.SDG_DebugFrame then _G.SDG_DebugFrame:Hide() end
end
