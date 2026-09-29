local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule
local map = addon:NewModule('Minimap')

local EditMode = addon.EditMode

local _G = _G
local unpack = unpack
local Minimap = _G.Minimap
local MinimapCluster = _G.MinimapCluster ---@type Frame
local Animations = addon.Animations
local DEFAULT_FADE_DURATION = 0.25
local fadeAnimations = {}

map.minimapFade = { from = 1, to = 1, elapsed = 0, active = false, hideOnComplete = false }
map.worldMapFade = { from = 0, to = 0, elapsed = 0, active = false, hideOnComplete = false }
map.toolbarFade = { from = 0, to = 0, elapsed = 0, active = false, hideOnComplete = false }
map.containerFade = { from = 1, to = 1, elapsed = 0, active = false, hideOnComplete = false }
---@class MapGrowTransition
---@field active boolean
---@field elapsed number
---@field fromW number
---@field fromH number
---@field toW number
---@field toH number
---@field animShape string
---@field lastZoomAt number

---@type MapGrowTransition
map.growTransition = { active = false, elapsed = 0, fromW = 0, fromH = 0, toW = 0, toH = 0, animShape = "", lastZoomAt = 0 }

function map.cancelFrameFade(state)
    local animation = fadeAnimations[state]
    if animation then
        animation:Cancel()
        fadeAnimations[state] = nil
    end
    state.active = false
end

function map.startFrameFade(frame, state, to_alpha, hide_on_complete, duration)
    map.cancelFrameFade(state)
    state.from = frame:GetAlpha()
    state.to = to_alpha
    state.elapsed = 0
    state.active = true
    state.hideOnComplete = hide_on_complete or false

    local animation
    animation = Animations.Progress(map.container, duration or DEFAULT_FADE_DURATION, Animations.Linear,
        function(progress, _, elapsed)
            state.elapsed = elapsed
            frame:SetAlpha(state.from + (state.to - state.from) * progress)
        end,
        function()
            if fadeAnimations[state] == animation then
                fadeAnimations[state] = nil
                state.active = false
                if state.hideOnComplete then frame:Hide() end
            end
        end)
    fadeAnimations[state] = animation
end

--#region ── Module lifecycle ─────────────────────────────────────────────────

function map:OnEnable()
    if not addon.db.profile.minimap.enabled then
        self:Disable(); return
    end

    if not map.container then
        map.createFrame()

        local db = addon.db.profile.minimap ---@type MinimapDB
        local frame = map.container

        EditMode:RegisterFrame(frame, function(_, layoutName, point, x, y)
            if not layoutName then return end
            db.positions[layoutName] = { point = point, x = x, y = y }
        end, { point = 'TOPRIGHT', x = -20, y = -20 }, 'CouchMode Map')

        EditMode:RegisterFrameSettings(frame, {
            {
                kind = EditMode.SettingType.Dropdown,
                name = 'Shape',
                desc = 'Square: full square. Rectangle: wide letterbox.',
                default = 'rectangle',
                values = {
                    { text = 'Square',    value = 'square' },
                    { text = 'Rectangle', value = 'rectangle' },
                },
                get = function(_) return db.shape end,
                set = function(_, value, fromReset)
                    db.shape = fromReset and 'rectangle' or value
                    map.applySettings()
                end,
            },
            {
                kind = EditMode.SettingType.Slider,
                name = 'Size',
                desc = 'Normal minimap width in pixels.',
                default = 200,
                minValue = 100,
                maxValue = 500,
                valueStep = 10,
                get = function(_) return db.size end,
                set = function(_, value, fromReset)
                    db.size = fromReset and 200 or value
                    map.applySettings()
                end,
            },
        })

        EditMode:RegisterCallback('layout', function(layoutName)
            local pos = db.positions[layoutName]
            frame:ClearAllPoints()
            if pos then
                frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
            else
                frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
            end
        end)

        EditMode:RegisterCallback('enter', function()
            frame:Show()
        end)

        EditMode:RegisterCallback('exit', function()
            -- nothing to do; map visibility is managed by normal gameplay state
        end)
    end

    map.container:Show()
end

