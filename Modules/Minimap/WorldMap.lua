local addonName           = ...

---@class ConsoleTools: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class MinimapModule: AceModule
local minimod             = addon:GetModule('Minimap')

local TRANSITION_DURATION = 0.25

--#region ── World Map ───────────────────────────────────────────────────────

local function createWorldMap()
    if minimod.worldMap then return end

    if not MapCanvasMixin or not BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_MapCanvas")
    end
    if not GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_SharedMapDataProviders")
    end

    local mapFrame = CreateFrame("Frame", nil, minimod.wrapper)
    mapFrame:SetAllPoints(minimod.wrapper)

    -- ScrollContainer required by MapCanvasMixin
    local scrollContainer = CreateFrame("ScrollFrame", nil, mapFrame)
    scrollContainer:SetAllPoints()
    mapFrame.ScrollContainer = scrollContainer

    local scrollChild = CreateFrame("Frame", nil, scrollContainer)
    scrollChild:SetSize(2048, 2048)
    scrollContainer:SetScrollChild(scrollChild)
    scrollContainer.Child = scrollChild

    scrollChild.TiledBackground = scrollChild:CreateTexture(nil, "BACKGROUND")
    scrollChild.TiledBackground:SetAllPoints()

    -- Black background fills the frame area behind map tiles
    local mapBg = mapFrame:CreateTexture(nil, "BACKGROUND")
    mapBg:SetAllPoints(mapFrame)
    mapBg:SetColorTexture(0, 0, 0, 0.75)

    mapFrame.BorderFrame             = CreateFrame("Frame", nil, mapFrame)

    local ZOOM_ENTRY                 = .25
    local MIN_ZOOM                   = .12
    local MAX_ZOOM                   = .30
    local zoom                       = ZOOM_ENTRY

    local cachedChildW, cachedChildH = scrollChild:GetSize()
    local cachedWrapW, cachedWrapH   = minimod.wrapper:GetSize()

    scrollChild:SetScript("OnSizeChanged", function(_, sw, sh)
        cachedChildW, cachedChildH = sw, sh
    end)
    minimod.wrapper:SetScript("OnSizeChanged", function(_, ww, wh)
        cachedWrapW, cachedWrapH = ww, wh
    end)

    local function applyZoom(z)
        zoom = math.max(MIN_ZOOM, math.min(z, MAX_ZOOM))
        scrollChild:SetScale(zoom)
        local mapID = mapFrame.GetMapID and mapFrame:GetMapID()
        if mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            if pos then
                scrollContainer:SetHorizontalScroll((pos.x * cachedChildW) - (cachedWrapW / (2 * zoom)))
                scrollContainer:SetVerticalScroll((pos.y * cachedChildH) - (cachedWrapH / (2 * zoom)))
            end
        end

        -- Notify pins to update their scale (counter-scale) so they remain static size
        for _, pool in pairs(mapFrame.pinPools or {}) do
            for pin in pool:EnumerateActive() do
                if pin.ApplyCurrentScale then
                    pin:ApplyCurrentScale()
                end
            end
        end
    end


    --#region Stubs
    function scrollContainer:GetZoom() return zoom end

    function scrollContainer:SetZoomTarget(z) applyZoom(z) end

    function scrollContainer:SetMapID() end

    function scrollContainer:SetPanTarget() end

    function scrollContainer:OnCanvasSizeChanged() end

    function scrollContainer:OnLoad() end

    function scrollContainer:OnShow() end

    function scrollContainer:OnHide() end

    function scrollContainer:GetCanvasScale() return zoom end

    function scrollContainer:DenormalizeHorizontalSize(size) return size * scrollChild:GetWidth() end

    function scrollContainer:DenormalizeVerticalSize(size) return size * scrollChild:GetHeight() end

    function scrollContainer:NormalizeHorizontalSize(size)
        local w = scrollChild:GetWidth(); return w > 0 and size / w or 0
    end

    function scrollContainer:NormalizeVerticalSize(size)
        local h = scrollChild:GetHeight(); return h > 0 and size / h or 0
    end

    function scrollContainer:GetCanvasZoomPercent() return 0 end

    function scrollContainer:GetCurrentLayerIndex() return 1 end

    function scrollContainer:MarkCanvasDirty() end

    function scrollContainer:MarkAreaTriggersDirty() end

    function scrollContainer:GetCursorPosition()
        local x, y = GetCursorPosition()
        local s    = self:GetEffectiveScale()
        return x / s, y / s
    end

    --#endregion

    scrollContainer:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 and zoom >= MAX_ZOOM then
            minimod.closeWorldMap()
            return
        end
        applyZoom(zoom * (delta > 0 and 1.25 or 0.8))
    end)

    scrollContainer:SetScript("OnUpdate", function()
        local mapID = mapFrame.GetMapID and mapFrame:GetMapID()
        if not mapID then return end
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then return end
        scrollContainer:SetHorizontalScroll((pos.x * cachedChildW) - (cachedWrapW / (2 * zoom)))
        scrollContainer:SetVerticalScroll((pos.y * cachedChildH) - (cachedWrapH / (2 * zoom)))
    end)

    scrollContainer:EnableMouse(true)
    scrollContainer:EnableMouseWheel(true)

    Mixin(mapFrame, MapCanvasMixin)
    mapFrame:SetScript("OnShow", mapFrame.OnShow)
    mapFrame:SetScript("OnHide", mapFrame.OnHide)
    mapFrame:SetScript("OnEvent", mapFrame.OnEvent)

    if mapFrame.OnLoad then mapFrame:OnLoad() end

    local _origRefresh = mapFrame.RefreshDetailLayers
    if _origRefresh then
        mapFrame.RefreshDetailLayers = function(self)
            pcall(_origRefresh, self)
        end
    end

    -- Zoom constants are derived from the current wrapper width so visual quality
    -- (art pixels per viewport pixel) stays constant regardless of db.growSize.
    -- Reference: 500px growSize → ZOOM_ENTRY 0.25 → 500/0.25 = 2000 art px visible.
    minimod.resetWorldMapZoom = function()
        ZOOM_ENTRY = cachedWrapW / 2000
        MIN_ZOOM   = ZOOM_ENTRY * 0.53
        MAX_ZOOM   = ZOOM_ENTRY * 1.24
        zoom       = ZOOM_ENTRY
        scrollChild:SetScale(ZOOM_ENTRY)
    end

    mapFrame:EnableMouse(true)
    mapFrame:EnableMouseWheel(true)

    if BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        local detailDP = CreateFromMixins(BaseMapCanvasDetailLayerMixin) ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(detailDP)
        detailDP.AdjustDetailLayerAlpha = function() end
    end
    if MapCanvasCursorDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(MapCanvasCursorDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Register pin frame levels needed by the providers below.
    local plm = mapFrame:GetPinFrameLevelsManager()
    plm:AddFrameLevel("PIN_FRAME_LEVEL_MAP_EXPLORATION_TEXTURE") -- MapExplorationDataProvider
    plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_VIGNETTE", 200)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_WORLD_QUEST", 500)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", C_QuestLog.GetMaxNumQuests())
    plm:AddFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")

    if GroupMembersPinMixin and not GroupMembersPinMixin._ctPatched then ---@diagnostic disable-line: undefined-global
        local _orig = GroupMembersPinMixin.OnHide ---@diagnostic disable-line: undefined-global
        GroupMembersPinMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.dataProvider then _orig(self) end
        end
        GroupMembersPinMixin._ctPatched = true ---@diagnostic disable-line: undefined-global
    end

    -- World Quests
    if WorldQuestDataProviderMixin and not WorldQuestDataProviderMixin._ctPatched then ---@diagnostic disable-line: undefined-global
        local _orig = WorldQuestDataProviderMixin.OnHide ---@diagnostic disable-line: undefined-global
        WorldQuestDataProviderMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.ticker then _orig(self) end
        end
        WorldQuestDataProviderMixin._ctPatched = true ---@diagnostic disable-line: undefined-global
    end

    -- Fog of War removal
    if MapExplorationDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(MapExplorationDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Player arrow + party/raid members
    if GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(GroupMembersDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Active quest pins
    if QuestDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(QuestDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- World quests + bounties (same config as WorldMapFrame)
    if WorldQuestDataProviderMixin then ---@diagnostic disable-line: undefined-global
        local wqDP = CreateFromMixins(WorldQuestDataProviderMixin) ---@diagnostic disable-line: undefined-global
        wqDP:SetMatchWorldMapFilters(true)
        wqDP:SetUsesSpellEffect(true)
        wqDP:SetCheckBounties(true)
        mapFrame:AddDataProvider(wqDP)
    end

    -- Rare/treasure vignettes
    if VignetteDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(VignetteDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    minimod.worldMap = mapFrame
end

minimod.openWorldMap = function()
    minimod.worldMapOpen = true
    createWorldMap()
    if minimod.resetWorldMapZoom then minimod.resetWorldMapZoom() end

    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
        local layer  = layers and layers[1]
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

        minimod.worldMap:SetMapID(mapID)

        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then
            local sc        = minimod.worldMap.ScrollContainer
            local cw, ch    = sc.Child:GetSize()
            local vw, vh    = minimod.wrapper:GetSize()
            local entryZoom = sc:GetZoom()
            sc:SetHorizontalScroll(pos.x * cw - vw / (2 * entryZoom))
            sc:SetVerticalScroll(pos.y * ch - vh / (2 * entryZoom))
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
