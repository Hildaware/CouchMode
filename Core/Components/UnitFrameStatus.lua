local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecret = addon.Utils.IsSecretValue
local Status = {}
local READY_TEXTURES = {
    ready = 'Interface\\RaidFrame\\ReadyCheck-Ready',
    notready = 'Interface\\RaidFrame\\ReadyCheck-NotReady',
    waiting = 'Interface\\RaidFrame\\ReadyCheck-Waiting',
}
local READY_ATLASES = {
    ready = 'UI-LFG-ReadyMark',
    notready = 'UI-LFG-DeclineMark',
    waiting = 'UI-LFG-PendingMark',
}

local function known(value)
    return not isSecret(value) and value
end

local function booleanAlpha(value, yes, no)
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        return C_CurveUtil.EvaluateColorValueFromBoolean(value, yes, no)
    end
    return known(value) and yes or no
end

local function setArt(texture, atlas, fallback)
    texture:SetTexCoord(0, 1, 0, 1)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetTexture(fallback)
    end
end

local function makeIcon(parent, x, y)
    local icon = CreateFrame('Frame', nil, parent)
    icon:SetSize(20, 20)
    icon:SetPoint('TOPRIGHT', parent, 'TOPRIGHT', x, y)
    icon:SetMouseMotionEnabled(true)
    icon:SetMouseClickEnabled(false)
    icon.texture = icon:CreateTexture(nil, 'ARTWORK')
    icon.texture:SetAllPoints()
    icon:SetScript('OnEnter', function(self)
        parent.owner:UpdatePercentVisibility()
        if not self.tooltip then return end
        GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
        GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    icon:SetScript('OnLeave', function(self)
        hideTooltip(self)
        parent.owner:UpdatePercentVisibility()
    end)
    icon:SetScript('OnHide', hideTooltip)
    icon:Hide()
    return icon
end

local function makeOutline(parent, topFrame, bottomFrame, inset, r, g, b)
    local outline = CreateFrame('Frame', nil, parent)
    outline:SetPoint('TOPLEFT', topFrame, 'TOPLEFT', -inset, inset)
    outline:SetPoint('BOTTOMRIGHT', bottomFrame, 'BOTTOMRIGHT', inset, -inset)
    outline:EnableMouse(false)
    for _, edge in ipairs({ 'TOP', 'BOTTOM', 'LEFT', 'RIGHT' }) do
        local texture = outline:CreateTexture(nil, 'OVERLAY')
        texture:SetColorTexture(r, g, b, 1)
        if edge == 'TOP' or edge == 'BOTTOM' then
            texture:SetHeight(1)
            texture:SetPoint(edge .. 'LEFT')
            texture:SetPoint(edge .. 'RIGHT')
        else
            texture:SetWidth(1)
            texture:SetPoint('TOP' .. edge)
            texture:SetPoint('BOTTOM' .. edge)
        end
    end
    outline:SetAlpha(0)
    return outline
end

function Status:UpdateTarget()
    local selected = self.owner.preview and self.owner.previewData.selected or false
    if not self.owner.preview and UnitIsUnit and UnitExists('target') then
        selected = UnitIsUnit(self.owner.unit, 'target')
    end
    self.targetBorder:SetAlpha(booleanAlpha(selected, 1, 0))
end

function Status:UpdateCenterIndicators()
    self.resurrection:SetShown(self.hasResurrection)
    -- Pass restricted resurrection state straight to the display APIs.
    local alpha = booleanAlpha(self.hasResurrection, 0, 1)
    self.summon:SetShown(self.hasSummon)
    self.summon:SetAlpha(alpha)
    self.ready:SetShown(self.readyState ~= nil and not self.hasSummon)
    self.ready:SetAlpha(alpha)
    self.raid:SetShown(self.hasRaidMarker and not self.hasSummon and not self.readyState)
    self.raid:SetAlpha(alpha)
end

function Status:UpdateRaidMarker()
    local index
    if self.owner.preview then
        index = self.owner.previewData.raidMarker
    elseif GetRaidTargetIndex and UnitExists(self.owner.unit) then
        index = GetRaidTargetIndex(self.owner.unit)
    end
    if isSecret(index) and self.raid.texture.SetSpriteSheetCell then
        self.raid.texture:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
        self.raid.texture:SetSpriteSheetCell(index, 4, 4)
        self.raid.tooltip = RAID_TARGET_ICON or 'Raid target marker'
        self.hasRaidMarker = true
    elseif known(index) and index >= 1 and index <= 8 and SetRaidTargetIconTexture then
        self.raid.texture:SetTexture('Interface\\TargetingFrame\\UI-RaidTargetingIcons')
        SetRaidTargetIconTexture(self.raid.texture, index)
        self.raid.tooltip = _G['RAID_TARGET_' .. index]
        self.hasRaidMarker = true
    else
        self.hasRaidMarker = false
    end
    self:UpdateCenterIndicators()
end

function Status:SetReadyCheck(state)
    self.readyState = state and READY_TEXTURES[state] and state or nil
    if state and READY_TEXTURES[state] then
        setArt(self.ready.texture, READY_ATLASES[state], READY_TEXTURES[state])
        self.ready.tooltip = state == 'ready' and (READY or 'Ready')
            or state == 'notready' and (NOT_READY or 'Not ready') or (READY_CHECK or 'Ready check')
    end
    self:UpdateCenterIndicators()
end

function Status:UpdateReadyCheck()
    if self.owner.preview then return end
    if self.readyExpires then return end
    if GetReadyCheckTimeLeft then
        local remaining = GetReadyCheckTimeLeft()
        if not isSecret(remaining) and remaining <= 0 then
            self:SetReadyCheck(nil)
            return
        end
    end
    local state = GetReadyCheckStatus and GetReadyCheckStatus(self.owner.unit)
    self:SetReadyCheck(known(state) or nil)
end

function Status:BeginReadyCheck()
    if self.owner.preview then return end
    self.readyExpires = nil
    self:UpdateReadyCheck()
end

function Status:FinishReadyCheck()
    if self.owner.preview then return end
    if self.readyState == 'waiting' then self:SetReadyCheck('notready') end
    self.readyExpires = GetTime() + 10
end

function Status:UpdatePvP()
    local faction, flagged, freeForAll
    if self.owner.preview then
        faction = self.owner.previewData.pvpFaction
        flagged = faction ~= nil
        freeForAll = self.owner.previewData.freeForAll
    else
        local unit = self.owner.unit
        faction = UnitFactionGroup and known(UnitFactionGroup(unit))
        flagged = UnitIsPVP and known(UnitIsPVP(unit))
        freeForAll = UnitIsPVPFreeForAll and known(UnitIsPVPFreeForAll(unit))
    end
    if freeForAll then
        setArt(self.pvp.texture, 'ui-hud-unitframe-player-pvp-ffaicon', 'Interface\\TargetingFrame\\UI-PVP-FFA')
    elseif flagged and (faction == 'Horde' or faction == 'Alliance') then
        setArt(self.pvp.texture, 'ui-hud-unitframe-player-pvp-' .. faction:lower() .. 'icon',
            'Interface\\TargetingFrame\\UI-PVP-' .. faction)
    else
        self.pvp:Hide()
        return
    end
    self.pvp.tooltip = PVP
    self.pvp:Show()
end

function Status:UpdatePresence()
    local unit = self.owner.unit
    local data = self.owner.preview and self.owner.previewData
    local resurrection = data and data.resurrection == true or false
    local summon = data and data.summon
    local phased = data and data.phased
    local phaseReason
    if not data and UnitExists(unit) then
        if UnitHasIncomingResurrection then resurrection = UnitHasIncomingResurrection(unit) end
        if C_IncomingSummon and C_IncomingSummon.HasIncomingSummon
            and known(C_IncomingSummon.HasIncomingSummon(unit)) then
            local state = known(C_IncomingSummon.IncomingSummonStatus(unit))
            local states = Enum and Enum.SummonStatus
            if states then
                summon = state == states.Pending and 'Pending' or state == states.Accepted and 'Accepted'
                    or state == states.Declined and 'Declined' or nil
            end
        end
        phaseReason = UnitPhaseReason and known(UnitPhaseReason(unit))
        phased = phaseReason ~= nil and phaseReason ~= false
    end
    self.hasResurrection = resurrection
    local hasSummon = summon == 'Pending' or summon == 'Accepted' or summon == 'Declined'
    if hasSummon then
        setArt(self.summon.texture, 'RaidFrame-Icon-Summon' .. summon, 'Interface\\Icons\\Spell_Shadow_Twilight')
        self.summon.tooltip = _G['INCOMING_SUMMON_TOOLTIP_SUMMON_' .. summon:upper()]
    end
    self.hasSummon = hasSummon
    self:UpdateCenterIndicators()
    setArt(self.phase.texture, 'RaidFrame-Icon-Phasing', 'Interface\\Icons\\Spell_Arcane_TeleportStormWind')
    self.phase.tooltip = PARTY_MEMBER_NOT_IN_PHASE or 'In another phase'
    if phaseReason and PartyUtil and PartyUtil.GetPhasedReasonString then
        self.phase.tooltip = PartyUtil.GetPhasedReasonString(phaseReason, unit)
    end
    if not data and not phased and UnitExists(unit) and UnitIsVisible then
        local visible = UnitIsVisible(unit)
        phased = not isSecret(visible) and not visible
        if phased then self.phase.tooltip = UNIT_OUT_OF_RANGE or 'Out of range' end
    end
    if not data and UnitInOtherParty and known(UnitInOtherParty(unit)) then
        phased = true
        setArt(self.phase.texture, 'RaidFrame-Icon-LFR', 'Interface\\Icons\\Spell_Arcane_TeleportStormWind')
        self.phase.tooltip = PARTY_IN_PUBLIC_GROUP_MESSAGE
    end
    self.phase:SetShown(phased == true)
end

function Status:UpdateRange()
    if self.owner.preview then
        self.owner:SetAlpha(self.owner.previewData.outOfRange and 0.45 or 1)
        return
    end
    if self.owner.unit == 'player' or not UnitExists(self.owner.unit) then
        self.owner:SetAlpha(1)
        return
    end
    local alpha = 1
    if UnitIsVisible and not known(UnitIsVisible(self.owner.unit)) then alpha = 0.45 end
    if UnitInRange then
        local inRange, checked = UnitInRange(self.owner.unit)
        alpha = booleanAlpha(checked, booleanAlpha(inRange, 1, 0.45), alpha)
    end
    self.owner:SetAlpha(alpha)
end

function Status:UpdateThreat()
    local threat
    if self.owner.preview then
        threat = self.owner.previewData.threat
    elseif UnitThreatSituation and UnitExists(self.owner.unit) then
        threat = UnitThreatSituation(self.owner.unit)
    end
    -- A curve can map restricted threat values directly to a display alpha.
    if isSecret(threat) then
        if self.threatCurve then
            self.threatBorder:SetAlpha(self.threatCurve:Evaluate(threat))
        else
            self.threatBorder:SetAlpha(0)
        end
    elseif self.threatCurve and threat ~= nil then
        self.threatBorder:SetAlpha(self.threatCurve:Evaluate(threat))
    else
        self.threatBorder:SetAlpha(known(threat) and threat >= 2 and 1 or 0)
    end
end

function Status:Refresh()
    self:UpdateTarget()
    self:UpdateRaidMarker()
    self:UpdatePvP()
    self:UpdatePresence()
    self:UpdateThreat()
    self:UpdateRange()
    if self.owner.preview then
        self.readyExpires = nil
        self:SetReadyCheck(self.owner.previewData.ready)
    else
        self:UpdateReadyCheck()
    end
end

addon.UnitFrameStatus = {}

function addon.UnitFrameStatus.Create(owner)
    local frame = CreateFrame('Frame', nil, owner)
    Mixin(frame, Status)
    frame.owner = owner
    frame:SetAllPoints(owner)
    frame:SetFrameLevel(owner.portraitGroup:GetFrameLevel() + 1)
    frame:EnableMouse(false)
    frame.hasRaidMarker = false
    frame.hasResurrection = false
    frame.hasSummon = false
    frame.raid = makeIcon(frame, -61, -12)
    frame.raid:ClearAllPoints()
    frame.raid:SetSize(40, 40)
    frame.raid:SetPoint('CENTER', owner.healthBarGroup, 'CENTER')
    frame.pvp = makeIcon(frame, -35, -12)
    frame.pvp:ClearAllPoints()
    frame.pvp:SetPoint('CENTER', owner.portrait, 'LEFT', -2, 0)
    frame.ready = makeIcon(frame, -61, -39)
    frame.ready:ClearAllPoints()
    frame.ready:SetSize(40, 40)
    frame.ready:SetPoint('CENTER', owner.healthBarGroup, 'CENTER')
    frame.resurrection = makeIcon(frame, -35, -39)
    frame.resurrection:ClearAllPoints()
    frame.resurrection:SetSize(60, 60)
    frame.resurrection:SetPoint('CENTER', owner.healthBarGroup, 'CENTER')
    frame.summon = makeIcon(frame, -9, -39)
    frame.summon:ClearAllPoints()
    frame.summon:SetSize(40, 40)
    frame.summon:SetPoint('CENTER', owner.healthBarGroup, 'CENTER')
    -- Keep the visual and tooltip order consistent with the center-icon priority.
    frame.raid:SetFrameLevel(frame:GetFrameLevel() + 1)
    frame.ready:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.summon:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.resurrection:SetFrameLevel(frame:GetFrameLevel() + 4)
    frame.phase = makeIcon(frame, -9, -65)
    frame.phase:ClearAllPoints()
    frame.phase:SetPoint('CENTER', owner.portrait, 'BOTTOM', 0, -2)
    setArt(frame.resurrection.texture, 'RaidFrame-Icon-Rez', 'Interface\\Icons\\Spell_Holy_Resurrection')
    frame.resurrection.tooltip = RESURRECT or 'Resurrection'
    setArt(frame.phase.texture, 'RaidFrame-Icon-Phasing', 'Interface\\Icons\\Spell_Arcane_TeleportStormWind')
    frame.targetBorder = makeOutline(frame, owner.healthBarGroup, owner.powerBarGroup, 3, 0.3, 0.85, 1)
    frame.threatBorder = makeOutline(frame, owner.healthBarGroup, owner.healthBarGroup, 1, 1, 0.15, 0.1)
    if C_CurveUtil and C_CurveUtil.CreateCurve and Enum and Enum.LuaCurveType then
        frame.threatCurve = C_CurveUtil.CreateCurve()
        frame.threatCurve:SetType(Enum.LuaCurveType.Step)
        frame.threatCurve:AddPoint(0, 0)
        frame.threatCurve:AddPoint(2, 1)
    end
    frame:SetScript('OnShow', function(self)
        if owner.status then self:Refresh() end
    end)
    frame:SetScript('OnHide', function(self)
        self.readyExpires = nil
        self:SetReadyCheck(nil)
    end)
    frame.elapsed = 0
    frame.presenceElapsed = 0
    frame:SetScript('OnUpdate', function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < 0.25 then return end
        self.elapsed = 0
        self:UpdateRange()
        if owner.preview then owner:UpdatePreviewCooldowns(GetTime()) end
        self.presenceElapsed = self.presenceElapsed + 0.25
        if self.presenceElapsed >= 1 then
            self.presenceElapsed = 0
            self:UpdatePresence()
        end
        if self.readyExpires and GetTime() >= self.readyExpires then
            self.readyExpires = nil
            self:SetReadyCheck(nil)
        end
    end)
    return frame
end