function map:OnDisable()
    if map.worldMapOpen then map.onHideWorldMap() end
    if map.container then map.container:Hide() end

    if map.origParent then
        Minimap:SetParent(map.origParent)
        Minimap:ClearAllPoints()
        Minimap:SetPoint(unpack(map.origPoints)) ---@diagnostic disable-line: param-type-mismatch
        Minimap:SetSize(map.origW, map.origH)
        Minimap:SetClampedToScreen(true)
        Minimap:SetMaskTexture("Textures\\MinimapMask")

        local hybrid_minimap = map.hybridMinimap ---@type any
        if hybrid_minimap then
            if hybrid_minimap.MapCanvas and hybrid_minimap.CircleMask then
                hybrid_minimap:ClearAllPoints()
                hybrid_minimap:SetAllPoints(Minimap)
                hybrid_minimap.MapCanvas:SetMaskTexture(hybrid_minimap.CircleMask)
                hybrid_minimap.MapCanvas:SetUseMaskTexture(false)
                hybrid_minimap.CircleMask:ClearAllPoints()
                hybrid_minimap.CircleMask:SetAllPoints(hybrid_minimap.MapCanvas)
                if map.origCircleMaskTexture then
                    hybrid_minimap.CircleMask:SetTexture(map.origCircleMaskTexture)
                end
                hybrid_minimap.MapCanvas:SetUseMaskTexture(true)
            end
            hybrid_minimap:Enable() ---@diagnostic disable-line: undefined-field
            map.hybridMinimap = nil
        end

        if map.blizzTracking then
            map.blizzTracking:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            map.blizzTracking = nil
        end

        if map.blizzCompartment then
            map.blizzCompartment:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            map.blizzCompartment = nil
        end

        if map.blizzCalendar then
            map.blizzCalendar:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            map.blizzCalendar = nil
        end

        if map.blizzInstanceDifficulty then
            map.blizzInstanceDifficulty:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            map.blizzInstanceDifficulty = nil
        end

        if map.blizzZoneText then
            map.blizzZoneText:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            map.blizzZoneText:Show()
            map.blizzZoneText = nil
        end

        ---@diagnostic disable-next-line: undefined-global
        MinimapCluster:Show()
        if MinimapCluster.BorderTop then MinimapCluster.BorderTop:Show() end ---@diagnostic disable-line: undefined-field
        if MinimapCluster.IndicatorFrame then MinimapCluster.IndicatorFrame:Show() end ---@diagnostic disable-line: undefined-field
        if _G.MinimapBackdrop then _G.MinimapBackdrop:Show() end ---@diagnostic disable-line: undefined-global

        map.origParent = nil
        map.grown = false
        map.cancelFrameFade(map.containerFade)
    end
end

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function map:GetDefaults()
    return {
        ---@type MinimapDB
        minimap = {
            enabled = true,
            shape = "rectangle",
            size = 200,
            alpha = 1.0,
            growSize = 600,
            growShape = "rectangle",
            locked = true,
            positions = {},
            zoom = 2,
            growZoom = 3,
            point = "TOPRIGHT",
            x = -20,
            y = -20,
            moveAlphaEnabled = false,
            moveAlpha = 0.3,
            worldMapCentered = true,
            worldMapShowWorldQuests = true,
            worldMapShowActiveQuests = true,
            worldMapShowLocalStories = true,
            worldMapShowDungeons = true,
            worldMapShowDelves = true,
            worldMapShowEvents = true,
            worldMapShowTravel = true,
            toolbarDock = "top",
            borderEnabled = true,
            borderR = 1,
            borderG = 1,
            borderB = 1,
            borderA = 1,
            poiLabelsEnabled = true,
            poiLabelsFontSize = 9,
            poiLabelsAlpha = 0.9,
            poiLabelsShowQuests = true,
            poiLabelsShowRares = true,
            poiLabelsShowTreasures = true,
            poiLabelsShowPetTamers = true,
            zoneTextEnabled = false,
            zoneTextFont = "Fonts\\FRIZQT__.TTF",
            zoneTextSize = 11,
            zoneTextX = 0,
            zoneTextY = 30,
            zoneTextR = 1,
            zoneTextG = 1,
            zoneTextB = 1,
            zoneTextA = 1,
        },
    }
end

