local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class CastBar: AceModule
local castBar = addon:NewModule('CastBar')

-- ── Options ───────────────────────────────────────────────────────────────────

local ANCHOR_POINTS = {
    ['CENTER']      = 'Center',
    ['TOP']         = 'Top',
    ['BOTTOM']      = 'Bottom',
    ['LEFT']        = 'Left',
    ['RIGHT']       = 'Right',
    ['TOPLEFT']     = 'Top Left',
    ['TOPRIGHT']    = 'Top Right',
    ['BOTTOMLEFT']  = 'Bottom Left',
    ['BOTTOMRIGHT'] = 'Bottom Right',
}

local function ring() return addon:GetModule('CastRing') --[[@as CastRing]] end
local function bar() return addon:GetModule('PlayerCastBar') --[[@as PlayerCastBar]] end

function castBar:GetDefaults()
    return {
        castRing = {
            enabled             = true,
            size                = 128,
            xPos                = 0,
            yPos                = -150,
            locked              = false,
            hideBlizzardCastBar = false,
            showIcon            = true,
            showSpellName       = true,
            showTimer           = true,
            useClassColor       = false,
            attachToNameplate   = false,
            nameplateAnchor     = 'BOTTOM',
            nameplateRelative   = 'TOP',
            nameplateXOffset    = 0,
            nameplateYOffset    = 0,
            showSpark           = false,
            showBorder          = false,
            borderWidth         = 3,
            borderColor         = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            castColor           = { r = 0.8, g = 0.4, b = 0.0, a = 1.0 },
            channelColor        = { r = 0.0, g = 0.6, b = 1.0, a = 1.0 },
            frameStrata         = 'MEDIUM',
        },
        playerCastBar = {
            enabled       = true,
            width         = 250,
            height        = 24,
            xPos          = 0,
            yPos          = -200,
            locked        = false,
            showIcon      = true,
            showSpellName = true,
            showTimer     = true,
            showSpark     = true,
            showLatency   = true,
            alwaysShow    = false,
            useClassColor = false,
            castColor     = { r = 0.8, g = 0.4, b = 0.0, a = 1.0 },
            channelColor  = { r = 0.0, g = 0.6, b = 1.0, a = 1.0 },
        },
    }
end

