local addon_name              = ...

---@class ConsoleTools: AceAddon
local addon                   = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class MapModule
local map                     = addon:GetModule('Minimap')

local _G                      = _G
local math_cos                = math.cos
local math_sin                = math.sin
local math_max                = math.max
local table_concat            = table.concat
local table_sort              = table.sort

local CreateFrame             = _G.CreateFrame
local Minimap                 = _G.Minimap
local C_Map                   = _G.C_Map
local C_Minimap               = _G.C_Minimap
local C_QuestLog              = _G.C_QuestLog
local C_VignetteInfo          = _G.C_VignetteInfo
local C_PetInfo               = _G.C_PetInfo
local Enum                    = _G.Enum
local GetCVar                 = _G.GetCVar
local GetPlayerFacing         = _G.GetPlayerFacing
local GetQuestLogLeaderBoard  = _G.GetQuestLogLeaderBoard ---@diagnostic disable-line: undefined-global
local GetNumQuestLeaderBoards = _G.GetNumQuestLeaderBoards ---@diagnostic disable-line: undefined-global
local wipe                    = _G.wipe

local POOL_SIZE               = 20
local UPDATE_THROTTLE         = 0.05

local poi_candidates          = {} -- {sx, sy, d2, title, sub} wiped each update
local placed_rects            = {} -- {rx, ry, fw, fh}          wiped each update

--#region ── Coordinate math ──────────────────────────────────────────────────

-- Returns (screenX, screenY) pixel offset from minimap center for a given
-- normalized map position, or nil if position is off-map or player pos unknown.
local function map_to_minimap_pixels(mapID, poiX, poiY)
    local playerPos = C_Map.GetPlayerMapPosition(mapID, 'player')
    if not playerPos then return nil, nil end
    local pX, pY = playerPos:GetXY()

    local mapW, mapH = C_Map.GetMapWorldSize(mapID)
    if not mapW or mapW == 0 then return nil, nil end

    local viewRadius = C_Minimap.GetViewRadius()
    if not viewRadius or viewRadius == 0 then return nil, nil end

    local mmRadius = Minimap:GetWidth() / 2

    local dx_yards = (poiX - pX) * mapW
    local dy_yards = -(poiY - pY) * mapH -- Y is inverted in map coords

    local sx = (dx_yards / viewRadius) * mmRadius
    local sy = (dy_yards / viewRadius) * mmRadius

    -- Rotate if minimap is set to face direction of travel
    if GetCVar('rotateMinimap') == '1' then
        local facing = GetPlayerFacing() or 0
        local cf = math_cos(-facing)
        local sf = math_sin(-facing)
        sx, sy = cf * sx - sf * sy, sf * sx + cf * sy
    end

    return sx, sy
end

--#endregion

--#region ── Label pool ───────────────────────────────────────────────────────

local function create_label_frame(parent)
    local f = CreateFrame('Frame', nil, parent)
    f:SetFrameStrata('TOOLTIP')
    f:SetFrameLevel(parent:GetFrameLevel() + 10)
    f:Hide()

    local bg = f:CreateTexture(nil, 'BACKGROUND')
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.6)
    f.bg = bg

    -- Arrow pointing down toward the blip, anchored below the label
    local arrow = f:CreateTexture(nil, 'BACKGROUND', nil, -1)
    arrow:SetAtlas('Azerite-PointingArrow', true)
    arrow:SetPoint('TOP', f, 'BOTTOM', 0, 0)
    arrow:SetSize(12, 16)
    f.arrow = arrow

    local title = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    title:SetJustifyH('CENTER')
    title:SetJustifyV('TOP')
    title:SetTextColor(.8, .8, 0, 1)
    f.title = title

    -- Subtitle: muted gray, slightly smaller
    local sub = f:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
    sub:SetJustifyH('CENTER')
    sub:SetJustifyV('TOP')
    sub:SetTextColor(1, 1, 1, 1)
    f.subtitle = sub

    return f
end

