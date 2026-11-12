local addonName = ...

local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecret = addon.Utils.IsSecretValue

local BAR_BACKGROUND_ATLAS = 'UI-CastingBar-Background'
local BAR_BORDER_ATLAS = 'UI-CastingBar-Frame'
local BAR_FILL_ATLAS = 'ui-castingbar-tier4-empower'
local PORTRAIT_BORDER_ATLAS = 'hud-PlayerFrame-portraitring-large'
local PORTRAIT_WHIRL_ATLAS = 'ArtifactsFX-Whirls'
local RING_BORDER_ATLAS = 'gamepad-actionbar-circleslot-border-selected'
local BAR_FALLBACK_TEXTURE = 'Interface\\AddOns\\CouchMode\\Resources\\Media\\basic_bar.tga'
local WHITE_TEXTURE = 'Interface\\Buttons\\WHITE8X8'
local CLASS_TEXTURE = 'Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES'
local PORTRAIT_SIZE = 66
local PORTRAIT_WHIRL_SIZE = 96
local PORTRAIT_WHIRL_ROTATION_DURATION = 12
local PORTRAIT_WHIRL_FADE_DURATION = 0.3
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

local healthColorCurve
if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
    healthColorCurve = C_CurveUtil.CreateColorCurve()
    healthColorCurve:AddPoint(0, CreateColor(1, 0, 0))
    healthColorCurve:AddPoint(0.5, CreateColor(1, 1, 0))
    healthColorCurve:AddPoint(1, CreateColor(0, 1, 0))
end

local function setHealthBarColor(bar, unit, current, maximum)
    if unit and healthColorCurve and UnitHealthPercent then
        local color = UnitHealthPercent(unit, true, healthColorCurve)
        bar:SetStatusBarColor(color:GetRGB())
    elseif not isSecret(current) and not isSecret(maximum) and maximum > 0 then
        local percent = math.max(0, math.min(1, current / maximum))
        bar:SetStatusBarColor(math.min(1, 2 * (1 - percent)), math.min(1, 2 * percent), 0)
    else
        bar:SetStatusBarColor(0, 1, 0)
    end
end

local function setPowerBarColor(bar, powerType, powerToken, altR, altG, altB)
    local color
    if PowerBarColor and not isSecret(powerToken) and powerToken then
        color = PowerBarColor[powerToken]
    end
    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b)
    elseif altR ~= nil and altG ~= nil and altB ~= nil then
        bar:SetStatusBarColor(altR, altG, altB)
    else
        if PowerBarColor then
            if not isSecret(powerType) and powerType then color = PowerBarColor[powerType] end
            color = color or PowerBarColor.MANA
        end
        bar:SetStatusBarColor(color and color.r or 0, color and color.g or 0, color and color.b or 1)
    end
end

local function setStatusBarValue(statusBar, value, smooth)
    local interpolation = Enum and Enum.StatusBarInterpolation
    if interpolation then
        local mode = smooth and interpolation.ExponentialEaseOut or interpolation.Immediate
        if mode ~= nil then
            statusBar:SetValue(value, mode)
            return
        end
    end
    statusBar:SetValue(value)
end

local function smoothBarsEnabled()
    local profile = addon.db and addon.db.profile
    return profile and profile.party and profile.party.smoothBars == true
end

local function hasAtlas(atlas)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

local function makeAtlasTexture(parent, atlas, layer)
    if not hasAtlas(atlas) then
        return nil
    end

    local texture = parent:CreateTexture(nil, layer)
    texture:SetAtlas(atlas)
    return texture
end

local function makeAtlasBorder(parent, size, atlas)
    local border = makeAtlasTexture(parent, atlas, 'OVERLAY')
    if not border then
        return nil
    end
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
    if hasAtlas(BAR_FILL_ATLAS) then
        fill:SetAtlas(BAR_FILL_ATLAS)
    end
    fill:SetDesaturated(true) -- keep the fill's artwork from shifting the bar color
    bar:SetStatusBarColor(unpack(color))
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)
    if hasAtlas(BAR_BACKGROUND_ATLAS) then
        background:SetAtlas(BAR_BACKGROUND_ATLAS)
    else
        background:SetColorTexture(0.04, 0.05, 0.06, 0.9)
    end
    local borderFrame = CreateFrame('Frame', nil, group)
    borderFrame:SetAllPoints(group)
    borderFrame:SetFrameLevel(bar:GetFrameLevel() + 1)
    local border = makeAtlasTexture(borderFrame, BAR_BORDER_ATLAS, 'OVERLAY')
    if border then
        border:SetAllPoints(bar)
    else
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