function castBar:GetOptions()
    return 'castBars', {
        name        = 'Cast Bars',
        type        = 'group',
        order       = 1,
        childGroups = 'tab',
        args        = {

            -- ── Player Cast Bar ───────────────────────────────────────────────
            playerCastBar = {
                name  = 'Cast Bar',
                type  = 'group',
                order = 1,
                args  = {
                    description = {
                        name  =
                        'A standard horizontal cast bar for your character. Also acts as fallback when Cast Ring is set to attach to a nameplate but no target is present.',
                        type  = 'description',
                        order = 1,
                    },
                    enabled = {
                        name  = 'Enabled',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.playerCastBar.enabled end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.enabled = value
                            if value then bar():Enable() else bar():Disable() end
                        end,
                    },
                    general = {
                        name   = 'General',
                        type   = 'group',
                        order  = 3,
                        inline = true,
                        args   = {
                            width = {
                                name  = 'Width',
                                desc  = 'Width of the cast bar in pixels.',
                                type  = 'range',
                                order = 1,
                                min   = 80,
                                max   = 600,
                                step  = 2,
                                get   = function() return addon.db.profile.playerCastBar.width end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.width = value
                                    bar():Refresh()
                                end,
                            },
                            height = {
                                name  = 'Height',
                                desc  = 'Height of the cast bar in pixels.',
                                type  = 'range',
                                order = 2,
                                min   = 10,
                                max   = 60,
                                step  = 2,
                                get   = function() return addon.db.profile.playerCastBar.height end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.height = value
                                    bar():Refresh()
                                end,
                            },
                            locked = {
                                name  = 'Lock Position',
                                desc  = 'Prevent the bar from being dragged.',
                                type  = 'toggle',
                                order = 3,
                                get   = function() return addon.db.profile.playerCastBar.locked end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.locked = value
                                    bar():Refresh()
                                end,
                            },
                            alwaysShow = {
                                name  = 'Always Show Bar',
                                desc  =
                                'Show the cast bar even while the Cast Ring is active. By default the bar is hidden when the ring handles cast display.',
                                type  = 'toggle',
                                order = 4,
                                get   = function() return addon.db.profile.playerCastBar.alwaysShow end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.alwaysShow = value
                                end,
                            },
                            preview = {
                                name  = function()
                                    return bar().preview and 'Hide Preview' or 'Show Preview'
                                end,
                                desc  = 'Show or hide the cast bar so you can drag it into position.',
                                type  = 'execute',
                                order = 5,
                                func  = function() bar():TogglePreview() end,
                            },
                        },
                    },
                    display = {
                        name   = 'Display',
                        type   = 'group',
                        order  = 4,
                        inline = true,
                        args   = {
                            showIcon = {
                                name  = 'Show Spell Icon',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.playerCastBar.showIcon end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.showIcon = value
                                    bar():Refresh()
                                end,
                            },
                            showSpellName = {
                                name  = 'Show Spell Name',
                                type  = 'toggle',
                                order = 2,
                                get   = function() return addon.db.profile.playerCastBar.showSpellName end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.showSpellName = value
                                    bar():Refresh()
                                end,
                            },
                            showTimer = {
                                name  = 'Show Timer',
                                type  = 'toggle',
                                order = 3,
                                get   = function() return addon.db.profile.playerCastBar.showTimer end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.showTimer = value
                                    bar():Refresh()
                                end,
                            },
                            showSpark = {
                                name  = 'Show Spark',
                                type  = 'toggle',
                                order = 4,
                                get   = function() return addon.db.profile.playerCastBar.showSpark end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.showSpark = value
                                    bar():Refresh()
                                end,
                            },
                            showLatency = {
                                name  = 'Show Latency',
                                desc  = 'Show a red zone at the end of the bar indicating your network latency window.',
                                type  = 'toggle',
                                order = 5,
                                get   = function() return addon.db.profile.playerCastBar.showLatency end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.showLatency = value
                                    bar():Refresh()
                                end,
                            },
                        },
                    },
                    colors = {
                        name   = 'Colors',
                        type   = 'group',
                        order  = 5,
                        inline = true,
                        args   = {
                            useClassColor = {
                                name  = 'Use Class Color',
                                desc  = 'Color the bar with your class color instead of the custom cast/channel colors.',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.playerCastBar.useClassColor end,
                                set   = function(_, value)
                                    addon.db.profile.playerCastBar.useClassColor = value
                                end,
                            },
                            castColor = {
                                name     = 'Cast Color',
                                desc     = 'Fill color for regular casts.',
                                type     = 'color',
                                order    = 2,
                                hasAlpha = false,
                                disabled = function() return addon.db.profile.playerCastBar.useClassColor end,
                                get      = function()
                                    local c = addon.db.profile.playerCastBar.castColor
                                    return c.r, c.g, c.b
                                end,
                                set      = function(_, r, g, b)
                                    local c = addon.db.profile.playerCastBar.castColor
                                    c.r, c.g, c.b = r, g, b
                                end,
                            },
                            channelColor = {
                                name     = 'Channel Color',
                                desc     = 'Fill color for channeled spells.',
                                type     = 'color',
                                order    = 3,
                                hasAlpha = false,
                                disabled = function() return addon.db.profile.playerCastBar.useClassColor end,
                                get      = function()
                                    local c = addon.db.profile.playerCastBar.channelColor
                                    return c.r, c.g, c.b
                                end,
                                set      = function(_, r, g, b)
                                    local c = addon.db.profile.playerCastBar.channelColor
                                    c.r, c.g, c.b = r, g, b
                                end,
                            },
                        },
                    },
                },
            },

            -- ── Cast Ring ─────────────────────────────────────────────────────
            castRing = {
                name  = 'Cast Ring',
                type  = 'group',
                order = 2,
                args  = {
                    description = {
                        name  = 'A circular cast bar for your character. Drag it anywhere on screen (unless locked).',
                        type  = 'description',
                        order = 1,
                    },
                    enabled = {
                        name  = 'Enabled',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.castRing.enabled end,
                        set   = function(_, value)
                            addon.db.profile.castRing.enabled = value
                            if value then ring():Enable() else ring():Disable() end
                        end,
                    },
                    general = {
                        name   = 'General',
                        type   = 'group',
                        order  = 3,
                        inline = true,
                        args   = {
                            size = {
                                name  = 'Size',
                                desc  = 'Diameter of the ring in pixels.',
                                type  = 'range',
                                order = 1,
                                min   = 16,
                                max   = 256,
                                step  = 2,
                                get   = function() return addon.db.profile.castRing.size end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.size = value
                                    ring():Refresh()
                                end,
                            },
                            locked = {
                                name  = 'Lock Position',
                                desc  = 'Prevent the ring from being dragged.',
                                type  = 'toggle',
                                order = 2,
                                get   = function() return addon.db.profile.castRing.locked end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.locked = value
                                    ring():Refresh()
                                end,
                            },
                            hideBlizzardCastBar = {
                                name  = 'Hide Blizzard Cast Bar',
                                desc  = 'Hide the default Blizzard casting bar.',
                                type  = 'toggle',
                                order = 3,
                                get   = function() return addon.db.profile.castRing.hideBlizzardCastBar end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.hideBlizzardCastBar = value
                                    ring():ApplyCastBarHide()
                                end,
                            },
                            frameStrata = {
                                name   = 'Frame Strata',
                                desc   = 'Rendering layer of the ring. Raise this if other frames overlap it.',
                                type   = 'select',
                                order  = 4,
                                values = {
                                    BACKGROUND        = 'Background',
                                    LOW               = 'Low',
                                    MEDIUM            = 'Medium',
                                    HIGH              = 'High',
                                    DIALOG            = 'Dialog',
                                    FULLSCREEN        = 'Fullscreen',
                                    FULLSCREEN_DIALOG = 'Fullscreen Dialog',
                                    TOOLTIP           = 'Tooltip',
                                },
                                get    = function() return addon.db.profile.castRing.frameStrata end,
                                set    = function(_, value)
                                    addon.db.profile.castRing.frameStrata = value
                                    ring():Refresh()
                                end,
                            },
                            preview = {
                                name  = function()
                                    return ring().preview and 'Hide Preview' or 'Show Preview'
                                end,
                                desc  = 'Show or hide the cast ring so you can drag it into position.',
                                type  = 'execute',
                                order = 5,
                                func  = function() ring():TogglePreview() end,
                            },
                        },
                    },
                    nameplate = {
                        name   = 'Nameplate',
                        type   = 'group',
                        order  = 4,
                        inline = true,
                        args   = {
                            attachToNameplate = {
                                name  = 'Attach to Nameplate',
                                desc  =
                                'Move the cast ring to your target\'s nameplate while casting. Falls back to the Player Cast Bar when no nameplate is present.',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.castRing.attachToNameplate end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.attachToNameplate = value
                                    local pcb = addon:GetModule('PlayerCastBar', true)
                                    ---@diagnostic disable-next-line: undefined-field
                                    if pcb then pcb:SetCastRingMode(value) end
                                end,
                            },
                            nameplateAnchor = {
                                name     = 'Ring Anchor',
                                desc     = 'The point on the cast ring that attaches to the nameplate.',
                                type     = 'select',
                                order    = 2,
                                values   = ANCHOR_POINTS,
                                disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                                get      = function() return addon.db.profile.castRing.nameplateAnchor end,
                                set      = function(_, value)
                                    addon.db.profile.castRing.nameplateAnchor = value
                                    ring():UpdateNameplateAnchor()
                                end,
                            },
                            nameplateRelative = {
                                name     = 'Nameplate Anchor',
                                desc     = 'The point on the nameplate that the ring attaches to.',
                                type     = 'select',
                                order    = 3,
                                values   = ANCHOR_POINTS,
                                disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                                get      = function() return addon.db.profile.castRing.nameplateRelative end,
                                set      = function(_, value)
                                    addon.db.profile.castRing.nameplateRelative = value
                                    ring():UpdateNameplateAnchor()
                                end,
                            },
                            nameplateXOffset = {
                                name     = 'X Offset',
                                type     = 'range',
                                order    = 4,
                                min      = -200,
                                max      = 200,
                                step     = 1,
                                disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                                get      = function() return addon.db.profile.castRing.nameplateXOffset end,
                                set      = function(_, value)
                                    addon.db.profile.castRing.nameplateXOffset = value
                                    ring():UpdateNameplateAnchor()
                                end,
                            },
                            nameplateYOffset = {
                                name     = 'Y Offset',
                                type     = 'range',
                                order    = 5,
                                min      = -200,
                                max      = 200,
                                step     = 1,
                                disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                                get      = function() return addon.db.profile.castRing.nameplateYOffset end,
                                set      = function(_, value)
                                    addon.db.profile.castRing.nameplateYOffset = value
                                    ring():UpdateNameplateAnchor()
                                end,
                            },
                        },
                    },
                    display = {
                        name   = 'Display',
                        type   = 'group',
                        order  = 5,
                        inline = true,
                        args   = {
                            showIcon = {
                                name  = 'Show Spell Icon',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.castRing.showIcon end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.showIcon = value
                                    ring():Refresh()
                                end,
                            },
                            showSpellName = {
                                name  = 'Show Spell Name',
                                type  = 'toggle',
                                order = 2,
                                get   = function() return addon.db.profile.castRing.showSpellName end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.showSpellName = value
                                    ring():Refresh()
                                end,
                            },
                            showTimer = {
                                name  = 'Show Timer',
                                type  = 'toggle',
                                order = 3,
                                get   = function() return addon.db.profile.castRing.showTimer end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.showTimer = value
                                    ring():Refresh()
                                end,
                            },
                            showSpark = {
                                name  = 'Show Spark',
                                desc  = 'Show a bright edge at the leading edge of the cast sweep.',
                                type  = 'toggle',
                                order = 4,
                                get   = function() return addon.db.profile.castRing.showSpark end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.showSpark = value
                                    ring():Refresh()
                                end,
                            },
                        },
                    },
                    colors = {
                        name   = 'Colors',
                        type   = 'group',
                        order  = 6,
                        inline = true,
                        args   = {
                            useClassColor = {
                                name  = 'Use Class Color',
                                desc  = 'Color the ring with your class color instead of the custom cast/channel colors.',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.castRing.useClassColor end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.useClassColor = value
                                end,
                            },
                            castColor = {
                                name     = 'Cast Color',
                                desc     = 'Fill color for regular casts.',
                                type     = 'color',
                                order    = 2,
                                hasAlpha = false,
                                disabled = function() return addon.db.profile.castRing.useClassColor end,
                                get      = function()
                                    local c = addon.db.profile.castRing.castColor
                                    return c.r, c.g, c.b
                                end,
                                set      = function(_, r, g, b)
                                    local c = addon.db.profile.castRing.castColor
                                    c.r, c.g, c.b = r, g, b
                                    ring():Refresh()
                                end,
                            },
                            channelColor = {
                                name     = 'Channel Color',
                                desc     = 'Fill color for channeled spells.',
                                type     = 'color',
                                order    = 3,
                                hasAlpha = false,
                                disabled = function() return addon.db.profile.castRing.useClassColor end,
                                get      = function()
                                    local c = addon.db.profile.castRing.channelColor
                                    return c.r, c.g, c.b
                                end,
                                set      = function(_, r, g, b)
                                    local c = addon.db.profile.castRing.channelColor
                                    c.r, c.g, c.b = r, g, b
                                end,
                            },
                        },
                    },
                    border = {
                        name   = 'Border',
                        type   = 'group',
                        order  = 7,
                        inline = true,
                        args   = {
                            showBorder = {
                                name  = 'Show Border',
                                desc  = 'Show a colored outline around the outer edge of the ring.',
                                type  = 'toggle',
                                order = 1,
                                get   = function() return addon.db.profile.castRing.showBorder end,
                                set   = function(_, value)
                                    addon.db.profile.castRing.showBorder = value
                                    ring():Refresh()
                                end,
                            },
                            borderWidth = {
                                name     = 'Border Width',
                                desc     = 'Thickness of the border in pixels.',
                                type     = 'range',
                                order    = 2,
                                min      = 1,
                                max      = 10,
                                step     = 1,
                                disabled = function() return not addon.db.profile.castRing.showBorder end,
                                get      = function() return addon.db.profile.castRing.borderWidth end,
                                set      = function(_, value)
                                    addon.db.profile.castRing.borderWidth = value
                                    ring():Refresh()
                                end,
                            },
                            borderColor = {
                                name     = 'Border Color',
                                type     = 'color',
                                order    = 3,
                                hasAlpha = true,
                                disabled = function() return not addon.db.profile.castRing.showBorder end,
                                get      = function()
                                    local c = addon.db.profile.castRing.borderColor
                                    return c.r, c.g, c.b, c.a
                                end,
                                set      = function(_, r, g, b, a)
                                    local c = addon.db.profile.castRing.borderColor
                                    c.r, c.g, c.b, c.a = r, g, b, a
                                    ring():Refresh()
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

castBar:Enable()
