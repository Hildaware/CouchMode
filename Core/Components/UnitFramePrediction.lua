local addonName = ...
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)
local isSecret = addon.Utils.IsSecretValue
local Prediction = {}

local function makeBar(parent, r, g, b, alpha)
    local bar = CreateFrame('StatusBar', nil, parent)
    bar:SetStatusBarTexture('Interface\\Buttons\\WHITE8X8')
    bar:SetStatusBarColor(r, g, b, alpha)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetFrameLevel(parent:GetFrameLevel())
    bar:EnableMouse(false)
    return bar
end

local function amount(value)
    if isSecret(value) then return value end
    return value or 0
end

function Prediction:ApplyLayout()
    local width = self.owner.healthBarGroup:GetWidth()
    self.incoming:SetWidth(width)
    self.absorb:SetWidth(width)
    self.healAbsorb:SetWidth(width)
end

function Prediction:Clear()
    for _, bar in ipairs(self.bars) do
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
    end
    self.overAbsorb:SetAlpha(0)
end

function Prediction:Refresh()
    local owner = self.owner
    local health, maximum, incoming, absorb, healAbsorb, overAbsorb
    if owner.preview then
        local data = owner.previewData
        health, maximum = data.health or 92, 100
        incoming, absorb, healAbsorb = data.incomingHeal or 0, data.absorb or 0, data.healAbsorb or 0
        -- Match the calculator's ReducedByIncomingHeals processing on older clients.
        local reduction = math.min(incoming, healAbsorb)
        incoming, healAbsorb = incoming - reduction, healAbsorb - reduction
        incoming = math.min(incoming, maximum - health)
        overAbsorb = absorb > maximum - health - incoming
        absorb = math.min(absorb, maximum - health - incoming)
        healAbsorb = math.min(healAbsorb, health)
    elseif not UnitExists(owner.unit) then
        self:Clear()
        return
    elseif self.calculator then
        UnitGetDetailedHealPrediction(owner.unit, 'player', self.calculator)
        maximum = self.calculator:GetMaximumHealth()
        incoming = self.calculator:GetIncomingHeals()
        absorb, overAbsorb = self.calculator:GetDamageAbsorbs()
        healAbsorb = self.calculator:GetHealAbsorbs()
    else
        health, maximum = UnitHealth(owner.unit), UnitHealthMax(owner.unit)
        incoming = amount(UnitGetIncomingHeals and UnitGetIncomingHeals(owner.unit))
        absorb = amount(UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(owner.unit))
        healAbsorb = amount(UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(owner.unit))
        -- Never calculate with restricted values on clients without the calculator.
        if isSecret(health) or isSecret(maximum) or isSecret(incoming)
            or isSecret(absorb) or isSecret(healAbsorb) then
            self:Clear()
            return
        end
        local reduction = math.min(incoming, healAbsorb)
        incoming, healAbsorb = incoming - reduction, healAbsorb - reduction
        incoming = math.min(incoming, math.max(0, maximum - health))
        overAbsorb = absorb > maximum - health - incoming
        absorb = math.min(absorb, math.max(0, maximum - health - incoming))
        healAbsorb = math.min(healAbsorb, health)
    end
    if not isSecret(maximum) and maximum <= 0 then
        self:Clear()
        return
    end
    for _, bar in ipairs(self.bars) do bar:SetMinMaxValues(0, maximum) end
    -- Status bars do the sizing, including restricted values, entirely in the client.
    self.incoming:SetValue(incoming)
    self.absorb:SetValue(absorb)
    self.healAbsorb:SetValue(healAbsorb)
    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        self.overAbsorb:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(overAbsorb, 1, 0))
    else
        self.overAbsorb:SetAlpha(not isSecret(overAbsorb) and overAbsorb and 1 or 0)
    end
end

addon.UnitFramePrediction = {}

function addon.UnitFramePrediction.Create(owner)
    local frame = CreateFrame('Frame', nil, owner.healthBarGroup)
    Mixin(frame, Prediction)
    frame.owner = owner
    frame:SetAllPoints(owner.healthBarGroup)
    frame:SetFrameLevel(owner.healthBar:GetFrameLevel() + 1)
    frame:SetClipsChildren(true)
    frame:EnableMouse(false)
    local healthTexture = owner.healthBar:GetStatusBarTexture()
    frame.incoming = makeBar(frame, 0.2, 1, 0.55, 0.65)
    frame.incoming:SetPoint('TOPLEFT', healthTexture, 'TOPRIGHT')
    frame.incoming:SetPoint('BOTTOMLEFT', healthTexture, 'BOTTOMRIGHT')
    frame.absorb = makeBar(frame, 0.35, 0.8, 1, 0.8)
    local healTexture = frame.incoming:GetStatusBarTexture()
    frame.absorb:SetPoint('TOPLEFT', healTexture, 'TOPRIGHT')
    frame.absorb:SetPoint('BOTTOMLEFT', healTexture, 'BOTTOMRIGHT')
    frame.healAbsorb = makeBar(frame, 0.65, 0.15, 0.8, 0.85)
    frame.healAbsorb:SetReverseFill(true)
    frame.healAbsorb:SetPoint('TOPRIGHT', healthTexture, 'TOPRIGHT')
    frame.healAbsorb:SetPoint('BOTTOMRIGHT', healthTexture, 'BOTTOMRIGHT')
    frame.bars = { frame.incoming, frame.absorb, frame.healAbsorb }
    frame.overAbsorb = owner.healthBorderFrame:CreateTexture(nil, 'OVERLAY')
    frame.overAbsorb:SetColorTexture(0.35, 0.8, 1, 1)
    frame.overAbsorb:SetWidth(3)
    frame.overAbsorb:SetPoint('TOPRIGHT', owner.healthBarGroup, 'TOPRIGHT')
    frame.overAbsorb:SetPoint('BOTTOMRIGHT', owner.healthBarGroup, 'BOTTOMRIGHT')
    frame.overAbsorb:SetAlpha(0)
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction and Enum
        and Enum.UnitIncomingHealClampMode and Enum.UnitDamageAbsorbClampMode
        and Enum.UnitHealAbsorbClampMode and Enum.UnitHealAbsorbMode then
        frame.calculator = CreateUnitHealPredictionCalculator()
        frame.calculator:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
        frame.calculator:SetIncomingHealOverflowPercent(1)
        frame.calculator:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
        frame.calculator:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
        frame.calculator:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)
    end
    return frame
end
