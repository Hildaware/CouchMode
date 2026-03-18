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
local CreateFrame         = _G.CreateFrame
local HasNewMail          = _G.HasNewMail
local InCombatLockdown    = _G.InCombatLockdown
local MinimapCluster      = _G.MinimapCluster ---@type Frame

local ConsolePort         = _G['ConsolePort'] ---@type any

local FADE_DURATION       = 0.5
local TRANSITION_DURATION = 0.25
local GROW_DURATION       = 0.5
local ZOOM_BAR_W          = 80
local ZOOM_BAR_H          = 10
local WM_ZOOM_LEVELS      = 5

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

local function create_mail_indicator()
    -- Mail indicator: custom frame driven by events
    map.mailIndicator = CreateFrame("Frame", nil, map.container)
    map.mailIndicator:SetSize(19.5, 15)
    map.mailIndicator:SetPoint("BOTTOMLEFT", map.container, "BOTTOMLEFT", 4, 4)
    map.mailIndicator:SetFrameLevel(map.container:GetFrameLevel() + 150)
    map.mailIndicator:Hide()

    local mail_icon = map.mailIndicator:CreateTexture(nil, "ARTWORK")
    mail_icon:SetAllPoints(map.mailIndicator)
    mail_icon:SetAtlas('UI-HUD-Minimap-Mail-Up')

    local function update_mail()
        map.mailIndicator:SetShown(HasNewMail() and true or false) ---@diagnostic disable-line: undefined-global
    end

    map.mailIndicator:RegisterEvent("UPDATE_PENDING_MAIL")
    map.mailIndicator:RegisterEvent("MAIL_INBOX_UPDATE")
    map.mailIndicator:RegisterEvent("PLAYER_ENTERING_WORLD")
    map.mailIndicator:SetScript("OnEvent", update_mail)
    update_mail()
end

local function create_zoom_indicator()
    local zi = CreateFrame("Frame", nil, map.container)
    zi:SetSize(ZOOM_BAR_W, ZOOM_BAR_H)
    zi:SetPoint("BOTTOMRIGHT", map.container, "BOTTOMRIGHT", -4, 4)
    zi:SetFrameLevel(map.container:GetFrameLevel() + 150)
    map.zoomIndicator = zi

    local bg = zi:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(zi)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local fill = zi:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", zi, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", zi, "BOTTOMLEFT", 0, 0)
    fill:SetColorTexture(0, 0.82, 0.9, 0.9)
    fill:SetWidth(1)
    zi.fill = fill

    local borders = map.MapUtils.create_border_textures(zi, zi)
    map.MapUtils.apply_border_textures(zi, borders, true, 0, 0, 0, 0, 1)

    zi.ticks = {}
    for i = 1, 10 do
        local t = zi:CreateTexture(nil, "OVERLAY")
        t:SetSize(1, ZOOM_BAR_H)
        t:SetColorTexture(0, 0, 0, 0.8)
        t:Hide()
        zi.ticks[i] = t
    end

    zi.numLevels = 0  -- cached; ticks only repositioned when this changes
    zi.lastZoom  = -1 -- sentinel → first frame always redraws fill
