local addon_name = ...

---@class ConsoleTools: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

function nameplates.buildCastFrame(f, overlay)
    local CAST_W = nameplates.CAST_W
    local CAST_H = nameplates.CAST_H
    local BAR_TEX = nameplates.BAR_TEX

    f.cast = CreateFrame("Frame", nil, f)
    f.cast:SetSize(CAST_W, CAST_H)
    f.cast:SetPoint("TOPRIGHT", f.bar, "BOTTOMRIGHT", -4, 2)
    f.cast:SetFrameLevel(f.bar:GetFrameLevel() + 5)
    f.cast:Hide()
    f.cast:SetAlpha(0.8)

    local castBg = f.cast:CreateTexture(nil, "BACKGROUND")
    castBg:SetTexture(BAR_TEX)
    castBg:SetAllPoints(f.cast)

    do
        local b = nameplates.addon.Utils.create_border_textures(f.cast, f.cast)
        nameplates.addon.Utils.apply_border_textures(f.cast, b, true, 1, 0, 0, 0, 1)
    end

    f.cast.fill = CreateFrame("StatusBar", nil, f.cast)
    f.cast.fill:SetAllPoints(f.cast)
    f.cast.fill:SetStatusBarTexture(BAR_TEX)
    f.cast.fill:GetStatusBarTexture():SetBlendMode("ADD")
    f.cast.fill:SetMinMaxValues(0, 1)
    f.cast.fill:SetValue(0)

    f.cast:SetScript("OnUpdate", function(self)
        if not self.endMS then return end
        local now  = GetTime() * 1000
        local span = self.endMS - self.startMS
        if span <= 0 then return end
        local pct = self.isChannel and math.max(0, (self.endMS - now) / span) or math.min(1, (now - self.startMS) / span)
        self.fill:SetValue(pct)
    end)

    f.cast.spellName = overlay:CreateFontString(nil, "OVERLAY")
    f.cast.spellName:SetFont(nameplates.currentCastFont())
    f.cast.spellName:SetPoint("CENTER", f.cast, "CENTER", 0, -1)
    f.cast.spellName:SetJustifyH("CENTER")
    f.cast.spellName:Hide()

    f.cast.shield = overlay:CreateTexture(nil, "OVERLAY")
    f.cast.shield:SetAtlas("UI-CastingBar-Shield", false)
    f.cast.shield:SetSize(CAST_H + 4, CAST_H + 4)
    f.cast.shield:SetPoint("RIGHT", f.cast, "LEFT", 10, 0)
    f.cast.shield:SetAlpha(0)
end

local function applycastStyle(f, isChannel, notInterruptible)
    f.cast.fill:SetStatusBarColor(
        C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0.6, isChannel and 0.1 or 0.9),
        C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0.6, isChannel and 0.9 or 0.6),
        C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 0.6, isChannel and 0.6 or 0.1)
    )
    f.cast.shield:SetAlpha(C_CurveUtil.EvaluateColorValueFromBoolean(notInterruptible, 1, 0))
end

function nameplates.hideCast(f)
    f.cast:Hide()
    f.cast.endMS = nil
    f.cast.spellName:SetText("")
    f.cast.spellName:Hide()
    f.cast.shield:SetAlpha(0)
end

function nameplates.updateCast(f, unitToken)
    local name, _, _, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unitToken)
    local isChannel = false
    if not name then
        name, _, _, startMS, endMS, _, notInterruptible = UnitChannelInfo(unitToken)
        isChannel = true
    end
    if not name then
        nameplates.hideCast(f)
        return
    end
    f.cast.startMS   = startMS
    f.cast.endMS     = endMS
    f.cast.isChannel = isChannel
    applycastStyle(f, isChannel, notInterruptible)
    f.cast.fill:SetValue(isChannel and 1 or 0)
    f.cast.spellName:SetText(name)
    f.cast.spellName:Show()
    f.cast:Show()
end
