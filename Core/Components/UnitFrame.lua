local addonName = ...

local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecret = addon.Utils.IsSecretValue

local BAR_BACKGROUND_ATLAS = 'UI-CastingBar-Background'
local BAR_BORDER_ATLAS = 'UI-CastingBar-Frame'
local BAR_FILL_ATLAS = 'ui-castingbar-tier4-empower'
local PORTRAIT_BORDER_ATLAS = 'UI-HUD-Minimap-Frame-Circle'
local RING_BORDER_ATLAS = 'gamepad-actionbar-circleslot-border-selected'
local BAR_FALLBACK_TEXTURE = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\basic_bar.tga'
local WHITE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'
local CLASS_TEXTURE = 'Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES'
local PORTRAIT_SIZE = 66
local AURA_SIZE = 19
local AURA_GAP = 3
local AURAS_PER_ROW = 4
local AURA_WIDTH = AURA_SIZE * AURAS_PER_ROW + AURA_GAP * (AURAS_PER_ROW - 1)
local BAR_LEFT = 68
local BAR_RIGHT_GAP = 9
local NAME_LEFT = 86
local BAR_WIDTH_REDUCTION = 100

local percentCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    percentCurve = C_CurveUtil.CreateCurve()
    percentCurve:AddPoint(0, 0)
    percentCurve:AddPoint(1, 100)
end

local function hasAtlas(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function makeAtlasBorder(parent, size, atlas)
    if not hasAtlas(atlas) then return nil end
    local border = parent:CreateTexture(nil, 'OVERLAY')
    border:SetAtlas(atlas)
    border:SetSize(size, size)
    return border
end

local function makeCircle(parent, size, color)
    local texture = parent:CreateTexture(nil, 'ARTWORK')
    texture:SetSize(size, size)
    texture:SetTexture(WHITE_TEXTURE)
    texture:SetVertexColor(unpack(color))
    local mask = parent:CreateMaskTexture()
    mask:SetAtlas('CircleMask')
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return texture
end

local function makeBar(parent, height, color)
    local group = CreateFrame('Frame', nil, parent)
    group:SetHeight(height)
    local background = group:CreateTexture(nil, 'BACKGROUND')
    background:SetAllPoints(group)
    local bar = CreateFrame('StatusBar', nil, group)
    bar:SetAllPoints(group)
    bar:SetStatusBarTexture(BAR_FALLBACK_TEXTURE)
    local fill = bar:GetStatusBarTexture()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_FILL_ATLAS) then
        fill:SetAtlas(BAR_FILL_ATLAS)
    end
    bar:SetStatusBarColor(unpack(color))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_BACKGROUND_ATLAS) then
        background:SetAtlas(BAR_BACKGROUND_ATLAS)
    else
        background:SetColorTexture(0.04, 0.05, 0.06, 0.9)
    end
    local borderFrame = CreateFrame('Frame', nil, group)
    borderFrame:SetAllPoints(group)
    borderFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
    local border = borderFrame:CreateTexture(nil, 'OVERLAY')
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_BORDER_ATLAS) then
        border:SetAtlas(BAR_BORDER_ATLAS)
        border:SetAllPoints(bar)
    else
        border:Hide()
        local edges = {}
        for i = 1, 4 do
            local edge = borderFrame:CreateTexture(nil, 'OVERLAY')
            edge:SetColorTexture(0, 0, 0, 0.9)
            edges[i] = edge
        end
        edges[1]:SetPoint('TOPLEFT', bar, 'TOPLEFT')
        edges[1]:SetPoint('TOPRIGHT', bar, 'TOPRIGHT')
        edges[1]:SetHeight(1)
        edges[2]:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT')
        edges[2]:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT')
        edges[2]:SetHeight(1)
        edges[3]:SetPoint('TOPLEFT', bar, 'TOPLEFT')
        edges[3]:SetPoint('BOTTOMLEFT', bar, 'BOTTOMLEFT')
        edges[3]:SetWidth(1)
        edges[4]:SetPoint('TOPRIGHT', bar, 'TOPRIGHT')
        edges[4]:SetPoint('BOTTOMRIGHT', bar, 'BOTTOMRIGHT')
        edges[4]:SetWidth(1)
    end

    local text = borderFrame:CreateFontString(nil, 'OVERLAY')
    text:SetFont(addon.Media.ResolveFont('Bebas Neue'), 15, 'OUTLINE')
    text:SetPoint('RIGHT', group, 'RIGHT', -5, 0)
    text:SetJustifyH('RIGHT')
    addon.Utils.apply_font_shadow(text)
    return bar, text, group, borderFrame