local function showAuraTooltip(icon)
    local owner = icon:GetParent()
    if owner.preview then
        if not icon.previewSpellID then return end
        GameTooltip:SetOwner(icon, 'ANCHOR_RIGHT')
        GameTooltip:SetSpellByID(icon.previewSpellID)
    else
        if not addon.Utils.CanReadAuras() then return end
        if not icon.auraIndex or not UnitExists(owner.unit) then return end
        GameTooltip:SetOwner(icon, 'ANCHOR_RIGHT')
        if icon.auraInstanceID and GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(owner.unit, icon.auraInstanceID)
        else
            GameTooltip:SetUnitAura(owner.unit, icon.auraIndex, icon.auraFilter)
        end
    end
    if icon.dispellable then
        GameTooltip:AddLine(DISPELLABLE or 'You can dispel this effect', 0.3, 0.85, 1)
        GameTooltip:Show()
    end
end

local function hideAuraTooltip(icon)
    if GameTooltip:IsOwned(icon) then GameTooltip:Hide() end
end

local function makeAuraIcon(parent, isDebuff)
    local frame = CreateFrame('Frame', nil, parent)
    frame:SetSize(AURA_SIZE, AURA_SIZE)
    frame:SetMouseMotionEnabled(true)
    frame:SetMouseClickEnabled(false) -- clicks continue to target the unit beneath the icon
    frame:SetScript('OnEnter', function(self)
        parent:UpdatePercentVisibility()
        showAuraTooltip(self)
    end)
    frame:SetScript('OnLeave', function(self)
        hideAuraTooltip(self)
        parent:UpdatePercentVisibility()
    end)
    frame:SetScript('OnHide', hideAuraTooltip)
    local texture = frame:CreateTexture(nil, 'ARTWORK')
    texture:SetAllPoints(frame)
    texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = frame:CreateTexture(nil, 'OVERLAY')
    border:SetColorTexture(isDebuff and 1 or 0, 0, 0, 1)
    border:SetPoint('TOPLEFT', frame, 'TOPLEFT', -1, 1)
    border:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 1, -1)
    border:SetDrawLayer('BACKGROUND')
    frame.cooldown = CreateFrame('Cooldown', nil, frame, 'CooldownFrameTemplate')
    frame.cooldown:SetAllPoints(frame)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetReverse(true)
    if frame.cooldown.SetHideCountdownNumbers then frame.cooldown:SetHideCountdownNumbers(true) end
    frame.cooldown:EnableMouse(false)
    local labels = CreateFrame('Frame', nil, frame)
    labels:SetAllPoints(frame)
    labels:SetFrameLevel(frame.cooldown:GetFrameLevel() + 1)
    labels:EnableMouse(false)
    frame.dispelCue = labels:CreateTexture(nil, 'OVERLAY')
    frame.dispelCue:SetColorTexture(0.3, 0.85, 1, 1)
    frame.dispelCue:SetSize(5, 5)
    frame.dispelCue:SetPoint('TOPLEFT', frame, 'TOPLEFT', 1, -1)
    frame.dispelCue:Hide()
    frame.isDebuff = isDebuff
    local count = labels:CreateFontString(nil, 'OVERLAY')
    count:SetFont(addon.Media.ResolveFont('Bebas Neue'), 12, 'OUTLINE')
    count:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', 2, -2)
    addon.Utils.apply_font_shadow(count)
    frame.texture = texture
    frame.count = count
    frame:Hide()
    return frame
end

local function clearAuraIcon(icon)
    icon:Hide()
    icon.auraInstanceID = nil
    icon.auraIndex = nil
    icon.auraFilter = nil
    icon.previewSpellID = nil
    icon.previewDuration = nil
    icon.previewEnds = nil
    icon.dispellable = nil
    icon.dispelCue:Hide()
    icon.cooldown:SetCooldown(0, 0)
    icon.cooldown:Hide()
    icon.texture:SetTexture(nil)
    icon.count:SetText('')
end

