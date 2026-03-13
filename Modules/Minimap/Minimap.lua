local addonName      = ...

---@class ConsoleTools: AceAddon
local addon          = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class FadeState
---@field from    number
---@field to      number
---@field elapsed number
---@field active  boolean

---@class MinimapModule: AceModule
---@field minimapFade            FadeState
---@field worldMapFade           FadeState
---@field startFrameFade         fun(frame: Frame, state: FadeState, toAlpha: number)
---@field fadeTo                 number|nil
---@field fadeFrom               number
---@field fadeElapsed            number
---@field grown                  boolean
---@field worldMapOpen           boolean
---@field origParent             Frame|nil
---@field origW                  number
---@field origH                  number
---@field origPoints             table
---@field hybridMinimap          Frame|nil
---@field origCircleMaskTexture  string|nil
---@field rectMask               MaskTexture|nil
---@field growTransition         { active: boolean, elapsed: number, fromW: number, fromH: number, toW: number, toH: number, lastZoomAt: number }
---@field wrapper                Frame
---@field borderFrame            Frame
---@field borderTexT             Texture
---@field borderTexB             Texture
---@field borderTexL             Texture
---@field borderTexR             Texture
---@field applyBorder            fun()
---@field applySettings          fun()
---@field createFrame            fun()
---@field worldMap               Frame|nil
---@field worldMapArtW           number
---@field worldMapArtH           number
---@field resetWorldMapZoom      fun()
---@field openWorldMap           fun()
---@field closeWorldMap          fun()
local minimod        = addon:NewModule('Minimap')

minimod.minimapFade    = { from = 1, to = 1, elapsed = 0, active = false }
minimod.worldMapFade   = { from = 0, to = 0, elapsed = 0, active = false }
minimod.growTransition = { active = false, elapsed = 0, fromW = 0, fromH = 0, toW = 0, toH = 0, lastZoomAt = 0 }

function minimod.startFrameFade(frame, state, toAlpha)
    state.from    = frame:GetAlpha()
    state.to      = toAlpha
    state.elapsed = 0
    state.active  = true
end

--#region ── Module lifecycle ─────────────────────────────────────────────────

function minimod:OnEnable()
    if not minimod.wrapper then minimod.createFrame() end
    minimod.wrapper:Show()
end

function minimod:OnDisable()
    if minimod.worldMapOpen then minimod.closeWorldMap() end
    if minimod.wrapper then minimod.wrapper:Hide() end

    local ih = _G['ConsolePortInputHandler']
    if ih then ih:Release(minimod.wrapper) end

    if minimod.origParent then
        Minimap:SetParent(minimod.origParent)
        Minimap:ClearAllPoints()
        local pt, relFrame, relPt, ox, oy = unpack(minimod.origPoints)
        Minimap:SetPoint(pt, relFrame, relPt, ox, oy) ---@diagnostic disable-line: param-type-mismatch
        Minimap:SetSize(minimod.origW, minimod.origH)
        Minimap:SetClampedToScreen(true)
        Minimap:SetMaskTexture("Textures\\MinimapMask")

        local hybridMinimap = minimod.hybridMinimap ---@type any
        if hybridMinimap and hybridMinimap.MapCanvas and hybridMinimap.CircleMask then
            hybridMinimap:ClearAllPoints()
            hybridMinimap:SetAllPoints(Minimap)
            hybridMinimap.MapCanvas:SetMaskTexture(hybridMinimap.CircleMask)
            hybridMinimap.MapCanvas:SetUseMaskTexture(false)
            hybridMinimap.CircleMask:ClearAllPoints()
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
            if minimod.origCircleMaskTexture then
                hybridMinimap.CircleMask:SetTexture(minimod.origCircleMaskTexture)
            end
            hybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end

        ---@diagnostic disable-next-line: undefined-global
        MinimapCluster:Show()
        if MinimapBackdrop then MinimapBackdrop:Show() end ---@diagnostic disable-line: undefined-global

        minimod.origParent = nil
        minimod.grown      = false
        minimod.fadeTo     = nil
    end
end

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function minimod:GetDefaults()
    return {
        minimap = {
            enabled          = true,
            shape            = "rectangle",
            size             = 200,
            alpha            = 0.85,
            growSize         = 420,
            point            = "TOPRIGHT",
            x                = -20,
            y                = -20,
            moveAlphaEnabled = true,
            moveAlpha        = 0.3,
            borderEnabled    = false,
            borderSize       = 2,
            borderR          = 1,
            borderG          = 1,
            borderB          = 1,
            borderA          = 1,
        },
    }
