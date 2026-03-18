local addon_name       = ...

---@class ConsoleTools: AceAddon
local addon            = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule
local minimod          = addon:NewModule('Minimap')

local _G               = _G
local unpack           = unpack
local Minimap          = _G.Minimap
local MinimapCluster   = _G.MinimapCluster ---@type Frame

minimod.minimapFade    = { from = 1, to = 1, elapsed = 0, active = false }
minimod.worldMapFade   = { from = 0, to = 0, elapsed = 0, active = false }
minimod.toolbarFade    = { from = 0, to = 0, elapsed = 0, active = false }
minimod.growTransition = { active = false, elapsed = 0, fromW = 0, fromH = 0, toW = 0, toH = 0, lastZoomAt = 0 }

function minimod.startFrameFade(frame, state, to_alpha)
    state.from = frame:GetAlpha()
    state.to = to_alpha
    state.elapsed = 0
    state.active = true
end

--#region ── Module lifecycle ─────────────────────────────────────────────────

function minimod:OnEnable()
    if not minimod.wrapper then minimod.createFrame() end
    minimod.wrapper:Show()
end

function minimod:OnDisable()
    if minimod.worldMapOpen then minimod.closeWorldMap() end
    if minimod.wrapper then minimod.wrapper:Hide() end

    if minimod.origParent then
        Minimap:SetParent(minimod.origParent)
        Minimap:ClearAllPoints()
        Minimap:SetPoint(unpack(minimod.origPoints)) ---@diagnostic disable-line: param-type-mismatch
        Minimap:SetSize(minimod.origW, minimod.origH)
        Minimap:SetClampedToScreen(true)
        Minimap:SetMaskTexture("Textures\\MinimapMask")

        local hybrid_minimap = minimod.hybridMinimap ---@type any
        if hybrid_minimap and hybrid_minimap.MapCanvas and hybrid_minimap.CircleMask then
            hybrid_minimap:ClearAllPoints()
            hybrid_minimap:SetAllPoints(Minimap)
            hybrid_minimap.MapCanvas:SetMaskTexture(hybrid_minimap.CircleMask)
            hybrid_minimap.MapCanvas:SetUseMaskTexture(false)
            hybrid_minimap.CircleMask:ClearAllPoints()
            hybrid_minimap.CircleMask:SetAllPoints(hybrid_minimap.MapCanvas)
            if minimod.origCircleMaskTexture then
                hybrid_minimap.CircleMask:SetTexture(minimod.origCircleMaskTexture)
            end
            hybrid_minimap.MapCanvas:SetUseMaskTexture(true)
        end

        if minimod.blizzTracking then
            minimod.blizzTracking:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            minimod.blizzTracking = nil
        end

        if minimod.blizzCompartment then
            minimod.blizzCompartment:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            minimod.blizzCompartment = nil
        end

        if minimod.blizzCalendar then
            minimod.blizzCalendar:SetParent(MinimapCluster) ---@diagnostic disable-line: param-type-mismatch
            minimod.blizzCalendar = nil
        end

        ---@diagnostic disable-next-line: undefined-global
        MinimapCluster:Show()
        if _G.MinimapBackdrop then _G.MinimapBackdrop:Show() end ---@diagnostic disable-line: undefined-global

        minimod.origParent = nil
        minimod.grown = false
        minimod.fadeTo = nil
    end
end

--#endregion

--#region ── Defaults & Options ───────────────────────────────────────────────

function minimod:GetDefaults()
    return {
        ---@type MinimapDB
        minimap = {
            enabled                  = true,
            shape                    = "rectangle",
            size                     = 200,
            alpha                    = 0.85,
            growSize                 = 420,
            zoom                     = 2,
            growZoom                 = 3,
            point                    = "TOPRIGHT",
            x                        = -20,
            y                        = -20,
            moveAlphaEnabled         = true,
            moveAlpha                = 0.3,
            worldMapCentered         = false,
            worldMapShowWorldQuests  = true,
            worldMapShowActiveQuests = true,
            worldMapShowLocalStories = true,
            worldMapShowDungeons     = true,
            worldMapShowDelves       = true,
            worldMapShowEvents       = true,
            worldMapShowTravel       = true,
            toolbarDock              = "top",
            borderEnabled            = false,
            borderSize               = 2,
            borderR                  = 1,
            borderG                  = 1,
            borderB                  = 1,
            borderA                  = 1,
        },
    }
end

