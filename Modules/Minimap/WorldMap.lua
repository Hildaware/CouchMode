local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod = addon:GetModule('Minimap')

local _G = _G
local math_min = math.min
local math_max = math.max
local pairs = pairs
local pcall = pcall

local CreateFrame = _G.CreateFrame
local C_AddOns = _G.C_AddOns
local C_Map = _G.C_Map
local C_QuestLog = _G.C_QuestLog
local Mixin = _G.Mixin
local CreateFromMixins = _G.CreateFromMixins
local GetCursorPosition = _G.GetCursorPosition
local Minimap = _G.Minimap

local ConsolePort = _G['ConsolePort'] ---@type any

-- Maps each world-map toolbar button field to its db toggle key.
-- Used by openWorldMap/closeWorldMap to sync all buttons in one loop.
-- Also exposed on minimod so MinimapFrame.lua can build the D-pad button list.
minimod.WM_BUTTON_DEFS = {
    { btn = "wmBtnWQ",       db = "worldMapShowWorldQuests" },
    { btn = "wmBtnAQ",       db = "worldMapShowActiveQuests" },
    { btn = "wmBtnLS",       db = "worldMapShowLocalStories" },
    { btn = "wmBtnDungeons", db = "worldMapShowDungeons" },
    { btn = "wmBtnDelves",   db = "worldMapShowDelves" },
    { btn = "wmBtnEvents",   db = "worldMapShowEvents" },
    { btn = "wmBtnTravel",   db = "worldMapShowTravel" },
}

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
    if minimod.worldMap then return end

    if not _G.MapCanvasMixin or not _G.BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_MapCanvas")
    end
    if not _G.GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_SharedMapDataProviders")
    end

    local map_frame = CreateFrame("Frame", nil, minimod.wrapper)
    map_frame:SetAllPoints(minimod.wrapper)

    -- ScrollContainer required by MapCanvasMixin
    local scroll_container = CreateFrame("ScrollFrame", nil, map_frame)
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
    local cached_wrap_w, cached_wrap_h = minimod.wrapper:GetSize()

    local is_panning = false
    local has_panned = false
    local drag_start_x, drag_start_y = 0, 0
    local drag_start_scroll_h, drag_start_scroll_v = 0, 0

    scroll_child:SetScript("OnSizeChanged", function(_, sw, sh)
        cached_child_w, cached_child_h = sw, sh
    end)
    minimod.wrapper:SetScript("OnSizeChanged", function(_, ww, wh)
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
        elseif addon.db.profile.minimap.worldMapCentered then
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

        -- Notify pins to update their scale (counter-scale) so they remain static size
        for _, pool in pairs(map_frame.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.ApplyCurrentScale then
                    pin:ApplyCurrentScale()
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

    function scroll_container:GetCanvasZoomPercent() return 0 end

    function scroll_container:GetCurrentLayerIndex() return 1 end

    function scroll_container:MarkCanvasDirty() end

    function scroll_container:MarkAreaTriggersDirty() end

    function scroll_container:GetCursorPosition()
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale()
        return x / s, y / s
    end

    --#endregion

    scroll_container:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        is_panning = true
        has_panned = true
        local s = scroll_container:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        drag_start_x = cx / s
        drag_start_y = cy / s
        drag_start_scroll_h = scroll_container:GetHorizontalScroll()
        drag_start_scroll_v = scroll_container:GetVerticalScroll()
    end)

    scroll_container:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        is_panning = false
    end)

    scroll_container:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 and zoom >= max_zoom then
            minimod.closeWorldMap()
            return
        end
        apply_zoom(zoom * (delta > 0 and 1.25 or 0.8))
    end)

    scroll_container:SetScript("OnUpdate", function()
        if is_panning then
            local s = scroll_container:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local dx = cx / s - drag_start_x
            local dy = cy / s - drag_start_y
            scroll_container:SetHorizontalScroll(drag_start_scroll_h - dx / zoom)
            scroll_container:SetVerticalScroll(drag_start_scroll_v + dy / zoom)
            return
        end
        if has_panned then return end
        if addon.db.profile.minimap.worldMapCentered then return end
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

    if map_frame.OnLoad then map_frame:OnLoad() end

    local _orig_refresh = map_frame.RefreshDetailLayers
    if _orig_refresh then
        map_frame.RefreshDetailLayers = function(self)
            pcall(_orig_refresh, self)
        end
    end

    -- Zoom constants are derived from the current wrapper width so visual quality
    -- (art pixels per viewport pixel) stays constant regardless of db.growSize.
    -- Reference: 500px growSize → ZOOM_ENTRY 0.25 → 500/0.25 = 2000 art px visible.
    minimod.resetWorldMapZoom = function()
        has_panned = false
        zoom_entry = cached_wrap_w / 2000
        min_zoom = zoom_entry * 0.52
        max_zoom = zoom_entry * 1.24
        zoom = zoom_entry
        scroll_child:SetScale(zoom_entry)
    end

    map_frame:EnableMouse(true)
    map_frame:EnableMouseWheel(true)

    -- Register pin frame levels needed by the providers below.
    local plm = map_frame:GetPinFrameLevelsManager()
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION_TEXTURE")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_VIGNETTE", 200)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_WORLD_QUEST", 500)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", C_QuestLog.GetMaxNumQuests())
    plm:AddFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")
    if _G.QuestOfferDataProviderMixin then ---@diagnostic disable-line: undefined-global
        plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_OFFER", _G.QuestOfferDataProviderMixin.PIN_LEVEL_RANGE) ---@diagnostic disable-line: undefined-global, undefined-field
    end
    plm:AddFrameLevel("PIN_FRAME_LEVEL_DUNGEON_ENTRANCE")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_DELVE_ENTRANCE")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_AREA_POI_EVENT")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_FLIGHT_POINT")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_LINK")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_AREA_POI")

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
    -- store_field saves the ref on minimod. setup_fn(dp) runs after creation.
    local function add_provider(mixin_name, store_field, db_key, setup_fn)
        local mixin = _G[mixin_name] ---@diagnostic disable-line: undefined-global
        if not mixin then return end
        local dp = db_key and make_toggleable_dp(mixin, db_key) or CreateFromMixins(mixin)
        if setup_fn then setup_fn(dp) end
        if store_field then minimod[store_field] = dp end
        map_frame:AddDataProvider(dp)
    end

    add_provider("BaseMapCanvasDetailLayerMixin", nil, nil,
        function(dp) dp.AdjustDetailLayerAlpha = function() end end)
    add_provider("MapCanvasCursorDataProviderMixin")
    add_provider("MapExplorationDataProviderMixin")
    add_provider("GroupMembersDataProviderMixin")
    add_provider("VignetteDataProviderMixin")
    add_provider("QuestDataProviderMixin", "wmDpActiveQuests", "worldMapShowActiveQuests")
    add_provider("WorldQuestDataProviderMixin", "wmDpWorldQuests", "worldMapShowWorldQuests", function(dp)
        dp:SetMatchWorldMapFilters(true)
        dp:SetUsesSpellEffect(true)
        dp:SetCheckBounties(true)
    end)
    add_provider("QuestOfferDataProviderMixin", "wmDpLocalStories", "worldMapShowLocalStories")
    add_provider("DungeonEntranceDataProviderMixin", "wmDpDungeons", "worldMapShowDungeons")
    add_provider("DelveEntranceDataProviderMixin", "wmDpDelves", "worldMapShowDelves")
    add_provider("AreaPOIEventDataProviderMixin", "wmDpEvents", "worldMapShowEvents")
    add_provider("FlightPointDataProviderMixin", "wmDpTravel", "worldMapShowTravel")
    add_provider("MapLinkDataProviderMixin", "wmDpPortals", "worldMapShowTravel")
    add_provider("AreaPOIDataProviderMixin", "wmDpAreaPOI", "worldMapShowTravel")

    minimod.worldMap = map_frame
