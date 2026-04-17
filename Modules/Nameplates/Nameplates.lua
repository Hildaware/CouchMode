local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM = LibStub('LibSharedMedia-3.0')

---@class NameplatesModule: AceModule
local nameplates = addon:NewModule('Nameplates', 'AceEvent-3.0')
---@cast nameplates +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────

local BAR_W = 160
local BAR_H = 14
local CAST_W = math.floor(BAR_W * 2 / 3)
local CAST_H = 10
local AURA_W = 24
local AURA_H = 16
local AURA_GAP = 4
local AURA_MAX = 8
local PIP_W = 12
local PIP_H = 12
local PIP_GAP = 1
local PIP_MAX = 10

local BAR_TEX = "Interface\\Addons\\CouchMode\\Media\\basic_bar.tga"

local PlateType = { Full = 1, NameOnly = 2 }
nameplates.PlateType = PlateType

-- Exposed so sub-modules can reference the same values.
nameplates.BAR_W = BAR_W
nameplates.BAR_H = BAR_H
nameplates.CAST_W = CAST_W
nameplates.CAST_H = CAST_H
nameplates.AURA_W = AURA_W
nameplates.AURA_H = AURA_H
nameplates.AURA_GAP = AURA_GAP
nameplates.AURA_MAX = AURA_MAX
nameplates.PIP_W = PIP_W
nameplates.PIP_H = PIP_H
nameplates.PIP_GAP = PIP_GAP
nameplates.PIP_MAX = PIP_MAX
nameplates.BAR_TEX = BAR_TEX
nameplates.addon = addon

--#endregion

--#region ── Font helpers ─────────────────────────────────────────────────────

local FONT_FLAGS = {
    [''] = 'None',
    ['OUTLINE'] = 'Outline',
    ['THICKOUTLINE'] = 'Thick Outline',
    ['MONOCHROME'] = 'Monochrome',
}

local function npDB() return addon.db.profile.nameplates end

local function currentFont()
    local db = npDB()
    return LSM:Fetch(LSM.MediaType.FONT, db.font) or "Fonts\\ARIALN.TTF", db.fontSize, db.fontFlag
end

local function currentGuildFont()
    local path, size, flag = currentFont()
    return path, math.max(8, size - 4), flag
end

local function currentCastFont()
    local path, size, flag = currentFont()
    return path, math.max(8, size - 10), flag
end

nameplates.currentFont = currentFont
nameplates.currentGuildFont = currentGuildFont
nameplates.currentCastFont = currentCastFont

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function nameplates:GetDefaults()
    return {
        ---@type NameplatesDB
        nameplates = {
            enabled = true,
            font = 'Arial Narrow',
            fontSize = 16,
            fontFlag = 'OUTLINE',
            shadowEnabled = true,
            alwaysShowParty = false,
            alwaysShowPlayers = 'never',
            alwaysShowImportant = false,
            occludedAlpha = 0,
            disableSoftTargetFriendInCombat = false,
        },
    }
end

