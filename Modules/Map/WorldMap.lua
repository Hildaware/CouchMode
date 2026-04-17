---@diagnostic disable: inject-field

local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule: AceModule
local map = addon:GetModule('Minimap')

local _G = _G
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local pairs = pairs
local pcall = pcall

local CreateFrame = _G.CreateFrame
local C_AddOns = _G.C_AddOns
local C_Map = _G.C_Map
local C_QuestLog = _G.C_QuestLog
local Mixin = _G.Mixin
local CreateFromMixins = _G.CreateFromMixins
local GetCursorPosition = _G.GetCursorPosition

local ConsolePort = _G['ConsolePort'] ---@type any

-- Patches global pin/provider mixins once to fix crashes and add tooltip support.
local function setup_mixin_patches()
    if _G.GroupMembersPinMixin and not _G.GroupMembersPinMixin._ct_patched then ---@diagnostic disable-line: undefined-global
        local _orig = _G.GroupMembersPinMixin.OnHide ---@diagnostic disable-line: undefined-global
        _G.GroupMembersPinMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.dataProvider then _orig(self) end
        end
        _G.GroupMembersPinMixin._ct_patched = true ---@diagnostic disable-line: undefined-global
    end

    if _G.WorldQuestDataProviderMixin and not _G.WorldQuestDataProviderMixin._ct_patched then ---@diagnostic disable-line: undefined-global
        local _orig = _G.WorldQuestDataProviderMixin.OnHide ---@diagnostic disable-line: undefined-global
        _G.WorldQuestDataProviderMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.ticker then _orig(self) end
        end
        _G.WorldQuestDataProviderMixin._ct_patched = true ---@diagnostic disable-line: undefined-global
    end

    if _G.AreaPOIPinMixin and not _G.AreaPOIPinMixin._ct_patched then ---@diagnostic disable-line: undefined-global
        _G.AreaPOIPinMixin.OnMouseEnter = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            local info = self.poiInfo ---@type any
            if not info or not info.name or info.name == "" then return end
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(info.name, 1, 1, 1)
            if info.description and info.description ~= "" then
                _G.GameTooltip:AddLine(info.description, nil, nil, nil, true)
            end
            _G.GameTooltip:Show()
        end
        _G.AreaPOIPinMixin.OnMouseLeave = function() ---@diagnostic disable-line: undefined-global, duplicate-set-field
            _G.GameTooltip:Hide()
        end
        _G.AreaPOIPinMixin._ct_patched = true ---@diagnostic disable-line: undefined-global
    end
end

--#region ── World Map ───────────────────────────────────────────────────────

