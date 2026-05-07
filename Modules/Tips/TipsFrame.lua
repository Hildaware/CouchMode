local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips = addon:GetModule('Tips')

--#region ── Anchor ───────────────────────────────────────────────────────────

---@param f TipsFrame
function tips.applyAnchor(f)
    if not f then return end
    local db = tips.tipsDB()
    local LibEditMode = LibStub('LibEditMode')
    local layoutName = LibEditMode:GetActiveLayoutName() or 'Default'
    local pos = db.positions[layoutName] or db.positions['Default']

    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
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
        local inInstance = addon.Utils.IsInInstance()
        if inInstance then
            w = tips.TIP_W -- skip naturalWidth(); GetStringWidth on secret strings is forbidden in instances
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

    tips.applyShadow()
    buildLayout(f)
end

local function setShadow(fs, enabled)
    if enabled then
        addon.Utils.apply_font_shadow(fs)
    else
        fs:SetShadowOffset(0, 0)
    end
end

function tips.applyShadow()
    containerPool.flush()
    unitInfoPool.flush()
    charPool.flush()
    mountPool.flush()
    questPool.flush()

    local f = tips.activeFrame
    if not f then return end
    local enabled = tips.tipsDB().shadowEnabled

    setShadow(f.unitInfo.name.fs, enabled)
    setShadow(f.unitInfo.pretitle.fs, enabled)
    setShadow(f.unitInfo.posttitle.fs, enabled)
    setShadow(f.unitInfo.subtitle.fs, enabled)
    setShadow(f.unitInfo.faction.fs, enabled)
    setShadow(f.unitInfo.level.fs, enabled)

    if f.chars then setShadow(f.chars.info.fs, enabled) end

    if f.mount then
        setShadow(f.mount.mountName.fs, enabled)
        setShadow(f.mount.mountSource.fs, enabled)
    end

    if f.quest then
        for i = 1, tips.MAX_QUEST_LINES do
            setShadow(f.quest.questLines[i].fs, enabled)
            for j = 1, tips.MAX_OBJECTIVES do
                setShadow(f.quest.questObjectives[i][j].fs, enabled)
            end
        end
    end
end

function tips.applyWidth()
    tips.TIP_W = tips.tipsDB().width or 240
    containerPool.flush()
    unitInfoPool.flush()
    charPool.flush()
    mountPool.flush()
    questPool.flush()

    if tips.editModeFrame then
        tips.editModeFrame:SetWidth(tips.TIP_W + 4)
    end

    local f = tips.activeFrame
    if not f then return end

    f:SetWidth(tips.TIP_W + 4)
    f.unitInfo:SetSize(tips.TIP_W, math.floor(tips.TIP_W * tips.HEADER_ASPECT))
    tips.applyFonts()
end

--#endregion