end

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

    -- Border overlay: parented to container (clipped to its bounds), above all content
    map.borderFrame = CreateFrame("Frame", nil, map.container)
    map.borderFrame:SetAllPoints(map.container)
    map.borderFrame:SetFrameLevel(map.container:GetFrameLevel() + 100)

    map.borders = map.MapUtils.create_border_textures(map.borderFrame, map.container)

    map.applyBorder()

    -- Toolbar: docked above container, shown on mouseover or when grown
    map.createToolbar()
    create_mail_indicator()
    create_zoom_indicator()

    map.container:SetScript("OnUpdate", function(_, elapsed)
        -- Movement fade (container alpha)
        if map.fadeTo then
            map.fadeElapsed = map.fadeElapsed + elapsed
            local t = math_min(1, map.fadeElapsed / FADE_DURATION)
            map.container:SetAlpha(map.fadeFrom + (map.fadeTo - map.fadeFrom) * t)
            if t >= 1 then map.fadeTo = nil end
        end
        -- Frame cross-fade helper
        local function update_fade(state, frame, duration)
            if not state.active or not frame then return end
            state.elapsed = state.elapsed + elapsed
            local t = math_min(1, state.elapsed / (duration or TRANSITION_DURATION))
            frame:SetAlpha(state.from + (state.to - state.from) * t)
            if t >= 1 then
                state.active = false
                if state.to == 0 then frame:Hide() end
            end
        end

        update_fade(map.minimapFade, Minimap)
        update_fade(map.worldMapFade, map.worldMap)
        update_fade(map.toolbarFade, map.toolbar, FADE_DURATION)

        -- Grow/shrink transition
        local gt = map.growTransition
        if gt.active then
            gt.elapsed = gt.elapsed + elapsed
            local t = math_min(1, gt.elapsed / GROW_DURATION)
            local ts = t * t * (3 - 2 * t) -- smoothstep easing
            local cw = gt.fromW + (gt.toW - gt.fromW) * ts
            local ch = gt.fromH + (gt.toH - gt.fromH) * ts
            local off = math_ceil((cw - ch) / 2)
            map.container:SetSize(cw, ch)
            map.container:SetClampRectInsets(0, 0, off, off)
            Minimap:ClearAllPoints()
            Minimap:SetPoint('TOPRIGHT', map.container, 'TOPRIGHT', 0, off)
            Minimap:SetSize(cw, cw)
            if (map.growTransition.elapsed - gt.lastZoomAt) >= 0.005 then
                gt.lastZoomAt = map.growTransition.elapsed
                local cz = Minimap:GetZoom()
                local mz = Minimap:GetZoomLevels() - 1
                if cz < mz then
                    Minimap:SetZoom(cz + 1)
                    Minimap:SetZoom(cz)
                else
                    Minimap:SetZoom(cz - 1)
                    Minimap:SetZoom(cz)
                end
            end
            if t >= 1 then
                map.growTransition.active = false
                -- Force tile recalculation at final size
                local cur_zoom = Minimap:GetZoom()
                local max_zoom = Minimap:GetZoomLevels() - 1
                if cur_zoom < max_zoom then
                    Minimap:SetZoom(cur_zoom + 1)
                    Minimap:SetZoom(cur_zoom)
                else
                    Minimap:SetZoom(cur_zoom - 1)
                    Minimap:SetZoom(cur_zoom)
                end
                map.applySettings()
                map.applyZoom()
            end
        end
        -- Toolbar visibility: fade in/out
        if map.toolbar then
            local should_show = map.grown or map.container:IsMouseOver() or map.toolbar:IsMouseOver()
            local tf = map.toolbarFade
            if should_show and tf.to ~= 1 then
                map.toolbar:Show()
                map.startFrameFade(map.toolbar, tf, 1)
            elseif not should_show and tf.to ~= 0 then
                map.startFrameFade(map.toolbar, tf, 0)
            end
        end
        -- Zoom indicator bar (only while expanded)
        local zi = map.zoomIndicator
        if zi then
            zi:SetShown(map.grown)
            if map.grown then
                if map.worldMapOpen and map.worldMap then
                    -- World map mode: discrete levels (WM_ZOOM_LEVELS), same chunk logic as minimap
                    local n         = WM_ZOOM_LEVELS
                    local sc        = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                    local cur       = sc:GetZoom()
                    local wmin      = map.worldMapMinZoom or 0.12
                    local wmax      = map.worldMapMaxZoom or 0.30
                    local range     = wmax - wmin
                    local frac      = range > 0 and math_min(1, math_max(0, (cur - wmin) / range)) or 0
                    local cur_level = math_floor(frac * (n - 1) + 0.5)
                    if n ~= zi.numLevels then
                        zi.numLevels = n
                        zi.lastZoom = -1
                        for i, tick in ipairs(zi.ticks) do
                            if n > 1 and i <= (n - 2) then
                                local x = (i / (n - 1)) * ZOOM_BAR_W
                                tick:ClearAllPoints()
                                tick:SetPoint("TOPLEFT", zi, "TOPLEFT", x, 0)
                                tick:Show()
                            else
                                tick:Hide()
                            end
                        end
                    end
                    if cur_level ~= zi.lastZoom then
                        zi.lastZoom = cur_level
                        zi.fill:SetWidth(math_max(1, (cur_level / (n - 1)) * ZOOM_BAR_W))
                    end
                else
                    -- Minimap mode: discrete levels with tick marks
                    local n = Minimap:GetZoomLevels()
                    if n ~= zi.numLevels then
                        zi.numLevels = n
                        zi.lastZoom = -1  -- force fill redraw when level count changes
                        for i, tick in ipairs(zi.ticks) do
                            local lvl = i -- interior tick at zoom level i (1..n-2)
                            if n > 1 and lvl <= (n - 2) then
                                local x = (lvl / (n - 1)) * ZOOM_BAR_W
                                tick:ClearAllPoints()
                                tick:SetPoint("TOPLEFT", zi, "TOPLEFT", x, 0)
                                tick:Show()
                            else
                                tick:Hide()
                            end
                        end
                    end
                    local cur_zoom = Minimap:GetZoom()
                    if cur_zoom ~= zi.lastZoom then
                        zi.lastZoom = cur_zoom
                        local frac = (n > 1) and (cur_zoom / (n - 1)) or 0
                        zi.fill:SetWidth(math_max(1, frac * ZOOM_BAR_W))
                    end
                end -- map.grown
            end
        end
    end)

    local function start_fade(target)
        map.fadeFrom = map.container:GetAlpha()
        map.fadeTo = target
        map.fadeElapsed = 0
    end

    map.container:RegisterEvent("PLAYER_STARTED_MOVING")
    map.container:RegisterEvent("PLAYER_STOPPED_MOVING")
    map.container:RegisterEvent("PLAYER_REGEN_DISABLED")
    map.container:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            local ih = _G['ConsolePortInputHandler']
            if ih then ih:Release(map.container) end
            return
        end
        if not db.moveAlphaEnabled then return end
        if event == "PLAYER_STARTED_MOVING" then
            if db.moveAlphaEnabled then start_fade(db.moveAlpha) end
        elseif event == "PLAYER_STOPPED_MOVING" then
            if db.moveAlphaEnabled then start_fade(db.alpha) end
        end
    end)

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
            if map.worldMapOpen and map.worldMap then
                local sc = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                sc:SetZoomTarget(sc:GetZoom() * 1.1)
            else
                if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
            end
            handled = true
        elseif key == 'PADLTRIGGER' then
            if map.worldMapOpen and map.worldMap then
                local sc = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                if sc:IsAtMaxZoom() then
                    map.onHideWorldMap()
                else
                    sc:SetZoomTarget(sc:GetZoom() * 0.9)
                end
            else
                if Minimap:GetZoom() == 0 then
                    map.openWorldMap()
                elseif Minimap.ZoomOut then
                    Minimap.ZoomOut:Click()
                end
            end
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

            if map.worldMapOpen and map.worldMap then
                local sc = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                if zoom_in and sc:IsAtMaxZoom() then
                    map.onHideWorldMap()
                else
                    sc:SetZoomTarget(sc:GetZoom() * (zoom_in and 1.1 or 0.9))
                end
            elseif zoom_in then
                if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
            else
                if Minimap:GetZoom() == 0 then
                    map.openWorldMap()
                elseif Minimap.ZoomOut then
                    Minimap.ZoomOut:Click()
                end
            end
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
