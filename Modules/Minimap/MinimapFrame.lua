local addon_name          = ...

---@class ConsoleTools: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod             = addon:GetModule('Minimap')

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

--#region ── Shape & masking ──────────────────────────────────────────────────

local function size_for_shape(shape, size)
    if shape == "rectangle" then
        return size, math_floor(size * (2 / 3))
    end
    return size, size
end

local RECT_MASK = "Interface\\AddOns\\ConsoleTools\\Media\\3-2.blp"

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

function minimod.applyBorder()
    if not minimod.borders then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local show = db.borderEnabled
    local size = db.borderSize
    local r, g, b, a = db.borderR, db.borderG, db.borderB, db.borderA

    minimod.MapUtils.apply_border_textures(minimod.wrapper, minimod.borders, show, size, r, g, b, a)
    if minimod.toolbarBorders then
        minimod.MapUtils.apply_border_textures(minimod.toolbar, minimod.toolbarBorders, show, size, r, g, b, a)
        if show then
            -- Hide the edge shared with the minimap wrapper
            minimod.toolbarBorders[db.toolbarDock == "bottom" and "T" or "B"]:Hide()
        end
    end
end

function minimod.applyZoom()
    if not minimod.wrapper then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local target = minimod.grown and db.growZoom or db.zoom
    local max_zoom = Minimap:GetZoomLevels() - 1
    -- Minimap:SetZoom(math_min(target, max_zoom))
end

function minimod.applySettings()
    if not minimod.wrapper then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local size = minimod.grown and db.growSize or db.size
    local w, h = size_for_shape(db.shape, size)

    minimod.wrapper:SetSize(w, h)
    minimod.wrapper:SetAlpha(db.alpha)
    local offset = math_ceil((w - h) / 2)
    minimod.wrapper:SetClampedToScreen(true)
    minimod.wrapper:SetClampRectInsets(0, 0, offset, offset)
    Minimap:ClearAllPoints()
    Minimap:SetPoint('TOPRIGHT', minimod.wrapper, 'TOPRIGHT', 0, offset)
    apply_minimap_shape(db.shape, w, h)
    minimod.applyBorder()
end

--#endregion

--#region ── Frame setup ──────────────────────────────────────────────────────

local function create_mail_indicator()
    -- Mail indicator: custom frame driven by events
    minimod.mailIndicator = CreateFrame("Frame", nil, minimod.wrapper)
    minimod.mailIndicator:SetSize(19.5, 15)
    minimod.mailIndicator:SetPoint("BOTTOMLEFT", minimod.wrapper, "BOTTOMLEFT", 4, 4)
    minimod.mailIndicator:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 150)
    minimod.mailIndicator:Hide()

    local mail_icon = minimod.mailIndicator:CreateTexture(nil, "ARTWORK")
    mail_icon:SetAllPoints(minimod.mailIndicator)
    mail_icon:SetAtlas('UI-HUD-Minimap-Mail-Up')

    local function update_mail()
        minimod.mailIndicator:SetShown(HasNewMail() and true or false) ---@diagnostic disable-line: undefined-global
    end

    minimod.mailIndicator:RegisterEvent("UPDATE_PENDING_MAIL")
    minimod.mailIndicator:RegisterEvent("MAIL_INBOX_UPDATE")
    minimod.mailIndicator:RegisterEvent("PLAYER_ENTERING_WORLD")
    minimod.mailIndicator:SetScript("OnEvent", update_mail)
    update_mail()
end

local function create_zoom_indicator()
    local zi = CreateFrame("Frame", nil, minimod.wrapper)
    zi:SetSize(ZOOM_BAR_W, ZOOM_BAR_H)
    zi:SetPoint("BOTTOMRIGHT", minimod.wrapper, "BOTTOMRIGHT", -4, 4)
    zi:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 150)
    minimod.zoomIndicator = zi

    local bg = zi:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(zi)
    bg:SetColorTexture(0, 0, 0, 0.5)

    local fill = zi:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", zi, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMLEFT", zi, "BOTTOMLEFT", 0, 0)
    fill:SetColorTexture(0, 0.82, 0.9, 0.9)
    fill:SetWidth(1)
    zi.fill = fill

    local borders = minimod.MapUtils.create_border_textures(zi, zi)
    minimod.MapUtils.apply_border_textures(zi, borders, true, 0, 0, 0, 0, 1)

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

