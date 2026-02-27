local addonName     = ...

---@class ConsoleTools: AceAddon
local addon         = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class CastRing: AceModule
---@field preview boolean
local castRing      = addon:NewModule('CastRing', 'AceEvent-3.0')
---@cast castRing +AceEvent-3.0

local CastUtil      = addon.CastUtil

local MEDIA         = {
    RING         = "Interface\\AddOns\\ConsoleTools\\Media\\CastRingSM.blp",
    BORDER       = "interface/azerite/azerite",
    BORDER_ATLAS = "Azerite-Trait-Ring-Open",
    ICON_MASK    = "Interface\\CharacterFrame\\TempPortraitAlphaMask",
}

---@class CastRingGUI
---@field frame Frame
---@field ringTex Texture
---@field borderRingTex Texture
---@field borderInnerRingTex Texture
---@field cooldown Cooldown
---@field latencyCD Cooldown
---@field sparkTex Texture
---@field iconMask MaskTexture
---@field icon Texture
---@field spellName FontString
---@field castTimer FontString
local gui           = {}
local lastTimerText = ""

local HOLE_RATIO    = 0.72 -- fraction of ring size that is the inner hole (matches Ring.tga)

local function cfg()
    return addon.db.profile.castRing
end

function castRing:ApplyCastBarHide()
    CastUtil.ConfigureBlizzardCastBar(cfg().hideBlizzardCastBar)
end

-- ── Refresh ───────────────────────────────────────────────────────────────────
function castRing:Refresh()
    if not gui.frame then return end
    local c = cfg()

    gui.frame:SetFrameStrata(c.frameStrata)
    gui.frame:SetSize(c.size, c.size)
    gui.frame:ClearAllPoints()
    gui.frame:SetPoint("CENTER", UIParent, "CENTER", c.xPos, c.yPos)

    gui.frame:SetMovable(not c.locked)
    gui.frame:EnableMouse(not c.locked)

    local holeSize = math.floor(c.size * HOLE_RATIO)
    gui.iconMask:SetSize(holeSize, holeSize)
    gui.icon:SetSize(holeSize, holeSize)

    local cc = c.castColor
    gui.ringTex:SetVertexColor(cc.r, cc.g, cc.b, cc.a)

    gui.borderRingTex:SetShown(c.showBorder)
    gui.borderInnerRingTex:SetShown(c.showBorder)
    if c.showBorder then
        local bc = c.borderColor
        gui.borderRingTex:SetVertexColor(bc.r, bc.g, bc.b, bc.a)
        gui.borderRingTex:SetSize(c.size + c.borderWidth * 2, c.size + c.borderWidth * 2)
        gui.borderInnerRingTex:SetVertexColor(bc.r, bc.g, bc.b, bc.a)
        gui.borderInnerRingTex:SetSize(c.size - c.borderWidth * 2, c.size - c.borderWidth * 2)
    end

    gui.icon:SetShown(c.showIcon)
    gui.spellName:SetShown(c.showSpellName)
    gui.castTimer:SetShown(c.showTimer)
end