local function showPreviewAuraRow(icons, auras)
    for i, icon in ipairs(icons) do
        clearAuraIcon(icon)
        local aura = auras and auras[i]
        if aura then
            icon.previewSpellID = aura.spellID
            icon.texture:SetTexture(aura.icon)
            if aura.duration then
                local start = GetTime() - aura.duration * 0.3
                icon.previewDuration = aura.duration
                icon.previewEnds = start + aura.duration
                icon.cooldown:SetCooldown(start, aura.duration)
                icon.cooldown:Show()
            end
            icon.dispellable = aura.dispellable == true
            icon.dispelCue:SetShown(icon.dispellable)
            if aura.applications and aura.applications > 1 then
                icon.count:SetFormattedText('%d', aura.applications)
            end
            icon:Show()
        end
    end
end

local function getAuras(unit, filter)
    if not addon.Utils.CanReadAuras() then return {} end
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
            local name, icon, applications, dispelName, duration, expirationTime = UnitAura(unit, i, filter)
            if not name then break end
            auras[#auras + 1] = { icon = icon, applications = applications,
                dispelName = dispelName, duration = duration, expirationTime = expirationTime }
        end
    end
    return auras
end

local function percentText(label, unit, current, maximum, kind, powerType)
    if percentCurve then
        if kind == 'health' and UnitHealthPercent then
            label:SetFormattedText('%d%%', UnitHealthPercent(unit, true, percentCurve))
            return
        elseif kind == 'power' and UnitPowerPercent then
            label:SetFormattedText('%d%%', UnitPowerPercent(unit, powerType, false, percentCurve))
            return
        end
    end

    if not isSecret(current) and not isSecret(maximum) and maximum > 0 then
        label:SetFormattedText('%d%%', math.floor(current / maximum * 100 + 0.5))
        return
    end

    label:SetText('')
end

local function showAuraRow(frame, icons, filters)
    local shown = 0
    local seen = {}
    for _, filter in ipairs(filters) do
        for auraIndex, aura in ipairs(getAuras(frame.unit, filter)) do
            if shown >= AURAS_PER_ROW then break end
            local id = aura.auraInstanceID
            local canDeduplicate = not isSecret(id) and id ~= nil
            if not canDeduplicate or not seen[id] then
                if canDeduplicate then seen[id] = true end
                shown = shown + 1
                local icon = icons[shown]
                icon.previewSpellID = nil
                icon.auraInstanceID = canDeduplicate and id or nil
                icon.auraIndex = auraIndex
                icon.auraFilter = filter
                icon.texture:SetTexture(aura.icon)
                icon.cooldown:SetCooldown(0, 0)
                icon.cooldown:Hide()
                if canDeduplicate and C_UnitAuras and C_UnitAuras.GetAuraDuration
                    and icon.cooldown.SetCooldownFromDurationObject then
                    icon.cooldown:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(frame.unit, id))
                    icon.cooldown:Show()
                elseif not isSecret(aura.duration) and not isSecret(aura.expirationTime)
                    and aura.duration and aura.duration > 0 and aura.expirationTime then
                    icon.cooldown:SetCooldown(aura.expirationTime - aura.duration, aura.duration)
                    icon.cooldown:Show()
                end
                icon.dispellable = false
                if icon.isDebuff then
                    if canDeduplicate and C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID then
                        local filtered = C_UnitAuras.IsAuraFilteredOutByInstanceID(frame.unit, id, 'HARMFUL|RAID')
                        icon.dispellable = not isSecret(filtered) and not filtered
                    else
                        icon.dispellable = filter == 'HARMFUL|RAID'
                    end
                end
                icon.dispelCue:SetShown(icon.dispellable)
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
                if GameTooltip:IsOwned(icon) then showAuraTooltip(icon) end
            end
        end
        if shown >= AURAS_PER_ROW then break end
    end
    for i = shown + 1, AURAS_PER_ROW do
        clearAuraIcon(icons[i])
    end
end

local UnitFrameMixin = {}

function UnitFrameMixin:UpdatePreviewCooldowns(now)
    if not self.preview then return end
    for _, icons in ipairs({ self.buffIcons, self.debuffIcons }) do
        for _, icon in ipairs(icons) do
            if icon.previewEnds and now >= icon.previewEnds then
                icon.previewEnds = now + icon.previewDuration
                icon.cooldown:SetCooldown(now, icon.previewDuration)
                icon.cooldown:Show()
            end
        end
    end
end

