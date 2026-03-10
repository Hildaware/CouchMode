local addonName           = ...

---@class ConsoleTools: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class MinimapModule: AceModule
local minimod             = addon:NewModule('Minimap')

local wrapper ---@type Frame
local borderFrame ---@type Frame
local borderTexT, borderTexB, borderTexL, borderTexR ---@type Texture
---@diagnostic disable-next-line: undefined-global
local MinimapCluster      = MinimapCluster ---@type Frame

--#region ── Shared: constants, state, fade helpers ──────────────────────────

local FADE_DURATION       = 0.5  -- wrapper movement fade
local TRANSITION_DURATION = 0.25 -- minimap ↔ world map cross-fade

local minimapFade         = { from = 1, to = 1, elapsed = 0, active = false }
local worldMapFade        = { from = 0, to = 0, elapsed = 0, active = false }

local function startFrameFade(frame, state, toAlpha)
    state.from    = frame:GetAlpha()
    state.to      = toAlpha
    state.elapsed = 0
    state.active  = true
end

-- Forward declarations: defined in the World Map region below, referenced from
-- the Minimap frame setup region (scroll handler, grow button).
local openWorldMap
local closeWorldMap

--#endregion

--#region ── Minimap: shape & masking ────────────────────────────────────────

-- Saved HybridMinimap state; restored on disable.
local origCircleMaskTexture ---@type string|nil
local rectMask ---@type MaskTexture|nil  -- secondary clip mask for rectangle shape

local function sizeForShape(db)
    if db.shape == "rectangle" then
        return db.size, math.floor(db.size * 0.5)
    end
    return db.size, db.size
end

local function maskForShape(shape)
    if shape == "square" or shape == "rectangle" then
        return "Interface\\BUTTONS\\WHITE8X8"
    end
    return nil -- circle: pass nil to restore Blizzard's native circular mask
end

-- Applies shape masking to both the Minimap frame mask and HybridMinimap.MapCanvas.
-- IMPORTANT: Do NOT resize CircleMask — HybridMinimap uses it as a render-viewport hint,
-- so SetSize(w,h) squashes map tiles rather than cropping them.  Instead we keep CircleMask
-- at SetAllPoints (full square, non-restrictive white texture) and add a *second* MaskTexture
-- for rectangle via AddMaskTexture.  The two masks are ANDed: full-square AND w×h rect = rect.
local function applyMinimapShape(shape, w, h)
    Minimap:SetMaskTexture(maskForShape(shape))

    ---@diagnostic disable-next-line: undefined-global
    local hybridMinimap = HybridMinimap
    if not (hybridMinimap and hybridMinimap.MapCanvas and hybridMinimap.CircleMask) then return end

    if not origCircleMaskTexture then
        origCircleMaskTexture = hybridMinimap.CircleMask:GetTexture()
    end

    hybridMinimap.MapCanvas:SetUseMaskTexture(false)
    hybridMinimap.CircleMask:ClearAllPoints()

    if shape == "rectangle" then
        hybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas) -- full-square, non-restrictive

        -- Create the secondary rectangle clip mask once, then reuse/resize it.
        if not rectMask then
            rectMask = hybridMinimap.MapCanvas:CreateMaskTexture()
            rectMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            hybridMinimap.MapCanvas:AddMaskTexture(rectMask) ---@diagnostic disable-line: undefined-field
        end
        rectMask:ClearAllPoints()
        rectMask:SetSize(w, h)
        rectMask:SetPoint("CENTER", hybridMinimap.MapCanvas, "CENTER")
    else
        -- Remove the secondary rectangle mask for square/circle.
        if rectMask then hybridMinimap.MapCanvas:RemoveMaskTexture(rectMask) end ---@diagnostic disable-line: undefined-field
        if shape == "square" then
            hybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
        else -- circle
            if origCircleMaskTexture then
                hybridMinimap.CircleMask:SetTexture(origCircleMaskTexture)
            end
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
        end
    end

    hybridMinimap.MapCanvas:SetUseMaskTexture(true)
