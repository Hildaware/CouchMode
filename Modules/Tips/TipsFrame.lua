local addon_name = ...

---@class CouchMode: AceAddon
local addon      = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips       = addon:GetModule('Tips')

--#region ── Anchor ───────────────────────────────────────────────────────────

function tips.applyAnchor(f)
    if not f then return end
    local db = tips.tipsDB()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -200)
    if db.locked then
        f.indicator:Hide()
    else
        f.indicator:Show()
    end
end

function tips.applyDock()
    local f      = tips.activeFrame
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

--#region ── Frame building ───────────────────────────────────────────────────

tips.PADDING       = 10
tips.LINE_GAP      = 3
tips.ICON_SIZE     = 32
tips.ICON_GAP      = 4
tips.ICON_X        = (tips.ICON_SIZE + 24) / 240 -- class icon border width as fraction of default TIP_W
tips.HEADER_ASPECT = 69 / 304                    -- native atlas dimensions
tips.BADGE_W       = 37
tips.BADGE_H       = 38
tips.BADGE_GAP     = 6
tips.BADGE_X       = tips.BADGE_W / 240 -- badge width as fraction of default TIP_W

function tips.makeFontString(overlay, font, color)
    local fs = overlay:CreateFontString(nil, "OVERLAY")
    fs:SetFont(font())
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    if color then fs:SetVertexColor(unpack(color)) end
    return fs
end

local function buildFrame()
    local TIP_W = tips.TIP_W
    local f     = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(100)
    f:SetWidth(TIP_W + 4)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Outer background
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.65)

    -- 1px frame border
    local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
    border:SetAllPoints(f)
    border:SetFrameLevel(f:GetFrameLevel() + 5)
    border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    border:SetBackdropBorderColor(0.08, 0.08, 0.08, 1)

    -- Position indicator: light green border shown when unlocked
    f.indicator = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.indicator:SetAllPoints(f)
    f.indicator:SetFrameLevel(f:GetFrameLevel() + 20)
    f.indicator:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    f.indicator:SetBackdropBorderColor(0.3, 1.0, 0.3, 0.9)
    f.indicator:Hide()

    f.headerFrame = CreateFrame("Frame", nil, f)
    f.headerFrame:SetFrameLevel(f:GetFrameLevel() + 1)
    f.headerFrame:SetPoint("TOP", f, "TOP", 0, -4)
    f.headerFrame:SetSize(TIP_W, math.floor(TIP_W * tips.HEADER_ASPECT))

    f.headerBg = f.headerFrame:CreateTexture(nil, "ARTWORK")
    f.headerBg:SetAllPoints(f.headerFrame)

    local subfont = tips.currentSubFont

    -- Header overlay: text and badge live here, sized with headerFrame.
    local headerOverlay = CreateFrame("Frame", nil, f.headerFrame)
    headerOverlay:SetAllPoints(f.headerFrame)
    headerOverlay:SetFrameLevel(f.headerFrame:GetFrameLevel() + 1)

    tips.buildUnitInfo(f, headerOverlay, subfont)

    -- Main overlay: info line, class icon, mount section.
    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints(f)
    overlay:SetFrameLevel(f:GetFrameLevel() + 1)

    tips.buildCharacteristics(f, overlay, subfont)
    tips.buildMountInfo(f, overlay, subfont)
    tips.buildQuestInfo(f, overlay, subfont)

    -- Drag: free positioning — save center x/y on drop.
    f:SetScript("OnDragStart", function(self)
        if not tips.tipsDB().locked then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local db  = tips.tipsDB()
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        db.x      = math.floor(self:GetLeft() + self:GetWidth() / 2 - uiW / 2 + 0.5)
        db.y      = math.floor(self:GetBottom() + self:GetHeight() / 2 - uiH / 2 + 0.5)
        tips.applyAnchor(self)
    end)

    return f
end

--#endregion

--#region ── Ghost frame (position drag handle) ───────────────────────────────

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
        local db  = tips.tipsDB()
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        db.x      = math.floor(self:GetLeft() + self:GetWidth() / 2 - uiW / 2 + 0.5)
        db.y      = math.floor(self:GetBottom() + self:GetHeight() / 2 - uiH / 2 + 0.5)
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    end)

    f:Hide()
    return f
end

function tips.showGhostFrame()
    if not tips.ghostFrame then
        tips.ghostFrame = buildGhostFrame()
    end
    local db = tips.tipsDB()
    local f  = tips.ghostFrame
    f:SetWidth(tips.TIP_W + 4)
    f:SetHeight(math.floor(tips.TIP_W * tips.HEADER_ASPECT) + 8)
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -200)
    f:Show()