function map.createPOILabelPool()
    if not map.poiLabelPool then
        map.poiLabelPool = {}
    end
    -- Fill pool up to POOL_SIZE (idempotent)
    while #map.poiLabelPool < POOL_SIZE do
        local f = create_label_frame(map.container)
        map.poiLabelPool[#map.poiLabelPool + 1] = f
    end
end

--#endregion

--#region ── Label placement ──────────────────────────────────────────────────

local function acquire_label(pool, idx)
    local f = pool[idx]
    if not f then return nil end
    f:Hide()
    return f
end

local FONT     = 'Fonts\\FRIZQT__.TTF'
local PAD_H    = 8 -- horizontal padding (each side)
local PAD_V    = 6 -- vertical padding (each side)
local LINE_GAP = 1 -- gap between title and subtitle

local function place_label(f, db, screenX, screenY, titleText, subText)
    local titleSize = db.poiLabelsFontSize
    local subSize   = math_max(7, titleSize - 2)
    local alpha     = db.poiLabelsAlpha

    -- ── Title ────────────────────────────────────────────────────────────
    f.title:SetFont(FONT, titleSize, 'OUTLINE')
    f.title:SetAlpha(alpha)
    f.title:SetText(titleText)
    local tw = f.title:GetStringWidth()
    local th = f.title:GetStringHeight()

    -- ── Subtitle ─────────────────────────────────────────────────────────
    local sw, sh = 0, 0
    if subText and subText ~= '' then
        f.subtitle:SetFont(FONT, subSize, 'OUTLINE')
        f.subtitle:SetAlpha(alpha)
        f.subtitle:SetText(subText)
        sw = f.subtitle:GetStringWidth()
        sh = f.subtitle:GetStringHeight()
        f.subtitle:Show()
    else
        f.subtitle:SetText('')
        f.subtitle:Hide()
    end

    -- ── Frame size ───────────────────────────────────────────────────────
    local fw = math_max(tw, sw) + PAD_H * 2
    local fh = th + (sh > 0 and (sh + LINE_GAP) or 0) + PAD_V * 2
    f:SetSize(fw, fh)

    -- ── Anchor FontStrings inside frame ──────────────────────────────────
    f.title:ClearAllPoints()
    f.title:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD_H, -PAD_V)
    f.title:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -PAD_H, -PAD_V)
    f.title:SetHeight(th)

    f.subtitle:ClearAllPoints()
    f.subtitle:SetPoint('TOPLEFT', f, 'TOPLEFT', PAD_H, -(PAD_V + th + LINE_GAP))
    f.subtitle:SetPoint('TOPRIGHT', f, 'TOPRIGHT', -PAD_H, -(PAD_V + th + LINE_GAP))
    if sh > 0 then f.subtitle:SetHeight(sh) end

    -- ── Position ─────────────────────────────────────────────────────────
    f:ClearAllPoints()
    f:SetPoint('CENTER', map.container, 'CENTER', screenX, screenY + 26)
    f:Show()
end

-- Measures label dimensions without rendering. Safe on a hidden frame.
local function measure_label(f, db, titleText, subText)
    local titleSize = db.poiLabelsFontSize
    local subSize   = math_max(7, titleSize - 2)

    f.title:SetFont(FONT, titleSize, 'OUTLINE')
    f.title:SetText(titleText)
    local tw = f.title:GetStringWidth()
    local th = f.title:GetStringHeight()

    local sw, sh = 0, 0
    if subText and subText ~= '' then
        f.subtitle:SetFont(FONT, subSize, 'OUTLINE')
        f.subtitle:SetText(subText)
        sw = f.subtitle:GetStringWidth()
        sh = f.subtitle:GetStringHeight()
    end

    local fw = math_max(tw, sw) + PAD_H * 2
    local fh = th + (sh > 0 and (sh + LINE_GAP) or 0) + PAD_V * 2
    return fw, fh
end

