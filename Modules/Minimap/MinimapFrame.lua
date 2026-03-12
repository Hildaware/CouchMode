local addonName           = ...

---@class ConsoleTools: AceAddon
local addon               = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class MinimapModule: AceModule
local minimod             = addon:GetModule('Minimap')

---@diagnostic disable-next-line: undefined-global
local MinimapCluster      = MinimapCluster ---@type Frame

local FADE_DURATION       = 0.5
local TRANSITION_DURATION = 0.25

--#region ── Shape & masking ──────────────────────────────────────────────────

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

    if not minimod.origCircleMaskTexture then
        minimod.origCircleMaskTexture = hybridMinimap.CircleMask:GetTexture()
    end

    hybridMinimap.MapCanvas:SetUseMaskTexture(false)
    hybridMinimap.CircleMask:ClearAllPoints()

    if shape == "rectangle" then
        hybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
        hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)

        if not minimod.rectMask then
            minimod.rectMask = hybridMinimap.MapCanvas:CreateMaskTexture()
            minimod.rectMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            hybridMinimap.MapCanvas:AddMaskTexture(minimod.rectMask) ---@diagnostic disable-line: undefined-field
        end
        minimod.rectMask:ClearAllPoints()
        minimod.rectMask:SetSize(w, h)
        minimod.rectMask:SetPoint("CENTER", hybridMinimap.MapCanvas, "CENTER")
    else
        if minimod.rectMask then hybridMinimap.MapCanvas:RemoveMaskTexture(minimod.rectMask) end ---@diagnostic disable-line: undefined-field
        if shape == "square" then
            hybridMinimap.CircleMask:SetTexture("Interface\\BUTTONS\\WHITE8X8")
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
        else -- circle
            if minimod.origCircleMaskTexture then
                hybridMinimap.CircleMask:SetTexture(minimod.origCircleMaskTexture)
            end
            hybridMinimap.CircleMask:SetAllPoints(hybridMinimap.MapCanvas)
        end
    end

    hybridMinimap.MapCanvas:SetUseMaskTexture(true)
end

--#endregion

--#region ── Border & settings ────────────────────────────────────────────────

function minimod.applyBorder()
    if not minimod.borderTexT then return end
    local db         = addon.db.profile.minimap
    local show       = db.borderEnabled
    local size       = db.borderSize
    local r, g, b, a = db.borderR, db.borderG, db.borderB, db.borderA

    minimod.borderTexT:SetShown(show)
    minimod.borderTexB:SetShown(show)
    minimod.borderTexL:SetShown(show)
    minimod.borderTexR:SetShown(show)
    if not show then return end

    for _, tex in ipairs({ minimod.borderTexT, minimod.borderTexB, minimod.borderTexL, minimod.borderTexR }) do
        tex:SetColorTexture(r, g, b, a)
    end

    minimod.borderTexT:SetHeight(size)
    minimod.borderTexB:SetHeight(size)
    minimod.borderTexL:SetWidth(size)
    minimod.borderTexR:SetWidth(size)

    -- Side textures inset by `size` on corners so they don't overlap top/bottom strips
    minimod.borderTexL:ClearAllPoints()
    minimod.borderTexL:SetPoint("TOPLEFT",     minimod.wrapper, "TOPLEFT",     0, -size)
    minimod.borderTexL:SetPoint("BOTTOMLEFT",  minimod.wrapper, "BOTTOMLEFT",  0,  size)
    minimod.borderTexR:ClearAllPoints()
    minimod.borderTexR:SetPoint("TOPRIGHT",    minimod.wrapper, "TOPRIGHT",    0, -size)
    minimod.borderTexR:SetPoint("BOTTOMRIGHT", minimod.wrapper, "BOTTOMRIGHT", 0,  size)
end