-- ── UI Construction ───────────────────────────────────────────────────────────
function castRing:CreateUI()
    gui.frame = CreateFrame("Frame", "CastRingFrame", UIParent)
    gui.frame:SetFrameStrata(cfg().frameStrata)
    gui.frame:SetFrameLevel(10)
    gui.frame:Hide()

    CastUtil.ApplyDragToMove(gui.frame, cfg)

    gui.borderRingTex = gui.frame:CreateTexture(nil, "BACKGROUND")
    gui.borderRingTex:SetTexture(MEDIA.BORDER)
    gui.borderRingTex:SetAtlas(MEDIA.BORDER_ATLAS)
    gui.borderRingTex:SetPoint("CENTER", gui.frame, "CENTER")

    gui.borderInnerRingTex = gui.frame:CreateTexture(nil, "BACKGROUND")
    gui.borderInnerRingTex:SetTexture(MEDIA.BORDER)
    gui.borderInnerRingTex:SetAtlas(MEDIA.BORDER_ATLAS)
    gui.borderInnerRingTex:SetPoint("CENTER", gui.frame, "CENTER")

    gui.ringTex = gui.frame:CreateTexture(nil, "ARTWORK")
    gui.ringTex:SetAllPoints()
    gui.ringTex:SetTexture(MEDIA.RING)

    gui.cooldown = CreateFrame("Cooldown", nil, gui.frame, "CooldownFrameTemplate")
    gui.cooldown:SetAllPoints()
    gui.cooldown:SetFrameLevel(gui.frame:GetFrameLevel() + 1)
    gui.cooldown:SetDrawBling(false)
    gui.cooldown:SetDrawEdge(false)
    gui.cooldown:SetHideCountdownNumbers(true)
    gui.cooldown:SetSwipeTexture(MEDIA.RING, 0.5, 0.5, 0.5, 1)

    gui.latencyCD = CreateFrame("Cooldown", nil, gui.frame, "CooldownFrameTemplate")
    gui.latencyCD:SetAllPoints()
    gui.latencyCD:SetFrameLevel(gui.frame:GetFrameLevel() + 2)
    gui.latencyCD:SetDrawBling(false)
    gui.latencyCD:SetDrawEdge(false)
    gui.latencyCD:SetHideCountdownNumbers(true)
    gui.latencyCD:SetSwipeTexture(MEDIA.RING, 0, 0, 0, 1)
    gui.latencyCD:SetSwipeColor(.85, .25, .25, 1)

    local sparkFrame = CreateFrame("Frame", nil, gui.frame)
    sparkFrame:SetAllPoints()
    sparkFrame:SetFrameLevel(gui.frame:GetFrameLevel() + 3)
    gui.sparkTex = sparkFrame:CreateTexture(nil, "OVERLAY")
    gui.sparkTex:SetColorTexture(1, 0.9, 0.6, 1)
    gui.sparkTex:SetBlendMode("ADD")
    gui.sparkTex:Hide()

    local iconFrame = CreateFrame("Frame", nil, gui.frame)
    iconFrame:SetAllPoints()
    iconFrame:SetFrameLevel(gui.frame:GetFrameLevel() - 1)

    gui.iconMask = iconFrame:CreateMaskTexture()
    gui.iconMask:SetTexture(MEDIA.ICON_MASK)
    gui.iconMask:SetPoint("CENTER")

    gui.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    gui.icon:SetPoint("CENTER")
    gui.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    gui.icon:AddMaskTexture(gui.iconMask)

    gui.spellName = gui.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gui.spellName:SetPoint("TOP", gui.frame, "BOTTOM", 0, -4)
    gui.spellName:SetTextColor(1, 1, 1, 1)

    gui.castTimer = gui.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gui.castTimer:SetPoint("TOP", gui.spellName, "BOTTOM", 0, -2)
    gui.castTimer:SetTextColor(1, 0.82, 0, 1)

    gui.frame:SetScript("OnUpdate", function()
        if not castRing.castEndTime then return end

        local remaining
        lastTimerText, remaining = CastUtil.UpdateTimer(gui.castTimer, castRing.castEndTime, lastTimerText)

        if cfg().showSpark and castRing.castDuration then
            local c        = cfg()
            local progress = 1 - remaining / castRing.castDuration
            local angle    = progress * 2 * math.pi -- clockwise from 12 o'clock
            local outerR   = c.size / 2
            local innerR   = outerR * HOLE_RATIO
            local midR     = (outerR + innerR) / 2
            local bandH    = outerR - innerR
            gui.sparkTex:SetSize(bandH * 0.3, bandH * .65)
            gui.sparkTex:ClearAllPoints()
            gui.sparkTex:SetPoint("CENTER", gui.frame, "CENTER",
                midR * math.sin(angle),
                midR * math.cos(angle))
            gui.sparkTex:SetRotation(-angle)
            gui.sparkTex:SetShown(true)
        else
            gui.sparkTex:Hide()
        end
    end)

    self:Refresh()