function UnitFrameMixin:SetPortraitWhirlActive(active)
    if not self.portraitWhirl or self.portraitWhirlActive == active then
        return
    end

    self.portraitWhirlActive = active
    local targetAlpha = active and 1 or 0
    local currentAlpha = self.portraitWhirl:GetAlpha()
    self.portraitWhirlFade:Stop()
    self.portraitWhirl:SetAlpha(currentAlpha)

    if active then
        self.portraitWhirlAnimation:Play()
    end

    if currentAlpha == targetAlpha then
        if not active then
            self.portraitWhirlAnimation:Stop()
        end
        return
    end

    self.portraitWhirlFadeTarget = targetAlpha
    self.portraitWhirlFadeAlpha:SetFromAlpha(currentAlpha)
    self.portraitWhirlFadeAlpha:SetToAlpha(targetAlpha)
    self.portraitWhirlFade:Play()
end

function UnitFrameMixin:UpdateCombat()
    local inCombat = false
    if not self.preview and self.unit and UnitExists(self.unit) and UnitAffectingCombat then
        local affectingCombat = UnitAffectingCombat(self.unit)
        inCombat = not isSecret(affectingCombat) and affectingCombat == true
    end
    self:SetPortraitWhirlActive(inCombat)
end

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
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    self:SetSize(width, height)
    local barWidth = width - BAR_LEFT - BAR_RIGHT_GAP - AURA_WIDTH - 5 - BAR_WIDTH_REDUCTION
    self.name:SetWidth(width - NAME_LEFT - BAR_RIGHT_GAP - AURA_WIDTH - 5)
    self.healthBarGroup:SetWidth(barWidth)
    self.powerBarGroup:SetWidth(barWidth)
    if self.prediction then self.prediction:ApplyLayout() end
    for i = 1, AURAS_PER_ROW do
        local x = 5 + (i - 1) * (AURA_SIZE + AURA_GAP)
        self.buffIcons[i]:ClearAllPoints()
        self.buffIcons[i]:SetPoint('TOPLEFT', self.healthBarGroup, 'TOPRIGHT', x, 3)
        self.debuffIcons[i]:ClearAllPoints()
        self.debuffIcons[i]:SetPoint('TOPLEFT', self.powerBarGroup, 'TOPRIGHT', x, -3)
    end
    if self.auraRows then
        self.auraRows.buffs:ClearAllPoints()
        self.auraRows.debuffs:ClearAllPoints()
        self.auraRows.buffs:SetPoint('TOPLEFT', self.healthBarGroup, 'TOPRIGHT', 5, 3)
        self.auraRows.debuffs:SetPoint('TOPLEFT', self.powerBarGroup, 'TOPRIGHT', 5, -3)
    end
    return true
end

function UnitFrameMixin:SetRoleIcon(role)
    self.roleFrame:Hide()
    if isSecret(role) then return end
    if role ~= 'TANK' and role ~= 'HEALER' and role ~= 'DAMAGER' then return end
    self.roleIcon:SetTexCoord(0, 1, 0, 1)
    local atlas = GetMicroIconForRole and GetMicroIconForRole(role)
    if atlas and hasAtlas(atlas) then
        self.roleIcon:SetAtlas(atlas)
    elseif GetTexCoordsForRoleSmallCircle then
        self.roleIcon:SetTexture('Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES')
        self.roleIcon:SetTexCoord(GetTexCoordsForRoleSmallCircle(role))
    else
        return
    end
    self.roleFrame:Show()
end

function UnitFrameMixin:SetLeaderIcon(isLeader)
    self.leaderIcon:SetShown(not isSecret(isLeader) and isLeader == true)
end

function UnitFrameMixin:UpdateLeader()
    if self.preview then return end
    local leader = self.unit and UnitExists(self.unit) and UnitIsGroupLeader and UnitIsGroupLeader(self.unit)
    self:SetLeaderIcon(leader)
end

