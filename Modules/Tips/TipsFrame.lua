local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

--#region ── Anchor ───────────────────────────────────────────────────────────

-- Derives the best anchor point from the frame's current screen position and
-- stores x/y as offsets from that corner (rather than from CENTER).
local function saveAnchor(frame)
    local db = tips.tipsDB()
    local uiW = UIParent:GetWidth()
    local uiH = UIParent:GetHeight()
    local cx = frame:GetLeft() + frame:GetWidth() / 2
    local cy = frame:GetBottom() + frame:GetHeight() / 2
    local h = cx < uiW * 0.4 and "LEFT" or cx > uiW * 0.6 and "RIGHT" or ""
    -- Default to TOP so the frame always grows downward; only flip to BOTTOM
    -- when near the very bottom of the screen.
    local v = cy < uiH * 0.2 and "BOTTOM" or "TOP"
    db.anchor = v .. h
    db.x = math.floor((h == "LEFT" and frame:GetLeft()
        or h == "RIGHT" and (frame:GetRight() - uiW)
        or (cx - uiW / 2)) + 0.5)
    db.y = math.floor((v == "TOP" and (frame:GetTop() - uiH)
        or frame:GetBottom()) + 0.5)
end

---@param f TipsFrame
function tips.applyAnchor(f)
    if not f then return end
    local db = tips.tipsDB()
    local anchor = db.anchor or "TOP"
    f:ClearAllPoints()
    f:SetPoint(anchor, UIParent, anchor, db.x or 0, db.y or -100)
    f:SetPoint(anchor, UIParent, anchor, db.x or 0, db.y or -100)
end

function tips.applyDock()
    local f = tips.activeFrame
    local locked = tips.tipsDB().locked
    if locked then
        tips.hideGhostFrame()
        if f then tips.applyAnchor(f) end
    else
        if f then
            tips.applyAnchor(f)
        else
            tips.showGhostFrame()
        end
    end
end

--#endregion

--#region ── Constants ────────────────────────────────────────────────────────

tips.PADDING = 10
tips.LINE_GAP = 3
tips.ICON_SIZE = 32
tips.ICON_GAP = 4
tips.ICON_X = (tips.ICON_SIZE + 24) / 240
tips.HEADER_ASPECT = 69 / 304
tips.BADGE_W = 37
tips.BADGE_H = 38
tips.BADGE_GAP = 6
tips.BADGE_X = tips.BADGE_W / 240
tips.QUEST_ICON_SIZE = 14
tips.QUEST_ICON_GAP = 4

--#endregion

--#region ── Ghost frame ──────────────────────────────────────────────────────

local function buildGhostFrame()
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(99)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.55)

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(tips.currentSubFont())
    label:SetPoint("CENTER", f, "CENTER", 0, 0)
    label:SetText("Drag to reposition")
    label:SetVertexColor(0.3, 1.0, 0.3, 1)

    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetAllPoints(f)
    border:SetFrameLevel(f:GetFrameLevel() + 10)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    border:SetBackdropBorderColor(0.3, 1.0, 0.3, 0.9)

    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveAnchor(self)
        local db = tips.tipsDB()
        self:ClearAllPoints()
        self:SetPoint(db.anchor, UIParent, db.anchor, db.x, db.y)
    end)

    f:Hide()
    return f
end

function tips.showGhostFrame()
    if not tips.ghostFrame then
        tips.ghostFrame = buildGhostFrame()
    end
    local db = tips.tipsDB()
    local f = tips.ghostFrame
    f:SetWidth(tips.TIP_W + 4)
    f:SetHeight(math.floor(tips.TIP_W * tips.HEADER_ASPECT) + 8)
    local anchor = db.anchor or "TOP"
    f:ClearAllPoints()
    f:SetPoint(anchor, UIParent, anchor, db.x or 0, db.y or -100)
    f:Show()
end

function tips.hideGhostFrame()
    if tips.ghostFrame then
        tips.ghostFrame:Hide()
    end
end

--#endregion

--#region ── Outer frame build ────────────────────────────────────────────────

