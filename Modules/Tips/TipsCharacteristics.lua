local addon_name       = ...

---@class CouchMode: AceAddon
local addon            = LibStub('AceAddon-3.0'):GetAddon(addon_name)

---@class TipsModule: AceModule
local tips             = addon:GetModule('Tips')

tips.CREATURE_TYPE_SET = {
    ["Beast"] = true,
    ["Dragonkin"] = true,
    ["Demon"] = true,
    ["Elemental"] = true,
    ["Giant"] = true,
    ["Undead"] = true,
    ["Humanoid"] = true,
    ["Critter"] = true,
    ["Mechanical"] = true,
    ["Not specified"] = true,
    ["Totem"] = true,
    ["Non-combat Pet"] = true,
    ["Gas Cloud"] = true,
    ["Wild Pet"] = true,
    ["Aberration"] = true,
}

function tips.populateCharacteristics(f, unit)
    local isPlayer = UnitIsPlayer(unit)
    if isPlayer then
        local className, classToken = UnitClass(unit)
        local cc                    = classToken and RAID_CLASS_COLORS[classToken]
        local specInfo              = addon.TipsUtils and addon.TipsUtils.getSpecData(unit)
        if cc then f.info:SetVertexColor(cc.r, cc.g, cc.b) end
        f.classIconBorder:Show()
        if specInfo then
            f.classIcon:SetTexture(specInfo.specIcon)
            f.info:SetText(specInfo.specName .. " " .. (className or ""))
        else
            f.classIcon:SetAtlas("BfAMission-Icon-Normal")
            f.info:SetText(className or "")
        end
        f.classIcon:Show()
        f.hasInfo = (className ~= nil) or (specInfo ~= nil)
    else
        f.classIconBorder:Hide()
        f.classIcon:Hide()
        local creatureType = UnitCreatureType(unit)
        f.info:SetText(creatureType or "")
        f.info:SetTextColor(1, 1, 1)
        f.hasInfo = (creatureType ~= nil)
    end
end

function tips.buildCharacteristics(f, overlay, subfont)
    -- Class / spec icon (players only)
    f.classIcon = overlay:CreateTexture(nil, "OVERLAY", nil, 0)
    f.classIcon:SetSize(tips.ICON_SIZE - 2, tips.ICON_SIZE - 2)
    f.classIcon:Hide()

    f.classIconBorder = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    f.classIconBorder:SetAtlas("Relic-Fire-TraitBG")
    f.classIconBorder:SetSize(tips.ICON_SIZE + 24, tips.ICON_SIZE + 24)
    f.classIconBorder:Hide()
    f.classIcon:SetPoint("CENTER", f.classIconBorder, "CENTER")

    local mask = overlay:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(f.classIcon)
    f.classIcon:AddMaskTexture(mask)

    -- Info line: "Assassination Rogue" (players) or creature type (NPCs)
    f.info = tips.makeFontString(overlay, subfont, { 0.6, 0.6, 0.6 })
end

function tips.layoutCharacteristics(f, y, height, fonts)
    f.info:SetFont(fonts.path, fonts.titleSize, fonts.flag)

    if f.hasInfo then
        y                 = y + 6
        height            = height + tips.LINE_GAP

        local borderShown = f.classIconBorder:IsShown()
        local borderW     = tips.ICON_SIZE + 4
        local xText       = tips.PADDING + (borderShown and (borderW + tips.ICON_GAP) or 0)

        if borderShown then
            f.classIconBorder:ClearAllPoints()
            f.classIconBorder:SetPoint("TOPLEFT", f, "TOPLEFT", -2, y)
        end

        f.info:ClearAllPoints()
        f.info:SetWidth(tips.TIP_W - xText - tips.PADDING)
        if borderShown then
            f.info:SetPoint("LEFT", f.classIconBorder, "RIGHT", 0, 0)
        else
            f.info:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING, y - 14)
        end

        local h = math.max(borderShown and borderW or 0, fonts.titleSize, 1)
        y       = y - h - tips.LINE_GAP
        height  = height + h + tips.LINE_GAP
    end
    return y, height
end
