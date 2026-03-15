local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MinimapModule: AceModule
local minimod = addon:GetModule('Minimap')

-- Cache globals for performance and style guide compliance
local _G = _G
local math_min = math.min
local math_max = math.max
local math_floor = math.floor
local math_ceil = math.ceil

local Minimap = _G.Minimap
local UIParent = _G.UIParent
local CreateFrame = _G.CreateFrame
local HasNewMail = _G.HasNewMail
local InCombatLockdown = _G.InCombatLockdown
local AnchorUtil = _G.AnchorUtil
local MinimapCluster = _G.MinimapCluster ---@type Frame

local FADE_DURATION = 0.5
local TRANSITION_DURATION = 0.25
local GROW_DURATION = 0.5

--#region ── Shape & masking ──────────────────────────────────────────────────

local function size_for_shape(db)
    if db.shape == "rectangle" then
        return db.size, math_floor(db.size * (2 / 3))
    end
    return db.size, db.size
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
    local db = addon.db.profile.minimap
    local show = db.borderEnabled
    local size = db.borderSize
    local r, g, b, a = db.borderR, db.borderG, db.borderB, db.borderA

    minimod.MapUtils.apply_border_textures(minimod.wrapper, minimod.borders, show, size, r, g, b, a)
    if minimod.toolbarBorders then
        minimod.MapUtils.apply_border_textures(minimod.toolbar, minimod.toolbarBorders, show, size, r, g, b, a)
    end
end

