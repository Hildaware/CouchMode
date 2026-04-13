local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM = LibStub('LibSharedMedia-3.0')

---@class TipsModule: AceModule
local tips = addon:NewModule('Tips', 'AceEvent-3.0')
---@cast tips +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────
local FONT_SIZE_BASE = 14
local TIP_W_DEFAULT = 240
local FONT_FLAGS = {
    [''] = 'None',
    ['OUTLINE'] = 'Outline',
    ['THICKOUTLINE'] = 'Thick Outline',
    ['MONOCHROME'] = 'Monochrome',
}

tips.TIP_W = TIP_W_DEFAULT
tips.addon = addon

--#endregion

--#region ── Font helpers ─────────────────────────────────────────────────────

local function tipsDB() return addon.db.profile.tips end

local function currentFont()
    local db = tipsDB()
    local fontSize = math.max(10, math.floor(FONT_SIZE_BASE * (tips.TIP_W / TIP_W_DEFAULT)))
    return LSM:Fetch(LSM.MediaType.FONT, db.font) or "Fonts\\ARIALN.TTF", fontSize, db.fontFlags or ""
end

local function currentSubFont()
    local path, fontSize = currentFont()
    return path, fontSize, ""
end

tips.currentFont = currentFont
tips.currentSubFont = currentSubFont
tips.tipsDB = tipsDB

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function tips:GetDefaults()
    return {
        tips = {
            enabled = true,
            showFriendlyNpcs = true,
            showEnemyNpcs = true,
            alwaysShowQuestObjectiveTips = true,
            alwaysShowImportant = false,
            shadowEnabled = true,
            font = 'Arial Narrow',
            fontFlags = '',
            width = TIP_W_DEFAULT,
            x = 0,
            y = -200,
            locked = true,
        },
    }
end

function tips:GetOptions()
    return 'tips', {
        name = 'Tips',
        type = 'group',
        order = 10,
        args = {
            description = {
                name = 'Custom unit tooltips for players and NPCs.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Show custom tooltip for targeted and moused-over units.',
                type = 'toggle',
                order = 2,
                get = function() return tipsDB().enabled end,
                set = function(_, value)
                    tipsDB().enabled = value
                    if value then tips:Enable() else tips:Disable() end
                end,
            },
            visibility = {
                name = 'Visibility',
                type = 'group',
                inline = true,
                order = 4,
                args = {
                    showFriendlyNpcs = {
                        name = 'Show Friendly NPC Tips',
                        desc = 'Show tooltip for friendly (non-attackable) NPCs.',
                        type = 'toggle',
                        order = 1,
                        get = function() return tipsDB().showFriendlyNpcs end,
                        set = function(_, value) tipsDB().showFriendlyNpcs = value end,
                    },
                    showEnemyNpcs = {
                        name = 'Show Enemy NPC Tips',
                        desc = 'Show tooltip for attackable NPCs.',
                        type = 'toggle',
                        order = 2,
                        get = function() return tipsDB().showEnemyNpcs end,
                        set = function(_, value) tipsDB().showEnemyNpcs = value end,
                    },
                    alwaysShowQuestObjectiveTips = {
                        name = 'Always Show Quest Objective Tips',
                        desc = 'Show tooltip for quest objective NPCs even when friendly or enemy tips are disabled.',
                        type = 'toggle',
                        width = 'full',
                        order = 3,
                        get = function() return tipsDB().alwaysShowQuestObjectiveTips end,
                        set = function(_, value) tipsDB().alwaysShowQuestObjectiveTips = value end,
                    },
                    alwaysShowImportant = {
                        name = 'Always Show Important',
                        desc = 'Always show tips for rares and elite rares even when NPC tips are disabled.',
                        type = 'toggle',
                        width = 'full',
                        order = 4,
                        get = function() return tipsDB().alwaysShowImportant end,
                        set = function(_, value) tipsDB().alwaysShowImportant = value end,
                    },
                },
            },
            appearance = {
                name = 'Appearance',
                type = 'group',
                inline = true,
                order = 3,
                args = {
                    lockToggle = {
                        name = function() return tipsDB().locked and 'Unlock Position' or 'Lock Position' end,
                        desc =
                        'Toggle the drag handle. While unlocked, a green border marks the frame and it can be freely dragged.',
                        type = 'execute',
                        order = 5,
                        func = function()
                            local db = tipsDB()
                            db.locked = not db.locked
                            tips.applyDock()
                        end,
                    },
                    font = {
                        name = 'Font',
                        type = 'select',
                        dialogControl = 'LSM30_Font',
                        order = 1,
                        values = LSM:HashTable(LSM.MediaType.FONT),
                        get = function() return tipsDB().font end,
                        set = function(_, value)
                            tipsDB().font = value
                            tips.applyFonts()
                        end,
                    },
                    fontFlags = {
                        name = 'Font Style',
                        type = 'select',
                        order = 3,
                        values = FONT_FLAGS,
                        get = function() return tipsDB().fontFlags end,
                        set = function(_, value)
                            tipsDB().fontFlags = value
                            tips.applyFonts()
                        end,
                    },
                    shadowEnabled = {
                        name = 'Drop Shadow',
                        desc = 'Add a drop shadow to all tip text.',
                        type = 'toggle',
                        order = 4,
                        get = function() return tipsDB().shadowEnabled end,
                        set = function(_, value)
                            tipsDB().shadowEnabled = value
                            tips.applyShadow()
                        end,
                    },
                    width = {
                        name = 'Max Width',
                        desc = 'Max width of the tooltip frame in pixels.',
                        type = 'range',
                        order = 2,
                        min = 120,
                        max = 500,
                        step = 1,
                        get = function() return tipsDB().width end,
                        set = function(_, value)
                            tipsDB().width = value
                            tips.applyWidth()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