---@return TipsFrame
local function buildContainer()
    local TIP_W = tips.TIP_W

    ---@type TipsFrame
    local container = addon.Layout:VStack(UIParent, {
        spacing = 0,
        frameStrata = "TOOLTIP",
        frameLevel = 100,
        width = TIP_W + 4,
        childAlign = "CENTER",
    })

    local function onDragStart(self) if not tips.tipsDB().locked then self:StartMoving() end end
    local function onDragStop(self)
        self:StopMovingOrSizing()
        saveAnchor(self)
        tips.applyAnchor(container)
    end

    container:Movable(onDragStart, onDragStop)

    container.bg = container:AddBackground("Interface\\Addons\\CouchMode\\Media\\parchment_bg", {
        alpha = 0.85,
        insets = { left = -16, right = 16, top = 12, bottom = -12 },
    })

    return container
end

--#endregion

--#region ── Section pool helpers ─────────────────────────────────────────────

local function resetSection(s)
    s:reset()
    s:Hide()
    s.frame:SetParent(UIParent)
end

local unitInfoPool = addon.Utils.CreatePool(tips.buildUnitInfo, resetSection)
local charPool = addon.Utils.CreatePool(tips.buildCharacteristics, resetSection)
local mountPool = addon.Utils.CreatePool(tips.buildMountInfo, resetSection)
local questPool = addon.Utils.CreatePool(tips.buildQuestInfo, resetSection)

---@param f TipsFrame
local function releaseSections(f)
    if f.unitInfo then
        unitInfoPool.release(f.unitInfo); f.unitInfo = nil
    end
    if f.chars then
        charPool.release(f.chars); f.chars = nil
    end
    if f.mount then
        mountPool.release(f.mount); f.mount = nil
    end
    if f.quest then
        questPool.release(f.quest); f.quest = nil
    end
end

--#endregion

--#region ── Frame pool ───────────────────────────────────────────────────────

---@param f TipsFrame
local reset = function(f)
    f:Hide()
    f:ClearAllPoints()
    f.frame:SetParent(nil)
    releaseSections(f)
end

local containerPool = addon.Utils.CreatePool(buildContainer, reset)

tips.acquire = function()
    ---@type TipsFrame
    local f = containerPool.acquire()
    f.frame:SetParent(UIParent)
    f:ClearAllPoints()
    return f
end

tips.release = containerPool.release

--#endregion

--#region ── Layout ───────────────────────────────────────────────────────────

---@param f TipsFrame
---@param fullWidth? boolean
local function buildLayout(f, fullWidth)
    -- Register only the sections that were acquired
    f:ClearChildren()
    f:AddChild(f.unitInfo)
    if f.chars then f:AddChild(f.chars) end
    if f.mount then f:AddChild(f.mount) end
    if f.quest then f:AddChild(f.quest) end

    -- Players always use the full user-configured width
    local w
    if fullWidth then
        w = tips.TIP_W
    else
        local inInstance = IsInInstance()
        if inInstance then
            w = tips.TIP_W  -- skip naturalWidth(); GetStringWidth on secret strings is forbidden in instances
        else
            w = f.unitInfo:naturalWidth()
            if f.chars then w = math.max(w, f.chars:naturalWidth()) end
            if f.mount then w = math.max(w, f.mount:naturalWidth()) end
            if f.quest then w = math.max(w, f.quest:naturalWidth()) end
            w = math.max(math.min(w, tips.TIP_W), 140)
        end
    end

    f:SetWidth(w + 4)

    -- Draw each section at the resolved width
    f.unitInfo:draw((w == tips.TIP_W) and w or w + 8)
    if f.chars then f.chars:draw(w) end
    if f.mount then f.mount:draw(w) end
    if f.quest then f.quest:draw(w) end

    local totalH, _ = f:Layout()
    f:SetHeight(math.max(totalH + tips.PADDING, 30))

    local baseHeight = math.floor(w * tips.HEADER_ASPECT)
    if f:GetHeight() <= baseHeight then
        f.bg:Hide()
    else
        f.bg:Show()
    end
end

--#endregion

--#region ── Frame population ─────────────────────────────────────────────────

