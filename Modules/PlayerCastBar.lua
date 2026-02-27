local addonName = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class PlayerCastBar: AceModule
---@field preview boolean
---@field castRingMode boolean
local castBar = addon:NewModule('PlayerCastBar', 'AceEvent-3.0')
---@cast castBar +AceEvent-3.0

---@type CastUtil
local CastUtil = addon.CastUtil

local MEDIA = {
    BAR         = 'Interface\\widgets\\CosmicEnergyBar',
    BAR_ATLAS   = {
        BG_CENTER     = 'cosmic-bar-bgcenter',
        BG_LEFT       = 'cosmic-bar-bgleft',
        BG_RIGHT      = 'cosmic-bar-bgright',
        BORDER_CENTER = 'cosmic-bar-bordercenter',
        BORDER_LEFT   = 'cosmic-bar-borderleft',
        BORDER_RIGHT  = 'cosmic-bar-borderright',
    },
    FILL_LEFT   = "Interface\\AddOns\\ConsoleTools\\Media\\BarBgLeft",
    FILL_RIGHT  = "Interface\\AddOns\\ConsoleTools\\Media\\BarBgRight",
    SPARK_TEX   = "interface\\questframe\\objectivewidget",
    SPARK_ATLAS = "objectivewidget-bar-spark-neutral",
    ICON_MASK   = "Interface\\AddOns\\ConsoleTools\\Media\\IconMask",
    ICON_BORDER = "Interface\\AddOns\\ConsoleTools\\Media\\IconBorder",
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
---@field endCap Texture
---@field bar Texture
---@field tex Texture
---@field border Texture
---@field borderEndcap Texture
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
        bg:SetPoint("LEFT", parentFrame, "LEFT", h / 2, 0)
        bg:SetPoint("RIGHT", iconFrm, "RIGHT")
    else
        bg:SetPoint("LEFT", iconFrm, "LEFT")
        bg:SetPoint("RIGHT", parentFrame, "RIGHT", -h / 2, 0)
    end
    bg:SetHeight(h)
    bg:SetTexture(MEDIA.BAR)
    bg:SetAtlas(MEDIA.BAR_ATLAS.BG_CENTER)

    local endCap = parentFrame:CreateTexture(nil, "BACKGROUND")
    endCap:SetTexture(MEDIA.BAR)

    if isLeft then
        endCap:SetPoint("RIGHT", bg, "LEFT")
        endCap:SetAtlas(MEDIA.BAR_ATLAS.BG_LEFT)
    else
        endCap:SetPoint("LEFT", bg, "RIGHT")
        endCap:SetAtlas(MEDIA.BAR_ATLAS.BG_RIGHT)
    end

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
        fillTex:SetPoint("LEFT", endCap, "LEFT")
        fillTex:SetTexture(MEDIA.FILL_LEFT)
    else
        fillTex:SetPoint("LEFT", iconFrm, "RIGHT")
        fillTex:SetPoint("RIGHT", endCap, "RIGHT")
        fillTex:SetTexture(MEDIA.FILL_RIGHT)
    end
    fillTex:SetHeight(h)

    local borderFrm = CreateFrame("Frame", nil, parentFrame)
    borderFrm:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local borderCenter = borderFrm:CreateTexture(nil, "OVERLAY")
    if isLeft then
        borderCenter:SetPoint("RIGHT", iconFrm, "RIGHT")
        borderCenter:SetPoint("LEFT", parentFrame, "LEFT", h / 2, 0)
    else
        borderCenter:SetPoint("LEFT", iconFrm, "LEFT")
        borderCenter:SetPoint("RIGHT", parentFrame, "RIGHT", -h / 2, 0)
    end
    borderCenter:SetHeight(h)
    borderCenter:SetTexture(MEDIA.BAR)
    borderCenter:SetAtlas(MEDIA.BAR_ATLAS.BORDER_CENTER)

    local borderEndcap = borderFrm:CreateTexture(nil, "OVERLAY")
    borderEndcap:SetTexture(MEDIA.BAR)

    if isLeft then
        borderEndcap:SetPoint("RIGHT", borderCenter, "LEFT")
        borderEndcap:SetAtlas(MEDIA.BAR_ATLAS.BORDER_LEFT)
    else
        borderEndcap:SetPoint("LEFT", borderCenter, "RIGHT")
        borderEndcap:SetAtlas(MEDIA.BAR_ATLAS.BORDER_RIGHT)
    end

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
        endCap = endCap,
        bar = fill,
        tex = fillTex,
        border = borderCenter,
        borderEndcap = borderEndcap,
        spark =
            spark
    }