end

--#endregion

--#region ── Minimap: frame setup ────────────────────────────────────────────

local function applyBorder()
    if not borderTexT then return end
    local db         = addon.db.profile.minimap
    local show       = db.borderEnabled
    local size       = db.borderSize
    local r, g, b, a = db.borderR, db.borderG, db.borderB, db.borderA

    borderTexT:SetShown(show)
    borderTexB:SetShown(show)
    borderTexL:SetShown(show)
    borderTexR:SetShown(show)
    if not show then return end

    for _, tex in ipairs({ borderTexT, borderTexB, borderTexL, borderTexR }) do
        tex:SetColorTexture(r, g, b, a)
    end

    borderTexT:SetHeight(size)
    borderTexB:SetHeight(size)
    borderTexL:SetWidth(size)
    borderTexR:SetWidth(size)

    -- Side textures inset by `size` on corners so they don't overlap top/bottom strips
    borderTexL:ClearAllPoints()
    borderTexL:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, -size)
    borderTexL:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, size)
    borderTexR:ClearAllPoints()
    borderTexR:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT", 0, -size)
    borderTexR:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", 0, size)
end

local function applySettings()
    if not wrapper then return end
    local db   = addon.db.profile.minimap
    local size = minimod.grown and db.growSize or db.size
    local w, h = sizeForShape({ shape = db.shape, size = size })
    wrapper:SetSize(w, h)
    wrapper:SetAlpha(db.alpha)
    Minimap:SetSize(w, w) -- always square; HybridMinimap expects square frame
    applyMinimapShape(db.shape, w, h)
    applyBorder()
end

local function applyGrowKey(key)
    if minimod.currentGrowKey then
        SetBinding(minimod.currentGrowKey)
        minimod.currentGrowKey = nil
    end
    if key and key ~= "" then
        SetBindingClick(key, "CTMinimapGrowToggle", "LeftButton")
        minimod.currentGrowKey = key
    end
end