local function create_world_map()
    if map.worldMap then return end

    if not _G.MapCanvasMixin or not _G.BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-field
        C_AddOns.LoadAddOn("Blizzard_MapCanvas")
    end
    if not _G.GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_SharedMapDataProviders")
    end

    local map_frame = CreateFrame("Frame", nil, map.container)
    map_frame:SetAllPoints(map.container)

    -- ScrollContainer required by MapCanvasMixin
    local scroll_container = CreateFrame("ScrollFrame", nil, map_frame) ---@type CTScrollContainer
    scroll_container:SetAllPoints()
    map_frame.ScrollContainer = scroll_container

    local scroll_child = CreateFrame("Frame", nil, scroll_container)
    scroll_child:SetSize(2048, 2048)
    scroll_container:SetScrollChild(scroll_child)
    scroll_container.Child = scroll_child

    scroll_child.TiledBackground = scroll_child:CreateTexture(nil, "BACKGROUND")
    scroll_child.TiledBackground:SetAllPoints()

    -- Black background fills the frame area behind map tiles
    local map_bg = map_frame:CreateTexture(nil, "BACKGROUND")
    map_bg:SetAllPoints(map_frame)
    map_bg:SetColorTexture(0, 0, 0, 0.75)

    map_frame.BorderFrame = CreateFrame("Frame", nil, map_frame)

    local zoom_entry = 0.25
    local min_zoom = 0.12
    local max_zoom = 0.30
    local zoom = zoom_entry

    local cached_child_w, cached_child_h = scroll_child:GetSize()
    local cached_wrap_w, cached_wrap_h = map.container:GetSize()

    local is_panning = false
    local drag_moved = false
    local has_panned = false
    local force_centered = false
    local drag_start_x, drag_start_y = 0, 0
    local drag_start_scroll_h, drag_start_scroll_v = 0, 0
    local DRAG_THRESHOLD = 4 -- pixels before a press is considered a drag

    scroll_child:SetScript("OnSizeChanged", function(_, sw, sh)
        cached_child_w, cached_child_h = sw, sh
    end)
    map.container:SetScript("OnSizeChanged", function(_, ww, wh)
        cached_wrap_w, cached_wrap_h = ww, wh
    end)

    local function apply_zoom(z)
        local old_zoom = zoom
        zoom = math_max(min_zoom, math_min(z, max_zoom))
        scroll_child:SetScale(zoom)

        local half_w_zoom = cached_wrap_w / (2 * zoom)
        local half_h_zoom = cached_wrap_h / (2 * zoom)

        if has_panned then
            -- Keep the same canvas point at the viewport center after the scale change
            local zoom_diff = (1 / (2 * old_zoom)) - (1 / (2 * zoom))
            scroll_container:SetHorizontalScroll(scroll_container:GetHorizontalScroll() + cached_wrap_w * zoom_diff)
            scroll_container:SetVerticalScroll(scroll_container:GetVerticalScroll() + cached_wrap_h * zoom_diff)
        elseif addon.db.profile.minimap.worldMapCentered or force_centered then
            scroll_container:SetHorizontalScroll(cached_child_w / 2 - half_w_zoom)
            scroll_container:SetVerticalScroll(cached_child_h / 2 - half_h_zoom)
        else
            local map_id = map_frame.GetMapID and map_frame:GetMapID()
            if map_id then
                local pos = C_Map.GetPlayerMapPosition(map_id, "player")
                if pos then
                    scroll_container:SetHorizontalScroll((pos.x * cached_child_w) - half_w_zoom)
                    scroll_container:SetVerticalScroll((pos.y * cached_child_h) - half_h_zoom)
                end
            end
        end

        -- GroupMembersPinMixin (and any other pin using ignoreGlobalPinScale) manages
        -- its own icon sizes via SynchronizePinSizes(), triggered by OnCanvasScaleChanged.
        -- The real scroll controller calls this; we must do it ourselves.
        pcall(map_frame.OnCanvasScaleChanged, map_frame)

        -- Standard MapCanvasPinMixin pins (world quests etc.) use C-side ApplyCurrentScale
        -- which doesn't read our Lua GetCanvasScale() stub. Override with correct value.
        -- Pins with ignoreGlobalPinScale manage their own sizing (e.g. GroupMembers) so skip.
        local counter_scale = zoom > 0 and (1 / zoom) or 1
        for _, pool in pairs(map_frame.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if not pin.ignoreGlobalPinScale then
                    pin:SetScale(counter_scale)
                end
            end
        end
    end

    --#region Stubs
    function scroll_container:GetZoom() return zoom end

    function scroll_container:SetZoomTarget(z) apply_zoom(z) end

    function scroll_container:SetMapID() end

    function scroll_container:SetPanTarget() end

    function scroll_container:OnCanvasSizeChanged() end

    function scroll_container:OnLoad() end

    function scroll_container:OnShow() end

    function scroll_container:OnHide() end

    function scroll_container:GetCanvasScale() return zoom end

    function scroll_container:DenormalizeHorizontalSize(size) return size * scroll_child:GetWidth() end

    function scroll_container:DenormalizeVerticalSize(size) return size * scroll_child:GetHeight() end

    function scroll_container:NormalizeHorizontalSize(size)
        local w = scroll_child:GetWidth()
        return w > 0 and size / w or 0
    end

    function scroll_container:NormalizeVerticalSize(size)
        local h = scroll_child:GetHeight()
        return h > 0 and size / h or 0
    end

    function scroll_container:IsAtMaxZoom() return zoom >= max_zoom end

    function scroll_container:IsAtMinZoom() return zoom <= min_zoom end

    function scroll_container:GetCanvasZoomPercent() return 0 end

    function scroll_container:GetCurrentLayerIndex() return 1 end

    function scroll_container:MarkCanvasDirty() end

    function scroll_container:MarkAreaTriggersDirty() end

    function scroll_container:AdjustDetailLayerAlpha() end

    function scroll_container:GetCursorPosition()
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale()
        return x / s, y / s
    end

    function scroll_container:GetNormalizedCursorPosition()
        local x, y = self:GetCursorPosition()
        local scale = self:GetCanvasScale()
        if scale == 0 then scale = 1 end
        local left = scroll_child:GetLeft() or 0
        local top = scroll_child:GetTop() or 0
        return Saturate(self:NormalizeHorizontalSize(x / scale - left)),
            Saturate(self:NormalizeVerticalSize(top - y / scale))
    end

    --#endregion

    scroll_container:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        is_panning = true
        drag_moved = false
        has_panned = true
        force_centered = false
        local s = scroll_container:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        drag_start_x = cx / s
        drag_start_y = cy / s
        drag_start_scroll_h = scroll_container:GetHorizontalScroll()
        drag_start_scroll_v = scroll_container:GetVerticalScroll()
    end)

    scroll_container:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            is_panning = false
            if not drag_moved then
                local nx, ny = scroll_container:GetNormalizedCursorPosition()
                local mapInfo = C_Map.GetMapInfoAtPosition(map_frame:GetMapID(), nx, ny)
                if mapInfo then
                    map.navigateToChildMap(mapInfo.mapID)
                end
            end
        elseif button == "RightButton" then
            map.navigateToParentMap()
        end
    end)

    scroll_container:SetScript("OnMouseWheel", function(_, delta)
        map.zoomWorldMap(delta)
    end)

    scroll_container:SetScript("OnUpdate", function()
        if is_panning then
            local s = scroll_container:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local dx = cx / s - drag_start_x
            local dy = cy / s - drag_start_y
            if not drag_moved and (math.abs(dx) + math.abs(dy)) > DRAG_THRESHOLD then
                drag_moved = true
            end
            scroll_container:SetHorizontalScroll(drag_start_scroll_h - dx / zoom)
            scroll_container:SetVerticalScroll(drag_start_scroll_v + dy / zoom)
            return
        end
        if has_panned then return end
        if addon.db.profile.minimap.worldMapCentered or force_centered then return end
        local map_id = map_frame.GetMapID and map_frame:GetMapID()
        if not map_id then return end
        local pos = C_Map.GetPlayerMapPosition(map_id, "player")
        if not pos then return end

        local half_w_zoom = cached_wrap_w / (2 * zoom)
        local half_h_zoom = cached_wrap_h / (2 * zoom)

        scroll_container:SetHorizontalScroll((pos.x * cached_child_w) - half_w_zoom)
        scroll_container:SetVerticalScroll((pos.y * cached_child_h) - half_h_zoom)
    end)

    scroll_container:EnableMouse(true)
    scroll_container:EnableMouseWheel(true)

    Mixin(map_frame, _G.MapCanvasMixin)
    map_frame:SetScript("OnShow", map_frame.OnShow)
    map_frame:SetScript("OnHide", map_frame.OnHide)
    map_frame:SetScript("OnEvent", map_frame.OnEvent)

    -- AreDetailLayersLoaded stalls the exploration overlay because our scroll_container
    -- is not a MapCanvasScrollControllerMixin so its detail layers never report as loaded.
    -- Override to let the exploration pin restore alpha immediately.
    map_frame.AreDetailLayersLoaded = function() return true end

    if map_frame.OnLoad then map_frame:OnLoad() end

    -- Hook AcquirePin to counter-scale pins on creation.
    if map_frame.AcquirePin then
        hooksecurefunc(map_frame, "AcquirePin", function(self, pinTemplate)
            local pool = self.pinPools and self.pinPools[pinTemplate]
            if pool then
                pool:EnumerateActive(function(pin)
                    if not pin.ignoreGlobalPinScale then
                        pin:SetScale(zoom > 0 and (1 / zoom) or 1)
                    end
                end)
            end
        end)
    end

    local _orig_refresh = map_frame.RefreshDetailLayers
    if _orig_refresh then
        map_frame.RefreshDetailLayers = function(self)
            pcall(_orig_refresh, self)
        end
    end

    -- Zoom constants are derived from the current container width so visual quality
    -- (art pixels per viewport pixel) stays constant regardless of db.growSize.
    -- Reference: 500px growSize → ZOOM_ENTRY 0.25 → 500/0.25 = 2000 art px visible.
    map.resetWorldMapZoom = function()
        has_panned = false
        force_centered = false
        local art_w = map.worldMapArtW or 2048
        local art_h = map.worldMapArtH or 2048
        local fit_zoom = math.min(cached_wrap_w / art_w, cached_wrap_h / art_h)
        zoom_entry = math.max(fit_zoom, math.min(fit_zoom * 2, cached_wrap_w / 2000))
        min_zoom = fit_zoom
        max_zoom = zoom_entry * 2
        zoom = zoom_entry
        scroll_child:SetScale(zoom_entry)
        map.worldMapMinZoom = min_zoom
        map.worldMapMaxZoom = max_zoom
    end

    map.setForceCentered = function(v) force_centered = v end

    map.navigateToParentMap = function()
        if not map.worldMap then return false end
        local currentMapID = map.worldMap:GetMapID()
        if not currentMapID then return false end

        local info = C_Map.GetMapInfo(currentMapID)
        local parentID = info and info.parentMapID
        if not parentID or parentID <= 0 then return false end

        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(parentID)
        local layer = layers and layers[1]
        if layer and layer.layerWidth and layer.layerWidth > 0 then
            map.worldMapArtW = layer.layerWidth
            map.worldMapArtH = layer.layerHeight
            scroll_child:SetSize(layer.layerWidth, layer.layerHeight)
        end

        map.resetWorldMapZoom()
        map.worldMap:SetMapID(parentID)

        local sc = map.worldMap.ScrollContainer
        sc:SetZoomTarget(map.worldMapMinZoom)

        local cw, ch = sc.Child:GetSize()
        local vw, vh = map.container:GetSize()
        local z = sc:GetZoom()
        if z > 0 then
            sc:SetHorizontalScroll(cw / 2 - vw / (2 * z))
            sc:SetVerticalScroll(ch / 2 - vh / (2 * z))
        end

        force_centered = true

        if map_frame.OnCanvasSizeChanged then
            pcall(map_frame.OnCanvasSizeChanged, map_frame)
        end

        for _, pool in pairs(map_frame.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.ApplyCurrentPosition then
                    pcall(pin.ApplyCurrentPosition, pin)
                end
            end
        end

        map_frame:RefreshAllDataProviders()

        return true
    end

    map.navigateToChildMap = function(childMapID)
        if not map.worldMap then return end

        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(childMapID)
        local layer = layers and layers[1]
        if layer and layer.layerWidth and layer.layerWidth > 0 then
            map.worldMapArtW = layer.layerWidth
            map.worldMapArtH = layer.layerHeight
            scroll_child:SetSize(layer.layerWidth, layer.layerHeight)
        end

        map.resetWorldMapZoom()
        map.worldMap:SetMapID(childMapID)

        local sc = map.worldMap.ScrollContainer
        sc:SetZoomTarget(map.worldMapMinZoom)

        local cw, ch = sc.Child:GetSize()
        local vw, vh = map.container:GetSize()
        local z = sc:GetZoom()
        if z > 0 then
            sc:SetHorizontalScroll(cw / 2 - vw / (2 * z))
            sc:SetVerticalScroll(ch / 2 - vh / (2 * z))
        end

        force_centered = true

        if map_frame.OnCanvasSizeChanged then
            pcall(map_frame.OnCanvasSizeChanged, map_frame)
        end

        for _, pool in pairs(map_frame.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.ApplyCurrentPosition then
                    pcall(pin.ApplyCurrentPosition, pin)
                end
            end
        end

        map_frame:RefreshAllDataProviders()
    end

    map_frame:EnableMouse(true)
    map_frame:EnableMouseWheel(true)

    -- Register pin frame levels needed by the providers below.
    local plm = map_frame:GetPinFrameLevelsManager()
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_HIGHLIGHT")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_VIGNETTE", 200)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_WORLD_QUEST", 500)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", C_QuestLog.GetMaxNumQuests())
    plm:AddFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    if _G.QuestOfferDataProviderMixin then ---@diagnostic disable-line: undefined-global
        plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_OFFER", _G.QuestOfferDataProviderMixin.PIN_LEVEL_RANGE) ---@diagnostic disable-line: undefined-global, undefined-field
    end
    plm:AddFrameLevel("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_DELVE_ENTRANCE")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_AREA_POI_EVENT")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_FLIGHT_POINT")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_LINK")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_AREA_POI")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")

    setup_mixin_patches()

    -- Wraps RefreshAllData to gate on a db toggle; clears pins instead of redrawing when off.
    local function make_toggleable_dp(mixin, db_key)
        local dp = CreateFromMixins(mixin)
        local orig_refresh = dp.RefreshAllData
        if orig_refresh then
            dp.RefreshAllData = function(self, ...)
                if addon.db.profile.minimap[db_key] then
                    return orig_refresh(self, ...)
                end
                self:RemoveAllData()
            end
        end
        return dp
    end

    -- Adds a data provider to map_frame. Passing db_key makes it toggleable and
    -- store_field saves the ref on map. setup_fn(dp) runs after creation.
    local function add_provider(mixin_name, store_field, db_key, setup_fn)
        local mixin = _G[mixin_name] ---@diagnostic disable-line: undefined-global
        if not mixin then return end
        local dp = db_key and make_toggleable_dp(mixin, db_key) or CreateFromMixins(mixin)
        if setup_fn then setup_fn(dp) end
        if store_field then map[store_field] = dp end
        map_frame:AddDataProvider(dp)
    end

    add_provider("BaseMapCanvasDetailLayerMixin", nil, nil,
        function(dp) dp.AdjustDetailLayerAlpha = function() end end)
    add_provider("MapCanvasCursorDataProviderMixin")
    add_provider("MapExplorationDataProviderMixin")
    add_provider("MapHighlightDataProviderMixin", nil, nil, function(dp)
        local orig_added = dp.OnAdded
        dp.OnAdded = function(self, mapCanvas)
            orig_added(self, mapCanvas)
            if self.pin then
                self.pin.ignoreGlobalPinScale = true
                -- Also re-apply position after canvas resizes (map navigation changes canvas size).
                local orig_size_changed = self.pin.OnCanvasSizeChanged
                self.pin.OnCanvasSizeChanged = function(pin)
                    orig_size_changed(pin)
                    pin:ApplyCurrentPosition()
                end
                self.pin:ApplyCurrentPosition()
            end
        end
    end)
    add_provider("AreaLabelDataProviderMixin")
    add_provider("VignetteDataProviderMixin")
    add_provider("QuestDataProviderMixin", "wmDpActiveQuests", "worldMapShowActiveQuests")
    add_provider("WorldQuestDataProviderMixin", "wmDpWorldQuests", "worldMapShowWorldQuests", function(dp)
        dp:SetMatchWorldMapFilters(true)
        dp:SetUsesSpellEffect(true)
        dp:SetCheckBounties(true)
    end)
    add_provider("QuestOfferDataProviderMixin", "wmDpLocalStories", "worldMapShowLocalStories")
    add_provider("DungeonEntranceDataProviderMixin", "wmDpDungeons", "worldMapShowDungeons")
    add_provider("EncounterJournalDataProviderMixin", "wmDpBosses", "worldMapShowDungeons")
    add_provider("DelveEntranceDataProviderMixin", "wmDpDelves", "worldMapShowDelves")
    add_provider("AreaPOIEventDataProviderMixin", "wmDpEvents", "worldMapShowEvents")
    add_provider("FlightPointDataProviderMixin", "wmDpTravel", "worldMapShowTravel")
    add_provider("MapLinkDataProviderMixin", "wmDpPortals", "worldMapShowTravel")
    add_provider("AreaPOIDataProviderMixin", "wmDpAreaPOI", "worldMapShowTravel")
    add_provider("GroupMembersDataProviderMixin")

    map.worldMap = map_frame