function minimod:GetOptions()
    return 'minimap', {
        name = 'Minimap',
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
                name = 'Size',
                desc = 'Normal minimap width in pixels.',
                type = 'range',
                order = 4,
                min = 100,
                max = 500,
                step = 10,
                get = function() return addon.db.profile.minimap.size end,
                set = function(_, value)
                    addon.db.profile.minimap.size = value
                    minimod.applySettings()
                end,
            },
            alpha = {
                name = 'Opacity',
                desc = 'Transparency of the minimap overlay.',
                type = 'range',
                order = 5,
                min = 0.1,
                max = 1.0,
                step = 0.05,
                get = function() return addon.db.profile.minimap.alpha end,
                set = function(_, value)
                    addon.db.profile.minimap.alpha = value
                    if minimod.wrapper then minimod.wrapper:SetAlpha(value) end
                end,
            },
            growSize = {
                name = 'Grown Size',
                desc = 'Width while the grow key is held.',
                type = 'range',
                order = 6,
                min = 200,
                max = 800,
                step = 10,
                get = function() return addon.db.profile.minimap.growSize end,
                set = function(_, value) addon.db.profile.minimap.growSize = value end,
            },
            -- zoom = {
            --     name  = 'Default Zoom',
            --     desc  = 'Zoom level when the minimap is at normal size.',
            --     type  = 'range',
            --     order = 7,
            --     min   = 0,
            --     max   = 5,
            --     step  = 1,
            --     get   = function() return addon.db.profile.minimap.zoom end,
            --     set   = function(_, value)
            --         addon.db.profile.minimap.zoom = value
            --         minimod.applyZoom()
            --     end,
            -- },
            -- growZoom = {
            --     name  = 'Grown Zoom',
            --     desc  = 'Zoom level when the minimap is grown.',
            --     type  = 'range',
            --     order = 8,
            --     min   = 0,
            --     max   = 5,
            --     step  = 1,
            --     get   = function() return addon.db.profile.minimap.growZoom end,
            --     set   = function(_, value)
            --         addon.db.profile.minimap.growZoom = value
            --         minimod.applyZoom()
            --     end,
            -- },
            worldMapCentered = {
                name = 'Map Centered World Map',
                desc = 'Center the world map on the map origin instead of the player.',
                type = 'toggle',
                order = 9,
                get = function() return addon.db.profile.minimap.worldMapCentered end,
                set = function(_, value) addon.db.profile.minimap.worldMapCentered = value end,
            },
            moveAlphaEnabled = {
                name = 'Fade on Move',
                desc = 'Fade the minimap while the player is moving.',
                type = 'toggle',
                order = 10,
                get = function() return addon.db.profile.minimap.moveAlphaEnabled end,
                set = function(_, value) addon.db.profile.minimap.moveAlphaEnabled = value end,
            },
            moveAlpha = {
                name = 'Move Alpha',
                desc = 'Opacity while the player is moving.',
                type = 'range',
                order = 11,
                min = 0.0,
                max = 1.0,
                step = 0.05,
                get = function() return addon.db.profile.minimap.moveAlpha end,
                set = function(_, value) addon.db.profile.minimap.moveAlpha = value end,
            },
            toolbarDock = {
                name   = 'Toolbar Position',
                desc   = 'Dock the toolbar above or below the minimap.',
                type   = 'select',
                order  = 12,
                values = { top = 'Top', bottom = 'Bottom' },
                get    = function() return addon.db.profile.minimap.toolbarDock end,
                set    = function(_, value)
                    addon.db.profile.minimap.toolbarDock = value
                    minimod.applyToolbarPosition()
                end,
            },
            borderEnabled = {
                name = 'Border',
                desc = 'Show a colored border around the minimap and world map.',
                type = 'toggle',
                order = 13,
                get = function() return addon.db.profile.minimap.borderEnabled end,
                set = function(_, value)
                    addon.db.profile.minimap.borderEnabled = value
                    minimod.applyBorder()
                end,
            },
            borderSize = {
                name = 'Border Size',
                desc = 'Border thickness in pixels.',
                type = 'range',
                order = 14,
                min = 1,
                max = 20,
                step = 1,
                get = function() return addon.db.profile.minimap.borderSize end,
                set = function(_, value)
                    addon.db.profile.minimap.borderSize = value
                    minimod.applyBorder()
                end,
            },
            borderColor = {
                name = 'Border Color',
                type = 'color',
                hasAlpha = true,
                order = 15,
                get = function()
                    local db = addon.db.profile.minimap ---@type MinimapDB
                    return db.borderR, db.borderG, db.borderB, db.borderA
                end,
                set = function(_, r, g, b, a)
                    local db = addon.db.profile.minimap ---@type MinimapDB
                    db.borderR, db.borderG, db.borderB, db.borderA = r, g, b, a
                    minimod.applyBorder()
                end,
            },
        },
    }
end

--#endregion
