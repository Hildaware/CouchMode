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
        local rpRace  = addon.TRPUtils.getRPRace(unit)
        local rpClass = addon.TRPUtils.getRPClass(unit)

        if rpRace or rpClass then
            -- TRP3 custom race/class: show as plain text, hide class icon.
            local parts = {}
            if rpRace then parts[#parts + 1] = rpRace end
            if rpClass then parts[#parts + 1] = rpClass end
            f.info:SetText(table.concat(parts, " "))
            local r, g, b = addon.TRPUtils.getRPColor(unit)
            if r then
                f.info:SetVertexColor(r, g, b)
            else
                local _, classToken = UnitClass(unit)
                local cc = classToken and RAID_CLASS_COLORS[classToken]
                if cc then f.info:SetVertexColor(cc.r, cc.g, cc.b) end
            end
            local rpIcon = addon.TRPUtils.getRPIcon(unit)
            if rpIcon then
                f.classIcon:SetTexture("Interface/icons/" .. rpIcon)
            else
                f.classIcon:SetTexture("Interface/AddOns/totalRP3/Resources/trp3logo")
            end
            f.classIcon:Show()
            f.classIconBorder:Show()
            f.hasInfo = true
        else
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
        end
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
    f.info = tips.makeFontString(overlay, tips.currentFont, { 0.6, 0.6, 0.6 })
    f.info:SetWordWrap(true)
    f.info:SetMaxLines(2)
end

function tips.layoutCharacteristics(f, y, height, fonts)
    f.info:SetFont(fonts.path, fonts.baseSize, fonts.flag)

    if f.hasInfo then
        y                    = y + 6
        height               = height + tips.LINE_GAP

        local borderShown    = f.classIconBorder:IsShown()

        -- Scale icon and border proportionally with TIP_W
        local scaledBorderSz = math.floor(tips.TIP_W * tips.ICON_X)
        local scaledIconSz   = math.floor(scaledBorderSz * (tips.ICON_SIZE - 2) / (tips.ICON_SIZE + 24))
        -- Effective height preserves the original compact-overlap ratio
        local scaledEffectH  = math.floor(scaledBorderSz * (tips.ICON_SIZE + 4) / (tips.ICON_SIZE + 24))

        if borderShown then
            f.classIconBorder:SetSize(scaledBorderSz, scaledBorderSz)
            f.classIcon:SetSize(scaledIconSz, scaledIconSz)
            f.classIconBorder:ClearAllPoints()
            f.classIconBorder:SetPoint("TOPLEFT", f, "TOPLEFT", -2, y)
        end

        -- Info width: available space from border's right edge (or left padding) to frame right
        local infoW = borderShown
            and (tips.TIP_W + 2 - scaledBorderSz - tips.PADDING)
            or (tips.TIP_W - tips.PADDING * 2)

        f.info:ClearAllPoints()
        f.info:SetWidth(math.max(infoW, 20))
        if borderShown then
            f.info:SetPoint("LEFT", f.classIconBorder, "RIGHT", 0, 0)
        else
            f.info:SetPoint("TOPLEFT", f, "TOPLEFT", tips.PADDING, y - 14)
        end

        -- Height: max of scaled border or 2 lines of wrapped text
        local textH = fonts.titleSize * 2 + tips.LINE_GAP
        local h     = math.max(borderShown and scaledEffectH or 0, textH, 1)
        y           = y - h - tips.LINE_GAP
        height      = height + h + tips.LINE_GAP
    end
    return y, height
end