function minimod.applySettings()
    if not minimod.wrapper then return end
    local db   = addon.db.profile.minimap
    local size = minimod.grown and db.growSize or db.size
    local w, h = sizeForShape({ shape = db.shape, size = size })
    minimod.wrapper:SetSize(w, h)
    minimod.wrapper:SetAlpha(db.alpha)
    Minimap:SetSize(w, w) -- always square; HybridMinimap expects square frame
    applyMinimapShape(db.shape, w, h)
    minimod.applyBorder()
end

--#endregion

--#region ── Frame setup ──────────────────────────────────────────────────────

function minimod.createFrame()
    local db = addon.db.profile.minimap

    -- Save Blizzard state so we can restore on disable
    minimod.origParent = Minimap:GetParent()
    minimod.origW, minimod.origH = Minimap:GetSize()
    minimod.origPoints = { Minimap:GetPoint(1) }

    Minimap:SetArchBlobRingScalar(0)
    Minimap:SetArchBlobRingAlpha(0)
    Minimap:SetQuestBlobRingScalar(0)
    Minimap:SetQuestBlobRingAlpha(0)

    -- Wrapper: clips rectangle shapes, drag target, alpha host
    local w, h = sizeForShape(db)
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
    Minimap:SetSize(w, w) -- always square; HybridMinimap expects square frame
    applyMinimapShape(db.shape, w, h)
    Minimap:Show()

    -- Hide all Blizzard chrome
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
    minimod.borderFrame = CreateFrame("Frame", nil, minimod.wrapper)
    minimod.borderFrame:SetAllPoints(minimod.wrapper)
    minimod.borderFrame:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 100)

    minimod.borderTexT = minimod.borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    minimod.borderTexT:SetPoint("TOPLEFT",  minimod.wrapper, "TOPLEFT")
    minimod.borderTexT:SetPoint("TOPRIGHT", minimod.wrapper, "TOPRIGHT")

    minimod.borderTexB = minimod.borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    minimod.borderTexB:SetPoint("BOTTOMLEFT",  minimod.wrapper, "BOTTOMLEFT")
    minimod.borderTexB:SetPoint("BOTTOMRIGHT", minimod.wrapper, "BOTTOMRIGHT")

    minimod.borderTexL = minimod.borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    minimod.borderTexR = minimod.borderFrame:CreateTexture(nil, "OVERLAY", nil, 7)

    minimod.applyBorder()

    -- Drag-to-move
    minimod.wrapper:SetMovable(true)
    minimod.wrapper:EnableMouse(true)
    minimod.wrapper:RegisterForDrag("LeftButton")
    minimod.wrapper:SetScript("OnDragStart", minimod.wrapper.StartMoving)
    minimod.wrapper:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        local pt, _, _, ox, oy = f:GetPoint()
        db.point               = pt
        db.x                   = ox
        db.y                   = oy
    end)

    minimod.wrapper:SetScript("OnUpdate", function(_, elapsed)
        -- Movement fade (wrapper alpha)
        if minimod.fadeTo then
            minimod.fadeElapsed = minimod.fadeElapsed + elapsed
            local t = math.min(1, minimod.fadeElapsed / FADE_DURATION)
            minimod.wrapper:SetAlpha(minimod.fadeFrom + (minimod.fadeTo - minimod.fadeFrom) * t)
            if t >= 1 then minimod.fadeTo = nil end
        end
        -- Minimap cross-fade
        if minimod.minimapFade.active then
            minimod.minimapFade.elapsed = minimod.minimapFade.elapsed + elapsed
            local t = math.min(1, minimod.minimapFade.elapsed / TRANSITION_DURATION)
            Minimap:SetAlpha(minimod.minimapFade.from + (minimod.minimapFade.to - minimod.minimapFade.from) * t)
            if t >= 1 then
                minimod.minimapFade.active = false
                if minimod.minimapFade.to == 0 then Minimap:Hide() end
            end
        end
        -- World map cross-fade
        if minimod.worldMapFade.active and minimod.worldMap then
            minimod.worldMapFade.elapsed = minimod.worldMapFade.elapsed + elapsed
            local t = math.min(1, minimod.worldMapFade.elapsed / TRANSITION_DURATION)
            minimod.worldMap:SetAlpha(minimod.worldMapFade.from + (minimod.worldMapFade.to - minimod.worldMapFade.from) * t)
            if t >= 1 then
                minimod.worldMapFade.active = false
                if minimod.worldMapFade.to == 0 then minimod.worldMap:Hide() end
            end
        end
    end)

    local function startFade(target)
        minimod.fadeFrom    = minimod.wrapper:GetAlpha()
        minimod.fadeTo      = target
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
            minimod.openWorldMap()
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
    local growBtn = CreateFrame("Button", "CTMinimapGrowToggle", minimod.wrapper)
    growBtn:RegisterForClicks("AnyDown")
    growBtn:SetScript("OnClick", function()
        local cp = _G['ConsolePort']
        if minimod.grown then
            -- Shrinking: close world map first if open
            minimod.grown = false
            if minimod.worldMapOpen then minimod.closeWorldMap() end
            local w2, h2 = sizeForShape({ shape = db.shape, size = db.size })
            minimod.wrapper:SetSize(w2, h2)
            Minimap:SetSize(w2, w2)
            applyMinimapShape(db.shape, w2, h2)
            if cp then
                cp:RemoveInterfaceCursorFrame(minimod.wrapper)
                local ih = _G['ConsolePortInputHandler']
                if ih then ih:Release(minimod.wrapper) end
                _G['ConsolePortCursor']:SetEnabled(false)
            end
        else
            -- Growing
            minimod.grown = true
            local w2, h2 = sizeForShape({ shape = db.shape, size = db.growSize })
            minimod.wrapper:SetSize(w2, h2)
            Minimap:SetSize(w2, w2)
            applyMinimapShape(db.shape, w2, h2)
            if cp then
                cp:AddInterfaceCursorFrame(minimod.wrapper)
                local ih = _G['ConsolePortInputHandler']
                if ih and not InCombatLockdown() then
                    ih:SetCommand('PADRSHOULDER', minimod.wrapper, false, 'LeftButton', 'ZoomIn', nil)
                    ih:SetCommand('PADLSHOULDER', minimod.wrapper, false, 'LeftButton', 'ZoomOut', nil)
                end
            end
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

    if _G['ConsolePort'] then
        minimod.wrapper:SetPropagateKeyboardInput(true)

        minimod.wrapper:SetScript('OnGamePadButtonDown', function(_, key)
            if not minimod.grown or InCombatLockdown() then return end
            if key ~= 'PADRSHOULDER' and key ~= 'PADLSHOULDER' then return end

            local function doZoom()
                if minimod.worldMapOpen and minimod.worldMap then
                    local sc = minimod.worldMap.ScrollContainer
                    sc:SetZoomTarget(sc:GetZoom() * (key == 'PADRSHOULDER' and 1.1 or 0.9))
                elseif key == 'PADRSHOULDER' then
                    if Minimap.ZoomIn then Minimap.ZoomIn:Click() end
                else
                    if Minimap:GetZoom() == 0 then
                        minimod.openWorldMap()
                    elseif Minimap.ZoomOut then
                        Minimap.ZoomOut:Click()
                    end
                end
            end
            doZoom()
        end)
    end

    -- Expose as a global so Bindings.xml can invoke it by name.
    function ConsoleTools_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
        if minimod.wrapper and minimod.wrapper:IsShown() then growBtn:Click() end
    end

    -- Blizzard Key Bindings panel display strings.
    BINDING_HEADER_CONSOLETOOLS = "Console Tools"                          ---@diagnostic disable-line: lowercase-global
    BINDING_NAME_CONSOLETOOLS_MINIMAP_GROWTOGGLE = "Toggle Minimap Expand" ---@diagnostic disable-line: lowercase-global
end

--#endregion