local function createFrame()
    local db = addon.db.profile.minimap

    -- Save Blizzard state so we can restore on disable
    minimod.origParent = Minimap:GetParent()
    minimod.origW, minimod.origH = Minimap:GetSize()
    minimod.origPoints = { Minimap:GetPoint(1) } -- { point, relFrame, relPoint, x, y }

    Minimap:SetArchBlobRingScalar(0)
    Minimap:SetArchBlobRingAlpha(0)
    Minimap:SetQuestBlobRingScalar(0)
    Minimap:SetQuestBlobRingAlpha(0)

    -- Wrapper: clips rectangle shapes, drag target, alpha host
    local w, h = sizeForShape(db)
    wrapper = CreateFrame("Frame", "CTMinimapWrapper", UIParent)
    wrapper:SetSize(w, h)
    wrapper:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    wrapper:SetClipsChildren(true)
    wrapper:SetAlpha(db.alpha)
    wrapper:SetFrameStrata("DIALOG")

    -- Reparent the Blizzard Minimap widget into our wrapper
    Minimap:SetParent(wrapper)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", wrapper, "CENTER")
    Minimap:SetSize(w, w) -- always square; HybridMinimap expects square frame
    applyMinimapShape(db.shape, w, h)
    Minimap:Show()

    -- Hide all Blizzard chrome (MinimapCluster's children are now orphaned visually)
    MinimapCluster:Hide()
    if MinimapBackdrop then MinimapBackdrop:Hide() end ---@diagnostic disable-line: undefined-global
    if Minimap.ZoomHitArea then Minimap.ZoomHitArea:Hide() end ---@diagnostic disable-line: undefined-field
    -- Keep buttons shown so Click() still fires their full OnClick logic
    -- (hiding them breaks the click dispatch). SetAlpha(0) hides them visually.
    -- IsMouseOver override prevents MinimapMixin:OnLeave() from auto-hiding them.
    if Minimap.ZoomIn then ---@diagnostic disable-line: undefined-field
        Minimap.ZoomIn:SetAlpha(0)
        Minimap.ZoomIn.IsMouseOver = function() return true end
    end
    if Minimap.ZoomOut then ---@diagnostic disable-line: undefined-field
        Minimap.ZoomOut:SetAlpha(0)
        Minimap.ZoomOut.IsMouseOver = function() return true end
    end

    -- Border overlay: parented to wrapper (clipped to its bounds), above all content
    borderFrame = CreateFrame("Frame", nil, wrapper)
    borderFrame:SetAllPoints(wrapper)
    borderFrame:SetFrameLevel(wrapper:GetFrameLevel() + 100)

    borderTexT = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderTexT:SetPoint("TOPLEFT", wrapper, "TOPLEFT")
    borderTexT:SetPoint("TOPRIGHT", wrapper, "TOPRIGHT")

    borderTexB = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderTexB:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT")
    borderTexB:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT")

    borderTexL = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    borderTexR = borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)

    applyBorder()

    -- Drag-to-move
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetScript("OnDragStart", wrapper.StartMoving)
    wrapper:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local pt, _, _, ox, oy = f:GetPoint()
        db.point               = pt
        db.x                   = ox
        db.y                   = oy
    end)

    wrapper:SetScript("OnUpdate", function(_, elapsed)
        -- Movement fade (wrapper alpha)
        if minimod.fadeTo then
            minimod.fadeElapsed = minimod.fadeElapsed + elapsed
            local t = math.min(1, minimod.fadeElapsed / FADE_DURATION)
            wrapper:SetAlpha(minimod.fadeFrom + (minimod.fadeTo - minimod.fadeFrom) * t)
            if t >= 1 then minimod.fadeTo = nil end
        end
        -- Minimap cross-fade
        if minimapFade.active then
            minimapFade.elapsed = minimapFade.elapsed + elapsed
            local t = math.min(1, minimapFade.elapsed / TRANSITION_DURATION)
            Minimap:SetAlpha(minimapFade.from + (minimapFade.to - minimapFade.from) * t)
            if t >= 1 then
                minimapFade.active = false
                if minimapFade.to == 0 then Minimap:Hide() end
            end
        end
        -- World map cross-fade
        if worldMapFade.active and minimod.worldMap then
            worldMapFade.elapsed = worldMapFade.elapsed + elapsed
            local t = math.min(1, worldMapFade.elapsed / TRANSITION_DURATION)
            minimod.worldMap:SetAlpha(worldMapFade.from + (worldMapFade.to - worldMapFade.from) * t)
            if t >= 1 then
                worldMapFade.active = false
                if worldMapFade.to == 0 then minimod.worldMap:Hide() end
            end
        end
    end)

    local function startFade(target)
        minimod.fadeFrom    = wrapper:GetAlpha()
        minimod.fadeTo      = target
        minimod.fadeElapsed = 0
    end

    wrapper:RegisterEvent("PLAYER_STARTED_MOVING")
    wrapper:RegisterEvent("PLAYER_STOPPED_MOVING")
    wrapper:SetScript("OnEvent", function(_, event)
        if not db.moveAlphaEnabled then return end
        if event == "PLAYER_STARTED_MOVING" then
            startFade(db.moveAlpha)
        elseif event == "PLAYER_STOPPED_MOVING" then
            startFade(db.alpha)
        end
    end)

    -- Scroll handler: intercepts scroll-out-at-zero-zoom to open the world map
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function(_, delta)
        if minimod.worldMapOpen then return end -- world map is visible; ignore
        local zoom    = Minimap:GetZoom()
        local maxZoom = Minimap:GetZoomLevels() - 1
        if delta < 0 and zoom == 0 and minimod.grown then
            openWorldMap()
            return
        end
        -- Delegate to Blizzard's own zoom buttons so their OnClick handlers run
        -- (which handle player-pin recentering). Direct SetZoom() skips that logic,
        -- causing the player arrow to drift during zoom.
        if delta > 0 then
            if Minimap.ZoomIn then
                Minimap.ZoomIn:Click("LeftButton")
            else
                Minimap:SetZoom(math.min(zoom + 1, maxZoom))
            end
        else
            if Minimap.ZoomOut then
                Minimap.ZoomOut:Click("LeftButton")
            else
                Minimap:SetZoom(math.max(zoom - 1, 0))
            end
        end
    end)

    -- Toggle grow: press to grow, press again to shrink
    local growBtn = CreateFrame("Button", "CTMinimapGrowToggle", wrapper)
    growBtn:RegisterForClicks("AnyDown")
    growBtn:SetScript("OnClick", function()
        if minimod.grown then
            -- Shrinking: close world map first if open
            minimod.grown = false
            if minimod.worldMapOpen then closeWorldMap() end
            local w2, h2 = sizeForShape({ shape = db.shape, size = db.size })
            wrapper:SetSize(w2, h2)
            Minimap:SetSize(w2, w2)
            applyMinimapShape(db.shape, w2, h2)
        else
            -- Growing
            minimod.grown = true
            local w2, h2 = sizeForShape({ shape = db.shape, size = db.growSize })
            wrapper:SetSize(w2, h2)
            Minimap:SetSize(w2, w2)
            applyMinimapShape(db.shape, w2, h2)
        end
        -- Zoom click cycle forces the HybridMinimap render layer to update for the
        -- new frame size (same technique used by BasicMinimap after SetSize).
        local curZoom = Minimap:GetZoom()
        local maxZoom = Minimap:GetZoomLevels() - 1
        if Minimap.ZoomIn and Minimap.ZoomOut then
            if curZoom < maxZoom then
                Minimap.ZoomIn:Click(); Minimap.ZoomOut:Click()
            else
                Minimap.ZoomOut:Click(); Minimap.ZoomIn:Click()
            end
        end
    end)
