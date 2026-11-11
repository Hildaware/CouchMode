local addonName, addon = ...
addon = addon or LibStub('AceAddon-3.0'):GetAddon(addonName)
local toasts = addon.Toasts

local function db() return addon.db.profile.toasts end
local PANEL_ORDER = toasts.PANEL_ORDER
local DEFAULT_WIDTH = toasts.DEFAULT_WIDTH
local DEFAULT_MAX_ITEMS = toasts.DEFAULT_MAX_ITEMS
local MAX_ITEMS_LIMIT = toasts.MAX_ITEMS_LIMIT
local FADE_DELAY_DESC = toasts.FADE_DELAY_DESC

--#region ── Defaults ─────────────────────────────────────────────────────────

function toasts:GetDefaults()
    return {
        toasts = {
            enabled = true,
            -- Position (per Edit Mode layout)
            positions = {},
            -- Sizing / appearance
            width = DEFAULT_WIDTH,
            maxItems = DEFAULT_MAX_ITEMS,
            activeOpacity = 1,
            fadeDelay = 15,
            fontFace = 'Arial Narrow',
            fontSize = 14,
            -- Reward categories
            items = true,
            money = true,
            currency = true,
            reputation = true,
            system = true,
            filterJunk = true,
        },
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function toasts:NotifyChange()
    local registry = LibStub('AceConfigRegistry-3.0', true)
    if registry then registry:NotifyChange(addonName) end
end

function toasts:BuildArgs()
    return {
        description = {
            name = 'A live feed for rewards and system messages. Recognized lines are removed '
                .. 'from Blizzard chat while their Toasts category is enabled. System messages are '
                .. 'also removed from CouchMode Chat when both Toasts and this category are enabled.',
            type = 'description',
            order = 1,
        },
        general = {
            name = 'General', type = 'group', inline = true, order = 2,
            args = {
                enabled = {
                    name = 'Enable',
                    desc = 'Show Toasts and hide recognized lines from Blizzard chat.',
                    type = 'toggle',
                    order = 0,
                    get = function() return db().enabled end,
                    set = function(_, value)
                        db().enabled = value
                        if value then toasts:Enable() else toasts:Disable() end
                    end,
                },
                maxItems = {
                    name = 'Max Items',
                    desc = 'Maximum number of active toast rows shown at once. Additional rewards wait in the queue.',
                    type = 'range', min = 1, max = MAX_ITEMS_LIMIT, step = 1, order = 2,
                    get = function() return db().maxItems or DEFAULT_MAX_ITEMS end,
                    set = function(_, value)
                        db().maxItems = value
                        if toasts.feed then toasts.feed:TrimToCount(value) end
                        toasts:ApplyLayout()
                        if toasts:HasQueuedEntries() then toasts:SchedulePresentationQueue(0) end
                    end,
                },
                fadeDelay = {
                    name = 'Fade Delay', desc = FADE_DELAY_DESC,
                    type = 'range', min = 0, max = 120, step = 1, order = 6,
                    get = function() return db().fadeDelay end,
                    set = function(_, value) db().fadeDelay = value; toasts:Touch() end,
                },
                filterJunk = {
                    name = 'Filter Junk',
                    desc = 'Hide repetitive action errors such as “Out of range” and “You have no target.”',
                    type = 'toggle', order = 12,
                    get = function() return db().filterJunk end,
                    set = function(_, value) db().filterJunk = value end,
                },
            },
        },
        layout = {
            name = 'Layout', type = 'group', inline = true, order = 3,
            args = addon.EditMode:GetLayoutOptions('Toasts'),
        },
        appearance = {
            name = 'Appearance', type = 'group', inline = true, order = 4,
            args = {
                activeOpacity = {
                    name = 'Active Opacity', desc = 'Feed opacity while at least one reward is visible.',
                    type = 'range', min = 0.1, max = 1, step = 0.05, order = 4,
                    get = function() return db().activeOpacity end,
                    set = function(_, value) db().activeOpacity = value; toasts:Touch() end,
                },
                fontFace = {
                    name = 'Font', desc = 'Font used for reward text.',
                    type = 'select', style = 'dropdown', order = 8,
                    values = addon.Media.GetFontOptions(),
                    get = function() return db().fontFace end,
                    set = function(_, value) db().fontFace = value; toasts:ApplyFont() end,
                },
                fontSize = {
                    name = 'Font Size', desc = 'Reward text size.',
                    type = 'range', min = 8, max = 28, step = 1, order = 9,
                    get = function() return db().fontSize end,
                    set = function(_, value) db().fontSize = value; toasts:ApplyFont() end,
                },
            },
        },
        rewards = {
            name = 'Reward Categories', type = 'group', inline = true, order = 5,
            args = {
                items = {
                    name = 'Items', desc = 'Items looted by you.',
                    type = 'toggle', order = 1,
                    get = function() return db().items end,
                    set = function(_, value) db().items = value end,
                },
                money = {
                    name = 'Money', desc = 'Money you gain.',
                    type = 'toggle', order = 2,
                    get = function() return db().money end,
                    set = function(_, value) db().money = value end,
                },
                currency = {
                    name = 'Currency', desc = 'Currency you gain.',
                    type = 'toggle', order = 3,
                    get = function() return db().currency end,
                    set = function(_, value) db().currency = value end,
                },
                reputation = {
                    name = 'Reputation', desc = 'Reputation increases.',
                    type = 'toggle', order = 4,
                    get = function() return db().reputation end,
                    set = function(_, value) db().reputation = value end,
                },
                system = {
                    name = 'System Messages',
                    desc = 'Show system messages in a distinct toast style instead of duplicating them in CouchMode Chat.',
                    type = 'toggle', order = 11,
                    get = function() return db().system end,
                    set = function(_, value) db().system = value end,
                },
            },
        },
        preview = {
            name = 'Preview', type = 'group', inline = true, order = 90,
            args = {
                testRewards = {
                    name = 'Preview Rewards',
                    desc = 'Fire mock toasts for every category.\n\nAlso available as /cm toasts mock.',
                    type = 'execute', order = 1,
                    func = function() toasts:RunMock('all') end,
                },
            },
        },
    }
end

function toasts:GetOptions()
    self.optionsArgs = self.optionsArgs or self:BuildArgs()
    return 'toasts', {
        name = 'Toasts',
        type = 'group',
        order = PANEL_ORDER,
        args = self.optionsArgs,
    }
end

--#endregion