end

minimod.openWorldMap = function()
    if ConsolePort then
        ConsolePort:AddInterfaceCursorFrame(minimod.wrapper)
    end

    minimod.worldMapOpen = true
    create_world_map()
    if minimod.resetWorldMapZoom then minimod.resetWorldMapZoom() end

    local map_id = C_Map.GetBestMapForUnit("player")
    if map_id then
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(map_id)
        local layer = layers and layers[1]
        if layer and layer.layerWidth and layer.layerWidth > 0 then
            minimod.worldMapArtW = layer.layerWidth
            minimod.worldMapArtH = layer.layerHeight
            minimod.worldMap.ScrollContainer.Child:SetSize(layer.layerWidth, layer.layerHeight)
        end

        for _, pool in pairs(minimod.worldMap.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.OnCanvasSizeChanged then pin:OnCanvasSizeChanged() end
                if pin.ApplyCurrentPosition then pin:ApplyCurrentPosition() end
            end
        end

        minimod.worldMap:SetMapID(map_id)

        local sc = minimod.worldMap.ScrollContainer
        local cw, ch = sc.Child:GetSize()
        local vw, vh = minimod.wrapper:GetSize()
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
    end

    -- Swap toolbar buttons: hide minimap-only, show + sync world map filters
    if minimod.trackingBtn then minimod.trackingBtn:Hide() end
    local wm_db = addon.db.profile.minimap
    for _, def in ipairs(minimod.WM_BUTTON_DEFS) do
        local btn = minimod[def.btn]
        if btn then
            btn:SetAlpha(wm_db[def.db] and 1 or 0.4); btn:Show()
        end
    end

    minimod.worldMap:SetAlpha(0)
    minimod.worldMap:Show()
    minimod.startFrameFade(minimod.worldMap, minimod.worldMapFade, 1)
    minimod.startFrameFade(Minimap, minimod.minimapFade, 0)
end

minimod.closeWorldMap = function()
    minimod.worldMapOpen = false
    minimod.applySettings()

    -- Swap toolbar buttons back: hide world map filters, restore minimap-only buttons
    if minimod.trackingBtn then minimod.trackingBtn:Show() end
    for _, def in ipairs(minimod.WM_BUTTON_DEFS) do
        local btn = minimod[def.btn]
        if btn then btn:Hide() end
    end

    Minimap:SetAlpha(0)
    Minimap:Show()
    Minimap:SetZoom(0)

    if Minimap.ZoomIn and Minimap.ZoomOut then
        Minimap.ZoomIn:Click()
        Minimap.ZoomOut:Click()
    end
    minimod.startFrameFade(Minimap, minimod.minimapFade, 1)
    if minimod.worldMap then
        minimod.startFrameFade(minimod.worldMap, minimod.worldMapFade, 0)
    end
end

--#endregion

minimod:Enable()
