-- Defaults and settings for the existing ChatBubbles module.
local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local bubbles = addon:GetModule('ChatBubbles')

local function db() return addon.db.profile.chatBubbles end

local function toggleOption(name, desc, key, order)
    return {
        name = name, desc = desc, type = 'toggle', order = order,
        get = function() return db()[key] end,
        set = function(_, value)
            db()[key] = value
            bubbles:RefreshVisibleBubbles()
        end,
    }
end

local function fontOptions(name, prefix, order, automaticColorKey)
    local function set(suffix, value)
        db()[prefix .. suffix] = value
        bubbles:RefreshVisibleBubbles()
    end
    local args = {
        face = {
            name = 'Font', type = 'select', order = 1,
            values = addon.Media.GetFontOptions(),
            get = function() return db()[prefix .. 'FontFace'] end,
            set = function(_, value) set('FontFace', value) end,
        },
        size = {
            name = 'Size', type = 'range', order = 2, min = 8, max = 48, step = 1,
            get = function() return db()[prefix .. 'FontSize'] end,
            set = function(_, value) set('FontSize', value) end,
        },
        color = {
            name = 'Color', type = 'color', order = 3, hasAlpha = true,
            disabled = function() return automaticColorKey and db()[automaticColorKey] end,
            get = function()
                local c = db()[prefix .. 'FontColor']
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                set('FontColor', { r = r, g = g, b = b, a = a })
            end,
        },
        outline = {
            name = 'Outline', type = 'select', order = 4,
            values = { NONE = 'None', OUTLINE = 'Outline', THICKOUTLINE = 'Thick Outline' },
            get = function() return db()[prefix .. 'FontOutline'] end,
            set = function(_, value) set('FontOutline', value) end,
        },
        shadow = toggleOption('Shadow', 'Show a black drop shadow.', prefix .. 'FontShadow', 5),
    }
    if automaticColorKey then
        args.automaticColor = toggleOption('Color by Speech Type',
            'Use the speech type color, such as red for yells or pink for whispers.', automaticColorKey, 6)
    end
    return { name = name, type = 'group', inline = true, order = order, args = args }
end

--#region ── Defaults ─────────────────────────────────────────────────────────

function bubbles:GetDefaults()
    return {
        chatBubbles = {
            enabled = true,
            -- Overhead replacement is NPC-only and needs reskinning on.
            reskinBubbles = true,
            -- 'fallback' (only replace overhead, record failures) or 'always'.
            mode = 'fallback',
            -- Blizzard UI suppression
            disableTalkingHead = true,
            -- Sizing
            itemWidth = 340,
            offsetX = 0,
            offsetY = -24,
            scale = 1,
            clampToScreen = true,
            -- Name font
            nameFontFace = 'Arial Narrow',
            nameFontSize = 20,
            nameFontColor = { r = .902, g = .702, b = 0, a = 1 },
            nameFontOutline = 'OUTLINE',
            nameFontShadow = true,
            -- Message font
            msgFontFace = 'Arial Narrow',
            msgFontSize = 16,
            msgFontColor = { r = 1, g = 1, b = 0, a = 1 },
            msgFontOutline = 'OUTLINE',
            msgFontShadow = true,
            styleByType = true,
            enlargeYells = true,
            enlargeSingleLine = true,
            -- Text reveal
            revealText = false,
            revealSpeed = 44,
        },
    }
end

--#endregion

--#region ── Options ──────────────────────────────────────────────────────────