function minimod.applySettings()
    if not minimod.wrapper then return end
    local db = addon.db.profile.minimap
    local size = minimod.grown and db.growSize or db.size
    local w, h = size_for_shape({ shape = db.shape, size = size })

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
    local w, h = size_for_shape(db)
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

    minimod.borders = minimod.MapUtils.create_border_textures(minimod.borderFrame, minimod.wrapper)

    minimod.applyBorder()

    -- Toolbar: docked above wrapper, shown on mouseover or when grown
    minimod.toolbar = CreateFrame("Frame", nil, UIParent)
    minimod.toolbar:SetHeight(24)
    minimod.toolbar:SetPoint("BOTTOMLEFT", minimod.wrapper, "TOPLEFT", 0, 0)
    minimod.toolbar:SetPoint("BOTTOMRIGHT", minimod.wrapper, "TOPRIGHT", 0, 0)
    minimod.toolbar:SetFrameStrata("DIALOG")
    minimod.toolbar:SetFrameLevel(minimod.wrapper:GetFrameLevel() + 50)
    minimod.toolbar:Hide()

    local toolbar_bg = minimod.toolbar:CreateTexture(nil, "BACKGROUND")
    toolbar_bg:SetAllPoints(minimod.toolbar)
    toolbar_bg:SetColorTexture(0, 0, 0, 0.6)

    minimod.toolbarBorders = minimod.MapUtils.create_border_textures(minimod.toolbar, minimod.toolbar)

    create_mail_indicator()

    -- Settings button
    local settings_btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, "echoes-icon", function()
        LibStub("AceConfigDialog-3.0"):Open(addon_name)
    end, "Settings")
    settings_btn:SetPoint("RIGHT", minimod.toolbar, "RIGHT", -2, 0)

    -- Tracking button: open native DropdownButton menu anchored to our button
    local tracking_btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, "UI-HUD-Minimap-Tracking-Up",
        function() end, "Tracking")
    tracking_btn:SetPoint("RIGHT", settings_btn, "LEFT", -10, 0)
    minimod.trackingBtn = tracking_btn
    if blizz_tracking_btn then
        blizz_tracking_btn:SetParent(tracking_btn)
        blizz_tracking_btn:ClearAllPoints()
        blizz_tracking_btn:SetPoint("CENTER", tracking_btn, "CENTER")
        blizz_tracking_btn:SetAlpha(0)
        blizz_tracking_btn.Button:SetMenuAnchor(AnchorUtil.CreateAnchor("BOTTOMLEFT", tracking_btn, "TOPLEFT", 0, 2)) ---@diagnostic disable-line: undefined-global
        tracking_btn:SetScript("OnClick", function()
            print("Opening Blizzard tracking menu")
            blizz_tracking_btn:OpenMenu()
        end)
    end

    -- World Map filter toggle buttons (hidden until world map is open)
    local function make_wm_toggle(atlas, dp_field, db_field, tooltip)
        local btn ---@type Button
        btn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, atlas, function()
            if not minimod.worldMap then return end
            db[db_field] = not db[db_field]
            local dp = minimod[dp_field] ---@type any
            if dp then
                if db[db_field] then
                    dp:RefreshAllData()
                else
                    dp:RemoveAllData()
                end
            end
            btn:SetAlpha(db[db_field] and 1 or 0.4)
        end, tooltip)
        btn:Hide()
        return btn
    end

    minimod.wmBtnWQ = make_wm_toggle("worldquest-tracker-questmarker", "wmDpWorldQuests", "worldMapShowWorldQuests",
        "World Quests")
    minimod.wmBtnWQ:SetPoint("RIGHT", settings_btn, "LEFT", -10, 0)

    minimod.wmBtnAQ = make_wm_toggle("QuestNormal", "wmDpActiveQuests", "worldMapShowActiveQuests", "Active Quests")
    minimod.wmBtnAQ:SetPoint("RIGHT", minimod.wmBtnWQ, "LEFT", -2, 0)

    minimod.wmBtnLS = make_wm_toggle("questlog-storylineicon", "wmDpLocalStories", "worldMapShowLocalStories",
        "Local Stories")
    minimod.wmBtnLS:SetPoint("RIGHT", minimod.wmBtnAQ, "LEFT", -2, 0)

    minimod.wmBtnDungeons = make_wm_toggle("questlog-questtypeicon-heroic", "wmDpDungeons", "worldMapShowDungeons",
        "Dungeons/Raids")
    minimod.wmBtnDungeons:SetPoint("RIGHT", minimod.wmBtnLS, "LEFT", -2, 0)

    minimod.wmBtnDelves = make_wm_toggle("questlog-questtypeicon-Delves", "wmDpDelves", "worldMapShowDelves", "Delves")
    minimod.wmBtnDelves:SetPoint("RIGHT", minimod.wmBtnDungeons, "LEFT", -2, 0)

    minimod.wmBtnEvents = make_wm_toggle("questlog-questtypeicon-story", "wmDpEvents", "worldMapShowEvents", "Events")
    minimod.wmBtnEvents:SetPoint("RIGHT", minimod.wmBtnDelves, "LEFT", -2, 0)

    local travelBtn ---@type Button
    travelBtn = minimod.MapUtils.create_toolbar_button(minimod.toolbar, "MagePortalAlliance", function()
        if not minimod.worldMap then return end
        db.worldMapShowTravel = not db.worldMapShowTravel
        for _, dpField in ipairs({ "wmDpTravel", "wmDpPortals", "wmDpAreaPOI" }) do
            local dp = minimod[dpField] ---@type any
            if dp then
                if db.worldMapShowTravel then dp:RefreshAllData() else dp:RemoveAllData() end
            end
        end
        travelBtn:SetAlpha(db.worldMapShowTravel and 1 or 0.4)
    end, "Travel")
    travelBtn:Hide()
    minimod.wmBtnTravel = travelBtn
    minimod.wmBtnTravel:SetPoint("RIGHT", minimod.wmBtnEvents, "LEFT", -2, 0)

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
        -- Minimap cross-fade
        if minimod.minimapFade.active then
            minimod.minimapFade.elapsed = minimod.minimapFade.elapsed + elapsed
            local t = math_min(1, minimod.minimapFade.elapsed / TRANSITION_DURATION)
            Minimap:SetAlpha(minimod.minimapFade.from + (minimod.minimapFade.to - minimod.minimapFade.from) * t)
            if t >= 1 then
                minimod.minimapFade.active = false
                if minimod.minimapFade.to == 0 then Minimap:Hide() end
            end
        end
        -- Grow/shrink transition
        if minimod.growTransition.active then
            minimod.growTransition.elapsed = minimod.growTransition.elapsed + elapsed
            local t = math_min(1, minimod.growTransition.elapsed / GROW_DURATION)
            local ts = t * t * (3 - 2 * t) -- smoothstep easing
            local gt = minimod.growTransition
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
            end
        end
        -- Toolbar visibility
        if minimod.toolbar then
            minimod.toolbar:SetShown(
                minimod.grown or
                minimod.wrapper:IsMouseOver() or
                minimod.toolbar:IsMouseOver()
            )
        end
        -- World map cross-fade
        if minimod.worldMapFade.active and minimod.worldMap then
            minimod.worldMapFade.elapsed = minimod.worldMapFade.elapsed + elapsed
            local t = math_min(1, minimod.worldMapFade.elapsed / TRANSITION_DURATION)
            minimod.worldMap:SetAlpha(minimod.worldMapFade.from +
                (minimod.worldMapFade.to - minimod.worldMapFade.from) * t)
            if t >= 1 then
                minimod.worldMapFade.active = false
                if minimod.worldMapFade.to == 0 then minimod.worldMap:Hide() end
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
            start_fade(db.moveAlpha)
        elseif event == "PLAYER_STOPPED_MOVING" then
            start_fade(db.alpha)
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

    -- Toggle grow: press to grow, press again to shrink
    local function toggle_grow()
        local cp = _G['ConsolePort']

        -- Shrinking
        if minimod.grown then
            minimod.grown = false
            if minimod.worldMapOpen then minimod.closeWorldMap() end
            if cp and cp:RemoveInterfaceCursorFrame(minimod.wrapper) then
                local ih = _G['ConsolePortInputHandler']
                if ih then ih:Release(minimod.wrapper) end
                _G['ConsolePortCursor']:SetEnabled(false)
            end
        else
            -- Growing
            minimod.grown = true
            if cp and cp:AddInterfaceCursorFrame(minimod.wrapper) then
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
        local to_w, to_h = size_for_shape({ shape = db.shape, size = size })

        minimod.growTransition.active = true
        minimod.growTransition.elapsed = 0
        minimod.growTransition.fromW = from_w
        minimod.growTransition.fromH = from_h
        minimod.growTransition.toW = to_w
        minimod.growTransition.toH = to_h
        minimod.growTransition.lastZoomAt = 0
    end

    if _G['ConsolePort'] then
        minimod.wrapper:SetPropagateKeyboardInput(true)

        minimod.wrapper:SetScript('OnGamePadButtonDown', function(_, key)
            if not minimod.grown or InCombatLockdown() then return end
            if key ~= 'PADRSHOULDER' and key ~= 'PADLSHOULDER' then return end

            local function do_zoom()
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
            do_zoom()
        end)
    end

    -- Expose as a global so Bindings.xml can invoke it by name.
    function ConsoleTools_MinimapGrowToggle() ---@diagnostic disable-line: lowercase-global
        if minimod.wrapper and minimod.wrapper:IsShown() then toggle_grow() end
    end

    -- Blizzard Key Bindings panel display strings.
    BINDING_HEADER_CONSOLETOOLS = "Console Tools" ---@diagnostic disable-line: lowercase-global
    BINDING_NAME_CONSOLETOOLS_MINIMAP_GROWTOGGLE = "Toggle Minimap Expand" ---@diagnostic disable-line: lowercase-global
end

--#endregion