end

function minimod:GetOptions()
    return 'minimap', {
        name  = 'Minimap',
        type  = 'group',
        order = 8,
        args  = {
            description = {
                name  = 'A clean, resizable minimap overlay. Drag to reposition. Scroll wheel to zoom.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Replace the default minimap chrome with the clean overlay.',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.minimap.enabled end,
                set   = function(_, value)
                    addon.db.profile.minimap.enabled = value
                    if value then minimod:Enable() else minimod:Disable() end
                end,
            },
            shape = {
                name   = 'Shape',
                desc   = 'Square: full square. Rectangle: wide letterbox.',
                type   = 'select',
                order  = 3,
                values = { square = 'Square', rectangle = 'Rectangle' },
                get    = function() return addon.db.profile.minimap.shape end,
                set    = function(_, value)
                    addon.db.profile.minimap.shape = value
                    minimod.applySettings()
                end,
            },
            size = {
                name  = 'Size',
                desc  = 'Normal minimap width in pixels.',
                type  = 'range',
                order = 4,
                min   = 100,
                max   = 500,
                step  = 10,
                get   = function() return addon.db.profile.minimap.size end,
                set   = function(_, value)
                    addon.db.profile.minimap.size = value
                    minimod.applySettings()
                end,
            },
            alpha = {
                name  = 'Opacity',
                desc  = 'Transparency of the minimap overlay.',
                type  = 'range',
                order = 5,
                min   = 0.1,
                max   = 1.0,
                step  = 0.05,
                get   = function() return addon.db.profile.minimap.alpha end,
                set   = function(_, value)
                    addon.db.profile.minimap.alpha = value
                    if minimod.wrapper then minimod.wrapper:SetAlpha(value) end
                end,
            },
            growSize = {
                name  = 'Grown Size',
                desc  = 'Width while the grow key is held.',
                type  = 'range',
                order = 6,
                min   = 200,
                max   = 800,
                step  = 10,
                get   = function() return addon.db.profile.minimap.growSize end,
                set   = function(_, value) addon.db.profile.minimap.growSize = value end,
            },
            moveAlphaEnabled = {
                name  = 'Fade on Move',
                desc  = 'Fade the minimap while the player is moving.',
                type  = 'toggle',
                order = 8,
                get   = function() return addon.db.profile.minimap.moveAlphaEnabled end,
                set   = function(_, value) addon.db.profile.minimap.moveAlphaEnabled = value end,
            },
            moveAlpha = {
                name  = 'Move Alpha',
                desc  = 'Opacity while the player is moving.',
                type  = 'range',
                order = 9,
                min   = 0.0,
                max   = 1.0,
                step  = 0.05,
                get   = function() return addon.db.profile.minimap.moveAlpha end,
                set   = function(_, value) addon.db.profile.minimap.moveAlpha = value end,
            },
            borderEnabled = {
                name  = 'Border',
                desc  = 'Show a colored border around the minimap and world map.',
                type  = 'toggle',
                order = 10,
                get   = function() return addon.db.profile.minimap.borderEnabled end,
                set   = function(_, value)
                    addon.db.profile.minimap.borderEnabled = value
                    minimod.applyBorder()
                end,
            },
            borderSize = {
                name  = 'Border Size',
                desc  = 'Border thickness in pixels.',
                type  = 'range',
                order = 11,
                min   = 1,
                max   = 20,
                step  = 1,
                get   = function() return addon.db.profile.minimap.borderSize end,
                set   = function(_, value)
                    addon.db.profile.minimap.borderSize = value
                    minimod.applyBorder()
                end,
            },
            borderColor = {
                name     = 'Border Color',
                type     = 'color',
                hasAlpha = true,
                order    = 12,
                get      = function()
                    local db = addon.db.profile.minimap
                    return db.borderR, db.borderG, db.borderB, db.borderA
                end,
                set      = function(_, r, g, b, a)
                    local db = addon.db.profile.minimap
                    db.borderR, db.borderG, db.borderB, db.borderA = r, g, b, a
                    minimod.applyBorder()
                end,
            },
        },
    }
end

--#endregion
