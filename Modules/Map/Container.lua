local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map = addon:GetModule('Minimap')

local _G = _G
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil
local CreateFrame = _G.CreateFrame
local UIParent = _G.UIParent
local Minimap = _G.Minimap
local HasNewMail = _G.HasNewMail
local GetTime = _G.GetTime

local ZOOM_BAR_W = 80
local ZOOM_BAR_H = 10

local FADE_DURATION = 0.5

local ConsolePort = _G['ConsolePort'] ---@type any

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
    map.container:SetFrameStrata("MEDIUM")
    map.container:SetFrameLevel(69)

    -- Drag-to-move: small handle in the top-right corner, visible only when unlocked
    map.container:SetMovable(true)
    map.container:SetClampedToScreen(true)
    map.container:SetClampRectInsets(-4, 4, math_ceil((w - h) / 2), math_ceil((w - h) / 2))
    map.dragHandle = CreateFrame("Frame", nil, map.container)
    map.dragHandle:SetSize(20, 20)
    map.dragHandle:SetPoint("TOPRIGHT", map.container, "TOPRIGHT", 0, 0)
    map.dragHandle:SetFrameLevel(map.container:GetFrameLevel() + 200)
    map.dragHandle:EnableMouse(true)
    map.dragHandle:RegisterForDrag("LeftButton")
    map.dragHandle:SetScript("OnDragStart", function() map.container:StartMoving() end)
    map.dragHandle:SetScript("OnDragStop", function()
        map.container:StopMovingOrSizing()
        local pt, _, _, ox, oy = map.container:GetPoint()
        db.point = pt
        db.x = ox
        db.y = oy
    end)

    local handle_bg = map.dragHandle:CreateTexture(nil, "BACKGROUND")
    handle_bg:SetAllPoints(map.dragHandle)
    handle_bg:SetColorTexture(0, 0, 0, 1)

    local handle_fill = map.dragHandle:CreateTexture(nil, "ARTWORK")
    handle_fill:SetPoint("TOPLEFT", map.dragHandle, "TOPLEFT", 1, -1)
    handle_fill:SetPoint("BOTTOMRIGHT", map.dragHandle, "BOTTOMRIGHT", -1, 1)
    handle_fill:SetColorTexture(0, 0.8, 0.2, 0.9)

    map.dragHandle:SetShown(not db.locked)
end

function map.applyLock()
    if not map.dragHandle then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    map.dragHandle:SetShown(not db.locked)
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
    zi:SetPoint("BOTTOMRIGHT", map.container, "BOTTOMRIGHT", -4, 6)
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
    zi.lastZoom = -1  -- sentinel → first frame always redraws fill

    local lt_tex = zi:CreateTexture(nil, "OVERLAY")
    lt_tex:SetSize(16, 16)
    lt_tex:SetPoint("RIGHT", zi, "LEFT", -3, 0)
    lt_tex:Hide()
    zi.ltTex = lt_tex

    local rt_tex = zi:CreateTexture(nil, "OVERLAY")
    rt_tex:SetSize(16, 16)
    rt_tex:SetPoint("LEFT", zi, "RIGHT", 3, 0)
    rt_tex:Hide()
    zi.rtTex = rt_tex

    zi.cpDevice = nil
end

function map.updateZoomIndicatorIcons()
    local zi = map.zoomIndicator
    if not zi then return end
    if not ConsolePort then
        zi.ltTex:Hide(); zi.rtTex:Hide()
        return
    end
    local device = ConsolePort:GetData().Gamepad:GetActiveDevice()
    if not device then
        zi.ltTex:Hide(); zi.rtTex:Hide()
        return
    end
    local function apply(tex, button)
        local path, useAtlas = device:GetIconForButton(button, 32)
        if not path then
            tex:Hide(); return
        end
        if useAtlas then
            tex:SetAtlas(path)
        else
            tex:SetTexture(path)
            tex:SetTexCoord(0.25, 0.75, 0.25, 0.75)
        end
        tex:Show()
    end
    apply(zi.ltTex, 'PADLSHOULDER')
    apply(zi.rtTex, 'PADRSHOULDER')
    zi.cpDevice = device

    zi:ClearAllPoints()
    zi:SetPoint("BOTTOMRIGHT", map.container, "BOTTOMRIGHT", device and -23 or -4, 6)
end