end

local function MoveToNameplate()
    ---@diagnostic disable-next-line: param-type-mismatch
    local np = C_NamePlate.GetNamePlateForUnit("target")
    if not np then return end
    local c = cfg()
    gui.frame:ClearAllPoints()
    gui.frame:SetPoint(c.nameplateAnchor, np, c.nameplateRelative, c.nameplateXOffset, c.nameplateYOffset)
end

-- ── Cast lifecycle ────────────────────────────────────────────────────────────
function castRing:StartCast(isChannel)
    local name, texture, startTimeMS, endTimeMS = CastUtil.GetCastInfo(isChannel)
    if not name or not startTimeMS or not endTimeMS then return end

    local startTime = startTimeMS / 1000
    local endTime   = endTimeMS / 1000
    local duration  = endTime - startTime
    if duration <= 0 then return end

    self.castEndTime  = endTime
    self.castDuration = duration
    self.isChannel    = isChannel

    gui.cooldown:SetReverse(isChannel)

    local latency  = CastUtil.GetLatency()
    local K        = 100
    local totalDur = duration * K
    gui.latencyCD:SetReverse(isChannel)
    gui.latencyCD:SetCooldown(startTime - totalDur * (1 - latency / duration), totalDur)

    gui.ringTex:SetVertexColor(CastUtil.ResolveColor(cfg(), isChannel))

    gui.cooldown:SetCooldown(startTime, duration)
    gui.icon:SetTexture(texture)
    gui.spellName:SetText(name)
    gui.frame:Show()

    if cfg().attachToNameplate then
        ---@diagnostic disable-next-line: param-type-mismatch
        local np = C_NamePlate.GetNamePlateForUnit("target")
        if np then
            local pcb = addon:GetModule('PlayerCastBar', true)
            ---@diagnostic disable-next-line: undefined-field
            if pcb then pcb:HideFallback() end
            MoveToNameplate()
        else
            gui.frame:Hide()
            local pcb = addon:GetModule('PlayerCastBar', true)
            ---@diagnostic disable-next-line: undefined-field
            if pcb then pcb:ShowFallback(isChannel) end
        end
    end
end

function castRing:StopCast()
    self.castEndTime     = nil
    self.castDuration    = nil
    self.currentCastGUID = nil
    self.isChannel       = nil
    gui.cooldown:SetCooldown(0, 0)
    gui.latencyCD:SetCooldown(0, 0)
    gui.sparkTex:Hide()
    lastTimerText = ""
    if not self.preview then
        gui.frame:Hide()
    end

    local pcb = addon:GetModule('PlayerCastBar', true)
    ---@diagnostic disable-next-line: undefined-field
    if pcb then pcb:HideFallback() end
end

function castRing:TogglePreview()
    if self.preview then
        self.preview = false
        if not self.castEndTime then
            gui.frame:Hide()
        end
    else
        self.preview = true
        local cc = cfg().castColor
        gui.ringTex:SetVertexColor(cc.r, cc.g, cc.b, cc.a)
        gui.frame:Show()
        if cfg().attachToNameplate then
            MoveToNameplate()
        end
    end
end

function castRing:UpdateNameplateAnchor()
    if not gui.frame:IsShown() then return end
    if not cfg().attachToNameplate then return end
    MoveToNameplate()
end

function castRing:UpdateCast(isChannel)
    local name, _, startTimeMS, endTimeMS = CastUtil.GetCastInfo(isChannel)
    if not name or not startTimeMS or not endTimeMS then
        self:StopCast()
        return
    end
    local startTime  = startTimeMS / 1000
    local endTime    = endTimeMS / 1000
    self.castEndTime = endTime
    gui.cooldown:SetCooldown(startTime, endTime - startTime)