---@param f TipsFrame
---@param unit string|nil
function tips.updateFrame(f, unit)
    releaseSections(f)

    local headerAtlas = "StoryHeader-BG"
    if UnitCanAttack("player", unit) then
        headerAtlas = "Campaign_Fist"
    else
        local fg = UnitFactionGroup(unit)
        if fg == "Horde" then
            headerAtlas = "Campaign_Horde"
        elseif fg == "Alliance" then
            headerAtlas = "Campaign_Alliance"
        end
    end

    -- UnitInfo: always present
    f.unitInfo = unitInfoPool.acquire()
    f.unitInfo.frame:SetParent(f.frame)
    f.unitInfo.frame:Show()
    f.unitInfo:populate(unit, nil, headerAtlas)

    -- Characteristics: only if unit has class / creature-type data
    local ch = charPool.acquire()
    ch:populate(unit)
    if ch.hasData then
        ch.frame:SetParent(f.frame)
        ch.frame:Show()
        f.chars = ch
    else
        charPool.release(ch)
    end

    -- MountInfo: only if unit is mounted
    local mo = mountPool.acquire()
    mo:populate(unit)
    if mo.hasData then
        mo.frame:SetParent(f.frame)
        mo.frame:Show()
        f.mount = mo
    else
        mountPool.release(mo)
    end

    -- QuestInfo: only for NPCs with active quests
    local qu = questPool.acquire()
    qu:populate(unit)
    if qu.hasData then
        qu.frame:SetParent(f.frame)
        qu.frame:Show()
        f.quest = qu
    else
        questPool.release(qu)
    end

    buildLayout(f, UnitIsPlayer(unit))
    tips.applyAnchor(f)
end

function tips.updateFrameForObject(f, name, questData)
    releaseSections(f)

    -- UnitInfo: always present
    f.unitInfo = unitInfoPool.acquire()
    f.unitInfo.frame:SetParent(f.frame)
    f.unitInfo.frame:Show()
    f.unitInfo:populate(nil, name, "StoryHeader-BG")

    -- QuestInfo: only if quest data was parsed from world cursor
    if questData then
        local qu = questPool.acquire()
        qu:populateFromData(questData)
        if qu.hasData then
            qu.frame:SetParent(f.frame)
            qu.frame:Show()
            f.quest = qu
        else
            questPool.release(qu)
        end
    end

    buildLayout(f)
    tips.applyAnchor(f)
end

--#endregion

--#region ── Font / width refresh ─────────────────────────────────────────────

function tips.applyFonts()
    -- Wipe all pools so new builds pick up the updated fonts.
    containerPool.flush()
    unitInfoPool.flush()
    charPool.flush()
    mountPool.flush()
    questPool.flush()

    local f = tips.activeFrame
    if not f then return end

    -- Directly update fontstrings on the active frame's sections.
    local fontPath, baseSize, fontFlag = tips.currentFont()
    local titleSize = math.max(8, math.floor(baseSize * 0.75))
    local guildSize = math.max(8, math.floor(baseSize * 0.60))

    -- UnitInfo
    f.unitInfo.name:SetFont(fontPath, baseSize, fontFlag)
    f.unitInfo.pretitle:SetFont(fontPath, titleSize, fontFlag)
    f.unitInfo.posttitle:SetFont(fontPath, titleSize, fontFlag)
    f.unitInfo.subtitle:SetFont(fontPath, guildSize, fontFlag)
    f.unitInfo.faction:SetFont(fontPath, guildSize, fontFlag)
    f.unitInfo.level:SetFont(tips.currentSubFont())

    -- Characteristics (may be absent)
    if f.chars then
        f.chars.charFontSize = baseSize
        f.chars.info:SetFont(fontPath, baseSize, fontFlag)
    end

    -- MountInfo (may be absent)
    if f.mount then
        f.mount.mountFontSize = guildSize
        f.mount.mountName:SetFont(fontPath, guildSize, fontFlag)
        f.mount.mountSource:SetFont(fontPath, guildSize, fontFlag)
    end

    -- QuestInfo (may be absent)
    if f.quest then
        for i = 1, tips.MAX_QUEST_LINES do
            f.quest.questLines[i]:SetFont(fontPath, guildSize, fontFlag)
            for j = 1, tips.MAX_OBJECTIVES do
                f.quest.questObjectives[i][j]:SetFont(fontPath, guildSize, fontFlag)
            end
        end
    end

    buildLayout(f)
end

function tips.applyWidth()
    tips.TIP_W = tips.tipsDB().width or 240
    containerPool.flush()
    unitInfoPool.flush()
    charPool.flush()
    mountPool.flush()
    questPool.flush()

    local gf = tips.ghostFrame
    if gf and gf:IsShown() then
        gf:SetWidth(tips.TIP_W + 4)
        gf:SetHeight(math.floor(tips.TIP_W * tips.HEADER_ASPECT) + 8)
    end

    local f = tips.activeFrame
    if not f then return end

    f:SetWidth(tips.TIP_W + 4)
    f.unitInfo:SetSize(tips.TIP_W, math.floor(tips.TIP_W * tips.HEADER_ASPECT))
    tips.applyFonts()
end

--#endregion