end

local function RefreshBarSide(cap, isLeft, t)
    t.endCap:SetSize(cap + 2, cap)
    t.borderEndcap:SetSize(cap + 6, cap)

    t.bg:ClearAllPoints()
    t.border:ClearAllPoints()
    if isLeft then
        t.bg:SetPoint("LEFT", gui.frame, "LEFT", cap / 2, 0)
        t.bg:SetPoint("RIGHT", gui.iconFrame, "RIGHT")
        t.border:SetPoint("LEFT", gui.frame, "LEFT", cap / 2, 0)
        t.border:SetPoint("RIGHT", gui.iconFrame, "RIGHT")
    else
        t.bg:SetPoint("LEFT", gui.iconFrame, "LEFT")
        t.bg:SetPoint("RIGHT", gui.frame, "RIGHT", -cap / 2, 0)
        t.border:SetPoint("LEFT", gui.iconFrame, "LEFT")
        t.border:SetPoint("RIGHT", gui.frame, "RIGHT", -cap / 2, 0)
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
        gui.iconFrame:SetSize(c.height * 3, c.height * 2)
        gui.barFullWidth = (c.width - c.height * 2) / 2 + 2
    end

    if gui.leftBar then
        local cap = c.height
        RefreshBarSide(cap, true, gui.leftBar)
        RefreshBarSide(cap, false, gui.rightBar)
        gui.leftBar.spark:SetShown(c.showSpark)
        gui.rightBar.spark:SetShown(c.showSpark)
        gui.leftBar.latency:SetHeight(cap)
        gui.rightBar.latency:SetHeight(cap)
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
    gui.leftBar.latency:SetColorTexture(0.85, 0.25, 0.25, 0.6)
    gui.leftBar.latency:SetPoint("LEFT", gui.leftBar.endCap, "LEFT")
    gui.leftBar.latency:Hide()

    gui.rightBar.latency = latencyFrm:CreateTexture(nil, "OVERLAY")
    gui.rightBar.latency:SetColorTexture(0.85, 0.25, 0.25, 0.6)
    gui.rightBar.latency:SetPoint("RIGHT", gui.rightBar.endCap, "RIGHT")
    gui.rightBar.latency:Hide()

    gui.spellName = gui.frame:CreateFontString(nil,
        "OVERLAY",
        "GameFontNormal")
    gui.spellName:SetPoint("TOP", gui.iconFrame, "BOTTOM", 0, -2)
    gui.spellName:SetJustifyH("CENTER")
    gui.spellName:SetTextColor(1, 1, 1, 1)

    gui.castTimer = gui.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gui.castTimer:SetPoint("BOTTOM", gui.iconFrame, "TOP", 0, 1)
    gui.castTimer:SetJustifyH("CENTER")
    gui.castTimer:SetTextColor(1, 0.82, 0, 1)

    gui.frame:SetScript("OnUpdate", function()
        if not castBar.castEndTime then return end
        local remaining = castBar.castEndTime - GetTime()

        if remaining < 0 then remaining = 0 end

        local newTimerText = string.format("%.1f", remaining)
        if newTimerText ~= lastTimerText then
            gui.castTimer:SetText(newTimerText)
            lastTimerText = newTimerText
        end
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
    local endTime   = endTimeMS / 1000
    local duration  = endTime - startTime
    if duration <= 0 then return end

    self.castEndTime  = endTime
    self.castDuration = duration
    self.isChannel    = isChannel

    local c           = cfg()
    local r, g, b, a  = CastUtil.ResolveColor(c, isChannel)
    gui.leftBar.tex:SetVertexColor(r, g, b, a)
    gui.rightBar.tex:SetVertexColor(r, g, b, a)
    gui.leftBar.spark:SetVertexColor(r, g, b, a)
    gui.rightBar.spark:SetVertexColor(r, g, b, a)

    if c.showLatency then
        local latency      = select(4, GetNetStats()) / 1000
        local latencyWidth = math.min((latency / duration) * gui.barFullWidth, gui.barFullWidth)
        gui.leftBar.latency:SetWidth(latencyWidth)
        gui.rightBar.latency:SetWidth(latencyWidth)
        gui.leftBar.latency:Show()
        gui.rightBar.latency:Show()
    end

    local elapsed = GetTime() - startTime
    local value   = isChannel and (1 - elapsed / duration) or (elapsed / duration)
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
    self.castEndTime     = nil
    self.castDuration    = nil
    self.isChannel       = nil
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
    local startTime   = startTimeMS / 1000
    local endTime     = endTimeMS / 1000
    self.castEndTime  = endTime
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
    self.castEndTime  = nil
    self.castDuration = nil
    self.isChannel    = nil
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
    if self.castRingMode then return end
    self.currentCastGUID = castGUID
    self:StartCastInternal(false)
end

function castBar:OnCastStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCastInternal()
end

function castBar:OnCastDelayed(_, unit)
    if unit ~= "player" then return end
    if self.castRingMode then return end
    self:UpdateCastInternal(false)
end

function castBar:OnChannelStart(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode then return end
    self.currentCastGUID = castGUID
    self:StartCastInternal(true)
end

function castBar:OnChannelStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if self.castRingMode then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCastInternal()
end

function castBar:OnChannelUpdate(_, unit)
    if unit ~= "player" then return end
    if self.castRingMode then return end
    self:UpdateCastInternal(true)
end

--#endregion

--#region ── Module lifecycle ──────────────────────────────────────────────────────────
function castBar:OnEnable()
    self:CreateUI()

    CastUtil.RegisterCastEvents(self)

    if not self.castRingMode then
        if UnitCastingInfo("player") then
            self:StartCastInternal(false)
        elseif UnitChannelInfo("player") then
            self:StartCastInternal(true)
        end
    end
end

function castBar:OnDisable()
    self.preview      = false
    self.castRingMode = false
    self:UnregisterAllEvents()
    if gui.frame then
        gui.frame:SetScript("OnUpdate", nil)
        gui.frame:Hide()
    end
end

--#endregion

--#region ── Options ────────────────────────────────────────────────────────────────────

function castBar:GetDefaults()
    return {
        playerCastBar = {
            enabled       = true,
            width         = 250,
            height        = 24,
            xPos          = 0,
            yPos          = -200,
            locked        = false,
            showIcon      = true,
            showSpellName = true,
            showTimer     = true,
            showSpark     = true,
            showLatency   = true,
            useClassColor = false,
            castColor     = { r = 0.8, g = 0.4, b = 0.0, a = 1.0 },
            channelColor  = { r = 0.0, g = 0.6, b = 1.0, a = 1.0 },
        },
    }
end

function castBar:GetOptions()
    return 'playerCastBar', {
        name  = 'Player Cast Bar',
        type  = 'group',
        order = 2,
        args  = {
            description = {
                name  =
                'A standard horizontal cast bar for your character. Also acts as fallback when Cast Ring is set to attach to a nameplate but no target is present.',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enabled',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.playerCastBar.enabled end,
                set   = function(_, value)
                    addon.db.profile.playerCastBar.enabled = value
                    if value then castBar:Enable() else castBar:Disable() end
                end,
            },
            general = {
                name   = 'General',
                type   = 'group',
                order  = 3,
                inline = true,
                args   = {
                    width = {
                        name  = 'Width',
                        desc  = 'Width of the cast bar in pixels.',
                        type  = 'range',
                        order = 1,
                        min   = 80,
                        max   = 600,
                        step  = 2,
                        get   = function() return addon.db.profile.playerCastBar.width end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.width = value
                            castBar:Refresh()
                        end,
                    },
                    height = {
                        name  = 'Height',
                        desc  = 'Height of the cast bar in pixels.',
                        type  = 'range',
                        order = 2,
                        min   = 10,
                        max   = 60,
                        step  = 2,
                        get   = function() return addon.db.profile.playerCastBar.height end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.height = value
                            castBar:Refresh()
                        end,
                    },
                    locked = {
                        name  = 'Lock Position',
                        desc  = 'Prevent the bar from being dragged.',
                        type  = 'toggle',
                        order = 3,
                        get   = function() return addon.db.profile.playerCastBar.locked end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.locked = value
                            castBar:Refresh()
                        end,
                    },
                    preview = {
                        name  = function()
                            return castBar.preview and 'Hide Preview' or 'Show Preview'
                        end,
                        desc  = 'Show or hide the cast bar so you can drag it into position.',
                        type  = 'execute',
                        order = 4,
                        func  = function() castBar:TogglePreview() end,
                    },
                },
            },
            display = {
                name   = 'Display',
                type   = 'group',
                order  = 4,
                inline = true,
                args   = {
                    showIcon = {
                        name  = 'Show Spell Icon',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.playerCastBar.showIcon end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.showIcon = value
                            castBar:Refresh()
                        end,
                    },
                    showSpellName = {
                        name  = 'Show Spell Name',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.playerCastBar.showSpellName end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.showSpellName = value
                            castBar:Refresh()
                        end,
                    },
                    showTimer = {
                        name  = 'Show Timer',
                        type  = 'toggle',
                        order = 3,
                        get   = function() return addon.db.profile.playerCastBar.showTimer end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.showTimer = value
                            castBar:Refresh()
                        end,
                    },
                    showSpark = {
                        name  = 'Show Spark',
                        type  = 'toggle',
                        order = 4,
                        get   = function() return addon.db.profile.playerCastBar.showSpark end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.showSpark = value
                            castBar:Refresh()
                        end,
                    },
                    showLatency = {
                        name  = 'Show Latency',
                        desc  = 'Show a red zone at the end of the bar indicating your network latency window.',
                        type  = 'toggle',
                        order = 5,
                        get   = function() return addon.db.profile.playerCastBar.showLatency end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.showLatency = value
                            castBar:Refresh()
                        end,
                    },
                },
            },
            colors = {
                name   = 'Colors',
                type   = 'group',
                order  = 5,
                inline = true,
                args   = {
                    useClassColor = {
                        name  = 'Use Class Color',
                        desc  = 'Color the bar with your class color instead of the custom cast/channel colors.',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.playerCastBar.useClassColor end,
                        set   = function(_, value)
                            addon.db.profile.playerCastBar.useClassColor = value
                        end,
                    },
                    castColor = {
                        name     = 'Cast Color',
                        desc     = 'Fill color for regular casts.',
                        type     = 'color',
                        order    = 2,
                        hasAlpha = false,
                        disabled = function() return addon.db.profile.playerCastBar.useClassColor end,
                        get      = function()
                            local c = addon.db.profile.playerCastBar.castColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            local c = addon.db.profile.playerCastBar.castColor
                            c.r, c.g, c.b = r, g, b
                        end,
                    },
                    channelColor = {
                        name     = 'Channel Color',
                        desc     = 'Fill color for channeled spells.',
                        type     = 'color',
                        order    = 3,
                        hasAlpha = false,
                        disabled = function() return addon.db.profile.playerCastBar.useClassColor end,
                        get      = function()
                            local c = addon.db.profile.playerCastBar.channelColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            local c = addon.db.profile.playerCastBar.channelColor
                            c.r, c.g, c.b = r, g, b
                        end,
                    },
                },
            },
        },
    }
end

--#endregion

castBar:Enable()