end

-- ── Event handlers ────────────────────────────────────────────────────────────
-- castGUID tracking prevents a stale STOP (from the previous cast) from
-- hiding the ring when the player quickly recasts before the old STOP fires.

function castRing:OnCastStart(_, unit, castGUID)
    if unit ~= "player" then return end
    self.currentCastGUID = castGUID
    self:StartCast(false)
end

function castRing:OnCastStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCast()
end

function castRing:OnCastDelayed(_, unit)
    if unit ~= "player" then return end
    self:UpdateCast(false)
end

function castRing:OnChannelStart(_, unit, castGUID)
    if unit ~= "player" then return end
    self.currentCastGUID = castGUID
    self:StartCast(true)
end

function castRing:OnChannelStop(_, unit, castGUID)
    if unit ~= "player" then return end
    if castGUID ~= self.currentCastGUID then return end
    self:StopCast()
end

function castRing:OnChannelUpdate(_, unit)
    if unit ~= "player" then return end
    self:UpdateCast(true)
end

function castRing:OnNamePlateAdded(_, unitToken)
    if not self.castEndTime then return end
    if not cfg().attachToNameplate then return end
    if not UnitIsUnit(unitToken, "target") then return end
    local pcb = addon:GetModule('PlayerCastBar', true)
    ---@diagnostic disable-next-line: undefined-field
    if pcb then pcb:HideFallback() end
    MoveToNameplate()
    gui.frame:Show()
end

function castRing:OnNamePlateRemoved(_, unitToken)
    if not self.castEndTime then return end
    if not cfg().attachToNameplate then return end
    if not UnitIsUnit(unitToken, "target") then return end
    gui.frame:ClearAllPoints()
    gui.frame:Hide()
    local pcb = addon:GetModule('PlayerCastBar', true)
    ---@diagnostic disable-next-line: undefined-field
    if pcb then pcb:ShowFallback(self.isChannel) end
end

function castRing:OnTargetChanged()
    if not cfg().attachToNameplate then return end
    if not self.castEndTime then return end
    ---@diagnostic disable-next-line: param-type-mismatch
    local np = C_NamePlate.GetNamePlateForUnit("target")
    if np then
        local pcb = addon:GetModule('PlayerCastBar', true)
        ---@diagnostic disable-next-line: undefined-field
        if pcb then pcb:HideFallback() end
        MoveToNameplate()
        gui.frame:Show()
    else
        gui.frame:ClearAllPoints()
        gui.frame:Hide()
        local pcb = addon:GetModule('PlayerCastBar', true)
        ---@diagnostic disable-next-line: undefined-field
        if pcb then pcb:ShowFallback(self.isChannel) end
    end
end

-- ── Module lifecycle ──────────────────────────────────────────────────────────
function castRing:OnEnable()
    self:CreateUI()

    CastUtil.RegisterCastEvents(self)
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "OnNamePlateAdded")
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", "OnNamePlateRemoved")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

    self:ApplyCastBarHide()

    if cfg().attachToNameplate then
        local pcb = addon:GetModule('PlayerCastBar', true)
        ---@diagnostic disable-next-line: undefined-field
        if pcb then pcb:SetCastRingMode(true) end
    end

    if UnitCastingInfo("player") then
        self:StartCast(false)
    elseif UnitChannelInfo("player") then
        self:StartCast(true)
    end
end

function castRing:OnDisable()
    self.preview   = false
    self.isChannel = nil
    hidingCastBar  = false
    self:UnregisterAllEvents()
    if gui.frame then
        gui.frame:SetScript("OnUpdate", nil)
        gui.frame:Hide()
    end
    local pcb = addon:GetModule('PlayerCastBar', true)
    ---@diagnostic disable-next-line: undefined-field
    if pcb then pcb:SetCastRingMode(false) end