function UnitFrameMixin:UpdateIdentity()
    if self.preview then return end
    local unit = self.unit
    self:UpdateLeader()
    self:SetRoleIcon(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit))
    local _, class = UnitClass(unit)
    local classColor = not isSecret(class) and class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if classColor then
        self.name:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        self.name:SetTextColor(1, 1, 1)
    end
    if not unit or not UnitExists(unit) then return end
    self.name:SetText(UnitName(unit))
    self.levelText:SetFormattedText('%d', UnitLevel(unit))
    self.portrait:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(self.portrait, unit)

    if self.portraitWhirl then
        if classColor then
            self.portraitWhirl:SetVertexColor(classColor.r, classColor.g, classColor.b)
        else
            self.portraitWhirl:SetVertexColor(1, 1, 1)
        end
    end

    self.markerIcon:SetTexCoord(0, 1, 0, 1)
    local specIcon = self.resolveSpecIcon and self.resolveSpecIcon(unit)
    if not isSecret(specIcon) and specIcon then
        self.markerIcon:SetTexture(specIcon)
        self.marker:Show()
        return
    end

    if not isSecret(class) and class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        self.markerIcon:SetTexture(CLASS_TEXTURE)
        self.markerIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        self.marker:Show()
        return
    end

    self.marker:Hide()
end

function UnitFrameMixin:UpdateHealth()
    if self.preview then
        return
    end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    local current, maximum = UnitHealth(unit), UnitHealthMax(unit)
    self.healthBar:SetMinMaxValues(0, maximum)
    setStatusBarValue(self.healthBar, current, smoothBarsEnabled())
    setHealthBarColor(self.healthBar, unit, current, maximum)
    self.portrait:SetDesaturated(false)
    self.healthStatus = nil

    local connected = UnitIsConnected(unit)
    if not isSecret(connected) and not connected then
        self.healthStatus = PLAYER_OFFLINE or 'Offline'
        self.healthText:SetText('')
        self.statusText:SetText(self.healthStatus)
        self.portrait:SetDesaturated(true)
        self.prediction:Clear()
        return
    end
    local dead = UnitIsDeadOrGhost(unit)
    if not isSecret(dead) and dead then
        local ghost = UnitIsGhost and UnitIsGhost(unit)
        self.healthStatus = not isSecret(ghost) and ghost and (GHOST or 'Ghost') or (DEAD or 'Dead')
        self.healthText:SetText('')
        self.statusText:SetText(self.healthStatus)
        self.portrait:SetDesaturated(true)
        self.prediction:Clear()
        return
    end
    self.statusText:SetText('')
    self.prediction:Refresh()
    percentText(self.healthText, unit, current, maximum, 'health')
end

function UnitFrameMixin:UpdatePower()
    if self.preview then
        return
    end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
    local current, maximum = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    self.powerBar:SetMinMaxValues(0, maximum)
    setStatusBarValue(self.powerBar, current, smoothBarsEnabled())
    if not isSecret(maximum) and maximum == 0 then
        self.powerText:SetText('')
    else
        percentText(self.powerText, unit, current, maximum, 'power', powerType)
    end
    setPowerBarColor(self.powerBar, powerType, powerToken, altR, altG, altB)
end

function UnitFrameMixin:UpdateAuras()
    if self.preview then
        return
    end
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    if self.auraRows then
        addon.AuraDisplay.SetUnit(self.auraRows.buffs, unit)
        addon.AuraDisplay.SetUnit(self.auraRows.debuffs, unit)
        return
    end
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
    if self.preview then
        return
    end
    self:UpdateIdentity()
    self:UpdateHealth()
    self:UpdatePower()
    self:UpdateAuras()
    self:UpdateCombat()
    self:UpdatePercentVisibility()
    self.status:Refresh()
end

