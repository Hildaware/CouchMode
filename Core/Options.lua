local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Options: AceModule
local options = addon:NewModule('Options')
addon.Options = options
local modulePaths = {}

---@class OptionsModule: AceModule
---@field GetDefaults  fun(self: OptionsModule): table<string, any>
---@field GetOptions   fun(self: OptionsModule): string, table
---@field GetPlayerBarGeneralOptions fun(self: OptionsModule): table<string, table>
---@field RebuildOptions fun(self: OptionsModule)

-- Ordered list of modules that contribute defaults and settings panels.
-- Order here determines tab order in the settings dialog.
local MODULES = { 'Bags', 'Merchant', 'CastBar', 'Nameplates', 'Minimap', 'Tips', 'Party', 'PlayerHealthBar', 'PlayerPowerBar',
    'PlayerManaBar', 'Chat', 'ChatBubbles', 'Toasts' }

-- Modules whose options are nested together under a single "Player Bars" group.
local PLAYER_BAR_MODULES = { CastBar = true, PlayerHealthBar = true, PlayerPowerBar = true, PlayerManaBar = true }

StaticPopupDialogs['COUCHMODE_RELOAD_REQUIRED'] = {
    text = 'Changing "%s" requires reloading the UI. Apply the change and reload now?',
    button1 = RELOADUI,
    button2 = CANCEL,
    OnAccept = function(_, data)
        data.settings[data.key] = data.value
        ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    exclusive = 1,
}

-- Keep saved and active settings in sync: cancelling leaves the current value intact.
function options:SetReloadRequiredOption(settings, key, value, label)
    if settings[key] == value then return end
    StaticPopup_Show('COUCHMODE_RELOAD_REQUIRED', label, nil, {
        settings = settings, key = key, value = value,
    })
end

-- Keep Edit Mode open when following this link: closing it can discard unsaved
-- Blizzard layout changes. Edit Layout closes /cm to return to the canvas.
function options:OpenModule(moduleName)
    local path = modulePaths[moduleName]
    local dialog = LibStub('AceConfigDialog-3.0')
    if path then
        dialog:Open(addonName, unpack(path))
    else
        dialog:Open(addonName)
    end
end

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
        args = {
            general = {
                name = 'General',
                type = 'group',
                order = 0,
                args = {
                    blizzardVisibility = {
                        name = 'Blizzard Frame Visibility',
                        type = 'group',
                        inline = true,
                        order = 1,
                        args = {
                            description = {
                                name = 'Check a box to hide that Blizzard frame. Changes require a UI reload.',
                                type = 'description',
                                order = 0,
                                width = 'full',
                            },
                        },
                    },
                },
            },
        },
    }
    for _, modName in ipairs(MODULES) do
        local mod = addon:GetModule(modName) --[[@as OptionsModule]]
        if PLAYER_BAR_MODULES[modName] and mod.GetPlayerBarGeneralOptions then
            for key, arg in pairs(mod:GetPlayerBarGeneralOptions()) do
                playerBarsGroup.args.general.args.blizzardVisibility.args[key] = arg
            end
        end
        if mod.GetOptions then
            local key, group = mod:GetOptions()
            if PLAYER_BAR_MODULES[modName] then
                playerBarsGroup.args[key] = group
                modulePaths[modName] = { 'playerBars', key }
            else
                settings.args[key] = group
                modulePaths[modName] = { key }
            end
        end
    end
    settings.args['playerBars'] = playerBarsGroup
    modulePaths.CastRing = { 'playerBars', 'castBars', 'castRing' }
    modulePaths.PlayerCastBar = { 'playerBars', 'castBars', 'playerCastBar' }

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
        -- `/cm toasts ...` drives the Toasts mock/testing subcommands.
        if cmd == 'toasts' then
            local sub, arg = rest:match('^%s*(%S*)%s*(.-)%s*$')
            if addon.Toasts and addon.Toasts.HandleCommand then
                addon.Toasts:HandleCommand(sub or '', arg or '')
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
