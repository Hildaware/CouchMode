local addon_name          = ...

---@class ConsoleTools: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map                 = addon:GetModule('Minimap')

local _G                  = _G
local math_min            = math.min
local math_max            = math.max
local math_floor          = math.floor
local math_ceil           = math.ceil

local Minimap             = _G.Minimap
local UIParent            = _G.UIParent
local InCombatLockdown    = _G.InCombatLockdown
local MinimapCluster      = _G.MinimapCluster ---@type Frame

local ConsolePort         = _G['ConsolePort'] ---@type any

local GROW_DURATION       = 0.5

local RECT_MASK           = "Interface\\AddOns\\ConsoleTools\\Media\\3-2.blp"

--#region ── Shape & masking ──────────────────────────────────────────────────

local function size_for_shape(shape, size)
    if shape == "rectangle" then
        return size, math_floor(size * (2 / 3))
    end
    return size, size
end

local function mask_for_shape(shape)
    if shape == "square" then
        return "Interface\\BUTTONS\\WHITE8X8"
    elseif shape == "rectangle" then
        return RECT_MASK
    end
    return nil -- circle: pass nil to restore Blizzard's native circular mask
end

local function apply_minimap_shape(shape, w, h)
    Minimap:SetMaskTexture(mask_for_shape(shape))

    if shape == "rectangle" then
        local half_diff = math_ceil((w - h) / 2)
        Minimap:SetHitRectInsets(0, 0, half_diff, half_diff)
    else
        Minimap:SetHitRectInsets(0, 0, 0, 0)
    end
end

--#endregion

--#region ── Border & settings ────────────────────────────────────────────────

function map.applyBorder()
    if not map.borders then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local show = db.borderEnabled
    local size = db.borderSize
    local r, g, b, a = db.borderR, db.borderG, db.borderB, db.borderA

    map.MapUtils.apply_border_textures(map.container, map.borders, show, size, r, g, b, a)
    if map.toolbarBorders then
        map.MapUtils.apply_border_textures(map.toolbar, map.toolbarBorders, show, size, r, g, b, a)
        if show then
            -- Hide the edge shared with the minimap container
            map.toolbarBorders[db.toolbarDock == "bottom" and "T" or "B"]:Hide()
        end
    end
end

function map.applyZoom()
    if not map.container then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local target = map.grown and db.growZoom or db.zoom
    local max_zoom = Minimap:GetZoomLevels() - 1
    -- Minimap:SetZoom(math_min(target, max_zoom))
end

function map.applySettings()
    if not map.container then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local size = map.grown and db.growSize or db.size
    local w, h = size_for_shape(db.shape, size)

    map.container:SetSize(w, h)
    map.container:SetAlpha(db.alpha)
    local offset = math_ceil((w - h) / 2)
    map.container:SetClampedToScreen(true)
    map.container:SetClampRectInsets(0, 0, offset, offset)
    Minimap:ClearAllPoints()
    Minimap:SetPoint('TOPRIGHT', map.container, 'TOPRIGHT', 0, offset)
    apply_minimap_shape(db.shape, w, h)
    map.applyBorder()
end

function map.updateGrowTransition(elapsed)
    local gt = map.growTransition
    if not gt.active then return end

    gt.elapsed = gt.elapsed + elapsed
    local t  = math_min(1, gt.elapsed / GROW_DURATION)
    local ts = t * t * (3 - 2 * t) -- smoothstep easing
    local cw = gt.fromW + (gt.toW - gt.fromW) * ts
    local ch = gt.fromH + (gt.toH - gt.fromH) * ts
    local off = math_ceil((cw - ch) / 2)
    map.container:SetSize(cw, ch)
    map.container:SetClampRectInsets(0, 0, off, off)
    Minimap:ClearAllPoints()
    Minimap:SetPoint('TOPRIGHT', map.container, 'TOPRIGHT', 0, off)
    Minimap:SetSize(cw, cw)
    if (gt.elapsed - gt.lastZoomAt) >= 0.005 then
        gt.lastZoomAt = gt.elapsed
        local cz = Minimap:GetZoom()
        local mz = Minimap:GetZoomLevels() - 1
        if cz < mz then Minimap:SetZoom(cz + 1); Minimap:SetZoom(cz)
        else             Minimap:SetZoom(cz - 1); Minimap:SetZoom(cz) end
    end
    if t >= 1 then
        gt.active = false
        local cur_zoom = Minimap:GetZoom()
        local max_zoom = Minimap:GetZoomLevels() - 1
        if cur_zoom < max_zoom then Minimap:SetZoom(cur_zoom + 1); Minimap:SetZoom(cur_zoom)
        else                        Minimap:SetZoom(cur_zoom - 1); Minimap:SetZoom(cur_zoom) end
        map.applySettings()
        map.applyZoom()
    end