end

--#endregion

--#region ── World Map ───────────────────────────────────────────────────────

local function createWorldMap()
    if minimod.worldMap then return end

    if not MapCanvasMixin or not BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_MapCanvas")
    end
    if not GroupMembersDataProviderMixin then ---@diagnostic disable-line: undefined-global
        C_AddOns.LoadAddOn("Blizzard_SharedMapDataProviders")
    end

    local mapFrame = CreateFrame("Frame", nil, wrapper)
    mapFrame:SetAllPoints(wrapper)

    -- ScrollContainer required by MapCanvasMixin
    local scrollContainer = CreateFrame("ScrollFrame", nil, mapFrame)
    scrollContainer:SetAllPoints()
    mapFrame.ScrollContainer = scrollContainer

    local scrollChild = CreateFrame("Frame", nil, scrollContainer)
    scrollChild:SetSize(2048, 2048)     -- placeholder; resized to real art dimensions in openWorldMap
    scrollContainer:SetScrollChild(scrollChild)
    scrollContainer.Child = scrollChild -- MapCanvasMixin accesses via .Child

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

    -- Cache scroll child and wrapper dimensions to avoid GetSize() calls every OnUpdate frame.
    -- Updated via OnSizeChanged so the values stay accurate without per-frame reads.
    local cachedChildW, cachedChildH = scrollChild:GetSize()
    local cachedWrapW, cachedWrapH   = wrapper:GetSize()

    scrollChild:SetScript("OnSizeChanged", function(_, sw, sh)
        cachedChildW, cachedChildH = sw, sh
    end)
    wrapper:SetScript("OnSizeChanged", function(_, ww, wh)
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

    -- Minimal interface MapCanvasMixin expects on ScrollContainer
    function scrollContainer:GetZoom() return zoom end

    function scrollContainer:SetZoomTarget(z) applyZoom(z) end

    function scrollContainer:SetMapID() end     -- MapCanvasMixin:SetMapID forwards here

    function scrollContainer:SetPanTarget() end -- centering handled in OnUpdate

    function scrollContainer:OnCanvasSizeChanged() end

    function scrollContainer:OnLoad() end

    function scrollContainer:OnShow() end

    function scrollContainer:OnHide() end

    -- Pin providers call GetCanvasScale() to size their pins.
    -- We scale via mapFrame:SetScale(zoom) so from the scroll container's
    -- perspective the canvas scale is always 1.
    function scrollContainer:GetCanvasScale() return zoom end

    -- DenormalizeSize converts normalized [0,1] map coords to pixel sizes.
    -- Uses GetWidth/Height() directly (not cached values) so callers always see
    -- the current logical canvas size, even before OnSizeChanged has fired.
    function scrollContainer:DenormalizeHorizontalSize(size) return size * scrollChild:GetWidth() end

    function scrollContainer:DenormalizeVerticalSize(size) return size * scrollChild:GetHeight() end

    function scrollContainer:NormalizeHorizontalSize(size)
        local w = scrollChild:GetWidth(); return w > 0 and size / w or 0
    end

    function scrollContainer:NormalizeVerticalSize(size)
        local h = scrollChild:GetHeight(); return h > 0 and size / h or 0
    end

    function scrollContainer:GetCanvasZoomPercent() return 0 end

    -- Called by AcquirePin (before OnAcquired) and by pin pool operations.
    -- Blizzard's version nils cached scroll/scale to force a redraw on their
    -- OnUpdate; our scroll is driven manually so a no-op is correct.
    function scrollContainer:MarkCanvasDirty() end

    -- Called during area-trigger processing; no-op since we don't use that system.
    function scrollContainer:MarkAreaTriggersDirty() end

    -- Cursor-position fix for SetScale: divide raw screen coords by effective scale
    -- so map hit-testing stays accurate after mapFrame:SetScale(zoom).
    function scrollContainer:GetCursorPosition()
        local x, y = GetCursorPosition()
        local s    = self:GetEffectiveScale()
        return x / s, y / s
    end

    scrollContainer:SetScript("OnMouseWheel", function(_, delta)
        if delta > 0 and zoom >= MAX_ZOOM then
            closeWorldMap()
            return
        end
        applyZoom(zoom * (delta > 0 and 1.25 or 0.8))
    end)

    -- Keep map centered on the player every frame using cached dimensions.
    -- (wrapper:GetSize() can return 0 before the scroll frame is first shown,
    -- which would corrupt the centering formula.)
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
    -- Intentionally NOT hooking MapCanvasMixin:OnUpdate — it drives smooth
    -- pan/zoom animations that fight our manual scrollContainer centering.
    if mapFrame.OnLoad then mapFrame:OnLoad() end

    -- RefreshDetailLayers drives tile visibility but also calls AdjustDetailLayerAlpha
    -- on internally-created layer objects that reference template textures we don't
    -- have. We can't intercept those objects before they're used, so pcall the whole
    -- call — tiles render, the alpha-fading error is silently swallowed.
    local _origRefresh = mapFrame.RefreshDetailLayers
    if _origRefresh then
        mapFrame.RefreshDetailLayers = function(self)
            pcall(_origRefresh, self)
        end
    end

    -- Exposes zoom reset to openWorldMap without needing direct access to the
    -- `zoom` upvalue. Scale must always match zoom so the OnUpdate centering
    -- formula (cachedWrapW / (2 * zoom)) stays consistent.
    -- Zoom constants are derived from the current wrapper width so visual quality
    -- (art pixels per viewport pixel) stays constant regardless of db.growSize.
    -- Reference: 500px growSize → ZOOM_ENTRY 0.25 → 500/0.25 = 2000 art px visible.
    minimod.resetWorldMapZoom = function()
        ZOOM_ENTRY = cachedWrapW / 2000
        MIN_ZOOM   = ZOOM_ENTRY * 0.48
        MAX_ZOOM   = ZOOM_ENTRY * 1.24
        zoom       = ZOOM_ENTRY
        scrollChild:SetScale(ZOOM_ENTRY)
    end

    mapFrame:EnableMouse(true)
    mapFrame:EnableMouseWheel(true)

    if BaseMapCanvasDetailLayerMixin then ---@diagnostic disable-line: undefined-global
        local detailDP = CreateFromMixins(BaseMapCanvasDetailLayerMixin) ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(detailDP)
        -- AdjustDetailLayerAlpha errors on template-created sub-textures our custom canvas
        -- doesn't have. Without this stub it runs partially, leaving some tiles at wrong
        -- alpha (creating visible "grid" seams). The no-op stub lets RefreshDetailLayers
        -- complete cleanly so all tiles render at full opacity.
        detailDP.AdjustDetailLayerAlpha = function() end
    end
    if MapCanvasCursorDataProviderMixin then ---@diagnostic disable-line: undefined-global
        mapFrame:AddDataProvider(CreateFromMixins(MapCanvasCursorDataProviderMixin)) ---@diagnostic disable-line: undefined-global
    end

    -- Register pin frame levels needed by the providers below.
    -- Unknown levels fall back to PIN_FRAME_LEVEL_DEFAULT (no crash), but explicit
    -- registration gives correct Z-ordering between quest, world quest, and player pins.
    local plm = mapFrame:GetPinFrameLevelsManager()
    plm:AddFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_VIGNETTE", 200)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_WORLD_QUEST", 500)
    plm:AddFrameLevel("PIN_FRAME_LEVEL_ACTIVE_QUEST", C_QuestLog.GetMaxNumQuests())
    plm:AddFrameLevel("PIN_FRAME_LEVEL_SUPER_TRACKED_QUEST")
    plm:AddFrameLevel("PIN_FRAME_LEVEL_GROUP_MEMBER")

    -- Blizzard's pin pool calls resetFunc (Hide) before OnAcquired sets dataProvider,
    -- causing GroupMembersPinMixin:OnHide to crash on a nil dataProvider.
    -- Patch it once with a nil guard; safe for WorldMapFrame too since its pins
    -- always have dataProvider set by the time they're actively used.
    if GroupMembersPinMixin and not GroupMembersPinMixin._ctPatched then ---@diagnostic disable-line: undefined-global
        local _orig = GroupMembersPinMixin.OnHide ---@diagnostic disable-line: undefined-global
        GroupMembersPinMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.dataProvider then _orig(self) end
        end
        GroupMembersPinMixin._ctPatched = true ---@diagnostic disable-line: undefined-global
    end

    -- WorldQuestDataProvider:OnHide crashes if OnShow never fired (ticker is nil).
    -- This happens when the map frame is hidden before it was shown (e.g. World Map
    -- closed immediately after opening, or shown then quickly transitioned to minimap).
    if WorldQuestDataProviderMixin and not WorldQuestDataProviderMixin._ctPatched then ---@diagnostic disable-line: undefined-global
        local _orig = WorldQuestDataProviderMixin.OnHide ---@diagnostic disable-line: undefined-global
        WorldQuestDataProviderMixin.OnHide = function(self) ---@diagnostic disable-line: undefined-global, duplicate-set-field
            if self.ticker then _orig(self) end
        end
        WorldQuestDataProviderMixin._ctPatched = true ---@diagnostic disable-line: undefined-global
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

