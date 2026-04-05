local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM        = LibStub('LibSharedMedia-3.0')

---@class TipsModule: AceModule
local tips       = addon:NewModule('Tips', 'AceEvent-3.0')
---@cast tips +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────
local FONT_SIZE  = 16

tips.TIP_W       = 240
tips.addon       = addon

--#endregion

--#region ── Font helpers ─────────────────────────────────────────────────────

local function tipsDB() return addon.db.profile.tips end

local function currentFont()
    local db = tipsDB()
    return LSM:Fetch(LSM.MediaType.FONT, db.font) or "Fonts\\ARIALN.TTF", FONT_SIZE, ""
end

local function currentSubFont()
    local path = currentFont()
    return path, FONT_SIZE, ""
end

tips.currentFont    = currentFont
tips.currentSubFont = currentSubFont
tips.tipsDB         = tipsDB

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function tips:GetDefaults()
    return {
        tips = {
            enabled          = true,
            showFriendlyNpcs = true,
            showEnemyNpcs    = true,
            font             = 'Arial Narrow',
            side             = 'RIGHT',
            y                = -200,
            locked           = true,
        },
    }
end

function tips:GetOptions()
    return 'tips', {
        name  = 'Tips',
        type  = 'group',
        order = 10,
        args  = {
            description = {
                name  = 'Custom unit tooltips for players and NPCs.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Show custom tooltip for targeted and moused-over units.',
                type  = 'toggle',
                order = 2,
                get   = function() return tipsDB().enabled end,
                set   = function(_, value)
                    tipsDB().enabled = value
                    if value then tips:Enable() else tips:Disable() end
                end,
            },
            showFriendlyNpcs = {
                name  = 'Show Friendly NPC Tips',
                desc  = 'Show tooltip for friendly (non-attackable) NPCs.',
                type  = 'toggle',
                order = 3,
                get   = function() return tipsDB().showFriendlyNpcs end,
                set   = function(_, value) tipsDB().showFriendlyNpcs = value end,
            },
            showEnemyNpcs = {
                name  = 'Show Enemy NPC Tips',
                desc  = 'Show tooltip for attackable NPCs.',
                type  = 'toggle',
                order = 4,
                get   = function() return tipsDB().showEnemyNpcs end,
                set   = function(_, value) tipsDB().showEnemyNpcs = value end,
            },
            position = {
                name   = 'Position',
                type   = 'group',
                inline = true,
                order  = 5,
                args   = {
                    side = {
                        name   = 'Side',
                        desc   = 'Which edge of the screen the tooltip docks to.',
                        type   = 'select',
                        order  = 1,
                        values = { LEFT = 'Left', RIGHT = 'Right' },
                        get    = function() return tipsDB().side end,
                        set    = function(_, value)
                            tipsDB().side = value
                            tips.applyDock()
                        end,
                    },
                    locked = {
                        name  = 'Lock Position',
                        desc  = 'Prevent the tooltip from being dragged.',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return tipsDB().locked end,
                        set   = function(_, value)
                            tipsDB().locked = value
                            tips.applyDock()
                        end,
                    },
                },
            },
            appearance = {
                name   = 'Appearance',
                type   = 'group',
                inline = true,
                order  = 6,
                args   = {
                    font = {
                        name          = 'Font',
                        type          = 'select',
                        dialogControl = 'LSM30_Font',
                        order         = 1,
                        values        = LSM:HashTable(LSM.MediaType.FONT),
                        get           = function() return tipsDB().font end,
                        set           = function(_, value)
                            tipsDB().font = value
                            tips.applyFonts()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