end

-- ── Options ────────────────────────────────────────────────────────────────────

local ANCHOR_POINTS = {
    ['CENTER']      = 'Center',
    ['TOP']         = 'Top',
    ['BOTTOM']      = 'Bottom',
    ['LEFT']        = 'Left',
    ['RIGHT']       = 'Right',
    ['TOPLEFT']     = 'Top Left',
    ['TOPRIGHT']    = 'Top Right',
    ['BOTTOMLEFT']  = 'Bottom Left',
    ['BOTTOMRIGHT'] = 'Bottom Right',
}

function castRing:GetDefaults()
    return {
        castRing = {
            enabled             = true,
            size                = 128,
            xPos                = 0,
            yPos                = -150,
            locked              = false,
            hideBlizzardCastBar = false,
            showIcon            = true,
            showSpellName       = true,
            showTimer           = true,
            useClassColor       = false,
            attachToNameplate   = false,
            nameplateAnchor     = 'BOTTOM',
            nameplateRelative   = 'TOP',
            nameplateXOffset    = 0,
            nameplateYOffset    = 0,
            showSpark           = false,
            showBorder          = false,
            borderWidth         = 3,
            borderColor         = { r = 0.0, g = 0.0, b = 0.0, a = 1.0 },
            castColor           = { r = 0.8, g = 0.4, b = 0.0, a = 1.0 },
            channelColor        = { r = 0.0, g = 0.6, b = 1.0, a = 1.0 },
            frameStrata         = 'MEDIUM',
        },
    }
end

