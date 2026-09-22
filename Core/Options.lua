local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Options: AceModule
local options = addon:NewModule('Options')

---@class OptionsModule: AceModule
---@field GetDefaults  fun(self: OptionsModule): table<string, any>
---@field GetOptions   fun(self: OptionsModule): string, table
---@field RebuildOptions fun(self: OptionsModule)

-- Ordered list of modules that contribute defaults and settings panels.
-- Order here determines tab order in the settings dialog.
local MODULES = { 'Bags', 'CastBar', 'Nameplates', 'Minimap', 'Tips', 'PlayerHealthBar', 'PlayerPowerBar',
    'PlayerManaBar', 'Chat', 'ChatBubbles' }

-- Modules whose options are nested together under a single "Player Bars" group.
local PLAYER_BAR_MODULES = { CastBar = true, PlayerHealthBar = true, PlayerPowerBar = true, PlayerManaBar = true }

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

    addon.db = LibStub("AceDB-3.0"):New("CouchModeDB", defaults, true)

    -- Migrate legacy profiles before any module reads its settings.
    if addon.ChatMigration then addon.ChatMigration.Run(addon.db) end

    -- Collect settings panels from each module.
    local settings = { type = 'group', args = {} }
    local playerBarsGroup = {
        name = 'Player Bars',
        type = 'group',
        order = 2,
        childGroups = 'tab',
        args = {},
    }
    for _, modName in ipairs(MODULES) do
        local mod = addon:GetModule(modName) --[[@as OptionsModule]]
        if mod.GetOptions then
            local key, group = mod:GetOptions()
            if PLAYER_BAR_MODULES[modName] then
                playerBarsGroup.args[key] = group
            else
                settings.args[key] = group
            end
        end
    end
    settings.args['playerBars'] = playerBarsGroup

    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, settings)
    addon.Utils.InstallAceConfigTooltipCompatibility()
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, 'Couch Mode')

    LibStub('AceConsole-3.0'):RegisterChatCommand('cm', function(args)
        local cmd, rest = tostring(args or ''):match('^%s*(%S*)%s*(.-)%s*$')
        -- `/cm chat ...` drives the Chat module's mock/testing subcommands.
        if cmd == 'chat' then
            local sub, arg = rest:match('^%s*(%S*)%s*(.-)%s*$')
            if addon.Chat and addon.Chat.HandleCommand then
                addon.Chat:HandleCommand(sub or '', arg or '')
            end
            return
        end
        LibStub("AceConfigDialog-3.0"):Open(addonName)
    end)
    LibStub('AceConsole-3.0'):RegisterChatCommand('couchmode',
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
