local addonName = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class PlayerCastBar: AceModule
---@field preview boolean
---@field castRingMode boolean
local castBar = addon:NewModule('PlayerCastBar', 'AceEvent-3.0')
---@cast castBar +AceEvent-3.0

---@type CastUtil
local CastUtil = addon.CastUtil

local MEDIA = {
    TEXTURE = 'interface/hud/uiwowlabsactionbar',
    BAR_ATLAS = 'plunderstorm-stormbar-fill',
    BORDER_ATLAS = 'plunderstorm-stormbar-border',
    BG_ATLAS = 'plunderstorm-stormbar-background',
    SPARK_TEX = "interface\\questframe\\objectivewidget",
    SPARK_ATLAS = "objectivewidget-bar-spark-neutral",
    ICON_MASK = "Interface\\AddOns\\CouchMode\\Media\\IconMask",
    ICON_BORDER = "Interface\\AddOns\\CouchMode\\Media\\IconBorder",
}

---@class PlayerCastBarGUI
---@field frame Frame
---@field iconFrame Frame
---@field icon Texture
---@field spellName FontString
---@field castTimer FontString
---@field leftBar BarSide
---@field rightBar BarSide
---@field barFullWidth number
local gui = {
    barFullWidth = 0
}

---@class BarSide
---@field bg Texture
---@field bar Texture
---@field tex Texture
---@field border Texture
---@field spark Texture
---@field latency Texture

-- OnUpdate optimization
local lastTimerText = ""

local function cfg()
    return addon.db.profile.playerCastBar
end

local function CreateBarSide(parentFrame, iconFrm, isLeft)
    local h = cfg().height

    local bg = parentFrame:CreateTexture(nil, "BACKGROUND")
    if isLeft then
        bg:SetPoint("LEFT", parentFrame, "LEFT")
        bg:SetPoint("RIGHT", iconFrm, "RIGHT")
    else
        bg:SetPoint("LEFT", iconFrm, "LEFT")
        bg:SetPoint("RIGHT", parentFrame, "RIGHT")
    end
    bg:SetHeight(h)
    bg:SetTexture(MEDIA.TEXTURE)
    bg:SetAtlas(MEDIA.BG_ATLAS)

    local fill = CreateFrame("Frame", nil, parentFrame)
    fill:SetFrameStrata("MEDIUM")
    fill:SetClipsChildren(true)
    fill:SetHeight(h)
    fill:SetWidth(0)
    if isLeft then
        fill:SetPoint("RIGHT", iconFrm, "LEFT")
    else
        fill:SetPoint("LEFT", iconFrm, "RIGHT")
    end

    local fillTex = fill:CreateTexture(nil, "BACKGROUND")
    if isLeft then
        fillTex:SetPoint("RIGHT", iconFrm, "LEFT")
        fillTex:SetPoint("LEFT", parentFrame, "LEFT")
    else
        fillTex:SetPoint("LEFT", iconFrm, "RIGHT")
        fillTex:SetPoint("RIGHT", parentFrame, "RIGHT")
    end
    fillTex:SetHeight(h)
    fillTex:SetTexture(MEDIA.TEXTURE)
    fillTex:SetAtlas(MEDIA.BAR_ATLAS)

    local borderFrm = CreateFrame("Frame", nil, parentFrame)
    borderFrm:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local borderCenter = borderFrm:CreateTexture(nil, "OVERLAY")
    if isLeft then
        borderCenter:SetPoint("RIGHT", iconFrm, "RIGHT")
        borderCenter:SetPoint("LEFT", parentFrame, "LEFT")
    else
        borderCenter:SetPoint("LEFT", iconFrm, "LEFT")
        borderCenter:SetPoint("RIGHT", parentFrame, "RIGHT")
    end
    borderCenter:SetHeight(h)
    borderCenter:SetTexture(MEDIA.TEXTURE)
    borderCenter:SetAtlas(MEDIA.BORDER_ATLAS)

    local spark = borderFrm:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(MEDIA.SPARK_TEX)
    spark:SetAtlas(MEDIA.SPARK_ATLAS)
    if isLeft then
        spark:SetPoint("CENTER", fill, "LEFT", 0, 0)
    else
        spark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
    end

    return {
        bg = bg,
        bar = fill,
        tex = fillTex,
        border = borderCenter,
        spark = spark,
    }
end

