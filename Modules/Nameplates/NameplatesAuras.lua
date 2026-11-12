local addon_name = ...

---@class CouchMode: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class NameplatesModule: AceModule
local nameplates = addon:GetModule('Nameplates')

local AURA_TIMER_INTERVAL = 0.1
local auraTimerElapsed = 0
local auraTimerFrame = CreateFrame("Frame")
auraTimerFrame:Hide()

local function auraAccessRestricted()
    return not addon.Utils.CanReadAuras()
end

local function startAuraTimers()
    auraTimerFrame:Show()
end

auraTimerFrame:SetScript("OnUpdate", function(self, elapsed)
    if auraAccessRestricted() then
        for _, f in pairs(nameplates.active) do
            if f.auras and not f.auras.container then nameplates.hideAuras(f) end
            if f.cc and not f.cc.container then nameplates.hideCC(f) end
        end
        self:Hide()
        return
    end
    auraTimerElapsed = auraTimerElapsed + elapsed
    if auraTimerElapsed < AURA_TIMER_INTERVAL then return end
    auraTimerElapsed = 0

    local hasTimers = false
    for _, f in pairs(nameplates.active) do
        if f.auras and f.auras:IsShown() then
            for i = 1, nameplates.AURA_MAX do
                local icon = f.auras.icons[i]
                if icon and icon:IsShown() and icon.duration then
                    hasTimers = true
                    icon.timer:SetFormattedText("%.0f", icon.duration:GetRemainingDuration())
                end
            end
        end
        if f.cc and f.cc:IsShown() and f.cc.duration then
            hasTimers = true
            f.cc.timer:SetFormattedText("%.0f", f.cc.duration:GetRemainingDuration())
        end
    end

    if not hasTimers then self:Hide() end
end)

function nameplates.buildAurasFrame(f)
    local AURA_MAX = nameplates.AURA_MAX
    local AURA_W = nameplates.AURA_W
    local AURA_H = nameplates.AURA_H
    local AURA_GAP = nameplates.AURA_GAP
    local BAR_W = nameplates.BAR_W

    if addon.AuraDisplay.IsSupported() then
        local function createRow(filter, maxCount, crowdControl)
            return addon.AuraDisplay.Create(f, {
                width = AURA_W, height = AURA_H, gap = AURA_GAP,
                maxCount = maxCount, filters = { filter }, timer = true,
                anchorWidth = crowdControl and AURA_W or BAR_W,
                innerBorder = true,
                showCount = not crowdControl,
                countOffsetX = 4, countOffsetY = -4,
                timerAnchor = crowdControl and 'BOTTOM' or 'CENTER',
                timerOffsetY = crowdControl and 1 or 0,
                font = nameplates.currentCastFont,
                shadow = function() return addon.db.profile.nameplates.shadowEnabled end,
            })
        end
        f.auras = createRow('HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY', AURA_MAX)
        f.auras.icons = {} -- legacy font/shadow loops must not inspect native buttons
        f.auras:SetPoint('BOTTOM', f.bar, 'TOP', 0, 12)
        f.cc = createRow('HARMFUL|CROWD_CONTROL|INCLUDE_NAME_PLATE_ONLY', 1, true)
        f.cc:SetPoint('LEFT', f.bar, 'RIGHT', 4, 0)
        return
    end

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

end

local AURA_MAX = nameplates.AURA_MAX
local AURA_FILTER = AuraUtil.CreateFilterString(
    AuraUtil.AuraFilters.Harmful,
    AuraUtil.AuraFilters.Player,
    AuraUtil.AuraFilters.IncludeNameplateOnly
)

local CC_FILTER = AuraUtil.CreateFilterString(
    AuraUtil.AuraFilters.Harmful,
    AuraUtil.AuraFilters.CrowdControl,
    AuraUtil.AuraFilters.IncludeNameplateOnly
)

function nameplates.refreshAuras(f, unitToken)
    if f.auras.container then
        addon.AuraDisplay.SetUnit(f.auras, unitToken)
        return
    end
    -- RequiresUnitAuraAccess errors before returning any data when restricted.
    if auraAccessRestricted() then
        nameplates.hideAuras(f)
        return
    end
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
            if icon.duration then
                icon.timer:SetFormattedText("%.0f", icon.duration:GetRemainingDuration())
                startAuraTimers()
            else
                icon.timer:SetText("")
            end
            local auraCountStr = C_UnitAuras.GetAuraApplicationDisplayCount(unitToken, aura.auraInstanceID, 2, 1000)
            icon.count:SetText(auraCountStr)
            icon:Show()
        end
    end
    for i = shown + 1, AURA_MAX do
        local icon = f.auras.icons[i]
        icon:Hide()
        icon.duration = nil
        icon.timer:SetText("")
    end
    f.auras:SetShown(shown > 0)
end

function nameplates.hideAuras(f)
    if f.auras.container then
        addon.AuraDisplay.SetUnit(f.auras, nil)
        return
    end
    for i = 1, AURA_MAX do
        local icon = f.auras.icons[i]
        icon:Hide()
        icon.duration = nil
        icon.timer:SetText("")
    end
    f.auras:Hide()
end

function nameplates.refreshCC(f, unitToken)
    if f.cc.container then
        addon.AuraDisplay.SetUnit(f.cc, unitToken)
        return
    end
    if auraAccessRestricted() then
        nameplates.hideCC(f)
        return
    end
    local auras = C_UnitAuras.GetUnitAuras(unitToken, CC_FILTER)
    local aura = auras and auras[1]
    if aura then
        f.cc.icon:SetTexture(aura.icon)
        f.cc.duration = C_UnitAuras.GetAuraDuration(unitToken, aura.auraInstanceID)
        f.cc.timer:SetShown(f.cc.duration ~= nil)
        if f.cc.duration then
            f.cc.timer:SetFormattedText("%.0f", f.cc.duration:GetRemainingDuration())
            startAuraTimers()
        else
            f.cc.timer:SetText("")
        end
        f.cc:Show()
        return
    end
    nameplates.hideCC(f)
end

function nameplates.hideCC(f)
    if f.cc.container then
        addon.AuraDisplay.SetUnit(f.cc, nil)
        return
    end
    f.cc:Hide()
    f.cc.duration = nil
    f.cc.timer:SetText("")
end