end

function tips.hideGhostFrame()
    if tips.ghostFrame then
        tips.ghostFrame:Hide()
    end
end

--#endregion

--#region ── Frame pool ───────────────────────────────────────────────────────

local pool = {}

local function acquire()
    local f = table.remove(pool) or buildFrame()
    f:SetParent(UIParent)
    f:ClearAllPoints()
    return f
end

local function release(f)
    f:Hide()
    f:ClearAllPoints()
    f:SetParent(nil)
    f._rawName   = nil
    f._nameColor = nil
    f.pretitle:SetText("")
    f.name:SetText("")
    f.posttitle:SetText("")
    f.subtitle:SetText("")
    f.level:SetText("")
    f.levelBadge:Hide()
    f.classificationIcon:Hide()
    f.faction:SetText("")
    f.classIcon:Hide()
    f.classIconBorder:Hide()
    f.info:SetText("")
    f.hasInfo = false
    f.mountDivider:Hide()
    f.mountIconBorder:Hide()
    f.mountIcon:Hide()
    f.mountName:SetText("")
    f.mountSource:SetText("")
    f.mountCollected:Hide()
    f.questDivider:Hide()
    for i, ql in ipairs(f.questLines) do
        ql:SetText("")
        ql:Hide()
        f.questIcons[i]:Hide()
        for _, obj in ipairs(f.questObjectives[i]) do
            obj:SetText("")
            obj:Hide()
        end
    end
    pool[#pool + 1] = f
end

tips.acquire = acquire
tips.release = release

--#endregion

--#region ── Layout ───────────────────────────────────────────────────────────

local function buildLayout(f)
    local fontPath, baseSize, fontFlag = tips.currentFont()
    local fonts                        = {
        path      = fontPath,
        baseSize  = baseSize,
        flag      = fontFlag,
        titleSize = math.max(8, math.floor(baseSize * 0.75)),
        guildSize = math.max(8, math.floor(baseSize * 0.60)),
    }

    local y, height                    = tips.layoutUnitInfo(f, fonts)
    y, height                          = tips.layoutCharacteristics(f, y, height, fonts)
    y, height                          = tips.layoutMountInfo(f, y, height, fonts)
    y, height                          = tips.layoutQuestInfo(f, y, height, fonts)

    f:SetHeight(math.max(-y + tips.PADDING, 30))
end

--#endregion

--#region ── Frame population ─────────────────────────────────────────────────

function tips.updateFrameForObject(f, name, questData)
    f.headerBg:SetAtlas("StoryHeader-BG", true)
    f._rawName   = name
    f._nameColor = "|cFFFFFFFF"
    f.name:SetText("|cFFFFFFFF" .. name .. "|r")
    f.pretitle:SetText("")
    f.posttitle:SetText("")
    f.subtitle:SetText("")
    f.faction:SetText("")
    f.level:SetText("")
    f.levelBadge:Hide()
    f.classificationIcon:Hide()
    f.classIcon:Hide()
    f.classIconBorder:Hide()
    f.info:SetText("")
    f.mountDivider:Hide()
    f.mountIconBorder:Hide()
    f.mountIcon:Hide()
    f.mountName:SetText("")
    f.mountSource:SetText("")
    f.mountCollected:Hide()
    tips.populateQuestSection(f, questData)
    buildLayout(f)
    tips.applyAnchor(f)
end

function tips.updateFrame(f, unit)
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
    f.headerBg:SetAtlas(headerAtlas, true)

    tips.populateUnitInfo(f, unit)
    tips.populateCharacteristics(f, unit)
    tips.populateMountInfo(f, unit)
    tips.populateQuestInfo(f, unit)

    buildLayout(f)
    tips.applyAnchor(f)
end

--#endregion

--#region ── Font refresh ─────────────────────────────────────────────────────

function tips.applyFonts()
    local f = tips.activeFrame
    if not f then return end
    f.level:SetFont(tips.currentSubFont())
    buildLayout(f)
end

function tips.applyWidth()
    tips.TIP_W = tips.tipsDB().width or 240
    wipe(pool)
    local gf = tips.ghostFrame
    if gf and gf:IsShown() then
        gf:SetWidth(tips.TIP_W + 4)
        gf:SetHeight(math.floor(tips.TIP_W * tips.HEADER_ASPECT) + 8)
    end
    local f = tips.activeFrame
    if not f then return end
    f:SetWidth(tips.TIP_W + 4)
    f.headerFrame:SetSize(tips.TIP_W, math.floor(tips.TIP_W * tips.HEADER_ASPECT))
    tips.applyFonts()
end

--#endregion
