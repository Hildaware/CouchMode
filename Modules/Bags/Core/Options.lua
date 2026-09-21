local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM = LibStub("LibSharedMedia-3.0")

---@class Bags: AceModule
local bagsModule = addon:GetModule('Bags')

---@class Options: AceModule
local options = addon:NewModule('Bags.Options')

---@class Database: AceModule
local database = addon:GetModule('Bags.Database')

function bagsModule:GetOptions()
    return 'bags', {
        name = 'Bags',
        type = 'group',
        order = 1,
        args = {
            enabled = {
                name = 'Enable',
                desc = 'Use the custom bag UI.',
                type = 'toggle',
                order = 0,
                get = function() return addon.db.profile.bags.enabled end,
                set = function(_, value)
                    addon.db.profile.bags.enabled = value
                    local bagsM = addon:GetModule('Bags', true)
                    if bagsM then
                        if value then bagsM:Enable() else bagsM:Disable() end
                    end
                end,
            },
            viewType = {
                name = 'View Type',
                desc =
                "'Compact' allows you to move the frame, resize it, etc. 'Full' is a more Console-like experience with docked windows.",
                type = 'select',
                order = 1,
                values = {
                    [1] = 'Compact',
                    [2] = 'Full',
                },
                get = function() return database:GetViewType() end,
                set = function(_, value) database:SetViewType(value) end
            },
            font = {
                name = 'Font',
                desc = 'The font to use for the view.',
                order = 2,
                type = 'select',
                values = addon.Media.GetFontOptions(),
                get = function()
                    return database:GetFont().name
                end,
                set = function(_, font)
                    database:SetFont(font, LSM:Fetch(LSM.MediaType.FONT, font))
                end
            },
            itemWidth = {
                name = 'Item Width',
                desc = 'The width of each item in the view.',
                type = 'range',
                min = 400,
                max = 1200,
                step = 1,
                get = function() return database:GetInventoryViewWidth() end,
                set = function(_, value) database:SetInventoryViewWidth(value) end
            },
            itemHeight = {
                name = 'Item Height',
                desc = 'The height of each item in the view.',
                type = 'range',
                min = 28,
                max = 100,
                step = 1,
                get = function() return database:GetItemViewHeight() end,
                set = function(_, value) database:SetItemViewHeight(value) end
            },
            backgroundOpacity = {
                name = 'Background Opacity',
                desc = 'The opacity of the background.',
                type = 'range',
                min = 0,
                max = 1,
                step = 0.01,
                get = function() return database:GetBackgroundOpacity() end,
                set = function(_, value) database:SetBackgroundOpacity(value) end
            },
        }
    }
end

function bagsModule:GetDefaults()
    return database:GetDefaults()
end

options:Enable()
