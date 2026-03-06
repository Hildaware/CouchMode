local addonName        = ...

---@class ConsoleTools: AceAddon
local addon            = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Compass: AceModule
local compass          = addon:NewModule('Compass', 'AceEvent-3.0')
---@cast compass +AceEvent-3.0

local container ---@type Frame
local strip ---@type Frame

--#region ── Constants ────────────────────────────────────────────────────────

local BAR_WIDTH        = 300
local BAR_HEIGHT       = 28
local VISIBLE_DEG      = 90
local STRIP_DEG        = 450                     -- strip covers -45° to +405°
local PX_PER_DEG       = BAR_WIDTH / VISIBLE_DEG -- 10/3 px per degree
local STRIP_WIDTH      = STRIP_DEG * PX_PER_DEG  -- 1500px

local UPDATE_HZ        = 0.05                    -- seconds between GetPlayerFacing() samples
local LERP_SPEED       = 12                      -- exponential-decay rate (higher = snappier)
local MARKER_UPDATE_HZ = 1.0                     -- seconds between full marker position refresh
local MARKER_SIZE      = 16                      -- icon size in pixels
local ICON_POOL_SIZE   = 20                      -- pre-allocated icon frames

local DIRS             = {
    { label = "N",  angle = 0 },
    { label = "NE", angle = 45 },
    { label = "E",  angle = 90 },
    { label = "SE", angle = 135 },
    { label = "S",  angle = 180 },
    { label = "SW", angle = 225 },
    { label = "W",  angle = 270 },
    { label = "NW", angle = 315 },
}

--#endregion

--#region ── Helpers ───────────────────────────────────────────────────────────

-- Returns a compass bearing (0°=N, clockwise) from two WoW map-fraction positions.
-- WoW map coords: X increases East, Y increases South (screen convention).
local function mapBearing(pX, pY, tX, tY)
    local dx = tX - pX
    local dy = tY - pY
    return (math.atan2(dx, -dy) * (180 / math.pi) + 360) % 360
end

--#endregion

--#region ── Markers ───────────────────────────────────────────────────────────

local iconPool = {} -- populated in createFrame()

local function rebuildQuestMarkers()
    local mapID     = C_Map.GetBestMapForUnit("player")
    local playerPos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not playerPos then return end

    local pois = C_QuestLog.GetQuestsOnMap(mapID)
    if not pois then return end

    for _, info in ipairs(pois) do
        if info.x and info.y then
            compass.markers[#compass.markers + 1] = {
                bearing = mapBearing(playerPos.x, playerPos.y, info.x, info.y),
                texture = 'interface/questframe/questlogframe2x',
                atlas   = "QuestLog-tab-icon-quest",
                r       = 1,
                g       = 0.8,
                b       = 0,
            }
        end
    end
end

local function rebuildPoiMarkers()
    local mapID     = C_Map.GetBestMapForUnit("player")
    local playerPos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not playerPos then return end

    ---@diagnostic disable-next-line: missing-parameter
    for _, poiID in ipairs(C_AreaPoiInfo.GetAreaPOIForMap(mapID) or {}) do
        local info = C_AreaPoiInfo.GetAreaPOIInfo(_, poiID)
        ---@diagnostic disable-next-line: undefined-field
        if info and info.position then
            compass.markers[#compass.markers + 1] = {
                ---@diagnostic disable-next-line: undefined-field
                bearing = mapBearing(playerPos.x, playerPos.y, info.position.x, info.position.y),
                atlas = info.atlasName,
                r = 1,
                g = 1,
                b = 1,
            }
        end
    end
end

-- Read tracking-node blips from the live Minimap child frames.
-- Filter: unnamed, visible, centre falls within the minimap circle.
-- NOTE: blip frame identification may need in-game tuning; this is intentionally
-- broad so it picks up any icon rendered inside the minimap circle.
local function rebuildTrackingMarkers()
    local cx, cy   = Minimap:GetCenter()
    local mRadius  = Minimap:GetWidth() / 2
    local rotating = GetCVar("rotateMinimap") == "1"

    for _, child in ipairs({ Minimap:GetChildren() }) do
        if not child:GetName() and child:IsVisible() then
            local bx, by = child:GetCenter()
            if bx and by then
                local dx   = bx - cx
                local dy   = by - cy
                local dist = math.sqrt(dx * dx + dy * dy)
                -- dist > 2 excludes the centre-pin (player dot) at ~0,0
                if dist > 2 and dist <= mRadius * 1.05 then
                    local screenBearing =
                        (math.atan2(dx, -dy) * (180 / math.pi) + 360) % 360
                    local worldBearing
                    if rotating then
                        -- rotating minimap: screen-up = player's current heading
                        worldBearing = (screenBearing + compass.displayedHeading) % 360
                    else
                        -- fixed minimap: screen-up = North
                        worldBearing = screenBearing
                    end
                    -- Prefer Button's NormalTexture; frame-with-texture falls back to nil
                    ---@diagnostic disable-next-line: undefined-field
                    local tex = child.GetNormalTexture and child:GetNormalTexture()
                    compass.markers[#compass.markers + 1] = {
                        bearing = worldBearing,
                        texture = tex,
                        r = 1,
                        g = 1,
                        b = 1,
                    }
                end
            end
        end
    end
end

function compass:rebuildMarkers()
    self.markers = {}
    rebuildQuestMarkers()
    -- rebuildPoiMarkers()
    -- rebuildTrackingMarkers()
end