local function RefreshBarSide(cap, isLeft, t)
    t.bg:ClearAllPoints()
    t.border:ClearAllPoints()
    if isLeft then
        t.bg:SetPoint("LEFT", gui.frame, "LEFT")
        t.bg:SetPoint("RIGHT", gui.iconFrame, "RIGHT")
        t.border:SetPoint("LEFT", gui.frame, "LEFT")
        t.border:SetPoint("RIGHT", gui.iconFrame, "RIGHT")
    else
        t.bg:SetPoint("LEFT", gui.iconFrame, "LEFT")
        t.bg:SetPoint("RIGHT", gui.frame, "RIGHT")
        t.border:SetPoint("LEFT", gui.iconFrame, "LEFT")
        t.border:SetPoint("RIGHT", gui.frame, "RIGHT")
    end

    t.bg:SetHeight(cap)
    t.bar:SetHeight(cap)
    t.tex:SetHeight(cap)
    t.border:SetHeight(cap)
    t.spark:SetSize(cap / 2, cap * 1.5)
end

-- ── Refresh ───────────────────────────────────────────────────────────────────
function castBar:Refresh()
    if not gui.frame then return end
    local c = cfg()

    gui.frame:SetSize(c.width, c.height)
    gui.frame:ClearAllPoints()
    gui.frame:SetPoint("CENTER", UIParent, "CENTER", c.xPos, c.yPos)

    gui.frame:SetMovable(not c.locked)
    gui.frame:EnableMouse(not c.locked)

    if gui.iconFrame then
        gui.iconFrame:SetSize(c.height * 2, c.height * 1.6)
        gui.barFullWidth = (c.width - c.height * 2) / 2 + 2
    end

    if gui.leftBar then
        local cap = c.height
        RefreshBarSide(cap, true, gui.leftBar)
        RefreshBarSide(cap, false, gui.rightBar)
        gui.leftBar.spark:SetShown(c.showSpark)
        gui.rightBar.spark:SetShown(c.showSpark)
        if not c.showLatency then
            gui.leftBar.latency:Hide()
            gui.rightBar.latency:Hide()
        end
    end

    gui.iconFrame:SetShown(c.showIcon)
    gui.spellName:SetShown(c.showSpellName)
    gui.castTimer:SetShown(c.showTimer)
end