function UnitFrameMixin:SetPreview(enabled, data)
    self.preview = enabled
    self.previewData = enabled and (data or {}) or nil
    self:EnableMouse(not enabled)
    if enabled and self.auraRows then
        addon.AuraDisplay.SetUnit(self.auraRows.buffs, nil)
        addon.AuraDisplay.SetUnit(self.auraRows.debuffs, nil)
    end
    if not enabled then
        self.status.readyExpires = nil
        self.status:SetReadyCheck(nil)
        for i = 1, AURAS_PER_ROW do
            clearAuraIcon(self.buffIcons[i])
            clearAuraIcon(self.debuffIcons[i])
        end
        self:Refresh()
        return
    end
    data = data or {}
    self:UpdateCombat()
    self:SetRoleIcon(data.role)
    self:SetLeaderIcon(data.leader)
    self.name:SetText(data.name or self.unit or 'Party member')
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
    self.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    self.levelText:SetText('80')
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class]
    self.portrait:SetTexCoord(0, 1, 0, 1)
    SetPortraitTexture(self.portrait, UnitExists(self.unit) and self.unit or 'player')
    self.portrait:SetDesaturated(false)
    self.markerIcon:SetTexCoord(0, 1, 0, 1)
    if coords then
        self.markerIcon:SetTexture(CLASS_TEXTURE)
        self.markerIcon:SetTexCoord(unpack(coords))
        self.marker:Show()
    else
        self.marker:Hide()
    end
    local health, power = data.health or 92, data.power or 100
    self.healthBar:SetMinMaxValues(0, 100)
    setStatusBarValue(self.healthBar, health, false)
    setHealthBarColor(self.healthBar, nil, health, 100)
    self.healthText:SetFormattedText('%d%%', health)
    self.powerBar:SetMinMaxValues(0, 100)
    setStatusBarValue(self.powerBar, power, false)
    setPowerBarColor(self.powerBar, nil, data.powerToken or 'MANA')
    self.powerText:SetFormattedText('%d%%', power)
    local state = data.state
    self.healthStatus = state == 'offline' and (PLAYER_OFFLINE or 'Offline')
        or state == 'ghost' and (GHOST or 'Ghost') or state == 'dead' and (DEAD or 'Dead') or nil
    self.statusText:SetText(self.healthStatus or '')
    if self.healthStatus then
        self.portrait:SetDesaturated(true)
        self.healthText:SetText('')
    end
    showPreviewAuraRow(self.buffIcons, data.buffs)
    showPreviewAuraRow(self.debuffIcons, data.debuffs)
    self:UpdatePercentVisibility()
    self.status:Refresh()
    if self.healthStatus then self.prediction:Clear() else self.prediction:Refresh() end
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
    frame.portraitWhirl = makeAtlasTexture(portraitGroup, PORTRAIT_WHIRL_ATLAS, 'OVERLAY')
    if frame.portraitWhirl then
        frame.portraitWhirl:SetDrawLayer('OVERLAY', 1)
        frame.portraitWhirl:SetSize(PORTRAIT_WHIRL_SIZE, PORTRAIT_WHIRL_SIZE)
        frame.portraitWhirl:SetPoint('CENTER', portraitGroup, 'CENTER')
        frame.portraitWhirl:SetDesaturated(true)
        frame.portraitWhirl:SetBlendMode('ADD')
        frame.portraitWhirl:SetAlpha(0)

        local animation = frame.portraitWhirl:CreateAnimationGroup()
        animation:SetLooping('REPEAT')
        local rotation = animation:CreateAnimation('Rotation')
        rotation:SetDegrees(-360)
        rotation:SetDuration(PORTRAIT_WHIRL_ROTATION_DURATION)
        rotation:SetSmoothing('NONE')
        frame.portraitWhirlAnimation = animation

        local fade = frame.portraitWhirl:CreateAnimationGroup()
        fade:SetToFinalAlpha(true)
        local fadeAlpha = fade:CreateAnimation('Alpha')
        fadeAlpha:SetDuration(PORTRAIT_WHIRL_FADE_DURATION)
        fadeAlpha:SetSmoothing('IN_OUT')
        fade:SetScript('OnFinished', function()
            frame.portraitWhirl:SetAlpha(frame.portraitWhirlFadeTarget or 0)
            if not frame.portraitWhirlActive then
                frame.portraitWhirlAnimation:Stop()
            end
        end)
        frame.portraitWhirlFade = fade
        frame.portraitWhirlFadeAlpha = fadeAlpha
    end
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
    frame.leaderIcon = portraitGroup:CreateTexture(nil, 'OVERLAY', nil, 7)
    frame.leaderIcon:SetSize(20, 20)
    frame.leaderIcon:SetPoint('TOPLEFT', frame.portrait, 'TOPLEFT', -5, 5)
    local leaderAtlas = 'UI-HUD-UnitFrame-Player-Group-LeaderIcon'
    if hasAtlas(leaderAtlas) then
        frame.leaderIcon:SetAtlas(leaderAtlas)
    else
        frame.leaderIcon:SetTexture('Interface\\GroupFrame\\UI-Group-LeaderIcon')
    end
    frame.leaderIcon:Hide()
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
    frame.levelText:SetSize(23, 23)
    frame.levelText:SetJustifyH('CENTER')
    frame.levelText:SetJustifyV('MIDDLE')
    -- Optical offset for the numerals inside the level ring.
    frame.levelText:SetPoint('CENTER', levelInner, 'CENTER', 1, -1)

    frame.marker = CreateFrame('Frame', nil, portraitGroup)
    frame.marker:SetSize(26, 26)
    frame.marker:SetPoint('TOPRIGHT', frame.portrait, 'TOPRIGHT', 4, 3)
    local markerBackground = makeCircle(frame.marker, 26, { 0.08, 0.08, 0.09, 1 })
    markerBackground:SetDrawLayer('BACKGROUND')
    markerBackground:SetPoint('CENTER', frame.marker, 'CENTER')
    local markerBorder = makeAtlasBorder(frame.marker, 30, RING_BORDER_ATLAS)
    if markerBorder then
        -- Selected-slot artwork includes a center; keep it beneath the masked icon.
        markerBorder:SetDrawLayer('BORDER')
        markerBorder:SetPoint('CENTER', frame.marker, 'CENTER')
    end
    frame.markerIcon = frame.marker:CreateTexture(nil, 'ARTWORK')
    frame.markerIcon:SetSize(21, 21)
    frame.markerIcon:SetPoint('CENTER', frame.marker, 'CENTER')
    local markerMask = frame.marker:CreateMaskTexture()
    markerMask:SetAtlas('CircleMask')
    markerMask:SetAllPoints(frame.markerIcon)
    frame.markerIcon:AddMaskTexture(markerMask)
    frame.marker:Hide()

    -- Role stays visible independently of the specialization/class badge above it.
    local roleFrame = CreateFrame('Frame', nil, portraitGroup)
    roleFrame:SetSize(22, 22)
    roleFrame:SetPoint('BOTTOMRIGHT', frame.portrait, 'BOTTOMRIGHT', 4, -3)
    roleFrame:EnableMouse(false)
    local roleBackground = makeCircle(roleFrame, 22, { 0.08, 0.08, 0.09, 1 })
    roleBackground:SetPoint('CENTER', roleFrame, 'CENTER')
    frame.roleIcon = roleFrame:CreateTexture(nil, 'OVERLAY')
    frame.roleIcon:SetSize(20, 20)
    frame.roleIcon:SetPoint('CENTER', roleFrame, 'CENTER')
    frame.roleFrame = roleFrame
    roleFrame:Hide()

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
    frame.healthBorderFrame:SetFrameLevel(barsLevel + 3)
    frame.powerBarGroup:SetFrameLevel(barsLevel)
    frame.powerBar:SetFrameLevel(barsLevel + 1)
    frame.powerBorderFrame:SetFrameLevel(barsLevel + 3)
    portraitGroup:SetFrameLevel(barsLevel + 4)

    frame.statusText = frame.powerBorderFrame:CreateFontString(nil, 'OVERLAY')
    frame.statusText:SetFont(addon.Media.ResolveFont('Bebas Neue'), 14, 'OUTLINE')
    frame.statusText:SetPoint('TOPLEFT', frame.powerBarGroup, 'BOTTOMLEFT', 14, -3)
    frame.statusText:SetTextColor(0.85, 0.85, 0.85)
    addon.Utils.apply_font_shadow(frame.statusText)
    frame.prediction = addon.UnitFramePrediction.Create(frame)
    frame.status = addon.UnitFrameStatus.Create(frame)

    frame.buffIcons, frame.debuffIcons = {}, {}
    for i = 1, AURAS_PER_ROW do
        frame.buffIcons[i] = makeAuraIcon(frame)
        frame.debuffIcons[i] = makeAuraIcon(frame, true)
    end
    if addon.AuraDisplay.IsSupported() then
        local function createRow(filters, debuff)
            return addon.AuraDisplay.Create(frame, {
                width = AURA_SIZE, height = AURA_SIZE, gap = AURA_GAP,
                maxCount = AURAS_PER_ROW, filters = filters, debuff = debuff,
                countOffsetX = 2, countOffsetY = -2,
                tooltips = true, shadow = true,
                font = function() return addon.Media.ResolveFont('Bebas Neue'), 12, 'OUTLINE' end,
            })
        end
        frame.auraRows = {
            buffs = createRow({ 'HELPFUL|PLAYER' }),
            -- Disjoint filters preserve priority and prevent duplicate icons.
            debuffs = createRow({ 'HARMFUL|RAID', 'HARMFUL|CROWD_CONTROL|!RAID',
                'HARMFUL|RAID_IN_COMBAT|!RAID|!CROWD_CONTROL' }, true),
        }
    end
    frame:ApplyLayout(opts.width or 430, opts.height or 88)
    frame:Refresh()
    return frame
end