-- Called every frame. Assigns visible markers to pool slots; hides the rest.
local function renderMarkers()
    local half = VISIBLE_DEG / 2
    local slot = 1

    for _, m in ipairs(compass.markers) do
        local diff = ((m.bearing - compass.displayedHeading + 540) % 360) - 180
        if math.abs(diff) <= half and slot <= ICON_POOL_SIZE then
            local f = iconPool[slot]
            f:ClearAllPoints()
            f:SetPoint("CENTER", container, "CENTER", diff * PX_PER_DEG, 0)
            if m.atlas then
                f.tex:SetAtlas(m.atlas)
            elseif m.texture then
                f.tex:SetTexture(m.texture)
            end
            f.tex:SetVertexColor(m.r, m.g, m.b)
            f:Show()
            slot = slot + 1
        end
    end

    for i = slot, ICON_POOL_SIZE do
        iconPool[i]:Hide()
    end
end

--#endregion

--#region ── Frame ─────────────────────────────────────────────────────────────

local function addLabel(text, x)
    local fs = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetPoint("CENTER", strip, "TOPLEFT", x, -BAR_HEIGHT / 2)
end

local function createFrame()
    -- Outer container: clips everything to the visible bar width
    container = CreateFrame("Frame", "CTCompassBar", UIParent)
    container:SetSize(BAR_WIDTH, BAR_HEIGHT)
    container:SetPoint("TOP", UIParent, "TOP", 0, -10)
    container:SetClipsChildren(true)

    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    -- Strip: scrolls horizontally to show the current heading
    strip = CreateFrame("Frame", nil, container)
    strip:SetSize(STRIP_WIDTH, BAR_HEIGHT)
    strip:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)

    for _, dir in ipairs(DIRS) do
        local x = (dir.angle + 45) * PX_PER_DEG
        addLabel(dir.label, x)
        if dir.angle <= 45 then
            addLabel(dir.label, x + 360 * PX_PER_DEG)
        elseif dir.angle >= 315 then
            addLabel(dir.label, x - 360 * PX_PER_DEG)
        end
    end

    -- Icon pool: sits above the strip, clipped by container
    local poolLevel = container:GetFrameLevel() + 3
    for i = 1, ICON_POOL_SIZE do
        local f = CreateFrame("Frame", nil, container)
        f:SetSize(MARKER_SIZE, MARKER_SIZE)
        f:SetFrameLevel(poolLevel)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        f.tex = tex
        f:Hide()
        iconPool[i] = f
    end

    -- Centre tick mark — drawn last so it's always on top
    local tick = container:CreateTexture(nil, "OVERLAY")
    tick:SetSize(2, BAR_HEIGHT)
    tick:SetPoint("CENTER", container, "CENTER", 0, 0)
    tick:SetColorTexture(1, 1, 1, 0.8)

    local elapsed       = 0
    local markerElapsed = 0
    container:SetScript("OnUpdate", function(_, dt)
        -- Sample player facing at reduced rate
        elapsed = elapsed + dt
        if elapsed >= UPDATE_HZ then
            elapsed = 0
            local facing = GetPlayerFacing()
            if facing then
                -- GetPlayerFacing: 0=North, increases CCW (N→W→S→E)
                -- Negate to convert to clockwise compass heading
                compass.targetHeading = (-facing * (180 / math.pi)) % 360
            end
        end

        -- Smooth heading toward target every frame
        local diff = ((compass.targetHeading - compass.displayedHeading + 540) % 360) - 180
        compass.displayedHeading =
            (compass.displayedHeading + diff * (1 - math.exp(-LERP_SPEED * dt))) % 360

        -- Single strip reposition
        strip:ClearAllPoints()
        strip:SetPoint("TOPLEFT", container, "TOPLEFT",
            -compass.displayedHeading * PX_PER_DEG, 0)

        -- Rebuild marker bearings every second; render every frame
        markerElapsed = markerElapsed + dt
        if markerElapsed >= MARKER_UPDATE_HZ then
            markerElapsed = 0
            compass:rebuildMarkers()
        end
        renderMarkers()
    end)
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────

function compass:OnEnable()
    if not container then createFrame() end

    local facing          = GetPlayerFacing()
    local initial         = facing and ((-facing * (180 / math.pi)) % 360) or 0
    self.targetHeading    = initial
    self.displayedHeading = initial
    self.markers          = {}

    self:RegisterEvent("QUEST_WATCH_LIST_CHANGED", "rebuildMarkers")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "rebuildMarkers")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "rebuildMarkers")
    self:RegisterEvent("MINIMAP_UPDATE_TRACKING", "rebuildMarkers")
    self:RegisterEvent("MINIMAP_UPDATE_ZOOM", "rebuildMarkers")

    self:rebuildMarkers()
    container:Show()
end

function compass:OnDisable()
    self:UnregisterAllEvents()
    if container then container:Hide() end
end

--#endregion

--#region ── Options ───────────────────────────────────────────────────────────

function compass:GetDefaults()
    return {
        compass = {
            enabled = true,
        },
    }
end

function compass:GetOptions()
    return 'compass', {
        name  = 'Compass',
        type  = 'group',
        order = 7,
        args  = {
            description = {
                name  = 'A Skyrim-style ribbon compass showing cardinal headings.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Show the ribbon compass at the top of the screen.',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.compass.enabled end,
                set   = function(_, value)
                    addon.db.profile.compass.enabled = value
                    if value then compass:Enable() else compass:Disable() end
                end,
            },
        },
    }
end

--#endregion

compass:Enable()