function map:GetOptions()
    return 'minimap', {
        name = 'Map',
        type = 'group',
        order = 8,
        args = {
            description = {
                name = 'A clean, resizable minimap overlay. Drag to reposition. Scroll wheel to zoom.',
                type = 'description',
                order = 1,
            },
            enabled = {
                name = 'Enable',
                desc = 'Replace the default minimap chrome with the clean overlay.',
                type = 'toggle',
                order = 2,
                get = function() return addon.db.profile.minimap.enabled end,
                set = function(_, value)
                    addon.db.profile.minimap.enabled = value
                    if value then map:Enable() else map:Disable() end
                end,
            },
            appearance = {
                name = 'Appearance',
                type = 'group',
                inline = true,
                order = 3,
                args = {
                    alpha = {
                        name = 'Opacity',
                        desc = 'Transparency of the minimap overlay.',
                        type = 'range',
                        order = 1,
                        min = 0.1,
                        max = 1.0,
                        step = 0.05,
                        get = function() return addon.db.profile.minimap.alpha end,
                        set = function(_, value)
                            addon.db.profile.minimap.alpha = value
                            if map.container then map.container:SetAlpha(value) end
                        end,
                    },
                },
            },
            expandedView = {
                name = 'Expanded View',
                type = 'group',
                inline = true,
                order = 4,
                args = {
                    growShape = {
                        name = 'Shape',
                        desc = 'Minimap shape when expanded.',
                        type = 'select',
                        order = 1,
                        values = { square = 'Square', rectangle = 'Rectangle' },
                        get = function() return addon.db.profile.minimap.growShape end,
                        set = function(_, value)
                            addon.db.profile.minimap.growShape = value
                            if map.grown then map.applySettings() end
                        end,
                    },
                    growSize = {
                        name = 'Size',
                        desc = 'Width when the minimap is expanded.',
                        type = 'range',
                        order = 2,
                        min = 200,
                        max = 1600,
                        step = 10,
                        get = function() return addon.db.profile.minimap.growSize end,
                        set = function(_, value) addon.db.profile.minimap.growSize = value end,
                    },
                },
            },
            worldMap = {
                name = 'World Map',
                type = 'group',
                inline = true,
                order = 5,
                args = {
                    worldMapCentered = {
                        name = 'Map-Centered',
                        desc = 'Center the world map on the map origin instead of the player.',
                        type = 'toggle',
                        order = 1,
                        get = function() return addon.db.profile.minimap.worldMapCentered end,
                        set = function(_, value) addon.db.profile.minimap.worldMapCentered = value end,
                    },
                },
            },
            fadeOnMove = {
                name = 'Fade on Move',
                type = 'group',
                inline = true,
                order = 6,
                args = {
                    moveAlphaEnabled = {
                        name = 'Enable',
                        desc = 'Fade the minimap while the player is moving.',
                        type = 'toggle',
                        order = 1,
                        get = function() return addon.db.profile.minimap.moveAlphaEnabled end,
                        set = function(_, value) addon.db.profile.minimap.moveAlphaEnabled = value end,
                    },
                    moveAlpha = {
                        name = 'Opacity',
                        desc = 'Opacity while the player is moving.',
                        type = 'range',
                        order = 2,
                        min = 0.0,
                        max = 1.0,
                        step = 0.05,
                        disabled = function() return not addon.db.profile.minimap.moveAlphaEnabled end,
                        get = function() return addon.db.profile.minimap.moveAlpha end,
                        set = function(_, value) addon.db.profile.minimap.moveAlpha = value end,
                    },
                },
            },
            toolbar = {
                name = 'Toolbar',
                type = 'group',
                inline = true,
                order = 7,
                args = {
                    toolbarDock = {
                        name = 'Position',
                        desc = 'Dock the toolbar above or below the minimap.',
                        type = 'select',
                        order = 1,
                        values = { top = 'Top', bottom = 'Bottom' },
                        get = function() return addon.db.profile.minimap.toolbarDock end,
                        set = function(_, value)
                            addon.db.profile.minimap.toolbarDock = value
                            map.applyToolbarPosition()
                        end,
                    },
                },
            },
            border = {
                name = 'Border',
                type = 'group',
                inline = true,
                order = 8,
                args = {
                    borderEnabled = {
                        name = 'Enable',
                        desc = 'Show Blizzard-style panel chrome around the minimap and world map.',
                        type = 'toggle',
                        order = 1,
                        get = function() return addon.db.profile.minimap.borderEnabled end,
                        set = function(_, value)
                            addon.db.profile.minimap.borderEnabled = value
                            map.applyBorder()
                        end,
                    },
                    borderColor = {
                        name = 'Color',
                        type = 'color',
                        hasAlpha = true,
                        order = 2,
                        disabled = function() return not addon.db.profile.minimap.borderEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.borderR, db.borderG, db.borderB, db.borderA
                        end,
                        set = function(_, r, g, b, a)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.borderR, db.borderG, db.borderB, db.borderA = r, g, b, a
                            map.applyBorder()
                        end,
                    },
                },
            },
            zoneText = {
                name = 'Zone Text',
                type = 'group',
                inline = true,
                order = 9,
                args = {
                    enabled = {
                        name = 'Enable',
                        type = 'toggle',
                        order = 1,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextEnabled
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextEnabled = value
                            map.applyZoneText()
                        end,
                    },
                    font = {
                        name = 'Font',
                        type = 'select',
                        order = 2,
                        disabled = function() return not addon.db.profile.minimap.zoneTextEnabled end,
                        values = {
                            ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata",
                            ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
                            ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
                            ["Fonts\\SKURRI.TTF"] = "Skurri",
                        },
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextFont
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextFont = value
                            map.applyZoneText()
                        end,
                    },
                    size = {
                        name = 'Font Size',
                        type = 'range',
                        order = 3,
                        min = 8,
                        max = 24,
                        step = 1,
                        disabled = function() return not addon.db.profile.minimap.zoneTextEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextSize
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextSize = value
                            map.applyZoneText()
                        end,
                    },
                    color = {
                        name = 'Color',
                        type = 'color',
                        hasAlpha = false,
                        order = 4,
                        disabled = function() return not addon.db.profile.minimap.zoneTextEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextR, db.zoneTextG, db.zoneTextB
                        end,
                        set = function(_, r, g, b)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextR, db.zoneTextG, db.zoneTextB = r, g, b
                            map.applyZoneText()
                        end,
                    },
                    xOffset = {
                        name = 'X Offset',
                        type = 'range',
                        order = 5,
                        min = -200,
                        max = 200,
                        step = 1,
                        disabled = function() return not addon.db.profile.minimap.zoneTextEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextX
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextX = value
                            map.applyZoneText()
                        end,
                    },
                    yOffset = {
                        name = 'Y Offset',
                        type = 'range',
                        order = 6,
                        min = -200,
                        max = 200,
                        step = 1,
                        disabled = function() return not addon.db.profile.minimap.zoneTextEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.zoneTextY
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.zoneTextY = value
                            map.applyZoneText()
                        end,
                    },
                },
            },
            poiLabels = {
                name = 'POI Labels',
                type = 'group',
                inline = true,
                order = 10,
                args = {
                    enabled = {
                        name = 'Enable',
                        desc = 'Show quest objective and rare/vignette names as labels on the minimap.',
                        type = 'toggle',
                        order = 1,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.poiLabelsEnabled
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.poiLabelsEnabled = value
                            map.applyPOILabels()
                        end,
                    },
                    fontSize = {
                        name = 'Font Size',
                        type = 'range',
                        order = 2,
                        min = 7,
                        max = 16,
                        step = 1,
                        disabled = function() return not addon.db.profile.minimap.poiLabelsEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.poiLabelsFontSize
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.poiLabelsFontSize = value
                            map.applyPOILabels()
                        end,
                    },
                    alpha = {
                        name = 'Opacity',
                        type = 'range',
                        order = 3,
                        min = 0.1,
                        max = 1.0,
                        step = 0.05,
                        disabled = function() return not addon.db.profile.minimap.poiLabelsEnabled end,
                        get = function()
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            return db.poiLabelsAlpha
                        end,
                        set = function(_, value)
                            local db = addon.db.profile.minimap ---@type MinimapDB
                            db.poiLabelsAlpha = value
                            map.applyPOILabels()
                        end,
                    },
                },
            },
        },
    }
end

--#endregion