function minimod.createFrame()
    local db = addon.db.profile.minimap ---@type MinimapDB

    -- Save Blizzard state so we can restore on disable
    minimod.origParent = Minimap:GetParent()
    minimod.origW, minimod.origH = Minimap:GetSize()
    minimod.origPoints = { Minimap:GetPoint(1) }

    Minimap:SetArchBlobRingScalar(0)
    Minimap:SetArchBlobRingAlpha(0)
    Minimap:SetQuestBlobRingScalar(0)
    Minimap:SetQuestBlobRingAlpha(0)

    -- Wrapper: clips rectangle shapes, drag target, alpha host
    local w, h = size_for_shape(db.shape, db.size)
    minimod.wrapper = CreateFrame("Frame", "CTMinimapWrapper", UIParent)
    minimod.wrapper:SetSize(w, h)
    minimod.wrapper:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    minimod.wrapper:SetClipsChildren(true)
    minimod.wrapper:SetAlpha(db.alpha)
    minimod.wrapper:SetFrameStrata("DIALOG")

    -- Reparent the Blizzard Minimap widget into our wrapper
    Minimap:SetParent(minimod.wrapper)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", minimod.wrapper, "CENTER")
    Minimap:SetSize(w, w)
    apply_minimap_shape(db.shape, w, h)
    Minimap:Show()

    -- Rescue tracking button before hiding MinimapCluster so its menu stays functional
    minimod.blizzTracking = MinimapCluster.Tracking ---@diagnostic disable-line: undefined-field
    minimod.blizzTracking:SetParent(UIParent)
    local blizz_tracking_btn = minimod.blizzTracking ---@diagnostic disable-line: undefined-field

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

    -- Border overlay: parented to wrapper (clipped to its bounds), above all content
    minimod.borderFrame = CreateFrame("Frame", nil, minimod.wrapper)
    minimod.borderFrame:SetAllPoints(minimod.wrapper)
    minimod.borderFrame:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 100)

    minimod.borders = minimod.MapUtils.create_border_textures(minimod.borderFrame, minimod.wrapper)

    minimod.applyBorder()

    -- Toolbar: docked above wrapper, shown on mouseover or when grown
    minimod.createToolbar(blizz_tracking_btn)
    create_mail_indicator()
    create_zoom_indicator()

    -- Drag-to-move: thin bar at the top so the Minimap's own click handling doesn't interfere
    minimod.wrapper:SetMovable(true)
    minimod.wrapper:SetClampedToScreen(true)
    minimod.wrapper:SetClampRectInsets(0, 0, math_ceil((w - h) / 2), math_ceil((w - h) / 2))
    minimod.dragBar = CreateFrame("Frame", nil, minimod.wrapper)
    minimod.dragBar:SetHeight(10)
    minimod.dragBar:SetPoint("TOPLEFT", minimod.wrapper, "TOPLEFT")
    minimod.dragBar:SetPoint("TOPRIGHT", minimod.wrapper, "TOPRIGHT")
    minimod.dragBar:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 200)
    minimod.dragBar:EnableMouse(true)
    minimod.dragBar:RegisterForDrag("LeftButton")
    minimod.dragBar:SetScript("OnDragStart", function() minimod.wrapper:StartMoving() end)
    minimod.dragBar:SetScript("OnDragStop", function()
        minimod.wrapper:StopMovingOrSizing()
        local pt, _, _, ox, oy = minimod.wrapper:GetPoint()
        db.point = pt
        db.x = ox
        db.y = oy
    end)

    minimod.wrapper:SetScript("OnUpdate", function(_, elapsed)
        -- Movement fade (wrapper alpha)
        if minimod.fadeTo then
            minimod.fadeElapsed = minimod.fadeElapsed + elapsed
            local t = math_min(1, minimod.fadeElapsed / FADE_DURATION)
            minimod.wrapper:SetAlpha(minimod.fadeFrom + (minimod.fadeTo - minimod.fadeFrom) * t)
            if t >= 1 then minimod.fadeTo = nil end
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

        update_fade(minimod.minimapFade, Minimap)
        update_fade(minimod.worldMapFade, minimod.worldMap)
        update_fade(minimod.toolbarFade, minimod.toolbar, FADE_DURATION)

        -- Grow/shrink transition
        local gt = minimod.growTransition
        if gt.active then
            gt.elapsed = gt.elapsed + elapsed
            local t = math_min(1, gt.elapsed / GROW_DURATION)
            local ts = t * t * (3 - 2 * t) -- smoothstep easing
            local cw = gt.fromW + (gt.toW - gt.fromW) * ts
            local ch = gt.fromH + (gt.toH - gt.fromH) * ts
            local off = math_ceil((cw - ch) / 2)
            minimod.wrapper:SetSize(cw, ch)
            minimod.wrapper:SetClampRectInsets(0, 0, off, off)
            Minimap:ClearAllPoints()
            Minimap:SetPoint('TOPRIGHT', minimod.wrapper, 'TOPRIGHT', 0, off)
            Minimap:SetSize(cw, cw)
            if (minimod.growTransition.elapsed - gt.lastZoomAt) >= 0.005 then
                gt.lastZoomAt = minimod.growTransition.elapsed
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
                minimod.growTransition.active = false
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
                minimod.applySettings()
                minimod.applyZoom()
            end
        end
        -- Toolbar visibility: fade in/out
        if minimod.toolbar then
            local should_show = minimod.grown or minimod.wrapper:IsMouseOver() or minimod.toolbar:IsMouseOver()
            local tf = minimod.toolbarFade
            if should_show and tf.to ~= 1 then
                minimod.toolbar:Show()
                minimod.startFrameFade(minimod.toolbar, tf, 1)
            elseif not should_show and tf.to ~= 0 then
                minimod.startFrameFade(minimod.toolbar, tf, 0)
            end
        end
        -- Zoom indicator bar (only while expanded)
        local zi = minimod.zoomIndicator
        if zi then
            zi:SetShown(minimod.grown)
            if minimod.grown then
                if minimod.worldMapOpen and minimod.worldMap then
                    -- World map mode: discrete levels (WM_ZOOM_LEVELS), same chunk logic as minimap
                    local n         = WM_ZOOM_LEVELS
                    local sc        = minimod.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                    local cur       = sc:GetZoom()
                    local wmin      = minimod.worldMapMinZoom or 0.12
                    local wmax      = minimod.worldMapMaxZoom or 0.30
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
                end -- minimod.grown
            end
        end
    end)

    local function start_fade(target)
        minimod.fadeFrom = minimod.wrapper:GetAlpha()
        minimod.fadeTo = target
        minimod.fadeElapsed = 0
    end

    minimod.wrapper:RegisterEvent("PLAYER_STARTED_MOVING")
    minimod.wrapper:RegisterEvent("PLAYER_STOPPED_MOVING")
    minimod.wrapper:RegisterEvent("PLAYER_REGEN_DISABLED")
    minimod.wrapper:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            local ih = _G['ConsolePortInputHandler']
            if ih then ih:Release(minimod.wrapper) end
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
        if minimod.worldMapOpen then return end -- world map is visible; ignore
        local zoom = Minimap:GetZoom()
        local max_zoom = Minimap:GetZoomLevels() - 1
        if delta < 0 and zoom == 0 and minimod.grown then
            minimod.openWorldMap()
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
    minimod.wrapper:EnableGamePadButton(true)
    minimod.wrapper:SetScript('OnGamePadButtonDown', function(_, key)
        if InCombatLockdown() then
            minimod.wrapper:SetPropagateKeyboardInput(true)
            return
        end
        if not minimod.grown then
            minimod.wrapper:SetPropagateKeyboardInput(true)
            return
        end

        local handled = false
        if minimod.toolbar and minimod.toolbar:IsShown() then
            if key == 'PADDLEFT' or key == 'PADLSHOULDER' then
                minimod.navigate(-1); handled = true
            elseif key == 'PADDRIGHT' or key == 'PADRSHOULDER' then
                minimod.navigate(1); handled = true
            elseif key == 'PADBTM1' and minimod.focused_btn then
                minimod.focused_btn:Click(); handled = true
            end
        end

        -- Triggers → zoom in/out on minimap or world map.
        if key == 'PADRTRIGGER' then
            if minimod.worldMapOpen and minimod.worldMap then
                local sc = minimod.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                sc:SetZoomTarget(sc:GetZoom() * 1.1)
            else
                if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
            end
            handled = true
        elseif key == 'PADLTRIGGER' then
            if minimod.worldMapOpen and minimod.worldMap then
                local sc = minimod.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                if sc:IsAtMaxZoom() then
                    minimod.closeWorldMap()
                else
                    sc:SetZoomTarget(sc:GetZoom() * 0.9)
                end
            else
                if Minimap:GetZoom() == 0 then
                    minimod.openWorldMap()
                elseif Minimap.ZoomOut then
                    Minimap.ZoomOut:Click()
                end
            end
            handled = true
        end

        minimod.wrapper:SetPropagateKeyboardInput(not handled)
    end)

    -- Toggle grow: press to grow, press again to shrink
    local function toggle_grow()
        -- Shrinking
        if minimod.grown then
            minimod.grown = false
            if minimod.worldMapOpen then minimod.closeWorldMap() end
            if ConsolePort and ConsolePort:RemoveInterfaceCursorFrame(minimod.wrapper) then
                local ih = _G['ConsolePortInputHandler']
                if ih then ih:Release(minimod.wrapper) end
                _G['ConsolePortCursor']:SetEnabled(false)
            end
        else
            -- Growing
            minimod.grown = true
            if ConsolePort and ConsolePort:RemoveInterfaceCursorFrame(minimod.wrapper) then
                ConsolePort:AddInterfaceCursorFrame(minimod.toolbar)
                local ih = _G['ConsolePortInputHandler']
                if ih and not InCombatLockdown() then
                    ih:SetCommand('PADRSHOULDER', minimod.wrapper, false, 'LeftButton', 'ZoomIn', nil)
                    ih:SetCommand('PADLSHOULDER', minimod.wrapper, false, 'LeftButton', 'ZoomOut', nil)
                end
            end
        end
        -- Guard: ignore re-toggle while animation is already running
        if minimod.growTransition.active then return end

        local from_w, from_h = minimod.wrapper:GetSize()
        local size = minimod.grown and db.growSize or db.size
        local to_w, to_h = size_for_shape(db.shape, size)

        local gt = minimod.growTransition
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
        minimod.wrapper:SetPropagateKeyboardInput(true)

        minimod.wrapper:SetScript('OnGamePadButtonDown', function(_, key)
            if not minimod.grown or InCombatLockdown() then return end

            local zoom_in  = key == 'PADRTRIGGER'
            local zoom_out = key == 'PADLTRIGGER'
            if not zoom_in and not zoom_out then return end

            if minimod.worldMapOpen and minimod.worldMap then
                local sc = minimod.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
                if zoom_in and sc:IsAtMaxZoom() then
                    minimod.closeWorldMap()
                else
                    sc:SetZoomTarget(sc:GetZoom() * (zoom_in and 1.1 or 0.9))
                end
            elseif zoom_in then
                if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
            else
                if Minimap:GetZoom() == 0 then
                    minimod.openWorldMap()
                elseif Minimap.ZoomOut then
                    Minimap.ZoomOut:Click()
                end
            end
        end)
    end

    -- Expose as a global so Bindings.xml can invoke it by name.
    function ConsoleTools_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
        if minimod.wrapper and minimod.wrapper:IsShown() then toggle_grow() end
    end

    -- Blizzard Key Bindings panel display strings.
    BINDING_HEADER_CONSOLETOOLS = "Console Tools" ---@diagnostic disable-line: lowercase-global
    BINDING_NAME_CONSOLETOOLS_MINIMAP_GROWTOGGLE = "Toggle Minimap Expand" ---@diagnostic disable-line: lowercase-global

    minimod.applyZoom()
end

--#endregion