function bubbles:GetOptions()
    return 'chatBubbles', {
        name = 'Chat Bubbles',
        type = 'group',
        order = 30,
        args = {
            description = {
                name = 'Reskins NPC overhead speech bubbles with portraits and reveal animation. '
                    .. 'Messages it cannot replace are routed to the CouchMode Chat feed.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Replace NPC overhead speech bubbles.',
                type = 'toggle',
                order = 2,
                get = function() return db().enabled end,
                set = function(_, value)
                    db().enabled = value
                    if value then bubbles:Enable() else bubbles:Disable() end
                end,
            },
            misc = {
                name = 'Misc',
                type = 'group',
                inline = true,
                order = 99,
                args = {
                    openChat = {
                        name = 'Open Chat',
                        desc = 'Open the CouchMode Chat feed.',
                        type = 'execute',
                        order = 1,
                        func = function() addon.Chat:Toggle() end,
                    },
                    test = {
                        name = 'Test',
                        desc = 'Fire sample NPC messages to preview the overhead display.',
                        type = 'execute',
                        order = 2,
                        func = function()
                            addon.ChatMock.Run(addon.ChatRouter, 'npc', 3)
                        end,
                    },
                },
            },
            control = {
                name = 'Controls',
                type = 'group',
                inline = true,
                order = 4,
                args = {
                    disableTalkingHead = {
                        name = 'Hide Talking Head',
                        desc = 'Hide the Blizzard Talking Head frame while Chat Bubbles is active.',
                        type = 'toggle',
                        order = 1,
                        get = function() return db().disableTalkingHead end,
                        set = function(_, val)
                            db().disableTalkingHead = val
                            bubbles:ApplyTalkingHeadSuppression(val)
                        end,
                    },
                    mode = {
                        name = 'NPC Routing',
                        desc = 'Fallback only keeps successful overhead replacements out of Chat. '
                            .. 'Always record mirrors every NPC line into Chat as well.',
                        type = 'select',
                        style = 'dropdown',
                        order = 2,
                        values = {
                            ['fallback'] = 'Fallback only',
                            ['always'] = 'Always record',
                        },
                        get = function() return db().mode end,
                        set = function(_, val) db().mode = val end,
                    },
                },
            },
            positioning = {
                name = 'Positioning', type = 'group', inline = true, order = 4.5,
                args = {
                    offsetX = {
                        name = 'Horizontal Offset', desc = 'Move the bubble left or right of its NPC anchor.',
                        type = 'range', order = 1, min = -200, max = 200, step = 1,
                        get = function() return db().offsetX end,
                        set = function(_, value) db().offsetX = value; bubbles:RefreshVisibleBubbles() end,
                    },
                    offsetY = {
                        name = 'Vertical Offset', desc = 'Move the bubble above or below its NPC anchor.',
                        type = 'range', order = 2, min = -200, max = 200, step = 1,
                        get = function() return db().offsetY end,
                        set = function(_, value) db().offsetY = value; bubbles:RefreshVisibleBubbles() end,
                    },
                    scale = {
                        name = 'Scale', type = 'range', order = 3, min = .5, max = 2, step = .05,
                        get = function() return db().scale end,
                        set = function(_, value) db().scale = value; bubbles:RefreshVisibleBubbles() end,
                    },
                    clampToScreen = toggleOption('Keep on Screen',
                        'Keep the bubble and portrait within the screen edges.', 'clampToScreen', 4),
                },
            },
            nameStyling = fontOptions('NPC Name', 'name', 5),
            messageStyling = fontOptions('Message', 'msg', 7, 'styleByType'),
            messageBehavior = {
                name = 'Message Behavior', type = 'group', inline = true, order = 8,
                args = {
                    enlargeYells = toggleOption('Enlarge Yells', 'Increase the font size for NPC yells by 25%.',
                        'enlargeYells', 1),
                    enlargeSingleLine = toggleOption('Enlarge Short Messages',
                        'Increase the font size by 30% when the larger text fits on one line.', 'enlargeSingleLine', 2),
                    revealText = toggleOption('Reveal Text', 'Reveal message text character by character.',
                        'revealText', 3),
                    revealSpeed = {
                        name = 'Reveal Speed', desc = 'Characters revealed per second.',
                        type = 'range', order = 4, min = 10, max = 120, step = 5,
                        disabled = function() return not db().revealText end,
                        get = function() return db().revealSpeed end,
                        set = function(_, value) db().revealSpeed = value end,
                    },
                },
            },
        },
    }
end
