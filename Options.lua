-- Sudden Doom Glow: native Blizzard Settings integration.

local SDG = _G.SuddenDoomGlow
if type(SDG) ~= "table" then return end

local CATEGORY_NAME = "Sudden Doom Glow"
local category
local registered = false
local pendingRegistration = false
local pendingOpen = false
local deferFrame
local writingSetting = false
local notifyingSettings = false
local unsupportedSchemaNoticeShown = false

local SETTING_VARIABLES = {
    enabled = "SuddenDoomGlow_Enabled",
    cdm = "SuddenDoomGlow_CooldownViewer",
    debug = "SuddenDoomGlow_Debug",
    glowScale = "SuddenDoomGlow_GlowScale",
}

local function InCombat()
    return type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown()
end

local function Print(message)
    if type(SDG.Print) == "function" then SDG:Print(message) end
end

local function EnsureDeferredWorkFrame()
    if deferFrame then return deferFrame end
    if type(_G.CreateFrame) ~= "function" then return nil end

    deferFrame = _G.CreateFrame("Frame")
    deferFrame:SetScript("OnEvent", function(self)
        if InCombat() then return end
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        if pendingRegistration then
            pendingRegistration = false
            SDG:RegisterSettings()
        end
        if pendingOpen then
            pendingOpen = false
            SDG:OpenSettings()
        end
    end)
    return deferFrame
end

local function DeferSettingsWork(openAfterward)
    pendingRegistration = true
    pendingOpen = pendingOpen or openAfterward
    local owner = EnsureDeferredWorkFrame()
    if owner and not owner:IsEventRegistered("PLAYER_REGEN_ENABLED") then
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    Print("Settings will open after combat.")
end

local function WriteOptionFromSetting(key, value)
    writingSetting = true
    local ok, result = pcall(SDG.SetOption, SDG, key, value)
    writingSetting = false
    if not ok then error(result) end
    return result
end

local function RegisterBoolean(key, variable, label, tooltip, defaultValue)
    local setting = _G.Settings.RegisterProxySetting(
        category,
        variable,
        _G.Settings.VarType.Boolean,
        label,
        defaultValue,
        function() return SDG:GetOption(key) end,
        function(value) WriteOptionFromSetting(key, value) end
    )
    _G.Settings.CreateCheckbox(category, setting, tooltip)
end

function SDG:RegisterSettings()
    if registered then return true end
    if SDG.runtime and SDG.runtime.unsupportedSchema then
        if not unsupportedSchemaNoticeShown then
            unsupportedSchemaNoticeShown = true
            Print("Update Sudden Doom Glow to edit settings saved by a newer version.")
        end
        return false
    end
    if InCombat() then
        DeferSettingsWork(false)
        return false
    end

    local settings = _G.Settings
    if type(settings) ~= "table" or
       type(settings.RegisterVerticalLayoutCategory) ~= "function" or
       type(settings.RegisterProxySetting) ~= "function" or
       type(settings.CreateCheckbox) ~= "function" or
       type(settings.CreateSlider) ~= "function" or
       type(settings.CreateSliderOptions) ~= "function" or
       type(settings.RegisterAddOnCategory) ~= "function" then
        Print("Blizzard Settings API is unavailable.")
        return false
    end

    category = settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)

    RegisterBoolean("enabled", "SuddenDoomGlow_Enabled", "Enable glow",
        "Show the addon glow while Sudden Doom is active.", true)
    RegisterBoolean("cdm", "SuddenDoomGlow_CooldownViewer", "Cooldown Viewer glow",
        "Mirror the glow on matching Cooldown Viewer items.", true)
    RegisterBoolean("debug", "SuddenDoomGlow_Debug", "Debug log",
        "Show diagnostic messages in the debug window.", false)

    local scaleSetting = settings.RegisterProxySetting(
        category,
        "SuddenDoomGlow_GlowScale",
        settings.VarType.Number,
        "Glow size",
        1.4,
        function() return SDG:GetOption("glowScale") end,
        function(value) WriteOptionFromSetting("glowScale", value) end
    )
    local scaleOptions = settings.CreateSliderOptions(1.0, 1.8, 0.1)
    local sliderLabel = _G.MinimalSliderWithSteppersMixin and
        _G.MinimalSliderWithSteppersMixin.Label and
        _G.MinimalSliderWithSteppersMixin.Label.Right
    if sliderLabel and type(scaleOptions.SetLabelFormatter) == "function" then
        scaleOptions:SetLabelFormatter(sliderLabel, function(value)
            return ("%.1f"):format(value)
        end)
    end
    settings.CreateSlider(category, scaleSetting, scaleOptions,
        "Adjust the size of addon-owned action button and Cooldown Viewer glows.")

    settings.RegisterAddOnCategory(category)
    registered = true
    return true
end

function SDG:NotifySettingsChanged(key)
    if not registered or writingSetting or notifyingSettings then return end
    local variable = SETTING_VARIABLES[key]
    if not variable then return end
    local settings = _G.Settings
    if type(settings) ~= "table" or type(settings.NotifyUpdate) ~= "function" then return end

    notifyingSettings = true
    local ok, err = pcall(settings.NotifyUpdate, variable)
    notifyingSettings = false
    if not ok then Print("Could not refresh the Settings control.") end
end

function SDG:OpenSettings()
    if InCombat() then
        DeferSettingsWork(true)
        return false
    end
    if not registered and not self:RegisterSettings() then return false end
    if not category or type(_G.Settings.OpenToCategory) ~= "function" then
        Print("Settings category is unavailable.")
        return false
    end
    _G.Settings.OpenToCategory(category:GetID())
    return true
end

-- This nonvisual event owner may be created during a late combat-time load;
-- settings category registration/opening remains deferred until combat ends.
EnsureDeferredWorkFrame()
