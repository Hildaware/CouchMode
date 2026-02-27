local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Options: AceModule
local options = addon:NewModule('Options')

---@class OptionsModule: AceModule
---@field GetDefaults  fun(self: OptionsModule): table<string, any>
---@field GetOptions   fun(self: OptionsModule): string, table
---@field RebuildOptions fun(self: OptionsModule)

-- Ordered list of modules that contribute defaults and settings panels.
-- Order here determines tab order in the settings dialog.
local MODULES = { 'CastRing', 'PlayerCastBar', 'AttachToTarget', 'PlayerHealthBar' }

function options:OnInitialize()
    -- Collect defaults from each module.
    local defaults = { profile = {} }
    for _, modName in ipairs(MODULES) do
        local mod = addon:GetModule(modName) --[[@as OptionsModule]]
        if mod.GetDefaults then
            for k, v in pairs(mod:GetDefaults()) do
                defaults.profile[k] = v
            end
        end
    end

    addon.db = LibStub("AceDB-3.0"):New("ConsoleToolsDB", defaults, true)

    -- Collect settings panels from each module.
    local settings = { type = 'group', args = {} }
    for _, modName in ipairs(MODULES) do
        local mod = addon:GetModule(modName) --[[@as OptionsModule]]
        if mod.GetOptions then
            local key, group = mod:GetOptions()
            settings.args[key] = group
        end
    end

    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, settings)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, 'Console Tools')

    LibStub('AceConsole-3.0'):RegisterChatCommand('ct',
        function() LibStub("AceConfigDialog-3.0"):Open(addonName) end)
    LibStub('AceConsole-3.0'):RegisterChatCommand('consoletools',
        function() LibStub("AceConfigDialog-3.0"):Open(addonName) end)

    -- Populate dynamic entries saved from previous sessions.
    for _, modName in ipairs(MODULES) do
        local mod = addon:GetModule(modName) --[[@as OptionsModule]]
        if mod.RebuildOptions then
            mod:RebuildOptions()
        end
    end
end

options:Enable()