openWorldMap = function()
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

        -- Notify all pins of the correct canvas dimensions and re-apply their anchors.
        -- MapCanvasMixin:ExecuteOnAllPins uses pool:GetPool() which is NOT exposed on
        -- the proxy returned by CreateFramePool, so we iterate directly instead.
        -- We must call both OnCanvasSizeChanged (sets pin frame size = canvas size)
        -- AND ApplyCurrentPosition (re-anchors pin to correct canvas center), because
        -- both were set during createWorldMap when canvas was still 2048×2048 placeholder.
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
            local vw, vh    = wrapper:GetSize()
            local entryZoom = sc:GetZoom()
            sc:SetHorizontalScroll(pos.x * cw - vw / (2 * entryZoom))
            sc:SetVerticalScroll(pos.y * ch - vh / (2 * entryZoom))
        end
    end

    minimod.worldMap:SetAlpha(0)
    minimod.worldMap:Show()
    startFrameFade(minimod.worldMap, worldMapFade, 1)
    startFrameFade(Minimap, minimapFade, 0)
end

closeWorldMap = function()
    minimod.worldMapOpen = false
    applySettings() -- restores wrapper to minimap size, shape, alpha immediately (before fades)

    Minimap:SetAlpha(0)
    Minimap:Show()
    Minimap:SetZoom(0) -- Set to Zero is perfect for transition
    -- ZoomIn then ZoomOut forces HybridMinimap to refresh at zoom 0.
    -- (ZoomOut first would try SetZoom(-1) which is out of range.)
    if Minimap.ZoomIn and Minimap.ZoomOut then
        Minimap.ZoomIn:Click()
        Minimap.ZoomOut:Click()
    end
    startFrameFade(Minimap, minimapFade, 1)
    if minimod.worldMap then
        startFrameFade(minimod.worldMap, worldMapFade, 0)
    end
