local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

function nameplates.buildAurasFrame(f)
    local AURA_MAX = nameplates.AURA_MAX
    local AURA_W = nameplates.AURA_W
    local AURA_H = nameplates.AURA_H
    local AURA_GAP = nameplates.AURA_GAP
    local BAR_W = nameplates.BAR_W

    f.auras = CreateFrame("Frame", nil, f)
    f.auras:SetPoint("BOTTOM", f.bar, "TOP", 0, 12)
    f.auras:SetSize(BAR_W, AURA_H)
    f.auras:Hide()

    f.auras.icons = {}
    for i = 1, AURA_MAX do
        local icon = CreateFrame("Frame", nil, f.auras)
        icon:SetSize(AURA_W, AURA_H)
        if i == 1 then
            icon:SetPoint("TOPLEFT", f.auras, "TOPLEFT")
        else
            icon:SetPoint("LEFT", f.auras.icons[i - 1], "RIGHT", AURA_GAP, 0)
        end
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints(icon)
        -- Square icon cropped to fill AURA_W x AURA_H: show centre AURA_H/AURA_W of the
        -- trimmed texture vertically, leaving U unchanged and cropping V symmetrically.
        local vCrop = (1 - AURA_H / AURA_W) / 2 * 0.84 -- 0.84 = trimmed range (0.92-0.08)
        icon.tex:SetTexCoord(0.08, 0.92, 0.08 + vCrop, 0.92 - vCrop)
        addon.Utils.apply_border_textures(icon, addon.Utils.create_border_textures(icon, icon), true, 1, 0, 0, 0, 1)
        icon.count = icon:CreateFontString(nil, "OVERLAY")
        icon.count:SetFont(nameplates.currentCastFont())
        icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4)
        icon.count:SetJustifyH("RIGHT")
        icon.timer = icon:CreateFontString(nil, "OVERLAY")
        icon.timer:SetFont(nameplates.currentCastFont())
        icon.timer:SetPoint("CENTER", icon, "CENTER")
        icon.timer:SetJustifyH("CENTER")
        if addon.db.profile.nameplates.shadowEnabled then
            addon.Utils.apply_font_shadow(icon.count)
            addon.Utils.apply_font_shadow(icon.timer)
        end
        icon:Hide()
        f.auras.icons[i] = icon
    end

    f.auras:SetScript("OnUpdate", function(self)
        for i = 1, AURA_MAX do
            local icon = self.icons[i]
            if icon:IsShown() and icon.duration then
                icon.timer:SetText(string.format("%.0f", icon.duration:GetRemainingDuration()))
            end
        end
    end)

    f.cc = CreateFrame("Frame", nil, f)
    f.cc:SetSize(AURA_W, AURA_H)
    f.cc:SetPoint("LEFT", f.bar, "RIGHT", 4, 0)
    f.cc:Hide()

    f.cc.icon = f.cc:CreateTexture(nil, "ARTWORK")
    f.cc.icon:SetAllPoints(f.cc)
    local vCropCC = (1 - AURA_H / AURA_W) / 2 * 0.84
    f.cc.icon:SetTexCoord(0.08, 0.92, 0.08 + vCropCC, 0.92 - vCropCC)
    addon.Utils.apply_border_textures(f.cc, addon.Utils.create_border_textures(f.cc, f.cc), true, 1, 0, 0, 0, 1)

    f.cc.timer = f.cc:CreateFontString(nil, "OVERLAY")
    f.cc.timer:SetFont(nameplates.currentCastFont())
    f.cc.timer:SetPoint("BOTTOM", f.cc, "BOTTOM", 0, 1)
    f.cc.timer:SetJustifyH("CENTER")
    f.cc.timer:Hide()
    if addon.db.profile.nameplates.shadowEnabled then
        addon.Utils.apply_font_shadow(f.cc.timer)
    end

    f.cc:SetScript("OnUpdate", function(self)
        if self.duration then
            self.timer:SetText(string.format("%.0f", self.duration:GetRemainingDuration()))
        end
    end)
end

local AURA_MAX = nameplates.AURA_MAX
local AURA_FILTER = AuraUtil.CreateFilterString(
    AuraUtil.AuraFilters.Harmful,
    AuraUtil.AuraFilters.Player,
    AuraUtil.AuraFilters.IncludeNameplateOnly
)

local CC_FILTER = AuraUtil.CreateFilterString(AuraUtil.AuraFilters.Harmful, AuraUtil.AuraFilters.CrowdControl)

function nameplates.refreshAuras(f, unitToken)
    local auras = C_UnitAuras.GetUnitAuras(unitToken, AURA_FILTER)
    local shown = 0
    if auras then
        for _, aura in ipairs(auras) do
            if shown >= AURA_MAX then break end
            shown = shown + 1
            local icon = f.auras.icons[shown]
            icon.tex:SetTexture(aura.icon)
            icon.duration = C_UnitAuras.GetAuraDuration(unitToken, aura.auraInstanceID)
            icon.timer:SetShown(icon.duration ~= nil)
            local auraCountStr = C_UnitAuras.GetAuraApplicationDisplayCount(unitToken, aura.auraInstanceID, 2, 1000)
            icon.count:SetText(auraCountStr)
            icon:Show()
        end
    end
    for i = shown + 1, AURA_MAX do f.auras.icons[i]:Hide() end
    f.auras:SetShown(shown > 0)
end

function nameplates.hideAuras(f)
    for i = 1, AURA_MAX do f.auras.icons[i]:Hide() end
    f.auras:Hide()
end

function nameplates.refreshCC(f, unitToken)
    local auras = C_UnitAuras.GetUnitAuras(unitToken, CC_FILTER)
    local aura = auras and auras[1]
    if aura then
        f.cc.icon:SetTexture(aura.icon)
        f.cc.duration = C_UnitAuras.GetAuraDuration(unitToken, aura.auraInstanceID)
        f.cc.timer:SetShown(f.cc.duration ~= nil)
        f.cc:Show()
        return
    end
    nameplates.hideCC(f)
end

function nameplates.hideCC(f)
    f.cc:Hide()
    f.cc.duration = nil
end