end

function map.zoomMinimap(delta)
    if delta > 0 then
        if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
    else
        if Minimap:GetZoom() == 0 then
            map.openWorldMap()
        elseif Minimap.ZoomOut then
            Minimap.ZoomOut:Click()
        end
    end
end

function map.onShowMinimap()
    map.setToolbarType(TOOLBAR_BUTTON_TYPE.MINIMAP)

    Minimap:SetAlpha(0)
    Minimap:Show()
    Minimap:SetZoom(0)
    if Minimap.ZoomIn and Minimap.ZoomOut then
        Minimap.ZoomIn:Click()
        Minimap.ZoomOut:Click()
    end

    map.startFrameFade(Minimap, map.minimapFade, 1)
end

function map.onHideMinimap()
    map.startFrameFade(Minimap, map.minimapFade, 0)
end

--#endregion

--#region ── Frame setup ──────────────────────────────────────────────────────

function map.createFrame()
    local db = addon.db.profile.minimap ---@type MinimapDB

    -- Save Blizzard state so we can restore on disable
    map.origParent = Minimap:GetParent()
    map.origW, map.origH = Minimap:GetSize()
    map.origPoints = { Minimap:GetPoint(1) }

    Minimap:SetArchBlobRingScalar(0)
    Minimap:SetArchBlobRingAlpha(0)
    Minimap:SetQuestBlobRingScalar(0)
    Minimap:SetQuestBlobRingAlpha(0)

    local w, h = size_for_shape(db.shape, db.size)
    map.createContainer(w, h)

    -- Reparent the Blizzard Minimap widget into our container
    Minimap:SetParent(map.container)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", map.container, "CENTER")
    Minimap:SetSize(w, w)
    apply_minimap_shape(db.shape, w, h)
    Minimap:Show()

    -- Rescue tracking button before hiding MinimapCluster so its menu stays functional
    map.blizzTracking = MinimapCluster.Tracking ---@diagnostic disable-line: undefined-field
    map.blizzTracking:SetParent(UIParent)

    -- Rescue addon compartment button before hiding MinimapCluster
    map.blizzCompartment = _G.AddonCompartmentFrame ---@diagnostic disable-line: undefined-global
    map.blizzCompartment:SetParent(UIParent)

    -- Rescue calendar button before hiding MinimapCluster
    map.blizzCalendar = _G.GameTimeFrame ---@diagnostic disable-line: undefined-global
    map.blizzCalendar:SetParent(UIParent)

    -- Hide all Blizzard chrome
    MinimapCluster:Hide()
    if _G.MinimapBackdrop then _G.MinimapBackdrop:Hide() end ---@diagnostic disable-line: undefined-global
    if Minimap.ZoomHitArea then Minimap.ZoomHitArea:Hide() end ---@diagnostic disable-line: undefined-field

    if Minimap.ZoomIn then ---@diagnostic disable-line: undefined-field
        Minimap.ZoomIn:SetAlpha(0)
        Minimap.ZoomIn:Hide()
        Minimap.ZoomIn.IsMouseOver = function() return true end
    end
    if Minimap.ZoomOut then ---@diagnostic disable-line: undefined-field
        Minimap.ZoomOut:SetAlpha(0)
        Minimap.ZoomOut:Hide()
        Minimap.ZoomOut.IsMouseOver = function() return true end
    end

    map.setupContainerScripts()

    -- Scroll handler: intercepts scroll-out-at-zero-zoom to open the world map
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if map.worldMapOpen then return end -- world map is visible; ignore
        local zoom = Minimap:GetZoom()
        local max_zoom = Minimap:GetZoomLevels() - 1
        if delta < 0 and zoom == 0 and map.grown then
            map.openWorldMap()
            return
        end

        if delta > 0 then
            if Minimap.ZoomIn then
                Minimap.ZoomIn:Click("LeftButton")
            else
                Minimap:SetZoom(math_min(zoom + 1, max_zoom))
            end
        else
            if Minimap.ZoomOut then
                Minimap.ZoomOut:Click("LeftButton")
            else
                Minimap:SetZoom(math_max(zoom - 1, 0))
            end
        end
    end)

    Minimap:HookScript("OnEnter", function()
        if Minimap.ZoomOut then
            Minimap.ZoomOut:Hide()
        end
        if Minimap.ZoomIn then
            Minimap.ZoomIn:Hide()
        end
    end)

    -- Native gamepad (no ConsolePort): trigger zoom + toolbar D-pad focus.
    -- SetPropagateKeyboardInput is set per-event so ConsolePort never sees
    -- inputs we've handled (matches DialogueUI's approach).
    map.container:EnableGamePadButton(true)
    map.container:SetScript('OnGamePadButtonDown', function(_, key)
        if InCombatLockdown() then
            map.container:SetPropagateKeyboardInput(true)
            return
        end
        if not map.grown then
            map.container:SetPropagateKeyboardInput(true)
            return
        end

        local handled = false
        if map.toolbar and map.toolbar:IsShown() then
            if key == 'PADDLEFT' or key == 'PADLSHOULDER' then
                map.navigate(-1); handled = true
            elseif key == 'PADDRIGHT' or key == 'PADRSHOULDER' then
                map.navigate(1); handled = true
            elseif key == 'PADBTM1' and map.focused_btn then
                map.focused_btn:Click(); handled = true
            end
        end

        -- Triggers → zoom in/out on minimap or world map.
        if key == 'PADRTRIGGER' then
            if map.worldMapOpen then map.zoomWorldMap(1) else map.zoomMinimap(1) end
            handled = true
        elseif key == 'PADLTRIGGER' then
            if map.worldMapOpen then map.zoomWorldMap(-1) else map.zoomMinimap(-1) end
            handled = true
        end

        map.container:SetPropagateKeyboardInput(not handled)
    end)

    -- Toggle grow: press to grow, press again to shrink
    local function toggle_grow()
        -- Shrinking
        if map.grown then
            map.grown = false
            if map.worldMapOpen then map.onHideWorldMap() end
            if ConsolePort and ConsolePort:RemoveInterfaceCursorFrame(map.container) then
                local ih = _G['ConsolePortInputHandler']
                if ih then ih:Release(map.container) end
                _G['ConsolePortCursor']:SetEnabled(false)
            end
        else
            -- Growing
            map.grown = true
            if ConsolePort and ConsolePort:RemoveInterfaceCursorFrame(map.container) then
                ConsolePort:AddInterfaceCursorFrame(map.toolbar)
                local ih = _G['ConsolePortInputHandler']
                if ih and not InCombatLockdown() then
                    ih:SetCommand('PADRSHOULDER', map.container, false, 'LeftButton', 'ZoomIn', nil)
                    ih:SetCommand('PADLSHOULDER', map.container, false, 'LeftButton', 'ZoomOut', nil)
                end
            end
        end
        -- Guard: ignore re-toggle while animation is already running
        if map.growTransition.active then return end

        local from_w, from_h = map.container:GetSize()
        local size = map.grown and db.growSize or db.size
        local to_w, to_h = size_for_shape(db.shape, size)

        local gt = map.growTransition
        gt.active = true
        gt.elapsed = 0
        gt.fromW = from_w
        gt.fromH = from_h
        gt.toW = to_w
        gt.toH = to_h
        gt.lastZoomAt = 0
    end

    -- ConsolePort overrides the native handler above; shoulders handle navigation
    -- via ih:SetCommand in toggle_grow, so here we only need trigger zoom.
    if ConsolePort then
        map.container:SetPropagateKeyboardInput(true)

        map.container:SetScript('OnGamePadButtonDown', function(_, key)
            if not map.grown or InCombatLockdown() then return end

            local zoom_in  = key == 'PADRTRIGGER'
            local zoom_out = key == 'PADLTRIGGER'
            if not zoom_in and not zoom_out then return end

            local delta = zoom_in and 1 or -1
            if map.worldMapOpen then map.zoomWorldMap(delta) else map.zoomMinimap(delta) end
        end)
    end

    -- Expose as a global so Bindings.xml can invoke it by name.
    function ConsoleTools_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
        if map.container and map.container:IsShown() then toggle_grow() end
    end

    -- Blizzard Key Bindings panel display strings.
    BINDING_HEADER_CONSOLETOOLS = "Console Tools" ---@diagnostic disable-line: lowercase-global
    BINDING_NAME_CONSOLETOOLS_MINIMAP_GROWTOGGLE = "Toggle Minimap Expand" ---@diagnostic disable-line: lowercase-global

    map.applyZoom()
end

--#endregion