end

local function makeAuraIcon(parent)
    local frame = CreateFrame('Frame', nil, parent)
    frame:SetSize(AURA_SIZE, AURA_SIZE)
    frame:EnableMouse(false) -- clicks anywhere in the row continue to target its unit
    local texture = frame:CreateTexture(nil, 'ARTWORK')
    texture:SetAllPoints(frame)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = frame:CreateTexture(nil, 'OVERLAY')
    border:SetColorTexture(0, 0, 0, 1)
    border:SetPoint('TOPLEFT', frame, 'TOPLEFT', -1, 1)
    border:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 1, -1)
    border:SetDrawLayer('BACKGROUND')
    local count = frame:CreateFontString(nil, 'OVERLAY')
    count:SetFont(addon.Media.ResolveFont('Bebas Neue'), 12, 'OUTLINE')
    count:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 2, -2)
    addon.Utils.apply_font_shadow(count)
    frame.texture = texture
    frame.count = count
    frame:Hide()
    return frame
end

local function getAuras(unit, filter)
    if C_UnitAuras and C_UnitAuras.GetUnitAuras then
        return C_UnitAuras.GetUnitAuras(unit, filter, AURAS_PER_ROW) or {}
    end
    local auras = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, AURAS_PER_ROW do
            local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
            if not aura then break end
            auras[#auras + 1] = aura
        end
    elseif UnitAura then
        for i = 1, AURAS_PER_ROW do
            local name, icon, applications = UnitAura(unit, i, filter)
            if not name then break end
            auras[#auras + 1] = { icon = icon, applications = applications }
        end
    end
    return auras
end

local function percentText(label, unit, current, maximum, kind, powerType)
    if percentCurve and kind == 'health' and UnitHealthPercent then
        label:SetFormattedText('%d%%', UnitHealthPercent(unit, true, percentCurve))
    elseif percentCurve and kind == 'power' and UnitPowerPercent then
        label:SetFormattedText('%d%%', UnitPowerPercent(unit, powerType, false, percentCurve))
    elseif not isSecret(current) and not isSecret(maximum) and maximum > 0 then
        label:SetFormattedText('%d%%', math.floor(current / maximum * 100 + 0.5))
    else
        label:SetText('')
    end
end

local function showAuraRow(frame, icons, filters)
    local shown = 0
    local seen = {}
    for _, filter in ipairs(filters) do
        for _, aura in ipairs(getAuras(frame.unit, filter)) do
            if shown >= AURAS_PER_ROW then break end
            local id = aura.auraInstanceID
            local canDeduplicate = not isSecret(id) and id ~= nil
            if not canDeduplicate or not seen[id] then
                if canDeduplicate then seen[id] = true end
                shown = shown + 1
                local icon = icons[shown]
                icon.texture:SetTexture(aura.icon)
                if canDeduplicate and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                    icon.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(frame.unit, id, 2, 1000))
                else
                    local applications = aura.applications
                    if isSecret(applications) then
                        icon.count:SetFormattedText('%d', applications)
                    elseif applications and applications > 1 then
                        icon.count:SetFormattedText('%d', applications)
                    else
                        icon.count:SetText('')
                    end
                end
                icon:Show()
            end
        end
        if shown >= AURAS_PER_ROW then break end
    end
    for i = shown + 1, AURAS_PER_ROW do
        icons[i]:Hide()
        icons[i].texture:SetTexture(nil)
        icons[i].count:SetText('')
    end
end

local UnitFrameMixin = {}

function UnitFrameMixin:UpdatePercentVisibility()
    local visible = self.preview or self:IsMouseOver()
    if not visible and UnitExists('target') and UnitIsUnit then
        local isTarget = UnitIsUnit(self.unit, 'target')
        visible = not isSecret(isTarget) and isTarget
    end
    local alpha = visible and 1 or 0
    self.healthText:SetAlpha(alpha)
    self.powerText:SetAlpha(alpha)
end

function UnitFrameMixin:ApplyLayout(width, height)
    if InCombatLockdown and InCombatLockdown() then return false end
    self:SetSize(width, height)
    local barWidth = width - BAR_LEFT - BAR_RIGHT_GAP - AURA_WIDTH - 5 - BAR_WIDTH_REDUCTION
    self.name:SetWidth(width - NAME_LEFT - BAR_RIGHT_GAP - AURA_WIDTH - 5)
    self.healthBarGroup:SetWidth(barWidth)
    self.powerBarGroup:SetWidth(barWidth)
    local auraLeft = width - AURA_WIDTH - 3
    for i = 1, AURAS_PER_ROW do
        local x = auraLeft + (i - 1) * (AURA_SIZE + AURA_GAP)
        self.buffIcons[i]:ClearAllPoints()
        self.buffIcons[i]:SetPoint('TOPLEFT', self, 'TOPLEFT', x, -28)
        self.debuffIcons[i]:ClearAllPoints()
        self.debuffIcons[i]:SetPoint('TOPLEFT', self, 'TOPLEFT', x, -54)
    end
    return true
end

function UnitFrameMixin:UpdateIdentity()
    if self.preview then return end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    self.name:SetText(UnitName(unit))
    self.levelText:SetFormattedText('%d', UnitLevel(unit))
    SetPortraitTexture(self.portrait, unit)

    self.markerIcon:SetTexCoord(0, 1, 0, 1)
    local specIcon = self.resolveSpecIcon and self.resolveSpecIcon(unit)
    if not isSecret(specIcon) and specIcon then
        self.markerIcon:SetTexture(specIcon)
        self.marker:Show()
        return
    end

    local _, class = UnitClass(unit)
    if not isSecret(class) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        self.markerIcon:SetTexture(CLASS_TEXTURE)
        self.markerIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        self.marker:Show()
        return
    end

    local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)
    if not isSecret(role) and role and role ~= 'NONE' and GetMicroIconForRole then
        local atlas = GetMicroIconForRole(role)
        if atlas then
            self.markerIcon:SetAtlas(atlas)
            self.marker:Show()
            return
        end
    end
    self.marker:Hide()