function map.updateZoomIndicator(elapsed) ---@diagnostic disable-line: unused-local
    local zi = map.zoomIndicator
    if not zi then return end

    local shouldShow = map.grown == true
    if zi:IsShown() ~= shouldShow then zi:SetShown(shouldShow) end
    if not shouldShow then return end

    if map.worldMapOpen and map.worldMap then
        -- Refresh trigger icons if the active controller device changed
        local cur_device = ConsolePort and ConsolePort:GetData().Gamepad:GetActiveDevice()
        if cur_device ~= zi.cpDevice then
            map.updateZoomIndicatorIcons()
        end

        -- World map mode: continuous fill, logarithmic scale (each zoom doubling = equal bar width)
        local sc = map.worldMap.ScrollContainer
        local cur = sc:GetZoom()
        local wmin = map.worldMapMinZoom or 0.12
        local wmax = map.worldMapMaxZoom or 0.30
        local frac = (wmin > 0 and wmax > wmin and cur > 0)
            and math_min(1, math_max(0, math.log(cur / wmin) / math.log(wmax / wmin)))
            or 0

        if zi.numLevels ~= 0 then
            zi.numLevels = 0
            for _, tick in ipairs(zi.ticks) do tick:Hide() end
        end

        local fill_w = math_floor(math_max(1, frac * ZOOM_BAR_W) + 0.5)
        if fill_w ~= zi.lastZoom then
            zi.lastZoom = fill_w
            zi.fill:SetWidth(fill_w)
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

    -- Chrome lives outside the clipping map container so its authored outer
    -- padding is visible.
    map.borderFrame = CreateFrame("Frame", nil, UIParent)
    map.borderFrame:SetFrameStrata("MEDIUM")
    map.borderFrame:SetFrameLevel(map.container:GetFrameLevel() + 100)
    addon.Components.Metal.PositionBorderFrame(map.borderFrame, map.container, addon.Components.Metal.BORDER_OUTSET)
    map.borders = addon.Components.Metal.CreateBorderTextures(map.borderFrame, map.borderFrame)
    map.container:HookScript("OnShow", function() map.borderFrame:Show() end)
    map.container:HookScript("OnHide", function() map.borderFrame:Hide() end)
    map.applyBorder()

    -- Container children: toolbar and indicators
    map.createToolbar()
    map.createMailIndicator()
    map.createZoomIndicator()

    if ConsolePort then
        ConsolePort:GetData():RegisterCallback('Gamepad/Active', map.updateZoomIndicatorIcons)
        map.updateZoomIndicatorIcons()
    end

    map.container:SetScript("OnUpdate", function(_, elapsed)

        -- Toolbar visibility: fade in/out
        if map.toolbar then
            local should_show = map.grown or map.container:IsMouseOver() or map.toolbar:IsMouseOver()
            local tf = map.toolbarFade
            if should_show and tf.to ~= 1 then
                map.toolbar:Show()
                map.startFrameFade(map.toolbar, tf, 1, false, FADE_DURATION)
            elseif not should_show and tf.to ~= 0 then
                map.startFrameFade(map.toolbar, tf, 0, false, FADE_DURATION)
            end
        end
        map.updateZoomIndicator(elapsed)
    end)

    local function start_fade(target)
        map.startFrameFade(map.container, map.containerFade, target, false, FADE_DURATION)
    end

    map.container:RegisterEvent("PLAYER_STARTED_MOVING")
    map.container:RegisterEvent("PLAYER_STOPPED_MOVING")
    map.container:RegisterEvent("PLAYER_REGEN_DISABLED")
    map.container:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            map.container:SetPropagateKeyboardInput(true)
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
    -- Guard: ignore re-toggle while animation is already running
    if map.growTransition.active then return end

    local from_w, from_h = map.container:GetSize()

    -- Shrinking
    if map.grown then
        map.grown = false
        if map.worldMapOpen then map.onHideWorldMap() end
        if map.toolbar then map.toolbar:Hide() end
        if ConsolePort then
            ConsolePort:RemoveInterfaceCursorFrame(map.toolbar)
            local ih = _G['ConsolePortInputHandler']
            if ih then ih:Release(map.container) end
            _G['ConsolePortCursor']:SetEnabled(false)
        end
    else
        -- Growing
        map.grown = true
        if ConsolePort then
            ConsolePort:AddInterfaceCursorFrame(map.toolbar)
            local ih = _G['ConsolePortInputHandler']
            if ih and not InCombatLockdown() then
                ih:SetCommand('PADRSHOULDER', map.container, true, 'LeftButton', 'ZoomIn', nil)
                ih:SetCommand('PADLSHOULDER', map.container, true, 'LeftButton', 'ZoomOut', nil)
            end
        end
    end

    local db = addon.db.profile.minimap ---@type MinimapDB
    local size = map.grown and db.growSize or db.size
    local shape = map.grown and db.growShape or db.shape
    local to_w, to_h = map.MapUtils.size_for_shape(shape, size)

    local gt = map.growTransition
    gt.active = true
    gt.elapsed = 0
    gt.fromW = from_w
    gt.fromH = from_h
    gt.toW = to_w
    gt.toH = to_h
    gt.animShape = db.growShape
    gt.lastZoomAt = 0
    map.startGrowTransition()
end

-- Expose as a global so Bindings.xml can invoke it by name
local grow_last_press = 0
local DOUBLE_PRESS_THRESHOLD = 0.4
function CouchMode_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
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

function CouchMode_MinimapToggle() ---@diagnostic disable-line: lowercase-global
    if not map.container then return end
    local db = addon.db.profile.minimap ---@type MinimapDB
    local target = map.container:GetAlpha() == db.alpha and 0 or db.alpha
    if target > 0 then map.container:Show() end
    map.startFrameFade(map.container, map.containerFade, target, target == 0, FADE_DURATION)
end

-- Blizzard Key Bindings panel display strings
BINDING_HEADER_COUCHMODE = "CouchMode" ---@diagnostic disable-line: lowercase-global
BINDING_NAME_COUCHMODE_MINIMAP_GROWTOGGLE = "Toggle Expand Minimap" ---@diagnostic disable-line: lowercase-global
BINDING_NAME_COUCHMODE_MINIMAP_TOGGLE = "Toggle Minimap" ---@diagnostic disable-line: lowercase-global
