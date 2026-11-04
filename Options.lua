-- Sudden Doom Glow: native Blizzard Settings integration.

local _addonName, SDG = ...
if type(SDG) ~= "table" then return end

local CATEGORY_NAME = "Sudden Doom Glow"
local category
local registered = false
local pendingRegistration = false
local pendingOpen = false
local deferFrame
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
    Print(openAfterward and "Settings will open after combat." or
        "Settings registration deferred until combat ends.")
end

local function AttachChangeCallback(setting, key)
    setting:SetValueChangedCallback(function(_setting, value)
        if not SDG:ApplySettingOption(key, value) then
            Print("Could not apply the updated setting.")
        end
    end)
end

local function RegisterBoolean(settings, variableTable, key, label, tooltip, defaultValue)
    local setting = settings.RegisterAddOnSetting(
        category,
        SETTING_VARIABLES[key],
        key,
        variableTable,
        settings.VarType.Boolean,
        label,
        defaultValue
    )
    AttachChangeCallback(setting, key)
    settings.CreateCheckbox(category, setting, tooltip)
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
    local variableTable = _G.SuddenDoomGlowDB
    if type(variableTable) ~= "table" or type(settings) ~= "table" or
       type(settings.RegisterVerticalLayoutCategory) ~= "function" or
       type(settings.RegisterAddOnSetting) ~= "function" or
       type(settings.CreateCheckbox) ~= "function" or
       type(settings.CreateSlider) ~= "function" or
       type(settings.CreateSliderOptions) ~= "function" or
       type(settings.RegisterAddOnCategory) ~= "function" then
        Print("Blizzard Settings API is unavailable.")
        return false
    end

    category = settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)

    RegisterBoolean(settings, variableTable, "enabled", "Enable glow",
        "Show the addon glow while Sudden Doom is active.", true)
    RegisterBoolean(settings, variableTable, "cdm", "Cooldown Viewer glow",
        "Mirror the glow on matching Cooldown Viewer items.", true)
    RegisterBoolean(settings, variableTable, "debug", "Debug log",
        "Show diagnostic messages in the debug window.", false)

    local scaleSetting = settings.RegisterAddOnSetting(
        category,
        SETTING_VARIABLES.glowScale,
        "glowScale",
        variableTable,
        settings.VarType.Number,
        "Glow size",
        1.4
    )
    AttachChangeCallback(scaleSetting, "glowScale")

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
    if not registered or notifyingSettings then return false end
    local variable = SETTING_VARIABLES[key]
    if not variable then return false end
    local settings = _G.Settings
    if type(settings) ~= "table" or type(settings.NotifyUpdate) ~= "function" then return false end

    notifyingSettings = true
    local ok = pcall(settings.NotifyUpdate, variable)
    notifyingSettings = false
    if not ok then Print("Could not refresh the Settings control.") end
    return ok
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