end

map.openWorldMap = function()
    if ConsolePort then
        ConsolePort:AddInterfaceCursorFrame(map.container)
    end

    map.worldMapOpen = true
    create_world_map()

    local map_id = C_Map.GetBestMapForUnit("player")
    if map_id then
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(map_id)
        local layer = layers and layers[1]
        if layer and layer.layerWidth and layer.layerWidth > 0 then
            map.worldMapArtW = layer.layerWidth
            map.worldMapArtH = layer.layerHeight
            map.worldMap.ScrollContainer.Child:SetSize(layer.layerWidth, layer.layerHeight)
        end
    end
    if map.resetWorldMapZoom then map.resetWorldMapZoom() end
    if map_id then
        for _, pool in pairs(map.worldMap.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.OnCanvasSizeChanged then pin:OnCanvasSizeChanged() end
                if pin.ApplyCurrentPosition then pin:ApplyCurrentPosition() end
            end
        end

        map.worldMap:SetMapID(map_id)

        local sc = map.worldMap.ScrollContainer

        local open_zoom = map.worldMapMaxZoom
        sc:SetZoomTarget(open_zoom)

        local cw, ch = sc.Child:GetSize()
        local vw, vh = map.container:GetSize()
        local entry_zoom = sc:GetZoom()
        local half_w_zoom = vw / (2 * entry_zoom)
        local half_h_zoom = vh / (2 * entry_zoom)
        if addon.db.profile.minimap.worldMapCentered then
            sc:SetHorizontalScroll(cw / 2 - half_w_zoom)
            sc:SetVerticalScroll(ch / 2 - half_h_zoom)
        else
            local pos = C_Map.GetPlayerMapPosition(map_id, "player")
            if pos then
                sc:SetHorizontalScroll(pos.x * cw - half_w_zoom)
                sc:SetVerticalScroll(pos.y * ch - half_h_zoom)
            end
        end

        if map.worldMap.OnCanvasSizeChanged then
            pcall(map.worldMap.OnCanvasSizeChanged, map.worldMap)
        end
    end

    map.onShowWorldMap()
end

-- Opens the world map at maximum zoom, centered on the map art.
function map.openWorldMapFresh()
    if map.growTransition and map.growTransition.active then
        map.pendingWorldMapOpen = true
        return
    end
    map.openWorldMap()
    if not map.worldMap then return end
    local sc = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
    local min = map.worldMapMinZoom
    if min then sc:SetZoomTarget(min) end
    local cw, ch = sc.Child:GetSize()
    local db = addon.db.profile.minimap ---@type MinimapDB
    local vw = db.growSize
    local vh = db.shape == "rectangle" and math_floor(db.growSize * (2 / 3)) or db.growSize
    local z = sc:GetZoom()
    if z > 0 and cw > 0 then
        sc:SetHorizontalScroll(cw / 2 - vw / (2 * z))
        sc:SetVerticalScroll(ch / 2 - vh / (2 * z))
    end
    map.setForceCentered(true)
end

local UIMapType = _G.Enum and _G.Enum.UIMapType

-- Zone/Dungeon/Micro maps allow internal zoom; Continent/World navigate directly.
local function is_zone_map(mapID)
    if not mapID then return false end
    local info = C_Map.GetMapInfo(mapID)
    return info and info.mapType and info.mapType >= (UIMapType and UIMapType.Zone or 3)
end

-- Walk from the player's zone up the parent chain to find the direct child of parentMapID.
local function get_child_map_for_player(parentMapID)
    local playerMapID = C_Map.GetBestMapForUnit("player")
    if not playerMapID or playerMapID == parentMapID then return nil end
    local candidate = playerMapID
    local seen = {}
    while candidate and not seen[candidate] do
        seen[candidate] = true
        local info = C_Map.GetMapInfo(candidate)
        if not info then break end
        if info.parentMapID == parentMapID then return candidate end
        candidate = info.parentMapID
    end
    return nil
end

function map.zoomWorldMap(delta)
    if not map.worldMap then return end
    local sc = map.worldMap.ScrollContainer ---@diagnostic disable-line: undefined-field
    local currentMapID = map.worldMap:GetMapID()
    if delta > 0 then
        if is_zone_map(currentMapID) then
            -- Zone: zoom within map; at max zoom close and return to minimap
            if sc:IsAtMaxZoom() then
                map.onHideWorldMap()
            else
                sc:SetZoomTarget(sc:GetZoom() * 1.1)
            end
        else
            -- Non-zone: skip internal zoom, jump directly to child toward player's zone
            local childID = get_child_map_for_player(currentMapID)
            if childID then map.navigateToChildMap(childID) end
        end
    else
        if is_zone_map(currentMapID) then
            -- Zone: zoom within map; at min zoom navigate to parent
            if sc:IsAtMinZoom() then
                map.navigateToParentMap()
            else
                sc:SetZoomTarget(sc:GetZoom() * 0.9)
            end
        else
            -- Non-zone: skip internal zoom, jump directly to parent
            map.navigateToParentMap()
        end
    end
end

function map.onShowWorldMap()
    map.setToolbarType(TOOLBAR_BUTTON_TYPE.WORLD_MAP)
    map.worldMap:SetAlpha(0)
    map.worldMap:Show()
    map.startFrameFade(map.worldMap, map.worldMapFade, 1)

    map.onHideMinimap()
end

function map.onHideWorldMap()
    map.worldMapOpen = false
    map.applySettings()

    map.onShowMinimap()

    if map.worldMap then
        map.startFrameFade(map.worldMap, map.worldMapFade, 0, true)
    end
end

--#endregion

map:Enable()
