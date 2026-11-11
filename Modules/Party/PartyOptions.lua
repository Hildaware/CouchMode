local addonName = ...

local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local party = addon:GetModule('Party')

local function db() return addon.db.profile.party end

function party:GetDefaults()
    return {
        party = {
            enabled = true,
            showWhileSolo = false,
            smoothBars = true,
            width = 430,
            scale = 1,
            positions = {},
        },
    }
end

function party:GetOptions()
    return 'party', {
        name = 'Party', type = 'group', order = 10,
        args = {
            description = {
                name = 'Portrait, health, power, and relevant auras for you and up to four party members.',
                type = 'description',
                order = 1,
            },
            general = {
                name = 'General', type = 'group', inline = true, order = 2,
                args = {
                    enabled = {
                        name = 'Enable Party Frames',
                        desc = 'Show CouchMode party frames instead of Blizzard party frames while in a party.',
                        type = 'toggle',
                        order = 2,
                        get = function() return db().enabled end,
                        set = function(_, value)
                            db().enabled = value
                            if value then party:Enable() else party:Disable() end
                        end,
                    },
                    showWhileSolo = {
                        name = 'Show while solo',
                        desc = 'Keep your player frame visible while you are not in a party. Other party rows remain hidden.',
                        type = 'toggle',
                        order = 3,
                        disabled = function() return not db().enabled end,
                        get = function() return db().showWhileSolo end,
                        set = function(_, value)
                            db().showWhileSolo = value
                            party:QueueProtectedState()
                        end,
                    },
                    smoothBars = {
                        name = 'Smooth health and power bars',
                        desc = 'Ease health and power changes over time instead of snapping to each new value.',
                        type = 'toggle',
                        order = 4,
                        disabled = function() return not db().enabled end,
                        get = function() return db().smoothBars end,
                        set = function(_, value)
                            db().smoothBars = value
                            party:RefreshAll()
                        end,
                    },
                },
            },
            layout = {
                name = 'Layout', type = 'group', inline = true, order = 3,
                args = addon.EditMode:GetLayoutOptions('Party'),
            },
            preview = {
                name = 'Preview', type = 'group', inline = true, order = 90,
                args = {
                    toggle = {
                        name = 'Toggle Party Preview',
                        desc = 'Toggle sample party frames on screen, even while solo.',
                        type = 'execute',
                        order = 5,
                        disabled = function() return not db().enabled end,
                        func = function() party:TogglePreview() end,
                    },
                },
            },
        },
    }
end