end

function UnitFrameMixin:UpdateHealth()
    if self.preview then return end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    local current, maximum = UnitHealth(unit), UnitHealthMax(unit)
    self.healthBar:SetMinMaxValues(0, maximum)
    self.healthBar:SetValue(current)
    self.portrait:SetDesaturated(false)

    local connected = UnitIsConnected(unit)
    if not isSecret(connected) and not connected then
        self.healthText:SetText(PLAYER_OFFLINE or 'Offline')
        self.portrait:SetDesaturated(true)
        return
    end
    local dead = UnitIsDeadOrGhost(unit)
    if not isSecret(dead) and dead then
        self.healthText:SetText(DEAD or 'Dead')
        self.portrait:SetDesaturated(true)
        return
    end
    percentText(self.healthText, unit, current, maximum, 'health')
end

function UnitFrameMixin:UpdatePower()
    if self.preview then return end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    local powerType, powerToken = UnitPowerType(unit)
    local current, maximum = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    self.powerBar:SetMinMaxValues(0, maximum)
    self.powerBar:SetValue(current)
    if not isSecret(maximum) and maximum == 0 then
        self.powerText:SetText('')
    else
        percentText(self.powerText, unit, current, maximum, 'power', powerType)
    end
    local color
    if PowerBarColor then
        if not isSecret(powerToken) and powerToken then color = PowerBarColor[powerToken] end
        if not color and not isSecret(powerType) and powerType then color = PowerBarColor[powerType] end
    end
    self.powerBar:SetStatusBarColor(color and color.r or 0.82, color and color.g or 0.25,
        color and color.b or 0.16)
end

