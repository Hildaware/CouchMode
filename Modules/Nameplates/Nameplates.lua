local addon_name     = ...

---@class CouchMode: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addon_name)
local LSM            = LibStub('LibSharedMedia-3.0')

---@class NameplatesModule: AceModule
local nameplates     = addon:NewModule('Nameplates', 'AceEvent-3.0')
---@cast nameplates +AceEvent-3.0

--#region ── Constants ────────────────────────────────────────────────────────

local BAR_W          = 160
local BAR_H          = 14
local CAST_W         = math.floor(BAR_W * 2 / 3)
local CAST_H         = 10
local AURA_W         = 24
local AURA_H         = 16
local AURA_GAP       = 4
local AURA_MAX       = 8
local PIP_W          = 12
local PIP_H          = 12
local PIP_GAP        = 1
local PIP_MAX        = 10

local BAR_TEX        = "Interface\\Addons\\CouchMode\\Media\\basic_bar.tga"

local PlateType      = { Full = 1, NameOnly = 2 }
nameplates.PlateType = PlateType

-- Exposed so sub-modules can reference the same values.
nameplates.BAR_W     = BAR_W
nameplates.BAR_H     = BAR_H
nameplates.CAST_W    = CAST_W
nameplates.CAST_H    = CAST_H
nameplates.AURA_W    = AURA_W
nameplates.AURA_H    = AURA_H
nameplates.AURA_GAP  = AURA_GAP
nameplates.AURA_MAX  = AURA_MAX
nameplates.PIP_W     = PIP_W
nameplates.PIP_H     = PIP_H
nameplates.PIP_GAP   = PIP_GAP
nameplates.PIP_MAX   = PIP_MAX
nameplates.BAR_TEX   = BAR_TEX
nameplates.addon     = addon

--#endregion

--#region ── Font helpers ─────────────────────────────────────────────────────

local FONT_FLAGS     = {
    ['']             = 'None',
    ['OUTLINE']      = 'Outline',
    ['THICKOUTLINE'] = 'Thick Outline',
    ['MONOCHROME']   = 'Monochrome',
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
    return path, math.max(8, size - 8), flag
end

nameplates.currentFont      = currentFont
nameplates.currentGuildFont = currentGuildFont
nameplates.currentCastFont  = currentCastFont

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function nameplates:GetDefaults()
    return {
        ---@type NameplatesDB
        nameplates = {
            enabled  = true,
            font     = 'Arial Narrow',
            fontSize = 16,
            fontFlag = 'OUTLINE',
        },
    }
end

function nameplates:GetOptions()
    return 'nameplates', {
        name  = 'Nameplates',
        type  = 'group',
        order = 9,
        args  = {
            description = {
                name  = 'Custom nameplate overlays.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Show custom name and health bar on nameplates.',
                type  = 'toggle',
                order = 2,
                get   = function() return npDB().enabled end,
                set   = function(_, value)
                    npDB().enabled = value
                    if value then nameplates:Enable() else nameplates:Disable() end
                end,
            },
            appearance = {
                name   = 'Appearance',
                type   = 'group',
                inline = true,
                order  = 3,
                args   = {
                    font = {
                        name          = 'Font',
                        type          = 'select',
                        dialogControl = 'LSM30_Font',
                        order         = 1,
                        values        = LSM:HashTable(LSM.MediaType.FONT),
                        get           = function() return npDB().font end,
                        set           = function(_, value)
                            npDB().font = value
                            nameplates.applyFontToAll()
                        end,
                    },
                    fontSize = {
                        name  = 'Size',
                        type  = 'range',
                        order = 2,
                        min   = 8,
                        max   = 32,
                        step  = 1,
                        get   = function() return npDB().fontSize end,
                        set   = function(_, value)
                            npDB().fontSize = value
                            nameplates.applyFontToAll()
                        end,
                    },
                    fontFlag = {
                        name   = 'Style',
                        type   = 'select',
                        order  = 3,
                        values = FONT_FLAGS,
                        get    = function() return npDB().fontFlag end,
                        set    = function(_, value)
                            npDB().fontFlag = value
                            nameplates.applyFontToAll()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
