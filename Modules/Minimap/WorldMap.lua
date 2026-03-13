local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod = addon:GetModule('Minimap')

-- Cache globals for performance and style guide compliance
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

local TRANSITION_DURATION = 0.25

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

    scroll_child:SetScript("OnSizeChanged", function(_, sw, sh)
        cached_child_w, cached_child_h = sw, sh
    end)
    minimod.wrapper:SetScript("OnSizeChanged", function(_, ww, wh)
        cached_wrap_w, cached_wrap_h = ww, wh
    end)

    local function apply_zoom(z)
        zoom = math_max(min_zoom, math_min(z, max_zoom))
        scroll_child:SetScale(zoom)
        local map_id = map_frame.GetMapID and map_frame:GetMapID()
        if map_id then
            local pos = C_Map.GetPlayerMapPosition(map_id, "player")
            if pos then
                scroll_container:SetHorizontalScroll((pos.x * cached_child_w) - (cached_wrap_w / (2 * zoom)))
                scroll_container:SetVerticalScroll((pos.y * cached_child_h) - (cached_wrap_h / (2 * zoom)))
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

    scroll_container:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 and zoom >= max_zoom then
            minimod.closeWorldMap()
            return
        end
        apply_zoom(zoom * (delta > 0 and 1.25 or 0.8))
    end)

    scroll_container:SetScript("OnUpdate", function()
        local map_id = map_frame.GetMapID and map_frame:GetMapID()
        if not map_id then return end
        local pos = C_Map.GetPlayerMapPosition(map_id, "player")
        if not pos then return end
        scroll_container:SetHorizontalScroll((pos.x * cached_child_w) - (cached_wrap_w / (2 * zoom)))
        scroll_container:SetVerticalScroll((pos.y * cached_child_h) - (cached_wrap_h / (2 * zoom)))
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
        zoom_entry = cached_wrap_w / 2000
        min_zoom = zoom_entry * 0.53
        max_zoom = zoom_entry * 1.24
        zoom = zoom_entry
        scroll_child:SetScale(zoom_entry)
    end

    map_frame:EnableMouse(true)
    map_frame:EnableMouseWheel(true)

    if _G.BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        local detail_dp = CreateFromMixins(_G.BaseMapCanvasDetailLayerMixin) ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(detail_dp)
        detail_dp.AdjustDetailLayerAlpha = function() end
    end
    if _G.MapCanvasCursorDataProviderMixin then ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(CreateFromMixins(_G.MapCanvasCursorDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Register pin frame levels needed by the providers below.
    local plm = map_frame:GetPinFrameLevelsManager()
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION_TEXTURE") -- MapExplorationDataProvider
    plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_VIGNETTE", 200)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_WORLD_QUEST", 500)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", C_QuestLog.GetMaxNumQuests())
    plm:AddFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")

    if _G.GroupMembersPinMixin and not _G.GroupMembersPinMixin._ct_patched then ---@diagnostic disable-line: undefined-global
        local _orig = _G.GroupMembersPinMixin.OnHide ---@diagnostic disable-line: undefined-global
        _G.GroupMembersPinMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.dataProvider then _orig(self) end
        end
        _G.GroupMembersPinMixin._ct_patched = true ---@diagnostic disable-line: undefined-global
    end

    -- World Quests
    if _G.WorldQuestDataProviderMixin and not _G.WorldQuestDataProviderMixin._ct_patched then ---@diagnostic disable-line: undefined-global
        local _orig = _G.WorldQuestDataProviderMixin.OnHide ---@diagnostic disable-line: undefined-global
        _G.WorldQuestDataProviderMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.ticker then _orig(self) end
        end
        _G.WorldQuestDataProviderMixin._ct_patched = true ---@diagnostic disable-line: undefined-global
    end

    -- Fog of War removal
    if _G.MapExplorationDataProviderMixin then ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(CreateFromMixins(_G.MapExplorationDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Player arrow + party/raid members
    if _G.GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(CreateFromMixins(_G.GroupMembersDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Active quest pins
    if _G.QuestDataProviderMixin then ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(CreateFromMixins(_G.QuestDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- World quests + bounties (same config as WorldMapFrame)
    if _G.WorldQuestDataProviderMixin then ---@diagnostic disable-line: undefined-global
        local wq_dp = CreateFromMixins(_G.WorldQuestDataProviderMixin) ---@diagnostic disable-line: undefined-global
        wq_dp:SetMatchWorldMapFilters(true)
        wq_dp:SetUsesSpellEffect(true)
        wq_dp:SetCheckBounties(true)
        map_frame:AddDataProvider(wq_dp)
    end

    -- Rare/treasure vignettes
    if _G.VignetteDataProviderMixin then ---@diagnostic disable-line: undefined-global
        map_frame:AddDataProvider(CreateFromMixins(_G.VignetteDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    minimod.worldMap = map_frame
end

minimod.openWorldMap = function()
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

        local pos = C_Map.GetPlayerMapPosition(map_id, "player")
        if pos then
            local sc = minimod.worldMap.ScrollContainer
            local cw, ch = sc.Child:GetSize()
            local vw, vh = minimod.wrapper:GetSize()
            local entry_zoom = sc:GetZoom()
            sc:SetHorizontalScroll(pos.x * cw - vw / (2 * entry_zoom))
            sc:SetVerticalScroll(pos.y * ch - vh / (2 * entry_zoom))
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