--#region ── UI Construction ───────────────────────────────────────────────────────────
function castBar:CreateUI()
    gui.frame = CreateFrame("Frame", "PlayerCastBarFrame", UIParent)
    gui.frame:SetFrameStrata("MEDIUM")
    gui.frame:SetFrameLevel(10)
    gui.frame:Hide()

    CastUtil.ApplyDragToMove(gui.frame, cfg)

    gui.iconFrame = CreateFrame("Button", nil, gui.frame)
    gui.iconFrame:SetPoint("CENTER", gui.frame, "CENTER")
    gui.iconFrame:SetFrameLevel(gui.frame:GetFrameLevel() + 5)
    gui.iconFrame:EnableMouse(false)

    gui.icon = gui.iconFrame:CreateTexture(nil, "ARTWORK")
    gui.icon:SetAllPoints(gui.iconFrame)

    local iconMask = gui.iconFrame:CreateMaskTexture()
    iconMask:SetTexture(MEDIA.ICON_MASK)
    iconMask:SetAllPoints(gui.icon)
    gui.icon:AddMaskTexture(iconMask)

    local iconBorderTex = gui.iconFrame:CreateTexture(nil, "OVERLAY")
    iconBorderTex:SetTexture(MEDIA.ICON_BORDER)
    iconBorderTex:SetAllPoints(gui.iconFrame)

    gui.leftBar = CreateBarSide(gui.frame, gui.iconFrame, true)
    gui.rightBar = CreateBarSide(gui.frame, gui.iconFrame, false)

    local latencyFrm = CreateFrame("Frame", nil, gui.frame)
    latencyFrm:SetFrameLevel(gui.frame:GetFrameLevel() + 2)
    latencyFrm:SetAllPoints()

    gui.leftBar.latency = latencyFrm:CreateTexture(nil, "OVERLAY")
    gui.leftBar.latency:SetTexture(MEDIA.TEXTURE)
    gui.leftBar.latency:SetAtlas(MEDIA.BAR_ATLAS)
    gui.leftBar.latency:SetDesaturated(true)
    gui.leftBar.latency:SetVertexColor(0.85, 0.25, 0.25, 0.85)
    gui.leftBar.latency:SetPoint("TOPLEFT", gui.leftBar.bg, "TOPLEFT", 3, 0)
    gui.leftBar.latency:SetPoint("BOTTOMLEFT", gui.leftBar.bg, "BOTTOMLEFT", 3, 0)
    gui.leftBar.latency:Hide()

    gui.rightBar.latency = latencyFrm:CreateTexture(nil, "OVERLAY")
    gui.rightBar.latency:SetTexture(MEDIA.TEXTURE)
    gui.rightBar.latency:SetAtlas(MEDIA.BAR_ATLAS)
    gui.rightBar.latency:SetDesaturated(true)
    gui.rightBar.latency:SetVertexColor(0.85, 0.25, 0.25, 0.85)
    gui.rightBar.latency:SetPoint("TOPRIGHT", gui.rightBar.bg, "TOPRIGHT", -3, 0)
    gui.rightBar.latency:SetPoint("BOTTOMRIGHT", gui.rightBar.bg, "BOTTOMRIGHT", -3, 0)
    gui.rightBar.latency:Hide()

    gui.spellName = gui.frame:CreateFontString(nil,
        "OVERLAY",
        "GameFontNormal")
    gui.spellName:SetPoint("TOP", gui.iconFrame, "BOTTOM", 0, -2)
    gui.spellName:SetJustifyH("CENTER")
    gui.spellName:SetTextColor(1, 1, 1, 1)
    addon.Utils.apply_font_shadow(gui.spellName)

    gui.castTimer = gui.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gui.castTimer:SetPoint("BOTTOM", gui.iconFrame, "TOP", 0, 1)
    gui.castTimer:SetJustifyH("CENTER")
    gui.castTimer:SetTextColor(1, 0.82, 0, 1)
    addon.Utils.apply_font_shadow(gui.castTimer)

    gui.frame:SetScript("OnUpdate", function()
        if not castBar.castEndTime then return end

        local remaining
        lastTimerText, remaining = CastUtil.UpdateTimer(gui.castTimer, castBar.castEndTime, lastTimerText)

        local total = castBar.castDuration or 1
        local value = castBar.isChannel and (remaining / total) or ((total - remaining) / total)
        gui.leftBar.bar:SetWidth(value * gui.barFullWidth)
        gui.rightBar.bar:SetWidth(value * gui.barFullWidth)
    end)

    self:Refresh()
end

--#endregion

--#region ── Cast lifecycle ────────────────────────────────────────────────────────────
function castBar:StartCastInternal(isChannel)
    local name, texture, startTimeMS, endTimeMS = CastUtil.GetCastInfo(isChannel)
    if not name or not startTimeMS or not endTimeMS then return end

    local startTime = startTimeMS / 1000
    local endTime = endTimeMS / 1000
    local duration = endTime - startTime
    if duration <= 0 then return end

    self.castEndTime = endTime
    self.castDuration = duration
    self.isChannel = isChannel

    local c = cfg()
    local r, g, b, a = CastUtil.ResolveColor(c, isChannel)
    gui.leftBar.tex:SetVertexColor(r, g, b, a)
    gui.rightBar.tex:SetVertexColor(r, g, b, a)
    gui.leftBar.spark:SetVertexColor(r, g, b, a)
    gui.rightBar.spark:SetVertexColor(r, g, b, a)

    if c.showLatency then
        local latency = CastUtil.GetLatency()
        local latencyWidth = math.min((latency / duration) * gui.barFullWidth, gui.barFullWidth)
        gui.leftBar.latency:SetWidth(latencyWidth)
        gui.rightBar.latency:SetWidth(latencyWidth)
        gui.leftBar.latency:Show()
        gui.rightBar.latency:Show()
    end

    local elapsed = GetTime() - startTime
    local value = isChannel and (1 - elapsed / duration) or (elapsed / duration)
    gui.leftBar.bar:SetWidth(value * gui.barFullWidth)
    gui.rightBar.bar:SetWidth(value * gui.barFullWidth)

    gui.icon:SetTexture(texture)
    local fw, fh = gui.iconFrame:GetWidth(), gui.iconFrame:GetHeight()
    if fw >= fh then
        local v = (1 - fh / fw) / 2
        gui.icon:SetTexCoord(0, 1, v, 1 - v)
    else
        local u = (1 - fw / fh) / 2
        gui.icon:SetTexCoord(u, 1 - u, 0, 1)
    end
    gui.spellName:SetText(name)

    gui.frame:ClearAllPoints()
    gui.frame:SetPoint("CENTER", UIParent, "CENTER", c.xPos, c.yPos)
    gui.frame:Show()
