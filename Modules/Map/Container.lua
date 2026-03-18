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
local CreateFrame         = _G.CreateFrame
local UIParent            = _G.UIParent
local Minimap             = _G.Minimap
local HasNewMail          = _G.HasNewMail
local GetTime             = _G.GetTime

local ZOOM_BAR_W          = 80
local ZOOM_BAR_H          = 10
local WM_ZOOM_LEVELS      = 5
local FADE_DURATION       = 0.5
local TRANSITION_DURATION = 0.25

local ConsolePort         = _G['ConsolePort'] ---@type any

--#region ── Container ────────────────────────────────────────────────────────

--- Creates map.container — the outer frame that clips children, hosts alpha, and
--- acts as the drag target. Must be called before any child frames are created.
---@param w number frame width
---@param h number frame height
function map.createContainer(w, h)
    local db = addon.db.profile.minimap ---@type MinimapDB

    map.container = CreateFrame("Frame", "CTMinimapContainer", UIParent)
    map.container:SetSize(w, h)
    map.container:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    map.container:SetClipsChildren(true)
    map.container:SetAlpha(db.alpha)
    map.container:SetFrameStrata("DIALOG")

    -- Drag-to-move: thin bar at the top so the Minimap's own click handling doesn't interfere
    map.container:SetMovable(true)
    map.container:SetClampedToScreen(true)
    map.container:SetClampRectInsets(0, 0, math_ceil((w - h) / 2), math_ceil((w - h) / 2))
    map.dragBar = CreateFrame("Frame", nil, map.container)
    map.dragBar:SetHeight(10)
    map.dragBar:SetPoint("TOPLEFT", map.container, "TOPLEFT")
    map.dragBar:SetPoint("TOPRIGHT", map.container, "TOPRIGHT")
    map.dragBar:SetFrameLevel(map.container:GetFrameLevel() + 200)
    map.dragBar:EnableMouse(true)
    map.dragBar:RegisterForDrag("LeftButton")
    map.dragBar:SetScript("OnDragStart", function() map.container:StartMoving() end)
    map.dragBar:SetScript("OnDragStop", function()
        map.container:StopMovingOrSizing()
        local pt, _, _, ox, oy = map.container:GetPoint()
        db.point = pt
        db.x = ox
        db.y = oy
    end)
end

--#endregion

--#region ── Container indicators ─────────────────────────────────────────────

function map.createMailIndicator()
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

function map.createZoomIndicator()
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

function map.updateZoomIndicator(elapsed) ---@diagnostic disable-line: unused-local
    local zi = map.zoomIndicator
    if not zi then return end

    zi:SetShown(map.grown)
    if not map.grown then return end

    if map.worldMapOpen and map.worldMap then
        -- World map mode: discrete levels (WM_ZOOM_LEVELS)
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
        local cur_zoom = Minimap:GetZoom()
        if cur_zoom ~= zi.lastZoom then
            zi.lastZoom = cur_zoom
            local frac = (n > 1) and (cur_zoom / (n - 1)) or 0
            zi.fill:SetWidth(math_max(1, frac * ZOOM_BAR_W))
        end
    end
end

function map.setupContainerScripts()
    local db = addon.db.profile.minimap ---@type MinimapDB

    -- Border overlay: parented to container (clipped to its bounds), above all content
    map.borderFrame = CreateFrame("Frame", nil, map.container)
    map.borderFrame:SetAllPoints(map.container)
    map.borderFrame:SetFrameLevel(map.container:GetFrameLevel() + 100)
    map.borders = map.MapUtils.create_border_textures(map.borderFrame, map.container)
    map.applyBorder()

    -- Container children: toolbar and indicators
    map.createToolbar()
    map.createMailIndicator()
    map.createZoomIndicator()

    map.container:SetScript("OnUpdate", function(_, elapsed)
        -- Movement fade (container alpha)
        if map.fadeTo then
            map.fadeElapsed = map.fadeElapsed + elapsed
            local t = math_min(1, map.fadeElapsed / FADE_DURATION)
            map.container:SetAlpha(map.fadeFrom + (map.fadeTo - map.fadeFrom) * t)
            if t >= 1 then
                if map.fadeHideOnComplete then
                    map.container:Hide()
                    map.fadeHideOnComplete = false
                end
                map.fadeTo = nil
            end
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

        -- Grow/shrink transition (Minimap frame, delegated to Minimap.lua)
        map.updateGrowTransition(elapsed)

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
        map.updateZoomIndicator(elapsed)
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
            start_fade(db.moveAlpha)
        elseif event == "PLAYER_STOPPED_MOVING" then
            start_fade(db.alpha)
        end
    end)
end

--#endregion

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

    local db = addon.db.profile.minimap ---@type MinimapDB
    local from_w, from_h = map.container:GetSize()
    local size = map.grown and db.growSize or db.size
    local to_w, to_h = map.MapUtils.size_for_shape(db.shape, size)

    local gt = map.growTransition
    gt.active = true
    gt.elapsed = 0
    gt.fromW = from_w
    gt.fromH = from_h
    gt.toW = to_w
    gt.toH = to_h
    gt.lastZoomAt = 0
end

-- Expose as a global so Bindings.xml can invoke it by name
local grow_last_press = 0
local DOUBLE_PRESS_THRESHOLD = 0.4
function ConsoleTools_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
    if not map.container then return end
    if not map.container:IsShown() then map.container:Show() end
    local now = GetTime()
    if (now - grow_last_press) < DOUBLE_PRESS_THRESHOLD and map.grown and not map.worldMapOpen then
        map.openWorldMapFresh()
        grow_last_press = 0
    else
        toggle_grow()
        grow_last_press = now
    end
end

function ConsoleTools_MinimapToggle() ---@diagnostic disable-line: lowercase-global
    if not map.container then return end
    local db     = addon.db.profile.minimap ---@type MinimapDB
    local target = map.container:GetAlpha() == db.alpha and 0 or db.alpha
    if target > 0 then
        map.container:Show()
        map.fadeHideOnComplete = false
    else
        map.fadeHideOnComplete = true
    end
    map.fadeFrom    = map.container:GetAlpha()
    map.fadeTo      = target
    map.fadeElapsed = 0
end

-- Blizzard Key Bindings panel display strings
BINDING_HEADER_CONSOLETOOLS = "Console Tools" ---@diagnostic disable-line: lowercase-global
BINDING_NAME_CONSOLETOOLS_MINIMAP_GROWTOGGLE = "Toggle Expand Minimap" ---@diagnostic disable-line: lowercase-global
BINDING_NAME_CONSOLETOOLS_MINIMAP_TOGGLE = "Toggle Minimap" ---@diagnostic disable-line: lowercase-global