local function aabb_overlap(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and ax + aw > bx
        and ay < by + bh and ay + ah > by
end

function map.updatePOILabels()
    if not map.poiLabelPool then return end

    local db = addon.db.profile.minimap ---@type MinimapDB

    -- Hide all pool frames first
    for i = 1, #map.poiLabelPool do
        map.poiLabelPool[i]:Hide()
    end

    if not db.poiLabelsEnabled
        or not map.container or not map.container:IsShown()
        or not map.grown
        or map.worldMapOpen then
        return
    end

    local mapID = C_Map.GetBestMapForUnit('player')
    if not mapID then return end

    local mmRadius  = Minimap:GetWidth() / 2
    local mmRadius2 = mmRadius * mmRadius
    local sub_lines = {} -- reused across iterations
    local getTitle  = C_QuestLog.GetTitleForQuestID
    local getLogIdx = C_QuestLog.GetLogIndexForQuestID

    -- ── Collect all visible POIs ──────────────────────────────────────────
    wipe(poi_candidates)

    local quests = db.poiLabelsShowQuests and C_QuestLog.GetQuestsOnMap(mapID)
    if quests then
        for _, info in ipairs(quests) do
            local sx, sy = map_to_minimap_pixels(mapID, info.x, info.y)
            if sx and sy then
                local d2 = sx * sx + sy * sy
                if d2 <= mmRadius2 then
                    local title  = getTitle(info.questID) or '?'
                    local logIdx = getLogIdx and getLogIdx(info.questID)
                    wipe(sub_lines)
                    if logIdx and GetNumQuestLeaderBoards then
                        local num = GetNumQuestLeaderBoards(logIdx)
                        for i = 1, num do
                            local obj_text, _, finished = GetQuestLogLeaderBoard(i, logIdx)
                            if obj_text and not finished then
                                sub_lines[#sub_lines + 1] = obj_text
                            end
                        end
                    end
                    poi_candidates[#poi_candidates + 1] = { sx, sy, d2, title, table_concat(sub_lines, '\n') }
                end
            end
        end
    end

    if (db.poiLabelsShowRares or db.poiLabelsShowTreasures) and C_VignetteInfo then
        local guids = C_VignetteInfo.GetVignettes and C_VignetteInfo.GetVignettes()
        if guids then
            for _, guid in ipairs(guids) do
                local vinfo = C_VignetteInfo.GetVignetteInfo(guid)
                if vinfo and vinfo.onMinimap and vinfo.name then
                    local isTreasure = vinfo.type == Enum.VignetteType.Treasure
                    if (isTreasure and db.poiLabelsShowTreasures)
                        or (not isTreasure and db.poiLabelsShowRares) then
                        local pos = C_VignetteInfo.GetVignettePosition(guid, mapID)
                        if pos then
                            local vx, vy = pos:GetXY()
                            local sx, sy = map_to_minimap_pixels(mapID, vx, vy)
                            if sx and sy then
                                local d2 = sx * sx + sy * sy
                                if d2 <= mmRadius2 then
                                    poi_candidates[#poi_candidates + 1] = { sx, sy, d2, vinfo.name, '' }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if db.poiLabelsShowPetTamers and C_PetInfo and C_Minimap.IsTrackingBattlePets() then
        local tamers = C_PetInfo.GetPetTamersForMap and C_PetInfo.GetPetTamersForMap(mapID)
        if tamers then
            for _, tamer in ipairs(tamers) do
                if tamer.name and tamer.position then
                    local tx, ty = tamer.position:GetXY()
                    local sx, sy = map_to_minimap_pixels(mapID, tx, ty)
                    if sx and sy then
                        local d2 = sx * sx + sy * sy
                        if d2 <= mmRadius2 then
                            poi_candidates[#poi_candidates + 1] = { sx, sy, d2, tamer.name, '' }
                        end
                    end
                end
            end
        end
    end

    -- ── Sort: closest POIs get label priority ─────────────────────────────
    table_sort(poi_candidates, function(a, b) return a[3] < b[3] end)

    -- ── Place: skip any label whose rect overlaps an already-placed one ───
    -- pool[POOL_SIZE] is reserved as a hidden scratch frame for measurement.
    local scratch  = map.poiLabelPool[POOL_SIZE]
    local placed_n = 0
    local poolIdx  = 1

    for _, poi in ipairs(poi_candidates) do
        if poolIdx >= POOL_SIZE then break end

        local sx, sy, title, sub = poi[1], poi[2], poi[4], poi[5]
        local fw, fh = measure_label(scratch, db, title, sub)
        local rx = sx - fw * 0.5
        local ry = sy + 26 - fh * 0.5

        local overlaps = false
        for i = 1, placed_n do
            local p = placed_rects[i]
            if aabb_overlap(rx, ry, fw, fh, p[1], p[2], p[3], p[4]) then
                overlaps = true
                break
            end
        end

        if not overlaps then
            local f = acquire_label(map.poiLabelPool, poolIdx)
            if f then
                place_label(f, db, sx, sy, title, sub)
                poolIdx  = poolIdx + 1
                placed_n = placed_n + 1
                if not placed_rects[placed_n] then placed_rects[placed_n] = {} end
                local p = placed_rects[placed_n]
                p[1], p[2], p[3], p[4] = rx, ry, fw, fh
            end
        end
    end
end

function map.applyPOILabels()
    map.updatePOILabels()
end

--#endregion

--#region ── Event-driven updates ─────────────────────────────────────────────

local poiElapsed = 0
local poiEventFrame = CreateFrame('Frame')
poiEventFrame:RegisterEvent('QUEST_LOG_UPDATE')
poiEventFrame:RegisterEvent('QUEST_POI_UPDATE')
poiEventFrame:RegisterEvent('QUEST_TURNED_IN')
poiEventFrame:RegisterEvent('QUEST_WATCH_LIST_CHANGED')
poiEventFrame:RegisterEvent('MINIMAP_UPDATE_ZOOM')
poiEventFrame:RegisterEvent('ZONE_CHANGED')
poiEventFrame:RegisterEvent('ZONE_CHANGED_INDOORS')
poiEventFrame:RegisterEvent('ZONE_CHANGED_NEW_AREA')
poiEventFrame:RegisterEvent('PLAYER_ENTERING_WORLD')
poiEventFrame:RegisterEvent('VIGNETTE_MINIMAP_UPDATED')
poiEventFrame:RegisterEvent('MINIMAP_UPDATE_TRACKING')
poiEventFrame:SetScript('OnEvent', function()
    poiElapsed = UPDATE_THROTTLE -- force immediate update next OnUpdate
end)

poiEventFrame:SetScript('OnUpdate', function(_, elapsed)
    poiElapsed = poiElapsed + elapsed
    if poiElapsed >= UPDATE_THROTTLE then
        poiElapsed = 0
        map.updatePOILabels()
    end
end)

--#endregion

--#region ── Hooks ────────────────────────────────────────────────────────────

do
    -- Reposition labels on resize / zoom
    local orig = map.applySettings
    map.applySettings = function(...)
        orig(...)
        map.updatePOILabels()
    end
end

do
    -- Hide labels immediately when the world map opens
    local orig = map.openWorldMap
    map.openWorldMap = function()
        orig()
        map.updatePOILabels()
    end
end

--#endregion