end

function castBar:StopCastInternal()
    self.castEndTime = nil
    self.castDuration = nil
    self.isChannel = nil
    self.currentCastGUID = nil
    gui.leftBar.bar:SetWidth(0)
    gui.rightBar.bar:SetWidth(0)
    gui.leftBar.latency:Hide()
    gui.rightBar.latency:Hide()
    lastTimerText = ""
    if not self.preview then
        gui.frame:Hide()
    end
end

function castBar:UpdateCastInternal(isChannel)
    local name, _, startTimeMS, endTimeMS = CastUtil.GetCastInfo(isChannel)
    if not name or not startTimeMS or not endTimeMS then
        self:StopCastInternal()
        return
    end
    local startTime = startTimeMS / 1000
    local endTime = endTimeMS / 1000
    self.castEndTime = endTime
    self.castDuration = endTime - startTime
end

--#endregion

--#region ── Public API — called by CastRing to coordinate display ─────────────────────

function castBar:SetCastRingMode(enabled)
    self.castRingMode = enabled
    if not enabled then
        self:HideFallback()
    end
end

function castBar:ShowFallback(isChannel)
    self:StartCastInternal(isChannel)
end

function castBar:HideFallback()
    if cfg().alwaysShow then return end
    self.castEndTime = nil
    self.castDuration = nil
    self.isChannel = nil
    gui.leftBar.bar:SetWidth(0)
    gui.rightBar.bar:SetWidth(0)
    gui.leftBar.latency:Hide()
    gui.rightBar.latency:Hide()
    lastTimerText = ""
    if not self.preview then
        gui.frame:Hide()
    end
end

function castBar:TogglePreview()
    if self.preview then
        self.preview = false
        if not self.castEndTime then
            gui.frame:Hide()
        end
    else
        self.preview = true
        local cc = cfg().castColor
        gui.leftBar.tex:SetVertexColor(cc.r, cc.g, cc.b, cc.a)
        gui.rightBar.tex:SetVertexColor(cc.r, cc.g, cc.b, cc.a)
        gui.leftBar.spark:SetVertexColor(cc.r, cc.g, cc.b, cc.a)
        gui.rightBar.spark:SetVertexColor(cc.r, cc.g, cc.b, cc.a)
        gui.leftBar.bar:SetWidth(0.6 * gui.barFullWidth)
        gui.rightBar.bar:SetWidth(0.6 * gui.barFullWidth)
        gui.frame:ClearAllPoints()
        gui.frame:SetPoint("CENTER", UIParent, "CENTER", cfg().xPos, cfg().yPos)
        gui.frame:Show()
    end
end

--#endregion

--#region ── Event handlers ────────────────────────────────────────────────────────────

function castBar:OnCastStart(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    self.currentCastGUID = castGUID
    self:StartCastInternal(false)
end

function castBar:OnCastStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCastInternal()
end

function castBar:OnCastDelayed(_, unit)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    self:UpdateCastInternal(false)
end

function castBar:OnChannelStart(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    self.currentCastGUID = castGUID
    self:StartCastInternal(true)
end

function castBar:OnChannelStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCastInternal()
end

function castBar:OnChannelUpdate(_, unit)
    if unit ~= "player" then return end
    if self.castRingMode and not cfg().alwaysShow then return end
    self:UpdateCastInternal(true)
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────────────
function castBar:OnEnable()
    self:CreateUI()

    CastUtil.RegisterCastEvents(self)

    if not self.castRingMode or cfg().alwaysShow then
        if UnitCastingInfo("player") then
            self:StartCastInternal(false)
        elseif UnitChannelInfo("player") then
            self:StartCastInternal(true)
        end
    end
end

function castBar:OnDisable()
    self.preview = false
    self.castRingMode = false
    self:UnregisterAllEvents()
    if gui.frame then
        gui.frame:SetScript("OnUpdate", nil)
        gui.frame:Hide()
    end
end

--#endregion

castBar:Enable()