function castRing:GetOptions()
    return 'castRing', {
        name  = 'Cast Ring',
        type  = 'group',
        order = 1,
        args  = {
            description = {
                name  = 'A circular cast bar for your character. Drag it anywhere on screen (unless locked).',
                type  = 'description',
                order = 1,
            },
            enabled = {
                name  = 'Enabled',
                type  = 'toggle',
                order = 2,
                get   = function() return addon.db.profile.castRing.enabled end,
                set   = function(_, value)
                    addon.db.profile.castRing.enabled = value
                    if value then castRing:Enable() else castRing:Disable() end
                end,
            },
            general = {
                name   = 'General',
                type   = 'group',
                order  = 3,
                inline = true,
                args   = {
                    size = {
                        name  = 'Size',
                        desc  = 'Diameter of the ring in pixels.',
                        type  = 'range',
                        order = 1,
                        min   = 64,
                        max   = 256,
                        step  = 2,
                        get   = function() return addon.db.profile.castRing.size end,
                        set   = function(_, value)
                            addon.db.profile.castRing.size = value
                            castRing:Refresh()
                        end,
                    },
                    locked = {
                        name  = 'Lock Position',
                        desc  = 'Prevent the ring from being dragged.',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.castRing.locked end,
                        set   = function(_, value)
                            addon.db.profile.castRing.locked = value
                            castRing:Refresh()
                        end,
                    },
                    hideBlizzardCastBar = {
                        name  = 'Hide Blizzard Cast Bar',
                        desc  = 'Hide the default Blizzard casting bar.',
                        type  = 'toggle',
                        order = 3,
                        get   = function() return addon.db.profile.castRing.hideBlizzardCastBar end,
                        set   = function(_, value)
                            addon.db.profile.castRing.hideBlizzardCastBar = value
                            castRing:ApplyCastBarHide()
                        end,
                    },
                    frameStrata = {
                        name   = 'Frame Strata',
                        desc   = 'Rendering layer of the ring. Raise this if other frames overlap it.',
                        type   = 'select',
                        order  = 4,
                        values = {
                            BACKGROUND        = 'Background',
                            LOW               = 'Low',
                            MEDIUM            = 'Medium',
                            HIGH              = 'High',
                            DIALOG            = 'Dialog',
                            FULLSCREEN        = 'Fullscreen',
                            FULLSCREEN_DIALOG = 'Fullscreen Dialog',
                            TOOLTIP           = 'Tooltip',
                        },
                        get    = function() return addon.db.profile.castRing.frameStrata end,
                        set    = function(_, value)
                            addon.db.profile.castRing.frameStrata = value
                            castRing:Refresh()
                        end,
                    },
                    preview = {
                        name  = function()
                            return castRing.preview and 'Hide Preview' or 'Show Preview'
                        end,
                        desc  = 'Show or hide the cast ring so you can drag it into position.',
                        type  = 'execute',
                        order = 5,
                        func  = function() castRing:TogglePreview() end,
                    },
                },
            },
            nameplate = {
                name   = 'Nameplate',
                type   = 'group',
                order  = 4,
                inline = true,
                args   = {
                    attachToNameplate = {
                        name  = 'Attach to Nameplate',
                        desc  =
                        'Move the cast ring to your target\'s nameplate while casting. Falls back to the Player Cast Bar when no nameplate is present.',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.castRing.attachToNameplate end,
                        set   = function(_, value)
                            addon.db.profile.castRing.attachToNameplate = value
                            local pcb = addon:GetModule('PlayerCastBar', true)
                            ---@diagnostic disable-next-line: undefined-field
                            if pcb then pcb:SetCastRingMode(value) end
                        end,
                    },
                    nameplateAnchor = {
                        name     = 'Ring Anchor',
                        desc     = 'The point on the cast ring that attaches to the nameplate.',
                        type     = 'select',
                        order    = 2,
                        values   = ANCHOR_POINTS,
                        disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                        get      = function() return addon.db.profile.castRing.nameplateAnchor end,
                        set      = function(_, value)
                            addon.db.profile.castRing.nameplateAnchor = value
                            castRing:UpdateNameplateAnchor()
                        end,
                    },
                    nameplateRelative = {
                        name     = 'Nameplate Anchor',
                        desc     = 'The point on the nameplate that the ring attaches to.',
                        type     = 'select',
                        order    = 3,
                        values   = ANCHOR_POINTS,
                        disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                        get      = function() return addon.db.profile.castRing.nameplateRelative end,
                        set      = function(_, value)
                            addon.db.profile.castRing.nameplateRelative = value
                            castRing:UpdateNameplateAnchor()
                        end,
                    },
                    nameplateXOffset = {
                        name     = 'X Offset',
                        type     = 'range',
                        order    = 4,
                        min      = -200,
                        max      = 200,
                        step     = 1,
                        disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                        get      = function() return addon.db.profile.castRing.nameplateXOffset end,
                        set      = function(_, value)
                            addon.db.profile.castRing.nameplateXOffset = value
                            castRing:UpdateNameplateAnchor()
                        end,
                    },
                    nameplateYOffset = {
                        name     = 'Y Offset',
                        type     = 'range',
                        order    = 5,
                        min      = -200,
                        max      = 200,
                        step     = 1,
                        disabled = function() return not addon.db.profile.castRing.attachToNameplate end,
                        get      = function() return addon.db.profile.castRing.nameplateYOffset end,
                        set      = function(_, value)
                            addon.db.profile.castRing.nameplateYOffset = value
                            castRing:UpdateNameplateAnchor()
                        end,
                    },
                },
            },
            display = {
                name   = 'Display',
                type   = 'group',
                order  = 5,
                inline = true,
                args   = {
                    showIcon = {
                        name  = 'Show Spell Icon',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.castRing.showIcon end,
                        set   = function(_, value)
                            addon.db.profile.castRing.showIcon = value
                            castRing:Refresh()
                        end,
                    },
                    showSpellName = {
                        name  = 'Show Spell Name',
                        type  = 'toggle',
                        order = 2,
                        get   = function() return addon.db.profile.castRing.showSpellName end,
                        set   = function(_, value)
                            addon.db.profile.castRing.showSpellName = value
                            castRing:Refresh()
                        end,
                    },
                    showTimer = {
                        name  = 'Show Timer',
                        type  = 'toggle',
                        order = 3,
                        get   = function() return addon.db.profile.castRing.showTimer end,
                        set   = function(_, value)
                            addon.db.profile.castRing.showTimer = value
                            castRing:Refresh()
                        end,
                    },
                    showSpark = {
                        name  = 'Show Spark',
                        desc  = 'Show a bright edge at the leading edge of the cast sweep.',
                        type  = 'toggle',
                        order = 4,
                        get   = function() return addon.db.profile.castRing.showSpark end,
                        set   = function(_, value)
                            addon.db.profile.castRing.showSpark = value
                            castRing:Refresh()
                        end,
                    },
                },
            },
            colors = {
                name   = 'Colors',
                type   = 'group',
                order  = 6,
                inline = true,
                args   = {
                    useClassColor = {
                        name  = 'Use Class Color',
                        desc  = 'Color the ring with your class color instead of the custom cast/channel colors.',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.castRing.useClassColor end,
                        set   = function(_, value)
                            addon.db.profile.castRing.useClassColor = value
                        end,
                    },
                    castColor = {
                        name     = 'Cast Color',
                        desc     = 'Fill color for regular casts.',
                        type     = 'color',
                        order    = 2,
                        hasAlpha = false,
                        disabled = function() return addon.db.profile.castRing.useClassColor end,
                        get      = function()
                            local c = addon.db.profile.castRing.castColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            local c = addon.db.profile.castRing.castColor
                            c.r, c.g, c.b = r, g, b
                            castRing:Refresh()
                        end,
                    },
                    channelColor = {
                        name     = 'Channel Color',
                        desc     = 'Fill color for channeled spells.',
                        type     = 'color',
                        order    = 3,
                        hasAlpha = false,
                        disabled = function() return addon.db.profile.castRing.useClassColor end,
                        get      = function()
                            local c = addon.db.profile.castRing.channelColor
                            return c.r, c.g, c.b
                        end,
                        set      = function(_, r, g, b)
                            local c = addon.db.profile.castRing.channelColor
                            c.r, c.g, c.b = r, g, b
                        end,
                    },
                },
            },
            border = {
                name   = 'Border',
                type   = 'group',
                order  = 7,
                inline = true,
                args   = {
                    showBorder = {
                        name  = 'Show Border',
                        desc  = 'Show a colored outline around the outer edge of the ring.',
                        type  = 'toggle',
                        order = 1,
                        get   = function() return addon.db.profile.castRing.showBorder end,
                        set   = function(_, value)
                            addon.db.profile.castRing.showBorder = value
                            castRing:Refresh()
                        end,
                    },
                    borderWidth = {
                        name     = 'Border Width',
                        desc     = 'Thickness of the border in pixels.',
                        type     = 'range',
                        order    = 2,
                        min      = 1,
                        max      = 10,
                        step     = 1,
                        disabled = function() return not addon.db.profile.castRing.showBorder end,
                        get      = function() return addon.db.profile.castRing.borderWidth end,
                        set      = function(_, value)
                            addon.db.profile.castRing.borderWidth = value
                            castRing:Refresh()
                        end,
                    },
                    borderColor = {
                        name     = 'Border Color',
                        type     = 'color',
                        order    = 3,
                        hasAlpha = true,
                        disabled = function() return not addon.db.profile.castRing.showBorder end,
                        get      = function()
                            local c = addon.db.profile.castRing.borderColor
                            return c.r, c.g, c.b, c.a
                        end,
                        set      = function(_, r, g, b, a)
                            local c = addon.db.profile.castRing.borderColor
                            c.r, c.g, c.b, c.a = r, g, b, a
                            castRing:Refresh()
                        end,
                    },
                },
            },
        },
    }
end

castRing:Enable()