function UnitFrameMixin:UpdateAuras()
    if self.preview then return end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    local filter = AuraUtil and AuraUtil.AuraFilters
    local helpful = filter and filter.Helpful or 'HELPFUL'
    local harmful = filter and filter.Harmful or 'HARMFUL'
    local player = filter and filter.Player or 'PLAYER'
    local raid = filter and filter.Raid or 'RAID'
    showAuraRow(self, self.buffIcons, { helpful .. '|' .. player })
    local harmfulFilters = { harmful .. '|' .. raid }
    if filter and filter.CrowdControl then harmfulFilters[#harmfulFilters + 1] = harmful .. '|' .. filter.CrowdControl end
    if filter and filter.RaidInCombat then harmfulFilters[#harmfulFilters + 1] = harmful .. '|' .. filter.RaidInCombat end
    showAuraRow(self, self.debuffIcons, harmfulFilters)
end

function UnitFrameMixin:Refresh()
    if self.preview then return end
    self:UpdateIdentity()
    self:UpdateHealth()
    self:UpdatePower()
    self:UpdateAuras()
    self:UpdatePercentVisibility()
end

function UnitFrameMixin:SetPreview(enabled, label)
    self.preview = enabled
    self:EnableMouse(not enabled)
    if not enabled then
        self:Refresh()
        return
    end
    self.name:SetText(label or self.unit or 'Party member')
    self.levelText:SetText('80')
    self.portrait:SetTexture('Interface\\Icons\\INV_Misc_QuestionMark')
    self.portrait:SetDesaturated(false)
    self.marker:Hide()
    self.healthBar:SetMinMaxValues(0, 100)
    self.healthBar:SetValue(92)
    self.healthText:SetText('92%')
    self.powerBar:SetMinMaxValues(0, 100)
    self.powerBar:SetValue(100)
    self.powerBar:SetStatusBarColor(0.82, 0.25, 0.16)
    self.powerText:SetText('100%')
    for i = 1, AURAS_PER_ROW do
        self.buffIcons[i]:Hide()
        self.debuffIcons[i]:Hide()
    end
    self:UpdatePercentVisibility()
end

local legacyMenu
local function openContextMenu(frame, unit)
    local kind = unit == 'player' and 'SELF' or 'PARTY'
    if UnitPopup_OpenMenu then
        UnitPopup_OpenMenu(kind, { ownerFrame = frame, unit = unit })
    elseif UnitPopup_ShowMenu and legacyMenu then
        UnitPopup_ShowMenu(legacyMenu, kind, unit, UnitName(unit))
    end
end

addon.UnitFrame = {}

--- Create a reusable, secure unit frame for a fixed unit token. The owner
--- handles unit events and visibility; this component handles presentation.
---@param parent Frame
---@param unit string
---@param opts? { width?: number, height?: number, resolveSpecIcon?: fun(unit: string): number|string? }
---@return Button
function addon.UnitFrame.Create(parent, unit, opts)
    opts = opts or {}
    if not UnitPopup_OpenMenu and UnitPopup_ShowMenu and not legacyMenu then
        legacyMenu = CreateFrame('Frame', 'CouchModeUnitPopup', UIParent, 'UIDropDownMenuTemplate')
    end
    local frame = CreateFrame('Button', nil, parent, 'SecureUnitButtonTemplate')
    Mixin(frame, UnitFrameMixin)
    frame.unit = unit
    frame.resolveSpecIcon = opts.resolveSpecIcon
    frame:SetFrameStrata('MEDIUM')
    SecureUnitButton_OnLoad(frame, unit, openContextMenu)
    frame:SetScript('OnEnter', function(self)
        self:UpdatePercentVisibility()
        if not self.preview and UnitExists(self.unit) then
            GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
            GameTooltip:SetUnit(self.unit)
        end
    end)
    frame:SetScript('OnLeave', function(self)
        GameTooltip:Hide()
        self:UpdatePercentVisibility()
    end)

    local portraitGroup = CreateFrame('Frame', nil, frame)
    portraitGroup:SetSize(88, 88)
    portraitGroup:SetPoint('TOPLEFT', frame, 'TOPLEFT', -2, 0)
    frame.portraitGroup = portraitGroup
    local portraitBorder = makeAtlasBorder(portraitGroup, 88, PORTRAIT_BORDER_ATLAS)
    if portraitBorder then portraitBorder:SetPoint('CENTER', portraitGroup, 'CENTER') end
    local portraitOuter
    if not portraitBorder then
        portraitOuter = makeCircle(portraitGroup, 84, { 0.62, 0.49, 0.30, 1 })
        portraitOuter:SetPoint('CENTER', portraitGroup, 'CENTER')
    end
    local portraitInner = makeCircle(portraitGroup, 74, { 0.08, 0.08, 0.09, 1 })
    if portraitOuter then
        portraitInner:SetPoint('CENTER', portraitOuter, 'CENTER')
    else
        portraitInner:SetPoint('CENTER', portraitGroup, 'CENTER')
    end
    frame.portrait = portraitGroup:CreateTexture(nil, 'ARTWORK')
    frame.portrait:SetDrawLayer('OVERLAY', 7)
    frame.portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    frame.portrait:SetPoint('CENTER', portraitGroup, 'CENTER')
    local portraitMask = portraitGroup:CreateMaskTexture()
    portraitMask:SetAtlas('CircleMask')
    portraitMask:SetAllPoints(frame.portrait)
    frame.portrait:AddMaskTexture(portraitMask)
    local level = CreateFrame('Frame', nil, portraitGroup)
    level:SetSize(27, 27)
    level:SetPoint('BOTTOMLEFT', frame.portrait, 'BOTTOMLEFT', -2, -2)
    local levelBorder = makeAtlasBorder(level, 31, RING_BORDER_ATLAS)
    if levelBorder then levelBorder:SetPoint('CENTER', level, 'CENTER') end
    if not levelBorder then
        local levelOuter = makeCircle(level, 27, { 0.65, 0.51, 0.27, 1 })
        levelOuter:SetPoint('CENTER', level, 'CENTER')
    end
    local levelInner = makeCircle(level, 23, { 0.08, 0.08, 0.09, 1 })
    levelInner:SetPoint('CENTER', level, 'CENTER')
    frame.levelText = level:CreateFontString(nil, 'OVERLAY')
    frame.levelText:SetFont(addon.Media.ResolveFont('Bebas Neue'), 15, 'OUTLINE')
    frame.levelText:SetPoint('CENTER', level, 'CENTER')

    frame.marker = CreateFrame('Frame', nil, portraitGroup)
    frame.marker:SetSize(26, 26)
    frame.marker:SetPoint('TOPRIGHT', frame.portrait, 'TOPRIGHT', 4, 3)
    local markerBackground = makeCircle(frame.marker, 26, { 0.08, 0.08, 0.09, 1 })
    markerBackground:SetPoint('CENTER', frame.marker, 'CENTER')
    local markerBorder = makeAtlasBorder(frame.marker, 30, RING_BORDER_ATLAS)
    if markerBorder then markerBorder:SetPoint('CENTER', frame.marker, 'CENTER') end
    frame.markerIcon = frame.marker:CreateTexture(nil, 'OVERLAY')
    frame.markerIcon:SetSize(21, 21)
    frame.markerIcon:SetPoint('CENTER', frame.marker, 'CENTER')
    frame.marker:Hide()

    frame.name = frame:CreateFontString(nil, 'OVERLAY')
    frame.name:SetFont(addon.Media.ResolveFont('Bebas Neue'), 18, 'OUTLINE')
    frame.name:SetPoint('TOPLEFT', frame, 'TOPLEFT', NAME_LEFT, -14)
    frame.name:SetJustifyH('LEFT')
    frame.name:SetWordWrap(false)
    addon.Utils.apply_font_shadow(frame.name)

    frame.healthBar, frame.healthText, frame.healthBarGroup, frame.healthBorderFrame =
        makeBar(frame, 20, { 0.49, 0.68, 0.23, 1 })
    frame.healthBarGroup:SetPoint('TOPLEFT', frame, 'TOPLEFT', BAR_LEFT, -31)
    frame.powerBar, frame.powerText, frame.powerBarGroup, frame.powerBorderFrame =
        makeBar(frame, 18, { 0.82, 0.25, 0.16, 1 })
    frame.powerBarGroup:SetPoint('TOPLEFT', frame, 'TOPLEFT', BAR_LEFT, -51)

    -- Keep each bar's visuals together below the portrait group as a unit.
    local barsLevel = frame:GetFrameLevel() + 1
    frame.healthBarGroup:SetFrameLevel(barsLevel)
    frame.healthBar:SetFrameLevel(barsLevel + 1)
    frame.healthBorderFrame:SetFrameLevel(barsLevel + 2)
    frame.powerBarGroup:SetFrameLevel(barsLevel)
    frame.powerBar:SetFrameLevel(barsLevel + 1)
    frame.powerBorderFrame:SetFrameLevel(barsLevel + 2)
    portraitGroup:SetFrameLevel(barsLevel + 3)

    frame.buffIcons, frame.debuffIcons = {}, {}
    for i = 1, AURAS_PER_ROW do
        frame.buffIcons[i] = makeAuraIcon(frame)
        frame.debuffIcons[i] = makeAuraIcon(frame)
    end
    frame:ApplyLayout(opts.width or 430, opts.height or 88)
    frame:Refresh()
    return frame
end