function nameplates:GetOptions()
    return 'nameplates', {
        name = 'Nameplates',
        type = 'group',
        order = 9,
        args = {
            description = {
                name = 'Custom nameplate overlays.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Show custom name and health bar on nameplates.',
                type = 'toggle',
                order = 2,
                get = function() return npDB().enabled end,
                set = function(_, value)
                    npDB().enabled = value
                    if value then nameplates:Enable() else nameplates:Disable() end
                end,
            },
            appearance = {
                name = 'Appearance',
                type = 'group',
                inline = true,
                order = 3,
                args = {
                    font = {
                        name = 'Font',
                        type = 'select',
                        dialogControl = 'LSM30_Font',
                        order = 1,
                        values = LSM:HashTable(LSM.MediaType.FONT),
                        get = function() return npDB().font end,
                        set = function(_, value)
                            npDB().font = value
                            nameplates.applyFontToAll()
                        end,
                    },
                    fontSize = {
                        name = 'Size',
                        type = 'range',
                        order = 2,
                        min = 8,
                        max = 32,
                        step = 1,
                        get = function() return npDB().fontSize end,
                        set = function(_, value)
                            npDB().fontSize = value
                            nameplates.applyFontToAll()
                        end,
                    },
                    fontFlag = {
                        name = 'Style',
                        type = 'select',
                        order = 3,
                        values = FONT_FLAGS,
                        get = function() return npDB().fontFlag end,
                        set = function(_, value)
                            npDB().fontFlag = value
                            nameplates.applyFontToAll()
                        end,
                    },
                    shadowEnabled = {
                        name = 'Drop Shadow',
                        desc = 'Add a drop shadow to all nameplate text.',
                        type = 'toggle',
                        order = 4,
                        get = function() return npDB().shadowEnabled end,
                        set = function(_, value)
                            npDB().shadowEnabled = value
                            nameplates.applyShadowToAll()
                        end,
                    },
                },
            },
            consoleVariables = {
                name = 'Console Variables',
                type = 'group',
                inline = true,
                order = 5,
                args = {
                    occludedAlpha = {
                        name = 'Occluded Alpha',
                        desc = 'Alpha of nameplates visible through walls. 0 hides them completely.',
                        type = 'range',
                        order = 1,
                        min = 0,
                        max = 1,
                        step = 0.05,
                        get = function() return npDB().occludedAlpha end,
                        set = function(_, value)
                            npDB().occludedAlpha = value
                            SetCVar("nameplateOccludedAlphaMult", value)
                        end,
                    },
                    softTargeting = {
                        name = 'Soft-Targeting',
                        type = 'group',
                        inline = true,
                        order = 2,
                        args = {
                            friendly = {
                                name = 'Friendly',
                                type = 'group',
                                inline = true,
                                order = 1,
                                args = {
                                    arc = {
                                        name = 'Arc',
                                        desc =
                                        'Direction from which a friendly unit can be soft-targeted. |n|nRecommended: In Front',
                                        type = 'select',
                                        order = 1,
                                        values = { [0] = 'None', [1] = 'In Front', [2] = 'Anywhere' },
                                        sorting = { 0, 1, 2 },
                                        get = function() return tonumber(GetCVar('SoftTargetFriendArc')) end,
                                        set = function(_, value) SetCVar('SoftTargetFriendArc', value) end,
                                    },
                                    range = {
                                        name = 'Range',
                                        desc =
                                        'Maximum yards at which a friendly unit can be soft-targeted. |n|nRecommended: 20',
                                        type = 'range',
                                        order = 2,
                                        min = 1,
                                        max = 60,
                                        step = 1,
                                        get = function() return tonumber(GetCVar('SoftTargetFriendRange')) end,
                                        set = function(_, value) SetCVar('SoftTargetFriendRange', value) end,
                                    },
                                    disableInCombat = {
                                        name = 'Disable in Combat',
                                        desc =
                                        'Disable friendly soft-targeting while in combat. Restores your setting when combat ends.',
                                        type = 'toggle',
                                        order = 3,
                                        get = function() return npDB().disableSoftTargetFriendInCombat end,
                                        set = function(_, value)
                                            npDB().disableSoftTargetFriendInCombat = value
                                        end,
                                    },
                                },
                            },
                            enemy = {
                                name = 'Enemy',
                                type = 'group',
                                inline = true,
                                order = 2,
                                args = {
                                    arc = {
                                        name = 'Arc',
                                        desc =
                                        'Direction from which an enemy unit can be soft-targeted. |n|nRecommended: In Front',
                                        type = 'select',
                                        order = 1,
                                        values = { [0] = 'None', [1] = 'In Front', [2] = 'Anywhere' },
                                        sorting = { 0, 1, 2 },
                                        get = function() return tonumber(GetCVar('SoftTargetEnemyArc')) end,
                                        set = function(_, value) SetCVar('SoftTargetEnemyArc', value) end,
                                    },
                                    range = {
                                        name = 'Range',
                                        desc =
                                        'Maximum yards at which an enemy unit can be soft-targeted. |n|nRecommended: 35',
                                        type = 'range',
                                        order = 2,
                                        min = 1,
                                        max = 60,
                                        step = 1,
                                        get = function() return tonumber(GetCVar('SoftTargetEnemyRange')) end,
                                        set = function(_, value) SetCVar('SoftTargetEnemyRange', value) end,
                                    },
                                },
                            },
                        },
                    },
                },
            },
            automation = {
                name = 'Visibility',
                type = 'group',
                inline = true,
                order = 4,
                args = {
                    alwaysShowParty = {
                        name = 'Always Show Party',
                        desc =
                        'Always show party members\' names on their nameplates. By default names are only shown when a party member is targeted or moused over.',
                        type = 'toggle',
                        order = 1,
                        get = function() return npDB().alwaysShowParty end,
                        set = function(_, value)
                            npDB().alwaysShowParty = value
                            nameplates.rebuildPartyGUIDs()
                            nameplates:OnInteractionChanged()
                        end,
                    },
                    alwaysShowPlayers = {
                        name = 'Show Players',
                        desc = 'When to show names on player nameplates.',
                        type = 'select',
                        order = 2,
                        values = { never = 'Never', cities = 'Cities Only', always = 'Always' },
                        sorting = { 'never', 'cities', 'always' },
                        get = function() return npDB().alwaysShowPlayers end,
                        set = function(_, value)
                            npDB().alwaysShowPlayers = value
                            nameplates:OnInteractionChanged()
                        end,
                    },
                    alwaysShowImportant = {
                        name = 'Always Show Important',
                        desc = 'Always show nameplates for rares, elites, and other important enemies.',
                        type = 'toggle',
                        order = 3,
                        get = function() return npDB().alwaysShowImportant end,
                        set = function(_, value)
                            npDB().alwaysShowImportant = value
                            nameplates:OnInteractionChanged()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