end

--#endregion

--#region ── Module lifecycle & Options ──────────────────────────────────────

function minimod:OnEnable()
    if not wrapper then createFrame() end
    applyGrowKey(addon.db.profile.minimap.growKey)
    wrapper:Show()
end

function minimod:OnDisable()
    if minimod.worldMapOpen then closeWorldMap() end
    if wrapper then wrapper:Hide() end

    -- Restore Minimap to original Blizzard state
    if minimod.origParent then
        Minimap:SetParent(minimod.origParent)
        Minimap:ClearAllPoints()
        local pt, relFrame, relPt, ox, oy = unpack(minimod.origPoints)
        Minimap:SetPoint(pt, relFrame, relPt, ox, oy) ---@diagnostic disable-line: param-type-mismatch
        Minimap:SetSize(minimod.origW, minimod.origH)
        Minimap:SetMaskTexture("Textures\\MinimapMask")

        -- Restore HybridMinimap.CircleMask to original circular shape
        ---@diagnostic disable-next-line: undefined-global
        local hybridMinimap = HybridMinimap
        if hybridMinimap and hybridMinimap.MapCanvas and hybridMinimap.CircleMask then
            if rectMask then hybridMinimap.MapCanvas:RemoveMaskTexture(rectMask) end ---@diagnostic disable-line: undefined-field
            hybridMinimap.MapCanvas:SetUseMaskTexture(false)
            hybridMinimap.CircleMask:ClearAllPoints()
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
            if origCircleMaskTexture then
                hybridMinimap.CircleMask:SetTexture(origCircleMaskTexture)
            end
            hybridMinimap.MapCanvas:SetUseMaskTexture(true)
        end
        MinimapCluster:Show()
        if MinimapBackdrop then MinimapBackdrop:Show() end ---@diagnostic disable-line: undefined-global
        minimod.origParent = nil
        minimod.grown      = false
        minimod.fadeTo     = nil
    end

    applyGrowKey("") -- clear binding
end

function minimod:GetDefaults()
    return {
        minimap = {
            enabled          = true,
            shape            = "square",
            size             = 200,
            alpha            = 0.85,
            growSize         = 420,
            growKey          = "",
            point            = "TOPRIGHT",
            x                = -20,
            y                = -20,
            moveAlphaEnabled = true,
            moveAlpha        = 0.3,
            borderEnabled    = false,
            borderSize       = 2,
            borderR          = 1,
            borderG          = 1,
            borderB          = 1,
            borderA          = 1,
        },
    }
end

function minimod:GetOptions()
    return 'minimap', {
        name  = 'Minimap',
        type  = 'group',
        order = 8,
        args  = {
            description = {
                name  = 'A clean, resizable minimap overlay. Drag to reposition. Scroll wheel to zoom.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enable',
                desc  = 'Replace the default minimap chrome with the clean overlay.',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.minimap.enabled end,
                set   = function(_, value)
                    addon.db.profile.minimap.enabled = value
                    if value then minimod:Enable() else minimod:Disable() end
                end,
            },
            shape = {
                name   = 'Shape',
                desc   = 'Square: full square. Rectangle: wide letterbox.',
                type   = 'select',
                order  = 3,
                values = { square = 'Square', rectangle = 'Rectangle' },
                get    = function() return addon.db.profile.minimap.shape end,
                set    = function(_, value)
                    addon.db.profile.minimap.shape = value
                    applySettings()
                end,
            },
            size = {
                name  = 'Size',
                desc  = 'Normal minimap width in pixels.',
                type  = 'range',
                order = 4,
                min   = 100,
                max   = 500,
                step  = 10,
                get   = function() return addon.db.profile.minimap.size end,
                set   = function(_, value)
                    addon.db.profile.minimap.size = value
                    applySettings()
                end,
            },
            alpha = {
                name  = 'Opacity',
                desc  = 'Transparency of the minimap overlay.',
                type  = 'range',
                order = 5,
                min   = 0.1,
                max   = 1.0,
                step  = 0.05,
                get   = function() return addon.db.profile.minimap.alpha end,
                set   = function(_, value)
                    addon.db.profile.minimap.alpha = value
                    if wrapper then wrapper:SetAlpha(value) end
                end,
            },
            growSize = {
                name  = 'Grown Size',
                desc  = 'Width while the grow key is held.',
                type  = 'range',
                order = 6,
                min   = 200,
                max   = 800,
                step  = 10,
                get   = function() return addon.db.profile.minimap.growSize end,
                set   = function(_, value) addon.db.profile.minimap.growSize = value end,
            },
            growKey = {
                name  = 'Grow Key',
                desc  = 'Key to hold for the larger view (e.g. ALT-M, CTRL-SPACE). Leave blank to disable.',
                type  = 'input',
                order = 7,
                get   = function() return addon.db.profile.minimap.growKey end,
                set   = function(_, value)
                    addon.db.profile.minimap.growKey = value
                    applyGrowKey(value)
                end,
            },
            moveAlphaEnabled = {
                name  = 'Fade on Move',
                desc  = 'Fade the minimap while the player is moving.',
                type  = 'toggle',
                order = 8,
                get   = function() return addon.db.profile.minimap.moveAlphaEnabled end,
                set   = function(_, value) addon.db.profile.minimap.moveAlphaEnabled = value end,
            },
            moveAlpha = {
                name  = 'Move Alpha',
                desc  = 'Opacity while the player is moving.',
                type  = 'range',
                order = 9,
                min   = 0.0,
                max   = 1.0,
                step  = 0.05,
                get   = function() return addon.db.profile.minimap.moveAlpha end,
                set   = function(_, value) addon.db.profile.minimap.moveAlpha = value end,
            },
            borderEnabled = {
                name  = 'Border',
                desc  = 'Show a colored border around the minimap and world map.',
                type  = 'toggle',
                order = 10,
                get   = function() return addon.db.profile.minimap.borderEnabled end,
                set   = function(_, value)
                    addon.db.profile.minimap.borderEnabled = value
                    applyBorder()
                end,
            },
            borderSize = {
                name  = 'Border Size',
                desc  = 'Border thickness in pixels.',
                type  = 'range',
                order = 11,
                min   = 1,
                max   = 20,
                step  = 1,
                get   = function() return addon.db.profile.minimap.borderSize end,
                set   = function(_, value)
                    addon.db.profile.minimap.borderSize = value
                    applyBorder()
                end,
            },
            borderColor = {
                name     = 'Border Color',
                type     = 'color',
                hasAlpha = true,
                order    = 12,
                get      = function()
                    local db = addon.db.profile.minimap
                    return db.borderR, db.borderG, db.borderB, db.borderA
                end,
                set      = function(_, r, g, b, a)
                    local db = addon.db.profile.minimap
                    db.borderR, db.borderG, db.borderB, db.borderA = r, g, b, a
                    applyBorder()
                end,
            },
        },
    }
end

--#endregion

minimod:Enable()
